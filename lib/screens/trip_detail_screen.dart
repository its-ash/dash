import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../core/chart_data.dart';
import '../core/trip.dart';
import '../core/units.dart';
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
  });

  final String tripId;
  final TripRepository repository;
  final SettingsStore settings;

  /// Opens the share sheet for the GPX file. Replaced in tests.
  final Future<void> Function(Trip trip) share;

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          formatDateTime(DateTime.fromMillisecondsSinceEpoch(trip.startMs)),
          style: context.text.titleLarge,
        ),
        const UiGap(UiSpace.md),
        RouteView(points: trip.points),
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
        const UiGap(UiSpace.lg),
        UiButton(
          'Export GPX',
          icon: Icons.ios_share_rounded,
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
