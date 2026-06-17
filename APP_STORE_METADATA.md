# Little Spud App Store Metadata Draft

## App Information

- Name: Little Spud
- Subtitle: Pocket companion for Tater
- Bundle ID: `com.tatertotterson.littlespud.ios`
- SKU: `little-spud-ios`
- Primary category: Productivity
- Secondary category: Utilities
- Platforms: iPhone and iPad
- Price: Free

## Description

Little Spud is a native companion app for Tater, the local-first assistant platform.

Pair Little Spud with your own Tater instance, then chat from your iPhone or iPad, receive local device notifications, use voice input, hear TTS replies, and view media responses from your private Tater setup.

Little Spud is designed for people who run their own Tater. It does not require a hosted account, does not use Apple Push Notification service, and does not route your assistant messages through a Little Spud cloud service. When paired, the app talks directly to the Tater URLs you configure, including local LAN addresses and your own away-from-home route such as a private VPN, tunnel, or Tater Tunnel.

Features:

- Pair with Tater by scanning a SpudLink QR code.
- Chat with your Tater assistant from iPhone or iPad.
- Show tool-progress messages while Tater works.
- Display images, audio, and video responses in chat.
- Use local iOS notifications pulled from your Tater queue while the app is active or resumes.
- Use voice input and TTS with your paired Tater.
- Switch between Home/LAN and Away/Tater Tunnel routes.
- Preview the app with built-in local demo mode before pairing.

Little Spud works best with a current Tater install that has SpudLink enabled. Project information and setup guidance are available at https://taterassistant.com.

## Promotional Text

Chat with your private Tater from iPhone or iPad, with local notifications, voice input, TTS, media replies, and Home/Away routing.

## Keywords

Tater,Little Spud,local AI,self hosted,assistant,voice,automation,smart home,chat,private AI

## What's New

Initial iOS release of Little Spud with native pairing, chat, local notifications, voice controls, media playback, TTS, and built-in demo mode.

## Support URL

https://taterassistant.com

## Privacy Policy URL

https://taterassistant.com

TODO: Replace with a dedicated privacy policy URL if we publish one before submission.

## App Review Notes

Use the contents of `APP_REVIEW_NOTES.md`.

## Privacy Answers Draft

Little Spud does not use third-party analytics or advertising tracking.

Data stays on the user's device or is sent directly to the user's configured Tater instance:

- User content: chat messages, voice transcripts, media prompts, and attachments are sent to the user's paired Tater instance when the user chooses to send them.
- Audio data: microphone audio is sent to the user's paired Tater instance only while voice input is active.
- Photos/media: selected media may be sent to the user's paired Tater instance only when the user chooses to attach or request media handling.
- Identifiers: the app stores a local pairing token for the user's Tater instance in the iOS Keychain.
- Diagnostics: no Little Spud cloud diagnostics or analytics are collected by this app.

## ATS / Network Note

Little Spud intentionally allows local and user-configured network connections because Tater is self-hosted. Users may pair with local HTTP LAN addresses, private VPN routes, private tunnel routes, or Tater Tunnel addresses. Away-from-home public routes should use HTTPS where the user's setup supports it.

## Screenshot Checklist

- iPhone pairing screen with Little Spud mascot.
- iPhone demo chat showing tool-progress message and final reply.
- iPhone media response in chat.
- iPhone voice/TTS controls visible.
- iPad pairing screen.
- iPad chat screen.
