# Static analysis

## Tools

| Tool | Purpose | Local | CI |
|------|---------|-------|----|
| **dart analyze** / **flutter analyze** | Type safety, lints (`analysis_options.yaml`) | yes | Static analysis + CI |
| **dart format** | Style gate | yes | Static analysis + CI |
| **license_check.dart** | Permissive-license allow-list | yes | Static analysis + CI |
| **gitleaks** | Secrets / credential leak detection | yes (Docker or binary) | Static analysis |
| **CodeQL** | Security/quality on **GitHub Actions YAML** only | GitHub only | Static analysis |
| **pub outdated** | Dependency freshness (informational) | yes | local script only |

> **Note:** CodeQL has **no Dart language pack** ([codeql#17447](https://github.com/github/codeql/issues/17447)).
> Dart/Flutter quality is covered by the analyzer + strict lints; secrets by gitleaks;
> workflow security by CodeQL `actions`.

## Run everything locally

```bash
./scripts/static_analysis.sh
```

Requires Flutter/Dart on `PATH` (or `$HOME/flutter`). Gitleaks uses a local binary if present, otherwise Docker (`zricethezav/gitleaks`).

## Per-package analyzer config

- Root: `analysis_options.yaml` — strict casts/inference + extra lints  
- Pure Dart packages: `package:lints/recommended.yaml`  
- Flutter packages / app: `package:flutter_lints/flutter.yaml`  

Analyzer treats **infos as errors** in CI (`--fatal-infos`).

## Gitleaks

Config: [`.gitleaks.toml`](../.gitleaks.toml)

- Ignores `build/`, `.dart_tool/`, generated assets  
- Allowlists crypto **identifier names** (`ed25519PrivateKey`, etc.) so field names are not treated as secrets  

## GitHub

Workflow: [`.github/workflows/static-analysis.yml`](../.github/workflows/static-analysis.yml)

- Push / PR to `main`  
- Weekly schedule  
- Manual: **Actions → Static analysis → Run workflow**  

CodeQL results appear under the repo **Security → Code scanning** tab (requires default setup permissions on first run).
