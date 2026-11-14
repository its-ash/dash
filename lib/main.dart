import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:theme/theme.dart';

import 'platform/dash_platform.dart';
import 'screens/home_screen.dart';
import 'settings/settings_store.dart';
import 'state/dash_controller.dart';
import 'storage/trip_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await SettingsStore.load();
  final docs = await getApplicationDocumentsDirectory();
  runApp(DashApp(
    settings: settings,
    platform: const DashPlatformChannel(),
    repository: FileTripRepository(Directory('${docs.path}/trips')),
  ));
}

class DashApp extends StatefulWidget {
  const DashApp({super.key, required this.settings, required this.platform, required this.repository});

  final SettingsStore settings;
  final DashPlatform platform;
  final TripRepository repository;

  @override
  State<DashApp> createState() => _DashAppState();
}

class _DashAppState extends State<DashApp> with WidgetsBindingObserver {
  late final DashController _controller = DashController(
    platform: widget.platform,
    settings: widget.settings,
    repository: widget.repository,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The GPS feed and screen-on flag are released in the background; a
    // running trip keeps recording in the Android foreground service and is
    // read back from its log when the app returns.
    if (state == AppLifecycleState.paused) {
      _controller.pause();
    } else if (state == AppLifecycleState.resumed) {
      _controller.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    return UiApp(
      title: 'Dash',
      home: HomeScreen(controller: _controller, settings: widget.settings, repository: widget.repository),
    );
  }
}
