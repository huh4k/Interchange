import 'package:gtfs_bindings/schedule.dart' as gtfs;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' show Position;
import 'package:transit_app/src/domain/entities/service.dart' show ServiceStop;
import 'package:provider/provider.dart';
import 'package:transit_app/main.dart';
import 'package:transit_app/src/domain/entities/live_connection.dart';
import 'package:transit_app/src/presentation/screens/home_screen.dart';
import 'package:transit_app/src/presentation/state/transit_view_model.dart';
import 'package:transit_app/src/services/connection_advisor_service.dart';
import 'package:transit_app/src/services/location_service.dart';
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

class _QuietLocation extends LocationService {
  @override
  Future<void> startLocationTracking({void Function(Position position)? onPositionChanged}) async {}
  @override
  Future<void> stopLocationTracking() async {}
}

class _NoConnectionsAdvisor extends ConnectionAdvisorService {
  _NoConnectionsAdvisor() : super(ptvService: _MockPtvService());
  @override
  Future<Map<String, List<LiveConnection>>> computeUpcomingConnections({
    required Trip activeTrip,
    required Station currentOrNextStation,
    required List<Station> allStations,
  }) async => {};
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

  testWidgets('Home content is not rebuilt by keyboard inset changes', (tester) async {
    await tester.pumpWidget(TransitApp(
      repository: _EmptyGtfsRepository(),
      ptvService: _MockPtvService(),
      themeViewModel: ThemeViewModel(SettingsService()),
    ));
    await tester.pumpAndSettle();

    final before = tester.widget<StationSelectorCard>(find.byType(StationSelectorCard));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();
    final after = tester.widget<StationSelectorCard>(find.byType(StationSelectorCard));

    expect(identical(before, after), isTrue);
  });

  testWidgets('GPS fixes rebuild only the mini player, not the home content', (tester) async {
    Station stop(String id, String name, double lat, double lon) => Station(
          id: id,
          stopId: id,
          name: name,
          code: id,
          lat: lat,
          lon: lon,
          suburb: '',
          zone: 'Zone 1',
          routes: const [],
        );
    final one = stop('s1', 'Alpha Station', -37.80, 144.90);
    final two = stop('s2', 'Bravo Station', -37.85, 144.95);
    final three = stop('s3', 'Charlie Station', -37.90, 145.00);
    final trip = Trip(
      tripId: 'ride',
      routeId: 'r',
      serviceId: 's',
      headsign: 'Charlie',
      stops: [
        ServiceStop(station: one, stopSequence: 1),
        ServiceStop(station: two, stopSequence: 2),
        ServiceStop(station: three, stopSequence: 3),
      ],
      departure: TripDeparture(
        scheduledTime: DateTime.now(),
        platform: '1',
        lineCode: 'X',
        routeName: 'X',
        destination: 'Charlie',
        type: TransitType.metro,
      ),
    );

    final repo = _EmptyGtfsRepository();
    final vm = TransitViewModel(
      repository: repo,
      ptvService: _MockPtvService(),
      locationService: _QuietLocation(),
      connectionAdvisor: _NoConnectionsAdvisor(),
    );
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<IGtfsRepository>.value(value: repo),
        ChangeNotifierProvider<TransitViewModel>.value(value: vm),
      ],
      child: const MaterialApp(home: HomeScreen()),
    ));
    await tester.pumpAndSettle();

    await vm.startTrackingTrip(trip, initialStation: one);
    await tester.pump();
    expect(find.textContaining('Alpha Station'), findsWidgets);
    final cardBefore = tester.widget<StationSelectorCard>(find.byType(StationSelectorCard));

    vm.handlePositionUpdate(Position(
      longitude: 144.95,
      latitude: -37.85,
      timestamp: DateTime.now(),
      accuracy: 1,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    ));
    await tester.pump();

    expect(find.textContaining('Bravo Station'), findsWidgets);
    final cardAfter = tester.widget<StationSelectorCard>(find.byType(StationSelectorCard));
    expect(identical(cardBefore, cardAfter), isTrue);

    vm.stopTracking();
    await tester.pumpWidget(const SizedBox());
    vm.dispose();
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
