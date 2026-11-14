import 'dart:convert';
import 'dart:io';

import '../core/trip.dart';

/// Where finished trips live. Summaries are listed newest first; the points
/// are loaded only for the detail screen.
abstract class TripRepository {
  Future<List<Trip>> list();
  Future<Trip?> load(String id);
  Future<void> save(Trip trip);
  Future<void> delete(String id);
}

/// Trips as JSON files in [dir]: `index.json` (summaries) and one
/// `trip_<id>.json` per trip with its points.
class FileTripRepository implements TripRepository {
  FileTripRepository(this.dir);

  final Directory dir;

  File get _index => File('${dir.path}/index.json');
  File _tripFile(String id) => File('${dir.path}/trip_$id.json');

  Future<List<Trip>> _readIndex() async {
    try {
      if (!await _index.exists()) return [];
      final list = jsonDecode(await _index.readAsString()) as List;
      return [for (final j in list) Trip.fromJson((j as Map).cast<String, Object?>())];
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeIndex(List<Trip> trips) async {
    await dir.create(recursive: true);
    await _index.writeAsString(jsonEncode([for (final t in trips) t.toSummaryJson()]));
  }

  @override
  Future<List<Trip>> list() async {
    final trips = await _readIndex();
    trips.sort((a, b) => b.startMs.compareTo(a.startMs));
    return trips;
  }

  @override
  Future<Trip?> load(String id) async {
    try {
      final f = _tripFile(id);
      if (!await f.exists()) return null;
      return Trip.fromJson((jsonDecode(await f.readAsString()) as Map).cast<String, Object?>());
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(Trip trip) async {
    await dir.create(recursive: true);
    await _tripFile(trip.id).writeAsString(jsonEncode(trip.toJson()));
    final trips = await _readIndex();
    trips.removeWhere((t) => t.id == trip.id);
    trips.add(trip.withoutPoints());
    await _writeIndex(trips);
  }

  @override
  Future<void> delete(String id) async {
    final f = _tripFile(id);
    if (await f.exists()) await f.delete();
    final trips = await _readIndex();
    trips.removeWhere((t) => t.id == id);
    await _writeIndex(trips);
  }
}

/// In-memory repository for tests.
class MemoryTripRepository implements TripRepository {
  final Map<String, Trip> _trips = {};

  @override
  Future<List<Trip>> list() async =>
      ([for (final t in _trips.values) t.withoutPoints()]..sort((a, b) => b.startMs.compareTo(a.startMs)));

  @override
  Future<Trip?> load(String id) async => _trips[id];

  @override
  Future<void> save(Trip trip) async => _trips[trip.id] = trip;

  @override
  Future<void> delete(String id) async => _trips.remove(id);
}
