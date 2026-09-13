import 'package:flutter/material.dart';
import '../../domain/entities/trips.dart';
import '../../domain/entities/transit_route.dart';
import '../../theme/app_theme.dart';

class TripCardWidget extends StatelessWidget {
  final Trip trip;
  final bool isFavorite;
  final bool hasDisruption;
  final VoidCallback onToggleFavorite;
  final VoidCallback onTap;

  const TripCardWidget({
    super.key,
    required this.trip,
    required this.isFavorite,
    this.hasDisruption = false,
    required this.onToggleFavorite,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final departure = trip.departure;

    final lineCode = departure?.lineCode ?? trip.shortName ?? trip.routeId;
    final badgeColor = departure == null
        ? AppColors.melbourneBus
        : departure.type.ptvBrandColor;
    final status = departure?.status ?? ServiceStatus.scheduled;
    final minutesAway = departure?.minutesUntil(DateTime.now()) ?? 0;
    final platform = departure?.platform ?? '';
    final scheduledTime = departure?.scheduledTime;
    final routeName = departure?.routeName ?? '';

    final timeString = scheduledTime != null
        ? '${scheduledTime.hour.toString().padLeft(2, '0')}:${scheduledTime.minute.toString().padLeft(2, '0')}'
        : '';

    final destinationText = trip.destinationName;

    final statusBackgroundColor = _getStatusBackgroundColor(status);
    final statusTextColor = _getStatusTextColor(status);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Card(
        margin: const EdgeInsets.only(bottom: 12.0),
        elevation: 1,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.brightness == Brightness.dark
                  ? const Color(0xFF2A3A56)
                  : const Color(0xFFE8EEF5),
              width: 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Row: Line Badge, Destination, Favorite
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: badgeColor,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: badgeColor.withAlpha(80),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        lineCode,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  destinationText,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (hasDisruption) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.statusDelayed.withAlpha(35),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: AppColors.statusDelayed.withAlpha(90),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.warning_amber_rounded,
                                        size: 12,
                                        color: AppColors.statusDelayed,
                                      ),
                                      SizedBox(width: 3),
                                      Text(
                                        'Alert',
                                        style: TextStyle(
                                          color: AppColors.statusDelayed,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (routeName.isNotEmpty && routeName != destinationText)
                            Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Text(
                                routeName,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.textTheme.bodySmall?.color
                                      ?.withAlpha(180),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                        color: isFavorite ? AppColors.statusAmber : Colors.grey,
                        size: 24,
                      ),
                      onPressed: onToggleFavorite,
                      tooltip: isFavorite
                          ? 'Remove from saved departures'
                          : 'Save this departure',
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Divider with enhanced styling
                Container(
                  height: 1,
                  color: theme.brightness == Brightness.dark
                      ? const Color(0xFF2A3A56)
                      : const Color(0xFFE2E8F0),
                ),
                const SizedBox(height: 14),

                // Footer Row: Time/Platform, Status, Minutes
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.primaryCyan.withAlpha(25),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.schedule_rounded,
                            size: 16,
                            color: AppColors.primaryCyan,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (timeString.isNotEmpty)
                              Text(
                                timeString,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                            if (platform.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2.0),
                                child: Text(
                                  'Plat $platform',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.textTheme.bodySmall?.color
                                        ?.withAlpha(160),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: statusBackgroundColor,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: statusTextColor.withAlpha(80),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            status.label,
                            style: TextStyle(
                              color: statusTextColor,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primaryCyan.withAlpha(35),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.primaryCyan.withAlpha(80),
                              width: 1.5,
                            ),
                          ),
                          child: Text(
                            scheduledTime == null
                                ? '--'
                                : (minutesAway <= 0 ? 'Now' : '$minutesAway min'),
                            style: const TextStyle(
                              color: AppColors.primaryCyan,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getStatusBackgroundColor(ServiceStatus status) {
    switch (status) {
      case ServiceStatus.onTime:
        return AppColors.statusGreen.withAlpha(30);
      case ServiceStatus.delayed:
        return AppColors.statusDelayed.withAlpha(30);
      case ServiceStatus.disrupted:
        return AppColors.statusDisrupted.withAlpha(30);
      case ServiceStatus.cancelled:
        return AppColors.statusDisrupted.withAlpha(30);
      case ServiceStatus.scheduled:
        return AppColors.secondaryIndigo.withAlpha(25);
    }
  }

  Color _getStatusTextColor(ServiceStatus status) {
    switch (status) {
      case ServiceStatus.onTime:
        return AppColors.statusGreen;
      case ServiceStatus.delayed:
        return AppColors.statusDelayed;
      case ServiceStatus.disrupted:
        return AppColors.statusDisrupted;
      case ServiceStatus.cancelled:
        return AppColors.statusDisrupted;
      case ServiceStatus.scheduled:
        return AppColors.secondaryIndigo;
    }
  }
}

