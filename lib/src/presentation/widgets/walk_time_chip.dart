import 'package:flutter/material.dart';
import '../../services/location_service.dart';
import '../state/transit_view_model.dart';

/// Opt-in pill showing the walk from the user to the selected station.
/// Tapping it turns walking time on (asking for location) or off.
class WalkTimeChip extends StatelessWidget {
  final TransitViewModel viewModel;

  const WalkTimeChip({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = viewModel.walkTimeEnabled;
    final walk = viewModel.walkToSelectedStation;
    final meters = viewModel.walkDistanceMeters;

    final String label;
    if (!enabled) {
      label = 'Show walking time';
    } else if (walk != null && meters != null) {
      label = walk.inMinutes < 1
          ? "You're here"
          : '${walk.inMinutes} min walk · ${LocationService.formatDistance(meters)}';
    } else if (viewModel.userPosition != null) {
      label = 'Too far to walk';
    } else {
      label = 'Waiting for location…';
    }

    final active = enabled && walk != null;
    final foreground = active
        ? Colors.white
        : theme.textTheme.bodyMedium?.color;

    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        button: true,
        label: enabled ? '$label. Tap to turn off walking time' : label,
        child: GestureDetector(
          onTap: viewModel.toggleWalkTime,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: active ? Theme.of(context).colorScheme.primary : theme.cardColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: active
                    ? Theme.of(context).colorScheme.primary
                    : theme.dividerColor.withAlpha(50),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.directions_walk_rounded, size: 14, color: foreground),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: active ? FontWeight.bold : FontWeight.w500,
                    color: foreground,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
