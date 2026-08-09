<div align="center">
  <a href="https://taterassistant.com">
    <img src="assets/littlespud.png" alt="Tater Little Spud App" width="720"/>
  </a>
</div>
<h3 align="center">
  <a href="https://taterassistant.com">taterassistant.com</a>
</h3>

# Little Spud

This repository contains the native iOS and Android apps for Little Spud. Both use the same SpudLink API for pairing, chat, voice, home controls, Music Core, and device notifications.

Device notifications use Firebase Cloud Messaging and Apple Push Notification service to wake the app with a generic Little Spud alert. The real notification content stays in the paired Tater instance and is fetched by the app or notification service extension when possible.

## Build

### iOS

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

### Android

With JDK 17 and Android SDK Platform 37 installed:

```sh
scripts/build_android.sh
```

The debug APK is written to `android/app/build/outputs/apk/debug/app-debug.apk`. See [`android/README.md`](android/README.md) for Android Studio, release, Firebase, and security setup.

## GitHub Releases

The `Release builds` GitHub Actions workflow runs when a GitHub Release is published. It builds Android and iOS in parallel, verifies the outputs, and attaches these assets to the release:

- Android release APK and AAB, plus SHA-256 checksums.
- Unsigned iOS Simulator app ZIP, plus a SHA-256 checksum.

The workflow can also be run manually from the Actions tab. Manual runs store both builds as Actions artifacts but do not modify a GitHub Release.

Firebase client configuration and Android signing are optional CI secrets. Without them, the workflow still builds, but push is disabled and the Android release is unsigned. Configure these repository secrets for production Android releases:

- `ANDROID_GOOGLE_SERVICES_JSON_BASE64`
- `ANDROID_RELEASE_KEYSTORE_BASE64`
- `ANDROID_RELEASE_STORE_PASSWORD`
- `ANDROID_RELEASE_KEY_ALIAS`
- `ANDROID_RELEASE_KEY_PASSWORD`
- `IOS_GOOGLE_SERVICE_INFO_PLIST_BASE64` for Firebase in the iOS Simulator artifact

Create the Base64 secrets as single-line values, for example: `base64 < google-services.json | tr -d '\n'`. The iOS asset is intended for Simulator testing; signed iPhone/App Store distribution remains an Apple code-signing workflow.

## iOS Native Features

- SpudLink pairing by QR payload or manual code.
- Tater chat over `/api/spudlink/v1/tater/chat`.
- History sync and queued Little Spud notification polling.
- Device notifications through Firebase/APNs with Tater-side content resolution.
- A dedicated Tater-styled notification inbox with preserved titles, timestamps, attachments, and stronger treatment for urgent alerts.
- Live streamed Tater replies with reply ticks and completion haptics.
- Four-lane navigation: swipe right for notifications, or left through room controls and the Music Core player.
- Music Core browsing, search, now-playing controls, sat/media-player selection, and playback directly on this device.
- Provider-neutral room controls for lights, fans, switches, plugs, covers, garage doors, locks, and thermostats, with compact read-only sensor summaries.
- Persistent automatic/Fahrenheit/Celsius display preferences, user-selectable inside/outside temperature rooms, and simultaneous compact inside and outside averages alongside active lights, fans, doors, locks, leaks, and motion grouped by room.
- Tappable room rows in the whole-home Lights details turn every light in that room off when any are on, or turn the room on when all are off; a dedicated compact slider adjusts supported room brightness with one update on release.
- Inside-temperature details place any live thermostat controls above the contributing room sensor readings; outside details remain sensor-only.
