import 'geo.dart';
import 'trip.dart';

/// Stops between start and end in a Google Maps link. The Maps app accepts
/// up to 9; fewer keeps the link short enough for every share target.
const int mapsWaypoints = 8;

/// A Google Maps directions link (Maps URLs, no API key) that follows a
/// recorded trip: start, end, and [waypoints] stops spread evenly by distance
/// along the route. Maps draws its own road route through those stops, so it
/// matches the drive closely but not point for point. Null when the trip has
/// fewer than two points.
Uri? tripMapsUrl(Trip trip, {int waypoints = mapsWaypoints, String travelMode = 'driving'}) {
  final pts = trip.points;
  if (pts.length < 2) return null;

  // Cumulative distance along the route, to place stops evenly by distance.
  final cum = List<double>.filled(pts.length, 0);
  for (var i = 1; i < pts.length; i++) {
    cum[i] = cum[i - 1] + haversine(pts[i - 1].lat, pts[i - 1].lon, pts[i].lat, pts[i].lon);
  }
  final total = cum.last;

  final stops = <TrackPoint>[];
  if (total > 0 && waypoints > 0) {
    var j = 0;
    for (var k = 1; k <= waypoints; k++) {
      final target = total * k / (waypoints + 1);
      while (j < pts.length - 1 && cum[j] < target) {
        j++;
      }
      final p = pts[j];
      if (j == 0 || j == pts.length - 1) continue;
      if (stops.isNotEmpty && identical(stops.last, p)) continue;
      stops.add(p);
    }
  }

  String ll(TrackPoint p) => '${p.lat.toStringAsFixed(6)},${p.lon.toStringAsFixed(6)}';
  return Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    'origin': ll(pts.first),
    'destination': ll(pts.last),
    if (stops.isNotEmpty) 'waypoints': stops.map(ll).join('|'),
    'travelmode': travelMode,
  });
}
