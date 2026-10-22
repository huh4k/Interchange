import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../state/transit_view_model.dart';
import 'common/ui_kit.dart';
import 'live_ride_sheet.dart';

/// A compact banner that stays pinned above the navigation bar when a trip
/// is being tracked, even as the user scrolls or switches tabs.
class ActiveRideMiniPlayer extends StatelessWidget {
  const ActiveRideMiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    // Subscribe only to the few values shown here so GPS fixes that don't move
    // the stop (and unrelated view-model changes) don't rebuild the banner.
    final (isActive, destination, currentName, nextName, between) = context
        .select<TransitViewModel, (bool, String?, String?, String?, bool)>(
          (vm) => (
            vm.isTrackingActive && vm.activeTrackedTrip != null,
            vm.activeTrackedTrip?.destinationName,
            vm.currentStopStation?.name,
            vm.nextStopStation?.name,
            vm.isBetweenStops,
          ),
        );
    if (!isActive) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(60),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: SurfacePanel(
          accent: AppColors.statusGreen,
          borderColor: AppColors.statusGreen.withAlpha(90),
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          onTap: () =>
              LiveRideSheet.show(context, context.read<TransitViewModel>()),
          child: Row(
            children: [
              const IconTile(
                icon: Icons.gps_fixed_rounded,
                color: AppColors.statusGreen,
                size: 34,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SectionLabel(
                      'LIVE ON-BOARD',
                      color: AppColors.statusGreen,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      between && nextName != null
                          ? 'To $destination • Between $currentName and $nextName'
                          : 'To $destination'
                                '${currentName != null ? ' • $currentName' : ''}'
                                '${nextName != null ? ' → $nextName' : ''}',
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
