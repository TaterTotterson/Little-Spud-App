# Little Spud for Android

Native Android client for the same SpudLink API used by Little Spud on iOS. It is built with Kotlin, Jetpack Compose, Android Keystore-backed credentials, OkHttp, Media3, ML Kit Code Scanner, and optional Firebase Cloud Messaging.

## Requirements

- JDK 17 or newer
- Android SDK Platform 37 and Build Tools 36.0.0
- An Android 8.0 (API 26) or newer device/emulator

Set `ANDROID_HOME` or `ANDROID_SDK_ROOT`, then build from the repository root:

```sh
scripts/build_android.sh
```

The debug APK is written to `android/app/build/outputs/apk/debug/app-debug.apk`. You can also open the `android` directory as a project in Android Studio.

For an unsigned release artifact:

```sh
scripts/build_android.sh :app:assembleRelease
```

Configure a release signing key in your private Gradle/CI configuration before distributing the resulting APK or App Bundle. Do not commit signing credentials.

### GitHub release builds

Publishing a GitHub Release runs `.github/workflows/release-builds.yml`. The workflow executes Android unit tests and release lint, builds an APK and AAB, generates SHA-256 checksums, and attaches them to the release. A manual workflow run produces downloadable Actions artifacts without changing a release.

The workflow uses these optional repository secrets:

- `ANDROID_GOOGLE_SERVICES_JSON_BASE64` enables Firebase in the build.
- `ANDROID_RELEASE_KEYSTORE_BASE64`, `ANDROID_RELEASE_STORE_PASSWORD`, `ANDROID_RELEASE_KEY_ALIAS`, and `ANDROID_RELEASE_KEY_PASSWORD` sign the APK and AAB.

All four signing secrets must be configured together. If they are absent, the release filenames include `-unsigned`.

## Firebase push setup

Push is optional. Pairing, chat, history, voice, home controls, music, attachments, and foreground notification polling work without Firebase.

To enable background notifications:

1. Add an Android app with package name `com.tatertotterson.littlespud.android` to the Firebase project used by the Little Spud push gateway.
2. Download its `google-services.json` to `android/app/google-services.json` (this path is ignored by Git).
3. Deploy the Android-aware version of `FirebaseGateway/little_spud_firebase_gateway.py`. Its registration allowlist includes the Android app ID and its FCM sends use high-priority Android data messages.
4. Rebuild the app, pair it, grant notification permission, and enable notifications in Settings.

The Google Services Gradle plugin is applied only when `google-services.json` exists. The Settings screen shows whether Firebase was included in the build.

## Network and security notes

- Pairing tokens, push credentials, and the stable installation ID are encrypted with an Android Keystore AES/GCM key.
- Notification bodies remain on the paired Tater. FCM carries only a generic wake event; the app fetches private content directly from Tater.
- Cleartext HTTP is enabled because a home-network Tater may advertise a local `http://` route. Use the HTTPS away route on untrusted networks.
- Microphone capture starts only after the user grants permission and taps the mic. Audio is streamed as 16 kHz, mono, 16-bit PCM to the paired Tater's `/api/spudlink/v1/stt/stream` endpoint and stops when the app leaves the foreground.

## Included features

- QR/manual SpudLink pairing, encrypted session persistence, home/away route probing, and reconnect.
- Streaming Tater chat, tool notices, history/active-run merge, image attachments, TTS, and streaming voice input.
- Four lanes for notification inbox, chat, provider-neutral home controls/cameras, and Music Core.
- Local Android playback through Media3 plus remote Music Core targets and controls.
- Optional FCM background wake-ups with direct Tater content resolution, acknowledgement, and foreground polling fallback.
- A no-server demo mode for checking the main UI and flows.

## Verification

```sh
scripts/build_android.sh :app:testDebugUnitTest :app:lintDebug :app:assembleDebug
```
