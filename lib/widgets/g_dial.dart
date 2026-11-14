import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../core/gforce.dart';

/// A g-force circle: the dot moves up when speeding up, down when braking,
/// and sideways in turns. Rings at 0.25 g steps up to [maxG]. When the
/// direction is not known yet, a ring shows the total g instead of a dot.
class GDial extends StatelessWidget {
  const GDial({super.key, required this.reading, this.maxG = 0.75, this.size = 200});

  final GReading? reading;
  final double maxG;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = reading;
    final label = r == null
        ? 'No g-force reading yet'
        : r.oriented
            ? 'G-force ${formatG(r.totalG)}'
            : 'G-force ${formatG(r.totalG)}, direction not known yet';
    return Semantics(
      label: label,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _GDialPainter(
            reading: r,
            maxG: maxG,
            line: c.border,
            text: c.textSubtle,
            dot: c.accent,
            labelStyle: context.text.labelSmall?.copyWith(color: c.textSubtle) ?? const TextStyle(fontSize: 11),
          ),
        ),
      ),
    );
  }
}

class _GDialPainter extends CustomPainter {
  _GDialPainter({
    required this.reading,
    required this.maxG,
    required this.line,
    required this.text,
    required this.dot,
    required this.labelStyle,
  });

  final GReading? reading;
  final double maxG;
  final Color line;
  final Color text;
  final Color dot;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 16;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = line;

    for (var g = 0.25; g <= maxG + 1e-9; g += 0.25) {
      canvas.drawCircle(center, radius * g / maxG, ring);
    }
    canvas.drawLine(center.translate(-radius, 0), center.translate(radius, 0), ring);
    canvas.drawLine(center.translate(0, -radius), center.translate(0, radius), ring);

    void label(String s, Offset at) {
      final tp = TextPainter(text: TextSpan(text: s, style: labelStyle), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
    }

    label('Accel', center.translate(0, -radius - 9));
    label('Brake', center.translate(0, radius + 9));
    label('L', center.translate(-radius - 9, 0));
    label('R', center.translate(radius + 9, 0));
    label('0.5', center.translate(radius * 0.5 / maxG + 10, -8));

    final r = reading;
    if (r == null) return;
    final long = r.longG, lat = r.latG;
    if (long == null || lat == null) {
      final pr = math.min(r.totalG / maxG, 1.0) * radius;
      canvas.drawCircle(
        center,
        pr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = dot,
      );
      return;
    }
    var offset = Offset(lat / maxG * radius, -long / maxG * radius);
    if (offset.distance > radius) offset = offset / offset.distance * radius;
    canvas.drawCircle(center + offset, 9, Paint()..color = dot);
  }

  @override
  bool shouldRepaint(_GDialPainter old) =>
      old.reading != reading || old.line != line || old.dot != dot || old.text != text || old.maxG != maxG;
}
