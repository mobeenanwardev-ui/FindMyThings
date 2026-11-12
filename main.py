
# FindMyThings - Main Application

import cv2
import torch

from pathlib import Path
from PIL import Image
from transformers import CLIPModel, CLIPProcessor

from src.camera import Camera
from src.detector import ObjectDetector
from src.matcher import (
    get_image_embedding,
    calculate_similarity
)
from src.config import (
    CAMERA_INDEX,
    DETECTION_CONFIDENCE,
    CLIP_MODEL_NAME,
    SIMILARITY_THRESHOLD,
    CLIP_INTERVAL,
    CLAHE_CLIP_LIMIT,
    CLAHE_GRID_SIZE
)


def main():

    # 1. Find project directory
    project_path = Path(__file__).resolve().parent

    reference_path = project_path / "wallet_reference.jpg"

    if not reference_path.exists():
        raise FileNotFoundError(
            f"Reference image not found: {reference_path}"
        )

    # 2. Load reference wallet
    reference_image = Image.open(
        reference_path
    ).convert("RGB")

    # 3. Load CLIP model
    print("Loading CLIP model...")

    clip_processor = CLIPProcessor.from_pretrained(
        CLIP_MODEL_NAME
    )

    clip_model = CLIPModel.from_pretrained(
        CLIP_MODEL_NAME
    )

    clip_model.eval()

    reference_embedding = get_image_embedding(
        reference_image,
        clip_model,
        clip_processor
    )

    # 4. Load YOLO detector
    print("Loading YOLO model...")

    detector = ObjectDetector()

    # 5. Configure image enhancement
    clahe = cv2.createCLAHE(
        clipLimit=CLAHE_CLIP_LIMIT,
        tileGridSize=CLAHE_GRID_SIZE
    )

    # 6. Initialise camera
    camera = Camera(CAMERA_INDEX)

    track_scores = {}
    frame_count = 0

    try:

        camera.start()

        print("FindMyThings is running!")
        print("Press Q to exit.")

        while True:

            frame = camera.read()
            frame_count += 1

            # Improve brightness
            lab = cv2.cvtColor(
                frame,
                cv2.COLOR_BGR2LAB
            )

            L, A, B = cv2.split(lab)

            enhanced_L = clahe.apply(L)

            bright_frame = cv2.cvtColor(
                cv2.merge((enhanced_L, A, B)),
                cv2.COLOR_LAB2BGR
            )

            # Detect and track objects
            result = detector.detect_and_track(
                bright_frame
            )

            display_frame = bright_frame.copy()

            # Process tracked objects
            if (
                result.boxes is not None
                and result.boxes.id is not None
            ):

                boxes = result.boxes.xyxy.cpu().numpy()
                track_ids = result.boxes.id.int().cpu().tolist()
                class_ids = result.boxes.cls.int().cpu().tolist()

                for box, track_id, class_id in zip(
                    boxes, track_ids, class_ids
                ):

                    x1, y1, x2, y2 = map(int, box)

                    height, width = bright_frame.shape[:2]

                    x1 = max(0, x1)
                    y1 = max(0, y1)
                    x2 = min(width, x2)
                    y2 = min(height, y2)

                    if x2 <= x1 or y2 <= y1:
                        continue

                    # Calculate CLIP similarity periodically
                    if (
                        track_id not in track_scores
                        or frame_count % CLIP_INTERVAL == 0
                    ):

                        crop = bright_frame[y1:y2, x1:x2]

                        if crop.size == 0:
                            continue

                        crop_rgb = cv2.cvtColor(
                            crop,
                            cv2.COLOR_BGR2RGB
                        )

                        crop_image = Image.fromarray(
                            crop_rgb
                        )

                        candidate_embedding = get_image_embedding(
                            crop_image,
                            clip_model,
                            clip_processor
                        )

                        similarity = calculate_similarity(
                            candidate_embedding,
                            reference_embedding
                        )

                        track_scores[track_id] = similarity

                    similarity = track_scores.get(
                        track_id, 0.0
                    )

                    class_name = detector.model.names[
                        class_id
                    ]

                    # Highlight possible match
                    if similarity >= SIMILARITY_THRESHOLD:

                        color = (0, 255, 0)
                        status = "Possible wallet match"

                    else:

                        color = (0, 165, 255)
                        status = "Other candidate"

                    cv2.rectangle(
                        display_frame,
                        (x1, y1),
                        (x2, y2),
                        color,
                        2
                    )

                    label = (
                        f"ID {track_id} | {class_name} | "
                        f"{similarity:.2f}"
                    )

                    cv2.putText(
                        display_frame,
                        label,
                        (x1, max(y1 - 10, 20)),
                        cv2.FONT_HERSHEY_SIMPLEX,
                        0.5,
                        color,
                        2
                    )

                    cv2.putText(
                        display_frame,
                        status,
                        (x1, min(y2 + 20, height - 5)),
                        cv2.FONT_HERSHEY_SIMPLEX,
                        0.5,
                        color,
                        2
                    )

            # Display camera output
            cv2.imshow(
                "FindMyThings",
                display_frame
            )

            if cv2.waitKey(1) & 0xFF == ord("q"):
                break

    finally:

        camera.stop()


if __name__ == "__main__":
    main()
