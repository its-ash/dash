import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../core/geo.dart';
import '../core/gforce.dart';
import '../core/trip.dart';
import '../core/units.dart';

/// Sequential speed colors: one hue (the accent), light for slow and dark
/// for fast in light mode; dim for slow and bright for fast in dark mode, so
/// fast always stands out from the route background.
({Color slow, Color fast}) speedRamp(BuildContext context) {
  final c = context.colors;
  final dark = Theme.of(context).brightness == Brightness.dark;
  return dark
      ? (slow: Color.lerp(c.surfaceMuted, c.accent, 0.35)!, fast: Color.lerp(c.accent, Colors.white, 0.45)!)
      : (slow: Color.lerp(c.surfaceMuted, c.accent, 0.30)!, fast: Color.lerp(c.accent, Colors.black, 0.35)!);
}

/// Letter drawn in a harsh-event marker, so the kind never relies on color.
String harshGlyph(HarshKind k) => switch (k) {
      HarshKind.accel => 'A',
      HarshKind.brake => 'B',
      HarshKind.turn => 'C',
    };

/// A trip's route as a plain polyline (no map tiles, works offline). North is
/// up. The line is colored by speed (see [speedRamp]); harsh moments are
/// lettered markers. Green dot = start, red dot = end.
class RouteView extends StatelessWidget {
  const RouteView({super.key, required this.points, this.events = const [], this.height = 260});

  final List<TrackPoint> points;
  final List<HarshEvent> events;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ramp = speedRamp(context);
    final brakes = events.where((e) => e.kind == HarshKind.brake).length;
    return Semantics(
      label: 'Route of the trip, colored by speed'
          '${events.isEmpty ? '' : ', ${events.length} harsh moments marked ($brakes hard braking)'}',
      child: Container(
        height: height,
        width: double.infinity,
        decoration: BoxDecoration(
          color: c.surfaceMuted,
          borderRadius: UiRadius.all(UiRadius.lg),
        ),
        child: ClipRRect(
          borderRadius: UiRadius.all(UiRadius.lg),
          child: CustomPaint(
            painter: RoutePainter(
              points: points,
              events: events,
              slowColor: ramp.slow,
              fastColor: ramp.fast,
              startColor: c.success,
              endColor: c.danger,
              gridColor: c.border,
              surfaceColor: c.surface,
              markerColor: c.warning,
            ),
          ),
        ),
      ),
    );
  }
}

/// Speed scale under the route: a slow-to-fast bar with the trip's range, and
/// the marker letters when there are harsh moments.
class RouteLegend extends StatelessWidget {
  const RouteLegend({super.key, required this.points, required this.unit, this.events = const []});

  final List<TrackPoint> points;
  final List<HarshEvent> events;
  final SpeedUnit unit;

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) return const SizedBox.shrink();
    final c = context.colors;
    final ramp = speedRamp(context);
    final style = context.text.bodySmall?.copyWith(color: c.textMuted);
    final maxMs = points.map((p) => p.speedMs).reduce((a, b) => a > b ? a : b);
    final kinds = {for (final e in events) e.kind}.toList()..sort((a, b) => a.index.compareTo(b.index));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('0', style: style),
            const UiGap(UiSpace.sm),
            Expanded(
              child: Container(
                height: 8,
                decoration: BoxDecoration(
                  borderRadius: UiRadius.all(4),
                  gradient: LinearGradient(colors: [ramp.slow, ramp.fast]),
                ),
              ),
            ),
            const UiGap(UiSpace.sm),
            Text('${formatSpeed(maxMs, unit)} ${unit.label}', style: style),
          ],
        ),
        if (kinds.isNotEmpty) ...[
          const UiGap(UiSpace.sm),
          Wrap(
            spacing: UiSpace.md,
            runSpacing: UiSpace.xs,
            children: [
              for (final k in kinds)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HarshMarker(kind: k, size: 18),
                    const UiGap(UiSpace.xs),
                    Text(k.label, style: style),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// The lettered harsh-event marker, for the legend and the event list.
class HarshMarker extends StatelessWidget {
  const HarshMarker({super.key, required this.kind, this.size = 20});

  final HarshKind kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.warning,
        shape: BoxShape.circle,
        border: Border.all(color: c.surface, width: 2),
      ),
      child: Text(
        harshGlyph(kind),
        style: TextStyle(fontSize: size * 0.5, fontWeight: FontWeight.w700, color: Colors.black, height: 1),
      ),
    );
  }
}

class RoutePainter extends CustomPainter {
  RoutePainter({
    required this.points,
    required this.slowColor,
    required this.fastColor,
    required this.startColor,
    required this.endColor,
    required this.gridColor,
    required this.surfaceColor,
    required this.markerColor,
    this.events = const [],
  });

  final List<TrackPoint> points;
  final List<HarshEvent> events;
  final Color slowColor;
  final Color fastColor;
  final Color startColor;
  final Color endColor;
  final Color gridColor;
  final Color surfaceColor;
  final Color markerColor;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      canvas.drawLine(Offset(size.width * i / 4, 0), Offset(size.width * i / 4, size.height), grid);
      canvas.drawLine(Offset(0, size.height * i / 4), Offset(size.width, size.height * i / 4), grid);
    }
    if (points.isEmpty) return;
    final proj = projectRoute(
      [for (final p in points) (p.lat, p.lon), for (final e in events) (e.lat, e.lon)],
      width: size.width,
      height: size.height,
      padding: 20,
    );
    final offsets = [for (final p in proj.take(points.length)) Offset(p.$1, p.$2)];
    final eventOffsets = [for (final p in proj.skip(points.length)) Offset(p.$1, p.$2)];

    if (offsets.length > 1) {
      var maxMs = 0.0;
      for (final p in points) {
        if (p.speedMs > maxMs) maxMs = p.speedMs;
      }
      final line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;
      for (var i = 1; i < offsets.length; i++) {
        final v = (points[i - 1].speedMs + points[i].speedMs) / 2;
        final t = maxMs <= 0 ? 0.0 : (v / maxMs).clamp(0.0, 1.0);
        line.color = Color.lerp(slowColor, fastColor, t)!;
        canvas.drawLine(offsets[i - 1], offsets[i], line);
      }
    }
    canvas.drawCircle(offsets.first, 7, Paint()..color = startColor);
    if (offsets.length > 1) canvas.drawCircle(offsets.last, 7, Paint()..color = endColor);

    for (var i = 0; i < eventOffsets.length; i++) {
      final o = eventOffsets[i];
      canvas.drawCircle(o, 11, Paint()..color = surfaceColor);
      canvas.drawCircle(o, 9, Paint()..color = markerColor);
      final tp = TextPainter(
        text: TextSpan(
          text: harshGlyph(events[i].kind),
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.black, height: 1),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, o - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(RoutePainter old) =>
      old.points != points || old.events != events || old.slowColor != slowColor || old.fastColor != fastColor;
}
