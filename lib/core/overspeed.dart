import 'dart:math' as math;

/// Result of one [OverspeedMonitor.update].
class OverspeedState {
  const OverspeedState({required this.over, required this.alertNow});

  /// True while the speed is above the limit (with hysteresis).
  final bool over;

  /// True when a beep and vibration should fire now: when the limit is first
  /// exceeded and then every `repeatMs` while it stays exceeded.
  final bool alertNow;

  static const off = OverspeedState(over: false, alertNow: false);
}

/// Speed limit alert that does not chatter around the limit.
///
/// It turns on above the limit and only turns off again once the speed falls
/// below the limit minus a margin of `max(2 km/h, 3% of the limit)`.
class OverspeedMonitor {
  OverspeedMonitor({this.repeatMs = 5000});

  final int repeatMs;

  bool _over = false;
  int? _lastAlertMs;

  bool get over => _over;

  /// Margin below the limit, in m/s, that the speed must drop to.
  static double marginFor(double limitMs) => math.max(2 / 3.6, limitMs * 0.03);

  void reset() {
    _over = false;
    _lastAlertMs = null;
  }

  OverspeedState update({required double speedMs, required double? limitMs, required int nowMs}) {
    if (limitMs == null || limitMs <= 0) {
      reset();
      return OverspeedState.off;
    }
    if (!_over) {
      if (speedMs > limitMs) {
        _over = true;
        _lastAlertMs = nowMs;
        return const OverspeedState(over: true, alertNow: true);
      }
      return OverspeedState.off;
    }
    if (speedMs < limitMs - marginFor(limitMs)) {
      reset();
      return OverspeedState.off;
    }
    final last = _lastAlertMs ?? nowMs;
    if (nowMs - last >= repeatMs) {
      _lastAlertMs = nowMs;
      return const OverspeedState(over: true, alertNow: true);
    }
    return const OverspeedState(over: true, alertNow: false);
  }
}
