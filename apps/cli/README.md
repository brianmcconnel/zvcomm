# ZVComm CLI

PKI tooling, secure-session demo, in-process mesh sim, and multi-process **hub / mesh-node** agents.

```bash
dart run apps/cli/bin/cli.dart --help
```

## Multi-process / Docker simulation

```bash
# Radio hub (range-limited links)
dart run apps/cli/bin/cli.dart hub --port 7700

# Client node
dart run apps/cli/bin/cli.dart mesh-node \
  --hub 127.0.0.1:7700 --id alice --x 0 --range 40 \
  --message "hello" --duration 30
```

Four-container line topology:

```bash
./scripts/run-four-client-sim.sh
```

See [docker/sim/README.md](../../docker/sim/README.md).
