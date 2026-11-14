import 'package:dash/core/chart_data.dart';
import 'package:dash/core/fix_filter.dart';
import 'package:dash/core/geo.dart';
import 'package:dash/core/gps_fix.dart';
import 'package:dash/core/gpx.dart';
import 'package:dash/core/overspeed.dart';
import 'package:dash/core/trip.dart';
import 'package:dash/core/trip_recorder.dart';
import 'package:dash/core/units.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  group('units', () {
    test('converts m/s', () {
      expect(SpeedUnit.kmh.fromMs(10), closeTo(36, 1e-9));
      expect(SpeedUnit.mph.fromMs(10), closeTo(22.369, 0.001));
      expect(SpeedUnit.knots.fromMs(10), closeTo(19.438, 0.001));
    });

    test('round trips through toMs', () {
      for (final u in SpeedUnit.values) {
        expect(u.toMs(u.fromMs(12.5)), closeTo(12.5, 1e-9));
      }
    });

    test('distance units', () {
      expect(SpeedUnit.kmh.distanceFromMeters(2500), closeTo(2.5, 1e-9));
      expect(SpeedUnit.mph.distanceFromMeters(1609.344), closeTo(1, 1e-9));
      expect(SpeedUnit.knots.distanceFromMeters(1852), closeTo(1, 1e-9));
    });

    test('formatting', () {
      expect(formatSpeed(10, SpeedUnit.kmh), '36');
      expect(formatSpeed(-3, SpeedUnit.kmh), '0');
      expect(formatDistance(1234, SpeedUnit.kmh), '1.23 km');
      expect(formatDistance(12340, SpeedUnit.kmh), '12.3 km');
      expect(formatDuration(const Duration(seconds: 75)), '1:15');
      expect(formatDuration(const Duration(seconds: 3725)), '1:02:05');
      expect(formatDateTime(DateTime(2026, 11, 3, 9, 5)), 'Nov 3, 2026 09:05');
    });

    test('fromName falls back to km/h', () {
      expect(SpeedUnit.fromName('mph'), SpeedUnit.mph);
      expect(SpeedUnit.fromName('nope'), SpeedUnit.kmh);
      expect(SpeedUnit.fromName(null), SpeedUnit.kmh);
    });
  });

  group('geo', () {
    test('haversine', () {
      expect(haversine(12, 77, 12, 77), 0);
      expect(haversine(0, 0, 1, 0), closeTo(111195, 100));
      // Delhi to Mumbai is about 1150 km.
      expect(haversine(28.6139, 77.2090, 19.0760, 72.8777), closeTo(1153000, 15000));
    });

    test('bearing and compass labels', () {
      expect(bearingBetween(0, 0, 1, 0), closeTo(0, 1e-6));
      expect(bearingBetween(0, 0, 0, 1), closeTo(90, 1e-6));
      expect(bearingBetween(1, 0, 0, 0), closeTo(180, 1e-6));
      expect(headingLabel(0), 'N');
      expect(headingLabel(44), 'NE');
      expect(headingLabel(225), 'SW');
      expect(headingLabel(359), 'N');
      expect(headingLabel(-90), 'W');
    });

    test('projectRoute puts north up and stays inside the padding', () {
      final p = projectRoute([(12.0, 77.0), (12.01, 77.01)], width: 200, height: 200, padding: 10);
      expect(p[1].$2, lessThan(p[0].$2)); // higher latitude is higher on screen
      expect(p[1].$1, greaterThan(p[0].$1));
      for (final o in p) {
        expect(o.$1, inInclusiveRange(10 - 1e-6, 190 + 1e-6));
        expect(o.$2, inInclusiveRange(10 - 1e-6, 190 + 1e-6));
      }
    });

    test('projectRoute handles one point and a straight line', () {
      final one = projectRoute([(12.0, 77.0)], width: 100, height: 100);
      expect(one.single.$1, closeTo(50, 1e-6));
      expect(one.single.$2, closeTo(50, 1e-6));
      final line = projectRoute([(12.0, 77.0), (12.0, 77.02)], width: 100, height: 100);
      expect(line[0].$2, closeTo(line[1].$2, 1e-6));
      expect(projectRoute(const [], width: 10, height: 10), isEmpty);
    });
  });

  group('gps status', () {
    test('searching, weak, good', () {
      expect(gpsStatusFor(accuracy: 5, ageMs: null), GpsStatus.searching);
      expect(gpsStatusFor(accuracy: 5, ageMs: 9000), GpsStatus.searching);
      expect(gpsStatusFor(accuracy: 40, ageMs: 1000), GpsStatus.weak);
      expect(gpsStatusFor(accuracy: null, ageMs: 1000), GpsStatus.weak);
      expect(gpsStatusFor(accuracy: 8, ageMs: 1000), GpsStatus.good);
    });

    test('fix json round trip', () {
      final f = northFix(3);
      final back = GpsFix.fromJson(f.toJson());
      expect(back.timeMs, f.timeMs);
      expect(back.lat, f.lat);
      expect(back.speed, f.speed);
      expect(back.bearing, 0);
      final bare = GpsFix.fromJson(const GpsFix(timeMs: 1, lat: 1, lon: 2).toJson());
      expect(bare.speed, isNull);
      expect(bare.accuracy, isNull);
    });
  });

  group('FixFilter', () {
    test('rejects missing and poor accuracy', () {
      final f = FixFilter();
      expect(f.process(const GpsFix(timeMs: baseMs, lat: 12, lon: 77)), isNull);
      expect(f.process(northFix(0, accuracy: 50)), isNull);
      expect(f.process(northFix(0, accuracy: 29)), isNotNull);
    });

    test('rejects old or repeated timestamps', () {
      final f = FixFilter();
      expect(f.process(northFix(5)), isNotNull);
      expect(f.process(northFix(5)), isNull);
      expect(f.process(northFix(4)), isNull);
      expect(f.process(northFix(6)), isNotNull);
    });

    test('rejects a position jump, then trusts it after a streak', () {
      final f = FixFilter(maxRejectStreak: 3);
      expect(f.process(northFix(0)), isNotNull);
      GpsFix jump(int i) => GpsFix(timeMs: baseMs + i * 1000, lat: 13.0, lon: 77.0, speed: 10, accuracy: 5);
      expect(f.process(jump(1)), isNull);
      expect(f.process(jump(2)), isNull);
      final accepted = f.process(jump(3));
      expect(accepted, isNotNull);
      expect(accepted!.distanceM, 0); // the jump itself adds no distance
      expect(f.process(jump(4)), isNotNull);
    });

    test('a single bad jump does not poison the next good fix', () {
      final f = FixFilter();
      f.process(northFix(0));
      expect(f.process(GpsFix(timeMs: baseMs + 1000, lat: 14, lon: 77, speed: 10, accuracy: 5)), isNull);
      final next = f.process(northFix(2));
      expect(next, isNotNull);
      expect(next!.distanceM, closeTo(20, 1));
    });

    test('below 1.5 km/h counts as standing still and adds no distance', () {
      final f = FixFilter();
      f.process(const GpsFix(timeMs: baseMs, lat: 12, lon: 77, speed: 0.1, accuracy: 5));
      // GPS wander of a few metres with a near zero reported speed.
      final p = f.process(const GpsFix(timeMs: baseMs + 1000, lat: 12.00003, lon: 77.00002, speed: 0.2, accuracy: 5))!;
      expect(p.moving, isFalse);
      expect(p.speedMs, 0);
      expect(p.distanceM, 0);
    });

    test('derives speed from positions when the receiver gives none', () {
      final f = FixFilter();
      f.process(northFix(0, reportedSpeed: -1));
      final p = f.process(GpsFix(timeMs: baseMs + 1000, lat: 12.0 + 10 / 111195, lon: 77, accuracy: 5))!;
      expect(p.moving, isTrue);
      expect(p.speedMs, greaterThan(3));
    });

    test('smooths speed changes', () {
      final f = FixFilter();
      f.process(northFix(0, speed: 0, reportedSpeed: 0));
      final p = f.process(northFix(1, speed: 10))!;
      expect(p.speedMs, inExclusiveRange(4, 6));
      var last = p.speedMs;
      for (var i = 2; i < 8; i++) {
        final q = f.process(northFix(i, speed: 10))!;
        expect(q.speedMs, greaterThan(last));
        last = q.speedMs;
      }
      expect(last, greaterThan(9));
    });

    test('snaps to zero when the receiver reports standstill', () {
      final f = FixFilter();
      f.process(northFix(0));
      f.process(northFix(1));
      final p = f.process(GpsFix(timeMs: baseMs + 2000, lat: 12.0002, lon: 77, speed: 0, accuracy: 5))!;
      expect(p.speedMs, 0);
      expect(p.moving, isFalse);
    });

    test('adds distance while moving', () {
      final f = FixFilter();
      var total = 0.0;
      for (var i = 0; i <= 10; i++) {
        total += f.process(northFix(i))!.distanceM;
      }
      expect(total, closeTo(100, 1));
    });

    test('reset forgets history', () {
      final f = FixFilter();
      f.process(northFix(5));
      f.reset();
      expect(f.process(northFix(1)), isNotNull);
    });
  });

  group('OverspeedMonitor', () {
    const limit = 100 / 3.6;

    test('alerts once when crossing, repeats every 5 s while over', () {
      final m = OverspeedMonitor();
      expect(m.update(speedMs: limit - 1, limitMs: limit, nowMs: 0).over, isFalse);
      final first = m.update(speedMs: limit + 1, limitMs: limit, nowMs: 1000);
      expect(first.over, isTrue);
      expect(first.alertNow, isTrue);
      expect(m.update(speedMs: limit + 1, limitMs: limit, nowMs: 3000).alertNow, isFalse);
      expect(m.update(speedMs: limit + 1, limitMs: limit, nowMs: 6000).alertNow, isTrue);
      expect(m.update(speedMs: limit + 1, limitMs: limit, nowMs: 7000).alertNow, isFalse);
    });

    test('hysteresis: hovering just under the limit stays over', () {
      final m = OverspeedMonitor();
      m.update(speedMs: limit + 1, limitMs: limit, nowMs: 0);
      for (final s in [limit - 0.1, limit - 0.5, limit + 0.2, limit - 0.7]) {
        expect(m.update(speedMs: s, limitMs: limit, nowMs: 100).over, isTrue, reason: 'speed $s');
      }
      expect(m.update(speedMs: limit - 2, limitMs: limit, nowMs: 200).over, isFalse);
      // Needs to cross the limit again to re-trigger.
      expect(m.update(speedMs: limit - 0.1, limitMs: limit, nowMs: 300).over, isFalse);
      expect(m.update(speedMs: limit + 0.1, limitMs: limit, nowMs: 400).alertNow, isTrue);
    });

    test('margin is at least 2 km/h and 3 percent of the limit', () {
      expect(OverspeedMonitor.marginFor(10), closeTo(2 / 3.6, 1e-9));
      expect(OverspeedMonitor.marginFor(40), closeTo(1.2, 1e-9));
    });

    test('no limit means no alert', () {
      final m = OverspeedMonitor();
      expect(m.update(speedMs: 50, limitMs: null, nowMs: 0).over, isFalse);
      expect(m.update(speedMs: 50, limitMs: 0, nowMs: 0).over, isFalse);
    });

    test('turning the limit off clears the state', () {
      final m = OverspeedMonitor();
      m.update(speedMs: limit + 1, limitMs: limit, nowMs: 0);
      m.update(speedMs: limit + 1, limitMs: null, nowMs: 100);
      expect(m.over, isFalse);
    });
  });

  group('TripRecorder', () {
    TripRecorder run({int fixes = 11, double speed = 10}) {
      final r = TripRecorder()..start(baseMs);
      for (var i = 1; i <= fixes; i++) {
        r.ingest(northFix(i, speed: speed));
      }
      return r;
    }

    test('computes distance, moving time, max and average speed', () {
      final r = run();
      expect(r.distanceM, closeTo(100, 1)); // 11 fixes, 10 segments
      expect(r.movingMs, 10000);
      expect(r.maxSpeedMs, closeTo(10, 0.01));
      expect(r.avgMovingSpeedMs, closeTo(10, 0.2));
      expect(r.elapsedMs(baseMs + 11000), 11000);
      expect(r.altitude, 900);
      expect(r.bearing, 0);
    });

    test('standing still adds no distance or moving time and thins points', () {
      final r = TripRecorder()..start(baseMs);
      for (var i = 1; i <= 30; i++) {
        r.ingest(GpsFix(
          timeMs: baseMs + i * 1000,
          lat: 12.0 + (i.isEven ? 0.00002 : 0),
          lon: 77.0,
          speed: 0.1,
          accuracy: 5,
        ));
      }
      expect(r.distanceM, 0);
      expect(r.movingMs, 0);
      expect(r.maxSpeedMs, 0);
      expect(r.pointCount, lessThanOrEqualTo(7)); // one per 5 s
    });

    test('pause ignores fixes and excludes paused time', () {
      final r = TripRecorder()..start(baseMs);
      for (var i = 1; i <= 4; i++) {
        r.ingest(northFix(i));
      }
      r.pause(baseMs + 5000);
      expect(r.paused, isTrue);
      expect(r.ingest(northFix(6)), isNull);
      expect(r.speedMs, 0);
      r.resume(baseMs + 8000);
      for (var i = 9; i <= 12; i++) {
        r.ingest(northFix(i));
      }
      expect(r.elapsedMs(baseMs + 10000), 7000);
      // The gap while paused is not driven distance: only 3 segments after resume.
      expect(r.distanceM, closeTo(30 + 30, 1));
      expect(r.movingMs, 3000 + 3000);
    });

    test('elapsed keeps counting wall time but freezes while paused', () {
      final r = TripRecorder()..start(baseMs);
      r.pause(baseMs + 4000);
      expect(r.elapsedMs(baseMs + 4000), 4000);
      expect(r.elapsedMs(baseMs + 60000), 4000);
    });

    test('ignores fixes before the start and duplicates', () {
      final r = TripRecorder()..start(baseMs);
      expect(r.ingest(northFix(-3)), isNull);
      expect(r.ingest(northFix(1)), isNotNull);
      expect(r.ingest(northFix(1)), isNull);
    });

    test('a gap longer than 10 s is not counted as moving time', () {
      final r = TripRecorder()..start(baseMs);
      r.ingest(northFix(1));
      r.ingest(northFix(2));
      r.ingest(northFix(40));
      expect(r.movingMs, 1000 + 0);
    });

    test('finish returns a trip, or null with no points', () {
      expect(TripRecorder().finish(baseMs), isNull);
      expect((TripRecorder()..start(baseMs)).finish(baseMs + 5000), isNull);
      final t = run().finish(baseMs + 11000)!;
      expect(t.id, baseMs.toString());
      expect(t.startMs, baseMs);
      expect(t.durationMs, 11000);
      expect(t.distanceM, closeTo(100, 1));
      expect(t.points.length, 11);
      expect(t.avgOverallSpeedMs, closeTo(100 / 11, 0.2));
    });

    test('thinPoints keeps the ends and the limit', () {
      final pts = [for (var i = 0; i < 1000; i++) TrackPoint(timeMs: i, lat: 0, lon: 0, speedMs: 0)];
      final out = thinPoints(pts, 100);
      expect(out.length, 100);
      expect(out.first.timeMs, 0);
      expect(out.last.timeMs, 999);
      expect(thinPoints(pts.take(5).toList(), 100).length, 5);
    });
  });

  group('track log', () {
    test('parses markers and fixes, skipping broken lines', () {
      final log = [
        '{"e":"start","t":$baseMs}',
        '{"t":${baseMs + 1000},"la":12.0,"lo":77.0,"sp":10.0,"ac":5.0}',
        'not json',
        '',
        '{"e":"pause","t":${baseMs + 2000}}',
        '{"e":"resume","t":${baseMs + 3000}}',
        '{"e":"bogus"}',
        '{"t":${baseMs + 4000},"la":12.0', // half written
      ].join('\n');
      final events = parseTrackLog(log);
      expect(events.length, 4);
      expect(events[0], isA<StartEvent>());
      expect(events[1], isA<FixEvent>());
      expect(events[2], isA<PauseEvent>());
      expect(events[3], isA<ResumeEvent>());
    });

    test('replaying a log gives the same trip as live ingestion', () {
      final live = TripRecorder()..start(baseMs);
      final lines = StringBuffer('{"e":"start","t":$baseMs}\n');
      for (var i = 1; i <= 20; i++) {
        final f = northFix(i, speed: 8 + (i % 3));
        live.ingest(f);
        lines.writeln(_json(f));
      }
      final replay = TripRecorder.fromEvents(parseTrackLog(lines.toString()));
      expect(replay.distanceM, closeTo(live.distanceM, 1e-6));
      expect(replay.movingMs, live.movingMs);
      expect(replay.maxSpeedMs, live.maxSpeedMs);
    });

    test('live fixes already in the log are not counted twice', () {
      final r = TripRecorder()..start(baseMs);
      for (var i = 1; i <= 5; i++) {
        r.ingest(northFix(i));
      }
      final before = r.distanceM;
      for (var i = 1; i <= 5; i++) {
        r.ingest(northFix(i));
      }
      expect(r.distanceM, before);
    });
  });

  group('trip json and chart data', () {
    test('round trips with points', () {
      final t = sampleTrip();
      final back = Trip.fromJson(t.toJson());
      expect(back.id, t.id);
      expect(back.points.length, t.points.length);
      expect(back.points[3].lat, t.points[3].lat);
      expect(back.points[3].speedMs, closeTo(t.points[3].speedMs, 0.01));
      expect(back.maxSpeedMs, t.maxSpeedMs);
    });

    test('summary has no points', () {
      final t = Trip.fromJson(sampleTrip().toSummaryJson());
      expect(t.points, isEmpty);
      expect(sampleTrip().withoutPoints().points, isEmpty);
    });

    test('resampleSpeeds interpolates over time', () {
      final pts = [
        const TrackPoint(timeMs: 0, lat: 0, lon: 0, speedMs: 0),
        const TrackPoint(timeMs: 1000, lat: 0, lon: 0, speedMs: 10),
        const TrackPoint(timeMs: 2000, lat: 0, lon: 0, speedMs: 0),
      ];
      final s = resampleSpeeds(pts, 5);
      expect(s, [0, 5, 10, 5, 0]);
      expect(resampleSpeeds(const [], 5), isEmpty);
      expect(resampleSpeeds([pts.first], 3), [0, 0, 0]);
    });
  });

  group('gpx', () {
    test('writes a valid track with time, elevation and speed', () {
      final gpx = buildGpx(sampleTrip(points: 3), name: 'A & B <trip>');
      expect(gpx, startsWith('<?xml version="1.0" encoding="UTF-8"?>'));
      expect(gpx, contains('<gpx version="1.1" creator="Dash"'));
      expect(gpx, contains('A &amp; B &lt;trip&gt;'));
      expect('<trkpt '.allMatches(gpx).length, 3);
      expect(gpx, contains('<trkpt lat="12.000000" lon="77.000000">'));
      expect(gpx, contains('<ele>900.0</ele>'));
      expect(gpx, contains('<time>2023-11-14T22:13:20.000Z</time>'));
      expect(gpx, contains('<speed>10.00</speed>'));
      expect(gpx.trimRight(), endsWith('</gpx>'));
    });

    test('omits elevation when unknown', () {
      final t = Trip(
        id: '1',
        startMs: baseMs,
        endMs: baseMs,
        distanceM: 0,
        durationMs: 0,
        movingMs: 0,
        maxSpeedMs: 0,
        points: const [TrackPoint(timeMs: baseMs, lat: 1, lon: 2, speedMs: 0)],
      );
      expect(buildGpx(t), isNot(contains('<ele>')));
    });
  });
}

String _json(GpsFix f) {
  final m = f.toJson();
  return '{${m.entries.map((e) => '"${e.key}":${e.value}').join(',')}}';
}
