import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gtfs_bindings/schedule.dart' as gtfs;
import 'package:transit_app/src/data/repositories/gtfs_repository.dart';
import 'package:transit_app/src/domain/entities/service.dart';
import 'package:transit_app/src/domain/entities/station.dart';
import 'package:transit_app/src/domain/entities/transit_route.dart';
import 'package:transit_app/src/domain/entities/trips.dart';
import 'package:geolocator/geolocator.dart';
import 'package:transit_app/src/presentation/state/transit_view_model.dart';
import 'package:transit_app/src/presentation/widgets/live_ride_sheet.dart';
import 'package:transit_app/src/services/location_service.dart';
import 'package:transit_app/src/services/ptv_rt_service.dart';

class _MockRepoForLiveRide implements IGtfsRepository {
  @override
  Future<void> clearCache() async {}
  @override
  Future<gtfs.DirectoryDataset?> getDatasetForMode(PtvMode mode, {bool forceRefresh = false, GtfsProgressCallback? onProgress}) async => null;
  @override
  Future<List<ServiceAlert>> getServiceAlerts() async => [];
  @override
  Future<List<Station>> getStopsForMode(PtvMode mode, {bool forceRefresh = false, GtfsProgressCallback? onProgress}) async => [];
  @override
  Future<List<Trip>> getTripsForMode(PtvMode mode, {Station? station, bool forceRefresh = false, GtfsProgressCallback? onProgress}) async => [];
}

class _MockPtvForLiveRide extends PtvRealtimeService {
  @override
  Future<List<ServiceAlert>> fetchLiveDisruptions() async => [];
  @override
  Future<List<Trip>> fetchDepartures(String stopId, {int routeType = 0, int maxResults = 30, Station? station}) async => [];
}

class _MockLocationService extends LocationService {
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> startLocationTracking({void Function(Position position)? onPositionChanged}) async {}
  @override
  Future<void> stopLocationTracking() async {}
}

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  const stationFlinders = Station(
    id: '1071',
    stopId: '1071',
    name: 'Flinders Street Station',
    code: 'FSS',
    lat: -37.8183,
    lon: 144.9671,
    suburb: 'CBD',
    zone: 'Zone 1',
    routes: [],
  );

  const stationRichmond = Station(
    id: '1162',
    stopId: '1162',
    name: 'Richmond Station',
    code: 'RMD',
    lat: -37.8240,
    lon: 144.9896,
    suburb: 'Richmond',
    zone: 'Zone 1',
    routes: [],
  );

  const stationSouthYarra = Station(
    id: '1197',
    stopId: '1197',
    name: 'South Yarra Station',
    code: 'SYR',
    lat: -37.8385,
    lon: 144.9922,
    suburb: 'South Yarra',
    zone: 'Zone 1',
    routes: [],
  );

  final sampleTrip = Trip(
    tripId: 'active_frankston_ride',
    routeId: 'route_fkn',
    serviceId: 'svc_01',
    headsign: 'Frankston',
    stops: [
      const ServiceStop(
        station: stationFlinders,
        departureTime: null,
        platform: '1',
        stopSequence: 1,
      ),
      const ServiceStop(
        station: stationRichmond,
        departureTime: null,
        platform: '4',
        stopSequence: 2,
      ),
      const ServiceStop(
        station: stationSouthYarra,
        departureTime: null,
        platform: '2',
        stopSequence: 3,
      ),
    ],
    departure: TripDeparture(
      scheduledTime: DateTime.now(),
      platform: '1',
      lineCode: 'FKN',
      routeName: 'Frankston Line',
      destination: 'Frankston',
      type: TransitType.metro,
    ),
  );

  testWidgets('LiveRideSheet renders live on-board state, current stop, and next stop at origin', (tester) async {
    final viewModel = TransitViewModel(
      repository: _MockRepoForLiveRide(),
      ptvService: _MockPtvForLiveRide(),
      locationService: _MockLocationService(),
    );

    await viewModel.startTrackingTrip(sampleTrip, initialStation: stationFlinders);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LiveRideSheet(viewModel: viewModel),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('LIVE ON-BOARD'), findsOneWidget);
    expect(find.text('Service to Frankston'), findsOneWidget);
    expect(find.text('CURRENT STOP'), findsOneWidget);
    expect(find.text('Flinders Street Station'), findsWidgets);
    expect(find.text('Next stop: Richmond Station'), findsOneWidget);
    expect(find.text('End Tracking'), findsOneWidget);

    viewModel.stopTracking();
    viewModel.dispose();
  });

  testWidgets('LiveRideSheet renders departed (previous) stop, current stop, and next stop at intermediate station', (tester) async {
    final viewModel = TransitViewModel(
      repository: _MockRepoForLiveRide(),
      ptvService: _MockPtvForLiveRide(),
      locationService: _MockLocationService(),
    );

    await viewModel.startTrackingTrip(sampleTrip, initialStation: stationRichmond);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LiveRideSheet(viewModel: viewModel),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('LIVE ON-BOARD'), findsOneWidget);
    expect(find.text('CURRENT STOP'), findsOneWidget);
    expect(find.text('Richmond Station'), findsWidgets);
    expect(find.text('Departed: Flinders Street Station'), findsOneWidget);
    expect(find.text('Next stop: South Yarra Station'), findsOneWidget);

    viewModel.stopTracking();
    viewModel.dispose();
  });

  testWidgets('LiveRideSheet cleans up location stream subscriptions and polling timers on dismissal', (tester) async {
    final locationService = _MockLocationService();
    final viewModel = TransitViewModel(
      repository: _MockRepoForLiveRide(),
      ptvService: _MockPtvForLiveRide(),
      locationService: locationService,
    );

    await viewModel.startTrackingTrip(sampleTrip, initialStation: stationFlinders);

    // Mount LiveRideSheet
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LiveRideSheet(viewModel: viewModel),
        ),
      ),
    );

    await tester.pump();
    expect(find.byType(LiveRideSheet), findsOneWidget);

    // Simulate location updates while mounted
    locationService.emitMockPosition(
      Position(
        longitude: 144.9896,
        latitude: -37.8240,
        timestamp: DateTime.now(),
        accuracy: 5.0,
        altitude: 0.0,
        altitudeAccuracy: 0.0,
        heading: 0.0,
        headingAccuracy: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
      ),
    );
    await tester.pump();

    // Dismiss the sheet by replacing the widget tree
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(),
        ),
      ),
    );
    await tester.pump();

    // Ensure LiveRideSheet is unmounted and disposed cleanly
    expect(find.byType(LiveRideSheet), findsNothing);

    // Advancing clock past 20s periodic timer interval should complete cleanly without pending timer exceptions
    await tester.pump(const Duration(seconds: 25));

    viewModel.stopTracking();
    viewModel.dispose();
  });
}
