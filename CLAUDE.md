# Dash (package: dash / com.itsash.dash)

Offline GPS speedometer for car, bike, cycling and walking. Big digits or analog
gauge (km/h, mph, knots), mirrored HUD mode for windshield reflection, speed
limit alert, trip recording that survives screen off (Kotlin foreground
service), automatic trips (auto-start while open, auto-stop in the service),
home-screen widget, g-force meter (accelerometer, GPS fallback) with peaks and
harsh-event markers, satellite count, trip history with speed-colored route,
speed and altitude charts, Google Maps link, odometer, GPX export. No map tiles,
no network except the update check.

## Code layout

- `lib/core/`: pure Dart, unit tested (`test/core_test.dart`). Add a test for every change.
  - `units.dart` (`SpeedUnit`, formatters), `geo.dart` (haversine, bearing,
    `projectRoute`), `gps_fix.dart` (`GpsFix`, `gpsStatusFor`).
  - `fix_filter.dart`: rejects accuracy > 30 m, non-increasing time, jumps over
    100 m/s (trusted after 5 in a row); smooths speed (tau 1.5 s); below
    1.5 km/h = stationary (speed 0, no distance).
  - `trip_recorder.dart`: `TripRecorder` (distance, moving time, max/avg, pause,
    point thinning) and the track log parser (`parseTrackLog`).
  - `overspeed.dart`: on above limit, off below limit - max(2 km/h, 3%); repeat alert every 5 s.
  - `trip.dart`, `gpx.dart`, `chart_data.dart` (speed/altitude resampling, climb/descent with 5 m hysteresis).
  - `gforce.dart`: `SensorGMeter` (gravity removed, forward learned from GPS
    speed change, reset when the phone turns > 20° in its mount), `GpsGMeter`
    (Doppler speed change + speed × turn rate), `GPeaks`, `HarshDetector`
    (brake 0.35 g, accel 0.30 g, cornering 0.40 g; same kind within 5 s merges).
  - `maps_link.dart` (Google Maps URL, no key), `satellites.dart`.
- `lib/platform/dash_platform.dart`: `DashPlatform` interface (faked in tests)
  and `DashPlatformChannel` over `com.itsash.dash/device` (methods) and
  `com.itsash.dash/fixes` (GPS events). Permissions via `permission_handler`.
  `gpx_share.dart` writes the GPX to cache and opens `share_plus`.
- `lib/state/dash_controller.dart`: live speed, fix status, overspeed, trip state.
- `lib/storage/trip_repository.dart`: `index.json` (summaries) + `trip_<id>.json` (points) in app documents.
- `lib/settings/settings_store.dart`: unit, gauge mode, limit, alerts, HUD mirror, odometer (`shared_preferences`).
- `lib/screens/`: `home_screen`, `hud_screen` (the only screen with hardcoded
  colors: pure black + bright readout), `trips_screen`, `trip_detail_screen`,
  `settings_screen` (ends with `UiAppearanceSection`, `UiUpdateSection(storeId: 'dash')`, `UiDeveloperSection`).
- `lib/widgets/`: `digital_speed`, `speed_gauge` (CustomPainter), `route_view` (CustomPainter).
- `android/app/src/main/kotlin/com/itsash/dash/`: `MainActivity` (channels, GPS
  stream via `LocationManager.GPS_PROVIDER`, keep screen on, max brightness,
  vibrate, beep, GNSS and accelerometer streams, widget start intent),
  `TrackingService` (foreground service type `location`, notification with live
  speed, appends fixes to the track log, auto-stop after `autoStopMs` without
  moving), `TripControl` (start / end in background), `DashWidget` (home-screen
  widget; Start opens the app, Stop ends in background), `TrackLog` (JSON-lines
  file, `pending/`, prefs).

## How a trip works

The service only logs raw fixes and start/pause/resume markers to
`files/active_track.jsonl`. Dart replays that log through `TripRecorder`, so all
trip maths is in Dart. While the app is visible it also feeds live fixes to the
same recorder (duplicates are ignored by timestamp). On launch or resume an
active trip is rebuilt from the log. Stop saves the trip if it is at least 30 m.

A trip that ends without the app (auto-stop or the widget's Stop) gets a
`{"e":"stop","t":ms}` marker and its log moves to `files/pending/`. Dart saves
pending trips on start and every few seconds while open (`_syncWithService`).
Auto-start happens only in Dart while the app is open: Android does not let a
closed app start location tracking without background location permission.

## Commands

- `make run`, `make build` (release APK), `make test` (`flutter analyze` + `flutter test`), `make clean`.
- Icon: SVG sources in `assets/icon/` (pixel speedometer gauge with needle) -> `rsvg-convert -w 1024 -h 1024` to `*-1024.png`, then `dart run flutter_launcher_icons`.

## Conventions

- minSdk 26. UI only from the shared `theme` package (`../theme`, read `../theme/COMPONENTS.md`). Starts in light mode.
- Permissions: `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION`, `POST_NOTIFICATIONS`, `VIBRATE`, `INTERNET` (update check only). No background location permission (the foreground service is started while the app is visible).

## Release (Ash Store)

- `store.json` (id `dash`, repo its-ash/dash), `store.mk`, `index.html` + `CNAME` (`dash.itsash.in`). See `../ash-store/store-kit/STORE.md`.
- `make deploy` = bump version -> build -> commit, tag `vX.Y.Z`, push -> GitHub release with `dash.apk` -> topics, homepage, Pages. Never create releases, tags or asset names by hand.
- Do not edit `store.mk` here. Edit `../ash-store/store-kit/store.mk`, then run `make store-sync` at the workspace root.
