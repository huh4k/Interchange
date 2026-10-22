import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import '../../domain/entities/trips.dart';
import '../../domain/entities/transit_route.dart';
import '../../theme/app_theme.dart';

class TripCardWidget extends StatelessWidget {
  final Trip trip;
  final bool isFavorite;
  final bool hasDisruption;

  /// When to set off to catch this service; null when walking time is off.
  final DateTime? leaveBy;

  /// False when the service leaves before the rider could walk to the station.
  final bool reachable;
  final VoidCallback onToggleFavorite;
  final VoidCallback onTap;

  const TripCardWidget({
    super.key,
    required this.trip,
    required this.isFavorite,
    this.hasDisruption = false,
    this.leaveBy,
    this.reachable = true,
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
    final destinationText = trip.destinationName;

    final timeString = scheduledTime != null
        ? '${scheduledTime.hour.toString().padLeft(2, '0')}:${scheduledTime.minute.toString().padLeft(2, '0')}'
        : '';
    final minutesLabel = scheduledTime == null
        ? '--'
        : (minutesAway <= 0 ? 'Now' : '$minutesAway');
    final showMinutesUnit = scheduledTime != null && minutesAway > 0;
    // Only call out the status when it carries information; plain
    // "Scheduled" on every card is noise.
    final showStatus = status != ServiceStatus.scheduled;
    final statusTextColor = _getStatusTextColor(status);
    final mutedColor = theme.colorScheme.onSurfaceVariant;
    // Short codes (tram routes, "FKN") read well as a badge; long line names
    // ("Frankston") would just repeat the destination, so they become a
    // coloured line label under it instead.
    final showBadge = lineCode.length <= 4;
    final lineLabel = routeName.isNotEmpty ? routeName : lineCode;
    final showLineLabel = lineLabel.isNotEmpty &&
        (lineLabel != destinationText || !showBadge);
    final minutesColor = scheduledTime != null && minutesAway <= 0
        ? AppColors.statusGreen
        : AppColors.primaryCyan;

    final leaveByText = leaveBy == null
        ? ''
        : reachable
            ? 'Leave by ${_hhmm(leaveBy!)}'
            : 'Too soon';

    final semanticsLabel = [
      '$lineCode to $destinationText',
      if (timeString.isNotEmpty) 'departs $timeString',
      if (scheduledTime != null)
        minutesAway <= 0 ? 'now' : 'in $minutesAway minutes',
      if (platform.isNotEmpty) 'platform $platform',
      if (showStatus) status.label,
      if (leaveByText.isNotEmpty) leaveByText.toLowerCase(),
      if (hasDisruption) 'service alert',
      if (isFavorite) 'saved',
    ].join(', ');

    return Semantics(
      container: true,
      button: true,
      label: semanticsLabel,
      onTap: onTap,
      customSemanticsActions: {
        CustomSemanticsAction(
          label: isFavorite ? 'Remove from saved' : 'Save departure',
        ): onToggleFavorite,
      },
      child: ExcludeSemantics(
        child: Opacity(
          opacity: leaveBy != null && !reachable ? 0.55 : 1,
          child: Card(
          margin: const EdgeInsets.only(bottom: 10.0),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Container(
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: badgeColor, width: 4)),
              ),
              padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
              child: Row(
                children: [
                  if (showBadge) ...[
                    Container(
                      constraints: const BoxConstraints(minWidth: 44),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 7,
                      ),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: badgeColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        lineCode,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          destinationText,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (showLineLabel)
                          Padding(
                            padding: const EdgeInsets.only(top: 2.0),
                            child: Text(
                              showBadge ? lineLabel : '$lineLabel line',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: showBadge ? mutedColor : badgeColor,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        if (leaveByText.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.directions_walk_rounded,
                                  size: 13,
                                  color: reachable
                                      ? AppColors.primaryCyan
                                      : AppColors.statusDelayed,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  leaveByText,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: reachable
                                        ? AppColors.primaryCyan
                                        : AppColors.statusDelayed,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (timeString.isNotEmpty)
                              Text(
                                timeString,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: mutedColor,
                                ),
                              ),
                            if (platform.isNotEmpty)
                              Text(
                                'Plat $platform',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: mutedColor,
                                ),
                              ),
                            if (showStatus)
                              _Chip(
                                label: status.label,
                                color: statusTextColor,
                              ),
                            if (hasDisruption)
                              const _Chip(
                                label: 'Alert',
                                color: AppColors.statusDelayed,
                                icon: Icons.warning_amber_rounded,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          isFavorite
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          color: isFavorite
                              ? AppColors.statusAmber
                              : theme.iconTheme.color?.withAlpha(150),
                          size: 22,
                        ),
                        onPressed: onToggleFavorite,
                        tooltip: isFavorite
                            ? 'Remove from saved departures'
                            : 'Save this departure',
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          textBaseline: TextBaseline.alphabetic,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          children: [
                            Text(
                              minutesLabel,
                              style: TextStyle(
                                color: minutesColor,
                                fontWeight: FontWeight.w800,
                                fontSize: 24,
                                letterSpacing: -0.5,
                              ),
                            ),
                            if (showMinutesUnit) ...[
                              const SizedBox(width: 3),
                              Text(
                                'min',
                                style: TextStyle(
                                  color: minutesColor,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        ),
      ),
    );
  }

  static String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

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

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const _Chip({required this.label, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(90)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 3),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
