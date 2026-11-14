import 'package:dash/core/gforce.dart';
import 'package:dash/core/satellites.dart';
import 'package:dash/core/trip.dart';
import 'package:dash/core/units.dart';
import 'package:dash/main.dart';
import 'package:dash/platform/dash_platform.dart';
import 'package:dash/screens/settings_screen.dart';
import 'package:dash/screens/trip_detail_screen.dart';
import 'package:dash/screens/trips_screen.dart';
import 'package:dash/settings/settings_store.dart';
import 'package:dash/storage/trip_repository.dart';
import 'package:dash/widgets/speed_gauge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:theme/theme.dart';

import 'test_helpers.dart';

Future<void> settle(WidgetTester tester) async {
  // The app has never-ending animations (GPS pulse), so pumpAndSettle would hang.
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> pumpApp(
  WidgetTester tester, {
  required FakePlatform platform,
  required SettingsStore settings,
  TripRepository? repository,
}) async {
  await tester.pumpWidget(DashApp(
    settings: settings,
    platform: platform,
    repository: repository ?? MemoryTripRepository(),
  ));
  await settle(tester);
}

String speedText(WidgetTester tester) => tester.widget<Text>(find.byKey(const ValueKey('speed-value'))).data!;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows the app bar actions and a searching status before the first fix', (tester) async {
    final platform = FakePlatform();
    await pumpApp(tester, platform: platform, settings: SettingsStore.memory());
    expect(find.text('Dash'), findsOneWidget);
    expect(find.byTooltip('HUD mode'), findsOneWidget);
    expect(find.byTooltip('Trips'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);
    expect(find.text('Searching for GPS'), findsOneWidget);
    expect(speedText(tester), '0');
    expect(platform.screenOn, contains(true));
    await tester.pumpWidget(const SizedBox());
    expect(platform.screenOn.last, isFalse);
    await platform.close();
  });

  testWidgets('shows the satellite count in the GPS card', (tester) async {
    final platform = FakePlatform();
    await pumpApp(tester, platform: platform, settings: SettingsStore.memory());
    expect(find.text('Satellites'), findsOneWidget);
    platform.emitSatellites(const SatelliteCount(inView: 24, used: 11));
    await settle(tester);
    expect(find.text('11 used of 24'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await platform.close();
  });

  testWidgets('g-force card uses the accelerometer when it sends data', (tester) async {
    final platform = FakePlatform();
    await pumpApp(tester, platform: platform, settings: SettingsStore.memory());
    expect(find.text('G-force'), findsOneWidget);
    platform.emitAccel(const AccelSample(timeMs: 0, x: 2, y: 0, z: 0, gx: 0, gy: 0, gz: gravityMs2));
    await settle(tester);
    expect(find.text('Accelerometer'), findsOneWidget);
    // Forward is not learned yet, so only the total is known.
    expect(find.text('Learning direction'), findsNWidgets(2));
    expect(find.textContaining('Keep the phone fixed in its mount'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await platform.close();
  });

  testWidgets('g-force falls back to GPS on a phone without an accelerometer', (tester) async {
    final platform = FakePlatform()..noAccelerometer = true;
    await pumpApp(tester, platform: platform, settings: SettingsStore.memory());
    expect(find.text('GPS (no accelerometer)'), findsOneWidget);
    for (var i = 1; i <= 4; i++) {
      platform.emit(northFix(i, base: DateTime.now().millisecondsSinceEpoch - 5000));
    }
    await settle(tester);
    expect(find.textContaining('comes from GPS speed and heading'), findsOneWidget);
    expect(find.text('Learning direction'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await platform.close();
  });

  testWidgets('asks for location permission and starts after allowing', (tester) async {
    final platform = FakePlatform()..permission = PermissionState.denied;
    await pumpApp(tester, platform: platform, settings: SettingsStore.memory());
    expect(find.text('Allow location'), findsWidgets);
    expect(tester.widget<UiButton>(find.widgetWithText(UiButton, 'Start trip')).onPressed, isNull);

    await tester.tap(find.widgetWithText(UiButton, 'Allow location'));
    await settle(tester);
    expect(platform.permission, PermissionState.granted);
    expect(find.text('Location blocked'), findsNothing);
    platform.emit(northFix(1));
    platform.emit(northFix(2));
    await settle(tester);
    expect(speedText(tester), isNot('0'));
    await tester.pumpWidget(const SizedBox());
    await platform.close();
  });

  testWidgets('shows a blocked permission and a GPS-off warning', (tester) async {
    final blocked = FakePlatform()..permission = PermissionState.blocked;
    await pumpApp(tester, platform: blocked, settings: SettingsStore.memory());
    expect(find.text('Location blocked'), findsOneWidget);
    expect(find.text('Open app settings'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());

    final off = FakePlatform()..gps = false;
    await pumpApp(tester, platform: off, settings: SettingsStore.memory());
    expect(find.text('GPS is off'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('live speed follows the fixes and respects the unit', (tester) async {
    final platform = FakePlatform();
    final settings = SettingsStore.memory();
    await pumpApp(tester, platform: platform, settings: settings);
    for (var i = 0; i < 8; i++) {
      platform.emit(northFix(i, speed: 10));
    }
    await settle(tester);
    expect(find.text('GPS fix'), findsOneWidget);
    expect(int.parse(speedText(tester)), inInclusiveRange(34, 36));
    settings.setUnit(SpeedUnit.mph);
    await settle(tester);
    expect(int.parse(speedText(tester)), inInclusiveRange(21, 22));
    expect(platform.unit, SpeedUnit.mph);
    await tester.pumpWidget(const SizedBox());
    await platform.close();
  });

  testWidgets('the analog gauge replaces the digits when switched on', (tester) async {
    final platform = FakePlatform();
    final settings = SettingsStore.memory()..setAnalog(true);
    await pumpApp(tester, platform: platform, settings: settings);
    expect(find.byKey(const ValueKey('speed-value')), findsNothing);
    expect(find.byType(SpeedGauge), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await platform.close();
  });

  testWidgets('speed limit alert warns once and stays on until clearly below', (tester) async {
    final platform = FakePlatform();
    final settings = SettingsStore.memory()
      ..setLimitEnabled(true)
      ..setLimitMs(SpeedUnit.kmh.toMs(20));
    await pumpApp(tester, platform: platform, settings: settings);
    expect(find.text('Limit 20 km/h'), findsOneWidget);
    for (var i = 0; i < 6; i++) {
      platform.emit(northFix(i, speed: 10)); // 36 km/h
    }
    await settle(tester);
    expect(find.text('Speed limit'), findsOneWidget);
    expect(platform.beeps, 1);
    expect(platform.vibrations, 1);

    settings.setSound(false);
    settings.setVibration(false);
    settings.setLimitEnabled(false);
    await settle(tester);
    expect(find.text('Speed limit'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await platform.close();
  });

  testWidgets('records a trip, saves it on stop and adds to the odometer', (tester) async {
    final platform = FakePlatform();
    final settings = SettingsStore.memory();
    final repo = MemoryTripRepository();
    await pumpApp(tester, platform: platform, settings: settings, repository: repo);

    await tester.tap(find.widgetWithText(UiButton, 'Start trip'));
    await settle(tester);
    expect(platform.active, isTrue);
    expect(find.text('Trip (recording)'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);

    final start = DateTime.now().millisecondsSinceEpoch;
    for (var i = 1; i <= 40; i++) {
      platform.emit(northFix(i, speed: 10, base: start));
    }
    await settle(tester);
    expect(find.textContaining('km'), findsWidgets);

    await tester.tap(find.widgetWithText(UiButton, 'Stop'));
    await settle(tester);
    final saved = await repo.list();
    expect(saved.length, 1);
    expect(saved.single.distanceM, closeTo(390, 5));
    expect(settings.odometerM, closeTo(390, 5));
    expect(platform.active, isFalse);
    expect(find.text('Start trip'), findsOneWidget);
    expect(find.textContaining('Trip saved'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await platform.close();
  });

  testWidgets('pausing stops recording; resuming continues', (tester) async {
    final platform = FakePlatform();
    await pumpApp(tester, platform: platform, settings: SettingsStore.memory());
    await tester.tap(find.widgetWithText(UiButton, 'Start trip'));
    await settle(tester);
    await tester.tap(find.widgetWithText(UiButton, 'Pause'));
    await settle(tester);
    expect(platform.paused, isTrue);
    expect(find.text('Trip (paused)'), findsOneWidget);
    await tester.tap(find.widgetWithText(UiButton, 'Resume'));
    await settle(tester);
    expect(platform.paused, isFalse);
    expect(find.text('Trip (recording)'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await platform.close();
  });

  testWidgets('a trip that is too short is discarded', (tester) async {
    final platform = FakePlatform();
    final repo = MemoryTripRepository();
    await pumpApp(tester, platform: platform, settings: SettingsStore.memory(), repository: repo);
    await tester.tap(find.widgetWithText(UiButton, 'Start trip'));
    await settle(tester);
    await tester.tap(find.widgetWithText(UiButton, 'Stop'));
    await settle(tester);
    expect(await repo.list(), isEmpty);
    expect(find.text('Trip was too short to save.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await platform.close();
  });

  testWidgets('a trip recorded while the app was closed is picked up on launch', (tester) async {
    final platform = FakePlatform()..active = true;
    final lines = StringBuffer('{"e":"start","t":$baseMs}\n');
    for (var i = 1; i <= 30; i++) {
      final f = northFix(i, speed: 10);
      lines.writeln('{"t":${f.timeMs},"la":${f.lat},"lo":${f.lon},"sp":10.0,"ac":5.0}');
    }
    platform.log = lines.toString();
    await pumpApp(tester, platform: platform, settings: SettingsStore.memory());
    expect(find.text('Trip (recording)'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
    expect(find.text('0.29 km'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await platform.close();
  });

  testWidgets('HUD mode mirrors the digits, raises brightness and exits', (tester) async {
    final platform = FakePlatform();
    final settings = SettingsStore.memory();
    await pumpApp(tester, platform: platform, settings: settings);
    platform.emit(northFix(0, speed: 10));
    platform.emit(northFix(1, speed: 10));
    await settle(tester);

    await tester.tap(find.byTooltip('HUD mode'));
    await settle(tester);
    expect(find.byKey(const ValueKey('hud-speed')), findsOneWidget);
    expect(platform.brightness, [true]);

    bool flipped() => find
        .ancestor(of: find.byKey(const ValueKey('hud-speed')), matching: find.byType(Transform))
        .evaluate()
        .any((e) => (e.widget as Transform).transform.storage[0] == -1.0);
    expect(flipped(), isTrue);

    await tester.tap(find.byIcon(Icons.flip_rounded));
    await settle(tester);
    expect(settings.hudMirror, isFalse);
    expect(flipped(), isFalse);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('hud-speed')), findsNothing);
    expect(platform.brightness, [true, false]);
    await tester.pumpWidget(const SizedBox());
    await platform.close();
  });

  testWidgets('settings screen has appearance, update and developer sections in order', (tester) async {
    final settings = SettingsStore.memory()..setLimitEnabled(true);
    await tester.pumpWidget(UiApp(home: SettingsScreen(settings: settings)));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Speed limit alert'), findsOneWidget);
    expect(find.text('Beep'), findsOneWidget);
    expect(find.byType(UiAppearanceSection), findsOneWidget);
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -3000));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(UiUpdateSection), findsOneWidget);
    expect(find.byType(UiDeveloperSection), findsOneWidget);
    final update = tester.getTopLeft(find.byType(UiUpdateSection)).dy;
    final dev = tester.getTopLeft(find.byType(UiDeveloperSection)).dy;
    expect(update, lessThan(dev));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('trips list, detail with export, and delete', (tester) async {
    final repo = MemoryTripRepository();
    await repo.save(sampleTrip());
    final settings = SettingsStore.memory()..addOdometer(2500);
    final shared = <Trip>[];
    final opened = <Uri>[];
    final texts = <String>[];

    await tester.pumpWidget(UiApp(home: TripsScreen(repository: repo, settings: settings)));
    await settle(tester);
    expect(find.text('2.50 km'), findsOneWidget); // odometer
    expect(find.textContaining('avg'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_right_rounded).first);
    await settle(tester);
    expect(find.byType(TripDetailScreen), findsOneWidget);
    expect(find.text('Speed over time (km/h)'), findsOneWidget);

    // Fresh app, so the detail route pushed above does not stay on top.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(UiApp(
      home: TripDetailScreen(
        tripId: sampleTrip().id,
        repository: repo,
        settings: settings,
        share: (t) async => shared.add(t),
        openUrl: (u) async {
          opened.add(u);
          return true;
        },
        shareText: (s) async => texts.add(s),
      ),
    ));
    await settle(tester);

    final maps = find.widgetWithText(UiButton, 'Open in Google Maps').first;
    await tester.ensureVisible(maps);
    await settle(tester);
    await tester.tap(maps);
    await settle(tester);
    expect(opened.single.host, 'www.google.com');
    expect(opened.single.queryParameters['origin'], '12.000000,77.000000');

    final shareLink = find.widgetWithText(UiButton, 'Share Maps link').first;
    await tester.ensureVisible(shareLink);
    await settle(tester);
    await tester.tap(shareLink);
    await settle(tester);
    expect(texts.single, contains('https://www.google.com/maps/dir/'));

    final export = find.widgetWithText(UiButton, 'Export GPX').first;
    await tester.ensureVisible(export);
    await settle(tester);
    await tester.tap(export);
    await settle(tester);
    expect(shared.single.points.length, 12);

    final delete = find.widgetWithText(UiButton, 'Delete trip').first;
    await tester.ensureVisible(delete);
    await settle(tester);
    await tester.tap(delete);
    await settle(tester);
    await tester.tap(find.text('Delete'));
    await settle(tester);
    expect(await repo.list(), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('empty trips screen explains itself', (tester) async {
    await tester.pumpWidget(UiApp(home: TripsScreen(repository: MemoryTripRepository(), settings: SettingsStore.memory())));
    await settle(tester);
    expect(find.text('No trips yet'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
