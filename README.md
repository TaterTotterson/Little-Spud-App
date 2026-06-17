# Little Spud iOS

This is the native iOS app for Little Spud. It uses SwiftUI for pairing, chat, local notification polling, QR scanning, reply haptics, and the same SpudLink API used by the browser and macOS Little Spud apps.

The app does not use APNs. Notifications are local iOS notifications triggered by the native poller while the app is running or active enough to poll the paired Tater Hub. Missed notifications stay queued in Tater and are picked up when the app resumes.

## Build

```sh
scripts/build_app.sh
```

By default this builds for the iOS Simulator with code signing disabled. To build for a signed device target, set the destination and signing options before running the script:

```sh
LITTLE_SPUD_IOS_DESTINATION='generic/platform=iOS' \
LITTLE_SPUD_IOS_CODE_SIGNING_ALLOWED=YES \
LITTLE_SPUD_IOS_CONFIGURATION=Release \
scripts/build_app.sh
```

## Native Features

- SpudLink pairing by QR payload or manual code.
- Tater chat over `/api/spudlink/v1/tater/chat`.
- History sync and queued Little Spud notification polling.
- Local iOS notifications without APNs.
- Reply reveal ticks and completion haptics.
