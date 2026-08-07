# QQ Integration Reference Sources

The reference repositories were pinned before implementation so the reviewed
source can be reproduced.

## openclaw-onebot

- Repository: https://github.com/LSTM-Kirigaya/openclaw-onebot
- Commit: `482cf0a949192003d41e0a55f2ed08695dd77fd3`
- License: MIT, Copyright (c) 2026 LSTM-Kirigaya
- Reviewed files: `src/connection.ts`, `src/message.ts`,
  `src/reply-context.ts`, `src/config.ts`, and `src/types.ts`
- Reused concepts: WebSocket lifecycle, OneBot action/echo correlation,
  timeouts, reconnect behavior, private-message parsing, and send failure
  handling

OpenClaw Plugin SDK integration, the OpenClaw main project, agents, schedulers,
group chat, media, Markdown rendering, and OpenClaw sessions were not copied.

## Read-KakaoTalk-Message

- Repository: https://github.com/deunlee/Read-KakaoTalk-Message
- Commit: `58afc262fcff506dee3b176131e227bf67a1ee20`
- License: MIT, Copyright (c) 2022 Deun Lee
- Reviewed files:
  `app/src/main/java/com/readkakaotalk/app/service/MyNotificationService.java`,
  `app/src/main/java/com/readkakaotalk/app/service/MyAccessibilityService.java`,
  and `app/src/main/AndroidManifest.xml`
- Reused concepts: notification-listener service lifecycle, package filtering,
  notification extras parsing, accessibility service lifecycle, and guarded
  node traversal

KakaoTalk package names, view hierarchies, child indexes, coordinate-based
actions, and LocalBroadcastManager behavior were not copied. QQ parsing and
node selection were implemented for QQ and are covered by Whisnya tests.

Full license texts are in [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md).
