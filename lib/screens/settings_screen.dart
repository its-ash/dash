import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../settings/settings_store.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.settings});

  final SettingsStore settings;

  @override
  Widget build(BuildContext context) {
    return UiScaffold(
      appBar: const UiAppBar(title: 'Settings', back: true),
      scrollable: true,
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          final unit = settings.unit;
          final maxLimit = unit.gaugeMax.toDouble();
          final limitInUnit = unit.fromMs(settings.limitMs).clamp(10.0, maxLimit);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              UiListGroup(
                header: 'Display',
                children: [
                  UiSwitchTile(
                    'Analog gauge',
                    subtitle: 'Show a dial with a needle instead of big digits',
                    icon: Icons.speed_rounded,
                    value: settings.analog,
                    onChanged: settings.setAnalog,
                  ),
                  UiSwitchTile(
                    'Mirror HUD',
                    subtitle: 'Flip the HUD digits so they read right in the windshield',
                    icon: Icons.flip_rounded,
                    value: settings.hudMirror,
                    onChanged: settings.setHudMirror,
                  ),
                ],
              ),
              const UiGap(UiSpace.lg),
              UiListGroup(
                header: 'Trips',
                footer: 'A trip starts after about 20 seconds above 15 km/h while Dash is open, and ends after '
                    '5 minutes without moving, also with the screen off. Android does not let Dash start a trip '
                    'while it is closed; use the home-screen widget for that.',
                children: [
                  UiSwitchTile(
                    'Automatic trips',
                    subtitle: 'Start and stop recording by itself',
                    icon: Icons.auto_mode_rounded,
                    value: settings.autoTrips,
                    onChanged: settings.setAutoTrips,
                  ),
                ],
              ),
              const UiGap(UiSpace.lg),
              UiListGroup(
                header: 'Speed limit alert',
                footer: 'The warning turns off again a little below the limit, so it does not flicker.',
                children: [
                  UiSwitchTile(
                    'Warn when over the limit',
                    icon: Icons.warning_amber_rounded,
                    status: UiStatus.warning,
                    value: settings.limitEnabled,
                    onChanged: settings.setLimitEnabled,
                  ),
                ],
              ),
              if (settings.limitEnabled) ...[
                const UiGap(UiSpace.md),
                UiSlider(
                  value: limitInUnit,
                  min: 10,
                  max: maxLimit,
                  divisions: ((maxLimit - 10) / 5).round(),
                  label: 'Limit (${unit.label})',
                  format: (v) => v.round().toString(),
                  onChanged: (v) => settings.setLimitMs(unit.toMs(v)),
                ),
                const UiGap(UiSpace.md),
                UiListGroup(
                  children: [
                    UiSwitchTile(
                      'Beep',
                      icon: Icons.volume_up_rounded,
                      value: settings.sound,
                      onChanged: settings.setSound,
                    ),
                    UiSwitchTile(
                      'Vibration',
                      icon: Icons.vibration_rounded,
                      value: settings.vibration,
                      onChanged: settings.setVibration,
                    ),
                  ],
                ),
              ],
              const UiGap(UiSpace.lg),
              const UiListGroup(
                header: 'Privacy',
                children: [
                  UiListTile(
                    'Everything stays on this phone',
                    subtitle: 'Dash reads GPS and the motion sensors. Trips are saved on this phone and leave it only '
                        'when you export a GPX file or open or share a Google Maps link. It uses the internet only '
                        'to check for app updates.',
                    icon: Icons.lock_rounded,
                    iconStatus: UiStatus.success,
                    maxSubtitleLines: 6,
                  ),
                ],
              ),
              const UiGap(UiSpace.lg),
              const UiAppearanceSection(),
              const UiGap(UiSpace.lg),
              const UiUpdateSection(storeId: 'dash'),
              const UiGap(UiSpace.lg),
              const UiDeveloperSection(),
            ],
          );
        },
      ),
    );
  }
}
