import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:theme/theme.dart';

import '../core/units.dart';
import '../settings/settings_store.dart';
import '../state/dash_controller.dart';

/// Windshield HUD: huge mirrored digits on pure black, landscape, full
/// brightness. Put the phone flat on the dashboard and the speed reflects in
/// the glass the right way round.
///
/// This is the one screen that does not follow the app theme: it needs pure
/// black and a bright readout to reflect well.
class HudScreen extends StatefulWidget {
  const HudScreen({super.key, required this.controller, required this.settings});

  final DashController controller;
  final SettingsStore settings;

  @override
  State<HudScreen> createState() => _HudScreenState();
}

class _HudScreenState extends State<HudScreen> {
  static const _black = Color(0xFF000000);
  static const _readout = Color(0xFF39FF88);
  static const _warning = Color(0xFFFF4D4D);
  static const _hint = Color(0x99FFFFFF);

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    widget.controller.platform.setMaxBrightness(true);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(const []);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    widget.controller.platform.setMaxBrightness(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _black,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([widget.controller, widget.settings]),
          builder: (context, _) {
            final unit = widget.settings.unit;
            final over = widget.controller.overspeed;
            final mirror = widget.settings.hudMirror;
            final color = over ? _warning : _readout;
            return Stack(
              children: [
                Positioned.fill(
                  child: Transform.flip(
                    flipX: mirror,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.contain,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 24),
                                child: Text(
                                  formatSpeed(widget.controller.speedMs, unit),
                                  key: const ValueKey('hud-speed'),
                                  style: context.text.displayLarge?.copyWith(
                                    fontSize: 400,
                                    height: 1.0,
                                    fontWeight: FontWeight.w700,
                                    color: color,
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Text(
                            unit.label,
                            style: context.text.headlineMedium?.copyWith(color: color),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 4,
                  top: 4,
                  child: _HudButton(
                    icon: Icons.close_rounded,
                    tooltip: 'Exit HUD',
                    color: _hint,
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                ),
                Positioned(
                  right: 4,
                  top: 4,
                  child: _HudButton(
                    icon: Icons.flip_rounded,
                    tooltip: mirror ? 'Mirror is on' : 'Mirror is off',
                    color: mirror ? _readout : _hint,
                    onTap: () => widget.settings.setHudMirror(!mirror),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HudButton extends StatelessWidget {
  const _HudButton({required this.icon, required this.tooltip, required this.color, required this.onTap});

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(icon, color: color, size: 32),
        ),
      ),
    );
  }
}
