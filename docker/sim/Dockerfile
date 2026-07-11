# ZVComm multi-client mesh simulator image (CLI + hub + mesh-node).
# Uses a slim workspace (no Flutter packages) for faster AOT compile.
FROM dart:stable AS build
WORKDIR /src

# Slim root workspace — only pure-Dart packages needed by the CLI.
COPY docker/sim/workspace.pubspec.yaml pubspec.yaml
COPY packages/core packages/core
COPY packages/pki packages/pki
COPY packages/sim packages/sim
COPY apps/cli apps/cli

RUN dart pub get
RUN mkdir -p /out && dart compile exe apps/cli/bin/cli.dart -o /out/zvcomm

FROM debian:bookworm-slim
RUN apt-get update -qq \
  && apt-get install -y -qq --no-install-recommends ca-certificates \
  && rm -rf /var/lib/apt/lists/*
COPY --from=build /out/zvcomm /usr/local/bin/zvcomm
ENTRYPOINT ["zvcomm"]
CMD ["version"]
