import 'dart:async';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/gps_fix.dart';
import '../core/units.dart';

/// State of a runtime permission, simplified for the UI.
enum PermissionState { granted, denied, blocked }

/// Everything Dash needs from Android. The real one is [DashPlatformChannel];
/// tests use a fake.
abstract class DashPlatform {
  /// GPS fixes about once a second while someone listens. Errors with
  /// [PlatformException] (`permission`, `no_gps`).
  Stream<GpsFix> fixes();

  Future<void> keepScreenOn(bool on);
  Future<void> setMaxBrightness(bool on);
  Future<void> vibrate(int ms);

  /// A short alert beep (speed limit warning).
  Future<void> beep();

  /// Whether the GPS provider is switched on in the phone's location settings.
  Future<bool> gpsEnabled();
  Future<void> openLocationSettings();

  Future<PermissionState> locationPermission();
  Future<PermissionState> requestLocationPermission();
  Future<void> requestNotificationPermission();
  Future<void> openAppSettings();

  /// Tells the service which unit to use in the notification.
  Future<void> setUnit(SpeedUnit unit);

  /// Starts the foreground service and a fresh track log. Returns the start
  /// time in ms.
  Future<int> startTrip();
  Future<int> pauseTrip();
  Future<int> resumeTrip();

  /// Stops the service and deletes the track log.
  Future<void> stopTrip();

  /// True while a trip is running or paused (also after the app was closed).
  Future<bool> tripActive();

  /// The raw track log (JSON lines), see `parseTrackLog`.
  Future<String> readTrack();
}

class DashPlatformChannel implements DashPlatform {
  const DashPlatformChannel();

  static const _method = MethodChannel('com.itsash.dash/device');
  static const _events = EventChannel('com.itsash.dash/fixes');

  @override
  Stream<GpsFix> fixes() => _events.receiveBroadcastStream().map((e) {
        final m = (e as Map).cast<String, Object?>();
        return GpsFix.fromJson(m);
      });

  @override
  Future<void> keepScreenOn(bool on) => _method.invokeMethod<void>('keepScreenOn', on);

  @override
  Future<void> setMaxBrightness(bool on) => _method.invokeMethod<void>('maxBrightness', on);

  @override
  Future<void> vibrate(int ms) => _method.invokeMethod<void>('vibrate', ms);

  @override
  Future<void> beep() => _method.invokeMethod<void>('beep');

  @override
  Future<bool> gpsEnabled() async => await _method.invokeMethod<bool>('gpsEnabled') ?? false;

  @override
  Future<void> openLocationSettings() => _method.invokeMethod<void>('openLocationSettings');

  PermissionState _map(PermissionStatus s) {
    if (s.isGranted) return PermissionState.granted;
    if (s.isPermanentlyDenied || s.isRestricted) return PermissionState.blocked;
    return PermissionState.denied;
  }

  @override
  Future<PermissionState> locationPermission() async => _map(await Permission.location.status);

  @override
  Future<PermissionState> requestLocationPermission() async => _map(await Permission.location.request());

  @override
  Future<void> requestNotificationPermission() async {
    if (await Permission.notification.isDenied) await Permission.notification.request();
  }

  @override
  Future<void> openAppSettings() => openAppSettingsPage();

  @override
  Future<void> setUnit(SpeedUnit unit) => _method.invokeMethod<void>('setUnit', {
        'speedLabel': unit.label,
        'speedFactor': unit.fromMs(1),
        'distLabel': unit.distanceLabel,
        'distDivisor': 1 / unit.distanceFromMeters(1),
      });

  @override
  Future<int> startTrip() async => (await _method.invokeMethod<num>('startTrip'))!.toInt();

  @override
  Future<int> pauseTrip() async => (await _method.invokeMethod<num>('pauseTrip'))!.toInt();

  @override
  Future<int> resumeTrip() async => (await _method.invokeMethod<num>('resumeTrip'))!.toInt();

  @override
  Future<void> stopTrip() => _method.invokeMethod<void>('stopTrip');

  @override
  Future<bool> tripActive() async => await _method.invokeMethod<bool>('tripActive') ?? false;

  @override
  Future<String> readTrack() async => await _method.invokeMethod<String>('readTrack') ?? '';
}

/// `openAppSettings` from permission_handler, under a name that does not clash
/// with [DashPlatform.openAppSettings].
Future<bool> openAppSettingsPage() => openAppSettings();
