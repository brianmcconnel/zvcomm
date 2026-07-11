# ZVComm

**Ultra-efficient, cross-platform short-range mesh communication.**

Bluetooth LE · NFC · Wi-Fi P2P · pluggable transports · offline-first · permissive licenses only · **no Rust**.

| | |
|---|---|
| **License** | Apache-2.0 |
| **Stack** | Flutter + Dart (AOT) |
| **Platforms** | Android, iOS, Linux, macOS, Windows |
| **Status** | Phase 5 – Extensibility (complete roadmap) |

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
│   ├── core/    # Transport API, mesh, models, identity, plugins
│   ├── ble/     # Bluetooth LE transport
│   ├── nfc/     # NFC transport
│   ├── wifi/    # Wi-Fi P2P / LAN transport
│   ├── pki/     # PKI / certificates
│   ├── sim/     # Mesh simulator
│   └── ui/      # Shared Flutter widgets
├── apps/
│   ├── app/     # Main Flutter app
│   └── cli/     # PKI + sim CLI (`dart run` / `zvcomm`)
├── docs/
├── tool/
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
dart test packages/core

# Simulator CLI
dart run apps/cli/bin/cli.dart sim --topology line --nodes 20 --range 40
dart run apps/cli/bin/cli.dart sim --topology grid --rows 5 --cols 5

# Generate an Ed25519/X25519 identity
dart run apps/cli/bin/cli.dart identity --name Alice --seed alice

# CA + enroll
dart run apps/cli/bin/cli.dart ca-init --out ca.json
dart run apps/cli/bin/cli.dart enroll --seed phone --name Phone --ca ca.json --out-cert cert.json

# Secure session demo
dart run apps/cli/bin/cli.dart noise-demo

# Run the Flutter app (mock discovery demo)
cd apps/app && flutter run -d linux   # or chrome, windows, macos, …
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

## Phase 3 deliverables

- [x] X25519 + Ed25519 device identities (`cryptography`, Apache-2.0)
- [x] ZVComm Handshake v1 + ChaCha20-Poly1305 sessions
- [x] `SecureMesh` E2E façade over mesh control/chat
- [x] Ed25519 mesh certificates + local CA
- [x] Enrollment request/response (NFC/QR/BLE ready)
- [x] Signed revocation lists
- [x] `MemoryIdentityStore` / `FileIdentityStore`
- [x] CLI: `ca-init`, `ca-issue`, `enroll`, `noise-demo`

See [docs/architecture/phase3-security.md](docs/architecture/phase3-security.md).

## Phase 4 deliverables

- [x] Chat (broadcast + peer threads)
- [x] Chunked file transfer over mesh
- [x] Status: transports, mesh stats, presence, transfers
- [x] Settings + power modes
- [x] App lifecycle battery policy (background power-saver)
- [x] Packaging guide + version 0.4.0
- [x] CI multi-platform release builds (Linux, Windows, macOS, Web, Android, iOS, CLI)

See [docs/architecture/phase4-features.md](docs/architecture/phase4-features.md) and [docs/packaging.md](docs/packaging.md).

## Phase 5 deliverables

- [x] `TransportPlugin` + `TransportRegistry`
- [x] Hot-plug `TransportManager.register` / `unregister`
- [x] `HardwareAdapter` + `AdapterTransport` bridge
- [x] Loopback hardware pair for tests
- [x] UWB / LoRa stub plugins (disabled by default)
- [x] BLE / NFC / Wi-Fi self-registration helpers
- [x] Settings UI to enable/disable plugins at runtime

See [docs/architecture/phase5-extensibility.md](docs/architecture/phase5-extensibility.md).

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
- [Repository layout](docs/REPOSITORY_LAYOUT.md)
- [CI builds (all platforms)](docs/CI_BUILDS.md)
- [Packaging](docs/packaging.md)
- [Project plan](docs/PROJECT_PLAN.md)
- [License allow-list](docs/licenses/ALLOWLIST.md)

## CI builds

Push to `main` or run **Actions → Build → Run workflow** to produce:

Linux · Windows · macOS · Web · Android (APK/AAB) · iOS (unsigned) · CLI binaries

Download artifacts from the workflow run page. Tags `v*` also create a GitHub Release. See [docs/CI_BUILDS.md](docs/CI_BUILDS.md).

---

Copyright 2026 ZVComm Contributors · Apache-2.0
