import 'dart:convert';

import 'fix_filter.dart';
import 'gps_fix.dart';
import 'trip.dart';

/// One line of the track log the Android service writes while a trip runs.
sealed class TrackEvent {
  const TrackEvent();
}

class StartEvent extends TrackEvent {
  const StartEvent(this.timeMs);
  final int timeMs;
}

class PauseEvent extends TrackEvent {
  const PauseEvent(this.timeMs);
  final int timeMs;
}

class ResumeEvent extends TrackEvent {
  const ResumeEvent(this.timeMs);
  final int timeMs;
}

class FixEvent extends TrackEvent {
  const FixEvent(this.fix);
  final GpsFix fix;
}

/// Parses the JSON-lines track log. Broken lines (for example a half written
/// last line after the process was killed) are skipped.
List<TrackEvent> parseTrackLog(String content) {
  final events = <TrackEvent>[];
  for (final line in const LineSplitter().convert(content)) {
    final text = line.trim();
    if (text.isEmpty) continue;
    try {
      final j = (jsonDecode(text) as Map).cast<String, Object?>();
      final e = j['e'];
      if (e == 'start') {
        events.add(StartEvent((j['t'] as num).toInt()));
      } else if (e == 'pause') {
        events.add(PauseEvent((j['t'] as num).toInt()));
      } else if (e == 'resume') {
        events.add(ResumeEvent((j['t'] as num).toInt()));
      } else if (j.containsKey('la')) {
        events.add(FixEvent(GpsFix.fromJson(j)));
      }
    } catch (_) {
      continue;
    }
  }
  return events;
}

/// Builds trip statistics from fixes: distance, moving time, max and average
/// speed, with pause support. All time comes from the fix and event
/// timestamps, so the same log always gives the same trip.
class TripRecorder {
  TripRecorder({FixFilter? filter, this.maxPoints = 1500, this.idleSampleMs = 5000})
      : _filter = filter ?? FixFilter();

  final FixFilter _filter;

  /// Most points kept in the finished trip (the rest is thinned out).
  final int maxPoints;

  /// While standing still, at most one point is kept per this many ms.
  final int idleSampleMs;

  final List<TrackPoint> _points = [];
  int? _startMs;
  bool _paused = false;
  int _pausedTotalMs = 0;
  int _pausedSinceMs = 0;
  int _lastEventMs = 0;
  int? _prevFixMs;
  int _lastPointMs = -1 << 40;
  double _distanceM = 0;
  int _movingMs = 0;
  double _maxSpeedMs = 0;
  double _speedMs = 0;
  double? _altitude;
  double? _bearing;

  bool get started => _startMs != null;
  bool get paused => _paused;
  int? get startMs => _startMs;
  double get distanceM => _distanceM;
  int get movingMs => _movingMs;
  double get maxSpeedMs => _maxSpeedMs;

  /// Latest smoothed speed, m/s.
  double get speedMs => _speedMs;
  double? get altitude => _altitude;
  double? get bearing => _bearing;
  int get lastEventMs => _lastEventMs;
  int get pointCount => _points.length;

  /// Average speed while moving, in m/s.
  double get avgMovingSpeedMs => _movingMs > 0 ? _distanceM / (_movingMs / 1000.0) : 0;

  /// Recorded time at [nowMs], without paused time.
  int elapsedMs(int nowMs) {
    final s = _startMs;
    if (s == null) return 0;
    final end = nowMs < s ? s : nowMs;
    final pausedNow = _paused ? end - _pausedSinceMs : 0;
    final v = end - s - _pausedTotalMs - pausedNow;
    return v < 0 ? 0 : v;
  }

  void start(int timeMs) {
    if (_startMs != null) return;
    _startMs = timeMs;
    _lastEventMs = timeMs;
    _filter.reset();
  }

  void pause(int timeMs) {
    if (_startMs == null || _paused) return;
    _paused = true;
    _pausedSinceMs = timeMs;
    _lastEventMs = timeMs;
    _speedMs = 0;
  }

  void resume(int timeMs) {
    if (_startMs == null || !_paused) return;
    _paused = false;
    _pausedTotalMs += timeMs - _pausedSinceMs;
    _lastEventMs = timeMs;
    _prevFixMs = null;
    _filter.reset();
  }

  /// Feeds one fix. Returns the processed fix, or null when the trip is not
  /// running, the fix is a duplicate or old one, or the filter rejected it.
  ProcessedFix? ingest(GpsFix fix) {
    final s = _startMs;
    if (s == null || _paused || fix.timeMs <= _lastEventMs) return null;
    final p = _filter.process(fix);
    if (p == null) return null;

    _lastEventMs = fix.timeMs;
    _speedMs = p.speedMs;
    _altitude = fix.altitude ?? _altitude;
    if (p.moving && fix.bearing != null) _bearing = fix.bearing;
    _distanceM += p.distanceM;
    final prev = _prevFixMs;
    if (prev != null && p.moving) {
      final dt = fix.timeMs - prev;
      if (dt > 0 && dt <= 10000) _movingMs += dt;
    }
    _prevFixMs = fix.timeMs;
    if (p.moving && p.speedMs > _maxSpeedMs) _maxSpeedMs = p.speedMs;

    if (p.moving || fix.timeMs - _lastPointMs >= idleSampleMs) {
      _lastPointMs = fix.timeMs;
      _points.add(TrackPoint(
        timeMs: fix.timeMs,
        lat: fix.lat,
        lon: fix.lon,
        speedMs: p.speedMs,
        altitude: fix.altitude,
      ));
    }
    return p;
  }

  void apply(TrackEvent e) {
    switch (e) {
      case StartEvent(:final timeMs):
        start(timeMs);
      case PauseEvent(:final timeMs):
        pause(timeMs);
      case ResumeEvent(:final timeMs):
        resume(timeMs);
      case FixEvent(:final fix):
        ingest(fix);
    }
  }

  /// Rebuilds a recorder from a whole track log.
  static TripRecorder fromEvents(Iterable<TrackEvent> events) {
    final r = TripRecorder();
    for (final e in events) {
      r.apply(e);
    }
    return r;
  }

  /// Ends the trip at [endMs] and returns it. Returns null when the trip never
  /// recorded any point.
  Trip? finish(int endMs) {
    final s = _startMs;
    if (s == null || _points.isEmpty) return null;
    final end = endMs < _lastEventMs ? _lastEventMs : endMs;
    return Trip(
      id: s.toString(),
      startMs: s,
      endMs: end,
      distanceM: _distanceM,
      durationMs: elapsedMs(end),
      movingMs: _movingMs,
      maxSpeedMs: _maxSpeedMs,
      points: thinPoints(_points, maxPoints),
    );
  }
}

/// Keeps at most [max] points, evenly spaced, always including the last.
List<TrackPoint> thinPoints(List<TrackPoint> points, int max) {
  if (points.length <= max || max < 2) return List.of(points);
  final out = <TrackPoint>[];
  final step = (points.length - 1) / (max - 1);
  for (var i = 0; i < max; i++) {
    out.add(points[(i * step).round()]);
  }
  return out;
}
