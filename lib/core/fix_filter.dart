import 'dart:math' as math;

import 'geo.dart';
import 'gps_fix.dart';

/// A fix that passed the filter, with smoothed speed and the distance it adds.
class ProcessedFix {
  const ProcessedFix({
    required this.fix,
    required this.speedMs,
    required this.moving,
    required this.distanceM,
    required this.dtMs,
  });

  final GpsFix fix;

  /// Smoothed speed in m/s. Exactly 0 while stationary.
  final double speedMs;

  /// False when the speed is below the stationary threshold.
  final bool moving;

  /// Metres travelled since the previous accepted moving fix.
  final double distanceM;

  /// Milliseconds since the previous accepted fix (0 for the first).
  final int dtMs;
}

/// Rejects bad GPS fixes and smooths the speed.
///
/// A fix is rejected when its accuracy is missing or worse than
/// [maxAccuracyM], its time does not move forward, or it implies a jump faster
/// than [maxSpeedMs]. After [maxRejectStreak] jumps in a row the new position
/// is trusted (the phone really did move, e.g. after a long tunnel).
/// Speed below [stationaryMs] counts as standing still: it shows as 0 and adds
/// no distance, so GPS drift does not pile up kilometres at a red light.
class FixFilter {
  FixFilter({
    this.maxAccuracyM = 30,
    this.maxSpeedMs = 100,
    this.stationaryMs = 1.5 / 3.6,
    this.tauMs = 1500,
    this.maxRejectStreak = 5,
  });

  final double maxAccuracyM;
  final double maxSpeedMs;
  final double stationaryMs;

  /// Smoothing time constant in milliseconds.
  final double tauMs;
  final int maxRejectStreak;

  GpsFix? _last;
  GpsFix? _anchor;
  double _speed = 0;
  int _jumpRejects = 0;

  /// Smoothed speed after the last accepted fix, in m/s.
  double get speedMs => _speed < stationaryMs ? 0 : _speed;

  /// Forgets all history (after a pause or a new trip).
  void reset() {
    _last = null;
    _anchor = null;
    _speed = 0;
    _jumpRejects = 0;
  }

  /// Returns the processed fix, or null when it was rejected.
  ProcessedFix? process(GpsFix f) {
    final acc = f.accuracy;
    if (acc == null || acc > maxAccuracyM) return null;
    final last = _last;
    if (last != null && f.timeMs <= last.timeMs) return null;

    var dtMs = 0;
    var jumped = false;
    double? implied;
    if (last != null) {
      dtMs = f.timeMs - last.timeMs;
      final d = haversine(last.lat, last.lon, f.lat, f.lon);
      implied = d / (dtMs / 1000.0);
      if (implied > maxSpeedMs) {
        _jumpRejects++;
        if (_jumpRejects < maxRejectStreak) return null;
        jumped = true;
      }
    }
    _jumpRejects = 0;

    if (last == null || jumped || dtMs > 10000) {
      // No usable history: restart smoothing from this fix.
      final raw = _rawSpeed(f, implied);
      _speed = raw < stationaryMs ? 0 : raw;
      _anchor = f;
      _last = f;
      return ProcessedFix(
        fix: f,
        speedMs: speedMs,
        moving: _speed >= stationaryMs,
        distanceM: 0,
        dtMs: jumped || last == null ? 0 : dtMs,
      );
    }

    final raw = _rawSpeed(f, implied);
    if (f.speed != null && raw < stationaryMs) {
      // The receiver's Doppler speed is very reliable at a standstill.
      _speed = 0;
    } else {
      final alpha = 1 - math.exp(-dtMs / tauMs);
      _speed += alpha * (raw - _speed);
    }

    final moving = _speed >= stationaryMs;
    var distance = 0.0;
    final anchor = _anchor;
    if (moving && anchor != null) {
      distance = haversine(anchor.lat, anchor.lon, f.lat, f.lon);
      _anchor = f;
    } else if (moving) {
      _anchor = f;
    }
    _last = f;
    return ProcessedFix(fix: f, speedMs: speedMs, moving: moving, distanceM: distance, dtMs: dtMs);
  }

  double _rawSpeed(GpsFix f, double? implied) {
    final s = f.speed;
    if (s != null && s >= 0) return s;
    return implied ?? 0;
  }
}
