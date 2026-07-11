# Phase 2 – Mesh Protocol & Simulator

## Mesh stack (`zvcomm_core`)

### Dedup
- **Exact LRU** window for recent message keys (`sourceId|messageId`)
- **Bloom filter** retains keys aged out of the LRU (memory-efficient)
- Hybrid policy: never false-negative; rare false-positive may drop a new msg

### Adaptive routing
- `RouteTable` learns next-hop from ingress (distance-vector lite)
- Unicast: try direct neighbor → route next-hop → flood fallback
- Neighbor fan-out ordered by RSSI + transport bandwidth rank

### Presence
- Periodic `MessageKind.presence` heartbeats (JSON payload)
- `PresenceTable` tracks live peers with TTL
- Exposed as `MeshNode.presenceUpdates`

### Config & stats
- `MeshConfig` — hop limit, presence interval, bloom size, adaptive flag
- `MeshStats` — originated / delivered / forwarded / dups / unicast vs flood

## Simulator (`zvcomm_sim`)

| Feature | Notes |
|---------|--------|
| Topologies | line, grid, random geometric, bridge |
| Loss model | per-packet Bernoulli loss on `MockMedium` |
| Mobility | random-walk with world bounds |
| Metrics | delivery ratio, hop samples, aggregate mesh stats, presence |
| Scale | line of 40+ nodes in CI; configurable for 500+ |

Uses **production** `MeshNode` + `MockTransport` (dependency injection).

## CLI

```bash
dart run apps/zvcomm_cli/bin/zvcomm_cli.dart sim --topology grid --rows 5 --cols 5
dart run apps/zvcomm_cli/bin/zvcomm_cli.dart sim --topology line --nodes 40 --range 40
dart run apps/zvcomm_cli/bin/zvcomm_cli.dart sim --topology random --nodes 80 --mobility --loss 0.05
```
