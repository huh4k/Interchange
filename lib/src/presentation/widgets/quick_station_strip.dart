import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../state/transit_view_model.dart';

/// Horizontal scrollable row of pill chips for favorite + recent stations,
/// allowing 1-tap switching without opening the full station picker.
class QuickStationStrip extends StatelessWidget {
  final TransitViewModel viewModel;

  const QuickStationStrip({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final favorites = viewModel.favoriteStations;
    final recents = viewModel.recentStations;

    // Show only stations relevant to the active mode; combine favorites first then recents.
    final combined = [
      ...favorites,
      ...recents.where((r) => !favorites.any((f) => f.id == r.id || f.name == r.name)),
    ];

    if (combined.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: combined.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final station = combined[index];
          final isActive = station.name == viewModel.selectedStation.name;
          final isFav = viewModel.isFavoriteStation(station);

          return Semantics(
            label: '${isActive ? 'Currently selected: ' : ''}${station.name}',
            button: true,
            child: GestureDetector(
              onTap: () {
                viewModel.selectStation(station);
                if (viewModel.selectedNavIndex != 0) {
                  viewModel.selectNavIndex(0);
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isActive
                      ? AppColors.primaryCyan
                      : Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isActive
                        ? AppColors.primaryCyan
                        : Theme.of(context).dividerColor.withAlpha(50),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isFav) ...[
                      Icon(
                        Icons.star_rounded,
                        size: 11,
                        color: isActive ? Colors.white : AppColors.statusAmber,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      // Strip " Station" suffix for compactness
                      station.name.replaceAll(RegExp(r'\s+[Ss]tation$'), ''),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                        color: isActive
                            ? Colors.white
                            : Theme.of(context).textTheme.bodyMedium?.color,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
