import 'dart:math' as math;

/// Standard gravity, m/s².
const double gravityMs2 = 9.80665;

/// Where a g-force reading comes from.
enum GSource { sensor, gps }

/// One g-force reading in the car's frame.
class GReading {
  const GReading({required this.totalG, required this.source, this.longG, this.latG});

  /// Along the direction of travel: positive when speeding up, negative when
  /// braking. Null while the sensor does not know yet which way is forward.
  final double? longG;

  /// Sideways: positive when the car turns right, negative when it turns
  /// left. Null while the direction is unknown.
  final double? latG;

  /// Horizontal g in any direction.
  final double totalG;
  final GSource source;

  bool get oriented => longG != null && latG != null;

  static const zero = GReading(totalG: 0, source: GSource.gps, longG: 0, latG: 0);
}

/// One averaged accelerometer window from Android, in the phone's frame
/// (m/s²): [x], [y], [z] is acceleration without gravity, [gx], [gy], [gz]
/// is gravity (pointing up, as Android reports it).
class AccelSample {
  const AccelSample({
    required this.timeMs,
    required this.x,
    required this.y,
    required this.z,
    required this.gx,
    required this.gy,
    required this.gz,
  });

  final int timeMs;
  final double x, y, z, gx, gy, gz;

  factory AccelSample.fromJson(Map<String, Object?> m) {
    double d(String k) => (m[k] as num?)?.toDouble() ?? 0;
    return AccelSample(
      timeMs: (m['t'] as num?)?.toInt() ?? 0,
      x: d('x'),
      y: d('y'),
      z: d('z'),
      gx: d('gx'),
      gy: d('gy'),
      gz: d('gz'),
    );
  }
}

class _V {
  const _V(this.x, this.y, this.z);
  final double x, y, z;
  static const zero = _V(0, 0, 0);

  _V operator +(_V o) => _V(x + o.x, y + o.y, z + o.z);
  _V operator -(_V o) => _V(x - o.x, y - o.y, z - o.z);
  _V operator *(double k) => _V(x * k, y * k, z * k);
  double dot(_V o) => x * o.x + y * o.y + z * o.z;
  _V cross(_V o) => _V(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double get length => math.sqrt(dot(this));
  _V get unit => this * (1 / length);
}

/// G-force from the accelerometer. Gravity is removed and only the
/// horizontal part is kept. Which way is forward is learned from GPS: when
/// GPS sees the car speed up or slow down, [learn] lines up the sensor's
/// horizontal push with it. Until then only [GReading.totalG] is known.
///
/// If the phone moves in its mount (gravity turns by more than
/// [remountDegrees]), the learned direction is dropped and learned again.
class SensorGMeter {
  SensorGMeter({this.tauMs = 300, this.remountDegrees = 20, this.minLearnMs2 = 0.6, this.learnWeight = 4});

  /// Smoothing time constant for the displayed value.
  final double tauMs;
  final double remountDegrees;

  /// GPS acceleration below this (m/s²) is too small to learn from.
  final double minLearnMs2;

  /// Sum of squared GPS accelerations (m²/s⁴) needed before forward is trusted.
  final double learnWeight;

  _V? _up;
  _V _h = _V.zero;
  int? _lastMs;
  _V _windowSum = _V.zero;
  int _windowN = 0;
  _V _corr = _V.zero;
  double _weight = 0;
  _V? _forward;

  bool get oriented => _forward != null;

  /// Forgets the learned forward direction.
  void resetOrientation() {
    _corr = _V.zero;
    _weight = 0;
    _forward = null;
    _windowSum = _V.zero;
    _windowN = 0;
  }

  GReading feed(AccelSample s) {
    final g = _V(s.gx, s.gy, s.gz);
    if (g.length < 1) return reading;
    final up = g.unit;
    final prevUp = _up;
    if (prevUp != null && up.dot(prevUp) < math.cos(remountDegrees * math.pi / 180)) {
      resetOrientation();
      _h = _V.zero;
    }
    _up = up;

    final a = _V(s.x, s.y, s.z);
    final h = a - up * a.dot(up);
    final last = _lastMs;
    _lastMs = s.timeMs;
    if (last == null) {
      _h = h;
    } else {
      final dt = (s.timeMs - last).clamp(1, 1000).toDouble();
      _h = _h + (h - _h) * (dt / (tauMs + dt));
    }

    _windowSum = _windowSum + h;
    _windowN++;
    return reading;
  }

  /// Called on each GPS fix with the GPS acceleration along the direction of
  /// travel (m/s²) since the previous fix. Pairs it with the mean sensor
  /// reading over the same second.
  void learn(double gpsLongMs2) {
    final n = _windowN;
    final mean = n == 0 ? null : _windowSum * (1 / n);
    _windowSum = _V.zero;
    _windowN = 0;
    final up = _up;
    if (mean == null || up == null || gpsLongMs2.abs() < minLearnMs2) return;

    _corr = _corr + mean * gpsLongMs2;
    _weight += gpsLongMs2 * gpsLongMs2;
    final horizontal = _corr - up * _corr.dot(up);
    if (_weight >= learnWeight && horizontal.length > 1e-6) _forward = horizontal.unit;
  }

  GReading get reading {
    final total = _h.length / gravityMs2;
    final f = _forward;
    final up = _up;
    if (f == null || up == null) return GReading(totalG: total, source: GSource.sensor);
    final right = f.cross(up);
    return GReading(
      totalG: total,
      source: GSource.sensor,
      longG: _h.dot(f) / gravityMs2,
      latG: _h.dot(right) / gravityMs2,
    );
  }
}

/// G-force from GPS alone: speed change for acceleration and braking,
/// speed × turn rate for cornering. About one reading per second, smoothed by
/// the speed filter, so it shows sustained forces but not short jolts.
class GpsGMeter {
  GpsGMeter({this.maxGapMs = 3000, this.minTurnSpeedMs = 4, this.maxG = 1.5});

  final int maxGapMs;

  /// Below this speed the GPS bearing is too noisy for cornering.
  final double minTurnSpeedMs;

  /// Readings above this are GPS glitches and are dropped.
  final double maxG;

  int? _t;
  double? _v;
  double? _bearing;

  /// Acceleration along the travel direction from the last [feed], m/s².
  double? lastLongMs2;

  void reset() {
    _t = null;
    _v = null;
    _bearing = null;
    lastLongMs2 = null;
  }

  /// Feeds one filtered fix. Returns null for the first fix or after a gap.
  GReading? feed({required int timeMs, required double speedMs, double? bearing}) {
    final pt = _t, pv = _v, pb = _bearing;
    _t = timeMs;
    _v = speedMs;
    _bearing = bearing;
    lastLongMs2 = null;
    if (pt == null || pv == null) return null;
    final dtMs = timeMs - pt;
    if (dtMs <= 0 || dtMs > maxGapMs) return null;
    final dt = dtMs / 1000.0;

    final long = (speedMs - pv) / dt;
    var lat = 0.0;
    if (bearing != null && pb != null && speedMs >= minTurnSpeedMs && pv >= minTurnSpeedMs) {
      var d = (bearing - pb) % 360;
      if (d > 180) d -= 360;
      if (d < -180) d += 360;
      lat = speedMs * (d * math.pi / 180) / dt;
    }
    final longG = long / gravityMs2;
    final latG = lat / gravityMs2;
    if (longG.abs() > maxG || latG.abs() > maxG) return null;
    lastLongMs2 = long;
    return GReading(
      totalG: math.sqrt(longG * longG + latG * latG),
      source: GSource.gps,
      longG: longG,
      latG: latG,
    );
  }
}

/// Highest g-forces of a trip, all positive values.
class GPeaks {
  GPeaks({this.accelG = 0, this.brakeG = 0, this.turnG = 0});

  double accelG;
  double brakeG;
  double turnG;

  bool get isEmpty => accelG == 0 && brakeG == 0 && turnG == 0;

  void add(GReading r) {
    final long = r.longG, lat = r.latG;
    if (long == null || lat == null) return;
    if (long > accelG) accelG = long;
    if (-long > brakeG) brakeG = -long;
    if (lat.abs() > turnG) turnG = lat.abs();
  }

  void reset() {
    accelG = 0;
    brakeG = 0;
    turnG = 0;
  }

  GPeaks merged(GPeaks o) => GPeaks(
        accelG: math.max(accelG, o.accelG),
        brakeG: math.max(brakeG, o.brakeG),
        turnG: math.max(turnG, o.turnG),
      );
}

/// A harsh driving moment, placed on the route.
enum HarshKind {
  accel('Hard acceleration', 0.30),
  brake('Hard braking', 0.35),
  turn('Sharp cornering', 0.40);

  const HarshKind(this.label, this.thresholdG);
  final String label;

  /// G-force at or above which a moment counts as harsh.
  final double thresholdG;
}

class HarshEvent {
  const HarshEvent({required this.timeMs, required this.lat, required this.lon, required this.kind, required this.g});

  final int timeMs;
  final double lat;
  final double lon;
  final HarshKind kind;

  /// Strength, positive.
  final double g;

  List<Object> toJson() => [timeMs, lat, lon, kind.index, double.parse(g.toStringAsFixed(3))];

  factory HarshEvent.fromJson(List<Object?> j) => HarshEvent(
        timeMs: (j[0] as num).toInt(),
        lat: (j[1] as num).toDouble(),
        lon: (j[2] as num).toDouble(),
        kind: HarshKind.values[(j[3] as num).toInt().clamp(0, HarshKind.values.length - 1)],
        g: (j[4] as num).toDouble(),
      );
}

/// Turns g-force readings into [HarshEvent]s. Readings of the same kind within
/// [mergeMs] are one event (the strongest one is kept).
class HarshDetector {
  HarshDetector({this.mergeMs = 5000});

  final int mergeMs;
  final List<HarshEvent> events = [];

  void add(GReading r, {required int timeMs, required double lat, required double lon}) {
    final long = r.longG, lat0 = r.latG;
    if (long == null || lat0 == null) return;
    final strengths = {HarshKind.accel: long, HarshKind.brake: -long, HarshKind.turn: lat0.abs()};
    strengths.forEach((kind, g) {
      if (g < kind.thresholdG) return;
      _put(HarshEvent(timeMs: timeMs, lat: lat, lon: lon, kind: kind, g: g));
    });
  }

  void _put(HarshEvent e) {
    for (var i = events.length - 1; i >= 0; i--) {
      final o = events[i];
      if (o.kind != e.kind) continue;
      if ((e.timeMs - o.timeMs).abs() > mergeMs) continue;
      if (e.g > o.g) events[i] = e;
      return;
    }
    events.add(e);
  }

  void reset() => events.clear();
}

/// Both lists as one, time ordered, with near-duplicates of the same kind
/// merged (for example the same braking seen by GPS and the accelerometer).
List<HarshEvent> mergeHarshEvents(List<HarshEvent> a, List<HarshEvent> b, {int mergeMs = 5000}) {
  final all = [...a, ...b]..sort((x, y) => x.timeMs.compareTo(y.timeMs));
  final d = HarshDetector(mergeMs: mergeMs);
  for (final e in all) {
    d._put(e);
  }
  return d.events;
}

/// `0.32 g`.
String formatG(double g) => '${g.abs().toStringAsFixed(2)} g';
