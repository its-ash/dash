import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/units.dart';

/// Dash options, saved with `shared_preferences`. Speeds are stored in m/s.
class SettingsStore extends ChangeNotifier {
  SettingsStore._(this._prefs)
      : _unit = SpeedUnit.fromName(_prefs?.getString(_kUnit)),
        _analog = _prefs?.getBool(_kAnalog) ?? false,
        _limitEnabled = _prefs?.getBool(_kLimitEnabled) ?? false,
        _limitMs = _prefs?.getDouble(_kLimitMs) ?? defaultLimitMs,
        _sound = _prefs?.getBool(_kSound) ?? true,
        _vibration = _prefs?.getBool(_kVibration) ?? true,
        _hudMirror = _prefs?.getBool(_kHudMirror) ?? true,
        _odometerM = _prefs?.getDouble(_kOdometer) ?? 0;

  /// For tests: keeps everything in memory.
  SettingsStore.memory()
      : _prefs = null,
        _unit = SpeedUnit.kmh,
        _analog = false,
        _limitEnabled = false,
        _limitMs = defaultLimitMs,
        _sound = true,
        _vibration = true,
        _hudMirror = true,
        _odometerM = 0;

  static const defaultLimitMs = 100 / 3.6;

  static const _kUnit = 'unit';
  static const _kAnalog = 'analog';
  static const _kLimitEnabled = 'limit_enabled';
  static const _kLimitMs = 'limit_ms';
  static const _kSound = 'alert_sound';
  static const _kVibration = 'alert_vibration';
  static const _kHudMirror = 'hud_mirror';
  static const _kOdometer = 'odometer_m';

  static Future<SettingsStore> load() async => SettingsStore._(await SharedPreferences.getInstance());

  final SharedPreferences? _prefs;
  SpeedUnit _unit;
  bool _analog;
  bool _limitEnabled;
  double _limitMs;
  bool _sound;
  bool _vibration;
  bool _hudMirror;
  double _odometerM;

  SpeedUnit get unit => _unit;

  /// Show the analog gauge instead of the big digits.
  bool get analog => _analog;
  bool get limitEnabled => _limitEnabled;
  double get limitMs => _limitMs;

  /// The limit to enforce in m/s, or null when the alert is off.
  double? get activeLimitMs => _limitEnabled ? _limitMs : null;
  bool get sound => _sound;
  bool get vibration => _vibration;

  /// Mirror the HUD digits horizontally for windshield reflection.
  bool get hudMirror => _hudMirror;

  /// Distance of all finished trips, in metres.
  double get odometerM => _odometerM;

  void setUnit(SpeedUnit v) {
    _unit = v;
    _prefs?.setString(_kUnit, v.name);
    notifyListeners();
  }

  void setAnalog(bool v) {
    _analog = v;
    _prefs?.setBool(_kAnalog, v);
    notifyListeners();
  }

  void setLimitEnabled(bool v) {
    _limitEnabled = v;
    _prefs?.setBool(_kLimitEnabled, v);
    notifyListeners();
  }

  void setLimitMs(double v) {
    _limitMs = v;
    _prefs?.setDouble(_kLimitMs, v);
    notifyListeners();
  }

  void setSound(bool v) {
    _sound = v;
    _prefs?.setBool(_kSound, v);
    notifyListeners();
  }

  void setVibration(bool v) {
    _vibration = v;
    _prefs?.setBool(_kVibration, v);
    notifyListeners();
  }

  void setHudMirror(bool v) {
    _hudMirror = v;
    _prefs?.setBool(_kHudMirror, v);
    notifyListeners();
  }

  void addOdometer(double meters) {
    if (meters <= 0) return;
    _odometerM += meters;
    _prefs?.setDouble(_kOdometer, _odometerM);
    notifyListeners();
  }

  void resetOdometer() {
    _odometerM = 0;
    _prefs?.setDouble(_kOdometer, 0);
    notifyListeners();
  }
}
