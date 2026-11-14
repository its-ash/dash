import 'trip.dart';

/// Speeds (m/s) sampled at [count] evenly spaced moments between the first and
/// last point, linearly interpolated, for the speed-over-time chart.
List<double> resampleSpeeds(List<TrackPoint> points, int count) {
  if (points.isEmpty || count < 1) return const [];
  if (points.length == 1 || count == 1) return List.filled(count, points.first.speedMs);
  final t0 = points.first.timeMs;
  final span = points.last.timeMs - t0;
  if (span <= 0) return List.filled(count, points.first.speedMs);
  final out = <double>[];
  var i = 0;
  for (var k = 0; k < count; k++) {
    final t = t0 + span * k / (count - 1);
    while (i < points.length - 2 && points[i + 1].timeMs < t) {
      i++;
    }
    final a = points[i];
    final b = points[i + 1];
    final dt = b.timeMs - a.timeMs;
    final f = dt <= 0 ? 0.0 : ((t - a.timeMs) / dt).clamp(0.0, 1.0);
    out.add(a.speedMs + (b.speedMs - a.speedMs) * f);
  }
  return out;
}
