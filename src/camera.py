
# FindMyThings - Camera Manager

import cv2


class Camera:

    def __init__(self, camera_index=0):

        self.camera_index = camera_index
        self.cap = None

    def start(self):

        self.cap = cv2.VideoCapture(
            self.camera_index
        )

        if not self.cap.isOpened():
            raise RuntimeError("Could not open camera")

        print("Camera started successfully!")

    def read(self):

        if self.cap is None:
            raise RuntimeError("Camera has not been started")

        ret, frame = self.cap.read()

        if not ret:
            raise RuntimeError("Could not read camera frame")

        return frame

    def stop(self):

        if self.cap is not None:
            self.cap.release()
            self.cap = None

        cv2.destroyAllWindows()

        print("Camera stopped.")
