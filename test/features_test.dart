import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transit_app/src/domain/entities/station.dart';
import 'package:transit_app/src/domain/entities/transit_route.dart';
import 'package:transit_app/src/domain/entities/trips.dart';
import 'package:transit_app/src/presentation/screens/disruptions_screen.dart';
import 'package:transit_app/src/presentation/widgets/trip_card_widget.dart';
import 'package:transit_app/src/presentation/widgets/trip_details_sheet.dart';
import 'package:transit_app/src/services/favorite_service.dart';
import 'package:transit_app/src/services/location_service.dart';
import 'package:transit_app/src/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Recent Stations Persistence Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Recent stations can be saved and retrieved with deduplication and cap', () async {
      final service = FavoriteService();

      expect(await service.getRecentStations(), isEmpty);

      final st1 = const Station(
        id: '1',
        stopId: '1001',
        name: 'Flinders Street',
        code: 'FSS',
        lat: -37.8183,
        lon: 144.9671,
        suburb: 'Melbourne',
        zone: 'Zone 1',
        routes: [],
      );

      final st2 = const Station(
        id: '2',
        stopId: '1002',
        name: 'Richmond',
        code: 'RMD',
        lat: -37.8240,
        lon: 144.9900,
        suburb: 'Richmond',
        zone: 'Zone 1',
        routes: [],
      );

      await service.saveRecentStation(st1);
      var recents = await service.getRecentStations();
      expect(recents.length, equals(1));
      expect(recents.first.name, equals('Flinders Street'));

      // Adding st2 moves it to the front
      await service.saveRecentStation(st2);
      recents = await service.getRecentStations();
      expect(recents.length, equals(2));
      expect(recents.first.name, equals('Richmond'));

      // Adding st1 again moves it back to the top without duplicate
      await service.saveRecentStation(st1);
      recents = await service.getRecentStations();
      expect(recents.length, equals(2));
      expect(recents.first.name, equals('Flinders Street'));

      // Clear recents
      await service.clearRecentStations();
      expect(await service.getRecentStations(), isEmpty);
    });
  });

  group('LocationService Distance Formatting Tests', () {
    test('formatDistance accurately formats meters and kilometers', () {
      expect(LocationService.formatDistance(350), equals('350 m'));
      expect(LocationService.formatDistance(999), equals('999 m'));
      expect(LocationService.formatDistance(1000), equals('1.0 km'));
      expect(LocationService.formatDistance(2450), equals('2.5 km'));
      expect(LocationService.formatDistance(12345), equals('12.3 km'));
    });
  });

  group('TripCardWidget Disruption Badge Tests', () {
    testWidgets('Renders Alert badge when hasDisruption is true', (tester) async {
      final trip = Trip(
        tripId: 'T1',
        routeId: 'BEL',
        serviceId: 'S1',
        headsign: 'Belgrave',
        departure: TripDeparture(
          destination: 'Belgrave',
          platform: '2',
          lineCode: 'BEL',
          routeName: 'Belgrave Line',
          type: TransitType.metro,
          scheduledTime: DateTime.now().add(const Duration(minutes: 10)),
          status: ServiceStatus.onTime,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: TripCardWidget(
              trip: trip,
              isFavorite: false,
              hasDisruption: true,
              onToggleFavorite: () {},
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('Alert'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('Does not render Alert badge when hasDisruption is false', (tester) async {
      final trip = Trip(
        tripId: 'T2',
        routeId: 'LIL',
        serviceId: 'S2',
        headsign: 'Lilydale',
        departure: TripDeparture(
          destination: 'Lilydale',
          platform: '3',
          lineCode: 'LIL',
          routeName: 'Lilydale Line',
          type: TransitType.metro,
          scheduledTime: DateTime.now().add(const Duration(minutes: 15)),
          status: ServiceStatus.onTime,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: TripCardWidget(
              trip: trip,
              isFavorite: false,
              hasDisruption: false,
              onToggleFavorite: () {},
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('Alert'), findsNothing);
    });
  });

  group('DisruptionsScreen Severity Filter Tests', () {
    testWidgets('Toggles category filter chips and filters alert list', (tester) async {
      final station = const Station(
        id: '1',
        stopId: '1001',
        name: 'Southern Cross',
        code: 'SSS',
        lat: -37.8185,
        lon: 144.9525,
        suburb: 'Melbourne',
        zone: 'Zone 1',
        routes: [],
      );

      final alerts = [
        ServiceAlert(
          id: 'A1',
          title: 'Major Track Fault near Richmond',
          description: 'Buses replacing trains between Flinders Street and Camberwell',
          lineCode: 'Belgrave',
          timestamp: DateTime.now(),
          severity: ServiceStatus.disrupted,
        ),
        ServiceAlert(
          id: 'A2',
          title: 'Minor Signal Delay',
          description: 'Delays up to 10 minutes on Glen Waverley line',
          lineCode: 'Glen Waverley',
          timestamp: DateTime.now(),
          severity: ServiceStatus.delayed,
        ),
        ServiceAlert(
          id: 'A3',
          title: 'Weekend Maintenance Works',
          description: 'Scheduled track maintenance on Pakenham line',
          lineCode: 'Pakenham',
          timestamp: DateTime.now(),
          severity: ServiceStatus.scheduled,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: DisruptionsScreen(
            alerts: alerts,
            allAlerts: alerts,
            selectedStation: station,
            isLoading: false,
            onRefresh: () {},
          ),
        ),
      );

      // Verify all 3 alerts are shown initially under 'All Alerts'
      expect(find.text('Major Track Fault near Richmond'), findsOneWidget);
      expect(find.text('Minor Signal Delay'), findsOneWidget);
      expect(find.text('Weekend Maintenance Works'), findsOneWidget);

      // Tap 'Disrupted (1)' filter chip
      await tester.tap(find.textContaining('Disrupted (1)'));
      await tester.pumpAndSettle();

      // Only Disrupted alert should be visible
      expect(find.text('Major Track Fault near Richmond'), findsOneWidget);
      expect(find.text('Minor Signal Delay'), findsNothing);
      expect(find.text('Weekend Maintenance Works'), findsNothing);

      // Tap 'Delays (1)' filter chip
      await tester.tap(find.textContaining('Delays (1)'));
      await tester.pumpAndSettle();

      // Only Delayed alert should be visible
      expect(find.text('Minor Signal Delay'), findsOneWidget);
      expect(find.text('Major Track Fault near Richmond'), findsNothing);

      // Reset filter
      await tester.tap(find.textContaining('All Alerts (3)'));
      await tester.pumpAndSettle();

      expect(find.text('Major Track Fault near Richmond'), findsOneWidget);
      expect(find.text('Minor Signal Delay'), findsOneWidget);
      expect(find.text('Weekend Maintenance Works'), findsOneWidget);
    });
  });

  group('TripDetailsSheet Share Itinerary Tests', () {
    testWidgets('Renders Share button in TripDetailsSheet header', (tester) async {
      final station = const Station(
        id: '1',
        stopId: '1001',
        name: 'Flinders Street',
        code: 'FSS',
        lat: -37.8183,
        lon: 144.9671,
        suburb: 'Melbourne',
        zone: 'Zone 1',
        routes: [],
      );

      final trip = Trip(
        tripId: 'T1',
        routeId: 'BEL',
        serviceId: 'S1',
        headsign: 'Belgrave',
        departure: TripDeparture(
          destination: 'Belgrave',
          platform: '1',
          lineCode: 'BEL',
          routeName: 'Belgrave Line',
          type: TransitType.metro,
          scheduledTime: DateTime(2026, 8, 26, 17, 30),
          status: ServiceStatus.onTime,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: TripDetailsSheet(
              trip: trip,
              selectedStation: station,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.share_rounded), findsOneWidget);

      // Tap share button to trigger copy
      await tester.tap(find.byIcon(Icons.share_rounded));
      await tester.pump();

      expect(find.text('Trip details copied to clipboard!'), findsOneWidget);
    });
  });

  group('Bug Fix Regression Tests', () {
    testWidgets('TripCardWidget displays -- when departure scheduledTime is null', (tester) async {
      const tripWithoutDep = Trip(
        tripId: 'trip_no_time',
        routeId: '1',
        serviceId: 's1',
        headsign: 'Flinders Street',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TripCardWidget(
              trip: tripWithoutDep,
              isFavorite: false,
              onToggleFavorite: () {},
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('--'), findsOneWidget);
      expect(find.text('Now'), findsNothing);
    });

    test('Trip.fromPtvDeparture generates fallback tripId when run_ref is missing', () {
      final dep = {
        'scheduled_departure_utc': '2026-09-13T10:00:00Z',
        'direction_id': 1,
      };
      final run = {
        'destination_name': 'Flinders Street',
      };
      final route = {
        'route_id': '101',
        'route_name': 'Frankston',
      };

      final trip = Trip.fromPtvDeparture(dep, run, route);
      expect(trip.tripId, isNotEmpty);
      expect(trip.tripId, contains('101'));
      expect(trip.tripId, contains('2026-09-13'));
    });
  });
}
