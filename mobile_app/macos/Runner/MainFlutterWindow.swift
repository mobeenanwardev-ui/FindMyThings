import Cocoa
import FlutterMacOS
import Vision

class MainFlutterWindow: NSWindow {
  private let trackerQueue = DispatchQueue(label: "com.findmythings.vision-tracker")
  private let trackerChannelName = "com.findmythings/object_tracker"
  private var sequenceHandler = VNSequenceRequestHandler()
  private var trackingRequest: VNTrackObjectRequest?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let trackerChannel = FlutterMethodChannel(
      name: trackerChannelName,
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    trackerChannel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "TRACKER_UNAVAILABLE", message: "The tracker is unavailable.", details: nil))
        return
      }
      switch call.method {
      case "startTracking":
        guard
          let args = call.arguments as? [String: Any],
          let image = args["image"] as? FlutterStandardTypedData,
          let x = (args["x"] as? NSNumber)?.doubleValue,
          let y = (args["y"] as? NSNumber)?.doubleValue,
          let width = (args["width"] as? NSNumber)?.doubleValue,
          let height = (args["height"] as? NSNumber)?.doubleValue
        else {
          result(FlutterError(code: "INVALID_ARGUMENTS", message: "A frame and normalized bounding box are required.", details: nil))
          return
        }
        self.trackerQueue.async {
          do {
            let rect = CGRect(x: x, y: 1.0 - y - height, width: width, height: height)
            let observation = VNDetectedObjectObservation(boundingBox: rect)
            let request = VNTrackObjectRequest(detectedObjectObservation: observation)
            request.trackingLevel = .accurate
            self.trackingRequest = request
            self.sequenceHandler = VNSequenceRequestHandler()
            DispatchQueue.main.async { result(["started": true]) }
          }
        }

      case "trackFrame":
        guard
          let args = call.arguments as? [String: Any],
          let image = args["image"] as? FlutterStandardTypedData
        else {
          result(FlutterError(code: "INVALID_ARGUMENTS", message: "A camera frame is required.", details: nil))
          return
        }
        self.trackerQueue.async {
          guard let request = self.trackingRequest else {
            DispatchQueue.main.async { result(["tracked": false, "reason": "not_started"]) }
            return
          }
          do {
            try self.sequenceHandler.perform([request], onImageData: image.data, orientation: .up)
            guard let observation = request.results?.first as? VNDetectedObjectObservation,
                  observation.confidence >= 0.25 else {
              self.trackingRequest = nil
              DispatchQueue.main.async { result(["tracked": false, "reason": "low_confidence"]) }
              return
            }
            request.inputObservation = observation
            let box = observation.boundingBox
            let payload: [String: Any] = [
              "tracked": true,
              "confidence": observation.confidence,
              "x": box.minX,
              "y": 1.0 - box.maxY,
              "width": box.width,
              "height": box.height
            ]
            DispatchQueue.main.async { result(payload) }
          } catch {
            self.trackingRequest = nil
            DispatchQueue.main.async {
              result(["tracked": false, "reason": error.localizedDescription])
            }
          }
        }

      case "resetTracking":
        self.trackerQueue.async {
          self.trackingRequest = nil
          self.sequenceHandler = VNSequenceRequestHandler()
          DispatchQueue.main.async { result(nil) }
        }

      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}
