import 'package:zvcomm_core/zvcomm_core.dart';

/// A simulated node placement and identity.
final class SimNodeConfig {
  final String id;
  final String displayName;
  final SimPoint position;
  final double rangeMeters;

  const SimNodeConfig({
    required this.id,
    this.displayName = '',
    required this.position,
    this.rangeMeters = 50,
  });
}

/// Topology + traffic scenario for the simulator (Phase 0 skeleton).
final class SimScenario {
  final String name;
  final List<SimNodeConfig> nodes;
  final Duration duration;
  final Duration tick;

  const SimScenario({
    required this.name,
    required this.nodes,
    this.duration = const Duration(seconds: 10),
    this.tick = const Duration(milliseconds: 100),
  });

  /// Line topology: nodes spaced along X axis.
  factory SimScenario.line({
    int count = 5,
    double spacing = 20,
    double rangeMeters = 30,
  }) {
    final nodes = List.generate(count, (i) {
      return SimNodeConfig(
        id: 'n$i',
        displayName: 'Node $i',
        position: SimPoint(i * spacing, 0),
        rangeMeters: rangeMeters,
      );
    });
    return SimScenario(name: 'line-$count', nodes: nodes);
  }
}
