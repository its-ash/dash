import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../core/units.dart';

/// The big digital speed readout. Turns the danger colour when over the limit.
class DigitalSpeed extends StatelessWidget {
  const DigitalSpeed({super.key, required this.speedMs, required this.unit, this.over = false});

  final double speedMs;
  final SpeedUnit unit;
  final bool over;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = over ? c.danger : c.text;
    return Semantics(
      label: 'Speed ${formatSpeed(speedMs, unit)} ${unit.label}',
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                formatSpeed(speedMs, unit),
                key: const ValueKey('speed-value'),
                style: context.text.displayLarge?.copyWith(
                  fontSize: 148,
                  height: 1.0,
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Text(unit.label, style: context.text.titleMedium?.copyWith(color: c.textMuted)),
          ],
        ),
      ),
    );
  }
}
