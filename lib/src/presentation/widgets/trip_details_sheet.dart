import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../domain/entities/service.dart';
import '../../domain/entities/trips.dart';
import '../../domain/entities/station.dart';
import '../../services/ptv_rt_service.dart';
import '../../services/connection_service.dart';
import '../../theme/app_theme.dart';
import '../state/transit_view_model.dart';
import 'common/ui_kit.dart';
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
  late final PtvRealtimeService _ptvService =
      widget.viewModel?.ptvService ?? PtvRealtimeService();
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

  List<Map<String, dynamic>>? _displayCache;
  List<Map<String, dynamic>>? _displayCacheSource;
  Station? _displayCacheStation;

  /// The stop list trimmed to start at the selected station. Read many times
  /// per build, so it is cached against the identity of its inputs.
  List<Map<String, dynamic>> get _displayStopsSequence {
    final cached = _displayCache;
    if (cached != null &&
        identical(_displayCacheSource, _stopsSequence) &&
        identical(_displayCacheStation, widget.selectedStation)) {
      return cached;
    }
    final result = _computeDisplayStops();
    _displayCache = result;
    _displayCacheSource = _stopsSequence;
    _displayCacheStation = widget.selectedStation;
    return result;
  }

  List<Map<String, dynamic>> _computeDisplayStops() {
    if (_stopsSequence.isEmpty) return [];

    final selId = widget.selectedStation.id;
    final selStopId = widget.selectedStation.stopId;

    final selNameClean = widget.selectedStation.normalizedName;
    int idx = _stopsSequence.indexWhere((s) {
      final st = s['station'] as Station?;
      final stopId = st?.stopId ?? '';
      final id = st?.id ?? '';
      if (selStopId.isNotEmpty && stopId == selStopId) return true;
      if (selId.isNotEmpty && id == selId) return true;
      final name = normalizeStationName(s['name'] as String? ?? st?.name ?? '');
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
        backgroundColor: Theme.of(context).colorScheme.primary,
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
        : departure.lineColor;
    final lineCode = departure?.displayCode ?? widget.trip.shortName ?? widget.trip.routeId;
    final scheduledTime = departure?.scheduledTime;
    final timeStr = scheduledTime != null
        ? '${scheduledTime.hour.toString().padLeft(2, '0')}:${scheduledTime.minute.toString().padLeft(2, '0')}'
        : '--:--';
    final nextStop = _nextStop;

    final scheme = theme.colorScheme;

    return SingleChildScrollView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SheetHandle(),
          const SizedBox(height: 18),

          // Header with Line Badge, Route Name & Share Action
          Row(
            children: [
              LineBadge(code: lineCode, color: badgeColor, large: true),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'To ${widget.trip.destinationName}',
                      style: theme.textTheme.titleLarge?.copyWith(fontSize: 20),
                    ),
                    if (departure?.routeName.isNotEmpty ?? false)
                      Text(
                        departure!.routeName,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.share_rounded, size: 20),
                tooltip: 'Share / Copy trip details',
                style: IconButton.styleFrom(
                  backgroundColor: scheme.surfaceContainerHigh,
                  foregroundColor: scheme.onSurface,
                  side: BorderSide(color: scheme.outlineVariant),
                ),
                onPressed: () => _copyTripItinerary(context),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Quick Summary (Departure, Platform, Status)
          SurfacePanel(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  _buildDetailItem(
                    icon: Icons.schedule_rounded,
                    label: 'Departure',
                    value: timeStr,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  VerticalDivider(width: 1, color: scheme.outlineVariant),
                  _buildDetailItem(
                    icon: Icons.signpost_rounded,
                    label: 'Platform',
                    value: departure?.platform.isNotEmpty == true
                        ? 'Plat ${departure!.platform}'
                        : 'TBA',
                    color: scheme.onSurfaceVariant,
                  ),
                  VerticalDivider(width: 1, color: scheme.outlineVariant),
                  _buildDetailItem(
                    icon: Icons.check_circle_outline_rounded,
                    label: 'Status',
                    value: departure?.status.label ?? 'On Time',
                    color: departure?.status.color ?? AppColors.statusGreen,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Primary Track My Ride Action Button
          if (widget.viewModel != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
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
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ),

          // Next Stop
          if (nextStop != null) ...[
            SurfacePanel(
              accent: Theme.of(context).colorScheme.primary,
              padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
              child: Row(
                children: [
                  IconTile(
                    icon: Icons.navigation_rounded,
                    color: Theme.of(context).colorScheme.primary,
                    size: 36,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SectionLabel(
                          'NEXT STOP',
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          nextStop['name'] as String? ?? 'Upcoming Stop',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
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
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      );
                    }(),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          Text(
            'Route Stop Sequence & Connections',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
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
              color: badgeColor,
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
                  color: badgeColor,
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
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(fontSize: 11, color: muted)),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
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

    final theme = Theme.of(context);
    final endpoint = isFirst || isLast;
    // Same rail-and-dot timeline as the live ride sheet.
    const dotCenter = 10.0;

    return Stack(
      children: [
        if (!isFirst)
          Positioned(
            left: 6.5,
            top: 0,
            height: dotCenter,
            child: Container(width: 3, color: color.withAlpha(110)),
          ),
        if (!isLast)
          Positioned(
            left: 6.5,
            top: dotCenter,
            bottom: 0,
            child: Container(width: 3, color: color.withAlpha(110)),
          ),
        Positioned(
          left: 0,
          top: dotCenter - 8,
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: endpoint ? color : theme.scaffoldBackgroundColor,
              shape: BoxShape.circle,
              border: Border.all(
                color: endpoint ? theme.scaffoldBackgroundColor : color,
                width: 3,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: endpoint ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 14.5,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),

              // Possible Connections Section at this stop
              if (connections.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final conn in connections)
                      TintPill(
                        label: conn.title,
                        color: conn.type.ptvBrandColor,
                        icon: conn.type.icon,
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
            ],
          ),
        ),
      ],
    );
  }
}
