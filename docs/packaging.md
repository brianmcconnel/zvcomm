# Packaging & store readiness (Phase 4)

## Versioning

App version lives in `apps/app/pubspec.yaml` (`version: X.Y.Z+build`).

| Platform | Artifact |
|----------|----------|
| Android | App Bundle / APK |
| iOS | IPA (Xcode / `flutter build ipa`) |
| Linux | `flutter build linux` → AppImage optional |
| macOS | `flutter build macos` → DMG/notarize |
| Windows | `flutter build windows` → MSIX optional |

## Build commands

```bash
export PATH="$HOME/flutter/bin:$PATH"
cd apps/app

flutter build apk --release
flutter build appbundle --release
flutter build linux --release
flutter build windows --release
flutter build macos --release
flutter build ipa --release   # macOS host + signing
```

## Android checklist

- [x] `minSdk` ≥ 24 (BLE)
- [x] Permissions: Bluetooth, NFC, Wi-Fi, location (for scan)
- [ ] Play App Signing + privacy policy URL
- [ ] Data safety form (nearby devices, approximate location)
- [ ] ProGuard/R8 keep rules if minifying plugins

## iOS / Apple checklist

- [x] Usage strings: Bluetooth, NFC, Local Network, Location
- [x] Background modes: bluetooth-central / peripheral
- [ ] NFC entitlement + Apple Developer capability
- [ ] Privacy Nutrition Labels
- [ ] App Store screenshots (all form factors)

## Desktop checklist

- [x] Linux / Windows / macOS targets from Flutter
- [ ] Linux: distribute as AppImage/Flatpak; sandbox portal notes for BLE
- [ ] Windows: MSIX identity; Bluetooth capability in package manifest
- [ ] macOS: App Sandbox Bluetooth + Network entitlements for release

## Battery / background

- App lifecycle → `MeshNode.setBackgroundMode` + transport `powerSaver`
- Presence interval stretches by `backgroundPresenceFactor`
- Avoid sticky foreground services until product requires always-on mesh

## Size budget

Target Android release **&lt; 25–30 MB** (tree-shake icons, split per ABI):

```bash
flutter build apk --release --split-per-abi
```

## License

Ship `LICENSE` (Apache-2.0) and third-party notices for Flutter + plugins.
