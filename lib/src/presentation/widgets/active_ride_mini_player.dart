import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../state/transit_view_model.dart';
import 'live_ride_sheet.dart';

/// A compact banner that stays pinned above the navigation bar when a trip
/// is being tracked, even as the user scrolls or switches tabs.
class ActiveRideMiniPlayer extends StatelessWidget {
  final TransitViewModel viewModel;

  const ActiveRideMiniPlayer({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final trip = viewModel.activeTrackedTrip!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => LiveRideSheet.show(context, viewModel),
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primaryCyan, AppColors.secondaryIndigo],
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryCyan.withAlpha(100),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(30),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.gps_fixed_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'ON-BOARD TRACKING ACTIVE',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          'To ${trip.destinationName}'
                          '${viewModel.currentStopStation?.name != null ? ' • ${viewModel.currentStopStation!.name}' : ''}'
                          '${viewModel.nextStopStation != null ? ' → ${viewModel.nextStopStation!.name}' : ''}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Colors.white),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
