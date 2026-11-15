# FindMyThings

**An offline-first visual search prototype for finding personal belongings.**

FindMyThings explores a practical question: can a person save a visual reference of an item and then use a live camera feed to locate that same item in their surroundings?

The system combines object detection with visual similarity matching. Rather than relying only on a generic category such as "backpack", it compares detected image regions with photographs of the user's particular belonging.

> **Project status:** This repository contains a Flutter desktop prototype targeting macOS, an on-device Core ML inference path, and an earlier Python/OpenCV proof of concept. The current camera and native tracking integration is macOS-specific. An iPhone/iOS-ready camera and tracking implementation is not yet complete; see [Current status and limitations](#current-status-and-limitations).

## What it does

- Save belongings with a name, category and reference photo.
- Keep the inventory and reference images in app-local storage.
- Run object detection on live camera frames using YOLOv8n.
- Compare candidate regions against reference images using CLIP image embeddings and cosine similarity.
- Display candidate detections and a possible-match state in the camera view.
- Use Apple Vision tracking after a visual match is found, with periodic detector passes to re-acquire the object and limit tracking drift.
- Run the mobile-app inference path locally with Core ML; no cloud inference service is part of this implementation.

## How the matching pipeline works

1. **Register the item.** The user saves a belonging and its reference image(s).
2. **Capture a frame.** The camera stream supplies frames to the Flutter application.
3. **Prepare the input.** Frames are resized while preserving aspect ratio, letterboxed to 640 × 640, and encoded as JPEG. Pixel conversion and encoding run in a worker isolate.
4. **Detect candidates.** YOLOv8n proposes object regions and confidence scores. The app decodes the model output and applies class-aware non-maximum suppression.
5. **Compare visual appearance.** The highest-confidence candidate region is cropped and encoded by CLIP. Its embedding is compared with cached embeddings of the saved reference photos using cosine similarity. The best reference similarity is used for the match decision.
6. **Track the confirmed target.** On macOS, Apple Vision tracks the matched bounding box between detector passes. YOLO + CLIP periodically re-check the target to correct drift.
7. **Present feedback.** The UI draws candidate boxes and communicates the current scan/match state.

The Python proof of concept follows the same broad idea using Ultralytics YOLO tracking and Hugging Face CLIP embeddings.

## Architecture

See **[ARCHITECTURE.md](ARCHITECTURE.md)** for component responsibilities, data flow, model details, design decisions, and platform constraints.

    Flutter UI + local inventory
              |
              v
       Camera frame stream
              |
              v
      Frame preprocessing
       (640x640 letterbox)
              |
              v
       YOLOv8n detection
              |
              v
       Candidate region crop
              |
              v
      CLIP image embedding <--- saved reference photo embeddings
              |
              v
      Cosine similarity / match decision
              |
              v
      Apple Vision tracking (macOS prototype)
              |
              v
          Detection overlay

## Technology

| Area | Technology |
|---|---|
| Desktop application UI | Flutter, Dart, Material 3 |
| On-device model runtime | Core ML |
| Object detection | YOLOv8n |
| Visual representation | CLIP image encoder |
| Native object tracking | Apple Vision (VNSequenceRequestHandler) |
| Image processing | Dart image package; OpenCV in Python prototype |
| Local persistence | JSON file in application documents directory; local image files |
| Earlier proof of concept | Python, PyTorch, Transformers, Ultralytics, OpenCV |

## Repository layout

    .
    ├── main.py                      # Python/OpenCV proof-of-concept entry point
    ├── src/
    │   ├── camera.py                # OpenCV camera lifecycle
    │   ├── detector.py              # YOLO detection and ByteTrack integration
    │   ├── matcher.py               # CLIP embeddings and cosine similarity
    │   └── config.py                # Model and pipeline configuration
    ├── mobile_app/
    │   ├── lib/
    │   │   ├── main.dart            # Flutter UI, inventory, camera workflow
    │   │   └── ai_model_service.dart # Core ML inference and visual matching
    │   ├── macos/Runner/
    │   │   └── MainFlutterWindow.swift # Native Apple Vision tracking channel
    │   ├── assets/models/            # YOLO and CLIP Core ML model packages
    │   └── pubspec.yaml              # Flutter dependencies and model assets
    └── ARCHITECTURE.md               # Detailed system architecture

## Running the Flutter macOS prototype

### Requirements

- macOS 15 or later (required by the current Core ML integration).
- Flutter SDK compatible with the Dart SDK constraint in mobile_app/pubspec.yaml.
- Xcode and macOS command-line development tools.
- A working camera and permission for the application to access it.

### Run

    cd mobile_app
    flutter pub get
    flutter run -d macos

The repository includes Core ML model packages under mobile_app/assets/models/. Use **Settings → Check offline AI models** in the app to verify that the bundled models can be loaded on the machine.

Camera access may require granting permission in macOS System Settings. If the camera or model runtime fails to initialize, check the application logs and permission configuration.

## Python proof of concept

The root-level Python application is an earlier desktop experiment. It uses a local camera, Ultralytics YOLO + ByteTrack, and Hugging Face CLIP through PyTorch/Transformers.

The Python environment must have the packages imported by main.py and the src/ modules installed. The script expects a reference image named wallet_reference.jpg in the repository root.

    python main.py

Press **Q** in the OpenCV window to stop the prototype. The Python and Flutter implementations are separate execution paths; the Python script is not a backend service used by the Flutter app.

## Current status and limitations

This repository should be evaluated as a working engineering prototype, not as a finished cross-platform consumer application.

- **macOS is the current supported camera target.** The Flutter camera integration uses camera_macos, and native tracking is exposed through a macOS Swift method channel.
- **iOS support remains unfinished.** The current macOS camera plugin and native Vision bridge are not an iPhone implementation. iOS camera capture, platform-specific tracking integration, permissions, signing, and on-device validation still need to be completed.
- **Matching is visual similarity, not identity verification.** Similar-looking objects, lighting changes, occlusion, camera angle, blur, and reference-photo quality can affect scores.
- **The similarity threshold is a heuristic.** It must be calibrated using a representative evaluation set before making accuracy claims.
- **Tracking can drift.** The app periodically re-runs detection and matching to re-anchor the tracker, but this does not eliminate all tracking errors.
- **No quantified accuracy or latency benchmark is published yet.** Performance and match quality should be measured on a documented test set and target hardware.

## Engineering priorities

1. Complete and validate the iOS camera and native tracking implementation.
2. Add automated tests for preprocessing, YOLO output decoding/NMS, embedding similarity, persistence, and coordinate transformations.
3. Build a reproducible evaluation dataset with multiple objects, reference photos, lighting conditions, viewpoints, and negative examples.
4. Measure precision/recall, false-positive rate, time-to-detection, and per-frame latency on target devices.
5. Calibrate match thresholds from evaluation results rather than relying on a manually selected constant.
6. Add structured logging and graceful handling for camera, model-loading, and inference failures.

## Privacy

The current inventory implementation stores saved item metadata and reference photos locally in the app's documents directory. The described inference flow runs on-device using bundled Core ML models. This repository does not implement account sync or a cloud inference backend.

## License

No license is currently declared. All rights and reuse permissions should be clarified before external redistribution.
