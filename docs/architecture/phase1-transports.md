# Phase 1 – Transports

## BLE (`zvcomm_ble`)

| Item | Choice |
|------|--------|
| Plugin | [bluetooth_low_energy](https://pub.dev/packages/bluetooth_low_energy) **MIT** |
| Roles | Central (scan/connect) + Peripheral (advertise + GATT server) |
| Platforms | Android, iOS, macOS, Windows (Linux central only; no peripheral) |

**GATT profile**

| UUID | Role |
|------|------|
| `6b7a0001-5e2d-4f3a-9c1b-8d4e2f0a1b2c` | Mesh service |
| `…0002…` | RX (central writes) |
| `…0003…` | TX (notify to central) |
| `…0004…` | Identity read (`id\|name`) |

Frames use length-prefixed binary (`StreamFrameCodec`) and are chunked to the negotiated write MTU.

**Power modes** map to scan duty cycle (continuous / periodic / rare burst).

## NFC (`zvcomm_nfc`)

| Item | Choice |
|------|--------|
| Plugin | [nfc_manager](https://pub.dev/packages/nfc_manager) + [nfc_manager_ndef](https://pub.dev/packages/nfc_manager_ndef) **MIT** |
| Platforms | Android, iOS |
| Use case | Pairing / bootstrap, short payloads |

NDEF MIME type: `application/x-zvcomm` carrying JSON identity (+ optional data).

## Wi-Fi (`zvcomm_wifi`)

| Backend | When | License |
|---------|------|---------|
| [flutter_p2p_connection](https://pub.dev/packages/flutter_p2p_connection) | Android Wi-Fi Direct + BLE credential exchange | MIT |
| `LanSoftApTransport` | Desktop / fallback | First-party Apache-2.0 |

LAN SoftAP fallback: UDP broadcast discovery + TCP framed links (same `StreamFrameCodec`). Suitable for lab mesh on one subnet; not a true radio SoftAP.

## Permissions

See Android `AndroidManifest.xml` and iOS `Info.plist` in `apps/zvcomm_app`.

## Testing without radios

- `BleTransport.unavailable()` for pure unit tests
- Mock transport still enabled in the app for demos
- LAN SoftAP works on loopback in CI
