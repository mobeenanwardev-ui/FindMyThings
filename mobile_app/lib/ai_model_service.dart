import 'dart:io';
import 'package:core_ml/core_ml.dart';
import 'package:image/image.dart' as img;

class ObjectDetection {
  const ObjectDetection({
    required this.label,
    required this.confidence,
    required this.centerX,
    required this.centerY,
  });

  final String label;
  final double confidence;
  final double centerX;
  final double centerY;
}

class ImageMatch {
  const ImageMatch({required this.similarity});
  final double similarity;
}

class AiModelService {
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
    if (!await CoreML.isSupported()) {
      throw StateError('Core ML requires macOS 15 or later.');
    }
    MLModel? model;
    try {
      model = await MLModel.loadAsset(
        yoloAsset,
        configuration: const MLModelConfiguration(
          computeUnits: MLComputeUnits.cpuAndNeuralEngine,
        ),
      );
      final prediction = await model.predict({
        'image': ImageInput.file(imagePath),
      });
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
          if (score > bestScore) {
            bestScore = score;
            bestClass = c;
          }
        }
        if (bestScore < 0.20) continue;
        detections.add(ObjectDetection(
          label: _labels[bestClass],
          confidence: bestScore,
          centerX: values[i],
          centerY: values[candidates + i],
        ));
      }
      detections.sort((a, b) => b.confidence.compareTo(a.confidence));
      return detections.take(5).toList();
    } finally {
      await model?.dispose();
    }
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
      return ImageMatch(similarity: dot / (refNorm * cameraNorm).sqrt());
    } finally {
      await model?.dispose();
    }
  }

  Future<List<double>> _clipEmbedding(MLModel model, String path) async {
    final file = File(path);
    if (!await file.exists()) throw FileSystemException('Image not found', path);
    final decoded = img.decodeImage(await file.readAsBytes());
    if (decoded == null) throw FormatException('Could not decode image: $path');
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

extension on double {
  double sqrt() => this <= 0 ? 0 : _sqrt(this);
}

double _sqrt(double value) {
  var x = value;
  var next = (x + 1) / 2;
  while ((next - x).abs() > 1e-10) {
    x = next;
    next = (x + value / x) / 2;
  }
  return x;
}
