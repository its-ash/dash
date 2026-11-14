# Dash

Offline GPS speedometer with a windshield HUD, speed limit alert and trip log.

**[Website](https://dash.itsash.in)** · **[Download APK](https://github.com/its-ash/dash/releases/latest/download/dash.apk)** · Get it in **[Ash Store](https://store.itsash.in)**

## Features

- **Big speed**: large digits or an analog gauge, in km/h, mph or knots. The screen stays on while Dash is open.
- **HUD mode**: full-screen mirrored digits on black, landscape and full brightness, so the speed reflects in the windshield.
- **Speed limit alert**: set a limit and get a warning colour, a beep and a vibration. It has hysteresis, so it does not flicker around the limit.
- **Trips**: start, pause and stop. Recording continues with the screen off through a foreground service, with a live speed notification.
- **Automatic trips**: with Dash open, a trip starts after about 20 seconds above 15 km/h, and ends after 5 minutes without moving (also with the screen off).
- **Home-screen widget**: odometer, last trip, and a Start / Stop trip button.
- **G-force meter**: live acceleration, braking and cornering from the accelerometer. Dash learns which way the phone faces from GPS; without an accelerometer it falls back to GPS.
- **Trip history**: each trip has its route (a plain polyline, no map tiles) colored by speed, with hard braking, hard acceleration and sharp cornering marked on it, plus speed and altitude charts with total climb and descent.
- **Google Maps**: open any trip in Google Maps, or share a Maps link to it. No API key: it is a plain Maps link with the start, the end and up to 8 stops.
- **GPS details**: altitude, heading, accuracy and the number of satellites in use and in view.
- **Odometer and GPX**: a total across all trips, and export of any trip as GPX through the share sheet.
- **Clean data**: bad fixes are rejected, speed is smoothed, distance uses the haversine formula, and speed under 1.5 km/h counts as standing still.
- **Private**: no accounts, no ads, no map tiles. The only network call is the update check in Settings; Google Maps opens only when you tap it.

## Install

- **Ash Store**: install [Ash Store](https://store.itsash.in) once, then install and update Dash from it.
- **APK**: download the [latest APK](https://github.com/its-ash/dash/releases/latest/download/dash.apk) on your phone and open it. Allow your browser to install unknown apps if Android asks.

Requires Android 8.0 (API 26) and a phone with GPS.

## Develop

Needs Flutter ≥ 3.44 and the shared theme package at `../theme`.

```bash
make run      # run on a connected device
make build    # release APK
make test     # flutter analyze + flutter test
make deploy   # bump version, build, tag, push, GitHub release (see store.mk)
```

## Release

`make deploy` follows the Ash Store kit (`store.mk`, `store.json`): it bumps the
version in `pubspec.yaml`, builds, commits, tags `vX.Y.Z`, pushes, and publishes
a GitHub release with `dash.apk`. Ash Store and the website pick up the new
version from that release.

## Project layout

```
lib/
├── main.dart                     # UiApp, lifecycle, wiring
├── core/                         # pure, tested logic
│   ├── units.dart                # km/h, mph, knots, formatting
│   ├── geo.dart                  # haversine, bearing, route projection
│   ├── gps_fix.dart              # GpsFix, GPS status
│   ├── fix_filter.dart           # bad fix rejection, smoothing, stationary
│   ├── trip_recorder.dart        # trip stats, pause, track log replay
│   ├── trip.dart                 # Trip, TrackPoint
│   ├── overspeed.dart            # limit alert with hysteresis
│   ├── gpx.dart                  # GPX writer
│   ├── gforce.dart               # g-force (sensor + GPS), peaks, harsh events
│   ├── maps_link.dart            # Google Maps directions link for a trip
│   ├── satellites.dart           # satellite counts
│   └── chart_data.dart           # speed and altitude series, climb/descent
├── platform/                     # Android channels, GPX share
├── state/dash_controller.dart    # live state, trip control
├── storage/trip_repository.dart  # trips as JSON files
├── settings/settings_store.dart
├── widgets/                      # digits, gauge, route
└── screens/                      # home, HUD, trips, trip detail, settings
android/app/src/main/kotlin/com/itsash/dash/
├── MainActivity.kt               # channels, GPS/GNSS/accelerometer streams, vibrate, beep
├── TrackingService.kt            # foreground location service, auto-stop
├── TripControl.kt                # start / end a trip (app, service, widget)
├── DashWidget.kt                 # home-screen widget
└── TrackLog.kt                   # active and pending trip logs, prefs
```

## License

No license file is included yet.

Built by [itsash.in](https://itsash.in).
