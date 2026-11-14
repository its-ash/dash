import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/fix_filter.dart';
import '../core/gps_fix.dart';
import '../core/overspeed.dart';
import '../core/trip.dart';
import '../core/trip_recorder.dart';
import '../platform/dash_platform.dart';
import '../settings/settings_store.dart';
import '../storage/trip_repository.dart';

enum TripState { idle, recording, paused }

/// Why the live feed has no data yet.
enum FeedProblem { none, permission, permissionBlocked, gpsOff, noGps }

/// Trips shorter than this are not saved.
const double minSavedTripM = 30;

/// Live GPS state for the screens: smoothed speed, fix quality, the running
/// trip and the speed limit alert. It is the only place that talks to
/// [DashPlatform], so it can be tested with a fake.
class DashController extends ChangeNotifier {
  DashController({
    required this.platform,
    required this.settings,
    required this.repository,
    int Function()? now,
    Duration tick = const Duration(seconds: 1),
  })  : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch),
        _tickEvery = tick;

  final DashPlatform platform;
  final SettingsStore settings;
  final TripRepository repository;
  final int Function() _now;
  final Duration _tickEvery;

  final FixFilter _live = FixFilter();
  final OverspeedMonitor _overspeed = OverspeedMonitor();
  StreamSubscription<GpsFix>? _sub;
  Timer? _timer;
  bool _started = false;
  bool _disposed = false;
  int _ticks = 0;

  FeedProblem problem = FeedProblem.none;
  GpsFix? lastFix;
  int? _lastFixAtMs;
  double _speedMs = 0;
  bool overspeed = false;
  TripRecorder? _recorder;
  TripState tripState = TripState.idle;

  /// Smoothed speed in m/s, or 0 when the fix is stale (tunnel, lost signal).
  double get speedMs => hasFreshFix ? _speedMs : 0;

  int? get fixAgeMs => _lastFixAtMs == null ? null : _now() - _lastFixAtMs!;
  bool get hasFreshFix => (fixAgeMs ?? 1 << 30) <= 5000;

  GpsStatus get gpsStatus => gpsStatusFor(accuracy: lastFix?.accuracy, ageMs: fixAgeMs);

  double? get accuracyM => lastFix?.accuracy;
  double? get altitudeM => lastFix?.altitude;

  /// Direction of travel in degrees, or null when unknown or standing still.
  double? get bearing => _speedMs > 0 && hasFreshFix ? (_recorder?.bearing ?? lastFix?.bearing) : null;

  TripRecorder? get recorder => _recorder;
  bool get tripActive => tripState != TripState.idle;
  double get tripDistanceM => _recorder?.distanceM ?? 0;
  Duration get tripElapsed => Duration(milliseconds: _recorder?.elapsedMs(_now()) ?? 0);
  Duration get tripMoving => Duration(milliseconds: _recorder?.movingMs ?? 0);
  double get tripAvgMs => _recorder?.avgMovingSpeedMs ?? 0;
  double get tripMaxMs => _recorder?.maxSpeedMs ?? 0;

  /// Call when the app comes to the foreground (also the first time).
  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    await platform.keepScreenOn(true);
    await platform.setUnit(settings.unit);
    settings.addListener(_onSettings);
    _live.reset();
    _timer = Timer.periodic(_tickEvery, (_) => _onTick());
    await _syncTrip();
    await _connect();
  }

  /// Call when the app goes to the background. A running trip keeps recording
  /// in the Android service.
  Future<void> pause() async {
    if (!_started) return;
    _started = false;
    settings.removeListener(_onSettings);
    _timer?.cancel();
    _timer = null;
    await _sub?.cancel();
    _sub = null;
    await platform.keepScreenOn(false);
  }

  @override
  void dispose() {
    _disposed = true;
    settings.removeListener(_onSettings);
    _timer?.cancel();
    _sub?.cancel();
    platform.keepScreenOn(false);
    super.dispose();
  }

  void _onSettings() {
    platform.setUnit(settings.unit);
    if (settings.activeLimitMs == null) overspeed = false;
    _notify();
  }

  Future<void> _connect() async {
    await _sub?.cancel();
    _sub = null;
    final perm = await platform.locationPermission();
    if (perm != PermissionState.granted) {
      problem = perm == PermissionState.blocked ? FeedProblem.permissionBlocked : FeedProblem.permission;
      _notify();
      return;
    }
    problem = await platform.gpsEnabled() ? FeedProblem.none : FeedProblem.gpsOff;
    _sub = platform.fixes().listen(
      _onFix,
      onError: (Object e) {
        problem = e is PlatformException && e.code == 'permission' ? FeedProblem.permission : FeedProblem.noGps;
        _notify();
      },
    );
    _notify();
  }

  /// Asks for location permission and starts the feed when granted.
  Future<void> requestPermission() async {
    final state = await platform.requestLocationPermission();
    if (state == PermissionState.blocked) {
      problem = FeedProblem.permissionBlocked;
      _notify();
      return;
    }
    await _connect();
  }

  Future<void> openAppSettings() => platform.openAppSettings();
  Future<void> openLocationSettings() => platform.openLocationSettings();

  void _onFix(GpsFix fix) {
    lastFix = fix;
    _lastFixAtMs = _now();
    if (problem == FeedProblem.gpsOff) problem = FeedProblem.none;

    final p = _live.process(fix);
    if (p != null) {
      _speedMs = p.speedMs;
      _updateOverspeed();
    }
    _recorder?.ingest(fix);
    _notify();
  }

  void _updateOverspeed() {
    final s = _overspeed.update(speedMs: _speedMs, limitMs: settings.activeLimitMs, nowMs: _now());
    overspeed = s.over;
    if (s.alertNow) {
      if (settings.sound) platform.beep();
      if (settings.vibration) platform.vibrate(400);
    }
  }

  Future<void> _onTick() async {
    _ticks++;
    if (_ticks % 3 == 0 && problem != FeedProblem.permission && problem != FeedProblem.permissionBlocked) {
      final on = await platform.gpsEnabled();
      if (on && problem == FeedProblem.gpsOff) problem = FeedProblem.none;
      if (!on && problem == FeedProblem.none) problem = FeedProblem.gpsOff;
    }
    if (!hasFreshFix) {
      _speedMs = 0;
      _overspeed.reset();
      overspeed = false;
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Rebuilds the running trip from the service's log (after the app was
  /// closed or in the background).
  Future<void> _syncTrip() async {
    if (!await platform.tripActive()) {
      _recorder = null;
      tripState = TripState.idle;
      return;
    }
    final r = TripRecorder.fromEvents(parseTrackLog(await platform.readTrack()));
    if (!r.started) {
      _recorder = null;
      tripState = TripState.idle;
      return;
    }
    _recorder = r;
    tripState = r.paused ? TripState.paused : TripState.recording;
  }

  Future<void> startTrip() async {
    if (tripActive || problem == FeedProblem.permission || problem == FeedProblem.permissionBlocked) return;
    await platform.requestNotificationPermission();
    await platform.setUnit(settings.unit);
    final t = await platform.startTrip();
    _recorder = TripRecorder()..start(t);
    tripState = TripState.recording;
    _notify();
  }

  Future<void> pauseTrip() async {
    final r = _recorder;
    if (r == null || tripState != TripState.recording) return;
    r.pause(await platform.pauseTrip());
    tripState = TripState.paused;
    _notify();
  }

  Future<void> resumeTrip() async {
    final r = _recorder;
    if (r == null || tripState != TripState.paused) return;
    r.resume(await platform.resumeTrip());
    tripState = TripState.recording;
    _notify();
  }

  /// Ends the trip. Returns the saved trip, or null when it was too short to
  /// keep (under [minSavedTripM]).
  Future<Trip?> stopTrip() async {
    if (_recorder == null) return null;
    await _syncTrip();
    final trip = _recorder?.finish(_now());
    await platform.stopTrip();
    _recorder = null;
    tripState = TripState.idle;
    Trip? saved;
    if (trip != null && trip.distanceM >= minSavedTripM) {
      await repository.save(trip);
      settings.addOdometer(trip.distanceM);
      saved = trip;
    }
    _notify();
    return saved;
  }
}
