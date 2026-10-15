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

Pair Little Spud with your own Tater instance, then chat from your iPhone or iPad, receive device notifications, use voice input, hear TTS replies, join Sat Chats, view connected cameras, and optionally synchronize approved health totals with your private Fitness Core.

Little Spud is designed for people who run their own Tater. It does not require a hosted account, does not use Apple Push Notification service, and does not route your assistant messages through a Little Spud cloud service. When paired, the app talks directly to the Tater URLs you configure, including local LAN addresses and your own away-from-home route such as a private VPN, tunnel, or Tater Tunnel.

Features:

- Pair with Tater by scanning a SpudLink QR code.
- Chat with your Tater assistant from iPhone or iPad.
- Show tool-progress messages while Tater works.
- Display images, audio, and video responses in chat.
- Receive private Tater notifications and reconcile removed Awareness events automatically.
- Use voice input and TTS with your paired Tater.
- Start audio or video Sat Chats with compatible Tater satellites.
- View live camera and doorbell streams exposed by your Tater integrations.
- Optionally send approved Apple Health daily aggregates to your own Fitness Core for wellness insights and activity challenges.
- Switch between Home/LAN and Away/Tater Tunnel routes.
- Preview the app with built-in local demo mode before pairing.

Little Spud works best with a current Tater install that has SpudLink enabled. Project information and setup guidance are available at https://taterassistant.com.

## Promotional Text

Chat with your private Tater, join Sat Chats, view cameras, receive alerts, and optionally explore private Fitness Core insights.

## Keywords

Tater,Little Spud,local AI,self hosted,assistant,voice,automation,smart home,chat,private AI

## What's New

Adds audio and video Sat Chat, live camera and doorbell viewing, and optional Apple Health synchronization with Fitness Core. Fitness now includes private wellness summaries, detailed metric insights, and challenges between people linked in Tater. This update also improves notification media loading, removes Awareness alerts that no longer exist, and reduces background health work by syncing only changed daily totals when Fitness Core is available.

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
- Health and fitness: approved daily aggregates may be sent directly to the user's paired, self-hosted Tater instance only after the user enables Apple Health synchronization. Little Spud does not send raw HealthKit samples or health data to the app developer.
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
