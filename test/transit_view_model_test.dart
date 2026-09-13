import 'package:flutter_test/flutter_test.dart';
import 'package:gtfs_bindings/schedule.dart' as gtfs;
import 'package:transit_app/src/data/repositories/gtfs_repository.dart';
import 'package:transit_app/src/domain/entities/service.dart';
import 'package:transit_app/src/domain/entities/station.dart';
import 'package:transit_app/src/domain/entities/trips.dart';
import 'package:transit_app/src/domain/entities/transit_route.dart';
import 'package:transit_app/src/presentation/state/transit_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transit_app/src/services/ptv_rt_service.dart';

class _MockRepository implements IGtfsRepository {
  @override
  Future<void> clearCache() async {}

  @override
  Future<gtfs.DirectoryDataset?> getDatasetForMode(
    PtvMode mode, {
    bool forceRefresh = false,
    GtfsProgressCallback? onProgress,
  }) async => null;

  @override
  Future<List<ServiceAlert>> getServiceAlerts() async => [];

  @override
  Future<List<Station>> getStopsForMode(
    PtvMode mode, {
    bool forceRefresh = false,
    GtfsProgressCallback? onProgress,
  }) async => [
    const Station(
      id: 'st_1',
      stopId: '101',
      name: 'Flinders Street',
      code: 'FSS',
      lat: 0.0,
      lon: 0.0,
      suburb: 'Melbourne',
      zone: 'Zone 1',
      routes: [],
    ),
  ];

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
        tripId: 'trip_belgrave',
        routeId: 'route_bel',
        serviceId: 'svc_1',
        headsign: 'Belgrave',
        departure: TripDeparture(
          scheduledTime: DateTime.now().add(const Duration(minutes: 5)),
          platform: '1',
          lineCode: 'BEL',
          routeName: 'Belgrave Line',
          destination: 'Belgrave',
          type: TransitType.metro,
        ),
      ),
      Trip(
        tripId: 'trip_frankston',
        routeId: 'route_frk',
        serviceId: 'svc_1',
        headsign: 'Frankston',
        departure: TripDeparture(
          scheduledTime: DateTime.now().add(const Duration(minutes: 12)),
          platform: '2',
          lineCode: 'FRK',
          routeName: 'Frankston Line',
          destination: 'Frankston',
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
        tripId: 'trip_belgrave',
        routeId: 'route_bel',
        serviceId: 'svc_1',
        headsign: 'Belgrave',
        departure: TripDeparture(
          scheduledTime: DateTime.now().add(const Duration(minutes: 5)),
          platform: '1',
          lineCode: 'BEL',
          routeName: 'Belgrave Line',
          destination: 'Belgrave',
          type: TransitType.metro,
        ),
      ),
      Trip(
        tripId: 'trip_frankston',
        routeId: 'route_frk',
        serviceId: 'svc_1',
        headsign: 'Frankston',
        departure: TripDeparture(
          scheduledTime: DateTime.now().add(const Duration(minutes: 12)),
          platform: '2',
          lineCode: 'FRK',
          routeName: 'Frankston Line',
          destination: 'Frankston',
          type: TransitType.metro,
        ),
      ),
    ];
  }
}

void main() {
  // Required because TransitViewModel calls WidgetsBinding.instance.addObserver
  // in its constructor, which needs the binding to be available.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TransitViewModel Tests', () {
    late TransitViewModel viewModel;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      viewModel = TransitViewModel(
        repository: _MockRepository(),
        ptvService: _MockPtvService(),
      );
    });

    tearDown(() {
      viewModel.dispose();
    });

    test('Initializes with default state and loads trips with percentage progress', () async {
      expect(viewModel.isLoading, isTrue);
      await viewModel.loadData();
      expect(viewModel.isLoading, isFalse);
      expect(viewModel.loadingProgress, equals(1.0));
      expect(viewModel.loadingPercentage, equals(100));
      expect(viewModel.trips.length, equals(2));
      expect(viewModel.filteredTrips.length, equals(2));
    });

    test('Filters trips by search query', () async {
      await viewModel.loadData();

      viewModel.updateSearchQuery('Belgrave');
      expect(viewModel.filteredTrips.length, equals(1));
      expect(viewModel.filteredTrips.single.headsign, equals('Belgrave'));

      viewModel.updateSearchQuery('Frankston');
      expect(viewModel.filteredTrips.length, equals(1));
      expect(viewModel.filteredTrips.single.headsign, equals('Frankston'));

      viewModel.updateSearchQuery('');
      expect(viewModel.filteredTrips.length, equals(2));
    });

    test('Manages favorite trips state', () async {
      await viewModel.loadData();

      expect(viewModel.isFavoriteTrip('trip_belgrave'), isFalse);
      await viewModel.toggleFavoriteTrip('trip_belgrave');
      expect(viewModel.isFavoriteTrip('trip_belgrave'), isTrue);

      viewModel.selectNavIndex(1); // Saved view
      expect(viewModel.displayedTrips.length, equals(1));
      expect(viewModel.displayedTrips.single.tripId, equals('trip_belgrave'));
    });

    test('Manages favorite stations state', () async {
      const station = Station(
        id: 'st_richmond',
        stopId: '19845',
        name: 'Richmond Station',
        code: 'RMD',
        lat: -37.8240,
        lon: 144.9896,
        suburb: 'Richmond',
        zone: 'Zone 1',
        routes: [],
      );

      expect(viewModel.isFavoriteStation(station), isFalse);
      await viewModel.toggleFavoriteStation(station);
      expect(viewModel.isFavoriteStation(station), isTrue);
      expect(viewModel.favoriteStations.length, equals(1));

      await viewModel.toggleFavoriteStation(station);
      expect(viewModel.isFavoriteStation(station), isFalse);
      expect(viewModel.favoriteStations.isEmpty, isTrue);
    });

    test('Switches base transit mode correctly', () async {
      await viewModel.loadData();

      expect(viewModel.activeMode, equals(PtvMode.metroTrain));

      viewModel.switchBaseMode(PtvMode.metroTram);
      expect(viewModel.activeMode, equals(PtvMode.metroTram));

      viewModel.switchBaseMode(PtvMode.metroTrain);
      expect(viewModel.activeMode, equals(PtvMode.metroTrain));

      // Switching to the same mode is a no-op
      viewModel.switchBaseMode(PtvMode.metroTrain);
      expect(viewModel.activeMode, equals(PtvMode.metroTrain));
    });

    test('Tracks trip correctly computing previous, current, and next stops', () async {
      const st1 = Station(
        id: '1',
        stopId: '1',
        name: 'Station 1',
        code: 'S1',
        lat: 0,
        lon: 0,
        suburb: '',
        zone: '1',
        routes: [],
      );
      const st2 = Station(
        id: '2',
        stopId: '2',
        name: 'Station 2',
        code: 'S2',
        lat: 0,
        lon: 0,
        suburb: '',
        zone: '1',
        routes: [],
      );
      const st3 = Station(
        id: '3',
        stopId: '3',
        name: 'Station 3',
        code: 'S3',
        lat: 0,
        lon: 0,
        suburb: '',
        zone: '1',
        routes: [],
      );

      final trip = Trip(
        tripId: 'test_trip',
        routeId: 'r1',
        serviceId: 's1',
        headsign: 'Station 3',
        stops: const [
          ServiceStop(station: st1, stopSequence: 1),
          ServiceStop(station: st2, stopSequence: 2),
          ServiceStop(station: st3, stopSequence: 3),
        ],
      );

      // 1. Boarding at origin (Station 1)
      await viewModel.startTrackingTrip(trip, initialStation: st1);
      expect(viewModel.isTrackingActive, isTrue);
      expect(viewModel.currentStopStation?.name, equals('Station 1'));
      expect(viewModel.onBoardStation?.name, equals('Station 1'));
      expect(viewModel.previousStopStation, isNull);
      expect(viewModel.nextStopStation?.name, equals('Station 2'));

      // 2. Boarding at intermediate station (Station 2)
      await viewModel.startTrackingTrip(trip, initialStation: st2);
      expect(viewModel.currentStopStation?.name, equals('Station 2'));
      expect(viewModel.previousStopStation?.name, equals('Station 1'));
      expect(viewModel.nextStopStation?.name, equals('Station 3'));

      // 3. Stop tracking
      viewModel.stopTracking();
      expect(viewModel.isTrackingActive, isFalse);
      expect(viewModel.currentStopStation, isNull);
      expect(viewModel.previousStopStation, isNull);
      expect(viewModel.nextStopStation, isNull);
    });

    test('preserves requestedStation in loadData even if not present in stationList', () async {
      final customStation = const Station(
        id: '2721',
        stopId: '2721',
        name: 'Collins St/Elizabeth St #2',
        code: '2',
        lat: -37.816,
        lon: 144.964,
        suburb: 'Melbourne CBD',
        zone: 'Zone 1',
        routes: [],
      );

      await viewModel.loadData(station: customStation);
      expect(viewModel.selectedStation.stopId, equals('2721'));
      expect(viewModel.selectedStation.name, equals('Collins St/Elizabeth St #2'));
    });

    test('startTrackingTrip prioritizes stopId over duplicate street names', () async {
      const stop1 = Station(
        id: '2722',
        stopId: '2722',
        name: 'Flinders St/Elizabeth St #1',
        code: '1',
        lat: 0,
        lon: 0,
        suburb: '',
        zone: '1',
        routes: [],
      );
      const stop2 = Station(
        id: '2721',
        stopId: '2721',
        name: 'Collins St/Elizabeth St #2',
        code: '2',
        lat: 0,
        lon: 0,
        suburb: '',
        zone: '1',
        routes: [],
      );
      const stop3 = Station(
        id: '2720',
        stopId: '2720',
        name: 'Bourke St/Elizabeth St #3',
        code: '3',
        lat: 0,
        lon: 0,
        suburb: '',
        zone: '1',
        routes: [],
      );

      final trip = Trip(
        tripId: 'tram_trip_59',
        routeId: '59',
        serviceId: 's1',
        headsign: 'Airport West',
        stops: const [
          ServiceStop(station: stop1, stopSequence: 1),
          ServiceStop(station: stop2, stopSequence: 2),
          ServiceStop(station: stop3, stopSequence: 3),
        ],
      );

      // User boards at Stop 2 (Collins St/Elizabeth St #2)
      await viewModel.startTrackingTrip(trip, initialStation: stop2);
      expect(viewModel.currentStopStation?.stopId, equals('2721'));
      expect(viewModel.previousStopStation?.stopId, equals('2722'));
      expect(viewModel.nextStopStation?.stopId, equals('2720'));
    });
  });
}
