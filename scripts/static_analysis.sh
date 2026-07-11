#!/usr/bin/env bash
# Local static analysis suite for ZVComm (Dart/Flutter monorepo).
# Usage: ./scripts/static_analysis.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export PATH="${FLUTTER_ROOT:+$FLUTTER_ROOT/bin:}${PATH}"
if ! command -v flutter >/dev/null 2>&1 && [[ -x "$HOME/flutter/bin/flutter" ]]; then
  export PATH="$HOME/flutter/bin:$PATH"
fi

fail=0
section() { printf '\n======== %s ========\n' "$1"; }

section "Workspace pub get"
flutter pub get

section "dart format"
if ! dart format --set-exit-if-changed --output=none .; then
  echo "FORMAT: failed (run: dart format .)"
  fail=1
fi

section "dart analyze (pure-Dart packages)"
if ! dart analyze --fatal-infos packages/core packages/pki packages/sim apps/cli; then
  fail=1
fi

section "flutter analyze (Flutter packages + app)"
for d in packages/ble packages/nfc packages/wifi packages/ui apps/app; do
  echo "--- $d ---"
  if ! (cd "$d" && flutter analyze --fatal-infos); then
    fail=1
  fi
done

section "License allow-list"
if ! dart run tool/license_check.dart; then
  fail=1
fi

section "Gitleaks (secrets)"
if command -v gitleaks >/dev/null 2>&1; then
  if ! gitleaks detect --source=. --config=.gitleaks.toml --verbose; then
    fail=1
  fi
elif command -v docker >/dev/null 2>&1; then
  if ! docker run --rm -v "$ROOT:/repo" -w /repo zricethezav/gitleaks:latest \
    detect --source=. --config=.gitleaks.toml --verbose; then
    fail=1
  fi
else
  echo "SKIP: gitleaks not installed (and no docker)"
fi

section "pub outdated (informational)"
dart pub outdated || true

if [[ "$fail" -ne 0 ]]; then
  echo
  echo "STATIC ANALYSIS: FAILED"
  exit 1
fi
echo
echo "STATIC ANALYSIS: OK"
