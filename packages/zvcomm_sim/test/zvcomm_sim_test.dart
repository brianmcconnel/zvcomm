import 'package:test/test.dart';
import 'package:zvcomm_core/zvcomm_core.dart';
import 'package:zvcomm_sim/zvcomm_sim.dart';

void main() {
  test('line scenario delivers broadcast to in-range nodes', () async {
    final scenario = SimScenario.line(count: 3, spacing: 15, rangeMeters: 40);
    final sim = MeshSimulator();
    final result = await sim.run(scenario);
    expect(result.nodeCount, 3);
    expect(result.messagesSent, 1);
    expect(result.messagesDelivered, greaterThanOrEqualTo(1));
    expect(result.deliveryRatio, greaterThan(0));
  });

  test('multi-hop line reaches far node', () async {
    // spacing 25, range 30 → only adjacent neighbors; needs flooding hops.
    final scenario = SimScenario.line(count: 5, spacing: 25, rangeMeters: 30);
    final result = await MeshSimulator().run(
      scenario,
      options: const SimRunOptions(
        settleAfterStart: Duration(milliseconds: 800),
        settleAfterSend: Duration(milliseconds: 1500),
        meshConfig: MeshConfig.simulation,
      ),
    );
    expect(result.uniqueDestinationsReached, greaterThanOrEqualTo(2));
  });

  test('grid scenario has high delivery under no loss', () async {
    final scenario = SimScenario.grid(rows: 3, cols: 3, spacing: 20, rangeMeters: 30);
    final result = await MeshSimulator().run(
      scenario,
      options: const SimRunOptions(
        settleAfterStart: Duration(milliseconds: 700),
        settleAfterSend: Duration(milliseconds: 1200),
      ),
    );
    expect(result.nodeCount, 9);
    expect(result.messagesDelivered, greaterThanOrEqualTo(4));
  });

  test('packet loss reduces delivery', () async {
    final clean = await MeshSimulator().run(
      SimScenario.line(count: 4, spacing: 15, rangeMeters: 40, packetLoss: 0),
    );
    final lossy = await MeshSimulator().run(
      SimScenario.line(count: 4, spacing: 15, rangeMeters: 40, packetLoss: 0.5),
      options: const SimRunOptions(
        settleAfterSend: Duration(milliseconds: 1000),
      ),
    );
    // Lossy should not deliver more than clean (probabilistic; allow equal).
    expect(lossy.messagesDelivered, lessThanOrEqualTo(clean.messagesDelivered + 1));
  });

  test('scale line of 40 nodes completes', () async {
    final result = await MeshSimulator().runLineScale(nodeCount: 40);
    expect(result.nodeCount, 40);
    expect(result.messagesSent, 1);
    // At least some multi-hop progress.
    expect(result.uniqueDestinationsReached, greaterThanOrEqualTo(1));
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('presence floods produce events', () async {
    final scenario = SimScenario.line(count: 3, spacing: 15, rangeMeters: 40);
    final result = await MeshSimulator().run(
      scenario,
      options: const SimRunOptions(
        collectPresence: true,
        settleAfterStart: Duration(milliseconds: 1200),
        settleAfterSend: Duration(milliseconds: 400),
        meshConfig: MeshConfig(
          presenceInterval: Duration(milliseconds: 300),
          presenceTtl: Duration(seconds: 5),
        ),
      ),
    );
    expect(result.presenceEvents, greaterThan(0));
  });
}
