# FindMyThings PWA

A separate, mobile-first web app for a private photo inventory and an experimental live visual finder.

## Features
- Choose a photo from the device photo library.
- Preview and compress the selected photo before saving.
- Create, edit, search, and delete belongings.
- Store item records and photo blobs in IndexedDB on the current device.
- Open **Find it** for a live camera session.
- Load TensorFlow.js + MobileNet in the browser and compare visual feature vectors from the saved reference image and camera frames.
- Cache the app shell with a service worker for offline reopening after the first successful visit.

## Important: what the live finder does (and does not do)
The current scanner is an **experimental whole-frame visual-similarity prototype**. It compares MobileNet features from the saved photo with features from the camera frame and displays a similarity score. The score is not a probability, and a high score is not proof that the object has been found. It does not yet locate an object's bounding box, isolate the target from the background, or reliably distinguish a personal item from similar-looking objects. It may be affected by camera angle, distance, lighting, and the background in the reference photo.

A first internet connection is required to download TensorFlow.js and the MobileNet model. Camera access requires HTTPS and user permission. The inventory itself remains local; camera frames and photos are processed in the browser and are not sent to a FindMyThings server.

## GitHub Pages deployment
The editable source is in `pwa/`; the publishing copy is in `docs/`. In GitHub:
1. Open **Settings → Pages**.
2. Choose **Deploy from a branch**.
3. Select branch `feature/pwa-mobile-inventory` and folder `/docs`.

Expected URL:
`https://mobeenanwardev-ui.github.io/FindMyThings/`

## Install on iPhone
1. Open the published URL in Safari.
2. Tap Share → **Add to Home Screen**.
3. Open FindMyThings from the new home-screen icon.
4. Add a belonging with a clear reference photo, then tap **Find it** to try the camera prototype.

## Data and privacy
Belongings and photos are stored in IndexedDB in the browser on that device. They are not synchronized to other devices and may be removed if website data is cleared. No account or FindMyThings backend is used.

## Next engineering steps
- Evaluate on real iPhone Safari devices and tune the similarity pipeline using representative belongings.
- Add object proposals/cropping and reference-to-region matching rather than comparing the whole camera frame.
- Consider a dedicated image-embedding model and model caching for more robust offline operation.
- Add an explicit tracking overlay only after the target region can be located reliably.
