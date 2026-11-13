import 'dart:io';
import 'dart:math' as math;
import 'package:core_ml/core_ml.dart';
import 'package:image/image.dart' as img;

class ObjectDetection {
  const ObjectDetection({
    required this.label,
    required this.confidence,
    required this.centerX,
    required this.centerY,
    required this.width,
    required this.height,
    this.similarity,
    this.isMatch = false,
  });

  final String label;
  final double confidence;
  final double centerX;
  final double centerY;
  final double width;
  final double height;
  final double? similarity;
  final bool isMatch;
}
class ImageMatch {
  const ImageMatch({required this.similarity});
  final double similarity;
}

class AiModelService {
  MLModel? _yoloModel;
  MLModel? _clipModel;
  final Map<String, List<double>> _cachedReferenceEmbeddings = {};

  Future<MLModel> _loadYolo() async {
    if (_yoloModel != null) return _yoloModel!;
    if (!await CoreML.isSupported()) throw StateError('Core ML requires macOS 15 or later.');
    _yoloModel = await MLModel.loadAsset(
      yoloAsset,
      configuration: const MLModelConfiguration(computeUnits: MLComputeUnits.cpuAndNeuralEngine),
    );
    return _yoloModel!;
  }

  Future<MLModel> _loadClip() async {
    if (_clipModel != null) return _clipModel!;
    if (!await CoreML.isSupported()) throw StateError('Core ML requires macOS 15 or later.');
    _clipModel = await MLModel.loadAsset(
      clipAsset,
      configuration: const MLModelConfiguration(computeUnits: MLComputeUnits.cpuAndNeuralEngine),
    );
    return _clipModel!;
  }

  Future<void> dispose() async {
    await _yoloModel?.dispose();
    await _clipModel?.dispose();
    _yoloModel = null;
    _clipModel = null;
    _cachedReferenceEmbeddings.clear();
  }

  static const yoloAsset = 'assets/models/yolov8n.mlpackage';
  static const clipAsset = 'assets/models/clip_image_encoder.mlpackage';

  static const _labels = <String>[
    'person', 'bicycle', 'car', 'motorcycle', 'airplane', 'bus', 'train',
    'truck', 'boat', 'traffic light', 'fire hydrant', 'stop sign',
    'parking meter', 'bench', 'bird', 'cat', 'dog', 'horse', 'sheep',
    'cow', 'elephant', 'bear', 'zebra', 'giraffe', 'backpack', 'umbrella',
    'handbag', 'tie', 'suitcase', 'frisbee', 'skis', 'snowboard',
    'sports ball', 'kite', 'baseball bat', 'baseball glove', 'skateboard',
    'surfboard', 'tennis racket', 'bottle', 'wine glass', 'cup', 'fork',
    'knife', 'spoon', 'bowl', 'banana', 'apple', 'sandwich', 'orange',
    'broccoli', 'carrot', 'hot dog', 'pizza', 'donut', 'cake', 'chair',
    'couch', 'potted plant', 'bed', 'dining table', 'toilet', 'tv',
    'laptop', 'mouse', 'remote', 'keyboard', 'cell phone', 'microwave',
    'oven', 'toaster', 'sink', 'refrigerator', 'book', 'clock', 'vase',
    'scissors', 'teddy bear', 'hair drier', 'toothbrush',
  ];

  Future<String> verifyInstalledModels() async {
    if (!await CoreML.isSupported()) {
      throw StateError('Core ML requires macOS 15 or later.');
    }
    final yolo = await _inspectAndDispose(yoloAsset, 'YOLOv8n');
    final clip = await _inspectAndDispose(clipAsset, 'CLIP image encoder');
    return '$yolo\n\n$clip';
  }

  Future<String> _inspectAndDispose(String asset, String label) async {
    MLModel? model;
    try {
      model = await MLModel.loadAsset(
        asset,
        configuration: const MLModelConfiguration(
          computeUnits: MLComputeUnits.cpuAndNeuralEngine,
        ),
      );
      return '$label loaded successfully.\n${model.modelDescription}';
    } finally {
      await model?.dispose();
    }
  }

  Future<List<ObjectDetection>> detectObjects(String imagePath) async {
    final model = await _loadYolo();
    final prediction = await model.predict({'image': ImageInput.file(imagePath)});
    final output = prediction.multiArray('var_911');
    final shape = output.shape;
    if (shape.length != 3 || shape[1] != 84 || shape[2] != 8400) {
      throw StateError('Unexpected YOLO output shape: $shape');
    }
    final values = output.toDoubleList();
    const candidates = 8400;
    final detections = <ObjectDetection>[];
    for (var i = 0; i < candidates; i++) {
      var bestClass = 0;
      var bestScore = 0.0;
      for (var c = 0; c < 80; c++) {
        final score = values[(4 + c) * candidates + i];
        if (score > bestScore) { bestScore = score; bestClass = c; }
      }
      if (bestScore < 0.25) continue;
      detections.add(ObjectDetection(
        label: _labels[bestClass],
        confidence: bestScore,
        centerX: values[i] / 640.0,
        centerY: values[candidates + i] / 640.0,
        width: values[2 * candidates + i] / 640.0,
        height: values[3 * candidates + i] / 640.0,
      ));
    }
    // Class-aware non-maximum suppression removes duplicate and oversized
    // overlapping proposals around the same physical object.
    detections.sort((a, b) => b.confidence.compareTo(a.confidence));
    final selected = <ObjectDetection>[];
    for (final candidate in detections) {
      final overlaps = selected.any((kept) =>
          kept.label == candidate.label && _intersectionOverUnion(kept, candidate) > 0.40);
      if (!overlaps) selected.add(candidate);
      if (selected.length == 5) break;
    }
    return selected;
  }

  double _intersectionOverUnion(ObjectDetection a, ObjectDetection b) {
    final aLeft = a.centerX - a.width / 2;
    final aTop = a.centerY - a.height / 2;
    final aRight = a.centerX + a.width / 2;
    final aBottom = a.centerY + a.height / 2;
    final bLeft = b.centerX - b.width / 2;
    final bTop = b.centerY - b.height / 2;
    final bRight = b.centerX + b.width / 2;
    final bBottom = b.centerY + b.height / 2;
    final intersectionWidth = math.max(0.0, math.min(aRight, bRight) - math.max(aLeft, bLeft));
    final intersectionHeight = math.max(0.0, math.min(aBottom, bBottom) - math.max(aTop, bTop));
    final intersection = intersectionWidth * intersectionHeight;
    final union = a.width * a.height + b.width * b.height - intersection;
    return union <= 0 ? 0 : intersection / union;
  }

  Future<List<ObjectDetection>> matchDetectedRegions({
    required List<String> referencePaths,
    required String framePath,
    required List<ObjectDetection> detections,
    double matchThreshold = 0.72,
  }) async {
    if (detections.isEmpty || referencePaths.isEmpty) return detections;
    final model = await _loadClip();
    final referenceEmbeddings = <List<double>>[];
    for (final path in referencePaths) {
      if (!await File(path).exists()) continue;
      var embedding = _cachedReferenceEmbeddings[path];
      if (embedding == null) {
        embedding = await _clipEmbedding(model, path);
        _cachedReferenceEmbeddings[path] = embedding;
      }
      referenceEmbeddings.add(embedding);
    }
    if (referenceEmbeddings.isEmpty) return detections;
    final frame = img.decodeImage(await File(framePath).readAsBytes());
    if (frame == null) throw FormatException('Could not decode camera frame for crop matching.');
    final matched = <ObjectDetection>[];
    for (final detection in detections.take(2)) {
      final left = ((detection.centerX - detection.width / 2) * frame.width).round().clamp(0, frame.width - 1);
      final top = ((detection.centerY - detection.height / 2) * frame.height).round().clamp(0, frame.height - 1);
      final cropWidth = (detection.width * frame.width).round().clamp(1, frame.width - left);
      final cropHeight = (detection.height * frame.height).round().clamp(1, frame.height - top);
      final crop = img.copyCrop(frame, x: left, y: top, width: cropWidth, height: cropHeight);
      final cropPath = '${Directory.systemTemp.path}/fmt_crop_${detection.hashCode}.jpg';
      await File(cropPath).writeAsBytes(img.encodeJpg(crop, quality: 75), flush: true);
      try {
        final embedding = await _clipEmbedding(model, cropPath);
        var bestSimilarity = 0.0;
        for (final reference in referenceEmbeddings) {
          final similarity = _cosineSimilarity(reference, embedding);
          if (similarity > bestSimilarity) bestSimilarity = similarity;
        }
        matched.add(ObjectDetection(
          label: detection.label, confidence: detection.confidence,
          centerX: detection.centerX, centerY: detection.centerY,
          width: detection.width, height: detection.height,
          similarity: bestSimilarity, isMatch: bestSimilarity >= matchThreshold,
        ));
      } finally {
        try { await File(cropPath).delete(); } catch (_) {}
      }
    }
    return matched;
  }

  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) throw StateError('CLIP embedding dimensions do not match.');
    var dot = 0.0;
    var normA = 0.0;
    var normB = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA == 0 || normB == 0) return 0;
    return dot / math.sqrt(normA * normB);
  }

  Future<ImageMatch> compareImages(String referencePath, String cameraPath) async {
    if (!await CoreML.isSupported()) {
      throw StateError('Core ML requires macOS 15 or later.');
    }
    MLModel? model;
    try {
      model = await MLModel.loadAsset(
        clipAsset,
        configuration: const MLModelConfiguration(
          computeUnits: MLComputeUnits.cpuAndNeuralEngine,
        ),
      );
      final reference = await _clipEmbedding(model, referencePath);
      final camera = await _clipEmbedding(model, cameraPath);
      if (reference.length != camera.length) {
        throw StateError('CLIP embedding dimensions do not match.');
      }
      var dot = 0.0;
      var refNorm = 0.0;
      var cameraNorm = 0.0;
      for (var i = 0; i < reference.length; i++) {
        dot += reference[i] * camera[i];
        refNorm += reference[i] * reference[i];
        cameraNorm += camera[i] * camera[i];
      }
      if (refNorm == 0 || cameraNorm == 0) {
        throw StateError('CLIP returned an empty embedding.');
      }
      return ImageMatch(similarity: dot / math.sqrt(refNorm * cameraNorm));
    } finally {
      await model?.dispose();
    }
  }

  Future<List<double>> _clipEmbedding(MLModel model, String path) async {
    final file = File(path);
    if (!await file.exists()) throw FileSystemException('Image not found', path);
    var imageBytes = await file.readAsBytes();
    var decoded = img.decodeImage(imageBytes);

    // Photos selected on macOS can be HEIC even when the picker gives
    // the file a .jpg-looking path. The Dart image package cannot decode
    // HEIC, so use the built-in macOS sips converter as a fallback.
    if (decoded == null && Platform.isMacOS) {
      final convertedPath = '${file.parent.path}/clip_input_${file.uri.pathSegments.last.hashCode}.jpg';
      final conversion = await Process.run(
        'sips',
        ['-s', 'format', 'jpeg', path, '--out', convertedPath],
      );
      final convertedFile = File(convertedPath);
      if (conversion.exitCode == 0 && await convertedFile.exists()) {
        imageBytes = await convertedFile.readAsBytes();
        decoded = img.decodeImage(imageBytes);
      }
    }

    if (decoded == null) {
      throw FormatException(
        'Unsupported image format for CLIP: $path. Please re-add the reference photo as JPEG or PNG.',
      );
    }
    final resized = img.copyResize(decoded, width: 224, height: 224);
    const mean = [0.48145466, 0.4578275, 0.40821073];
    const std = [0.26862954, 0.26130258, 0.27577711];
    final tensor = List<double>.filled(3 * 224 * 224, 0);
    for (var y = 0; y < 224; y++) {
      for (var x = 0; x < 224; x++) {
        final pixel = resized.getPixel(x, y);
        final index = y * 224 + x;
        tensor[index] = (pixel.r / 255.0 - mean[0]) / std[0];
        tensor[224 * 224 + index] = (pixel.g / 255.0 - mean[1]) / std[1];
        tensor[2 * 224 * 224 + index] = (pixel.b / 255.0 - mean[2]) / std[2];
      }
    }
    final prediction = await model.predict({
      'pixel_values': MLMultiArray.float32(
        tensor,
        shape: [1, 3, 224, 224],
      ),
    });
    return prediction.multiArray('var_799').toDoubleList();
  }
}

