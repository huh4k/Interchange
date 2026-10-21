import 'package:flutter/material.dart';
import '../../../domain/entities/live_connection.dart';
import '../../../domain/entities/station.dart';
import '../../../services/connection_service.dart';
import '../../../theme/app_theme.dart';
import 'connection_card.dart';

/// One stop in the upcoming-journey list. Designated interchanges expand to
/// show their connecting services; local stops render as a simple node.
class StopConnectionTile extends StatelessWidget {
  final Station station;
  final String platform;
  final DateTime? departureTime;
  final List<LiveConnection> connections;
  final bool isCurrentStop;
  final bool isNextStop;

  /// True when the list is filtered to a single interchange station.
  final bool hasFocused;
  final void Function(Station station) onShowDepartures;

  const StopConnectionTile({
    super.key,
    required this.station,
    required this.platform,
    required this.departureTime,
    required this.connections,
    required this.isCurrentStop,
    required this.isNextStop,
    required this.hasFocused,
    required this.onShowDepartures,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDesignatedInterchange = ConnectionService.isDesignatedInterchange(
      station,
    );
    final isHighlighted = isCurrentStop || isNextStop;

    if (!isDesignatedInterchange) {
      // Standard Local Stop (Non-Interchange): Clean, simple timeline node
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: isCurrentStop
                ? AppColors.primaryCyan
                : (isNextStop
                      ? AppColors.primaryCyan.withAlpha(120)
                      : theme.dividerColor.withAlpha(25)),
            width: isCurrentStop ? 1.8 : (isNextStop ? 1.4 : 1.0),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: isHighlighted
                      ? AppColors.primaryCyan.withAlpha(30)
                      : theme.dividerColor.withAlpha(15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.circle,
                  color: isHighlighted
                      ? AppColors.primaryCyan
                      : Colors.grey.withAlpha(120),
                  size: 9,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        station.name,
                        style: TextStyle(
                          fontWeight: isHighlighted
                              ? FontWeight.bold
                              : FontWeight.w500,
                          fontSize: 14,
                          color: isCurrentStop ? AppColors.primaryCyan : null,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isCurrentStop) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primaryCyan.withAlpha(30),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'CURRENT',
                          style: TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryCyan,
                          ),
                        ),
                      ),
                    ] else if (isNextStop) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primaryCyan.withAlpha(20),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'NEXT',
                          style: TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryCyan,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (platform.isNotEmpty) ...[
                Text(
                  'Plat $platform',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(width: 8),
              ],
              if (departureTime != null)
                Text(
                  formatClockTime(departureTime!),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
            ],
          ),
        ),
      );
    }

    // Designated Interchange Station: Interactive expandable card
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isCurrentStop
              ? AppColors.primaryCyan
              : (isNextStop
                    ? AppColors.primaryCyan.withAlpha(120)
                    : AppColors.primaryCyan.withAlpha(70)),
          width: isCurrentStop ? 2.0 : (isNextStop ? 1.5 : 1.2),
        ),
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded:
              hasFocused || isHighlighted || connections.isNotEmpty,
          leading: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.primaryCyan.withAlpha(30),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.alt_route_rounded,
              color: AppColors.primaryCyan,
              size: 19,
            ),
          ),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  station.name,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: isCurrentStop ? AppColors.primaryCyan : null,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              if (isCurrentStop) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryCyan.withAlpha(30),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'CURRENT',
                    style: TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      color: AppColors.primaryCyan,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ] else if (isNextStop) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryCyan.withAlpha(20),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'NEXT',
                    style: TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      color: AppColors.primaryCyan,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 1.5,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primaryCyan.withAlpha(25),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'INTERCHANGE',
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: AppColors.primaryCyan,
                  ),
                ),
              ),
            ],
          ),
          subtitle: Row(
            children: [
              if (platform.isNotEmpty) ...[
                Text(
                  'Plat $platform',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(width: 8),
              ],
              if (departureTime != null)
                Text(
                  formatClockTime(departureTime!),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              const SizedBox(width: 8),
              if (connections.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.statusGreen.withAlpha(25),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${connections.length} Destinations',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.statusGreen,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          children: [
            if (connections.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Checking connecting timetables at this interchange...',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primaryCyan,
                        side: const BorderSide(color: AppColors.primaryCyan),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.train_rounded, size: 16),
                      label: Text('View departures at ${station.name}'),
                      onPressed: () => onShowDepartures(station),
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(height: 1),
                    const SizedBox(height: 10),
                    ...connections.map(
                      (conn) => ConnectionCard(connection: conn),
                    ),
                    // View all departures button at base of connections list
                    const SizedBox(height: 4),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primaryCyan,
                          side: const BorderSide(color: AppColors.primaryCyan),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(
                          Icons.departure_board_rounded,
                          size: 16,
                        ),
                        label: Text(
                          'View all departures at ${station.name}',
                          style: const TextStyle(fontSize: 13),
                        ),
                        onPressed: () => onShowDepartures(station),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
