import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:core/core.dart';

/// Formats a duration like Task Manager: `00:04:12` or `1:02:03:04` (d:h:m:s).
String formatUptime(Duration d) {
  final days = d.inDays;
  final h = d.inHours.remainder(24);
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  String two(int n) => n.toString().padLeft(2, '0');
  if (days > 0) return '$days:${two(h)}:${two(m)}:${two(s)}';
  return '${two(h)}:${two(m)}:${two(s)}';
}

String formatClock(DateTime t) {
  final l = t.toLocal();
  final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
  final m = l.minute.toString().padLeft(2, '0');
  final s = l.second.toString().padLeft(2, '0');
  final ap = l.hour >= 12 ? 'PM' : 'AM';
  return '$h:$m:$s $ap';
}

/// Multi-series sparkline / area chart over a time window (Task Manager style).
class TimeSeriesChart extends StatelessWidget {
  final List<StatsSample> samples;
  final List<TimeSeriesLine> lines;
  final double height;
  final String? title;
  final String? subtitle;

  const TimeSeriesChart({
    super.key,
    required this.samples,
    required this.lines,
    this.height = 120,
    this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title!,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            SizedBox(
              height: height,
              child: CustomPaint(
                painter: _TimeSeriesPainter(
                  samples: samples,
                  lines: lines,
                  gridColor: scheme.outlineVariant.withValues(alpha: 0.5),
                  axisLabelStyle:
                      Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontSize: 10,
                          ),
                ),
                size: Size.infinite,
              ),
            ),
            if (lines.length > 1) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  for (final line in lines)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: line.color,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          line.label,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

final class TimeSeriesLine {
  final String label;
  final Color color;
  final double Function(StatsSample) value;
  final bool fill;

  const TimeSeriesLine({
    required this.label,
    required this.color,
    required this.value,
    this.fill = true,
  });
}

class _TimeSeriesPainter extends CustomPainter {
  final List<StatsSample> samples;
  final List<TimeSeriesLine> lines;
  final Color gridColor;
  final TextStyle? axisLabelStyle;

  _TimeSeriesPainter({
    required this.samples,
    required this.lines,
    required this.gridColor,
    this.axisLabelStyle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final chart = Rect.fromLTWH(0, 0, size.width, size.height - 14);
    if (chart.width <= 0 || chart.height <= 0) return;

    // Grid.
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = chart.top + chart.height * i / 3;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), grid);
    }

    if (samples.length < 2) {
      final tp = TextPainter(
        text: TextSpan(text: 'Collecting…', style: axisLabelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(
          chart.center.dx - tp.width / 2,
          chart.center.dy - tp.height / 2,
        ),
      );
      return;
    }

    var maxV = 0.0;
    for (final s in samples) {
      for (final line in lines) {
        maxV = math.max(maxV, line.value(s));
      }
    }
    if (maxV < 0.5) maxV = 1.0; // floor for quiet systems
    maxV *= 1.15;

    for (final line in lines) {
      final path = Path();
      final fillPath = Path();
      for (var i = 0; i < samples.length; i++) {
        final x = chart.left + chart.width * i / (samples.length - 1);
        final v = line.value(samples[i]).clamp(0.0, maxV);
        final y = chart.bottom - chart.height * (v / maxV);
        if (i == 0) {
          path.moveTo(x, y);
          fillPath.moveTo(x, chart.bottom);
          fillPath.lineTo(x, y);
        } else {
          path.lineTo(x, y);
          fillPath.lineTo(x, y);
        }
      }
      fillPath.lineTo(chart.right, chart.bottom);
      fillPath.close();

      if (line.fill) {
        canvas.drawPath(
          fillPath,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                line.color.withValues(alpha: 0.35),
                line.color.withValues(alpha: 0.02),
              ],
            ).createShader(chart),
        );
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = line.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }

    // Time axis labels.
    final first = samples.first.at.toLocal();
    final last = samples.last.at.toLocal();
    String fmt(DateTime t) =>
        '${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
    final left = TextPainter(
      text: TextSpan(text: fmt(first), style: axisLabelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final right = TextPainter(
      text: TextSpan(text: fmt(last), style: axisLabelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    left.paint(canvas, Offset(chart.left, chart.bottom + 2));
    right.paint(
      canvas,
      Offset(chart.right - right.width, chart.bottom + 2),
    );

    // Max scale label.
    final maxLabel = TextPainter(
      text: TextSpan(
        text: maxV >= 10 ? maxV.toStringAsFixed(0) : maxV.toStringAsFixed(1),
        style: axisLabelStyle,
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    maxLabel.paint(canvas, Offset(chart.left + 2, chart.top + 2));
  }

  @override
  bool shouldRepaint(covariant _TimeSeriesPainter old) =>
      old.samples != samples || old.lines != lines;
}

/// Compact KPI tile with optional sparkline (like Task Manager performance cards).
class MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final IconData icon;
  final Color? accent;
  final List<double>? sparkline;

  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    required this.icon,
    this.accent,
    this.sparkline,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = accent ?? scheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: color,
                      ),
                ),
                if (unit != null) ...[
                  const SizedBox(width: 4),
                  Text(
                    unit!,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ],
            ),
            if (sparkline != null && sparkline!.length >= 2) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 28,
                width: double.infinity,
                child: CustomPaint(
                  painter: _SparkPainter(
                    values: sparkline!,
                    color: color,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  final List<double> values;
  final Color color;

  _SparkPainter({required this.values, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    var maxV = values.reduce(math.max);
    if (maxV <= 0) maxV = 1;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final y = size.height * (1 - (values[i] / maxV).clamp(0.0, 1.0));
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) =>
      old.values != values || old.color != color;
}

/// Process-style row for a transport or peer (name · activity · status).
class ActivityRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final double activity; // 0..1 bar
  final Color? color;
  final bool active;

  const ActivityRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.activity = 0,
    this.color,
    this.active = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = color ?? scheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: active ? c : scheme.outline),
          const SizedBox(width: 10),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: activity.clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: scheme.surfaceContainerHighest,
                color: active ? c : scheme.outlineVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 40,
            child: Text(
              '${(activity * 100).clamp(0, 100).toStringAsFixed(0)}%',
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
