import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../core/units.dart';

/// Analog speedometer: a 270 degree dial with ticks, a coloured arc and a
/// needle that eases to the current speed.
class SpeedGauge extends StatelessWidget {
  const SpeedGauge({super.key, required this.speedMs, required this.unit, this.over = false, this.maxSpeed});

  final double speedMs;
  final SpeedUnit unit;
  final bool over;

  /// Full scale in [unit]; default is [SpeedUnit.gaugeMax].
  final int? maxSpeed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final max = (maxSpeed ?? unit.gaugeMax).toDouble();
    final value = unit.fromMs(speedMs < 0 ? 0 : speedMs);
    final fraction = (value / max).clamp(0.0, 1.0);
    final arc = over ? c.danger : c.accent;
    return Semantics(
      label: 'Speed ${formatSpeed(speedMs, unit)} ${unit.label}',
      child: AspectRatio(
        aspectRatio: 1,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: fraction),
          duration: context.motion(UiMotion.normal),
          curve: Curves.easeOut,
          builder: (context, f, _) => CustomPaint(
            painter: GaugePainter(
              fraction: f,
              max: max,
              arcColor: arc,
              trackColor: c.surfaceMuted,
              tickColor: c.borderStrong,
              labelColor: c.textMuted,
              needleColor: over ? c.danger : c.text,
              labelStyle: context.text.labelSmall ?? const TextStyle(fontSize: 11),
            ),
            child: Align(
              alignment: const Alignment(0, 0.62),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    formatSpeed(speedMs, unit),
                    style: context.text.displayMedium?.copyWith(
                      color: over ? c.danger : c.text,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(unit.label, style: context.text.labelLarge?.copyWith(color: c.textMuted)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints the dial. Exposed so it can be tested.
class GaugePainter extends CustomPainter {
  GaugePainter({
    required this.fraction,
    required this.max,
    required this.arcColor,
    required this.trackColor,
    required this.tickColor,
    required this.labelColor,
    required this.needleColor,
    required this.labelStyle,
  });

  final double fraction;
  final double max;
  final Color arcColor;
  final Color trackColor;
  final Color tickColor;
  final Color labelColor;
  final Color needleColor;
  final TextStyle labelStyle;

  static const startAngle = 3 * math.pi / 4; // 135 degrees, bottom left
  static const sweep = 3 * math.pi / 2; // 270 degrees

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 8;
    final stroke = radius * 0.12;
    final arcRect = Rect.fromCircle(center: center, radius: radius - stroke / 2);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = trackColor;
    canvas.drawArc(arcRect, startAngle, sweep, false, track);

    if (fraction > 0) {
      canvas.drawArc(arcRect, startAngle, sweep * fraction, false, track..color = arcColor);
    }

    final major = max <= 100 ? 10 : 20;
    final tick = Paint()
      ..color = tickColor
      ..strokeWidth = 2;
    for (var v = 0.0; v <= max + 0.001; v += major) {
      final a = startAngle + sweep * (v / max);
      final dir = Offset(math.cos(a), math.sin(a));
      final outer = radius - stroke - 4;
      canvas.drawLine(center + dir * outer, center + dir * (outer - radius * 0.07), tick);
      final tp = TextPainter(
        text: TextSpan(text: v.round().toString(), style: labelStyle.copyWith(color: labelColor)),
        textDirection: TextDirection.ltr,
      )..layout();
      final labelPos = center + dir * (outer - radius * 0.20);
      tp.paint(canvas, labelPos - Offset(tp.width / 2, tp.height / 2));
    }

    final needleAngle = startAngle + sweep * fraction;
    final needleDir = Offset(math.cos(needleAngle), math.sin(needleAngle));
    canvas.drawLine(
      center,
      center + needleDir * (radius - stroke - radius * 0.12),
      Paint()
        ..color = needleColor
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(center, radius * 0.06, Paint()..color = needleColor);
  }

  @override
  bool shouldRepaint(GaugePainter old) =>
      old.fraction != fraction ||
      old.max != max ||
      old.arcColor != arcColor ||
      old.trackColor != trackColor ||
      old.needleColor != needleColor ||
      old.labelColor != labelColor;
}
