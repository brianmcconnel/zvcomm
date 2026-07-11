# Four-client Docker mesh simulation

Runs **production `MeshNode` code** in four CLI containers over a shared **TCP radio hub** that simulates range-limited links.

## Topology

```
alice (x=0) —— bob (x=25) —— carol (x=50) —— dave (x=75)
              range = 40 m each
```

Direct radio links: alice↔bob, bob↔carol, carol↔dave.  
Messages from **alice → dave** take **multi-hop mesh flood** through bob and carol.

## Quick start

From the repo root:

```bash
./scripts/run-four-client-sim.sh
# or
docker compose -f docker/sim/docker-compose.yml up --build
```

Clients emit JSON lines:

| `event` | Meaning |
|---------|---------|
| `started` | Node online on hub |
| `peer` | Neighbor discovered (in range) |
| `sent` | Outbound chat (post-censor) |
| `chat` | Inbound chat delivered by mesh |
| `stopped` | Node exiting |

## CLI (without Docker)

```bash
# Terminal 1 — hub
dart run apps/cli/bin/cli.dart hub --port 7700

# Terminals 2–5 — nodes
dart run apps/cli/bin/cli.dart mesh-node --hub 127.0.0.1:7700 \
  --id alice --x 0 --range 40 --message "hi" --duration 30
# bob x=25, carol x=50, dave x=75 …
```

## Architecture

| Component | Role |
|-----------|------|
| `zvcomm hub` | Simulated medium: register positions, peer sightings, range checks, frame delivery |
| `zvcomm mesh-node` | Full `MeshNode` + `TcpSimTransport` client |
| `TcpSimTransport` | `Transport` backend over TCP (in `packages/sim`) |

Multi-hop routing, dedup, and presence still come from **core** — the hub only models **one radio hop**.
