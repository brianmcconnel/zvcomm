# ZVComm

**Ultra-efficient, cross-platform short-range mesh communication.**

Bluetooth LE · NFC · Wi-Fi P2P · pluggable transports · offline-first · permissive licenses only · **no Rust**.

| | |
|---|---|
| **License** | Apache-2.0 |
| **Stack** | Flutter + Dart (AOT) |
| **Platforms** | Android, iOS, Linux, macOS, Windows |
| **Status** | Phase 2 – Mesh + Simulator |

## Architecture

```
Application (chat, files, presence)
        ↓
Security (PKI + crypto)          ← Phase 3
        ↓
Mesh / routing                   ← Phase 0 skeleton + Phase 2
        ↓
Transport abstraction
   BLE │ NFC │ Wi-Fi │ Mock │ Future (UWB, LoRa, …)
```

## Repository layout

```
zvcomm/
├── packages/
│   ├── zvcomm_core/     # Transport API, mesh, models, identity
│   ├── zvcomm_ble/      # BLE transport (stub → Phase 1)
│   ├── zvcomm_nfc/      # NFC transport (stub → Phase 1)
│   ├── zvcomm_wifi/     # Wi-Fi P2P transport (stub → Phase 1)
│   ├── zvcomm_pki/      # PKI / local CA skeleton
│   ├── zvcomm_sim/      # Mesh simulator
│   └── zvcomm_ui/       # Shared Flutter widgets
├── apps/
│   ├── zvcomm_app/      # Main Flutter app
│   └── zvcomm_cli/      # PKI + simulator CLI
├── docs/
├── tool/license_check.dart
└── melos.yaml
```

## Prerequisites

- Flutter stable (3.22+) / Dart 3.5+
- Linux: `clang`, `cmake`, `ninja`, GTK dev packages for desktop runs

```bash
# Optional: add Flutter to PATH
export PATH="$HOME/flutter/bin:$PATH"
```

## Quick start

```bash
# From repo root
dart pub get

# Core unit tests
dart test packages/zvcomm_core

# Simulator CLI
dart run apps/zvcomm_cli/bin/zvcomm_cli.dart sim --topology line --nodes 20 --range 40
dart run apps/zvcomm_cli/bin/zvcomm_cli.dart sim --topology grid --rows 5 --cols 5

# Generate a demo identity
dart run apps/zvcomm_cli/bin/zvcomm_cli.dart identity --name Alice

# Issue a placeholder mesh certificate
dart run apps/zvcomm_cli/bin/zvcomm_cli.dart ca-issue --name Alice

# Run the Flutter app (mock discovery demo)
cd apps/zvcomm_app && flutter run -d linux   # or chrome, windows, macos, …
```

### Melos (optional)

```bash
dart pub global activate melos
melos bootstrap
melos run test:core
melos run license:check
```

## Phase 0 deliverables

- [x] Flutter monorepo (pub workspace + Melos)
- [x] `Transport` interface + `MockTransport` / `MockMedium`
- [x] `TransportManager` multi-backend discovery
- [x] Mesh flood router + `MeshPacket` framing + `MeshNode`
- [x] Minimal app UI: identity + discovered peers
- [x] Simulator skeleton sharing production mesh code
- [x] PKI skeleton (`LocalCa`, placeholder certs) + CLI
- [x] License allow-list docs + CI license gate

## Phase 1 deliverables

- [x] BLE: central + peripheral via `bluetooth_low_energy` (MIT)
- [x] NFC: NDEF bootstrap via `nfc_manager` (MIT)
- [x] Wi-Fi: Android P2P (`flutter_p2p_connection` MIT) + LAN SoftAP fallback
- [x] Power-mode hooks (scan duty cycle / session control)
- [x] Android / iOS permissions and manifests
- [x] App UI transport availability chips
- [x] Length-prefixed frame codec for MTU-limited links

See [docs/architecture/phase1-transports.md](docs/architecture/phase1-transports.md).

## Phase 2 deliverables

- [x] Hybrid bloom + LRU packet dedup
- [x] Adaptive unicast routing with route table + flood fallback
- [x] Presence heartbeats and live peer table
- [x] MeshConfig / MeshStats
- [x] Simulator: line/grid/random/bridge, loss, mobility, metrics
- [x] Multi-hop and scale tests (40-node line)
- [x] CLI topologies (`--topology line|grid|random|bridge`)

See [docs/architecture/phase2-mesh.md](docs/architecture/phase2-mesh.md).

## Development phases

| Phase | Focus |
|-------|--------|
| **0** | Foundation, mock transport, mesh skeleton, UI, license CI |
| **1** | Real BLE / NFC / Wi-Fi transports |
| **2** | Mesh protocol polish + full simulator |
| **3** | Noise / PKI, secure storage, enrollment |
| **4** | Chat, files, battery, store packaging |
| **5** | Plugin system for new transports |

## Licensing

- **First-party code:** Apache-2.0
- **Dependencies:** MIT / Apache-2.0 / BSD / ISC / Zlib / 0BSD / public domain only  
- **No** GPL, LGPL, AGPL, BUSL, or commercial-only plugins  
- See [docs/licenses/ALLOWLIST.md](docs/licenses/ALLOWLIST.md)

```bash
dart run tool/license_check.dart
```

## Success metrics (targets)

- 2-hop BLE chat latency &lt; 150 ms  
- Android release size &lt; 25–30 MB  
- Simulator: 500+ nodes  
- Zero non-permissive licenses  
- Clean builds on all five platforms  

## Docs

- [Architecture overview](docs/architecture/overview.md)
- [Project plan](docs/PROJECT_PLAN.md)
- [License allow-list](docs/licenses/ALLOWLIST.md)

---

Copyright 2026 ZVComm Contributors · Apache-2.0
