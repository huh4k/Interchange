import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../domain/entities/live_connection.dart';
import '../../domain/entities/service.dart';
import '../../domain/entities/station.dart';
import '../../domain/entities/trips.dart';
import '../../services/connection_service.dart';
import '../../theme/app_theme.dart';
import '../state/transit_view_model.dart';
import 'trip_card_widget.dart';
import 'trip_details_sheet.dart';

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
  StreamSubscription<Position>? _locationSubscription;

  @override
  void initState() {
    super.initState();
    _initLiveTrackingSubscriptions();
  }

  void _initLiveTrackingSubscriptions() {
    // Tightly couple location stream subscription to widget lifecycle so
    // position events update the ViewModel only when the sheet is visible.
    _locationSubscription = widget.viewModel.locationService.positionStream.listen(
      (position) {
        if (mounted) {
          widget.viewModel.handlePositionUpdate(position);
        }
      },
    );
    // Connection polling is now managed by TransitViewModel._trackingPollingTimer
    // so it continues even when this sheet is not visible.
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _locationSubscription = null;
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
      final boardName = boardStation.name.toLowerCase();
      final boardId = boardStation.id;
      final boardStopId = boardStation.stopId;

      final boardNameClean = boardName.replaceAll(RegExp(r'\s+'), ' ').trim();
      final idx = trip.stops.indexWhere((s) {
        if (boardStopId.isNotEmpty && s.station.stopId == boardStopId) return true;
        if (boardId.isNotEmpty && s.station.id == boardId) return true;
        final sName = s.station.name.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
        return sName == boardNameClean;
      });
      if (idx != -1) {
        boardIndex = idx;
      }
    }

    final upcomingJourneyStops = trip.stops.isNotEmpty
        ? trip.stops.sublist(boardIndex)
        : <ServiceStop>[];

    // List of upcoming stops that are designated map interchanges and have connections
    final stopsWithConnections = upcomingJourneyStops.where((s) {
      final isInterchange =
          ConnectionService.isDesignatedInterchange(s.station);
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
                                  _focusedStationName =
                                      selected ? stName : null;
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

                        return _buildStopConnectionTile(
                          context: context,
                          theme: theme,
                          station: station,
                          platform: serviceStop.platform ?? '',
                          departureTime: serviceStop.departureTime,
                          connections: connections,
                          isCurrentStop: (currentStation != null && currentStation.stopId.isNotEmpty && currentStation.stopId == station.stopId) ||
                              (currentStation != null && currentStation.id.isNotEmpty && currentStation.id == station.id) ||
                              currentStation?.name.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim() == station.name.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim(),
                          isNextStop: (nextStation != null && nextStation.stopId.isNotEmpty && nextStation.stopId == station.stopId) ||
                              (nextStation != null && nextStation.id.isNotEmpty && nextStation.id == station.id) ||
                              nextStation?.name.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim() == station.name.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim(),
                        );
                      }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStopConnectionTile({
    required BuildContext context,
    required ThemeData theme,
    required Station station,
    required String platform,
    required DateTime? departureTime,
    required List<LiveConnection> connections,
    required bool isCurrentStop,
    required bool isNextStop,
  }) {
    final isDesignatedInterchange =
        ConnectionService.isDesignatedInterchange(station);
    final hasFocused = _focusedStationName != null;
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
                          fontWeight: isHighlighted ? FontWeight.bold : FontWeight.w500,
                          fontSize: 14,
                          color: isCurrentStop ? AppColors.primaryCyan : null,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isCurrentStop) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
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
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
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
                  '${departureTime.hour.toString().padLeft(2, '0')}:${departureTime.minute.toString().padLeft(2, '0')}',
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
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
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
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
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
                  '${departureTime.hour.toString().padLeft(2, '0')}:${departureTime.minute.toString().padLeft(2, '0')}',
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                        side:
                            const BorderSide(color: AppColors.primaryCyan),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.train_rounded, size: 16),
                      label: Text('View departures at ${station.name}'),
                      onPressed: () =>
                          _showStationDepartures(context, station),
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
                      (conn) => _buildConnectionCard(theme, conn),
                    ),
                    // View all departures button at base of connections list
                    const SizedBox(height: 4),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primaryCyan,
                          side: const BorderSide(
                              color: AppColors.primaryCyan),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.departure_board_rounded,
                            size: 16),
                        label: Text(
                          'View all departures at ${station.name}',
                          style: const TextStyle(fontSize: 13),
                        ),
                        onPressed: () =>
                            _showStationDepartures(context, station),
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

  Widget _buildConnectionCard(ThemeData theme, LiveConnection conn) {
    final feasibility = conn.feasibility;
    final lineCode =
        conn.connectingTrip.departure?.lineCode.isNotEmpty == true
            ? conn.connectingTrip.departure!.lineCode
            : conn.connectingTrip.headsign;
    final depTime = conn.connectingTrainDeparture;
    final timeStr =
        '${depTime.hour.toString().padLeft(2, '0')}:${depTime.minute.toString().padLeft(2, '0')}';
    final bufferMins = conn.bufferMinutes;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: feasibility.color.withAlpha(60),
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryCyan,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      lineCode,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'to ${conn.connectingTrip.destinationName}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              Text(
                timeStr,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Plat ${conn.platform}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              // Feasibility Pill
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: feasibility.color.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: feasibility.color, width: 1.0),
                ),
                child: Row(
                  children: [
                    Icon(
                      feasibility.icon,
                      size: 12,
                      color: feasibility.color,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${feasibility.label} ($bufferMins min)',
                      style: TextStyle(
                        color: feasibility.color,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            feasibility.advisory,
            style: TextStyle(
              fontSize: 11,
              color: theme.textTheme.bodySmall?.color?.withAlpha(170),
            ),
          ),

          // 2nd Departure Backup Card (Rendered ONLY if within the 4-minute mark and 2nd departure exists)
          if (conn.hasSecondDeparture &&
              conn.subsequentConnectingDeparture != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 7,
              ),
              decoration: BoxDecoration(
                color: (conn.subsequentFeasibility?.color ??
                        AppColors.statusGreen)
                    .withAlpha(15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: (conn.subsequentFeasibility?.color ??
                          AppColors.statusGreen)
                      .withAlpha(50),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.update_rounded,
                        size: 14,
                        color: conn.subsequentFeasibility?.color ??
                            AppColors.statusGreen,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Next: ${_formatTime(conn.subsequentConnectingDeparture!)} (Plat ${conn.subsequentPlatform})',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: (conn.subsequentFeasibility?.color ??
                              AppColors.statusGreen)
                          .withAlpha(30),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '+${conn.subsequentBufferMinutes}m (${conn.subsequentFeasibility?.label ?? "Guaranteed"})',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: conn.subsequentFeasibility?.color ??
                            AppColors.statusGreen,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
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
      builder: (ctx) => _StationDeparturesSheet(
        station: station,
        viewModel: widget.viewModel,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _StationDeparturesSheet
// ---------------------------------------------------------------------------

/// A self-contained bottom sheet that shows live departures for a connecting
/// [station] while leaving the parent [LiveRideSheet] and its tracked ride
/// completely undisturbed.
class _StationDeparturesSheet extends StatefulWidget {
  final Station station;
  final TransitViewModel viewModel;

  const _StationDeparturesSheet({
    required this.station,
    required this.viewModel,
  });

  @override
  State<_StationDeparturesSheet> createState() =>
      _StationDeparturesSheetState();
}

class _StationDeparturesSheetState extends State<_StationDeparturesSheet> {
  bool _isLoading = true;
  List<Trip> _trips = [];

  @override
  void initState() {
    super.initState();
    _fetchDepartures();
  }

  Future<void> _fetchDepartures() async {
    final trips = await widget.viewModel.fetchTripsForStation(widget.station);
    if (mounted) {
      setState(() {
        _trips = trips;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final station = widget.station;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.45,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primaryCyan.withAlpha(30),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.alt_route_rounded,
                      color: AppColors.primaryCyan,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          station.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppColors.primaryCyan.withAlpha(25),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: const Text(
                                'CONNECTING STATION',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primaryCyan,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppColors.statusGreen.withAlpha(25),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: const Text(
                                'RIDE TRACKING ACTIVE',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.statusGreen,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    color: AppColors.primaryCyan,
                    tooltip: 'Refresh departures',
                    onPressed: () {
                      setState(() => _isLoading = true);
                      _fetchDepartures();
                    },
                  ),
                ],
              ),
            ),
            Divider(
                height: 1,
                color: theme.dividerColor.withAlpha(40),
                indent: 20,
                endIndent: 20),
            const SizedBox(height: 4),

            // Departures list
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _trips.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.train_outlined,
                                    size: 48,
                                    color: Colors.grey.withAlpha(120)),
                                const SizedBox(height: 12),
                                Text(
                                  'No departures found',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'No upcoming departures at ${station.name} in the next hour.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.grey,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          itemCount: _trips.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 2),
                          itemBuilder: (context, index) {
                            final trip = _trips[index];
                            return TripCardWidget(
                              trip: trip,
                              isFavorite: widget.viewModel
                                  .isFavoriteTrip(trip.tripId),
                              hasDisruption:
                                  widget.viewModel.hasDisruptionForTrip(trip),
                              onToggleFavorite: () => widget.viewModel
                                  .toggleFavoriteTrip(trip.tripId),
                              onTap: () => TripDetailsSheet.show(
                                context,
                                trip: trip,
                                selectedStation: station,
                                viewModel: widget.viewModel,
                              ),
                            );
                          },
                        ),
            ),
          ],
        );
      },
    );
  }
}
