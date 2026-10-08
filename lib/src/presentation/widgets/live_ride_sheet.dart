import 'package:flutter/material.dart';
import '../../domain/entities/service.dart';
import '../../domain/entities/station.dart';
import '../../services/connection_service.dart';
import '../../theme/app_theme.dart';
import '../state/transit_view_model.dart';
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
    final viewModel = widget.viewModel;
    final trip = viewModel.activeTrackedTrip;

    if (trip == null) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: const Center(child: Text('No active service being tracked')),
      );
    }

    final onBoardStation = viewModel.onBoardStation;
    final currentStation = viewModel.currentStopStation ?? onBoardStation;
    final previousStation = viewModel.previousStopStation;
    final nextStation = viewModel.nextStopStation;
    final connectionsByStation = viewModel.upcomingConnections;
    final isLoadingConnections = viewModel.isLoadingConnections;

    final isTramTrip = trip.departure?.type.value == 1;
    final lineCode = trip.departure?.lineCode.isNotEmpty == true
        ? trip.departure!.lineCode
        : (isTramTrip ? 'TRAM' : 'METRO');
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

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(80),
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Column(
        children: [
          // Drag Handle
          const SizedBox(height: 12),
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: theme.dividerColor.withAlpha(60),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.statusGreen.withAlpha(30),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppColors.statusGreen,
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.statusGreen,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'LIVE ON-BOARD',
                            style: TextStyle(
                              color: AppColors.statusGreen,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primaryCyan,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        lineCode,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: () {
                    viewModel.stopTracking();
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(
                    Icons.stop_circle_outlined,
                    size: 18,
                    color: AppColors.statusRose,
                  ),
                  label: const Text(
                    'End Tracking',
                    style: TextStyle(color: AppColors.statusRose, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Service to $destination',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ),

          const SizedBox(height: 10),

          // Scrollable Content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              children: [
                // Current Stop Callout Card
                if (currentStation != null || nextStation != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primaryCyan.withAlpha(35),
                          AppColors.secondaryIndigo.withAlpha(25),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: AppColors.primaryCyan.withAlpha(80),
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.primaryCyan.withAlpha(50),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.directions_railway_rounded,
                            color: AppColors.primaryCyan,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'CURRENT STOP',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.0,
                                  color: AppColors.primaryCyan,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                (currentStation ?? nextStation)!.name,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 17,
                                ),
                              ),
                              if (previousStation != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Departed: ${previousStation.name}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.textTheme.bodySmall?.color
                                        ?.withAlpha(160),
                                  ),
                                ),
                              ],
                              if (nextStation != null &&
                                  nextStation.name != currentStation?.name) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Next stop: ${nextStation.name}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.primaryCyan,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                // Upcoming Interchange Station Filter Chips
                if (stopsWithConnections.isNotEmpty) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'SELECT UPCOMING INTERCHANGE STATION',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                        color: theme.textTheme.bodySmall?.color?.withAlpha(160),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 38,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: const Text(
                              'All Upcoming Stops',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            selected: _focusedStationName == null,
                            onSelected: (selected) {
                              if (selected) {
                                setState(() => _focusedStationName = null);
                              }
                            },
                          ),
                        ),
                        ...stopsWithConnections.map((stop) {
                          final stName = stop.station.name;
                          final conns = connectionsByStation[stName] ?? [];
                          final isSelected = _focusedStationName == stName;

                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              avatar: Icon(
                                Icons.alt_route_rounded,
                                size: 14,
                                color: isSelected
                                    ? Colors.white
                                    : AppColors.primaryCyan,
                              ),
                              label: Text(
                                '$stName (${conns.length})',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              selected: isSelected,
                              onSelected: (selected) {
                                setState(() {
                                  _focusedStationName = selected
                                      ? stName
                                      : null;
                                });
                              },
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Connection Advisory Section Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _focusedStationName != null
                          ? 'CONNECTIONS AT $_focusedStationName'.toUpperCase()
                          : 'UPCOMING STOPS & CONNECTIONS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                        color: theme.textTheme.bodySmall?.color?.withAlpha(160),
                      ),
                    ),
                    if (isLoadingConnections)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        onPressed: viewModel.refreshUpcomingConnections,
                        tooltip: 'Refresh Connections',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                // Stops & Connection Cards List
                if (upcomingJourneyStops.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Text(
                      'No intermediate stopping points available for this run.',
                    ),
                  )
                else
                  ...upcomingJourneyStops
                      .where(
                        (s) =>
                            _focusedStationName == null ||
                            s.station.name.toLowerCase() ==
                                _focusedStationName!.toLowerCase(),
                      )
                      .map((serviceStop) {
                        final station = serviceStop.station;
                        final connections =
                            connectionsByStation[station.name] ?? [];

                        return StopConnectionTile(
                          station: station,
                          platform: serviceStop.platform ?? '',
                          departureTime: serviceStop.departureTime,
                          connections: connections,
                          isCurrentStop:
                              currentStation?.isSameStopAs(station) ?? false,
                          isNextStop:
                              nextStation?.isSameStopAs(station) ?? false,
                          hasFocused: _focusedStationName != null,
                          onShowDepartures: (st) =>
                              _showStationDepartures(context, st),
                        );
                      }),
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) =>
          StationDeparturesSheet(station: station, viewModel: widget.viewModel),
    );
  }
}
