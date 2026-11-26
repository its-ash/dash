import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/fix_filter.dart';
import '../core/gforce.dart';
import '../core/gps_fix.dart';
import '../core/overspeed.dart';
import '../core/satellites.dart';
import '../core/trip.dart';
import '../core/trip_recorder.dart';
import '../core/units.dart';
import '../platform/dash_platform.dart';
import '../settings/settings_store.dart';
import '../storage/trip_repository.dart';

enum TripState { idle, recording, paused }

/// Why the live feed has no data yet.
enum FeedProblem { none, permission, permissionBlocked, gpsOff, noGps }

/// Trips shorter than this are not saved.
const double minSavedTripM = 30;

/// The accelerometer counts as not working when it sends nothing for this long.
const int sensorTimeoutMs = 3000;

/// Below this speed (m/s) the accelerometer's peaks are not counted for the
/// trip: hand movements while parked are not driving forces.
const double peakMinSpeedMs = 2;

/// Automatic trips: start after holding this speed (m/s, 15 km/h) for
/// [autoStartHoldMs] with Dash open; the service ends the trip after
/// [autoStopAfter] without moving.
const double autoStartSpeedMs = 15 / 3.6;
const int autoStartHoldMs = 20000;
const Duration autoStopAfter = Duration(minutes: 5);

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
  StreamSubscription<SatelliteCount>? _satSub;
  StreamSubscription<AccelSample>? _accelSub;
  final SensorGMeter _sensorG = SensorGMeter();
  final GpsGMeter _gpsG = GpsGMeter();
  final GPeaks _sensorPeaks = GPeaks();
  final HarshDetector _sensorHarsh = HarshDetector();
  int? _fastSinceMs;
  bool _syncing = false;

  /// The last trip saved without the Stop button (auto-stop or the widget),
  /// for the home screen to mention. Cleared by [clearAutoSaved].
  Trip? autoSaved;

  /// True when the running trip was started by automatic trips.
  bool autoStarted = false;
  GReading? _sensorReading;
  GReading? _gpsReading;
  int? _lastSensorAtMs;

  /// True when the phone reported no usable accelerometer.
  bool accelerometerMissing = false;
  Timer? _timer;
  bool _started = false;
  bool _disposed = false;
  int _gen = 0;
  bool _starting = false;
  bool _stopping = false;
  int _ticks = 0;

  FeedProblem problem = FeedProblem.none;
  GpsFix? lastFix;

  /// Latest satellite counts, or null before the first GNSS status.
  SatelliteCount? satellites;
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

  /// The accelerometer is sending data (and has in the last few seconds).
  bool get sensorActive =>
      !accelerometerMissing && _lastSensorAtMs != null && _now() - _lastSensorAtMs! <= sensorTimeoutMs;

  /// Where [gforce] comes from: the accelerometer, or GPS when it is missing
  /// or silent.
  GSource get gSource => sensorActive ? GSource.sensor : GSource.gps;

  /// Live g-force, or null when there is nothing to show yet.
  GReading? get gforce => sensorActive ? _sensorReading : (hasFreshFix ? _gpsReading : null);

  /// Peaks of the running trip: GPS over the whole trip, merged with the
  /// accelerometer while Dash was open.
  GPeaks get tripPeaks => (_recorder?.gpsPeaks ?? GPeaks()).merged(_sensorPeaks);

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
    final gen = _gen;
    await platform.keepScreenOn(true);
    if (gen != _gen || _disposed) return;
    await platform.setUnit(settings.unit);
    if (gen != _gen || _disposed) return;
    settings.addListener(_onSettings);
    _live.reset();
    _timer = Timer.periodic(_tickEvery, (_) => _onTick());
    await _syncTrip();
    if (gen != _gen || _disposed) return;
    await _savePending();
    if (gen != _gen || _disposed) return;
    await _pushAutoStop();
    if (gen != _gen || _disposed) return;
    _connectAccelerometer();
    final connecting = _connect();
    final connectGen = _gen;
    await connecting;
    if (connectGen != _gen || _disposed) return;
    await refreshWidget();
  }

  Future<void> _pushAutoStop() => platform.setAutoStop(settings.autoTrips ? autoStopAfter : Duration.zero);

  void clearAutoSaved() {
    autoSaved = null;
    _notify();
  }

  /// Saves trips that ended outside the app (auto-stop or the widget).
  Future<void> _savePending() async {
    final pending = await platform.pendingTracks();
    for (final p in pending) {
      final r = TripRecorder.fromEvents(parseTrackLog(p.log));
      final trip = r.finish(r.lastEventMs);
      if (trip != null && trip.distanceM >= minSavedTripM) {
        await repository.save(trip);
        settings.addOdometer(trip.distanceM);
        autoSaved = trip;
      }
      await platform.deletePending(p.name);
    }
    if (pending.isNotEmpty) {
      await refreshWidget();
      _notify();
    }
  }

  /// Sends the odometer and last trip to the home-screen widget.
  Future<void> refreshWidget() async {
    final unit = settings.unit;
    final trips = await repository.list();
    final last = trips.isEmpty ? null : trips.first;
    await platform.updateWidget(
      odometer: formatDistance(settings.odometerM, unit),
      lastTrip: last == null
          ? ''
          : 'Last trip ${formatDistance(last.distanceM, unit)} · '
              '${formatDateTime(DateTime.fromMillisecondsSinceEpoch(last.startMs))}',
    );
  }

  /// Follows trips started or ended outside the app (the widget, auto-stop).
  Future<void> _syncWithService() async {
    if (_syncing) return;
    _syncing = true;
    try {
      final s = await platform.tripStatus();
      if (s.pending > 0) {
        if (!s.active && tripActive) {
          _recorder = null;
          tripState = TripState.idle;
          autoStarted = false;
        }
        await _savePending();
      }
      if (s.active != tripActive) {
        await _syncTrip();
        if (tripActive) _sensorPeaks.reset();
        _notify();
      }
    } finally {
      _syncing = false;
    }
  }

  void _connectAccelerometer() {
    _accelSub?.cancel();
    accelerometerMissing = false;
    _lastSensorAtMs = null;
    _accelSub = platform.acceleration().listen(
      (s) {
        _lastSensorAtMs = _now();
        final r = _sensorG.feed(s);
        _sensorReading = r;
        final fix = lastFix;
        if (tripState == TripState.recording && _speedMs >= peakMinSpeedMs && hasFreshFix && fix != null) {
          _sensorPeaks.add(r);
          _sensorHarsh.add(r, timeMs: _now(), lat: fix.lat, lon: fix.lon);
        }
        _notify();
      },
      onError: (Object _) {
        accelerometerMissing = true;
        _notify();
      },
    );
  }

  /// Call when the app goes to the background. A running trip keeps recording
  /// in the Android service.
  Future<void> pause() async {
    if (!_started) return;
    _started = false;
    _gen++;
    settings.removeListener(_onSettings);
    _timer?.cancel();
    _timer = null;
    final sub = _sub;
    _sub = null;
    await sub?.cancel();
    final satSub = _satSub;
    _satSub = null;
    await satSub?.cancel();
    satellites = null;
    final accelSub = _accelSub;
    _accelSub = null;
    await accelSub?.cancel();
    _lastSensorAtMs = null;
    await platform.keepScreenOn(false);
  }

  @override
  void dispose() {
    _disposed = true;
    _gen++;
    settings.removeListener(_onSettings);
    _timer?.cancel();
    _sub?.cancel();
    _satSub?.cancel();
    _accelSub?.cancel();
    platform.keepScreenOn(false);
    super.dispose();
  }

  SpeedUnit? _widgetUnit;
  double? _widgetOdometer;
  bool? _sentAutoTrips;

  void _onSettings() {
    platform.setUnit(settings.unit);
    if (_sentAutoTrips != settings.autoTrips) {
      _sentAutoTrips = settings.autoTrips;
      _pushAutoStop();
      if (!settings.autoTrips) _fastSinceMs = null;
    }
    if (_widgetUnit != settings.unit || _widgetOdometer != settings.odometerM) {
      _widgetUnit = settings.unit;
      _widgetOdometer = settings.odometerM;
      refreshWidget();
    }
    if (settings.activeLimitMs == null) overspeed = false;
    _notify();
  }

  Future<void> _connect() async {
    final gen = ++_gen;
    final prevSub = _sub;
    _sub = null;
    final prevSat = _satSub;
    _satSub = null;
    await prevSub?.cancel();
    if (gen != _gen || _disposed) return;
    await prevSat?.cancel();
    if (gen != _gen || _disposed) return;
    final perm = await platform.locationPermission();
    if (gen != _gen || _disposed) return;
    if (perm != PermissionState.granted) {
      problem = perm == PermissionState.blocked ? FeedProblem.permissionBlocked : FeedProblem.permission;
      _notify();
      return;
    }
    final enabled = await platform.gpsEnabled();
    if (gen != _gen || _disposed) return;
    problem = enabled ? FeedProblem.none : FeedProblem.gpsOff;
    final sub = platform.fixes().listen(
      _onFix,
      onError: (Object e) {
        problem = e is PlatformException && e.code == 'permission' ? FeedProblem.permission : FeedProblem.noGps;
        _notify();
      },
    );
    final satSub = platform.satellites().listen(
      (s) {
        if (s == satellites) return;
        satellites = s;
        _notify();
      },
      onError: (Object _) {},
    );
    if (gen != _gen || _disposed) {
      await sub.cancel();
      await satSub.cancel();
      return;
    }
    _sub = sub;
    _satSub = satSub;
    _notify();
  }

  /// Asks for location permission and starts the feed when granted.
  Future<void> requestPermission() async {
    final gen = _gen;
    final state = await platform.requestLocationPermission();
    if (gen != _gen || _disposed) return;
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
      final g = _gpsG.feed(timeMs: fix.timeMs, speedMs: p.speedMs, bearing: p.moving ? fix.bearing : null);
      if (g != null) _gpsReading = g;
      // GPS speed change teaches the accelerometer which way is forward.
      _sensorG.learn(p.moving ? (_gpsG.lastLongMs2 ?? 0) : 0);
    }
    _recorder?.ingest(fix);
    _checkAutoStart();
    _notify();
  }

  void _checkAutoStart() {
    if (!settings.autoTrips || tripActive || _starting || problem != FeedProblem.none) {
      _fastSinceMs = null;
      return;
    }
    if (_speedMs < autoStartSpeedMs) {
      _fastSinceMs = null;
      return;
    }
    final since = _fastSinceMs ??= _now();
    if (_now() - since >= autoStartHoldMs) {
      _fastSinceMs = null;
      startTrip(auto: true);
    }
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
      await _syncWithService();
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

  /// Starts a trip. [auto] is true for automatic trips: no permission dialog
  /// pops up while driving.
  Future<void> startTrip({bool auto = false}) async {
    if (_starting ||
        _stopping ||
        tripActive ||
        problem == FeedProblem.permission ||
        problem == FeedProblem.permissionBlocked) {
      return;
    }
    _starting = true;
    try {
      if (!auto) await platform.requestNotificationPermission();
      if (_disposed) return;
      await platform.setUnit(settings.unit);
      await _pushAutoStop();
      final int t;
      try {
        t = await platform.startTrip();
      } on PlatformException {
        return;
      }
      if (_disposed) return;
      autoStarted = auto;
      _sensorPeaks.reset();
      _sensorHarsh.reset();
      _recorder = TripRecorder()..start(t);
      tripState = TripState.recording;
      _notify();
    } finally {
      _starting = false;
    }
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
    if (_stopping || _recorder == null) return null;
    _stopping = true;
    try {
      await _syncTrip();
      final peaks = tripPeaks;
      final finished = _recorder?.finish(_now());
      final trip = finished?.withGForce(peaks, mergeHarshEvents(finished.events, _sensorHarsh.events));
      _sensorPeaks.reset();
      _sensorHarsh.reset();
      await platform.stopTrip();
      _recorder = null;
      tripState = TripState.idle;
      autoStarted = false;
      Trip? saved;
      if (trip != null && trip.distanceM >= minSavedTripM) {
        await repository.save(trip);
        settings.addOdometer(trip.distanceM);
        saved = trip;
      }
      await refreshWidget();
      _notify();
      return saved;
    } finally {
      _stopping = false;
    }
  }
}
