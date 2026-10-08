import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtfs_bindings/schedule.dart' as gtfs;
import 'package:transit_app/src/data/repositories/gtfs_repository.dart';
import 'package:transit_app/src/domain/entities/service.dart';
import 'package:transit_app/src/domain/entities/station.dart';
import 'package:transit_app/src/domain/entities/trips.dart';
import 'package:transit_app/src/domain/entities/transit_route.dart';
import 'package:transit_app/src/presentation/state/transit_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:transit_app/src/services/connection_advisor_service.dart';
import 'package:transit_app/src/services/location_service.dart';
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

class _FixedLocationService extends LocationService {
  @override
  Future<Position?> getCurrentPosition() async => Position(
        longitude: 144.9,
        latitude: -37.8,
        timestamp: DateTime.now(),
        accuracy: 1,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
}

class _GeoRepository extends _MockRepository {
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
      lat: -37.8,
      lon: 144.9,
      suburb: 'Melbourne',
      zone: 'Zone 1',
      routes: [],
    ),
  ];
}

Station _station(String id, String name) => Station(
      id: id,
      stopId: id,
      name: name,
      code: id,
      lat: -37.8,
      lon: 144.9,
      suburb: 'Melbourne',
      zone: 'Zone 1',
      routes: const [],
    );

class _GatedRepository extends _MockRepository {
  final Completer<List<Station>> train = Completer();
  final Completer<List<Station>> tram = Completer();

  @override
  Future<List<Station>> getStopsForMode(
    PtvMode mode, {
    bool forceRefresh = false,
    GtfsProgressCallback? onProgress,
  }) =>
      mode == PtvMode.metroTram ? tram.future : train.future;
}

class _RecordingPtv extends _MockPtvService {
  final departureStopIds = <String>[];
  int disruptionCalls = 0;

  @override
  Future<List<ServiceAlert>> fetchLiveDisruptions() async {
    disruptionCalls++;
    return [];
  }

  @override
  Future<List<Trip>> fetchDepartures(String stopId,
      {int routeType = 0, int maxResults = 15, Station? station}) {
    departureStopIds.add(station?.stopId ?? stopId);
    return super.fetchDepartures(stopId,
        routeType: routeType, maxResults: maxResults, station: station);
  }
}

class _CountingRepository extends _MockRepository {
  int stopCalls = 0;

  @override
  Future<List<Station>> getStopsForMode(
    PtvMode mode, {
    bool forceRefresh = false,
    GtfsProgressCallback? onProgress,
  }) {
    stopCalls++;
    return super.getStopsForMode(mode, forceRefresh: forceRefresh, onProgress: onProgress);
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

    test('displayedTrips is memoised and invalidated by query and favorites', () async {
      await viewModel.loadData();
      final first = viewModel.displayedTrips;
      expect(identical(first, viewModel.displayedTrips), isTrue);

      viewModel.updateSearchQuery('belgrave');
      final filtered = viewModel.displayedTrips;
      expect(identical(first, filtered), isFalse);
      expect(filtered.length, 1);

      viewModel.updateSearchQuery('');
      viewModel.selectNavIndex(1);
      expect(viewModel.displayedTrips, isEmpty);
      await viewModel.toggleFavoriteTrip('trip_belgrave');
      expect(viewModel.displayedTrips.map((t) => t.tripId), ['trip_belgrave']);
    });

    test('locateNearestStation returns the station without selecting it', () async {
      final vm = TransitViewModel(
        repository: _GeoRepository(),
        ptvService: _MockPtvService(),
        locationService: _FixedLocationService(),
      );
      addTearDown(vm.dispose);
      await vm.loadData();
      final before = vm.selectedStation;
      final nearest = await vm.locateNearestStation();
      expect(nearest, isNotNull);
      expect(nearest!.name, 'Flinders Street');
      expect(identical(vm.selectedStation, before), isTrue);
      expect(vm.isLocating, isFalse);
    });

    test('favorite toggle notifies before persisting completes', () async {
      var notified = 0;
      viewModel.addListener(() => notified++);
      final future = viewModel.toggleFavoriteTrip('x');
      await viewModel.initFuture;
      await Future<void>.delayed(Duration.zero);
      expect(notified, greaterThan(0));
      expect(viewModel.isFavoriteTrip('x'), isTrue);
      await future;
    });

    test('connection advisor shares the view model PTV service', () {
      final ptv = _MockPtvService();
      final vm = TransitViewModel(repository: _MockRepository(), ptvService: ptv);
      addTearDown(vm.dispose);
      expect(identical(vm.ptvService, ptv), isTrue);
      expect(identical(vm.connectionAdvisor.ptvService, ptv), isTrue);

      final defaultVm = TransitViewModel(repository: _MockRepository());
      addTearDown(defaultVm.dispose);
      expect(identical(defaultVm.connectionAdvisor.ptvService, defaultVm.ptvService), isTrue);
    });

    test('an injected connection advisor is used as-is', () {
      final advisor = ConnectionAdvisorService(
        ptvService: _MockPtvService(),
        repository: _MockRepository(),
      );
      final vm = TransitViewModel(repository: _MockRepository(), connectionAdvisor: advisor);
      addTearDown(vm.dispose);
      expect(identical(vm.connectionAdvisor, advisor), isTrue);
    });

    test('station taps, resets and mode switches reuse loaded stations', () async {
      final repo = _CountingRepository();
      final vm = TransitViewModel(repository: repo, ptvService: _MockPtvService());
      addTearDown(vm.dispose);
      Future<void> settle() async {
        while (vm.isLoading) {
          await Future<void>.delayed(Duration.zero);
        }
      }

      await vm.loadData();
      expect(repo.stopCalls, 1);

      vm.selectStation(vm.stations.first);
      await settle();
      expect(repo.stopCalls, 1);

      vm.resetFilters();
      await settle();
      expect(repo.stopCalls, 1);

      vm.switchBaseMode(PtvMode.metroTram);
      await settle();
      expect(repo.stopCalls, 2);

      vm.switchBaseMode(PtvMode.metroTrain);
      await settle();
      expect(repo.stopCalls, 2);

      await vm.loadData();
      expect(repo.stopCalls, 3);
    });

    test('a mode switch during a stations load does not poison the other mode', () async {
      final repo = _GatedRepository();
      final vm = TransitViewModel(repository: repo, ptvService: _MockPtvService());
      addTearDown(vm.dispose);

      final first = vm.loadData();
      vm.switchBaseMode(PtvMode.metroTram);
      repo.tram.complete([_station('tram_1', 'Bourke St/Swanston St')]);
      await Future<void>.delayed(Duration.zero);
      repo.train.complete([_station('train_1', 'Richmond')]);
      await first;
      while (vm.isLoading) {
        await Future<void>.delayed(Duration.zero);
      }

      vm.selectStation(vm.stations.first);
      while (vm.isLoading) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(vm.stations.map((s) => s.id), ['tram_1']);
    });

    test('alerts and departures start before the stations step finishes', () async {
      final repo = _GatedRepository();
      final ptv = _RecordingPtv();
      final vm = TransitViewModel(repository: repo, ptvService: ptv);
      addTearDown(vm.dispose);
      await vm.initFuture;

      final load = vm.loadData();
      await pumpEventQueue();
      expect(ptv.disruptionCalls, 1);
      expect(ptv.departureStopIds, ['1071']);
      expect(vm.isLoading, isTrue);

      repo.train.complete([_station('1071', 'Flinders Street Station')]);
      await load;
      // The speculative request is reused: still exactly one departures call.
      expect(ptv.departureStopIds, ['1071']);
      expect(vm.isLoading, isFalse);
      expect(vm.trips, isNotEmpty);
    });

    test('a station without a direct PTV id gets no speculative departures call', () async {
      final repo = _GatedRepository();
      final ptv = _RecordingPtv();
      final vm = TransitViewModel(repository: repo, ptvService: ptv);
      addTearDown(vm.dispose);
      await vm.initFuture;

      final odd = _station('vic:rail:STL', 'St Albans');
      final load = vm.loadData(station: odd);
      await pumpEventQueue();
      expect(ptv.departureStopIds, isEmpty);

      repo.train.complete([odd]);
      await load;
      expect(ptv.departureStopIds, ['vic:rail:STL']);
    });

    test('silent refresh reuses the loaded station list', () async {
      final repo = _CountingRepository();
      final vm = TransitViewModel(repository: repo, ptvService: _MockPtvService());
      addTearDown(vm.dispose);
      await vm.loadData();
      expect(repo.stopCalls, 1);
      await vm.loadData(isSilent: true);
      expect(repo.stopCalls, 1);
      await vm.loadData();
      expect(repo.stopCalls, 2);
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

    test('loadData with isSilent: true refreshes departures without setting isLoading to true', () async {
      await viewModel.loadData();
      expect(viewModel.isLoading, isFalse);

      bool wasLoadingDuringSilent = false;
      viewModel.addListener(() {
        if (viewModel.isLoading) {
          wasLoadingDuringSilent = true;
        }
      });

      await viewModel.loadData(isSilent: true);
      expect(wasLoadingDuringSilent, isFalse);
      expect(viewModel.isLoading, isFalse);
      expect(viewModel.trips, isNotEmpty);
    });
  });
}
