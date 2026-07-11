# Phase 4 – Features, Polish, Packaging

## Application features

| Feature | Implementation |
|---------|----------------|
| Chat | Broadcast + per-peer threads (`ChatLog`, `ChatScreen`) |
| Profanity filter | [`censor_it`](https://pub.dev/packages/censor_it) (MIT) via `MessageCensor` — applied before encrypt / after decrypt |
| File transfer | Chunked `MessageKind.data` frames (`FileTransferService`) |
| Presence / status | Live presence list + `MeshStatsView` |
| Power / battery | Lifecycle observer → background presence + powerSaver |
| Settings | Discovery toggle, mock peer, power mode |

## Navigation

Bottom bar: **Peers · Chat · Status · Settings**

## File transfer wire format

- `0x01` offer (JSON metadata)
- `0x02` chunk (id, index, payload)
- `0x04` complete
- `0x05` abort

Default chunk size 400 bytes (BLE-friendly).

## Packaging

See [docs/packaging.md](../packaging.md).
