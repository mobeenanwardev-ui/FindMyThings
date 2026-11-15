# FindMyThings — System Architecture

## 1. Purpose and scope

FindMyThings is a visual-search prototype for personal belongings. A user registers an item with a name, category and reference photograph, then opens a live camera finder. The system detects candidate objects in camera frames and compares their visual appearance with the saved reference image(s).

The core design separates two questions:

- **Where are the candidate objects?** Object detection (YOLOv8n) estimates bounding boxes and category confidence.
- **Which candidate resembles the user's item?** CLIP produces image embeddings; cosine similarity compares a candidate crop with the saved reference-photo embeddings.

This is a prototype architecture. The repository currently has two related but separate implementations: an earlier Python/OpenCV proof of concept at the repository root, and the more recent Flutter + Core ML desktop application in mobile_app/.

## 2. System context

    flowchart LR
      User[User] --> UI[Flutter application]
      UI --> Inventory[Local inventory and photos]
      UI --> Camera[macOS camera stream]
      Camera --> Pipeline[On-device vision pipeline]
      Pipeline --> UI
      Inventory --> Pipeline
      Pipeline --> Vision[Apple Vision tracker]
      Vision --> UI

The mobile application does not depend on a remote API for its current inventory or inference workflow. Item metadata and reference images are kept on the device, while the YOLO and CLIP models are bundled as Core ML assets.

## 3. High-level component architecture

    flowchart TB
      subgraph App[Flutter application — mobile_app]
        Screens[UI and navigation]
        Inventory[Belonging model and inventory state]
        Persistence[JSON + local image files]
        Camera[CameraFinderPage]
        Preprocess[Frame preprocessing isolate]
        AIS[AiModelService]
        Overlay[Detection overlay and scan status]
        Screens --> Inventory
        Inventory <--> Persistence
        Screens --> Camera
        Camera --> Preprocess
        Preprocess --> AIS
        AIS --> Overlay
        Overlay --> Camera
      end

      subgraph Models[Bundled Core ML models]
        YOLO[YOLOv8n]
        CLIP[CLIP image encoder]
      end

      subgraph Native[macOS native layer]
        Bridge[Flutter MethodChannel]
        VN[Apple Vision object tracker]
        Bridge --> VN
      end

      AIS --> YOLO
      AIS --> CLIP
      Camera <--> Bridge

      subgraph Legacy[Python proof of concept — repository root]
        Entry[main.py]
        Capture[src/camera.py]
        Detect[src/detector.py]
        Match[src/matcher.py]
        Config[src/config.py]
        Entry --> Capture
        Entry --> Detect
        Entry --> Match
        Entry --> Config
      end

The Python proof of concept is not a service called by Flutter. It is a separate executable experiment that demonstrates the detection-plus-embedding-matching concept with desktop Python libraries.

## 4. Flutter application components

### 4.1 Presentation and application flow — mobile_app/lib/main.dart

The main Flutter file currently owns the UI and application workflow:

- FindMyThingsApp configures the Material 3 application theme.
- Belonging represents an inventory item, including its ID, name, category, creation time and reference-photo paths.
- HomePage loads, searches, adds, edits and deletes belongings.
- ItemDialog collects item metadata and a reference photo.
- CameraFinderPage manages the camera stream, inference cadence, match state, tracking hand-off and detection overlay.

The inventory serializes item metadata to belongings.json in the application documents directory. Reference images are copied into a belonging_photos subdirectory. The photos field supports multiple reference paths while retaining compatibility with the older single-photo representation.

### 4.2 Persistence boundary

The current persistence design is intentionally local and simple:

- Metadata: JSON serialization of the inventory.
- Images: files copied into application-private documents storage.
- No account, remote database, or synchronization service is implemented.

This keeps the prototype usable offline and avoids uploading personal belongings photographs to a server. It also means data is device-local and is not synchronized between devices.

### 4.3 Frame preprocessing

Camera frames are converted to a model input in a worker isolate using Flutter compute:

1. Camera pixel data is transferred to the isolate using TransferableTypedData.
2. The source aspect ratio is preserved.
3. The image is resized to fit inside a 640 × 640 square.
4. Black letterbox padding fills the remaining area.
5. The result is JPEG-encoded and written to a temporary file for model inference.

Letterboxing avoids distorting objects by stretching a non-square camera frame. The coordinate transforms in the finder convert model-space boxes back to the original camera preview.

### 4.4 AI model service — mobile_app/lib/ai_model_service.dart

AiModelService encapsulates Core ML model loading and inference.

**YOLOv8n object detection**

- Loads assets/models/yolov8n.mlpackage through the Core ML Flutter integration.
- Predicts candidate boxes from a 640 × 640 image.
- Decodes the expected output tensor with shape [1, 84, 8400].
- Selects the highest-scoring class for each candidate and applies a confidence threshold.
- Sorts candidates by confidence and applies class-aware non-maximum suppression (IoU threshold 0.40), returning up to five detections.

**CLIP visual embedding**

- Loads assets/models/clip_image_encoder.mlpackage.
- Resizes decoded images to 224 × 224.
- Normalizes RGB channels using the CLIP image mean and standard deviation.
- Passes a tensor with shape [1, 3, 224, 224] to the image encoder.
- Returns the embedding vector from the model output.

Reference embeddings are cached by image path for reuse during the camera session.

**Candidate matching**

- The current implementation scores the highest-confidence candidate region.
- It crops that region from the processed frame and encodes it with CLIP.
- It compares the candidate embedding with each available reference-photo embedding.
- The highest cosine similarity is assigned to the candidate.
- A candidate is marked as a match when similarity meets the configured matching threshold (currently 0.72 in matchDetectedRegions).

Cosine similarity is:

    similarity(a, b) = (a · b) / (||a|| × ||b||)

The score is a similarity measure, not a calibrated probability that the object is the same physical item.

### 4.5 Native tracking — mobile_app/macos/Runner/MainFlutterWindow.swift

After the Flutter pipeline confirms a candidate, it sends the encoded frame and normalized bounding box to a native method channel named com.findmythings/object_tracker.

The macOS Swift layer uses Apple Vision sequence tracking (including VNSequenceRequestHandler) to follow the target in intervening frames. The Flutter layer periodically returns to YOLO + CLIP detection/matching to re-anchor the tracker and reduce accumulated drift.

Tracking is an optimization for temporal continuity; it does not replace visual re-identification. If tracking fails or a periodic detector pass cannot reconfirm the target, the application falls back to detection and matching.

## 5. End-to-end live search sequence

    sequenceDiagram
      actor User
      participant UI as Flutter UI
      participant Store as Local inventory
      participant Cam as macOS camera
      participant Prep as Preprocessing isolate
      participant YOLO as Core ML YOLO
      participant CLIP as Core ML CLIP
      participant Vision as Apple Vision

      User->>UI: Register belonging + reference photo
      UI->>Store: Save JSON metadata + local photo
      User->>UI: Select Find it
      UI->>Cam: Start image stream
      Cam->>Prep: Camera frame
      Prep->>Prep: Letterbox to 640x640
      Prep->>YOLO: Prepared frame
      YOLO-->>UI: Candidate boxes + class scores
      UI->>CLIP: Crop best candidate + reference photos
      CLIP-->>UI: Embedding vectors
      UI->>UI: Cosine similarity + threshold
      alt Candidate passes threshold
        UI->>Vision: Start tracking matched bounding box
        loop Tracking interval
          Cam->>Vision: New frame
          Vision-->>UI: Updated target box
        end
        UI->>YOLO: Periodic re-detection
        YOLO-->>UI: Re-anchoring candidates
        UI->>CLIP: Re-check candidate appearance
        CLIP-->>UI: Updated similarity
      else No candidate passes threshold
        UI->>UI: Continue scanning
      end
      UI-->>User: Live boxes and scan status

## 6. Earlier Python proof of concept

The root-level Python implementation demonstrates the same high-level approach with a different runtime:

| Module | Responsibility |
|---|---|
| main.py | Loads the reference image and models, runs the camera loop, enhances frames and renders match feedback |
| src/camera.py | Wraps OpenCV camera start/read/stop operations |
| src/detector.py | Runs Ultralytics YOLO tracking with persistent ByteTrack IDs |
| src/matcher.py | Extracts normalized CLIP image embeddings and calculates cosine similarity |
| src/config.py | Stores camera, detector, CLIP, similarity and CLAHE settings |

The Python flow uses OpenCV CLAHE brightness/contrast enhancement, YOLO tracking, and periodic CLIP scoring per tracked object. It expects wallet_reference.jpg at the repository root. It is a research/prototyping path, not the runtime architecture of the Flutter app.

## 7. Important design decisions

### Detection and visual matching are separate stages

A generic detector can find known object categories, but it does not inherently know which specific backpack, wallet or pair of keys belongs to the user. The architecture therefore uses YOLO to propose regions and CLIP to compare their visual representations with the user's reference image.

### Multiple reference photos

A single photograph may not capture an item's appearance from every angle. The application can store multiple reference-photo paths, cache their embeddings, and use the best similarity score across the available references. The current item editor's photo picker interaction should still be treated as a single-photo selection per action; multiple references can be accumulated only where the UI workflow supports it.

### On-device inference

Bundled Core ML models avoid a network round trip for the inference path and keep reference photos on-device. This improves privacy and makes the inference architecture independent of network availability, while placing model size, memory use and device performance constraints on the client.

### Tracking between inference passes

Running full detection and embedding comparison on every camera frame is expensive. Apple Vision tracking provides a lighter way to update a confirmed object's location between periodic detector/matcher passes. Periodic re-detection is retained because trackers can drift or lose the object.

### Worker-isolate preprocessing

Pixel conversion and JPEG encoding can be CPU-intensive. Moving this work away from Flutter's UI isolate helps keep the interface responsive while frames are prepared for inference.

## 8. Platform support and current constraints

**Current camera and tracking implementation: macOS prototype.**

The Flutter dependency list includes camera_macos, and the native tracking bridge is in mobile_app/macos/Runner/MainFlutterWindow.swift. These are macOS-specific integrations. The existence of a Flutter application or Core ML model assets does not, by itself, mean the camera finder is ready for iPhone.

To deliver an iOS build, the project still needs:

1. An iOS-compatible camera stream implementation and lifecycle handling.
2. An iOS native Vision tracking bridge, or a verified cross-platform abstraction.
3. iOS camera usage descriptions and permission handling.
4. Core ML model loading and inference validated on supported iPhone hardware.
5. iOS build configuration, signing, and physical-device testing.
6. Performance, thermal, battery and memory measurements on the target device.

The current Core ML integration checks for macOS 15 or later in its runtime guard. That platform check and model-loading behavior must be reviewed and adapted for the iOS target rather than assumed to be portable unchanged.

## 9. Quality, evaluation and observability

No formal accuracy or latency benchmark is currently published in this repository. Before presenting this as a reliable product, build an evaluation set that includes:

- Multiple physical instances of the same generic category.
- Several reference photos per item, including different viewpoints.
- Similar-looking distractor objects.
- Different distances, backgrounds, lighting levels and partial occlusion.
- Negative scenes in which the target item is absent.

Recommended metrics:

| Metric | Why it matters |
|---|---|
| Precision / false-positive rate | How often the app incorrectly says an unrelated object is the target |
| Recall | How often the target is successfully found when visible |
| Time to first match | User-perceived search speed |
| Detection and embedding latency | Cost of each inference stage |
| Tracking loss / re-acquisition rate | Stability of the live bounding box |
| Memory, battery and thermal behavior | Suitability for sustained mobile camera use |

The similarity threshold should be selected from validation data and documented with the evaluation protocol. A raw cosine-similarity threshold is not a universal confidence score.

## 10. Security and privacy considerations

- Keep reference images and inventory data in application-private storage.
- Do not log image bytes, full file contents, or sensitive user inventory details.
- Make camera activation visible and explain why camera permission is needed.
- Define deletion behavior for both item metadata and its stored image files.
- If cloud synchronization is added in the future, document encryption, retention, access control and deletion behavior before shipping it.

## 11. Roadmap

### Near term
- Finish the iOS camera and Vision integration.
- Validate model loading and inference on a physical iPhone.
- Add automated tests around image preprocessing, coordinate mapping, NMS, cosine similarity and persistence.
- Fix and verify the reference-photo editing workflow end to end.

### Next
- Establish a repeatable accuracy and latency benchmark.
- Calibrate the match threshold with positive and negative examples.
- Improve lifecycle handling, cancellation, memory cleanup and camera error recovery.
- Separate UI, persistence, camera orchestration and inference into independently testable modules.

### Later
- Evaluate model quantization and inference scheduling for battery efficiency.
- Explore robust re-identification after an object leaves and re-enters the camera view.
- Consider encrypted backup/sync only if the product needs multi-device continuity.

## 12. Source map

- Flutter UI and camera workflow: mobile_app/lib/main.dart
- Core ML inference and embedding matching: mobile_app/lib/ai_model_service.dart
- macOS Vision tracking bridge: mobile_app/macos/Runner/MainFlutterWindow.swift
- Model assets and Flutter dependencies: mobile_app/pubspec.yaml
- Python entry point: main.py
- Python camera: src/camera.py
- Python detector: src/detector.py
- Python matcher: src/matcher.py
- Python configuration: src/config.py
