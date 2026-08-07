# Whisnya QQ Bridge

A minimal Node.js 20+ sidecar for forwarding NapCat OneBot v11 private text
messages to Whisnya. It is intended to run in Termux on the same Android device
as Whisnya and NapCat.

## Install in Termux

```sh
pkg update -y
pkg install -y nodejs git nano curl
git clone https://github.com/mkdjj/Whisnya.git
cd Whisnya/qq_bridge
npm install
cp config.example.json config.json
nano config.json
npm run build
npm start
```

Configure NapCat with a OneBot 11 forward WebSocket that listens only on
`127.0.0.1`, normally `ws://127.0.0.1:3001`. Copy the Bridge Token from
Whisnya's QQ settings into `whisnya.token` in `config.json`. If NapCat has an
access token, put the same value in `onebot.accessToken`.

Whisnya must be running in Termux / NapCat mode before the sidecar can sync its
allowlist or forward messages. `config.json` is ignored by Git.

## Security and behavior

- Whisnya HTTP is accepted only over loopback and requires a Bearer token.
- The contact allowlist is synchronized from Whisnya every 60 seconds. A failed
  sync clears the in-memory allowlist, so no messages are forwarded.
- Only OneBot private text messages are processed. Groups and non-text segments
  are ignored.
- Action responses are matched by random `echo`, time out after 15 seconds, and
  all pending actions are rejected when the socket closes.
- Reconnect delays are 1, 2, 5, 10, then 30 seconds.
- Message IDs are deduplicated in memory for 30 minutes, up to 1000 entries.
- Tokens and message text are not logged.

## Development

```sh
npm test
npm run build
```
