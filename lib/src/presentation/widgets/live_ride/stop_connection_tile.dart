import 'package:flutter/material.dart';
import '../../../domain/entities/live_connection.dart';
import '../../../domain/entities/station.dart';
import '../../../services/connection_service.dart';
import '../../../theme/app_theme.dart';
import '../common/ui_kit.dart';
import 'connection_card.dart';

/// One stop on the live-ride timeline. A rail on the left joins the stops in
/// the line's colour; designated interchanges expand into a card listing
/// their connecting services, local stops are a single row.
class StopConnectionTile extends StatelessWidget {
  final Station station;
  final String platform;
  final DateTime? departureTime;
  final List<LiveConnection> connections;
  final bool isCurrentStop;
  final bool isNextStop;

  /// True when the list is filtered to a single interchange station.
  final bool hasFocused;

  /// Position on the timeline, so the rail starts and ends at the dots.
  final bool isFirst;
  final bool isLast;
  final Color lineColor;
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
    this.isFirst = false,
    this.isLast = false,
    this.lineColor = AppColors.primaryCyan,
    required this.onShowDepartures,
  });

  /// Fixed column left of the rail for time and platform, so every stop's
  /// times line up whether it is a plain row or an interchange card.
  static const double _timeWidth = 42;
  static const double _railWidth = 24;
  static const double _railLeft = _timeWidth + 2;

  @override
  Widget build(BuildContext context) {
    final isInterchange = ConnectionService.isDesignatedInterchange(station);
    // Vertical centre of the dot, lined up with the stop name.
    final dotCenter = isInterchange ? 31.0 : 21.0;

    return Stack(
      children: [
        // Rail above and below the dot
        if (!isFirst)
          Positioned(
            left: _railLeft + _railWidth / 2 - 1.5,
            top: 0,
            height: dotCenter,
            child: _rail(),
          ),
        if (!isLast)
          Positioned(
            left: _railLeft + _railWidth / 2 - 1.5,
            top: dotCenter,
            bottom: 0,
            child: _rail(),
          ),
        Positioned(
          left: _railLeft,
          width: _railWidth,
          top: dotCenter - 9,
          height: 18,
          child: Center(child: _dot(context, isInterchange)),
        ),
        Positioned(
          left: 0,
          width: _timeWidth,
          top: dotCenter - 9,
          child: _timeColumn(context),
        ),
        Padding(
          padding: const EdgeInsets.only(left: _railLeft + _railWidth + 4),
          child: isInterchange
              ? _interchangeCard(context)
              : _localRow(context),
        ),
      ],
    );
  }

  Widget _timeColumn(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final highlighted = isCurrentStop || isNextStop;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          departureTime != null ? formatClockTime(departureTime!) : '--:--',
          style: TextStyle(
            fontSize: 13,
            height: 18 / 13,
            fontWeight: highlighted ? FontWeight.w800 : FontWeight.w600,
            color: highlighted ? scheme.onSurface : scheme.onSurfaceVariant,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (platform.isNotEmpty)
          Text(
            'Plat $platform',
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
      ],
    );
  }

  Widget _rail() =>
      Container(width: 3, color: lineColor.withAlpha(110));

  Widget _dot(BuildContext context, bool isInterchange) {
    final surface = Theme.of(context).scaffoldBackgroundColor;
    if (isCurrentStop) {
      return Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: lineColor,
          shape: BoxShape.circle,
          border: Border.all(color: surface, width: 3),
          boxShadow: [BoxShadow(color: lineColor.withAlpha(120), blurRadius: 8)],
        ),
      );
    }
    final big = isNextStop || isInterchange;
    return Container(
      width: big ? 14 : 10,
      height: big ? 14 : 10,
      decoration: BoxDecoration(
        color: surface,
        shape: BoxShape.circle,
        border: Border.all(color: lineColor, width: big ? 3 : 2.5),
      ),
    );
  }

  Widget? _stateTag(BuildContext context) {
    if (isCurrentStop) {
      return const TintPill(label: 'Now', color: AppColors.statusGreen);
    }
    if (isNextStop) {
      return TintPill(label: 'Next', color: Theme.of(context).colorScheme.primary);
    }
    return null;
  }

  Widget _localRow(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final highlighted = isCurrentStop || isNextStop;
    final tag = _stateTag(context);

    return Padding(
      // Tall enough for the time + platform column beside it.
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        children: [
          Flexible(
            child: Text(
              station.name,
              style: TextStyle(
                fontWeight: highlighted ? FontWeight.w700 : FontWeight.w500,
                fontSize: 14.5,
                color: highlighted ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (tag != null) ...[const SizedBox(width: 8), tag],
        ],
      ),
    );
  }

  Widget _interchangeCard(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tag = _stateTag(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SurfacePanel(
        padding: EdgeInsets.zero,
        borderColor: isCurrentStop || isNextStop
            ? Theme.of(context).colorScheme.primary.withAlpha(140)
            : null,
        child: Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded:
                hasFocused || isCurrentStop || isNextStop || connections.isNotEmpty,
            tilePadding: const EdgeInsets.fromLTRB(14, 2, 10, 2),
            childrenPadding: EdgeInsets.zero,
            iconColor: scheme.onSurfaceVariant,
            collapsedIconColor: scheme.onSurfaceVariant,
            title: Row(
              children: [
                Flexible(
                  child: Text(
                    station.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (tag != null) ...[const SizedBox(width: 8), tag],
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  Icon(
                    Icons.alt_route_rounded,
                    size: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      [
                        'Interchange',
                        if (connections.isNotEmpty)
                          '${connections.length} connections',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (connections.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          'Checking connecting timetables at this interchange…',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    else
                      ...connections.map(
                        (conn) => ConnectionCard(connection: conn),
                      ),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary.withAlpha(30),
                          foregroundColor: Theme.of(context).colorScheme.primary,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(
                          Icons.departure_board_rounded,
                          size: 16,
                        ),
                        label: Text(
                          'Departures at ${station.name}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
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
      ),
    );
  }
}
