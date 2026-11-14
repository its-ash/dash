/// One recorded position of a trip.
class TrackPoint {
  const TrackPoint({required this.timeMs, required this.lat, required this.lon, required this.speedMs, this.altitude});

  final int timeMs;
  final double lat;
  final double lon;

  /// Smoothed speed in m/s.
  final double speedMs;
  final double? altitude;

  List<Object?> toJson() => [timeMs, lat, lon, double.parse(speedMs.toStringAsFixed(2)), altitude];

  factory TrackPoint.fromJson(List<Object?> j) => TrackPoint(
        timeMs: (j[0] as num).toInt(),
        lat: (j[1] as num).toDouble(),
        lon: (j[2] as num).toDouble(),
        speedMs: (j[3] as num).toDouble(),
        altitude: j.length > 4 ? (j[4] as num?)?.toDouble() : null,
      );
}

/// A finished trip. [points] is empty for list summaries.
class Trip {
  const Trip({
    required this.id,
    required this.startMs,
    required this.endMs,
    required this.distanceM,
    required this.durationMs,
    required this.movingMs,
    required this.maxSpeedMs,
    this.points = const [],
  });

  /// Unique id: the start time in milliseconds.
  final String id;
  final int startMs;
  final int endMs;
  final double distanceM;

  /// Recorded time without pauses.
  final int durationMs;

  /// Time spent above the stationary speed.
  final int movingMs;
  final double maxSpeedMs;
  final List<TrackPoint> points;

  /// Average speed while moving, in m/s.
  double get avgMovingSpeedMs => movingMs > 0 ? distanceM / (movingMs / 1000.0) : 0;

  /// Average speed over the whole trip including stops, in m/s.
  double get avgOverallSpeedMs => durationMs > 0 ? distanceM / (durationMs / 1000.0) : 0;

  Trip withoutPoints() => Trip(
        id: id,
        startMs: startMs,
        endMs: endMs,
        distanceM: distanceM,
        durationMs: durationMs,
        movingMs: movingMs,
        maxSpeedMs: maxSpeedMs,
      );

  Map<String, Object?> toSummaryJson() => {
        'id': id,
        'start': startMs,
        'end': endMs,
        'dist': distanceM,
        'dur': durationMs,
        'mov': movingMs,
        'max': maxSpeedMs,
      };

  Map<String, Object?> toJson() => {...toSummaryJson(), 'pts': [for (final p in points) p.toJson()]};

  factory Trip.fromJson(Map<String, Object?> j) => Trip(
        id: j['id'] as String,
        startMs: (j['start'] as num).toInt(),
        endMs: (j['end'] as num).toInt(),
        distanceM: (j['dist'] as num).toDouble(),
        durationMs: (j['dur'] as num).toInt(),
        movingMs: (j['mov'] as num).toInt(),
        maxSpeedMs: (j['max'] as num).toDouble(),
        points: [
          for (final p in (j['pts'] as List?) ?? const []) TrackPoint.fromJson((p as List).cast<Object?>()),
        ],
      );
}
