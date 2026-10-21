import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../data/datasources/gtfs_index_engine.dart';
import '../../domain/entities/station.dart';
import '../../domain/value_objects/ptv_mode.dart';
import '../../theme/app_theme.dart';
import 'station_search_sheet.dart';

/// De-duplicates [stations] by id and normalised name, merging the City Loop
/// flag. Exposed for tests.
@visibleForTesting
List<Station> dedupeSelectorStations(List<Station> stations) {
  final uniqueById = <String, Station>{};
  final uniqueByName = <String, Station>{};

  for (final s in stations) {
    final cleanName = GtfsIndexEngine.normalizeStationName(s.name);
    final nameKey = cleanName.toLowerCase();
    final idKey = s.id;

    if (uniqueById.containsKey(idKey)) {
      final existing = uniqueById[idKey]!;
      if (s.isCityLoop && !existing.isCityLoop) {
        uniqueById[idKey] = existing.copyWith(isCityLoop: true);
      }
      continue;
    }

    if (uniqueByName.containsKey(nameKey)) {
      final existing = uniqueByName[nameKey]!;
      if (s.isCityLoop && !existing.isCityLoop) {
        uniqueByName[nameKey] = existing.copyWith(isCityLoop: true);
      }
      continue;
    }

    final stationObj = s.copyWith(name: cleanName);
    uniqueById[idKey] = stationObj;
    uniqueByName[nameKey] = stationObj;
  }

  return uniqueById.values.toList();
}

typedef _Deduped = ({List<Station> stations, List<String> lowerNames});

/// The dedupe is O(stations) (about 1.7k tram stops), so cache it per input
/// list. Station lists are replaced, never mutated in place, so identity is a
/// sound cache key.
final Expando<_Deduped> _dedupeCache = Expando<_Deduped>('stationSelectorDedupe');

_Deduped _dedupedFor(List<Station> stations) {
  return _dedupeCache[stations] ??= () {
    final list = dedupeSelectorStations(stations);
    return (stations: list, lowerNames: [for (final s in list) s.name.toLowerCase()]);
  }();
}

class StationSelectorCard extends StatelessWidget {
  final Station selectedStation;
  final List<Station> stations;
  final List<Station> favoriteStations;
  final List<Station> recentStations;
  final Position? userPosition;
  final PtvMode activeMode;
  final Future<Station?> Function()? onLocateNearest;
  final ValueChanged<Station> onStationSelected;
  final ValueChanged<Station>? onToggleFavorite;

  const StationSelectorCard({
    super.key,
    required this.selectedStation,
    required this.stations,
    this.favoriteStations = const [],
    this.recentStations = const [],
    this.userPosition,
    this.activeMode = PtvMode.metroTrain,
    this.onLocateNearest,
    required this.onStationSelected,
    this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final deduped = _dedupedFor(stations);
    final combinedStations = deduped.stations;

    // Match the selection once per build against precomputed lower-case names.
    final selLower = selectedStation.name.toLowerCase();
    var matchIndex = -1;
    for (var i = 0; i < combinedStations.length; i++) {
      final s = combinedStations[i];
      if (s.id == selectedStation.id ||
          s.stopId == selectedStation.stopId ||
          deduped.lowerNames[i] == selLower) {
        matchIndex = i;
        break;
      }
    }
    final matchingStation = matchIndex != -1
        ? combinedStations[matchIndex]
        : (combinedStations.isNotEmpty ? combinedStations.first : selectedStation);

    final isFav = favoriteStations.any(
      (f) => f.id == matchingStation.id || f.name.toLowerCase() == matchingStation.name.toLowerCase(),
    );

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () {
        StationSearchSheet.show(
          context,
          stations: combinedStations.isNotEmpty ? combinedStations : stations,
          selectedStation: matchingStation,
          favoriteStations: favoriteStations,
          recentStations: recentStations,
          userPosition: userPosition,
          activeMode: activeMode,
          onLocateNearest: onLocateNearest,
          onStationSelected: onStationSelected,
          onToggleFavorite: onToggleFavorite ?? (_) {},
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        decoration: BoxDecoration(
          color: theme.brightness == Brightness.dark
              ? const Color(0xFF1F2B47)
              : const Color(0xFFF0F4F9),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: theme.brightness == Brightness.dark
                ? const Color(0xFF2A3A56)
                : const Color(0xFFD0DDE8),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(8),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (activeMode == PtvMode.metroTram
                        ? AppColors.melbourneTram
                        : AppColors.primaryCyan)
                    .withAlpha(25),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                activeMode == PtvMode.metroTram
                    ? Icons.tram_rounded
                    : Icons.location_on_rounded,
                color: activeMode == PtvMode.metroTram
                    ? AppColors.melbourneTram
                    : AppColors.primaryCyan,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'FROM',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.9,
                      color: theme.textTheme.bodySmall?.color?.withAlpha(160),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          matchingStation.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (matchingStation.isCityLoop) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.melbourneMetro.withAlpha(40),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppColors.melbourneMetro.withAlpha(80),
                              width: 1,
                            ),
                          ),
                          child: const Text(
                            'Loop',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.melbourneMetro,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (onLocateNearest != null) ...[
              IconButton(
                icon: const Icon(
                  Icons.my_location_rounded,
                  color: AppColors.primaryCyan,
                  size: 20,
                ),
                onPressed: () async {
                  final nearest = await onLocateNearest!();
                  if (nearest != null) {
                    onStationSelected(nearest);
                  }
                },
                tooltip: 'Snap to nearest station',
              ),
            ],
            if (onToggleFavorite != null) ...[
              IconButton(
                icon: Icon(
                  isFav ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: isFav ? AppColors.statusAmber : Colors.grey.withAlpha(120),
                  size: 24,
                ),
                onPressed: () => onToggleFavorite!(matchingStation),
                tooltip: isFav ? 'Remove favorite' : 'Add to favorites',
              ),
            ],
            Icon(
              activeMode == PtvMode.metroTram
                  ? Icons.tram_rounded
                  : Icons.search_rounded,
              color: activeMode == PtvMode.metroTram
                  ? AppColors.melbourneTram.withAlpha(180)
                  : Colors.grey,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

