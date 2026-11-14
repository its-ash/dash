/// GNSS satellites the phone can see, from Android's `GnssStatus`.
class SatelliteCount {
  const SatelliteCount({required this.inView, required this.used});

  /// Satellites whose signal the receiver picks up (all constellations).
  final int inView;

  /// Satellites used to compute the current position.
  final int used;

  factory SatelliteCount.fromJson(Map<String, Object?> m) =>
      SatelliteCount(inView: (m['v'] as num?)?.toInt() ?? 0, used: (m['u'] as num?)?.toInt() ?? 0);

  /// e.g. `9 used of 27`.
  String get label => '$used used of $inView';

  @override
  bool operator ==(Object other) => other is SatelliteCount && other.inView == inView && other.used == used;

  @override
  int get hashCode => Object.hash(inView, used);
}
