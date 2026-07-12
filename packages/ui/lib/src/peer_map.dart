import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:core/core.dart';

/// Layout model for a peer on the local mesh map (unit coordinates).
final class PeerMapMarker {
  final String id;
  final String label;

  /// Position in a normalized plane (self at origin); scaled to widget size.
  final Offset position;
  final int? rssi;
  final Set<TransportKind> transports;

  /// True when layout used metadata `x`/`y` (sim / future GPS-relative).
  final bool hasKnownPosition;

  const PeerMapMarker({
    required this.id,
    required this.label,
    required this.position,
    this.rssi,
    this.transports = const {},
    this.hasKnownPosition = false,
  });
}

/// Place peers around self using optional sim coordinates or RSSI rings.
///
/// **Not deck.gl** — pure Flutter [CustomPainter] (Skia/Impeller). deck.gl is
/// JavaScript/WebGPU only; this radar-style map is the multi-platform equivalent
/// for short-range mesh (dozens of peers, not city-scale GIS).
List<PeerMapMarker> layoutPeerMap(Iterable<Peer> peers) {
  final list = peers.toList();
  if (list.isEmpty) return const [];

  // Collect known plane positions when metadata carries x/y.
  final known = <String, Offset>{};
  for (final p in list) {
    final x = double.tryParse(p.metadata['x'] ?? '');
    final y = double.tryParse(p.metadata['y'] ?? '');
    if (x != null && y != null) {
      known[p.id] = Offset(x, y);
    }
  }

  // If any peer has known coords, place all known ones in that plane and
  // fall back to RSSI rings for the rest.
  Offset? centroid;
  double maxR = 1;
  if (known.isNotEmpty) {
    var sx = 0.0, sy = 0.0;
    for (final o in known.values) {
      sx += o.dx;
      sy += o.dy;
    }
    centroid = Offset(sx / known.length, sy / known.length);
    for (final o in known.values) {
      final d = (o - centroid).distance;
      if (d > maxR) maxR = d;
    }
    maxR = math.max(maxR, 1);
  }

  final markers = <PeerMapMarker>[];
  for (var i = 0; i < list.length; i++) {
    final p = list[i];
    final label = p.displayName.isNotEmpty
        ? p.displayName
        : (p.id.length > 6 ? p.id.substring(0, 6) : p.id);

    Offset unit;
    var knownPos = false;
    final k = known[p.id];
    if (k != null && centroid != null) {
      final rel = (k - centroid) / maxR;
      unit = Offset(rel.dx, rel.dy);
      knownPos = true;
    } else {
      // RSSI → radius (stronger = closer). Stable angle from id hash.
      final r = _radiusFromRssi(p.rssi);
      final angle = _angleForId(p.id) + i * 0.15;
      unit = Offset(math.cos(angle) * r, math.sin(angle) * r);
    }

    markers.add(
      PeerMapMarker(
        id: p.id,
        label: label,
        position: unit,
        rssi: p.rssi,
        transports: p.transports,
        hasKnownPosition: knownPos,
      ),
    );
  }
  return markers;
}

double _radiusFromRssi(int? rssi) {
  if (rssi == null) return 0.55;
  // Map roughly -30..-95 dBm → 0.18..0.92
  final t = ((-30 - rssi) / 65).clamp(0.0, 1.0);
  return 0.18 + t * 0.74;
}

double _angleForId(String id) {
  var h = 0;
  for (final c in id.codeUnits) {
    h = 0x1fffffff & (h * 31 + c);
  }
  return (h % 360) * math.pi / 180;
}

/// Interactive local-peer radar map (you at center).
class PeerMapView extends StatelessWidget {
  final List<Peer> peers;
  final String? selectedPeerId;
  final ValueChanged<Peer>? onPeerTap;
  final double height;

  const PeerMapView({
    super.key,
    required this.peers,
    this.selectedPeerId,
    this.onPeerTap,
    this.height = 280,
  });

  @override
  Widget build(BuildContext context) {
    final markers = layoutPeerMap(peers);
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: height,
      width: double.infinity,
      child: Card(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: onPeerTap == null
                  ? null
                  : (details) {
                      final hit = _hitTest(
                        details.localPosition,
                        Size(constraints.maxWidth, constraints.maxHeight),
                        markers,
                      );
                      if (hit == null) return;
                      final peer = peers.cast<Peer?>().firstWhere(
                            (p) => p?.id == hit.id,
                            orElse: () => null,
                          );
                      if (peer != null) onPeerTap!(peer);
                    },
              child: CustomPaint(
                painter: _PeerMapPainter(
                  markers: markers,
                  selectedId: selectedPeerId,
                  selfColor: scheme.primary,
                  peerColor: scheme.tertiary,
                  selectedColor: scheme.error,
                  ringColor: scheme.outlineVariant,
                  labelStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                  hintStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                size: Size(constraints.maxWidth, constraints.maxHeight),
              ),
            );
          },
        ),
      ),
    );
  }

  static PeerMapMarker? _hitTest(
    Offset local,
    Size size,
    List<PeerMapMarker> markers,
  ) {
    final center = Offset(size.width / 2, size.height / 2);
    final scale = math.min(size.width, size.height) * 0.42;
    PeerMapMarker? best;
    var bestD = 28.0;
    for (final m in markers) {
      final p = center + m.position.scale(scale, scale);
      final d = (p - local).distance;
      if (d < bestD) {
        bestD = d;
        best = m;
      }
    }
    return best;
  }
}

class _PeerMapPainter extends CustomPainter {
  final List<PeerMapMarker> markers;
  final String? selectedId;
  final Color selfColor;
  final Color peerColor;
  final Color selectedColor;
  final Color ringColor;
  final TextStyle? labelStyle;
  final TextStyle? hintStyle;

  _PeerMapPainter({
    required this.markers,
    required this.selectedId,
    required this.selfColor,
    required this.peerColor,
    required this.selectedColor,
    required this.ringColor,
    this.labelStyle,
    this.hintStyle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final scale = math.min(size.width, size.height) * 0.42;

    // Background wash.
    final bg = Paint()
      ..shader = ui.Gradient.radial(
        center,
        scale * 1.15,
        [
          selfColor.withValues(alpha: 0.08),
          ringColor.withValues(alpha: 0.04),
          Colors.transparent,
        ],
        const [0.0, 0.55, 1.0],
      );
    canvas.drawRect(Offset.zero & size, bg);

    // Range rings.
    final ringPaint = Paint()
      ..color = ringColor.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final f in [0.33, 0.66, 1.0]) {
      canvas.drawCircle(center, scale * f, ringPaint);
    }

    // Crosshair.
    final axis = Paint()
      ..color = ringColor.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(center.dx - scale, center.dy),
      Offset(center.dx + scale, center.dy),
      axis,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - scale),
      Offset(center.dx, center.dy + scale),
      axis,
    );

    // Peers.
    for (final m in markers) {
      final p = center + m.position.scale(scale, scale);
      final selected = m.id == selectedId;
      final color = selected ? selectedColor : peerColor;

      // Soft glow.
      canvas.drawCircle(
        p,
        selected ? 16 : 12,
        Paint()..color = color.withValues(alpha: 0.2),
      );
      canvas.drawCircle(p, selected ? 8 : 6, Paint()..color = color);

      // Label.
      final tp = TextPainter(
        text: TextSpan(text: m.label, style: labelStyle),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 88);
      tp.paint(canvas, Offset(p.dx - tp.width / 2, p.dy + 10));
    }

    // Self.
    canvas.drawCircle(
      center,
      14,
      Paint()..color = selfColor.withValues(alpha: 0.25),
    );
    canvas.drawCircle(center, 7, Paint()..color = selfColor);
    final you = TextPainter(
      text:
          TextSpan(text: 'You', style: labelStyle?.copyWith(color: selfColor)),
      textDirection: TextDirection.ltr,
    )..layout();
    you.paint(canvas, Offset(center.dx - you.width / 2, center.dy + 12));

    // Empty hint.
    if (markers.isEmpty) {
      final tp = TextPainter(
        text: TextSpan(text: 'No peers in range', style: hintStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(center.dx - tp.width / 2, center.dy - scale * 0.5),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PeerMapPainter old) {
    return old.markers != markers ||
        old.selectedId != selectedId ||
        old.selfColor != selfColor ||
        old.peerColor != peerColor;
  }
}
