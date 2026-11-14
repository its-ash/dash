import 'gforce.dart';

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
    this.peakAccelG,
    this.peakBrakeG,
    this.peakTurnG,
    this.events = const [],
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

  /// Highest g-forces (positive values). Null for trips saved before Dash had
  /// the g-force meter.
  final double? peakAccelG;
  final double? peakBrakeG;
  final double? peakTurnG;

  /// Harsh acceleration, braking and cornering moments, in time order.
  final List<HarshEvent> events;

  bool get hasPeaks => peakAccelG != null || peakBrakeG != null || peakTurnG != null;

  /// A copy with the given peaks and harsh events.
  Trip withGForce(GPeaks p, List<HarshEvent> events) => Trip(
        id: id,
        startMs: startMs,
        endMs: endMs,
        distanceM: distanceM,
        durationMs: durationMs,
        movingMs: movingMs,
        maxSpeedMs: maxSpeedMs,
        points: points,
        peakAccelG: p.accelG,
        peakBrakeG: p.brakeG,
        peakTurnG: p.turnG,
        events: events,
      );

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
        peakAccelG: peakAccelG,
        peakBrakeG: peakBrakeG,
        peakTurnG: peakTurnG,
      );

  static double? _round(double? v) => v == null ? null : double.parse(v.toStringAsFixed(3));

  Map<String, Object?> toSummaryJson() => {
        'id': id,
        'start': startMs,
        'end': endMs,
        'dist': distanceM,
        'dur': durationMs,
        'mov': movingMs,
        'max': maxSpeedMs,
        if (peakAccelG != null) 'pa': _round(peakAccelG),
        if (peakBrakeG != null) 'pb': _round(peakBrakeG),
        if (peakTurnG != null) 'pt': _round(peakTurnG),
      };

  Map<String, Object?> toJson() => {
        ...toSummaryJson(),
        'pts': [for (final p in points) p.toJson()],
        if (events.isNotEmpty) 'ev': [for (final e in events) e.toJson()],
      };

  factory Trip.fromJson(Map<String, Object?> j) => Trip(
        id: j['id'] as String,
        startMs: (j['start'] as num).toInt(),
        endMs: (j['end'] as num).toInt(),
        distanceM: (j['dist'] as num).toDouble(),
        durationMs: (j['dur'] as num).toInt(),
        movingMs: (j['mov'] as num).toInt(),
        maxSpeedMs: (j['max'] as num).toDouble(),
        peakAccelG: (j['pa'] as num?)?.toDouble(),
        peakBrakeG: (j['pb'] as num?)?.toDouble(),
        peakTurnG: (j['pt'] as num?)?.toDouble(),
        points: [
          for (final p in (j['pts'] as List?) ?? const []) TrackPoint.fromJson((p as List).cast<Object?>()),
        ],
        events: [
          for (final e in (j['ev'] as List?) ?? const []) HarshEvent.fromJson((e as List).cast<Object?>()),
        ],
      );
}
