import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';

/// Simple 7-day bar chart built from plain widgets (no chart library needed).
class WeeklyBarChart extends StatelessWidget {
  final List<DayValue> days;
  final Color color;
  final double height;

  const WeeklyBarChart({super.key, required this.days, required this.color, this.height = 170});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxValue = days.map((d) => d.value).fold<double>(0, max);
    final compact = NumberFormat.compact();

    // Labels are measured first; the bars then share whatever height is left,
    // so the chart never overflows, whatever the phone's text size.
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final day in days)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  children: [
                    _label(compact.format(day.value), theme),
                    const SizedBox(height: 2),
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: maxValue == 0 ? 0.02 : max(0.02, day.value / maxValue),
                          widthFactor: 1,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    _label(DateFormat.E().format(day.day), theme),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// One-line label that shrinks to fit instead of wrapping or overflowing.
  Widget _label(String text, ThemeData theme) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(text, style: theme.textTheme.labelSmall, maxLines: 1),
    );
  }
}

/// Heart rate over the day as a line, positioned by time of day.
class HeartRateLine extends StatelessWidget {
  final List<HeartRatePoint> points;
  final Color color;

  const HeartRateLine({super.key, required this.points, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final first = points.first.time;
    final last = points.last.time;
    return Column(
      children: [
        SizedBox(
          height: 120,
          width: double.infinity,
          child: CustomPaint(
            painter: _LinePainter(
              points: points,
              color: color,
              gridColor: theme.dividerColor,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(DateFormat.jm().format(first), style: theme.textTheme.labelSmall),
            Text(DateFormat.jm().format(last), style: theme.textTheme.labelSmall),
          ],
        ),
      ],
    );
  }
}

class _LinePainter extends CustomPainter {
  final List<HeartRatePoint> points;
  final Color color;
  final Color gridColor;

  _LinePainter({required this.points, required this.color, required this.gridColor});

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 2; i++) {
      final y = size.height * i / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final start = points.first.time.millisecondsSinceEpoch.toDouble();
    final end = points.last.time.millisecondsSinceEpoch.toDouble();
    final span = max(end - start, 1.0);
    final bpms = points.map((p) => p.bpm);
    final low = bpms.reduce(min) - 5;
    final high = bpms.reduce(max) + 5;
    final range = max(high - low, 1.0);

    Offset toOffset(HeartRatePoint p) => Offset(
          size.width * (p.time.millisecondsSinceEpoch - start) / span,
          size.height * (1 - (p.bpm - low) / range),
        );

    final line = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;

    if (points.length == 1) {
      canvas.drawCircle(toOffset(points.first), 4, line..style = PaintingStyle.fill);
      return;
    }

    final path = Path()..moveTo(toOffset(points.first).dx, toOffset(points.first).dy);
    for (final p in points.skip(1)) {
      final o = toOffset(p);
      path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) =>
      old.points != points || old.color != color || old.gridColor != gridColor;
}