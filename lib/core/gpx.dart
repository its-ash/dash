import 'trip.dart';

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

String _time(int ms) => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();

/// Serialises a trip as a GPX 1.1 document with one track and one segment.
/// Speed (m/s) is written as a `<speed>` extension on each point.
String buildGpx(Trip trip, {String? name, String creator = 'Dash'}) {
  final title = name ?? 'Dash trip ${_time(trip.startMs)}';
  final b = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<gpx version="1.1" creator="${_esc(creator)}" xmlns="http://www.topografix.com/GPX/1/1">')
    ..writeln('  <metadata><name>${_esc(title)}</name><time>${_time(trip.startMs)}</time></metadata>')
    ..writeln('  <trk>')
    ..writeln('    <name>${_esc(title)}</name>')
    ..writeln('    <trkseg>');
  for (final p in trip.points) {
    b.write('      <trkpt lat="${p.lat.toStringAsFixed(6)}" lon="${p.lon.toStringAsFixed(6)}">');
    if (p.altitude != null) b.write('<ele>${p.altitude!.toStringAsFixed(1)}</ele>');
    b.write('<time>${_time(p.timeMs)}</time>');
    b.write('<extensions><speed>${p.speedMs.toStringAsFixed(2)}</speed></extensions>');
    b.writeln('</trkpt>');
  }
  b
    ..writeln('    </trkseg>')
    ..writeln('  </trk>')
    ..writeln('</gpx>');
  return b.toString();
}
