import 'package:flutter/material.dart';
import '../../domain/value_objects/ptv_mode.dart';
import 'common/ui_kit.dart';

/// A capsule-shaped sliding toggle that switches between Metro Train, Yarra Tram, V/Line and Bus modes.
///
/// Designed to be extensible: [modes] accepts any ordered list of [PtvMode] values,
/// so further modes can be added later by simply appending to the list.
class TransitModeSlider extends StatelessWidget {
  final PtvMode activeMode;
  final ValueChanged<PtvMode> onModeChanged;

  /// The modes to display as segments. Defaults to Trains + Trams + V/Line.
  final List<PtvMode> modes;

  const TransitModeSlider({
    super.key,
    required this.activeMode,
    required this.onModeChanged,
    this.modes = const [
      PtvMode.metroTrain,
      PtvMode.metroTram,
      PtvMode.regionalTrain,
      PtvMode.metroBus,
    ],
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final activeIndex = modes.indexOf(activeMode).clamp(0, modes.length - 1);
    final activeColor = modes[activeIndex].transitType.ptvBrandColor;
    final hsl = HSLColor.fromColor(activeColor);
    final lighter = hsl
        .withLightness((hsl.lightness + 0.08).clamp(0.0, 1.0))
        .toColor();
    final darker = hsl
        .withLightness((hsl.lightness - 0.10).clamp(0.0, 1.0))
        .toColor();

    // Compute alignment: -1.0 = far left, +1.0 = far right
    final double xAlign = modes.length > 1
        ? -1.0 + (activeIndex / (modes.length - 1)) * 2.0
        : 0.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Each segment needs icon + gap + its widest label + some air. When the
        // labels don't fit, the icons alone carry the switcher.
        final segment = (constraints.maxWidth - 10) / modes.length;
        var widest = 0.0;
        for (final m in modes) {
          final w = measureTextWidth(
            context,
            _label(m),
            const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          );
          if (w > widest) widest = w;
        }
        final iconsOnly = segment < 16 + 6 + widest + 16;

        return Container(
          height: 48,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: scheme.outlineVariant),
          ),
          padding: const EdgeInsets.all(4),
          child: Stack(
            children: [
              // Sliding thumb in the active mode's brand colour
              AnimatedAlign(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOutCubic,
                alignment: Alignment(xAlign, 0),
                child: FractionallySizedBox(
                  widthFactor: 1 / modes.length,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [lighter, darker],
                      ),
                      borderRadius: BorderRadius.circular(100),
                      boxShadow: [
                        BoxShadow(
                          color: activeColor.withAlpha(80),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Tap zones (one per mode)
              Row(
                children: List.generate(modes.length, (i) {
                  final mode = modes[i];
                  final isActive = mode == activeMode;
                  final foreground = isActive
                      ? Colors.white
                      : scheme.onSurfaceVariant;

                  return Expanded(
                    child: Semantics(
                      button: true,
                      selected: isActive,
                      label: _label(mode),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: isActive ? null : () => onModeChanged(mode),
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                mode.transitType.icon,
                                size: iconsOnly ? 22 : 16,
                                color: isActive
                                    ? Colors.white
                                    : mode.transitType.ptvBrandColor,
                              ),
                              if (!iconsOnly) ...[
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    _label(mode),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: isActive
                                          ? FontWeight.w700
                                          : FontWeight.w600,
                                      color: foreground,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _label(PtvMode mode) {
    switch (mode) {
      case PtvMode.metroTrain:
        return 'Trains';
      case PtvMode.metroTram:
        return 'Trams';
      case PtvMode.metroBus:
      case PtvMode.regionalBus:
        return 'Buses';
      case PtvMode.regionalTrain:
        return 'V/Line';
      case PtvMode.regionalCoach:
        return 'Coach';
    }
  }
}
