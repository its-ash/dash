import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../core/trip.dart';
import '../core/units.dart';
import '../settings/settings_store.dart';
import '../storage/trip_repository.dart';
import 'trip_detail_screen.dart';

/// Trip history, newest first, with the odometer total on top.
class TripsScreen extends StatefulWidget {
  const TripsScreen({super.key, required this.repository, required this.settings});

  final TripRepository repository;
  final SettingsStore settings;

  @override
  State<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends State<TripsScreen> {
  late Future<List<Trip>> _trips = widget.repository.list();

  void _reload() => setState(() => _trips = widget.repository.list());

  Future<void> _open(Trip t) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => TripDetailScreen(tripId: t.id, repository: widget.repository, settings: widget.settings),
    ));
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return UiScaffold(
      appBar: const UiAppBar(title: 'Trips', back: true),
      scrollable: true,
      body: ListenableBuilder(
        listenable: widget.settings,
        builder: (context, _) {
          final unit = widget.settings.unit;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              UiListGroup(
                header: 'Odometer',
                footer: 'Total of all trips you have recorded. Deleting a trip does not change it.',
                children: [
                  UiListTile(
                    formatDistance(widget.settings.odometerM, unit),
                    icon: Icons.speed_rounded,
                    trailing: widget.settings.odometerM > 0
                        ? UiButton('Reset', variant: UiButtonVariant.ghost, size: UiSize.sm, onPressed: _confirmReset)
                        : null,
                  ),
                ],
              ),
              const UiGap(UiSpace.lg),
              FutureBuilder<List<Trip>>(
                future: _trips,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(UiSpace.xl),
                      child: Center(child: UiSpinner()),
                    );
                  }
                  final trips = snap.data ?? const <Trip>[];
                  if (trips.isEmpty) {
                    return const UiEmptyState(
                      icon: Icons.route_rounded,
                      title: 'No trips yet',
                      message: 'Start a trip on the home screen. It is saved here when you stop.',
                    );
                  }
                  return UiListGroup(
                    header: 'History',
                    children: [
                      for (final t in trips)
                        UiListTile(
                          formatDateTime(DateTime.fromMillisecondsSinceEpoch(t.startMs)),
                          subtitle: '${formatDistance(t.distanceM, unit)} · ${formatDuration(Duration(milliseconds: t.durationMs))}'
                              ' · avg ${formatSpeed(t.avgMovingSpeedMs, unit)} ${unit.label}',
                          icon: Icons.route_rounded,
                          chevron: true,
                          onTap: () => _open(t),
                        ),
                    ],
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmReset() async {
    final ok = await UiDialog.confirm(
      context,
      title: 'Reset odometer?',
      message: 'The total distance goes back to zero. Your saved trips stay.',
      confirmLabel: 'Reset',
      destructive: true,
    );
    if (ok) widget.settings.resetOdometer();
  }
}
