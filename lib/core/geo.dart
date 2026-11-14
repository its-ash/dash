import 'dart:math' as math;

const double earthRadiusM = 6371008.8;

double _rad(double deg) => deg * math.pi / 180.0;

/// Great-circle distance in metres between two coordinates (haversine).
double haversine(double lat1, double lon1, double lat2, double lon2) {
  final dLat = _rad(lat2 - lat1);
  final dLon = _rad(lon2 - lon1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(_rad(lat1)) * math.cos(_rad(lat2)) * math.pow(math.sin(dLon / 2), 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadiusM * c;
}

/// Initial bearing in degrees (0..360, 0 = north) from point 1 to point 2.
double bearingBetween(double lat1, double lon1, double lat2, double lon2) {
  final p1 = _rad(lat1);
  final p2 = _rad(lat2);
  final dl = _rad(lon2 - lon1);
  final y = math.sin(dl) * math.cos(p2);
  final x = math.cos(p1) * math.sin(p2) - math.sin(p1) * math.cos(p2) * math.cos(dl);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

const _compass = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];

/// Eight-point compass label for a heading in degrees.
String headingLabel(double degrees) {
  final d = ((degrees % 360) + 360) % 360;
  return _compass[((d + 22.5) ~/ 45) % 8];
}

/// Projects `(lat, lon)` points to a `width` x `height` box, keeping the
/// aspect ratio (equirectangular, longitude scaled by cos(latitude)) and
/// centring the route with `padding`. North is up. Returns `(x, y)` pairs.
List<(double, double)> projectRoute(
  List<(double, double)> latLon, {
  required double width,
  required double height,
  double padding = 12,
}) {
  if (latLon.isEmpty) return const [];
  var minLat = latLon.first.$1, maxLat = minLat;
  var minLon = latLon.first.$2, maxLon = minLon;
  for (final p in latLon) {
    minLat = math.min(minLat, p.$1);
    maxLat = math.max(maxLat, p.$1);
    minLon = math.min(minLon, p.$2);
    maxLon = math.max(maxLon, p.$2);
  }
  final midLat = (minLat + maxLat) / 2;
  final k = math.cos(_rad(midLat));
  final spanX = (maxLon - minLon) * k;
  final spanY = maxLat - minLat;
  final availW = math.max(1.0, width - 2 * padding);
  final availH = math.max(1.0, height - 2 * padding);
  // A single point or a perfectly straight line still gets a finite scale.
  final scale = math.min(
    spanX > 1e-9 ? availW / spanX : double.infinity,
    spanY > 1e-9 ? availH / spanY : double.infinity,
  );
  final s = scale.isFinite ? scale : 1.0;
  final offX = (width - spanX * s) / 2;
  final offY = (height - spanY * s) / 2;
  return [
    for (final p in latLon) (offX + (p.$2 - minLon) * k * s, offY + (maxLat - p.$1) * s),
  ];
}
