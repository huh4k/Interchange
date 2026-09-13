import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../domain/entities/station.dart';
import '../../domain/value_objects/ptv_mode.dart';
import '../../services/location_service.dart';
import '../../theme/app_theme.dart';

class StationSearchSheet extends StatefulWidget {
  final List<Station> stations;
  final Station selectedStation;
  final List<Station> favoriteStations;
  final List<Station> recentStations;
  final Position? userPosition;
  final PtvMode activeMode;
  final Future<Station?> Function()? onLocateNearest;
  final ValueChanged<Station> onStationSelected;
  final ValueChanged<Station> onToggleFavorite;
  final ScrollController? scrollController;

  const StationSearchSheet({
    super.key,
    required this.stations,
    required this.selectedStation,
    required this.favoriteStations,
    this.recentStations = const [],
    this.userPosition,
    this.activeMode = PtvMode.metroTrain,
    this.onLocateNearest,
    required this.onStationSelected,
    required this.onToggleFavorite,
    this.scrollController,
  });

  static Future<void> show(
    BuildContext context, {
    required List<Station> stations,
    required Station selectedStation,
    required List<Station> favoriteStations,
    List<Station> recentStations = const [],
    Position? userPosition,
    PtvMode activeMode = PtvMode.metroTrain,
    Future<Station?> Function()? onLocateNearest,
    required ValueChanged<Station> onStationSelected,
    required ValueChanged<Station> onToggleFavorite,
  }) {
    final theme = Theme.of(context);
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          builder: (context, scrollController) {
            return StationSearchSheet(
              stations: stations,
              selectedStation: selectedStation,
              favoriteStations: favoriteStations,
              recentStations: recentStations,
              userPosition: userPosition,
              activeMode: activeMode,
              onLocateNearest: onLocateNearest,
              onStationSelected: (st) {
                Navigator.of(context).pop();
                onStationSelected(st);
              },
              onToggleFavorite: onToggleFavorite,
              scrollController: scrollController,
            );
          },
        );
      },
    );
  }

  @override
  State<StationSearchSheet> createState() => _StationSearchSheetState();
}

class _StationSearchSheetState extends State<StationSearchSheet> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';
  bool _isLocating = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _isFavorite(Station s) {
    return widget.favoriteStations.any(
      (fav) => fav.id == s.id || fav.name.toLowerCase() == s.name.toLowerCase(),
    );
  }

  List<Station> get _filteredStations {
    if (_query.isEmpty) return widget.stations;
    final q = _query.toLowerCase().trim();
    return widget.stations.where((s) => s.name.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final results = _filteredStations;
    final favs = widget.favoriteStations;
    final recents = widget.recentStations;

    return Column(
      children: [
        const SizedBox(height: 12),
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
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Text(
                'Select Station',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (widget.activeMode == PtvMode.metroTram
                          ? AppColors.melbourneTram
                          : AppColors.melbourneMetro)
                      .withAlpha(25),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: (widget.activeMode == PtvMode.metroTram
                            ? AppColors.melbourneTram
                            : AppColors.melbourneMetro)
                        .withAlpha(70),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget.activeMode == PtvMode.metroTram
                          ? Icons.tram_rounded
                          : Icons.train_rounded,
                      size: 15,
                      color: widget.activeMode == PtvMode.metroTram
                          ? AppColors.melbourneTram
                          : AppColors.melbourneMetro,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${widget.stations.length} ${widget.activeMode == PtvMode.metroTram ? 'stops' : 'stations'}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: widget.activeMode == PtvMode.metroTram
                            ? AppColors.melbourneTram
                            : AppColors.melbourneMetro,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            controller: _controller,
            autofocus: false,
            decoration: InputDecoration(
              hintText: widget.activeMode == PtvMode.metroTram
                  ? 'Search tram stop (e.g. Bourke St, Collins St)...'
                  : 'Search station name (e.g. Flinders, Richmond)...',
              prefixIcon: Icon(
                widget.activeMode == PtvMode.metroTram
                    ? Icons.tram_rounded
                    : Icons.search_rounded,
                color: widget.activeMode == PtvMode.metroTram
                    ? AppColors.melbourneTram
                    : null,
              ),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () {
                        _controller.clear();
                        setState(() => _query = '');
                      },
                    )
                  : null,
            ),
            onChanged: (val) {
              setState(() => _query = val);
            },
          ),
        ),
        const SizedBox(height: 10),

        // 1-Tap Locate Nearest Station via GPS
        if (widget.onLocateNearest != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryCyan,
                  side: const BorderSide(color: AppColors.primaryCyan),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
                icon: _isLocating
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primaryCyan,
                        ),
                      )
                    : const Icon(Icons.my_location_rounded, size: 16),
                label: Text(
                  _isLocating ? 'Locating closest station...' : 'Find Nearest Station (GPS)',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                onPressed: _isLocating
                    ? null
                    : () async {
                        setState(() => _isLocating = true);
                        final nearest = await widget.onLocateNearest!();
                        if (mounted) {
                          setState(() => _isLocating = false);
                          if (nearest != null) {
                            widget.onStationSelected(nearest);
                          }
                        }
                      },
              ),
            ),
          ),

        // Quick Favorites Row if no search query active
        if (_query.isEmpty && favs.isNotEmpty) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'FAVORITES',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                  color: theme.textTheme.bodySmall?.color?.withAlpha(150),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 38,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: favs.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final st = favs[index];
                final isSelected = st.name == widget.selectedStation.name;
                return ActionChip(
                  avatar: const Icon(Icons.star_rounded, size: 16, color: AppColors.statusAmber),
                  label: Text(st.name),
                  backgroundColor: isSelected
                      ? AppColors.primaryCyan.withAlpha(40)
                      : theme.cardColor,
                  side: BorderSide(
                    color: isSelected
                        ? AppColors.primaryCyan
                        : theme.dividerColor.withAlpha(50),
                  ),
                  onPressed: () => widget.onStationSelected(st),
                );
              },
            ),
          ),
        ],

        // Quick Recent Stations Row if no search query active
        if (_query.isEmpty && recents.isNotEmpty) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'RECENTS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                  color: theme.textTheme.bodySmall?.color?.withAlpha(150),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 38,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: recents.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final st = recents[index];
                final isSelected = st.name == widget.selectedStation.name;
                return ActionChip(
                  avatar: const Icon(Icons.history_rounded, size: 16, color: AppColors.secondaryIndigo),
                  label: Text(st.name),
                  backgroundColor: isSelected
                      ? AppColors.primaryCyan.withAlpha(40)
                      : theme.cardColor,
                  side: BorderSide(
                    color: isSelected
                        ? AppColors.primaryCyan
                        : theme.dividerColor.withAlpha(50),
                  ),
                  onPressed: () => widget.onStationSelected(st),
                );
              },
            ),
          ),
        ],

        if (_query.isEmpty && (favs.isNotEmpty || recents.isNotEmpty)) ...[
          const SizedBox(height: 8),
          const Divider(height: 1),
        ],

        Expanded(
          child: results.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search_off_rounded, size: 48, color: Colors.grey.withAlpha(120)),
                      const SizedBox(height: 12),
                      Text(
                        'No stations matching "$_query"',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: widget.scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: results.length,
                  itemBuilder: (context, index) {
                    final st = results[index];
                    final isSelected = st.name == widget.selectedStation.name ||
                        st.id == widget.selectedStation.id;
                    final isFav = _isFavorite(st);
                    final double? distanceMeters =
                        (widget.userPosition != null && st.lat != 0.0 && st.lon != 0.0)
                            ? LocationService.calculateDistanceMeters(
                                widget.userPosition!.latitude,
                                widget.userPosition!.longitude,
                                st.lat,
                                st.lon,
                              )
                            : null;

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      elevation: 0,
                      color: isSelected
                          ? AppColors.primaryCyan.withAlpha(20)
                          : theme.cardColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: isSelected
                              ? AppColors.primaryCyan
                              : theme.dividerColor.withAlpha(35),
                        ),
                      ),
                      child: ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? (widget.activeMode == PtvMode.metroTram
                                    ? AppColors.melbourneTram
                                    : AppColors.primaryCyan)
                                : theme.dividerColor.withAlpha(20),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            widget.activeMode == PtvMode.metroTram
                                ? Icons.tram_rounded
                                : (st.isCityLoop
                                    ? Icons.subway_rounded
                                    : Icons.train_rounded),
                            size: 20,
                            color: isSelected
                                ? Colors.white
                                : (widget.activeMode == PtvMode.metroTram
                                    ? AppColors.melbourneTram
                                    : AppColors.primaryCyan),
                          ),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                st.name,
                                style: TextStyle(
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            if (distanceMeters != null) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryCyan.withAlpha(25),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: AppColors.primaryCyan.withAlpha(60),
                                    width: 0.8,
                                  ),
                                ),
                                child: Text(
                                  LocationService.formatDistance(distanceMeters),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: AppColors.primaryCyan,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                            if (st.isCityLoop) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.melbourneMetro.withAlpha(35),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'City Loop',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: AppColors.melbourneMetro,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Text(
                          st.zone.isNotEmpty ? st.zone : 'Zone 1',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.textTheme.bodySmall?.color?.withAlpha(150),
                          ),
                        ),
                        trailing: IconButton(
                          icon: Icon(
                            isFav ? Icons.star_rounded : Icons.star_outline_rounded,
                            color: isFav ? AppColors.statusAmber : Colors.grey.withAlpha(120),
                          ),
                          onPressed: () {
                            widget.onToggleFavorite(st);
                            setState(() {});
                          },
                          tooltip: isFav ? 'Remove from favorites' : 'Add to favorites',
                        ),
                        onTap: () => widget.onStationSelected(st),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
