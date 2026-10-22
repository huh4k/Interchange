import 'package:flutter/material.dart';
import '../../domain/entities/service.dart';
import '../../domain/entities/station.dart';
import '../../domain/value_objects/transit_type.dart';
import '../../services/connection_service.dart';
import '../../theme/app_theme.dart';
import '../state/transit_view_model.dart';
import 'common/ui_kit.dart';
import 'live_ride/station_departures_sheet.dart';
import 'live_ride/stop_connection_tile.dart';

class LiveRideSheet extends StatefulWidget {
  final TransitViewModel viewModel;

  const LiveRideSheet({super.key, required this.viewModel});

  static void show(BuildContext context, TransitViewModel viewModel) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ListenableBuilder(
        listenable: viewModel,
        builder: (ctx, _) => LiveRideSheet(viewModel: viewModel),
      ),
    );
  }

  @override
  State<LiveRideSheet> createState() => _LiveRideSheetState();
}

class _LiveRideSheetState extends State<LiveRideSheet> {
  String? _focusedStationName;
  late final TransitViewModel _viewModel = widget.viewModel;

  @override
  void initState() {
    super.initState();
    // GPS fixes reach the view model directly (TransitViewModel owns the single
    // position subscription); the sheet only tells it that connections are now
    // on screen so polling can speed up while it is visible.
    _viewModel.liveRideSheetOpened();
  }

  @override
  void dispose() {
    _viewModel.liveRideSheetClosed();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final viewModel = widget.viewModel;
    final trip = viewModel.activeTrackedTrip;
    const sheetShape = BorderRadius.vertical(top: Radius.circular(28));

    if (trip == null) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: sheetShape,
        ),
        child: Center(
          child: Text(
            'No active service being tracked',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ),
      );
    }

    final onBoardStation = viewModel.onBoardStation;
    final currentStation = viewModel.currentStopStation ?? onBoardStation;
    final previousStation = viewModel.previousStopStation;
    final nextStation = viewModel.nextStopStation;
    final isBetweenStops = viewModel.isBetweenStops;
    final connectionsByStation = viewModel.upcomingConnections;
    final isLoadingConnections = viewModel.isLoadingConnections;

    final isTramTrip = trip.departure?.type.value == 1;
    final lineCode = trip.departure?.lineCode.isNotEmpty == true
        ? trip.departure!.lineCode
        : (isTramTrip
            ? 'TRAM'
            : trip.departure?.type == TransitType.regionalTrain
                ? 'V/LINE'
                : 'METRO');
    final lineColor =
        trip.departure?.type.ptvBrandColor ?? AppColors.melbourneMetro;
    final destination = trip.destinationName;

    // Filter trip stops to only show the boarding station and following stations
    final boardStation =
        currentStation ?? nextStation ?? viewModel.selectedStation;
    int boardIndex = 0;
    if (trip.stops.isNotEmpty) {
      final idx = trip.stops.indexWhere(
        (s) => s.station.isSameStopAs(boardStation),
      );
      if (idx != -1) {
        boardIndex = idx;
      }
    }

    final upcomingJourneyStops = trip.stops.isNotEmpty
        ? trip.stops.sublist(boardIndex)
        : <ServiceStop>[];

    // List of upcoming stops that are designated map interchanges and have connections
    final stopsWithConnections = upcomingJourneyStops.where((s) {
      final isInterchange = ConnectionService.isDesignatedInterchange(
        s.station,
      );
      final conns = connectionsByStation[s.station.name] ?? [];
      return isInterchange && conns.isNotEmpty;
    }).toList();

    final visibleStops = upcomingJourneyStops
        .where(
          (s) =>
              _focusedStationName == null ||
              s.station.name.toLowerCase() ==
                  _focusedStationName!.toLowerCase(),
        )
        .toList();

    final mutedStyle = TextStyle(fontSize: 13, color: scheme.onSurfaceVariant);

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: sheetShape,
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          const SheetHandle(),
          const SizedBox(height: 14),

          // Header: live state + end action, then the service itself
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const TintPill(
                      label: 'LIVE ON-BOARD',
                      color: AppColors.statusGreen,
                      dot: true,
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () {
                        viewModel.stopTracking();
                        Navigator.of(context).pop();
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.statusRose,
                        backgroundColor: AppColors.statusRose.withAlpha(24),
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      icon: const Icon(Icons.stop_rounded, size: 18),
                      label: const Text(
                        'End Tracking',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    LineBadge(code: lineCode, color: lineColor, large: true),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Service to $destination',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontSize: 20,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Scrollable Content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                // Where the rider is right now
                if (currentStation != null || nextStation != null)
                  SurfacePanel(
                    accent: lineColor,
                    margin: const EdgeInsets.only(bottom: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SectionLabel(
                          isBetweenStops ? 'BETWEEN STOPS' : 'CURRENT STOP',
                          color: AppColors.primaryCyan,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isBetweenStops && currentStation != null
                              ? '${currentStation.name} → ${nextStation!.name}'
                              : (currentStation ?? nextStation)!.name,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontSize: 19,
                          ),
                        ),
                        if (isBetweenStops) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Departed: ${currentStation!.name}',
                            style: mutedStyle,
                          ),
                        ] else if (previousStation != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Departed: ${previousStation.name}',
                            style: mutedStyle,
                          ),
                        ],
                        if (nextStation != null &&
                            nextStation.name != currentStation?.name) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              const Icon(
                                Icons.arrow_forward_rounded,
                                size: 16,
                                color: AppColors.primaryCyan,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  '${isBetweenStops ? 'Approaching' : 'Next stop'}: ${nextStation.name}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primaryCyan,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                // Jump to an upcoming interchange
                if (stopsWithConnections.isNotEmpty) ...[
                  const SectionLabel('JUMP TO INTERCHANGE'),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 34,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        SelectPill(
                          label: 'All stops',
                          selected: _focusedStationName == null,
                          onTap: () =>
                              setState(() => _focusedStationName = null),
                        ),
                        ...stopsWithConnections.map((stop) {
                          final stName = stop.station.name;
                          final conns = connectionsByStation[stName] ?? [];
                          final isSelected = _focusedStationName == stName;
                          return Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: SelectPill(
                              icon: Icons.alt_route_rounded,
                              label: '$stName (${conns.length})',
                              selected: isSelected,
                              onTap: () => setState(() {
                                _focusedStationName =
                                    isSelected ? null : stName;
                              }),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // Stops & connections header
                Row(
                  children: [
                    Expanded(
                      child: SectionLabel(
                        _focusedStationName != null
                            ? 'CONNECTIONS AT $_focusedStationName'
                                .toUpperCase()
                            : 'UPCOMING STOPS & CONNECTIONS',
                      ),
                    ),
                    if (isLoadingConnections)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        onPressed: viewModel.refreshUpcomingConnections,
                        tooltip: 'Refresh Connections',
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                const SizedBox(height: 8),

                // Stop timeline
                if (upcomingJourneyStops.isEmpty)
                  SurfacePanel(
                    child: Text(
                      'No intermediate stopping points available for this run.',
                      style: mutedStyle,
                    ),
                  )
                else
                  for (var i = 0; i < visibleStops.length; i++)
                    StopConnectionTile(
                      station: visibleStops[i].station,
                      platform: visibleStops[i].platform ?? '',
                      departureTime: visibleStops[i].departureTime,
                      connections:
                          connectionsByStation[visibleStops[i].station.name] ??
                              [],
                      isCurrentStop:
                          currentStation?.isSameStopAs(visibleStops[i].station) ??
                              false,
                      isNextStop:
                          nextStation?.isSameStopAs(visibleStops[i].station) ??
                              false,
                      hasFocused: _focusedStationName != null,
                      isFirst: i == 0,
                      isLast: i == visibleStops.length - 1,
                      lineColor: lineColor,
                      onShowDepartures: (st) =>
                          _showStationDepartures(context, st),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Opens a departures bottom sheet for [station] without stopping the active
  /// ride tracking. The tracked trip and on-board position are left untouched.
  void _showStationDepartures(BuildContext context, Station station) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) =>
          StationDeparturesSheet(station: station, viewModel: widget.viewModel),
    );
  }
}
