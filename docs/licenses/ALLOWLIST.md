# Dependency License Allow-List

ZVComm only accepts **permissive** open-source licenses.

## Allowed

| License | Notes |
|---------|--------|
| MIT | |
| Apache-2.0 | Preferred for code we write |
| BSD-2-Clause | |
| BSD-3-Clause | Flutter / Dart SDK |
| ISC | |
| Zlib | |
| 0BSD | |
| Unlicense | Public domain equivalent |
| CC0-1.0 | Public domain dedication |
| MPL-2.0 | File-level weak copyleft; allowed only after review |

## Forbidden

| License / clause | Reason |
|------------------|--------|
| GPL (any) | Strong copyleft |
| LGPL (any) | Library copyleft / linking obligations |
| AGPL | Network copyleft |
| BUSL | Source-available, non-OSI / commercial restrictions |
| SSPL | Not OSI open source |
| Commons Clause | Commercial restriction |
| Proprietary / commercial-only | e.g. some BLE plugins requiring paid licenses |

## Phase 1 transport dependencies (verified)

| Package | License | Use |
|---------|---------|-----|
| bluetooth_low_energy (+ platform pkgs) | MIT | BLE central + peripheral |
| nfc_manager | MIT | NFC session |
| nfc_manager_ndef | MIT | NDEF read/write |
| ndef_record | MIT | NDEF records |
| flutter_p2p_connection | MIT | Android Wi-Fi Direct |
| permission_handler | MIT | Runtime permissions |
| network_info_plus | BSD | Optional network info |

**Avoided:** flutter_blue_plus commercial forks, LGPL NFC stacks (libnfc).

## Process

1. Prefer pure Dart / first-party Apache-2.0 code.
2. Before adding a dependency, verify license on pub.dev and in the repo `LICENSE`.
3. Run `dart run tool/license_check.dart` (also in CI).
4. If no permissive library exists, **implement it ourselves**.

## Project license

All first-party ZVComm code is **Apache-2.0**.
