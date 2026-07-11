# ZVComm Architecture Overview

## Layers

```
Application (chat, files, presence)
        ↓
Security (identity, PKI, Noise — Phase 3)
        ↓
Mesh / routing (flood + adaptive links)
        ↓
Transport abstraction (send/recv/discover)
   BLE │ NFC │ Wi-Fi │ Mock │ Future
```

## Packages

| Package | Role |
|---------|------|
| `core` | Transport interface, mesh, models, identity |
| `ble` | BLE backend (Phase 1) |
| `nfc` | NFC backend (Phase 1) |
| `wifi` | Wi-Fi P2P backend (Phase 1) |
| `pki` | CA / certificates |
| `sim` | Discrete-event / multi-node simulator |
| `ui` | Shared Flutter widgets |
| `app` | Main multi-platform app |
| `cli` | PKI + sim CLI |

## Transport interface

All radios implement `Transport` in `core`:

- `discover()` → `Stream<Peer>`
- `connect(Peer)` → `Connection`
- `startAdvertising` / power modes / dispose

`MockTransport` + `MockMedium` share production mesh code with the simulator.

## Mesh (Phase 2)

- Hybrid bloom + LRU dedup
- Adaptive unicast (route table) with managed flood fallback
- Presence heartbeats + TTL
- `MeshConfig` / `MeshStats`
- Binary `MeshPacket` v1 framing

See [phase2-mesh.md](phase2-mesh.md).

## Security (Phase 3)

- X25519 + Ed25519 identities (`cryptography`, Apache-2.0)
- ZVComm Handshake v1 + ChaCha20-Poly1305 E2E sessions
- Ed25519 mesh certificates, enrollment, signed CRLs
- `IdentityStore` (memory / file); mobile keystore later

See [phase3-security.md](phase3-security.md).

## Extensibility (Phase 5)

- Plugin registry for transports
- Hot enable/disable backends
- Hardware adapter byte-pipe → mesh transport
- Stubs for UWB / LoRa

See [phase5-extensibility.md](phase5-extensibility.md).

## Features (Phase 4)

Chat, file transfer, status UI, packaging — see [phase4-features.md](phase4-features.md).
