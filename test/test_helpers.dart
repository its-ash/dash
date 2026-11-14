import 'dart:async';
import 'dart:convert';

import 'package:dash/core/gps_fix.dart';
import 'package:dash/core/trip.dart';
import 'package:dash/core/units.dart';
import 'package:dash/platform/dash_platform.dart';

/// Base time for synthetic fixes (2023-11-14 22:13:20 UTC).
const baseMs = 1700000000000;

/// A fix [i] seconds after [base], travelling north at [speed] m/s along a
/// straight line (one degree of latitude is about 111195 m).
GpsFix northFix(int i, {double speed = 10, double accuracy = 5, int base = baseMs, double? reportedSpeed}) {
  return GpsFix(
    timeMs: base + i * 1000,
    lat: 12.0 + (i * speed) / 111195.0,
    lon: 77.0,
    altitude: 900,
    speed: reportedSpeed ?? speed,
    accuracy: accuracy,
    bearing: 0,
  );
}

Trip sampleTrip({String id = '1700000000000', int points = 12, double speed = 10}) {
  final pts = [
    for (var i = 0; i < points; i++)
      TrackPoint(
        timeMs: baseMs + i * 1000,
        lat: 12.0 + (i * speed) / 111195.0,
        lon: 77.0 + (i % 3) * 0.0001,
        speedMs: speed + (i % 4),
        altitude: 900,
      ),
  ];
  return Trip(
    id: id,
    startMs: baseMs,
    endMs: baseMs + points * 1000,
    distanceM: speed * (points - 1),
    durationMs: points * 1000,
    movingMs: (points - 1) * 1000,
    maxSpeedMs: speed + 3,
    points: pts,
  );
}

/// Fake Android side. Mimics the service: while a trip runs, every emitted fix
/// is also appended to the track log.
class FakePlatform implements DashPlatform {
  final _fixes = StreamController<GpsFix>.broadcast();

  PermissionState permission = PermissionState.granted;
  bool gps = true;
  bool active = false;
  bool paused = false;
  String log = '';
  int beeps = 0;
  int vibrations = 0;
  final brightness = <bool>[];
  final screenOn = <bool>[];
  SpeedUnit? unit;

  void emit(GpsFix f) {
    if (active && !paused) log += '${jsonEncode(f.toJson())}\n';
    _fixes.add(f);
  }

  @override
  Stream<GpsFix> fixes() => _fixes.stream;

  @override
  Future<void> keepScreenOn(bool on) async => screenOn.add(on);

  @override
  Future<void> setMaxBrightness(bool on) async => brightness.add(on);

  @override
  Future<void> vibrate(int ms) async => vibrations++;

  @override
  Future<void> beep() async => beeps++;

  @override
  Future<bool> gpsEnabled() async => gps;

  @override
  Future<void> openLocationSettings() async {}

  @override
  Future<PermissionState> locationPermission() async => permission;

  @override
  Future<PermissionState> requestLocationPermission() async {
    if (permission == PermissionState.denied) permission = PermissionState.granted;
    return permission;
  }

  @override
  Future<void> requestNotificationPermission() async {}

  @override
  Future<void> openAppSettings() async {}

  @override
  Future<void> setUnit(SpeedUnit unit) async => this.unit = unit;

  @override
  Future<int> startTrip() async {
    active = true;
    paused = false;
    final t = DateTime.now().millisecondsSinceEpoch;
    log = '{"e":"start","t":$t}\n';
    return t;
  }

  @override
  Future<int> pauseTrip() async {
    paused = true;
    final t = DateTime.now().millisecondsSinceEpoch;
    log += '{"e":"pause","t":$t}\n';
    return t;
  }

  @override
  Future<int> resumeTrip() async {
    paused = false;
    final t = DateTime.now().millisecondsSinceEpoch;
    log += '{"e":"resume","t":$t}\n';
    return t;
  }

  @override
  Future<void> stopTrip() async {
    active = false;
    paused = false;
    log = '';
  }

  @override
  Future<bool> tripActive() async => active;

  @override
  Future<String> readTrack() async => log;

  Future<void> close() => _fixes.close();
}
