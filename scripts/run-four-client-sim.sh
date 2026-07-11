#!/usr/bin/env bash
# Build and run the four-client Docker mesh simulation.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

COMPOSE=(docker compose -f docker/sim/docker-compose.yml)

echo "==> Building images..."
"${COMPOSE[@]}" build

echo "==> Starting hub + alice/bob/carol/dave (line topology)..."
"${COMPOSE[@]}" up --abort-on-container-exit --exit-code-from alice

echo "==> Done. Tear down with:"
echo "    docker compose -f docker/sim/docker-compose.yml down -v"
