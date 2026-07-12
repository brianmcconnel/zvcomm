# ZVComm – Short-Range Communication Application – Project Plan (No-Rust Edition)

**Project Codename:** ZVComm  
**Goal:** Ultra-efficient, cross-platform short-range communication app supporting Bluetooth LE, NFC, Wi-Fi (Direct/Aware/P2P), with modular transport layer for future links (e.g. UWB, LoRa, custom radio). Mesh networking, end-to-end encryption via lightweight PKI, offline-first. Builds for Android, iOS/Apple, Windows, macOS, and Linux.  
**Guiding Principles:**
- Maximum efficiency (low power, low memory, AOT compilation, minimal overhead).
- **Only permissively licensed open-source libraries** (MIT, Apache-2.0, BSD-2/3-Clause, ISC, Zlib, 0BSD, public domain). No GPL, LGPL, AGPL, BUSL, commercial-only, or any license with reuse restrictions.
- If a suitable library does not exist under a fully permissive license, we implement it ourselves (or thin platform-native wrappers we control).
- Modular, pluggable transports and protocols.
- Communication simulator for mesh networking testing.
- Full PKI infrastructure tooling.
- **No Rust** (as requested). Prefer Dart/Flutter or Kotlin Multiplatform for shared code.

**Overall License for Project:** Proprietary — Copyright Brian McConnel 2026. All rights reserved.

**Document Version:** 2.0 (No-Rust)  
**Date:** 2026-07-10  

See repository root `README.md` for setup and Phase 0 status.
