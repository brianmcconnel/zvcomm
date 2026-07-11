import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:zvcomm_core/zvcomm_core.dart';

import 'scenario.dart';

/// Aggregated metrics from a simulation run.
final class SimResult {
  final String scenarioName;
  final int nodeCount;
  final int messagesSent;
  final int messagesDelivered;
  final int uniqueDestinationsReached;
  final Duration wallTime;
  final Map<String, int> deliveriesByNode;
  final Map<String, int> aggregateMeshStats;
  final double deliveryRatio;
  final List<int> hopSamples;
  final double? avgHopCount;
  final int presenceEvents;

  const SimResult({
    required this.scenarioName,
    required this.nodeCount,
    required this.messagesSent,
    required this.messagesDelivered,
    required this.uniqueDestinationsReached,
    required this.wallTime,
    required this.deliveriesByNode,
    required this.aggregateMeshStats,
    required this.deliveryRatio,
    required this.hopSamples,
    required this.avgHopCount,
    required this.presenceEvents,
  });

  @override
  String toString() =>
      'SimResult(scenario=$scenarioName, nodes=$nodeCount, '
      'sent=$messagesSent, delivered=$messagesDelivered, '
      'ratio=${deliveryRatio.toStringAsFixed(2)}, '
      'avgHops=${avgHopCount?.toStringAsFixed(2)}, '
      'wall=${wallTime.inMilliseconds}ms)';

  Map<String, Object?> toJson() => {
        'scenario': scenarioName,
        'nodeCount': nodeCount,
        'messagesSent': messagesSent,
        'messagesDelivered': messagesDelivered,
        'uniqueDestinationsReached': uniqueDestinationsReached,
        'deliveryRatio': deliveryRatio,
        'avgHopCount': avgHopCount,
        'wallMs': wallTime.inMilliseconds,
        'presenceEvents': presenceEvents,
        'meshStats': aggregateMeshStats,
        'deliveriesByNode': deliveriesByNode,
      };
}

/// Options for a [MeshSimulator] run.
final class SimRunOptions {
  final String? broadcastFrom;
  final String broadcastText;
  final int broadcastCount;
  final Duration settleAfterStart;
  final Duration settleAfterSend;
  final bool collectPresence;
  final MeshConfig meshConfig;

  const SimRunOptions({
    this.broadcastFrom,
    this.broadcastText = 'sim-ping',
    this.broadcastCount = 1,
    this.settleAfterStart = const Duration(milliseconds: 600),
    this.settleAfterSend = const Duration(milliseconds: 800),
    this.collectPresence = false,
    this.meshConfig = MeshConfig.simulation,
  });
}

/// Runs production [MeshNode] code over [MockTransport] with loss/mobility.
final class MeshSimulator {
  /// Execute [scenario] and return metrics.
  Future<SimResult> run(
    SimScenario scenario, {
    String? broadcastFrom,
    String broadcastText = 'sim-ping',
    SimRunOptions? options,
  }) async {
    final opts = options ??
        SimRunOptions(
          broadcastFrom: broadcastFrom,
          broadcastText: broadcastText,
        );
    final started = DateTime.now();
    final medium = MockMedium(
      packetLoss: scenario.packetLoss,
      linkDelay: scenario.linkDelay,
    );
    final mobility = RandomWalkMobility(
      worldWidth: scenario.worldWidth,
      worldHeight: scenario.worldHeight,
      random: Random(99),
    );

    final nodes = <String, MeshNode>{};
    final transports = <String, MockTransport>{};
    final configs = <String, SimNodeConfig>{
      for (final n in scenario.nodes) n.id: n,
    };
    final deliveries = <String, int>{};
    final hopSamples = <int>[];
    var presenceEvents = 0;
    final subs = <StreamSubscription<dynamic>>[];
    Timer? mobilityTimer;

    try {
      for (final cfg in scenario.nodes) {
        final transport = MockTransport(
          medium: medium,
          localId: cfg.id,
          displayName: cfg.displayName.isEmpty ? cfg.id : cfg.displayName,
          position: cfg.position,
          rangeMeters: cfg.rangeMeters,
        );
        transports[cfg.id] = transport;
        final node = MeshNode(
          localId: cfg.id,
          displayName: cfg.displayName,
          transports: TransportManager([transport]),
          config: opts.meshConfig,
        );
        nodes[cfg.id] = node;
        deliveries[cfg.id] = 0;
        subs.add(node.messages.listen((msg) {
          if (utf8.decode(msg.payload) == opts.broadcastText) {
            deliveries[cfg.id] = (deliveries[cfg.id] ?? 0) + 1;
            // hopLimit remaining → hops used ≈ base - remaining (approx).
            final used =
                (opts.meshConfig.defaultHopLimit - msg.hopLimit).clamp(0, 64);
            hopSamples.add(used);
          }
        }));
        if (opts.collectPresence) {
          subs.add(node.presenceUpdates.listen((_) {
            presenceEvents++;
          }));
        }
        await node.start();
      }

      if (scenario.enableMobility) {
        mobilityTimer = Timer.periodic(scenario.tick, (_) {
          for (final id in transports.keys) {
            final cfg = configs[id]!;
            if (cfg.speed <= 0) continue;
            final next = mobility.step(cfg.position, cfg.speed);
            configs[id] = cfg.copyWith(position: next);
            transports[id]!.position = next;
          }
        });
      }

      await Future<void>.delayed(opts.settleAfterStart);

      final originId = opts.broadcastFrom ?? scenario.nodes.first.id;
      final origin = nodes[originId]!;
      for (var i = 0; i < opts.broadcastCount; i++) {
        await origin.sendChat(opts.broadcastText);
        if (i + 1 < opts.broadcastCount) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }

      await Future<void>.delayed(opts.settleAfterSend);

      // Extra settle if multi-hop long lines.
      if (scenario.nodes.length > 20) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }

      final deliveredToOthers = deliveries.entries
          .where((e) => e.key != originId)
          .fold<int>(0, (a, b) => a + b.value);
      final uniqueReached = deliveries.entries
          .where((e) => e.key != originId && e.value > 0)
          .length;
      final expected =
          (scenario.nodes.length - 1) * opts.broadcastCount;
      final ratio = expected == 0 ? 0.0 : deliveredToOthers / expected;

      final agg = <String, int>{};
      for (final n in nodes.values) {
        n.stats.toMap().forEach((k, v) {
          agg[k] = (agg[k] ?? 0) + v;
        });
      }

      final avgHops = hopSamples.isEmpty
          ? null
          : hopSamples.reduce((a, b) => a + b) / hopSamples.length;

      return SimResult(
        scenarioName: scenario.name,
        nodeCount: scenario.nodes.length,
        messagesSent: opts.broadcastCount,
        messagesDelivered: deliveredToOthers,
        uniqueDestinationsReached: uniqueReached,
        wallTime: DateTime.now().difference(started),
        deliveriesByNode: Map.unmodifiable(deliveries),
        aggregateMeshStats: Map.unmodifiable(agg),
        deliveryRatio: ratio,
        hopSamples: List.unmodifiable(hopSamples),
        avgHopCount: avgHops,
        presenceEvents: presenceEvents,
      );
    } finally {
      mobilityTimer?.cancel();
      for (final s in subs) {
        await s.cancel();
      }
      for (final n in nodes.values) {
        await n.dispose();
      }
    }
  }

  /// Scale probe: line topology with [nodeCount] nodes (for CI / metrics).
  Future<SimResult> runLineScale({
    int nodeCount = 50,
    double spacing = 15,
    double rangeMeters = 40,
  }) {
    return run(
      SimScenario.line(
        count: nodeCount,
        spacing: spacing,
        rangeMeters: rangeMeters,
      ),
      options: SimRunOptions(
        settleAfterStart: Duration(
          milliseconds: (400 + nodeCount * 8).clamp(400, 5000),
        ),
        settleAfterSend: Duration(
          milliseconds: (600 + nodeCount * 10).clamp(600, 8000),
        ),
        meshConfig: MeshConfig.simulation,
      ),
    );
  }
}
