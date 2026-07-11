/// Counters for mesh diagnostics and the simulator.
final class MeshStats {
  int originated = 0;
  int delivered = 0;
  int forwarded = 0;
  int duplicatesDropped = 0;
  int ttlExpired = 0;
  int sendFailures = 0;
  int presenceSent = 0;
  int presenceReceived = 0;
  int unicastRouted = 0;
  int flooded = 0;

  void reset() {
    originated = 0;
    delivered = 0;
    forwarded = 0;
    duplicatesDropped = 0;
    ttlExpired = 0;
    sendFailures = 0;
    presenceSent = 0;
    presenceReceived = 0;
    unicastRouted = 0;
    flooded = 0;
  }

  Map<String, int> toMap() => {
        'originated': originated,
        'delivered': delivered,
        'forwarded': forwarded,
        'duplicatesDropped': duplicatesDropped,
        'ttlExpired': ttlExpired,
        'sendFailures': sendFailures,
        'presenceSent': presenceSent,
        'presenceReceived': presenceReceived,
        'unicastRouted': unicastRouted,
        'flooded': flooded,
      };

  @override
  String toString() => 'MeshStats($toMap())';
}
