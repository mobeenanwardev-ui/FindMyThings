
# FindMyThings - Object Detector and Tracker

from src.config import DETECTION_CONFIDENCE
from ultralytics import YOLO


class ObjectDetector:

    def __init__(self, model_path="yolov8n.pt"):

        # Load YOLO model once
        self.model = YOLO(model_path)

    def detect_and_track(self, frame):

        # Detect and track objects
        results = self.model.track(
            frame,
            persist=True,
            tracker="bytetrack.yaml",
            conf=DETECTION_CONFIDENCE,
            verbose=False
        )

        return results[0]
