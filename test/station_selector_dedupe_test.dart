import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_app/src/data/datasources/gtfs_index_engine.dart';
import 'package:transit_app/src/domain/entities/station.dart';
import 'package:transit_app/src/presentation/widgets/station_selector_card.dart';

Station _st(String id, String name, {bool loop = false, String? stopId}) => Station(
      id: id,
      stopId: stopId ?? id,
      name: name,
      code: id,
      lat: -37.8,
      lon: 144.9,
      suburb: '',
      zone: 'Zone 1',
      isCityLoop: loop,
      routes: const [],
    );

/// The pre-optimisation implementation, kept verbatim as the reference.
List<Station> _reference(List<Station> stations) {
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

void main() {
  final fixture = [
    _st('1', 'Flinders Street Railway Station'),
    _st('1', 'Flinders Street Station', loop: true), // duplicate id
    _st('2', 'Flinders Street Station'), // same normalised name as #1
    _st('3', 'Richmond Railway Station/Platform 1', loop: true),
    _st('4', 'Bourke St/Swanston St #5'),
    _st('5', 'Southern  Cross   Station', loop: true),
    _st('6', 'Southern Cross Station'),
  ];

  test('dedupeSelectorStations matches the reference implementation', () {
    final got = dedupeSelectorStations(fixture);
    final want = _reference(fixture);
    expect(got.map((s) => [s.id, s.name, s.isCityLoop]).toList(),
        want.map((s) => [s.id, s.name, s.isCityLoop]).toList());
  });

  testWidgets('card updates its label when the selection changes with the same list', (tester) async {
    final stations = [_st('1', 'Flinders Street Station'), _st('2', 'Richmond Station')];
    Widget host(Station selected) => MaterialApp(
          home: Scaffold(
            body: StationSelectorCard(
              selectedStation: selected,
              stations: stations,
              onStationSelected: (_) {},
            ),
          ),
        );

    await tester.pumpWidget(host(stations[0]));
    expect(find.text('Flinders Street Station'), findsWidgets);
    await tester.pumpWidget(host(stations[1]));
    expect(find.text('Richmond Station'), findsWidgets);
  });
}
