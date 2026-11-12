import 'package:core_ml/core_ml.dart';

/// Loads one Core ML package at a time to reduce peak memory use.
class AiModelService {
  static const yoloAsset = 'assets/models/yolov8n.mlpackage';
  static const clipAsset = 'assets/models/clip_image_encoder.mlpackage';

  Future<String> verifyInstalledModels() async {
    if (!await CoreML.isSupported()) {
      throw StateError(
        'Core ML requires macOS 15 or later for this integration.',
      );
    }
    final yolo = await _inspectAndDispose(yoloAsset, 'YOLOv8n');
    final clip = await _inspectAndDispose(clipAsset, 'CLIP image encoder');
    return yolo + '\n\n' + clip;
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
      return label + ' loaded successfully.\n' + model.modelDescription.toString();
    } finally {
      await model?.dispose();
    }
  }
}
