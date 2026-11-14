import 'trip.dart';

/// Speeds (m/s) sampled at [count] evenly spaced moments between the first and
/// last point, linearly interpolated, for the speed-over-time chart.
List<double> resampleSpeeds(List<TrackPoint> points, int count) => _resample(points, count, (p) => p.speedMs);

/// Altitudes (m) resampled like [resampleSpeeds], using only points that have
/// an altitude. Empty when fewer than two points have one.
List<double> resampleAltitudes(List<TrackPoint> points, int count) {
  final withAlt = [for (final p in points) if (p.altitude != null) p];
  if (withAlt.length < 2) return const [];
  return _resample(withAlt, count, (p) => p.altitude!);
}

/// Total climb and descent in metres. GPS altitude wobbles by several metres,
/// so a change only counts once it exceeds [hysteresisM] from the last turning
/// point.
({double climbM, double descentM, double minM, double maxM})? climbAndDescent(
  List<TrackPoint> points, {
  double hysteresisM = 5,
}) {
  final alts = [for (final p in points) if (p.altitude != null) p.altitude!];
  if (alts.length < 2) return null;
  var climb = 0.0, descent = 0.0;
  var ref = alts.first;
  var lo = alts.first, hi = alts.first;
  for (final a in alts.skip(1)) {
    if (a < lo) lo = a;
    if (a > hi) hi = a;
    final d = a - ref;
    if (d >= hysteresisM) {
      climb += d;
      ref = a;
    } else if (d <= -hysteresisM) {
      descent -= d;
      ref = a;
    }
  }
  return (climbM: climb, descentM: descent, minM: lo, maxM: hi);
}

List<double> _resample(List<TrackPoint> points, int count, double Function(TrackPoint) value) {
  if (points.isEmpty || count < 1) return const [];
  if (points.length == 1 || count == 1) return List.filled(count, value(points.first));
  final t0 = points.first.timeMs;
  final span = points.last.timeMs - t0;
  if (span <= 0) return List.filled(count, value(points.first));
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
    out.add(value(a) + (value(b) - value(a)) * f);
  }
  return out;
}
