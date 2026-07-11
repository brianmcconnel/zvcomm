import 'package:test/test.dart';
import 'package:zvcomm_sim/zvcomm_sim.dart';

void main() {
  test('line scenario delivers broadcast to in-range nodes', () async {
    // Spacing 15, range 40 → all 3 nodes form a connected mesh.
    final scenario = SimScenario.line(count: 3, spacing: 15, rangeMeters: 40);
    final sim = MeshSimulator();
    final result = await sim.run(scenario);
    expect(result.nodeCount, 3);
    expect(result.messagesSent, 1);
    // At least the direct neighbors should receive; full mesh likely all.
    expect(result.messagesDelivered, greaterThanOrEqualTo(1));
  });
}
