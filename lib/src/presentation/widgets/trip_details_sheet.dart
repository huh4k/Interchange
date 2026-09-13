import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../domain/entities/service.dart';
import '../../domain/entities/trips.dart';
import '../../domain/entities/station.dart';
import '../../services/ptv_rt_service.dart';
import '../../services/connection_service.dart';
import '../../theme/app_theme.dart';
import '../state/transit_view_model.dart';
import 'live_ride_sheet.dart';

class TripDetailsSheet extends StatefulWidget {
  final Trip trip;
  final Station selectedStation;
  final TransitViewModel? viewModel;
  final ScrollController? scrollController;

  const TripDetailsSheet({
    super.key,
    required this.trip,
    required this.selectedStation,
    this.viewModel,
    this.scrollController,
  });

  static void show(
    BuildContext context, {
    required Trip trip,
    required Station selectedStation,
    TransitViewModel? viewModel,
  }) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          builder: (context, scrollController) {
            return TripDetailsSheet(
              trip: trip,
              selectedStation: selectedStation,
              viewModel: viewModel,
              scrollController: scrollController,
            );
          },
        );
      },
    );
  }

  @override
  State<TripDetailsSheet> createState() => _TripDetailsSheetState();
}

class _TripDetailsSheetState extends State<TripDetailsSheet> {
  final PtvRealtimeService _ptvService = PtvRealtimeService();
  bool _isLoading = true;
  List<Map<String, dynamic>> _stopsSequence = [];
  List<ServiceStop> _serviceStops = [];

  @override
  void initState() {
    super.initState();
    _fetchPattern();
  }

  Future<void> _fetchPattern() async {
    final runRef = widget.trip.tripId;
    final routeType = widget.trip.departure?.type.value ?? 0;

    // 1. Try PTV API Pattern
    if (runRef.isNotEmpty) {
      final serviceStops = await _ptvService.fetchPatternStops(
        runRef,
        routeType: routeType,
      );

      if (serviceStops.isNotEmpty && mounted) {
        final List<Map<String, dynamic>> seq = serviceStops.map((s) {
          return {
            'station': s.station,
            'name': s.station.name,
            'time': s.departureTime ?? s.arrivalTime,
            'platform': s.platform ?? '',
            'sequence': s.stopSequence,
          };
        }).toList();

        setState(() {
          _serviceStops = serviceStops;
          _stopsSequence = seq;
          _isLoading = false;
        });
        return;
      }
    }

    // 2. Fallback to GTFS Stop Sequence
    if (widget.trip.stops.isNotEmpty && mounted) {
      final List<Map<String, dynamic>> seq = widget.trip.stops.map((stop) {
        final t = stop.departureTime ?? stop.arrivalTime;
        return {
          'station': stop.station,
          'name': stop.station.name,
          'time': t,
          'platform': stop.platform ?? '',
          'sequence': stop.stopSequence,
        };
      }).toList();

      if (mounted) {
        setState(() {
          _serviceStops = widget.trip.stops;
          _stopsSequence = seq;
          _isLoading = false;
        });
        return;
      }
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _displayStopsSequence {
    if (_stopsSequence.isEmpty) return [];

    final selName = widget.selectedStation.name.toLowerCase();
    final selId = widget.selectedStation.id;
    final selStopId = widget.selectedStation.stopId;

    final selNameClean = selName.replaceAll(RegExp(r'\s+'), ' ').trim();
    int idx = _stopsSequence.indexWhere((s) {
      final st = s['station'] as Station?;
      final stopId = st?.stopId ?? '';
      final id = st?.id ?? '';
      if (selStopId.isNotEmpty && stopId == selStopId) return true;
      if (selId.isNotEmpty && id == selId) return true;
      final name = (s['name'] as String? ?? st?.name ?? '').toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
      return name == selNameClean;
    });

    if (idx != -1) {
      return _stopsSequence.sublist(idx);
    }
    return _stopsSequence;
  }

  Map<String, dynamic>? get _nextStop {
    final seq = _displayStopsSequence;
    if (seq.isEmpty) return null;
    final now = DateTime.now();

    for (final s in seq) {
      final time = s['time'] as DateTime?;
      if (time != null &&
          time.isAfter(now.subtract(const Duration(minutes: 1)))) {
        return s;
      }
    }
    return seq.length > 1 ? seq[1] : seq.first;
  }

  String _buildShareableItinerary() {
    final departure = widget.trip.departure;
    final lineCode = departure?.lineCode ?? widget.trip.shortName ?? widget.trip.routeId;
    final origin = widget.selectedStation.name;
    final dest = widget.trip.destinationName;
    final scheduledTime = departure?.scheduledTime;
    final timeStr = scheduledTime != null
        ? '${scheduledTime.hour.toString().padLeft(2, '0')}:${scheduledTime.minute.toString().padLeft(2, '0')}'
        : '';
    final platform = departure?.platform.isNotEmpty == true ? ' • Plat ${departure!.platform}' : '';
    final status = departure?.status.label ?? 'On Time';
    final stopCount = _displayStopsSequence.isNotEmpty ? '${_displayStopsSequence.length} stops' : '';

    final buffer = StringBuffer();
    buffer.writeln('🚆 $lineCode Line: $origin ➔ $dest');
    if (timeStr.isNotEmpty) {
      buffer.writeln('⏰ Departs: $timeStr$platform ($status)');
    }
    if (stopCount.isNotEmpty) {
      buffer.writeln('📍 Route: $stopCount');
    }
    buffer.writeln('📱 Shared via Interchange');
    return buffer.toString().trim();
  }

  void _copyTripItinerary(BuildContext context) {
    final text = _buildShareableItinerary();
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('Trip details copied to clipboard!'),
          ],
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.primaryCyan,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final departure = widget.trip.departure;
    final badgeColor = departure == null
        ? AppColors.melbourneBus
        : departure.type.ptvBrandColor;
    final lineCode = departure?.lineCode ?? widget.trip.shortName ?? widget.trip.routeId;
    final scheduledTime = departure?.scheduledTime;
    final timeStr = scheduledTime != null
        ? '${scheduledTime.hour.toString().padLeft(2, '0')}:${scheduledTime.minute.toString().padLeft(2, '0')}'
        : '--:--';
    final nextStop = _nextStop;

    return SingleChildScrollView(
      controller: widget.scrollController,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey.withAlpha(80),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Header with Line Badge, Route Name & Share Action
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: badgeColor.withAlpha(80),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Text(
                  lineCode,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'To ${widget.trip.destinationName}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (departure?.routeName.isNotEmpty ?? false)
                      Text(
                        departure!.routeName,
                        style: TextStyle(
                          color: theme.textTheme.bodyMedium?.color?.withAlpha(150),
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.share_rounded, size: 22),
                color: AppColors.primaryCyan,
                tooltip: 'Share / Copy trip details',
                onPressed: () => _copyTripItinerary(context),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Quick Summary Cards (Departure, Platform, Status)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.dividerColor.withAlpha(40),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildDetailItem(
                  icon: Icons.schedule_rounded,
                  label: 'Departure',
                  value: timeStr,
                  color: AppColors.primaryCyan,
                ),
                _buildDetailItem(
                  icon: Icons.directions_railway_rounded,
                  label: 'Platform',
                  value: departure?.platform.isNotEmpty == true
                      ? 'Plat ${departure!.platform}'
                      : 'TBA',
                  color: AppColors.secondaryIndigo,
                ),
                _buildDetailItem(
                  icon: Icons.check_circle_outline_rounded,
                  label: 'Status',
                  value: departure?.status.label ?? 'On Time',
                  color: departure?.status.color ?? AppColors.statusGreen,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Primary Track My Ride Action Button
          if (widget.viewModel != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    final vm = widget.viewModel!;
                    final tripWithStops = widget.trip.copyWith(
                      stops: _serviceStops.isNotEmpty
                          ? _serviceStops
                          : widget.trip.stops,
                    );
                    vm.startTrackingTrip(
                      tripWithStops,
                      initialStation: widget.selectedStation,
                    );
                    Navigator.of(context).pop();
                    LiveRideSheet.show(context, vm);
                  },
                  icon: const Icon(Icons.gps_fixed_rounded, size: 20),
                  label: const Text(
                    'Track My Ride & Live Connections',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryCyan,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 3,
                  ),
                ),
              ),
            ),

          // Prominent Next Stop Banner
          if (nextStop != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.primaryCyan.withAlpha(20),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.primaryCyan.withAlpha(70),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryCyan,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.navigation_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'NEXT STOP',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                            color: AppColors.primaryCyan,
                          ),
                        ),
                        Text(
                          nextStop['name'] as String? ?? 'Upcoming Stop',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (nextStop['time'] != null) ...[
                    () {
                      final nTime = nextStop['time'] as DateTime;
                      final tStr = '${nTime.hour.toString().padLeft(2, '0')}:${nTime.minute.toString().padLeft(2, '0')}';
                      return Text(
                        tStr,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: AppColors.primaryCyan,
                        ),
                      );
                    }(),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          Text(
            'Route Stop Sequence & Connections',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 14),

          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32.0),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_displayStopsSequence.isEmpty) ...[
            _buildTimelineItem(
              station: widget.selectedStation,
              title: widget.selectedStation.name,
              subtitle: 'Origin Station • Departs $timeStr',
              isFirst: true,
              isLast: false,
              color: AppColors.primaryCyan,
              currentLineCode: lineCode,
            ),
            _buildTimelineItem(
              station: Station(
                id: 'dest',
                stopId: 'dest',
                name: widget.trip.destinationName,
                code: '',
                lat: 0,
                lon: 0,
                suburb: '',
                zone: 'Zone 1',
                routes: const [],
              ),
              title: widget.trip.destinationName,
              subtitle: 'Terminating Station',
              isFirst: false,
              isLast: true,
              color: badgeColor,
              currentLineCode: lineCode,
            ),
          ] else ...[
            for (int i = 0; i < _displayStopsSequence.length; i++) ...[
              () {
                final stop = _displayStopsSequence[i];
                final isFirst = i == 0;
                final isLast = i == _displayStopsSequence.length - 1;
                final t = stop['time'] as DateTime?;
                final tStr = t != null
                    ? '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}'
                    : '';
                final plat = stop['platform']?.toString() ?? '';
                final platStr = plat.isNotEmpty ? ' • Plat $plat' : '';

                final sub = isFirst
                    ? 'Origin Station • Departs $tStr$platStr'
                    : (isLast
                        ? 'Terminus • Arrives $tStr$platStr'
                        : 'Stop ${i + 1} • $tStr$platStr');

                final stObj = stop['station'] as Station? ??
                    Station(
                      id: stop['name'] as String,
                      stopId: stop['name'] as String,
                      name: stop['name'] as String,
                      code: '',
                      lat: 0,
                      lon: 0,
                      suburb: '',
                      zone: 'Zone 1',
                      routes: const [],
                    );

                return _buildTimelineItem(
                  station: stObj,
                  title: stop['name'] as String,
                  subtitle: sub,
                  isFirst: isFirst,
                  isLast: isLast,
                  color: isFirst
                      ? AppColors.primaryCyan
                      : (isLast ? badgeColor : Colors.grey),
                  currentLineCode: lineCode,
                );
              }(),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildDetailItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildTimelineItem({
    required Station station,
    required String title,
    required String subtitle,
    required bool isFirst,
    required bool isLast,
    required Color color,
    required String currentLineCode,
  }) {
    final connections = ConnectionService.getConnectionsForStation(
      station,
      currentLineCode: currentLineCode,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: connections.isNotEmpty ? 70 : 40,
                color: Colors.grey.withAlpha(80),
              ),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),

              // Possible Connections Section at this stop
              if (connections.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: connections.map((conn) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: conn.type.ptvBrandColor.withAlpha(25),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: conn.type.ptvBrandColor.withAlpha(80),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            conn.type.icon,
                            size: 11,
                            color: conn.type.ptvBrandColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            conn.title,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: conn.type.ptvBrandColor,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 16),
            ],
          ),
        ),
      ],
    );
  }
}
