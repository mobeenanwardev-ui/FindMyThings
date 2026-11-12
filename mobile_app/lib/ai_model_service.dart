import 'package:core_ml/core_ml.dart';

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
        if (bestScore < 0.30) continue;

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
}
