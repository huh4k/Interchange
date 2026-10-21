import 'package:flutter/material.dart';
import '../../domain/value_objects/ptv_mode.dart';
import '../../theme/app_theme.dart';

/// A capsule-shaped sliding toggle that switches between Metro Train, Yarra Tram and V/Line modes.
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
    ],
  });

  @override
  Widget build(BuildContext context) {
    final activeIndex = modes.indexOf(activeMode).clamp(0, modes.length - 1);

    // Compute alignment: -1.0 = far left, +1.0 = far right
    final double xAlign = modes.length > 1
        ? -1.0 + (activeIndex / (modes.length - 1)) * 2.0
        : 0.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(100),
            gradient: const LinearGradient(
              colors: [
                AppColors.melbourneMetro,
                AppColors.melbourneTram,
                AppColors.melbourneVLine,
              ],
            ),
          ),
          padding: const EdgeInsets.all(4),
          child: Stack(
            children: [
              // Sliding white thumb
              AnimatedAlign(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOutCubic,
                alignment: Alignment(xAlign, 0),
                child: FractionallySizedBox(
                  widthFactor: 1 / modes.length,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(100),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 6,
                          offset: Offset(0, 2),
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
                  final brandColor = mode.transitType.ptvBrandColor;

                  return Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: isActive ? null : () => onModeChanged(mode),
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              mode.transitType.icon,
                              size: 16,
                              color: isActive ? brandColor : Colors.white,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _label(mode),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: isActive
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                                color: isActive ? brandColor : Colors.white,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
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
