import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_app/src/domain/entities/station.dart';
import 'package:transit_app/src/domain/entities/transit_route.dart';
import 'package:transit_app/src/presentation/screens/disruptions_screen.dart';

void main() {
  const stationFss = Station(
    id: 'vic:rail:FSS',
    stopId: '1071',
    name: 'Flinders Street',
    code: 'FSS',
    lat: -37.8183,
    lon: 144.9671,
    suburb: 'Melbourne CBD',
    zone: 'Zone 1',
    routes: [],
  );

  final myStationAlert = ServiceAlert(
    id: 'alert_fss',
    title: 'Flinders Street Signal Upgrade',
    description: 'Minor delays on Flinders Street platforms.',
    lineCode: 'FSS',
    timestamp: DateTime.now(),
    severity: ServiceStatus.delayed,
  );

  final otherLineAlert = ServiceAlert(
    id: 'alert_mernda',
    title: 'Mernda Line Track Works',
    description: 'Buses replace trains between Clifton Hill and Mernda.',
    lineCode: 'Mernda',
    timestamp: DateTime.now(),
    severity: ServiceStatus.disrupted,
  );

  testWidgets('DisruptionsScreen toggles between My Stations and All Lines', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DisruptionsScreen(
          alerts: [myStationAlert],
          allAlerts: [myStationAlert, otherLineAlert],
          favoriteStations: const [stationFss],
          selectedStation: stationFss,
          isLoading: false,
          onRefresh: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Initially on My Stations
    expect(find.text('Flinders Street Signal Upgrade'), findsOneWidget);
    expect(find.text('Mernda Line Track Works'), findsNothing);
    expect(find.text('MONITORING FAVORITE STATIONS'), findsOneWidget);

    // 2. Tap 'All Lines' segmented tab
    await tester.tap(find.text('All Lines (2)'));
    await tester.pumpAndSettle();

    expect(find.text('Flinders Street Signal Upgrade'), findsOneWidget);
    expect(find.text('Mernda Line Track Works'), findsOneWidget);
    expect(find.text('SHOWING ALL NETWORK DISRUPTIONS'), findsOneWidget);

    // 3. Tap 'My Stations' tab to switch back
    await tester.tap(find.text('My Stations (1)'));
    await tester.pumpAndSettle();

    expect(find.text('Flinders Street Signal Upgrade'), findsOneWidget);
    expect(find.text('Mernda Line Track Works'), findsNothing);

    // 4. Tap AppBar 'All Lines' button to toggle
    await tester.tap(find.widgetWithText(TextButton, 'All Lines'));
    await tester.pumpAndSettle();

    expect(find.text('Mernda Line Track Works'), findsOneWidget);
  });

  testWidgets('DisruptionsScreen empty state allows jumping to all network disruptions', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DisruptionsScreen(
          alerts: const [],
          allAlerts: [otherLineAlert],
          favoriteStations: const [stationFss],
          selectedStation: stationFss,
          isLoading: false,
          onRefresh: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No Active Disruptions'), findsOneWidget);
    expect(find.text('Show All Network Disruptions (1)'), findsOneWidget);

    // Tap button to view all network disruptions
    await tester.tap(find.text('Show All Network Disruptions (1)'));
    await tester.pumpAndSettle();

    expect(find.text('Mernda Line Track Works'), findsOneWidget);
  });
}
