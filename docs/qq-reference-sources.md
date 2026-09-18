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

Full license texts are in [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md).
