import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gtfs_bindings/schedule.dart' as gtfs;
import 'package:transit_app/src/data/repositories/gtfs_repository.dart';
import 'package:transit_app/src/domain/entities/service.dart';
import 'package:transit_app/src/domain/entities/station.dart';
import 'package:transit_app/src/domain/entities/transit_route.dart';
import 'package:transit_app/src/domain/entities/trips.dart';
import 'package:transit_app/src/domain/value_objects/transfer_feasibility.dart';
import 'package:transit_app/src/services/connection_advisor_service.dart';
import 'package:transit_app/src/services/connection_service.dart';
import 'package:transit_app/src/services/ptv_rt_service.dart';

class _MockPtvServiceForAdvisor extends PtvRealtimeService {
  final DateTime now;
  _MockPtvServiceForAdvisor(this.now);

  @override
  Future<List<Trip>> fetchDepartures(
    String stopId, {
    int routeType = 0,
    int maxResults = 30,
    Station? station,
  }) async {
    // Current train arrives at Richmond at now + 3 mins
    final richmondArrival = now.add(const Duration(minutes: 3));

    return [
      // 1 min buffer (tight)
      Trip(
        tripId: 'conn_belgrave',
        routeId: 'route_bel',
        serviceId: 'svc_1',
        headsign: 'Belgrave',
        departure: TripDeparture(
          scheduledTime: richmondArrival.add(const Duration(minutes: 1)),
          platform: '9',
          lineCode: 'BEL',
          routeName: 'Belgrave Line',
          destination: 'Belgrave',
          type: TransitType.metro,
        ),
      ),
      // 2 min buffer (possible)
      Trip(
        tripId: 'conn_lilydale',
        routeId: 'route_lil',
        serviceId: 'svc_1',
        headsign: 'Lilydale',
        departure: TripDeparture(
          scheduledTime: richmondArrival.add(const Duration(minutes: 2)),
          platform: '10',
          lineCode: 'LIL',
          routeName: 'Lilydale Line',
          destination: 'Lilydale',
          type: TransitType.metro,
        ),
      ),
      // 3 min buffer (easy)
      Trip(
        tripId: 'conn_glen_waverley',
        routeId: 'route_glw',
        serviceId: 'svc_1',
        headsign: 'Glen Waverley',
        departure: TripDeparture(
          scheduledTime: richmondArrival.add(const Duration(minutes: 3)),
          platform: '8',
          lineCode: 'GLW',
          routeName: 'Glen Waverley Line',
          destination: 'Glen Waverley',
          type: TransitType.metro,
        ),
      ),
      // 5 min buffer (guaranteed)
      Trip(
        tripId: 'conn_pakenham',
        routeId: 'route_pkm',
        serviceId: 'svc_1',
        headsign: 'Pakenham',
        departure: TripDeparture(
          scheduledTime: richmondArrival.add(const Duration(minutes: 5)),
          platform: '5',
          lineCode: 'PKM',
          routeName: 'Pakenham Line',
          destination: 'Pakenham',
          type: TransitType.metro,
        ),
      ),
    ];
  }
}

class _ProbePtv extends PtvRealtimeService {
  int inFlight = 0;
  int maxInFlight = 0;
  final calls = <String>[];
  final bool throwSync;
  final bool empty;
  _ProbePtv({this.throwSync = false, this.empty = false});

  @override
  Future<List<Trip>> fetchDepartures(
    String stopId, {
    int routeType = 0,
    int maxResults = 20,
    Station? station,
  }) {
    if (throwSync) throw StateError('sync failure');
    calls.add(stopId);
    inFlight++;
    maxInFlight = math.max(maxInFlight, inFlight);
    return Future<List<Trip>>.delayed(const Duration(milliseconds: 20), () {
      inFlight--;
      if (empty) return <Trip>[];
      return [
        Trip(
          tripId: 'conn_$stopId',
          routeId: 'r',
          serviceId: 's',
          headsign: 'Dest $stopId',
          departure: TripDeparture(
            scheduledTime: DateTime.now().add(const Duration(minutes: 10)),
            platform: '1',
            lineCode: 'X',
            routeName: 'X Line',
            destination: 'Dest $stopId',
            type: TransitType.metro,
          ),
        ),
      ];
    });
  }
}

class _ProbeRepo implements IGtfsRepository {
  int inFlight = 0;
  int maxInFlight = 0;
  final calls = <String>[];

  @override
  Future<List<Trip>> getTripsForMode(
    PtvMode mode, {
    Station? station,
    bool forceRefresh = false,
    GtfsProgressCallback? onProgress,
  }) async {
    calls.add(station?.name ?? '');
    inFlight++;
    maxInFlight = math.max(maxInFlight, inFlight);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    inFlight--;
    return [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  group('ConnectionAdvisorService Tests', () {
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

    test('Computes connection feasibility at upcoming stops with correct levels', () async {
      final now = DateTime.now();
      final richmondArrival = now.add(const Duration(minutes: 3));
      final advisor = ConnectionAdvisorService(
        ptvService: _MockPtvServiceForAdvisor(now),
      );

      final activeTrip = Trip(
        tripId: 'active_frankston',
        routeId: 'route_fkn',
        serviceId: 'svc_01',
        headsign: 'Frankston',
        stops: [
          ServiceStop(
            station: stationFlinders,
            departureTime: now,
            platform: '1',
            stopSequence: 1,
          ),
          ServiceStop(
            station: stationRichmond,
            departureTime: richmondArrival,
            platform: '4',
            stopSequence: 2,
          ),
        ],
        departure: TripDeparture(
          scheduledTime: now,
          platform: '1',
          lineCode: 'FKN',
          routeName: 'Frankston Line',
          destination: 'Frankston',
          type: TransitType.metro,
        ),
      );

      final connectionsMap = await advisor.computeUpcomingConnections(
        activeTrip: activeTrip,
        currentOrNextStation: stationFlinders,
        allStations: [stationFlinders, stationRichmond],
      );

      expect(connectionsMap.containsKey('Richmond Station'), isTrue);
      final richmondConns = connectionsMap['Richmond Station']!;
      expect(richmondConns.length, equals(4));

      // 1 min -> tight
      final belgraveConn = richmondConns.firstWhere((c) => c.connectingTrip.headsign == 'Belgrave');
      expect(belgraveConn.feasibility, equals(TransferFeasibility.tight));
      expect(belgraveConn.platform, equals('9'));

      // 2 min -> possible
      final lilydaleConn = richmondConns.firstWhere((c) => c.connectingTrip.headsign == 'Lilydale');
      expect(lilydaleConn.feasibility, equals(TransferFeasibility.possible));

      // 3 min -> easy
      final glwConn = richmondConns.firstWhere((c) => c.connectingTrip.headsign == 'Glen Waverley');
      expect(glwConn.feasibility, equals(TransferFeasibility.easy));

      // 5 min -> guaranteed
      final pkmConn = richmondConns.firstWhere((c) => c.connectingTrip.headsign == 'Pakenham');
      expect(pkmConn.feasibility, equals(TransferFeasibility.guaranteed));
    });

    test('Attaches 2nd departure if 1st is within 4-minute mark and omits otherwise', () async {
      final now = DateTime.now();
      final richmondArrival = now.add(const Duration(minutes: 3));

      final customPtvService = _MockCustomAdvisorService(now, richmondArrival);
      final advisor = ConnectionAdvisorService(ptvService: customPtvService);

      final activeTrip = Trip(
        tripId: 'active_frankston',
        routeId: 'route_fkn',
        serviceId: 'svc_01',
        headsign: 'Frankston',
        stops: [
          ServiceStop(
            station: stationRichmond,
            departureTime: richmondArrival,
            platform: '4',
            stopSequence: 1,
          ),
        ],
        departure: TripDeparture(
          scheduledTime: now,
          platform: '1',
          lineCode: 'FKN',
          routeName: 'Frankston Line',
          destination: 'Frankston',
          type: TransitType.metro,
        ),
      );

      final connectionsMap = await advisor.computeUpcomingConnections(
        activeTrip: activeTrip,
        currentOrNextStation: stationRichmond,
        allStations: [stationRichmond],
      );

      final conns = connectionsMap['Richmond Station']!;
      
      // Pakenham has 1st departure at +2 min (inside 4m mark) and 2nd departure at +12 min
      final pkmConn = conns.firstWhere((c) => c.connectingTrip.destinationName == 'Pakenham');
      expect(pkmConn.hasSecondDeparture, isTrue);
      expect(pkmConn.subsequentConnectingTrip, isNotNull);
      expect(pkmConn.subsequentBufferMinutes, equals(12));

      // Belgrave has 1st departure at +6 min (> 4m mark) and 2nd departure at +16 min
      final belConn = conns.firstWhere((c) => c.connectingTrip.destinationName == 'Belgrave');
      expect(belConn.hasSecondDeparture, isFalse);
      expect(belConn.subsequentConnectingTrip, isNull);
    });

    test('Gracefully degrades to static GTFS timetable data when PTV API throws or drops network', () async {
      final now = DateTime.now();
      final richmondArrival = now.add(const Duration(minutes: 3));

      final throwingPtvService = _FailingPtvRealtimeService();
      final mockRepo = _MockGtfsRepoForAdvisor(richmondArrival);

      final advisor = ConnectionAdvisorService(
        ptvService: throwingPtvService,
        repository: mockRepo,
      );

      final activeTrip = Trip(
        tripId: 'active_frankston',
        routeId: 'route_fkn',
        serviceId: 'svc_01',
        headsign: 'Frankston',
        stops: [
          ServiceStop(
            station: stationRichmond,
            departureTime: richmondArrival,
            platform: '4',
            stopSequence: 1,
          ),
        ],
        departure: TripDeparture(
          scheduledTime: now,
          platform: '1',
          lineCode: 'FKN',
          routeName: 'Frankston Line',
          destination: 'Frankston',
          type: TransitType.metro,
        ),
      );

      final connectionsMap = await advisor.computeUpcomingConnections(
        activeTrip: activeTrip,
        currentOrNextStation: stationRichmond,
        allStations: [stationRichmond],
      );

      expect(connectionsMap.containsKey('Richmond Station'), isTrue);
      final conns = connectionsMap['Richmond Station']!;
      expect(conns.isNotEmpty, isTrue);

      final glenConn = conns.firstWhere((c) => c.connectingTrip.headsign == 'Glen Waverley');
      expect(glenConn.feasibility, equals(TransferFeasibility.easy));
      expect(glenConn.platform, equals('8'));
    });

    test('Gracefully degrades to static GTFS timetable data when PTV API returns empty (rate limited)', () async {
      final now = DateTime.now();
      final richmondArrival = now.add(const Duration(minutes: 3));

      final emptyPtvService = _EmptyPtvRealtimeService();
      final mockRepo = _MockGtfsRepoForAdvisor(richmondArrival);

      final advisor = ConnectionAdvisorService(
        ptvService: emptyPtvService,
        repository: mockRepo,
      );

      final activeTrip = Trip(
        tripId: 'active_frankston',
        routeId: 'route_fkn',
        serviceId: 'svc_01',
        headsign: 'Frankston',
        stops: [
          ServiceStop(
            station: stationRichmond,
            departureTime: richmondArrival,
            platform: '4',
            stopSequence: 1,
          ),
        ],
        departure: TripDeparture(
          scheduledTime: now,
          platform: '1',
          lineCode: 'FKN',
          routeName: 'Frankston Line',
          destination: 'Frankston',
          type: TransitType.metro,
        ),
      );

      final connectionsMap = await advisor.computeUpcomingConnections(
        activeTrip: activeTrip,
        currentOrNextStation: stationRichmond,
        allStations: [stationRichmond],
      );

      expect(connectionsMap.containsKey('Richmond Station'), isTrue);
      final conns = connectionsMap['Richmond Station']!;
      expect(conns.isNotEmpty, isTrue);
    });

    group('concurrent interchange fetching', () {
      Station st(String id, String name) => Station(
            id: id,
            stopId: id,
            name: name,
            code: id,
            lat: -37.8,
            lon: 144.9,
            suburb: '',
            zone: 'Zone 1',
            routes: const [],
          );
      final hubs = [
        st('1071', 'Flinders Street Station'),
        st('1162', 'Richmond Station'),
        st('1214', 'South Yarra Station'),
        st('1036', 'Caulfield Station'),
        st('1181', 'Southern Cross Station'),
        st('1155', 'Parliament Station'),
      ];

      Trip tripOver(List<Station> stations) {
        final now = DateTime.now();
        return Trip(
          tripId: 'active',
          routeId: 'route_active',
          serviceId: 'svc',
          headsign: 'Elsewhere',
          stops: [
            for (var i = 0; i < stations.length; i++)
              ServiceStop(
                station: stations[i],
                departureTime: now.add(Duration(minutes: i * 3)),
                platform: '1',
                stopSequence: i + 1,
              ),
          ],
          departure: TripDeparture(
            scheduledTime: now,
            platform: '1',
            lineCode: 'FKN',
            routeName: 'Frankston Line',
            destination: 'Elsewhere',
            type: TransitType.metro,
          ),
        );
      }

      test('fetches in parallel (bounded) and keeps stop order', () async {
        for (final h in hubs) {
          expect(ConnectionService.isDesignatedInterchange(h), isTrue, reason: h.name);
        }
        final ptv = _ProbePtv();
        final advisor = ConnectionAdvisorService(ptvService: ptv);
        final map = await advisor.computeUpcomingConnections(
          activeTrip: tripOver(hubs),
          currentOrNextStation: hubs.first,
          allStations: hubs,
        );

        expect(ptv.maxInFlight, greaterThan(1));
        expect(ptv.maxInFlight, lessThanOrEqualTo(4));
        expect(map.keys.toList(), hubs.map((h) => h.name).toList());
      });

      test('falls back to the static timetable sequentially, only for empty results', () async {
        final ptv = _ProbePtv(empty: true);
        final repo = _ProbeRepo();
        final advisor = ConnectionAdvisorService(ptvService: ptv, repository: repo);
        await advisor.computeUpcomingConnections(
          activeTrip: tripOver(hubs),
          currentOrNextStation: hubs.first,
          allStations: hubs,
        );
        expect(repo.calls, hubs.map((h) => h.name).toList());
        expect(repo.maxInFlight, 1);

        final liveRepo = _ProbeRepo();
        await ConnectionAdvisorService(ptvService: _ProbePtv(), repository: liveRepo)
            .computeUpcomingConnections(
          activeTrip: tripOver(hubs),
          currentOrNextStation: hubs.first,
          allStations: hubs,
        );
        expect(liveRepo.calls, isEmpty);
      });

      test('a fetch that throws synchronously still reaches the fallback', () async {
        final repo = _ProbeRepo();
        final advisor = ConnectionAdvisorService(
          ptvService: _ProbePtv(throwSync: true),
          repository: repo,
        );
        final map = await advisor.computeUpcomingConnections(
          activeTrip: tripOver(hubs.take(2).toList()),
          currentOrNextStation: hubs.first,
          allStations: hubs,
        );
        expect(repo.calls.length, 2);
        expect(map.length, 2);
      });
    });
  });
}

class _FailingPtvRealtimeService extends PtvRealtimeService {
  @override
  Future<List<Trip>> fetchDepartures(
    String stopId, {
    int routeType = 0,
    int maxResults = 30,
    Station? station,
  }) async {
    throw Exception('PTV Real-time API Connection Refused (Network Drop)');
  }
}

class _EmptyPtvRealtimeService extends PtvRealtimeService {
  @override
  Future<List<Trip>> fetchDepartures(
    String stopId, {
    int routeType = 0,
    int maxResults = 30,
    Station? station,
  }) async {
    return []; // Rate limited HTTP 429
  }
}

class _MockGtfsRepoForAdvisor implements IGtfsRepository {
  final DateTime richmondArrival;
  _MockGtfsRepoForAdvisor(this.richmondArrival);

  @override
  Future<void> clearCache() async {}
  @override
  Future<gtfs.DirectoryDataset?> getDatasetForMode(PtvMode mode, {bool forceRefresh = false, GtfsProgressCallback? onProgress}) async => null;
  @override
  Future<List<ServiceAlert>> getServiceAlerts() async => [];
  @override
  Future<List<Station>> getStopsForMode(PtvMode mode, {bool forceRefresh = false, GtfsProgressCallback? onProgress}) async => [];

  @override
  Future<List<Trip>> getTripsForMode(
    PtvMode mode, {
    Station? station,
    bool forceRefresh = false,
    GtfsProgressCallback? onProgress,
  }) async {
    return [
      Trip(
        tripId: 'static_glw',
        routeId: 'route_glw',
        serviceId: 'svc_1',
        headsign: 'Glen Waverley',
        departure: TripDeparture(
          scheduledTime: richmondArrival.add(const Duration(minutes: 3)),
          platform: '8',
          lineCode: 'GLW',
          routeName: 'Glen Waverley Line',
          destination: 'Glen Waverley',
          type: TransitType.metro,
        ),
      ),
    ];
  }
}

class _MockCustomAdvisorService extends PtvRealtimeService {
  final DateTime now;
  final DateTime richmondArrival;
  _MockCustomAdvisorService(this.now, this.richmondArrival);

  @override
  Future<List<Trip>> fetchDepartures(
    String stopId, {
    int routeType = 0,
    int maxResults = 30,
    Station? station,
  }) async {
    return [
      // Destination 1: Pakenham (1st at +2m [<=4m], 2nd at +12m)
      Trip(
        tripId: 'pkm_1',
        routeId: 'route_pkm',
        serviceId: 'svc_1',
        headsign: 'Pakenham',
        departure: TripDeparture(
          scheduledTime: richmondArrival.add(const Duration(minutes: 2)),
          platform: '5',
          lineCode: 'PKM',
          routeName: 'Pakenham',
          destination: 'Pakenham',
          type: TransitType.metro,
        ),
      ),
      Trip(
        tripId: 'pkm_2',
        routeId: 'route_pkm',
        serviceId: 'svc_1',
        headsign: 'Pakenham',
        departure: TripDeparture(
          scheduledTime: richmondArrival.add(const Duration(minutes: 12)),
          platform: '5',
          lineCode: 'PKM',
          routeName: 'Pakenham',
          destination: 'Pakenham',
          type: TransitType.metro,
        ),
      ),
      // Destination 2: Belgrave (1st at +6m [>4m], 2nd at +16m)
      Trip(
        tripId: 'bel_1',
        routeId: 'route_bel',
        serviceId: 'svc_1',
        headsign: 'Belgrave',
        departure: TripDeparture(
          scheduledTime: richmondArrival.add(const Duration(minutes: 6)),
          platform: '9',
          lineCode: 'BEL',
          routeName: 'Belgrave',
          destination: 'Belgrave',
          type: TransitType.metro,
        ),
      ),
      Trip(
        tripId: 'bel_2',
        routeId: 'route_bel',
        serviceId: 'svc_1',
        headsign: 'Belgrave',
        departure: TripDeparture(
          scheduledTime: richmondArrival.add(const Duration(minutes: 16)),
          platform: '9',
          lineCode: 'BEL',
          routeName: 'Belgrave',
          destination: 'Belgrave',
          type: TransitType.metro,
        ),
      ),
    ];
  }
}
