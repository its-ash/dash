import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../core/chart_data.dart';
import '../core/gforce.dart';
import '../core/maps_link.dart';
import '../core/trip.dart';
import '../core/units.dart';
import '../platform/dash_platform.dart';
import '../platform/gpx_share.dart';
import '../settings/settings_store.dart';
import '../storage/trip_repository.dart';
import '../widgets/route_view.dart';

/// One saved trip: route, speed over time, totals, GPX export and delete.
class TripDetailScreen extends StatefulWidget {
  const TripDetailScreen({
    super.key,
    required this.tripId,
    required this.repository,
    required this.settings,
    this.share = shareTripGpx,
    this.openUrl = openExternalUrl,
    this.shareText = shareMapsLink,
  });

  final String tripId;
  final TripRepository repository;
  final SettingsStore settings;

  /// Opens the share sheet for the GPX file. Replaced in tests.
  final Future<void> Function(Trip trip) share;

  /// Opens a link in Google Maps (or the browser). Replaced in tests.
  final Future<bool> Function(Uri url) openUrl;

  /// Opens the share sheet with a Google Maps link. Replaced in tests.
  final Future<void> Function(String text) shareText;

  @override
  State<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<TripDetailScreen> {
  late final Future<Trip?> _trip = widget.repository.load(widget.tripId);

  Future<void> _export(Trip trip) async {
    try {
      await widget.share(trip);
    } catch (_) {
      if (mounted) context.showSnack('Could not share the GPX file.', status: UiStatus.danger);
    }
  }

  Future<void> _openMaps(Uri url) async {
    final ok = await widget.openUrl(url).catchError((Object _) => false);
    if (!ok && mounted) context.showSnack('Could not open Google Maps.', status: UiStatus.danger);
  }

  Future<void> _shareMaps(Trip trip, Uri url) async {
    try {
      await widget.shareText('Dash trip, ${formatDateTime(DateTime.fromMillisecondsSinceEpoch(trip.startMs))}\n$url');
    } catch (_) {
      if (mounted) context.showSnack('Could not share the link.', status: UiStatus.danger);
    }
  }

  static String _clock(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.hour)}:${two(d.minute)}';
  }

  Future<void> _delete(Trip trip) async {
    final ok = await UiDialog.confirm(
      context,
      title: 'Delete this trip?',
      message: 'The trip and its route are removed. The odometer keeps its total.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    await widget.repository.delete(trip.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return UiScaffold(
      appBar: const UiAppBar(title: 'Trip', back: true),
      scrollable: true,
      body: FutureBuilder<Trip?>(
        future: _trip,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Padding(padding: EdgeInsets.all(UiSpace.xl), child: Center(child: UiSpinner()));
          }
          final trip = snap.data;
          if (trip == null) {
            return const UiEmptyState(
              icon: Icons.error_outline_rounded,
              title: 'Trip not found',
              message: 'It may have been deleted.',
            );
          }
          return ListenableBuilder(
            listenable: widget.settings,
            builder: (context, _) => _content(context, trip),
          );
        },
      ),
    );
  }

  Widget _content(BuildContext context, Trip trip) {
    final unit = widget.settings.unit;
    final speeds = [for (final v in resampleSpeeds(trip.points, 80)) unit.fromMs(v)];
    final mapsUrl = tripMapsUrl(trip);
    final altitudes = resampleAltitudes(trip.points, 80);
    final climb = climbAndDescent(trip.points);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          formatDateTime(DateTime.fromMillisecondsSinceEpoch(trip.startMs)),
          style: context.text.titleLarge,
        ),
        const UiGap(UiSpace.md),
        RouteView(points: trip.points, events: trip.events),
        const UiGap(UiSpace.sm),
        RouteLegend(points: trip.points, events: trip.events, unit: unit),
        const UiGap(UiSpace.lg),
        UiCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Speed over time (${unit.label})', style: context.text.titleSmall),
              const UiGap(UiSpace.sm),
              if (speeds.length < 2)
                Text('Not enough data for a chart.', style: context.text.bodySmall)
              else
                UiLineChart(
                  series: [UiChartSeries('Speed', speeds)],
                  height: 180,
                  curved: false,
                  showLegend: false,
                  yFormat: (v) => v.toStringAsFixed(0),
                ),
            ],
          ),
        ),
        if (altitudes.length >= 2 && climb != null) ...[
          const UiGap(UiSpace.lg),
          UiCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Altitude (m)', style: context.text.titleSmall),
                const UiGap(UiSpace.sm),
                UiLineChart(
                  series: [UiChartSeries('Altitude', altitudes)],
                  height: 140,
                  curved: false,
                  area: true,
                  showLegend: false,
                  yFormat: (v) => v.toStringAsFixed(0),
                ),
                const UiGap(UiSpace.sm),
                Text(
                  'Climb ${climb.climbM.round()} m · descent ${climb.descentM.round()} m · '
                  '${climb.minM.round()} to ${climb.maxM.round()} m',
                  style: context.text.bodySmall?.copyWith(color: context.colors.textMuted),
                ),
              ],
            ),
          ),
        ],
        const UiGap(UiSpace.lg),
        UiListGroup(
          header: 'Summary',
          children: [
            UiKeyValue('Distance', formatDistance(trip.distanceM, unit)),
            UiKeyValue('Duration', formatDuration(Duration(milliseconds: trip.durationMs))),
            UiKeyValue('Moving time', formatDuration(Duration(milliseconds: trip.movingMs))),
            UiKeyValue('Average speed (moving)', '${formatSpeed(trip.avgMovingSpeedMs, unit)} ${unit.label}'),
            UiKeyValue('Average speed (overall)', '${formatSpeed(trip.avgOverallSpeedMs, unit)} ${unit.label}'),
            UiKeyValue('Max speed', '${formatSpeed(trip.maxSpeedMs, unit)} ${unit.label}'),
            UiKeyValue('Points', '${trip.points.length}'),
          ],
        ),
        if (trip.hasPeaks) ...[
          const UiGap(UiSpace.lg),
          UiListGroup(
            header: 'Peak g-force',
            children: [
              UiKeyValue('Speeding up', formatG(trip.peakAccelG ?? 0)),
              UiKeyValue('Braking', formatG(trip.peakBrakeG ?? 0)),
              UiKeyValue('Cornering', formatG(trip.peakTurnG ?? 0)),
            ],
          ),
          const UiGap(UiSpace.lg),
          UiListGroup(
            header: 'Harsh moments',
            footer: trip.events.isEmpty
                ? 'No hard braking, hard acceleration or sharp cornering on this trip.'
                : 'Marked on the route above. Braking counts from ${formatG(HarshKind.brake.thresholdG)}, '
                    'acceleration from ${formatG(HarshKind.accel.thresholdG)}, '
                    'cornering from ${formatG(HarshKind.turn.thresholdG)}.',
            children: [
              if (trip.events.isEmpty)
                const UiKeyValue('Smooth drive', 'None')
              else
                for (final e in trip.events)
                  UiKeyValue.custom(
                    '${_clock(e.timeMs)}  ${e.kind.label}',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(formatG(e.g), style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                        const UiGap(UiSpace.sm),
                        HarshMarker(kind: e.kind),
                      ],
                    ),
                  ),
            ],
          ),
        ],
        const UiGap(UiSpace.lg),
        if (mapsUrl != null) ...[
          UiButton(
            'Open in Google Maps',
            icon: Icons.map_outlined,
            variant: UiButtonVariant.primary,
            expand: true,
            onPressed: () => _openMaps(mapsUrl),
          ),
          const UiGap(UiSpace.sm),
          UiButton(
            'Share Maps link',
            icon: Icons.share_rounded,
            variant: UiButtonVariant.secondary,
            expand: true,
            onPressed: () => _shareMaps(trip, mapsUrl),
          ),
          const UiGap(UiSpace.xs),
          Text(
            'Google Maps draws a road route through the start, the end and up to $mapsWaypoints stops along your trip, so it follows your drive closely but not exactly.',
            style: context.text.bodySmall?.copyWith(color: context.colors.textSubtle),
          ),
          const UiGap(UiSpace.md),
        ],
        UiButton(
          'Export GPX',
          icon: Icons.ios_share_rounded,
          variant: UiButtonVariant.secondary,
          expand: true,
          onPressed: () => _export(trip),
        ),
        const UiGap(UiSpace.sm),
        UiButton(
          'Delete trip',
          icon: Icons.delete_outline_rounded,
          variant: UiButtonVariant.danger,
          expand: true,
          onPressed: () => _delete(trip),
        ),
        const UiGap(UiSpace.lg),
      ],
    );
  }
}
