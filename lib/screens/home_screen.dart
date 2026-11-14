import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../core/geo.dart';
import '../core/gforce.dart';
import '../core/gps_fix.dart';
import '../core/trip.dart';
import '../core/units.dart';
import '../settings/settings_store.dart';
import '../state/dash_controller.dart';
import '../storage/trip_repository.dart';
import '../widgets/digital_speed.dart';
import '../widgets/g_dial.dart';
import '../widgets/speed_gauge.dart';
import 'hud_screen.dart';
import 'settings_screen.dart';
import 'trip_detail_screen.dart';
import 'trips_screen.dart';

/// The speedometer: big digits or analog gauge, the running trip and GPS info.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.controller, required this.settings, required this.repository});

  final DashController controller;
  final SettingsStore settings;
  final TripRepository repository;

  void _open(BuildContext context, Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    return UiScaffold(
      appBar: UiAppBar(
        title: 'Dash',
        actions: [
          UiIconButton(
            Icons.speed_rounded,
            tooltip: 'HUD mode',
            onPressed: () => _open(context, HudScreen(controller: controller, settings: settings)),
          ),
          UiIconButton(
            Icons.route_rounded,
            tooltip: 'Trips',
            onPressed: () => _open(context, TripsScreen(repository: repository, settings: settings)),
          ),
          UiIconButton(
            Icons.settings_rounded,
            tooltip: 'Settings',
            onPressed: () => _open(context, SettingsScreen(settings: settings)),
          ),
        ],
      ),
      scrollable: true,
      body: ListenableBuilder(
        listenable: Listenable.merge([controller, settings]),
        builder: (context, _) => _Body(
          controller: controller,
          settings: settings,
          onOpenTrip: (trip) => _open(
            context,
            TripDetailScreen(tripId: trip.id, repository: repository, settings: settings),
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.controller, required this.settings, required this.onOpenTrip});

  final DashController controller;
  final SettingsStore settings;
  final void Function(Trip trip) onOpenTrip;

  @override
  Widget build(BuildContext context) {
    final unit = settings.unit;
    final limit = settings.activeLimitMs;
    final over = controller.overspeed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _problem(context),
        if (controller.autoSaved case final saved?)
          _gap(
            UiAlert(
              'Dash ended a trip of ${formatDistance(saved.distanceM, unit)} by itself and saved it.',
              title: 'Trip saved',
              status: UiStatus.success,
              action: UiButton(
                'View trip',
                icon: Icons.route_rounded,
                variant: UiButtonVariant.secondary,
                onPressed: () {
                  controller.clearAutoSaved();
                  onOpenTrip(saved);
                },
              ),
            ),
          ),
        _statusRow(context),
        const UiGap(UiSpace.md),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: settings.analog
                ? SpeedGauge(speedMs: controller.speedMs, unit: unit, over: over)
                : Padding(
                    padding: const EdgeInsets.symmetric(vertical: UiSpace.lg),
                    child: DigitalSpeed(speedMs: controller.speedMs, unit: unit, over: over),
                  ),
          ),
        ),
        if (limit != null) ...[
          const UiGap(UiSpace.sm),
          over
              ? UiAlert(
                  'You are over the limit of ${formatSpeed(limit, unit)} ${unit.label}. Slow down.',
                  title: 'Speed limit',
                  status: UiStatus.danger,
                )
              : Text(
                  'Limit ${formatSpeed(limit, unit)} ${unit.label}',
                  textAlign: TextAlign.center,
                  style: context.text.bodySmall?.copyWith(color: context.colors.textMuted),
                ),
        ],
        const UiGap(UiSpace.lg),
        UiSegmentedControl<SpeedUnit>(
          [for (final u in SpeedUnit.values) UiSegment(u, label: u.label)],
          value: unit,
          expand: true,
          onChanged: settings.setUnit,
        ),
        const UiGap(UiSpace.lg),
        _tripControls(context),
        const UiGap(UiSpace.lg),
        _tripStats(context, unit),
        const UiGap(UiSpace.lg),
        _gforce(context),
        const UiGap(UiSpace.lg),
        _position(context, unit),
        const UiGap(UiSpace.lg),
      ],
    );
  }

  Widget _statusRow(BuildContext context) {
    final status = controller.gpsStatus;
    final (label, tone) = switch (status) {
      GpsStatus.good => ('GPS fix', UiStatus.success),
      GpsStatus.weak => ('Weak GPS', UiStatus.warning),
      GpsStatus.searching => ('Searching for GPS', UiStatus.neutral),
    };
    return Row(
      children: [
        UiStatusPill(label, status: tone, dot: true, pulse: status == GpsStatus.searching),
        const Spacer(),
        UiSegmentedControl<bool>(
          const [
            UiSegment(false, icon: Icons.pin_outlined, tooltip: 'Digital'),
            UiSegment(true, icon: Icons.speed_rounded, tooltip: 'Gauge'),
          ],
          value: settings.analog,
          size: UiSize.sm,
          onChanged: settings.setAnalog,
        ),
      ],
    );
  }

  Widget _problem(BuildContext context) {
    switch (controller.problem) {
      case FeedProblem.none:
        return const SizedBox.shrink();
      case FeedProblem.permission:
        return _gap(
          UiAlert(
            'Dash needs your precise location to read your speed from GPS. '
            'Nothing is sent anywhere.',
            title: 'Allow location',
            status: UiStatus.warning,
            action: UiButton('Allow location', icon: Icons.my_location_rounded, onPressed: controller.requestPermission),
          ),
        );
      case FeedProblem.permissionBlocked:
        return _gap(
          UiAlert(
            'Location is turned off for Dash. Open the app settings and allow Location.',
            title: 'Location blocked',
            status: UiStatus.danger,
            action: UiButton('Open app settings', icon: Icons.settings_rounded, onPressed: controller.openAppSettings),
          ),
        );
      case FeedProblem.gpsOff:
        return _gap(
          UiAlert(
            'Location is switched off on this phone. Turn it on to see your speed.',
            title: 'GPS is off',
            status: UiStatus.warning,
            action: UiButton('Location settings', icon: Icons.location_on_rounded, onPressed: controller.openLocationSettings),
          ),
        );
      case FeedProblem.noGps:
        return _gap(
          const UiAlert('This phone does not report a GPS provider, so Dash cannot measure speed.',
              title: 'No GPS', status: UiStatus.danger),
        );
    }
  }

  Widget _gap(Widget w) => Padding(padding: const EdgeInsets.only(bottom: UiSpace.md), child: w);

  Widget _tripControls(BuildContext context) {
    final blocked = controller.problem == FeedProblem.permission || controller.problem == FeedProblem.permissionBlocked;
    switch (controller.tripState) {
      case TripState.idle:
        return UiButton(
          'Start trip',
          icon: Icons.play_arrow_rounded,
          expand: true,
          size: UiSize.lg,
          onPressed: blocked ? null : controller.startTrip,
        );
      case TripState.recording:
      case TripState.paused:
        final paused = controller.tripState == TripState.paused;
        return Row(
          children: [
            Expanded(
              child: UiButton(
                paused ? 'Resume' : 'Pause',
                icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                variant: UiButtonVariant.secondary,
                size: UiSize.lg,
                onPressed: paused ? controller.resumeTrip : controller.pauseTrip,
              ),
            ),
            const UiGap(UiSpace.md),
            Expanded(
              child: UiButton(
                'Stop',
                icon: Icons.stop_rounded,
                variant: UiButtonVariant.danger,
                size: UiSize.lg,
                onPressed: () => _stop(context),
              ),
            ),
          ],
        );
    }
  }

  Future<void> _stop(BuildContext context) async {
    final saved = await controller.stopTrip();
    if (!context.mounted) return;
    if (saved == null) {
      context.showSnack('Trip was too short to save.');
    } else {
      context.showSnack(
        'Trip saved: ${formatDistance(saved.distanceM, settings.unit)}',
        action: 'View',
        onAction: () => onOpenTrip(saved),
        status: UiStatus.success,
      );
    }
  }

  Widget _tripStats(BuildContext context, SpeedUnit unit) {
    final state = controller.tripState;
    final header = switch (state) {
      TripState.idle => 'Trip (not recording)',
      TripState.recording => controller.autoStarted ? 'Trip (recording, started automatically)' : 'Trip (recording)',
      TripState.paused => 'Trip (paused)',
    };
    final active = controller.tripActive;
    String speed(double ms) => active ? '${formatSpeed(ms, unit)} ${unit.label}' : '--';
    return UiListGroup(
      header: header,
      footer: active ? null : 'Tap Start trip to record distance and speed. Recording continues with the screen off.',
      children: [
        UiKeyValue('Distance', active ? formatDistance(controller.tripDistanceM, unit) : '--'),
        UiKeyValue('Duration', active ? formatDuration(controller.tripElapsed) : '--'),
        UiKeyValue('Moving time', active ? formatDuration(controller.tripMoving) : '--'),
        UiKeyValue('Average speed', speed(controller.tripAvgMs)),
        UiKeyValue('Max speed', speed(controller.tripMaxMs)),
      ],
    );
  }

  Widget _gforce(BuildContext context) {
    final r = controller.gforce;
    final sensor = controller.gSource == GSource.sensor;
    final long = r?.longG, lat = r?.latG;
    const still = 0.02;
    final longText = r == null
        ? '--'
        : long == null
            ? 'Learning direction'
            : long > still
                ? '${formatG(long)} speeding up'
                : long < -still
                    ? '${formatG(long)} braking'
                    : formatG(0);
    final latText = r == null
        ? '--'
        : lat == null
            ? 'Learning direction'
            : lat > still
                ? '${formatG(lat)} right'
                : lat < -still
                    ? '${formatG(lat)} left'
                    : formatG(0);
    final source = sensor
        ? 'Accelerometer'
        : controller.accelerometerMissing
            ? 'GPS (no accelerometer)'
            : 'GPS (accelerometer not responding)';
    final String? footer;
    if (sensor && r != null && !r.oriented) {
      footer = 'Drive for a moment: Dash learns which way your phone faces from GPS speed changes. '
          'Keep the phone fixed in its mount.';
    } else if (!sensor) {
      footer = 'Without the accelerometer, g-force comes from GPS speed and heading about once a second, '
          'so short jolts do not show.';
    } else {
      footer = null;
    }
    final peaks = controller.tripPeaks;
    return UiListGroup(
      header: 'G-force',
      footer: footer,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: UiSpace.md),
          child: Center(child: GDial(reading: r)),
        ),
        UiKeyValue('Speeding up / braking', longText),
        UiKeyValue('Cornering', latText),
        UiKeyValue('Total', r == null ? '--' : formatG(r.totalG)),
        UiKeyValue('Source', source),
        if (controller.tripActive)
          UiKeyValue(
            'Trip peaks',
            'accel ${peaks.accelG.toStringAsFixed(2)} · brake ${peaks.brakeG.toStringAsFixed(2)} · turn ${peaks.turnG.toStringAsFixed(2)} g',
          ),
      ],
    );
  }

  Widget _position(BuildContext context, SpeedUnit unit) {
    final alt = controller.altitudeM;
    final bearing = controller.bearing;
    final acc = controller.accuracyM;
    final status = switch (controller.gpsStatus) {
      GpsStatus.good => 'Good fix',
      GpsStatus.weak => 'Weak fix',
      GpsStatus.searching => 'No fix yet',
    };
    return UiListGroup(
      header: 'GPS',
      children: [
        UiKeyValue('Altitude', alt != null && controller.hasFreshFix ? '${alt.round()} m' : '--'),
        UiKeyValue('Heading', bearing != null ? '${bearing.round()}° ${headingLabel(bearing)}' : '--'),
        UiKeyValue('Accuracy', acc != null && controller.hasFreshFix ? '±${acc.round()} m' : '--'),
        UiKeyValue('Signal', status),
        UiKeyValue('Satellites', controller.satellites?.label ?? '--'),
        UiKeyValue('Odometer', formatDistance(settings.odometerM, unit)),
      ],
    );
  }
}
