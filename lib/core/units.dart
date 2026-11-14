/// Speed unit shown in the app. Speeds are stored in metres per second.
enum SpeedUnit {
  kmh('km/h', 'km', 3.6, 1000.0, 200),
  mph('mph', 'mi', 2.2369362920544, 1609.344, 120),
  knots('kn', 'nm', 1.9438444924406, 1852.0, 100);

  const SpeedUnit(this.label, this.distanceLabel, this._perMs, this._metersPerDistance, this.gaugeMax);

  /// Short unit text, e.g. `km/h`.
  final String label;

  /// Matching distance unit: km, mi or nm.
  final String distanceLabel;

  /// Default full scale of the analog gauge, in this unit.
  final int gaugeMax;

  final double _perMs;
  final double _metersPerDistance;

  /// Converts metres per second to this unit.
  double fromMs(double ms) => ms * _perMs;

  /// Converts a value in this unit to metres per second.
  double toMs(double value) => value / _perMs;

  /// Converts metres to this unit's distance (km, mi or nm).
  double distanceFromMeters(double m) => m / _metersPerDistance;

  static SpeedUnit fromName(String? name) {
    for (final u in values) {
      if (u.name == name) return u;
    }
    return SpeedUnit.kmh;
  }
}

/// Speed as a whole number for the big readout, never negative.
String formatSpeed(double ms, SpeedUnit unit) {
  final v = unit.fromMs(ms < 0 ? 0 : ms);
  return v.round().toString();
}

/// Distance with a sensible number of decimals, e.g. `12.40 km`.
String formatDistance(double meters, SpeedUnit unit) {
  final d = unit.distanceFromMeters(meters);
  final digits = d >= 100 ? 0 : (d >= 10 ? 1 : 2);
  return '${d.toStringAsFixed(digits)} ${unit.distanceLabel}';
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// `Nov 13, 2026 14:05` (24 hour clock, local time of [d]).
String formatDateTime(DateTime d) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${_months[d.month - 1]} ${d.day}, ${d.year} ${two(d.hour)}:${two(d.minute)}';
}

/// `h:mm:ss`, or `m:ss` below one hour.
String formatDuration(Duration d) {
  final total = d.inSeconds < 0 ? 0 : d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final ss = s.toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
  return '$m:$ss';
}
