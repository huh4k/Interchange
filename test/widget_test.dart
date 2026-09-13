import 'package:gtfs_bindings/schedule.dart' as gtfs;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_app/main.dart';
import 'package:transit_app/src/domain/entities/transit_route.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transit_app/src/services/ptv_rt_service.dart';
import 'package:transit_app/src/domain/entities/station.dart';
import 'package:transit_app/src/domain/entities/trips.dart';
import 'package:transit_app/src/presentation/widgets/station_selector_card.dart';
import 'package:transit_app/src/services/gtfs_parser.dart';
import 'package:transit_app/src/presentation/state/theme_view_model.dart';
import 'package:transit_app/src/services/settings_service.dart';

class _EmptyGtfsRepository implements IGtfsRepository {
  @override
  Future<void> clearCache() async {}

  @override
  Future<gtfs.DirectoryDataset?> getDatasetForMode(
    PtvMode mode, {
    bool forceRefresh = false,
    GtfsProgressCallback? onProgress,
  }) async => null;

  @override
  Future<List<ServiceAlert>> getServiceAlerts() async => [
    ServiceAlert(
      id: 'alert_1',
      title: 'Flinders Street Track Maintenance',
      description: 'Maintenance works around Flinders Street Station.',
      lineCode: 'FSS',
      timestamp: DateTime.now(),
      severity: ServiceStatus.disrupted,
    ),
  ];

  @override
  Future<List<Station>> getStopsForMode(
    PtvMode mode, {
    bool forceRefresh = false,
    GtfsProgressCallback? onProgress,
  }) async => [];

  @override
  Future<List<Trip>> getTripsForMode(
    PtvMode mode, {
    Station? station,
    bool forceRefresh = false,
    GtfsProgressCallback? onProgress,
  }) async {
    onProgress?.call(1.0, 'Mock complete');
    return [
      Trip(
        tripId: 'test-trip',
        routeId: 'test-route',
        serviceId: 'test-service',
        headsign: 'Test destination',
        shortName: 'T1',
        departure: TripDeparture(
          scheduledTime: DateTime.now().add(const Duration(minutes: 10)),
          platform: '1',
          lineCode: 'T1',
          routeName: 'Test line',
          destination: 'Test destination',
          type: TransitType.metro,
        ),
      ),
    ];
  }
}

class _MockPtvService extends PtvRealtimeService {
  @override
  Future<List<ServiceAlert>> fetchLiveDisruptions() async => [];

  @override
  Future<List<Trip>> fetchDepartures(String stopId, {int routeType = 0, int maxResults = 15, Station? station}) async {
    return [
      Trip(
        tripId: 'trip_1',
        routeId: 'route_1',
        serviceId: 'svc_1',
        headsign: 'Flinders Street',
        departure: TripDeparture(
          scheduledTime: DateTime.now().add(const Duration(minutes: 5)),
          platform: '1',
          lineCode: 'FSS',
          routeName: 'Metro',
          destination: 'Flinders Street',
          type: TransitType.metro,
        ),
      ),
    ];
  }
}

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Saved departures are reachable from navigation', (tester) async {
    await tester.pumpWidget(TransitApp(
      repository: _EmptyGtfsRepository(),
      ptvService: _MockPtvService(),
      themeViewModel: ThemeViewModel(SettingsService()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Save this departure'));
    await tester.pump();
    await tester.tap(find.text('Saved'));
    await tester.pump();

    expect(find.text('Saved Departures'), findsOneWidget);
    expect(find.text('Flinders Street'), findsOneWidget);
  });

  testWidgets('Disruptions screen is reachable from bottom navigation tab', (tester) async {
    await tester.pumpWidget(TransitApp(
      repository: _EmptyGtfsRepository(),
      ptvService: _MockPtvService(),
      themeViewModel: ThemeViewModel(SettingsService()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Disruptions'));
    await tester.pumpAndSettle();

    expect(find.text('Station Disruptions'), findsOneWidget);
    expect(find.text('Flinders Street Track Maintenance'), findsOneWidget);
  });

  testWidgets('Station selector handles empty station lists without asserting', (tester) async {
    const selectedStation = Station(
      id: 'vic:rail:STL',
      stopId: 'vic:rail:STL',
      name: 'Franklin St',
      code: 'vic:rail:STL',
      lat: 0,
      lon: 0,
      suburb: 'Melbourne',
      zone: 'Zone 1',
      routes: [],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StationSelectorCard(
            selectedStation: selectedStation,
            stations: const [],
            onStationSelected: (_) {},
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Franklin St'), findsOneWidget);
  });
}
