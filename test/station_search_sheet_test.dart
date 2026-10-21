import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_app/src/domain/entities/station.dart';
import 'package:transit_app/src/domain/value_objects/ptv_mode.dart';
import 'package:transit_app/src/presentation/widgets/station_search_sheet.dart';

void main() {
  const stations = [
    Station(
      id: '1071',
      stopId: '1071',
      name: 'Flinders Street',
      code: 'FSS',
      lat: -37.8183,
      lon: 144.9671,
      suburb: 'CBD',
      zone: 'Zone 1',
      isCityLoop: true,
      routes: [],
    ),
    Station(
      id: '1162',
      stopId: '1162',
      name: 'Richmond Station',
      code: 'RMD',
      lat: -37.8240,
      lon: 144.9896,
      suburb: 'Richmond',
      zone: 'Zone 1',
      isCityLoop: false,
      routes: [],
    ),
  ];

  testWidgets('StationSearchSheet renders and filters by query', (tester) async {
    Station? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StationSearchSheet(
            stations: stations,
            selectedStation: stations.first,
            favoriteStations: const [],
            onStationSelected: (s) => selected = s,
            onToggleFavorite: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Select Station'), findsOneWidget);
    expect(find.text('Flinders Street'), findsOneWidget);
    expect(find.text('Richmond Station'), findsOneWidget);
    expect(find.text('City Loop'), findsOneWidget);

    // Enter search query
    await tester.enterText(find.byType(TextField), 'Richmond');
    await tester.pump();

    expect(find.text('Richmond Station'), findsOneWidget);
    expect(find.text('Flinders Street'), findsNothing);

    // Tap station
    await tester.tap(find.text('Richmond Station'));
    await tester.pump();

    expect(selected?.name, equals('Richmond Station'));
  });

  testWidgets('StationSearchSheet toggles favorite', (tester) async {
    Station? favorited;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StationSearchSheet(
            stations: stations,
            selectedStation: stations.first,
            favoriteStations: const [],
            onStationSelected: (_) {},
            onToggleFavorite: (s) => favorited = s,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Add to favorites').first);
    await tester.pump();

    expect(favorited?.name, equals('Flinders Street'));
  });

  testWidgets('StationSearchSheet renders tram icon when activeMode is metroTram', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StationSearchSheet(
            stations: stations,
            selectedStation: stations.first,
            favoriteStations: const [],
            activeMode: PtvMode.metroTram,
            onStationSelected: (_) {},
            onToggleFavorite: (_) {},
          ),
        ),
      ),
    );

    // Expect tram icons for stops and search prefix/header badge
    expect(find.byIcon(Icons.tram_rounded), findsAtLeastNWidgets(2));
  });
}
