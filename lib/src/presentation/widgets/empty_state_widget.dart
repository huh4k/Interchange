import 'package:flutter/material.dart';

class EmptyStateWidget extends StatelessWidget {
  final bool isSavedView;
  final VoidCallback onReset;

  /// Active departure filter, if any. Named in the message so users know why
  /// nothing is showing.
  final String filterText;

  /// True when the last load failed, in which case an empty list means "could
  /// not load" rather than "nothing matches".
  final bool hasError;

  const EmptyStateWidget({
    super.key,
    required this.isSavedView,
    required this.onReset,
    this.filterText = '',
    this.hasError = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.color?.withAlpha(200);
    final filter = filterText.trim();

    final IconData icon;
    final String title;
    final String? subtitle;
    final String action;
    final IconData actionIcon;

    if (isSavedView) {
      icon = Icons.star_border_rounded;
      title = filter.isEmpty
          ? 'No saved departures yet'
          : 'No saved departures match “$filter”';
      subtitle = filter.isEmpty
          ? 'Tap the star on a departure to keep it here.'
          : null;
      action = 'View departures';
      actionIcon = Icons.directions_transit_rounded;
    } else if (hasError) {
      icon = Icons.cloud_off_rounded;
      title = 'Couldn’t load departures';
      subtitle = 'Check your connection and try again.';
      action = 'Try again';
      actionIcon = Icons.refresh_rounded;
    } else if (filter.isNotEmpty) {
      icon = Icons.search_off_rounded;
      title = 'No departures match “$filter”';
      subtitle = 'Try a different line or clear the filter.';
      action = 'Clear filter';
      actionIcon = Icons.clear_rounded;
    } else {
      icon = Icons.directions_off_rounded;
      title = 'No upcoming departures';
      subtitle = 'There is nothing scheduled from this station right now.';
      action = 'Reload';
      actionIcon = Icons.refresh_rounded;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 52, color: muted),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ],
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onReset,
              icon: Icon(actionIcon, size: 16),
              label: Text(action),
            ),
          ],
        ),
      ),
    );
  }
}
