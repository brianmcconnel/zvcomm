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
| `zvcomm_core` | Transport interface, mesh, models, identity |
| `zvcomm_ble` | BLE backend (Phase 1) |
| `zvcomm_nfc` | NFC backend (Phase 1) |
| `zvcomm_wifi` | Wi-Fi P2P backend (Phase 1) |
| `zvcomm_pki` | CA / certificates |
| `zvcomm_sim` | Discrete-event / multi-node simulator |
| `zvcomm_ui` | Shared Flutter widgets |
| `zvcomm_app` | Main multi-platform app |
| `zvcomm_cli` | PKI + sim CLI |

## Transport interface

All radios implement `Transport` in `zvcomm_core`:

- `discover()` → `Stream<Peer>`
- `connect(Peer)` → `Connection`
- `startAdvertising` / power modes / dispose

`MockTransport` + `MockMedium` share production mesh code with the simulator.

## Mesh (Phase 0)

Managed flooding:

- Sequence + message id dedup (`PacketDeduper`)
- TTL / hop limit
- Broadcast or unicast destination
- Binary `MeshPacket` v1 framing

Phase 2 adds bloom filters, adaptive routing, and richer topology.

## Security (Phase 0 placeholder)

`DeviceIdentity` uses SHA-256 derived material for stable IDs only.

Phase 3: Noise Protocol sessions, real keys, `LocalCa` → production CA / CFSSL.
