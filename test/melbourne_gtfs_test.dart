import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:transit_app/src/data/datasources/gtfs_index_engine.dart';
import 'package:transit_app/src/domain/entities/station.dart';
import 'package:transit_app/src/domain/entities/transit_route.dart';
import 'package:transit_app/src/services/gtfs_parser.dart';
import 'package:transit_app/src/services/melbourne_gtfs_service.dart';

class _MockHttpClient extends http.BaseClient {
  final Future<http.StreamedResponse> Function(http.BaseRequest request) _handler;
  _MockHttpClient(this._handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => _handler(request);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Melbourne GTFS Infrastructure Tests', () {
    test('Normalizes station names cleanly without raw railway station noise', () {
      expect(
        GtfsIndexEngine.normalizeStationName('Flinders Street Railway Station (Melbourne)'),
        equals('Flinders Street Station'),
      );
      expect(
        GtfsIndexEngine.normalizeStationName('Richmond Railway Station/Platform 1'),
        equals('Richmond Station'),
      );
      expect(
        GtfsIndexEngine.normalizeStationName('Southern Cross Railway Station'),
        equals('Southern Cross Station'),
      );
    });

    test('Filters out replacement bus stops from station index', () {
      expect(GtfsIndexEngine.isReplacementBusStop('Bus Replacement Stop'), isTrue);
      expect(GtfsIndexEngine.isReplacementBusStop('Temp Bus Stop'), isTrue);
      expect(GtfsIndexEngine.isReplacementBusStop('Flinders Street Station'), isFalse);
      expect(GtfsIndexEngine.isReplacementBusStop('Southern Cross Station'), isFalse);
    });

    test('Resolves PTV GTFS route types to domain modes correctly', () {
      expect(TransitRoute.fromGtfsRouteType(0), equals(TransitType.tram));
      expect(TransitRoute.fromGtfsRouteType(1), equals(TransitType.metro));
      expect(
        TransitRoute.fromGtfsRouteType(2),
        equals(TransitType.regionalTrain),
      );
      expect(TransitRoute.fromGtfsRouteType(3), equals(TransitType.bus));
      expect(TransitRoute.fromGtfsRouteType(4), equals(TransitType.ferry));
    });

    test('Provides official PTV brand colors for modes', () {
      expect(
        TransitRoute.ptvBrandColor(TransitType.metro),
        equals(PtvColors.metroTrain),
      );
      expect(
        TransitRoute.ptvBrandColor(TransitType.tram),
        equals(PtvColors.yarraTram),
      );
      expect(
        TransitRoute.ptvBrandColor(TransitType.regionalTrain),
        equals(PtvColors.vlinePurple),
      );
    });

    test('Parses stops.txt CSV format into Station objects with PTV numeric stopId', () {
      const sampleCsv = '''stop_id,stop_name,stop_lat,stop_lon,stop_url,location_type,parent_station,wheelchair_boarding,level_id,platform_code
"11212","Flinders Street Station","-37.81809481","144.96626579","https://transport.vic.gov.au/stop/1071/?utm_source=open_data_click_stop","","vic:rail:FSS","1","Level 0","1"
"11213","Flinders Street Station","-37.81814377","144.96649165","https://transport.vic.gov.au/stop/1071/?utm_source=open_data_click_stop","","vic:rail:FSS","1","Level 0","2"
"11220","Frankston Station","-38.14268180","145.12604465","https://transport.vic.gov.au/stop/1073/?utm_source=open_data_click_stop","","vic:rail:FKN","1","Level 1","1"
"10920","Flagstaff Station","-37.81205297","144.95562907","https://transport.vic.gov.au/stop/1068/?utm_source=open_data_click_stop","","vic:rail:FGS","1","Level -3","1"
''';

      final stations = MelbourneGtfsService.parseStopsTxt(sampleCsv);
      expect(stations.length, equals(3));

      final flinders = stations.firstWhere((s) => s.code == 'FSS');
      expect(flinders.name, equals('Flinders Street Station'));
      expect(flinders.stopId, equals('1071'));
      expect(flinders.isCityLoop, isTrue);

      final frankston = stations.firstWhere((s) => s.code == 'FKN');
      expect(frankston.name, equals('Frankston Station'));
      expect(frankston.stopId, equals('1073'));
      expect(frankston.isCityLoop, isFalse);

      final flagstaff = stations.firstWhere((s) => s.code == 'FGS');
      expect(flagstaff.stopId, equals('1068'));
      expect(flagstaff.isCityLoop, isTrue);
    });

    test('Downloads stops.txt with streaming progress callback, saves ETag, and parses stations', () async {
      const sampleCsv = '''stop_id,stop_name,stop_lat,stop_lon,stop_url,location_type,parent_station,wheelchair_boarding,level_id,platform_code
"11212","Flinders Street Station","-37.81809481","144.96626579","https://transport.vic.gov.au/stop/1071/?utm_source=open_data_click_stop","","vic:rail:FSS","1","Level 0","1"
"11220","Frankston Station","-38.14268180","145.12604465","https://transport.vic.gov.au/stop/1073/?utm_source=open_data_click_stop","","vic:rail:FKN","1","Level 1","1"
''';

      final progressValues = <double>[];
      final statusMessages = <String>[];

      final mockClient = _MockHttpClient((request) async {
        return http.StreamedResponse(
          Stream.value(utf8.encode(sampleCsv)),
          200,
          headers: {'etag': '"test-etag-abc"'},
          contentLength: utf8.encode(sampleCsv).length,
        );
      });

      final tempDir = Directory.systemTemp.createTempSync('stops_test_');
      final tempFile = File('${tempDir.path}/stops.txt');
      final etagFile = File('${tempDir.path}/stops.etag');

      final stations = await MelbourneGtfsService.loadOrDownloadStops(
        localFile: tempFile,
        client: mockClient,
        forceRefresh: true,
        onProgress: (p, s) {
          progressValues.add(p);
          statusMessages.add(s);
        },
      );

      expect(stations.length, equals(2));
      expect(progressValues.isNotEmpty, isTrue);
      expect(statusMessages.any((m) => m.contains('Stations Ready')), isTrue);
      expect(await tempFile.exists(), isTrue);
      expect(await etagFile.exists(), isTrue);
      expect(await etagFile.readAsString(), equals('"test-etag-abc"'));
    });

    test('Checks If-None-Match ETag and returns cached stations on 304 Not Modified', () async {
      const sampleCsv = '''stop_id,stop_name,stop_lat,stop_lon,stop_url,location_type,parent_station,wheelchair_boarding,level_id,platform_code
"11212","Flinders Street Station","-37.81809481","144.96626579","https://transport.vic.gov.au/stop/1071/?utm_source=open_data_click_stop","","vic:rail:FSS","1","Level 0","1"
"11220","Frankston Station","-38.14268180","145.12604465","https://transport.vic.gov.au/stop/1073/?utm_source=open_data_click_stop","","vic:rail:FKN","1","Level 1","1"
''';

      final tempDir = Directory.systemTemp.createTempSync('stops_304_');
      final tempFile = File('${tempDir.path}/stops.txt');
      final etagFile = File('${tempDir.path}/stops.etag');
      await tempFile.writeAsString(sampleCsv);
      await etagFile.writeAsString('"cached-etag-123"');

      String? sentIfNoneMatch;
      final mockClient = _MockHttpClient((request) async {
        sentIfNoneMatch = request.headers['If-None-Match'];
        return http.StreamedResponse(
          const Stream.empty(),
          304,
        );
      });

      final stations = await MelbourneGtfsService.loadOrDownloadStops(
        localFile: tempFile,
        client: mockClient,
      );

      expect(sentIfNoneMatch, equals('"cached-etag-123"'));
      expect(stations.length, equals(2));
      expect(stations.any((s) => s.name == 'Flinders Street Station'), isTrue);
    });

    test('Throws GtfsNetworkException when network fails and no local cache exists', () async {
      final tempDir = Directory.systemTemp.createTempSync('stops_offline_clean_');
      final tempFile = File('${tempDir.path}/stops.txt');

      final mockClient = _MockHttpClient((request) async {
        throw const SocketException('Connection failed');
      });

      expect(
        () => MelbourneGtfsService.loadOrDownloadStops(
          localFile: tempFile,
          client: mockClient,
        ),
        throwsA(isA<GtfsNetworkException>()),
      );
    });

    const timeoutCsv = '''stop_id,stop_name,stop_lat,stop_lon,stop_url,location_type,parent_station,wheelchair_boarding,level_id,platform_code
"11212","Flinders Street Station","-37.81809481","144.96626579","https://transport.vic.gov.au/stop/1071/?utm_source=open_data_click_stop","","vic:rail:FSS","1","Level 0","1"
''';

    test('Stalled response headers fall back to the cached stations', () async {
      final tempDir = Directory.systemTemp.createTempSync('stops_stall_cached_');
      final tempFile = File('${tempDir.path}/stops.txt');
      await tempFile.writeAsString(timeoutCsv);
      final mockClient = _MockHttpClient((request) => Completer<http.StreamedResponse>().future);

      final stations = await MelbourneGtfsService.loadOrDownloadStops(
        localFile: tempFile,
        client: mockClient,
        responseTimeout: const Duration(milliseconds: 50),
      );
      expect(stations.any((s) => s.name == 'Flinders Street Station'), isTrue);
    });

    test('Stalled response headers without a cache throw GtfsNetworkException', () async {
      final tempDir = Directory.systemTemp.createTempSync('stops_stall_clean_');
      final tempFile = File('${tempDir.path}/stops.txt');
      final mockClient = _MockHttpClient((request) => Completer<http.StreamedResponse>().future);

      await expectLater(
        MelbourneGtfsService.loadOrDownloadStops(
          localFile: tempFile,
          client: mockClient,
          responseTimeout: const Duration(milliseconds: 50),
        ),
        throwsA(isA<GtfsNetworkException>()),
      );
    });

    test('Stalled body stream falls back to cache and leaves no tmp file', () async {
      final tempDir = Directory.systemTemp.createTempSync('stops_stall_body_');
      final tempFile = File('${tempDir.path}/stops.txt');
      await tempFile.writeAsString(timeoutCsv);
      final controller = StreamController<List<int>>();
      addTearDown(controller.close);
      controller.add(utf8.encode('stop_id,stop_name\n'));
      final mockClient = _MockHttpClient(
        (request) async => http.StreamedResponse(controller.stream, 200),
      );

      final stations = await MelbourneGtfsService.loadOrDownloadStops(
        localFile: tempFile,
        client: mockClient,
        forceRefresh: true,
        idleTimeout: const Duration(milliseconds: 50),
      );
      expect(stations.any((s) => s.name == 'Flinders Street Station'), isTrue);
      expect(File('${tempFile.path}.tmp').existsSync(), isFalse);
    });

    test('Falls back to local cache when network fails but cache exists', () async {
      const sampleCsv = '''stop_id,stop_name,stop_lat,stop_lon,stop_url,location_type,parent_station,wheelchair_boarding,level_id,platform_code
"11212","Flinders Street Station","-37.81809481","144.96626579","https://transport.vic.gov.au/stop/1071/?utm_source=open_data_click_stop","","vic:rail:FSS","1","Level 0","1"
''';
      final tempDir = Directory.systemTemp.createTempSync('stops_offline_cached_');
      final tempFile = File('${tempDir.path}/stops.txt');
      await tempFile.writeAsString(sampleCsv);

      final mockClient = _MockHttpClient((request) async {
        throw const SocketException('Connection refused');
      });

      final stations = await MelbourneGtfsService.loadOrDownloadStops(
        localFile: tempFile,
        client: mockClient,
      );

      expect(stations.length, equals(1));
      expect(stations.first.name, equals('Flinders Street Station'));
    });

    test('stopsUrlForMode resolves correct URLs matching repo structure', () {
      expect(
        MelbourneGtfsService.stopsUrlForMode(PtvMode.metroTrain),
        equals('https://raw.githubusercontent.com/huh4k/h4k-lib/main/metro/stops.txt'),
      );
      expect(
        MelbourneGtfsService.stopsUrlForMode(PtvMode.metroTram),
        equals('https://raw.githubusercontent.com/huh4k/h4k-lib/main/tram/stops.txt'),
      );
    });

    test('Downloads and parses tram stops with mode metroTram preserving # stop numbers', () async {
      const tramCsv = '''stop_id,stop_name,stop_lat,stop_lon,stop_url,location_type,parent_station,wheelchair_boarding,level_id
"10311","Glenferrie Rd/Wattletree Rd #45","-37.86245520","145.02850849","https://transport.vic.gov.au/stop/2587/?utm_source=open_data_click_stop","","","0","Level 0"
"17850","Flinders Street Railway Station/Elizabeth St #1","-37.81771743","144.96476527","https://transport.vic.gov.au/stop/2722/?utm_source=open_data_click_stop","","","0","Level 0"
''';

      final mockClient = _MockHttpClient((request) async {
        return http.StreamedResponse(
          Stream.value(utf8.encode(tramCsv)),
          200,
          headers: {'etag': '"tram-etag-456"'},
          contentLength: utf8.encode(tramCsv).length,
        );
      });

      final tempDir = Directory.systemTemp.createTempSync('tram_stops_test_');
      final tempFile = File('${tempDir.path}/stops.txt');

      final stops = await MelbourneGtfsService.loadOrDownloadStops(
        mode: PtvMode.metroTram,
        localFile: tempFile,
        client: mockClient,
      );

      expect(stops.length, equals(2));
      final glenferrie = stops.firstWhere((s) => s.name.contains('Glenferrie'));
      expect(glenferrie.code, equals('45'));
      expect(glenferrie.stopId, equals('2587'));
      expect(glenferrie.name, equals('Glenferrie Rd/Wattletree Rd #45'));

      final flindersTram = stops.firstWhere((s) => s.stopId == '2722');
      expect(flindersTram.code, equals('1'));
    });

    test(
      'Parses GTFS data into Trip objects from routes, trips, and stop_times',
      () async {
        final tempDir = Directory.systemTemp.createTempSync('gtfs_test_');
        final now = DateTime.now();
        final firstDeparture = _gtfsTime(now.hour * 60 + now.minute + 5);
        final secondDeparture = _gtfsTime(now.hour * 60 + now.minute + 12);

        File('${tempDir.path}/routes.txt').writeAsStringSync(
          'route_id,agency_id,route_short_name,route_long_name,route_type\n'
          '2-BEL-F-mjp-1,2,BEL,Belgrave Line,1\n'
          '3-096-mjp-1,3,96,East Brunswick to St Kilda,0\n',
        );

        File('${tempDir.path}/trips.txt').writeAsStringSync(
          'route_id,service_id,trip_id,trip_headsign,direction_id\n'
          '2-BEL-F-mjp-1,weekday,trip_bel_1,Belgrave,0\n'
          '3-096-mjp-1,weekday,trip_96_1,St Kilda Beach,1\n',
        );

        File('${tempDir.path}/stop_times.txt').writeAsStringSync(
          'trip_id,arrival_time,departure_time,stop_id,stop_sequence\n'
          'trip_bel_1,$firstDeparture,$firstDeparture,19842,1\n'
          'trip_96_1,$secondDeparture,$secondDeparture,19842,1\n',
        );

        final trips = await PtvGtfsRepository.parseTripsFromDirectory(tempDir);

        expect(trips.length, equals(2));

        final headsigns = trips.map((t) => t.headsign).toSet();
        expect(headsigns, contains('Belgrave'));
        expect(headsigns, contains('St Kilda Beach'));

        final belgrave = trips.firstWhere((t) => t.headsign == 'Belgrave');
        expect(belgrave.routeId, equals('2-BEL-F-mjp-1'));

        final stKilda = trips.firstWhere((t) => t.headsign == 'St Kilda Beach');
        expect(stKilda.routeId, equals('3-096-mjp-1'));

        tempDir.deleteSync(recursive: true);
      },
    );

    test(
      'Generates departures successfully across at least 30 distinct Melbourne stations',
      () async {
        final tempDir = Directory.systemTemp.createTempSync('gtfs_30_stations_');
        addTearDown(() => tempDir.delete(recursive: true));

        final now = DateTime.now();
        final date = _gtfsDate(now);
        final depTime = _gtfsTime(now.hour * 60 + now.minute + 15);

        final stations = const [
          'Flinders Street', 'Southern Cross', 'Melbourne Central', 'Parliament', 'Flagstaff',
          'Richmond', 'South Yarra', 'Caulfield', 'Footscray', 'Box Hill',
          'Dandenong', 'Frankston', 'Belgrave', 'Lilydale', 'Glen Waverley',
          'Ringwood', 'Camberwell', 'Essendon', 'Broadmeadows', 'Watergardens',
          'Sunbury', 'Werribee', 'Williamstown', 'Sandringham', 'Moorabbin',
          'Cheltenham', 'Mentone', 'Mordialloc', 'Geelong', 'Ballarat',
          'Bendigo', 'Traralgon',
        ];

        expect(stations.length, greaterThanOrEqualTo(30));

        final stopsBuffer = StringBuffer('stop_id,stop_name,stop_lat,stop_lon\n');
        final tripsBuffer = StringBuffer('route_id,service_id,trip_id,trip_headsign\n');
        final stopTimesBuffer = StringBuffer('trip_id,arrival_time,departure_time,stop_id,stop_sequence\n');

        File('${tempDir.path}/routes.txt').writeAsStringSync(
          'route_id,route_short_name,route_long_name,route_type\n'
          'route_metro,METRO,Melbourne Metro Line,1\n',
        );

        for (int i = 0; i < stations.length; i++) {
          final stopId = '${1000 + i}';
          final name = stations[i];
          stopsBuffer.writeln('$stopId,"$name Station",-37.8,144.9');

          final tripId = 'trip_$stopId';
          tripsBuffer.writeln('route_metro,weekday,$tripId,$name');
          stopTimesBuffer.writeln('$tripId,$depTime,$depTime,$stopId,1');
        }

        File('${tempDir.path}/stops.txt').writeAsStringSync(stopsBuffer.toString());
        File('${tempDir.path}/trips.txt').writeAsStringSync(tripsBuffer.toString());
        File('${tempDir.path}/stop_times.txt').writeAsStringSync(stopTimesBuffer.toString());
        File('${tempDir.path}/calendar.txt').writeAsStringSync(
          'service_id,monday,tuesday,wednesday,thursday,friday,saturday,sunday,start_date,end_date\n'
          'weekday,1,1,1,1,1,1,1,$date,$date\n',
        );

        final parsedStops = await PtvGtfsRepository.parseStopsFromDirectory(tempDir);
        expect(parsedStops.length, equals(stations.length));

        for (final station in parsedStops) {
          final stationTrips = await PtvGtfsRepository.parseTripsFromDirectory(
            tempDir,
            targetStation: station,
          );
          expect(
            stationTrips.isNotEmpty,
            isTrue,
            reason: 'Departures should show up for ${station.name}',
          );
        }
      },
    );

    test('filters departures to services active today', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'gtfs_calendar_test_',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final now = DateTime.now();
      final activeDays = List.filled(7, '0')..[now.weekday - 1] = '1';
      final date = _gtfsDate(now);
      final departure = _gtfsTime(now.hour * 60 + now.minute + 8);

      File('${tempDir.path}/calendar.txt').writeAsStringSync(
        'service_id,monday,tuesday,wednesday,thursday,friday,saturday,sunday,start_date,end_date\n'
        'active,${activeDays.join(',')},$date,$date\n'
        'inactive,0,0,0,0,0,0,0,$date,$date\n',
      );
      File('${tempDir.path}/routes.txt').writeAsStringSync(
        'route_id,route_short_name,route_long_name,route_type\n'
        'route_1,T1,Test line,1\n',
      );
      File('${tempDir.path}/trips.txt').writeAsStringSync(
        'route_id,service_id,trip_id,trip_headsign\n'
        'route_1,active,active_trip,Active destination\n'
        'route_1,inactive,inactive_trip,Inactive destination\n',
      );
      File('${tempDir.path}/stop_times.txt').writeAsStringSync(
        'trip_id,arrival_time,departure_time,stop_id\n'
        'active_trip,$departure,$departure,19842\n'
        'inactive_trip,$departure,$departure,19842\n',
      );

      final trips = await PtvGtfsRepository.parseTripsFromDirectory(tempDir);

      expect(trips.map((trip) => trip.tripId), equals(['active_trip']));
      expect(trips.single.departure?.status, equals(ServiceStatus.scheduled));
    });

    test('Encodes and decodes GtfsIndexCache binary structures accurately', () {
      const station1 = Station(
        id: '1071',
        stopId: '1071',
        name: 'Flinders Street Station',
        code: 'FSS',
        lat: -37.8183,
        lon: 144.9671,
        suburb: 'Melbourne CBD',
        zone: 'Zone 1',
        isCityLoop: true,
        routes: [],
      );
      const station2 = Station(
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
      );

      final originalCache = GtfsIndexCache(
        stops: {
          '1071': station1,
          '1071:1': station1,
          '1162': station2,
        },
        parentStopIdMap: {
          '1071:1': '1071',
          '1162:1': '1162',
        },
      );

      final binaryBytes = GtfsIndexEngine.encodeBinary(originalCache);
      expect(binaryBytes.isNotEmpty, isTrue);

      final decodedCache = GtfsIndexEngine.decodeBinary(binaryBytes);
      expect(decodedCache, isNotNull);
      expect(decodedCache!.stops.length, equals(3));
      expect(decodedCache.parentStopIdMap.length, equals(2));

      final decodedFss = decodedCache.stops['1071']!;
      expect(decodedFss.id, equals('1071'));
      expect(decodedFss.name, equals('Flinders Street Station'));
      expect(decodedFss.code, equals('FSS'));
      expect(decodedFss.lat, closeTo(-37.8183, 0.0001));
      expect(decodedFss.lon, closeTo(144.9671, 0.0001));
      expect(decodedFss.isCityLoop, isTrue);

      final decodedRmd = decodedCache.stops['1162']!;
      expect(decodedRmd.id, equals('1162'));
      expect(decodedRmd.name, equals('Richmond Station'));
      expect(decodedRmd.isCityLoop, isFalse);

      expect(decodedCache.parentStopIdMap['1071:1'], equals('1071'));
    });

    test('getOrCreateIndex creates stops_index.bin and loads from binary on cold start', () async {
      final tempDir = Directory.systemTemp.createTempSync('gtfs_bin_cache_');
      addTearDown(() => tempDir.delete(recursive: true));

      File('${tempDir.path}/stops.txt').writeAsStringSync(
        'stop_id,stop_name,stop_lat,stop_lon,parent_station,zone_id\n'
        '1071,"Flinders Street Station",-37.8183,144.9671,vic:rail:FSS,1\n'
        '1162,"Richmond Station",-37.8240,144.9896,vic:rail:RMD,1\n',
      );

      // First run: parses stops.txt and writes stops_index.bin
      GtfsIndexEngine.clearCache();
      final cache1 = await GtfsIndexEngine.getOrCreateIndex(tempDir);
      expect(cache1.stops.isNotEmpty, isTrue);

      final binFile = File('${tempDir.path}/${GtfsIndexEngine.binaryIndexFilename}');
      expect(await binFile.exists(), isTrue);

      // Second run with in-memory cache cleared: loads directly from stops_index.bin
      GtfsIndexEngine.clearCache();
      // Remove or corrupt text file to verify binary file is loaded
      File('${tempDir.path}/stops.txt').deleteSync();

      final cache2 = await GtfsIndexEngine.getOrCreateIndex(tempDir);
      expect(cache2.stops.length, equals(cache1.stops.length));
      expect(cache2.stops.containsKey('1071'), isTrue);
    });
  });
}

String _gtfsTime(int totalMinutes) {
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:00';
}

String _gtfsDate(DateTime date) =>
    '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
