import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/gpx.dart';
import '../core/trip.dart';
import '../core/units.dart';

/// File name for a trip's GPX export, e.g. `dash-2026-11-13-1405.gpx`.
String gpxFileName(Trip trip) {
  final d = DateTime.fromMillisecondsSinceEpoch(trip.startMs);
  String two(int v) => v.toString().padLeft(2, '0');
  return 'dash-${d.year}-${two(d.month)}-${two(d.day)}-${two(d.hour)}${two(d.minute)}.gpx';
}

/// Opens the share sheet with plain text (a Google Maps link to a trip).
Future<void> shareMapsLink(String text) async {
  await SharePlus.instance.share(ShareParams(text: text, subject: 'Dash trip'));
}

/// Writes the trip as a GPX file in the cache folder and opens the Android
/// share sheet for it.
Future<void> shareTripGpx(Trip trip) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/${gpxFileName(trip)}');
  await file.writeAsString(buildGpx(trip, name: 'Dash trip ${formatDateTime(DateTime.fromMillisecondsSinceEpoch(trip.startMs))}'));
  await SharePlus.instance.share(
    ShareParams(files: [XFile(file.path, mimeType: 'application/gpx+xml')], title: 'Dash trip', subject: 'Dash trip'),
  );
}
