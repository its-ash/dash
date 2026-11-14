/// One raw location reading from the phone's GPS.
class GpsFix {
  const GpsFix({
    required this.timeMs,
    required this.lat,
    required this.lon,
    this.altitude,
    this.speed,
    this.accuracy,
    this.bearing,
  });

  /// Milliseconds since the Unix epoch.
  final int timeMs;
  final double lat;
  final double lon;

  /// Metres above sea level, when known.
  final double? altitude;

  /// Metres per second reported by the receiver (Doppler based), when known.
  final double? speed;

  /// Horizontal accuracy radius in metres, when known.
  final double? accuracy;

  /// Direction of travel in degrees, when known.
  final double? bearing;

  Map<String, Object?> toJson() => {
        't': timeMs,
        'la': lat,
        'lo': lon,
        if (altitude != null) 'al': altitude,
        if (speed != null) 'sp': speed,
        if (accuracy != null) 'ac': accuracy,
        if (bearing != null) 'be': bearing,
      };

  factory GpsFix.fromJson(Map<String, Object?> j) => GpsFix(
        timeMs: (j['t'] as num).toInt(),
        lat: (j['la'] as num).toDouble(),
        lon: (j['lo'] as num).toDouble(),
        altitude: (j['al'] as num?)?.toDouble(),
        speed: (j['sp'] as num?)?.toDouble(),
        accuracy: (j['ac'] as num?)?.toDouble(),
        bearing: (j['be'] as num?)?.toDouble(),
      );
}

/// How good the GPS signal is right now, for the status chip.
enum GpsStatus { searching, weak, good }

/// `searching` when no fix arrived for [staleMs] or the accuracy is unknown,
/// `weak` when the accuracy radius is worse than [weakAccuracyM].
GpsStatus gpsStatusFor({
  required double? accuracy,
  required int? ageMs,
  int staleMs = 5000,
  double weakAccuracyM = 20,
}) {
  if (ageMs == null || ageMs > staleMs) return GpsStatus.searching;
  if (accuracy == null || accuracy > weakAccuracyM) return GpsStatus.weak;
  return GpsStatus.good;
}
