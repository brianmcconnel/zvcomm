# CI builds

## Workflows

| Workflow | File | Purpose |
|----------|------|---------|
| **CI** | `.github/workflows/ci.yml` | Format, analyze, unit/widget tests, license gate (`flutter pub get` only; no melos bootstrap) |
| **Build** | `.github/workflows/build.yml` | Release binaries for all platforms + upload artifacts |

## When builds run

- Push to `main` / `master`
- Pull requests targeting those branches
- Tags matching `v*` (also creates a GitHub Release)
- Manual: **Actions → Build → Run workflow**

## Artifacts

Download from the Actions run page (**Artifacts** section):

| Artifact name | Contents |
|---------------|----------|
| `zvcomm-linux-x64` | `.tar.gz` of the Linux bundle (run `./app` inside) |
| `zvcomm-windows-x64` | `.zip` of the Windows `Release` folder (run `.exe`) |
| `zvcomm-macos` | `.zip` containing the `.app` |
| `zvcomm-web` | `.tar.gz` of `build/web` (static host / any web server) |
| `zvcomm-android` | Split APKs + App Bundle (`.aab`) |
| `zvcomm-ios-unsigned` | Unsigned `Runner.app` (needs Apple signing for devices/store) |
| `zvcomm-cli-linux-x64` | Native CLI binary |
| `zvcomm-cli-windows-x64` | `zvcomm-cli.exe` |
| `zvcomm-cli-macos` | Native CLI binary |

Retention: **14 days** (normal runs), **30 days** on tags.

## Tags → GitHub Release

```bash
git tag v0.5.0
git push origin v0.5.0
```

The **Build** workflow attaches all artifacts to a GitHub Release with generated notes.

## Notes

- **Windows / macOS / iOS** jobs use GitHub-hosted runners (not WSL).
- **CLI** jobs install Flutter (not Dart-only) so the monorepo workspace can resolve `apps/app`.
- **Android** APKs are **debug-signed by Flutter’s default debug/upload keystore** for CI unless you add signing secrets.
- **iOS** is intentionally **unsigned** (`--no-codesign`); store/TestFlight still need certificates and provisioning profiles.
- Desktop plugins that need radios (BLE/NFC) may build but need hardware + OS permissions at runtime.

## Local equivalent (Linux / web / CLI)

```bash
# CLI
dart compile exe apps/cli/bin/cli.dart -o dist/zvcomm-cli

# Web
cd apps/app && flutter build web --release

# Linux (needs clang/cmake/ninja/gtk)
cd apps/app && flutter build linux --release
```
