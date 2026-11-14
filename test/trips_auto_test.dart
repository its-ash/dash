import 'package:dash/core/chart_data.dart';
import 'package:dash/core/gforce.dart';
import 'package:dash/core/gps_fix.dart';
import 'package:dash/core/trip.dart';
import 'package:dash/core/trip_recorder.dart';
import 'package:dash/settings/settings_store.dart';
import 'package:dash/state/dash_controller.dart';
import 'package:dash/storage/trip_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

Future<void> flush() => Future<void>.delayed(const Duration(milliseconds: 5));

void main() {
  group('harsh events', () {
    GReading r({double long = 0, double lat = 0}) =>
        GReading(totalG: 0, source: GSource.gps, longG: long, latG: lat);

    test('only readings over the threshold count, and close ones merge', () {
      final d = HarshDetector();
      d.add(r(long: -0.2), timeMs: 0, lat: 1, lon: 2);
      expect(d.events, isEmpty);
      d.add(r(long: -0.4), timeMs: 1000, lat: 1, lon: 2);
      d.add(r(long: -0.5), timeMs: 3000, lat: 1.1, lon: 2);
      d.add(r(long: -0.36), timeMs: 4000, lat: 1.2, lon: 2);
      expect(d.events, hasLength(1));
      expect(d.events.single.g, 0.5);
      expect(d.events.single.lat, 1.1);

      d.add(r(long: -0.4), timeMs: 20000, lat: 3, lon: 4);
      d.add(r(lat: -0.45), timeMs: 20000, lat: 3, lon: 4);
      d.add(r(long: 0.31), timeMs: 30000, lat: 5, lon: 6);
      expect([for (final e in d.events) e.kind], [HarshKind.brake, HarshKind.brake, HarshKind.turn, HarshKind.accel]);
    });

    test('merging GPS and sensor events keeps one per moment, in time order', () {
      const a = HarshEvent(timeMs: 1000, lat: 1, lon: 1, kind: HarshKind.brake, g: 0.4);
      const b = HarshEvent(timeMs: 2500, lat: 1, lon: 1, kind: HarshKind.brake, g: 0.6);
      const c = HarshEvent(timeMs: 500, lat: 2, lon: 2, kind: HarshKind.turn, g: 0.5);
      final m = mergeHarshEvents([a], [b, c]);
      expect(m, hasLength(2));
      expect(m.first.kind, HarshKind.turn);
      expect(m.last.g, 0.6);
    });

    test('events survive the trip JSON', () {
      const e = HarshEvent(timeMs: 5, lat: 12.5, lon: 77.25, kind: HarshKind.turn, g: 0.4321);
      final t = Trip.fromJson(sampleTrip().withGForce(GPeaks(turnG: 0.43), [e]).toJson());
      expect(t.events.single.kind, HarshKind.turn);
      expect(t.events.single.g, 0.432);
      expect(t.events.single.lon, 77.25);
      expect(Trip.fromJson(sampleTrip().toJson()).events, isEmpty);
    });

    test('the recorder finds hard braking from GPS Doppler speed', () {
      final rec = TripRecorder()..start(baseMs);
      var lat = 12.0;
      final speeds = [for (var i = 0; i < 10; i++) 20.0, 15.0, 10.0, 5.0, 2.0, 2.0];
      for (var i = 0; i < speeds.length; i++) {
        lat += speeds[i] / 111195.0;
        rec.ingest(GpsFix(timeMs: baseMs + (i + 1) * 1000, lat: lat, lon: 77, speed: speeds[i], accuracy: 5, bearing: 0));
      }
      final braking = rec.gpsEvents.where((e) => e.kind == HarshKind.brake).toList();
      expect(braking, hasLength(1));
      expect(braking.single.g, closeTo(5 / gravityMs2, 0.01));
    });
  });

  group('stop marker', () {
    test('a trip ended outside the app ends at the stop time and drops later points', () {
      final events = <TrackEvent>[const StartEvent(baseMs)];
      for (var i = 1; i <= 20; i++) {
        events.add(FixEvent(northFix(i, speed: i <= 10 ? 10 : 0)));
      }
      events.add(const StopEvent(baseMs + 10000));
      final r = TripRecorder.fromEvents(events);
      final trip = r.finish(baseMs + 999999)!;
      expect(trip.endMs, baseMs + 10000);
      expect(trip.durationMs, 10000);
      expect(trip.points.last.timeMs, lessThanOrEqualTo(baseMs + 10000));
      expect(trip.distanceM, closeTo(90, 15));
    });

    test('parses the stop line', () {
      final e = parseTrackLog('{"e":"start","t":1}\n{"e":"stop","t":9}\n');
      expect(e.last, isA<StopEvent>());
    });
  });

  group('altitude', () {
    List<TrackPoint> pts(List<double?> alts) => [
          for (var i = 0; i < alts.length; i++) TrackPoint(timeMs: i * 1000, lat: 0, lon: 0, speedMs: 5, altitude: alts[i]),
        ];

    test('climb and descent ignore GPS wobble below the hysteresis', () {
      final r = climbAndDescent(pts([100, 102, 99, 101, 110, 120, 118, 121, 105, 100]))!;
      // 100 -> 110 -> 120 counted; 121 is within 5 m of 120, so it is wobble.
      expect(r.climbM, closeTo(20, 0.01));
      // 120 -> 105 -> 100.
      expect(r.descentM, closeTo(20, 0.01));
      expect(r.minM, 99);
      expect(r.maxM, 121);
    });

    test('no profile without altitudes', () {
      expect(climbAndDescent(pts([null, null])), isNull);
      expect(resampleAltitudes(pts([null, 5, null]), 10), isEmpty);
      expect(resampleAltitudes(pts([0, null, 10]), 3), [0, 5, 10]);
    });
  });

  group('automatic trips and the widget', () {
    late FakePlatform platform;
    late SettingsStore settings;
    late MemoryTripRepository repo;
    late DashController c;
    var now = baseMs;

    setUp(() {
      now = baseMs;
      platform = FakePlatform()..clock = () => now;
      settings = SettingsStore.memory();
      repo = MemoryTripRepository();
      c = DashController(
        platform: platform,
        settings: settings,
        repository: repo,
        now: () => now,
        tick: const Duration(milliseconds: 1),
      );
    });

    tearDown(() async {
      c.dispose();
      await platform.close();
    });

    Future<void> drive(int from, int to, {double speed = 10}) async {
      for (var i = from; i <= to; i++) {
        now = baseMs + i * 1000;
        platform.emit(northFix(i, speed: speed));
        await flush();
      }
    }

    test('starts a trip after 20 s above 15 km/h, without the permission dialog', () async {
      await c.start();
      expect(platform.autoStop, autoStopAfter);
      await drive(1, 15);
      expect(c.tripActive, isFalse);
      await drive(16, 26);
      expect(c.tripActive, isTrue);
      expect(c.autoStarted, isTrue);
    });

    test('slow driving or the setting off never starts a trip', () async {
      await c.start();
      await drive(1, 40, speed: 3);
      expect(c.tripActive, isFalse);

      settings.setAutoTrips(false);
      await flush();
      expect(platform.autoStop, Duration.zero);
      await drive(41, 80);
      expect(c.tripActive, isFalse);
    });

    test('saves a trip the service ended by itself and tells the widget', () async {
      await c.start();
      await c.startTrip();
      await drive(1, 30);
      platform.endInBackground(baseMs + 30000);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(c.tripActive, isFalse);
      final trips = await repo.list();
      expect(trips, hasLength(1));
      expect(c.autoSaved?.id, trips.single.id);
      expect(platform.pending, isEmpty);
      expect(settings.odometerM, greaterThan(250));
      expect(platform.widget?.lastTrip, startsWith('Last trip'));
    });

    test('a pending trip from while the app was closed is saved on start', () async {
      final log = StringBuffer('{"e":"start","t":$baseMs}\n');
      for (var i = 1; i <= 20; i++) {
        final m = northFix(i).toJson();
        log.writeln('{${m.entries.map((e) => '"${e.key}":${e.value}').join(',')}}');
      }
      log.writeln('{"e":"stop","t":${baseMs + 20000}}');
      platform.pending['x.jsonl'] = log.toString();
      await c.start();
      expect((await repo.list()), hasLength(1));
      expect(platform.pending, isEmpty);
      expect(platform.widget?.odometer, isNot('0.00 km'));
    });
  });
}
