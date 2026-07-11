import 'dart:async';
import 'dart:convert';

import 'package:zvcomm_core/zvcomm_core.dart';

import 'scenario.dart';

/// Result counters from a simulation run.
final class SimResult {
  final String scenarioName;
  final int nodeCount;
  final int messagesSent;
  final int messagesDelivered;
  final Duration wallTime;
  final Map<String, int> deliveriesByNode;

  const SimResult({
    required this.scenarioName,
    required this.nodeCount,
    required this.messagesSent,
    required this.messagesDelivered,
    required this.wallTime,
    required this.deliveriesByNode,
  });

  @override
  String toString() =>
      'SimResult(scenario=$scenarioName, nodes=$nodeCount, '
      'sent=$messagesSent, delivered=$messagesDelivered, wall=${wallTime.inMilliseconds}ms)';
}

/// Runs production [MeshNode] code over [MockTransport] medium.
///
/// Phase 2 will add discrete-event scheduling, mobility, loss models, and
/// power accounting. Phase 0 provides a synchronous multi-node harness.
final class MeshSimulator {
  Future<SimResult> run(
    SimScenario scenario, {
    String? broadcastFrom,
    String broadcastText = 'sim-ping',
  }) async {
    final started = DateTime.now();
    final medium = MockMedium();
    final nodes = <String, MeshNode>{};
    final deliveries = <String, int>{};
    final subs = <StreamSubscription<MeshMessage>>[];

    try {
      for (final cfg in scenario.nodes) {
        final transport = MockTransport(
          medium: medium,
          localId: cfg.id,
          displayName: cfg.displayName.isEmpty ? cfg.id : cfg.displayName,
          position: cfg.position,
          rangeMeters: cfg.rangeMeters,
        );
        final node = MeshNode(
          localId: cfg.id,
          displayName: cfg.displayName,
          transports: TransportManager([transport]),
        );
        nodes[cfg.id] = node;
        deliveries[cfg.id] = 0;
        subs.add(node.messages.listen((msg) {
          if (utf8.decode(msg.payload) == broadcastText) {
            deliveries[cfg.id] = (deliveries[cfg.id] ?? 0) + 1;
          }
        }));
        await node.start();
      }

      // Allow discovery ticks.
      await Future<void>.delayed(const Duration(milliseconds: 600));

      final originId = broadcastFrom ?? scenario.nodes.first.id;
      final origin = nodes[originId]!;
      await origin.sendChat(broadcastText);

      // Allow flood propagation.
      await Future<void>.delayed(const Duration(milliseconds: 800));

      final delivered = deliveries.entries
          .where((e) => e.key != originId)
          .fold<int>(0, (a, b) => a + b.value);

      return SimResult(
        scenarioName: scenario.name,
        nodeCount: scenario.nodes.length,
        messagesSent: 1,
        messagesDelivered: delivered,
        wallTime: DateTime.now().difference(started),
        deliveriesByNode: Map.unmodifiable(deliveries),
      );
    } finally {
      for (final s in subs) {
        await s.cancel();
      }
      for (final n in nodes.values) {
        await n.dispose();
      }
    }
  }
}
