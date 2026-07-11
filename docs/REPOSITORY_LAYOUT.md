# Repository layout

Package folders use short names (no `zvcomm_` prefix). The **product** is still
called ZVComm; Android/iOS application IDs remain under `com.zvcomm.*` for
platform identity.

```
packages/
  core/   # mesh, crypto, plugins  → package:core
  ble/    # BLE                    → package:ble
  nfc/    # NFC                    → package:nfc
  wifi/   # Wi-Fi / LAN            → package:wifi
  pki/    # certificates / CA      → package:pki
  sim/    # simulator              → package:sim
  ui/     # shared widgets         → package:ui
apps/
  app/    # Flutter client         → package:app
  cli/    # tooling CLI            → package:cli
```

Imports look like `import 'package:core/core.dart';`.

**Why not keep `zvcomm_*`?** This repo is not published as multiple pub.dev
packages, so the prefix only added noise. Short names match folder purpose.

**Why keep `com.zvcomm.zvcomm_app` on Android?** Store / OS install identity is
independent of Dart package names; changing it later is a migration.
