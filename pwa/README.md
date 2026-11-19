# FindMyThings PWA

A separate, mobile-first web app for keeping a private photo inventory of belongings.

## Features in this first version
- Choose a photo from the device photo library using the browser's image picker.
- Preview and compress the selected photo before saving.
- Create, edit, search, and delete belongings.
- Store item records and photo blobs in IndexedDB on the current device.
- Cache the app shell with a service worker for offline reopening after the first successful visit.
- No account, server API, analytics, or photo upload is used.

## GitHub Pages deployment
This repository contains a deployment-ready copy in `docs/`. In GitHub:
1. Open **Settings → Pages**.
2. Under **Build and deployment**, choose **Deploy from a branch**.
3. Select branch `feature/pwa-mobile-inventory` and folder `/docs`.
4. Save and wait for GitHub Pages to publish the site.

The expected site URL is:
`https://mobeenanwardev-ui.github.io/FindMyThings/`

## Install on iPhone
1. Open the published URL in Safari.
2. Tap Share.
3. Choose **Add to Home Screen**.
4. Open FindMyThings from its new home-screen icon.

## Data and privacy
Belongings and photos are saved in IndexedDB in the browser's local storage on that device. They are not synchronized to other devices and can be removed if website data is cleared. This first version does not yet include AI object recognition or camera tracking.

## Development
The editable PWA source is in `pwa/`; `docs/` is the GitHub Pages copy. Keep both in sync when making changes.
