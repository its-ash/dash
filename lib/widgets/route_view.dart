import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../core/geo.dart';
import '../core/trip.dart';

/// A trip's route as a plain polyline (no map tiles, works offline). North is
/// up. Green dot = start, red dot = end.
class RouteView extends StatelessWidget {
  const RouteView({super.key, required this.points, this.height = 260});

  final List<TrackPoint> points;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: 'Route of the trip',
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
              lineColor: c.accent,
              startColor: c.success,
              endColor: c.danger,
              gridColor: c.border,
            ),
          ),
        ),
      ),
    );
  }
}

class RoutePainter extends CustomPainter {
  RoutePainter({
    required this.points,
    required this.lineColor,
    required this.startColor,
    required this.endColor,
    required this.gridColor,
  });

  final List<TrackPoint> points;
  final Color lineColor;
  final Color startColor;
  final Color endColor;
  final Color gridColor;

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
      [for (final p in points) (p.lat, p.lon)],
      width: size.width,
      height: size.height,
      padding: 20,
    );
    final offsets = [for (final p in proj) Offset(p.$1, p.$2)];
    if (offsets.length > 1) {
      final path = Path()..moveTo(offsets.first.dx, offsets.first.dy);
      for (final o in offsets.skip(1)) {
        path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = lineColor,
      );
    }
    canvas.drawCircle(offsets.first, 7, Paint()..color = startColor);
    if (offsets.length > 1) canvas.drawCircle(offsets.last, 7, Paint()..color = endColor);
  }

  @override
  bool shouldRepaint(RoutePainter old) => old.points != points || old.lineColor != lineColor;
}
