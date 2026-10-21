import 'package:flutter/material.dart';
import '../../domain/value_objects/transit_type.dart';
import '../../theme/app_theme.dart';

class ModeFilterBar extends StatelessWidget {
  final TransitType? selectedTypeFilter;
  final ValueChanged<TransitType?> onModeSelected;

  const ModeFilterBar({
    super.key,
    required this.selectedTypeFilter,
    required this.onModeSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildModeChip(
            context,
            label: 'All Modes',
            icon: Icons.apps_rounded,
            isSelected: selectedTypeFilter == null,
            color: AppColors.primaryCyan,
            onTap: () => onModeSelected(null),
          ),
          const SizedBox(width: 10),
          ...TransitType.values
              .where((type) => type != TransitType.ferry)
              .map((type) {
            final isSelected = selectedTypeFilter == type;
            final brandColor = type.ptvBrandColor;

            return Padding(
              padding: const EdgeInsets.only(right: 10.0),
              child: _buildModeChip(
                context,
                label: type.displayName,
                icon: type.icon,
                isSelected: isSelected,
                color: brandColor,
                onTap: () => onModeSelected(isSelected ? null : type),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildModeChip(
    BuildContext context, {
    required String label,
    required IconData icon,
    required bool isSelected,
    required Color color,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? color.withAlpha(40)
                : (theme.brightness == Brightness.dark
                    ? const Color(0xFF1F2B47)
                    : const Color(0xFFEDF2F9)),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isSelected
                  ? color.withAlpha(120)
                  : (theme.brightness == Brightness.dark
                      ? const Color(0xFF2A3A56)
                      : const Color(0xFFD0DDE8)),
              width: isSelected ? 1.5 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: color.withAlpha(60),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected ? color : Colors.grey,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: isSelected ? color : Colors.grey,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

