import 'dart:io';

import 'package:dash/core/trip.dart';
import 'package:dash/core/units.dart';
import 'package:dash/settings/settings_store.dart';
import 'package:dash/storage/trip_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('dash_trips_test');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('saves, lists newest first, loads points and deletes', () async {
    final repo = FileTripRepository(Directory('${dir.path}/trips'));
    expect(await repo.list(), isEmpty);

    final older = sampleTrip(id: 'a');
    final base = sampleTrip(id: 'b');
    final newer = Trip(
      id: 'b',
      startMs: baseMs + 86400000,
      endMs: baseMs + 86460000,
      distanceM: base.distanceM,
      durationMs: base.durationMs,
      movingMs: base.movingMs,
      maxSpeedMs: base.maxSpeedMs,
      points: base.points,
    );
    await repo.save(older);
    await repo.save(newer);

    final list = await repo.list();
    expect(list.map((t) => t.id), ['b', 'a']);
    expect(list.first.points, isEmpty); // summaries only

    final full = await repo.load('a');
    expect(full!.points.length, older.points.length);
    expect(full.distanceM, older.distanceM);

    await repo.save(older); // saving again replaces, no duplicate
    expect((await repo.list()).length, 2);

    await repo.delete('a');
    expect((await repo.list()).map((t) => t.id), ['b']);
    expect(await repo.load('a'), isNull);
  });

  test('survives a damaged index', () async {
    final repo = FileTripRepository(dir);
    await File('${dir.path}/index.json').writeAsString('{oops');
    expect(await repo.list(), isEmpty);
    await repo.save(sampleTrip(id: 'x'));
    expect((await repo.list()).single.id, 'x');
  });

  test('settings are saved and restored', () async {
    SharedPreferences.setMockInitialValues({});
    final s = await SettingsStore.load();
    expect(s.activeLimitMs, isNull);
    s.setUnit(SpeedUnit.mph);
    s.setLimitEnabled(true);
    s.setLimitMs(20);
    s.setAnalog(true);
    s.setHudMirror(false);
    s.addOdometer(1500);
    s.addOdometer(500);
    final again = await SettingsStore.load();
    expect(again.unit, SpeedUnit.mph);
    expect(again.activeLimitMs, 20);
    expect(again.analog, isTrue);
    expect(again.hudMirror, isFalse);
    expect(again.odometerM, 2000);
    again.resetOdometer();
    expect((await SettingsStore.load()).odometerM, 0);
  });
}
