import 'dart:math';

import 'package:core/core.dart';

/// A simulated node placement and identity.
final class SimNodeConfig {
  final String id;
  final String displayName;
  final SimPoint position;
  final double rangeMeters;

  /// Mobility speed in meters per tick (0 = static).
  final double speed;

  const SimNodeConfig({
    required this.id,
    this.displayName = '',
    required this.position,
    this.rangeMeters = 50,
    this.speed = 0,
  });

  SimNodeConfig copyWith({
    SimPoint? position,
    double? speed,
    double? rangeMeters,
  }) =>
      SimNodeConfig(
        id: id,
        displayName: displayName,
        position: position ?? this.position,
        rangeMeters: rangeMeters ?? this.rangeMeters,
        speed: speed ?? this.speed,
      );
}

/// Topology + traffic scenario for the simulator.
final class SimScenario {
  final String name;
  final List<SimNodeConfig> nodes;
  final Duration duration;
  final Duration tick;
  final double packetLoss;
  final Duration linkDelay;
  final bool enableMobility;
  final double worldWidth;
  final double worldHeight;

  const SimScenario({
    required this.name,
    required this.nodes,
    this.duration = const Duration(seconds: 10),
    this.tick = const Duration(milliseconds: 100),
    this.packetLoss = 0,
    this.linkDelay = Duration.zero,
    this.enableMobility = false,
    this.worldWidth = 500,
    this.worldHeight = 500,
  });

  /// Line topology: nodes spaced along X axis (multi-hop when spacing < range).
  factory SimScenario.line({
    int count = 5,
    double spacing = 20,
    double rangeMeters = 30,
    double packetLoss = 0,
  }) {
    final nodes = List.generate(count, (i) {
      return SimNodeConfig(
        id: 'n$i',
        displayName: 'Node $i',
        position: SimPoint(i * spacing, 0),
        rangeMeters: rangeMeters,
      );
    });
    return SimScenario(
      name: 'line-$count',
      nodes: nodes,
      packetLoss: packetLoss,
      worldWidth: count * spacing + 50,
      worldHeight: 100,
    );
  }

  /// Grid topology: [rows] x [cols].
  factory SimScenario.grid({
    int rows = 5,
    int cols = 5,
    double spacing = 25,
    double rangeMeters = 35,
    double packetLoss = 0,
  }) {
    final nodes = <SimNodeConfig>[];
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final i = r * cols + c;
        nodes.add(
          SimNodeConfig(
            id: 'n$i',
            displayName: 'Node $i',
            position: SimPoint(c * spacing, r * spacing),
            rangeMeters: rangeMeters,
          ),
        );
      }
    }
    return SimScenario(
      name: 'grid-${rows}x$cols',
      nodes: nodes,
      packetLoss: packetLoss,
      worldWidth: cols * spacing + 50,
      worldHeight: rows * spacing + 50,
    );
  }

  /// Random geometric graph.
  factory SimScenario.random({
    int count = 50,
    double worldSize = 200,
    double rangeMeters = 40,
    double packetLoss = 0,
    int seed = 42,
    bool mobility = false,
    double speed = 2,
  }) {
    final rng = Random(seed);
    final nodes = List.generate(count, (i) {
      return SimNodeConfig(
        id: 'n$i',
        displayName: 'Node $i',
        position: SimPoint(
          rng.nextDouble() * worldSize,
          rng.nextDouble() * worldSize,
        ),
        rangeMeters: rangeMeters,
        speed: mobility ? speed : 0,
      );
    });
    return SimScenario(
      name: 'random-$count',
      nodes: nodes,
      packetLoss: packetLoss,
      enableMobility: mobility,
      worldWidth: worldSize,
      worldHeight: worldSize,
    );
  }

  /// Two clusters with a bridge node for partition / reconnection tests.
  factory SimScenario.bridge({
    int perCluster = 5,
    double clusterGap = 80,
    double rangeMeters = 35,
    double spacing = 20,
  }) {
    final nodes = <SimNodeConfig>[];
    for (var i = 0; i < perCluster; i++) {
      nodes.add(
        SimNodeConfig(
          id: 'l$i',
          displayName: 'Left $i',
          position: SimPoint(i * spacing, 0),
          rangeMeters: rangeMeters,
        ),
      );
    }
    nodes.add(
      SimNodeConfig(
        id: 'bridge',
        displayName: 'Bridge',
        position: SimPoint(perCluster * spacing + clusterGap / 2, 0),
        rangeMeters: rangeMeters + clusterGap / 2,
      ),
    );
    for (var i = 0; i < perCluster; i++) {
      nodes.add(
        SimNodeConfig(
          id: 'r$i',
          displayName: 'Right $i',
          position: SimPoint(
            perCluster * spacing + clusterGap + i * spacing,
            0,
          ),
          rangeMeters: rangeMeters,
        ),
      );
    }
    return SimScenario(
      name: 'bridge-$perCluster',
      nodes: nodes,
      worldWidth: perCluster * 2 * spacing + clusterGap + 50,
      worldHeight: 100,
    );
  }
}

/// Random-walk mobility step.
final class RandomWalkMobility {
  final double worldWidth;
  final double worldHeight;
  final Random random;

  RandomWalkMobility({
    required this.worldWidth,
    required this.worldHeight,
    Random? random,
  }) : random = random ?? Random(7);

  SimPoint step(SimPoint pos, double speed) {
    if (speed <= 0) return pos;
    final angle = random.nextDouble() * pi * 2;
    var x = pos.x + cos(angle) * speed;
    var y = pos.y + sin(angle) * speed;
    // Bounce off bounds.
    if (x < 0) x = -x;
    if (y < 0) y = -y;
    if (x > worldWidth) x = worldWidth - (x - worldWidth);
    if (y > worldHeight) y = worldHeight - (y - worldHeight);
    return SimPoint(
      x.clamp(0, worldWidth),
      y.clamp(0, worldHeight),
    );
  }
}
