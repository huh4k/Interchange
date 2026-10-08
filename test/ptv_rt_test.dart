import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http/testing.dart';
import 'package:transit_app/src/core/http_client_factory.dart';
import 'package:transit_app/src/domain/entities/station.dart';
import 'package:transit_app/src/services/ptv_rt_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    EnvService.setCredentials(
      userId: 'test_dev_id',
      apiKey: 'test_api_key_hash',
    );
  });

  group('PTV Realtime & Env Tests', () {
    test('EnvService manages runtime credentials', () {
      expect(EnvService.userId, equals('test_dev_id'));
      expect(EnvService.apiKey, equals('test_api_key_hash'));
      expect(EnvService.isConfigured, isTrue);
    });

    test('PtvRealtimeService generates HMAC signed URLs for PTV API v3', () {
      final signedUrl = PtvRealtimeService.generateSignedUrl('/v3/disruptions');

      expect(signedUrl, contains('https://timetableapi.ptv.vic.gov.au/v3/disruptions'));
      expect(signedUrl, contains('devid=test_dev_id'));
      expect(signedUrl, contains('signature='));
    });

    test('fetchLiveDisruptions decodes a body over 128 KB', () async {
      final items = List.generate(
        600,
        (i) => {
          'disruption_id': i,
          'title': 'Alert $i',
          'description': 'x' * 300,
          'routes': [
            {'route_short_name': 'X'},
          ],
        },
      );
      final body = jsonEncode({
        'disruptions': {'metro_train': items},
      });
      expect(body.length, greaterThan(128 * 1024));
      final service = PtvRealtimeService(
        client: MockClient((_) async => http.Response(body, 200)),
      );
      final alerts = await service.fetchLiveDisruptions();
      expect(alerts.length, 600);
    });

    test('Stalled responses time out and return empty results', () async {
      final service = PtvRealtimeService(
        client: MockClient((_) => Completer<http.Response>().future),
        responseTimeout: const Duration(milliseconds: 50),
        idleTimeout: const Duration(milliseconds: 50),
      );
      expect(await service.fetchDepartures('1071').timeout(const Duration(seconds: 1)), isEmpty);
      expect(await service.fetchLiveDisruptions().timeout(const Duration(seconds: 1)), isEmpty);
      expect(await service.fetchPattern('1', 0).timeout(const Duration(seconds: 1)), isNull);
    });

    test('Stalled body streams time out and return empty results', () async {
      final controllers = <StreamController<List<int>>>[];
      addTearDown(() {
        for (final c in controllers) {
          c.close();
        }
      });
      final service = PtvRealtimeService(
        client: MockClient.streaming((_, _) async {
          final c = StreamController<List<int>>();
          controllers.add(c);
          return http.StreamedResponse(c.stream, 200);
        }),
        responseTimeout: const Duration(milliseconds: 50),
        idleTimeout: const Duration(milliseconds: 50),
      );
      expect(await service.fetchDepartures('1071').timeout(const Duration(seconds: 1)), isEmpty);
      expect(await service.fetchPattern('1', 0).timeout(const Duration(seconds: 1)), isNull);
    });

    test('fetchPattern returns decoded JSON on success', () async {
      final service = PtvRealtimeService(
        client: MockClient((_) async => http.Response('{"departures":[],"stops":{}}', 200)),
      );
      expect(await service.fetchPattern('1', 0), isNotNull);
    });

    test('fetchLiveDisruptions shares one request between concurrent callers', () async {
      final gate = Completer<void>();
      var requests = 0;
      final service = PtvRealtimeService(
        client: MockClient((_) async {
          requests++;
          await gate.future;
          return http.Response(
            jsonEncode({
              'disruptions': {
                'metro_train': [
                  {'disruption_id': 1, 'title': 'A', 'description': 'd', 'routes': []},
                ],
              },
            }),
            200,
          );
        }),
      );
      final a = service.fetchLiveDisruptions();
      final b = service.fetchLiveDisruptions();
      gate.complete();
      expect((await a).length, 1);
      expect((await b).length, 1);
      expect(requests, 1);
      // A follow-up call inside the TTL is served from cache.
      await service.fetchLiveDisruptions();
      expect(requests, 1);
    });

    test('fetchLiveDisruptions keeps only train, tram, V/Line and general buckets', () async {
      Map<String, dynamic> item(int id) =>
          {'disruption_id': id, 'title': 'T$id', 'description': 'd', 'routes': []};
      Uri? requested;
      final service = PtvRealtimeService(
        client: MockClient((req) async {
          requested = req.url;
          return http.Response(
              jsonEncode({
                'disruptions': {
                  'metro_train': [item(1)],
                  'metro_tram': [item(2)],
                  'general': [item(3)],
                  'regional_train': [item(4)],
                  'metro_bus': [item(5)],
                  'regional_coach': [item(6)],
                },
              }),
              200,
            );
        }),
      );
      final alerts = await service.fetchLiveDisruptions();
      expect(requested!.queryParametersAll['route_types'], ['0', '1', '3']);
      expect(requested!.queryParameters['signature'], isNotEmpty);
      expect(alerts.map((a) => a.id).toSet(), {'1', '2', '3', '4'});
    });

    test('a failed first attempt is retried once; timeouts are not retried', () async {
      var calls = 0;
      final flaky = PtvRealtimeService(
        client: MockClient((_) async {
          calls++;
          if (calls == 1) throw http.ClientException('connection closed');
          return http.Response('{"departures":[],"stops":{}}', 200);
        }),
      );
      expect(await flaky.fetchPattern('1', 0), isNotNull);
      expect(calls, 2);

      var stalled = 0;
      final slow = PtvRealtimeService(
        client: MockClient((_) {
          stalled++;
          return Completer<http.Response>().future;
        }),
        responseTimeout: const Duration(milliseconds: 30),
      );
      expect(await slow.fetchPattern('1', 0), isNull);
      expect(stalled, 1);
    });

    test('the app HTTP client is an IOClient on the VM', () {
      expect(createAppHttpClient(), isA<IOClient>());
    });

    test('pattern requests ask for expand=Stop and yield ordered stops', () async {
      Uri? url;
      final now = DateTime.now().toUtc();
      final service = PtvRealtimeService(
        client: MockClient((req) async {
          url = req.url;
          return http.Response(
            jsonEncode({
              'departures': [
                {
                  'stop_id': 2,
                  'departure_sequence': 2,
                  'scheduled_departure_utc': now.add(const Duration(minutes: 10)).toIso8601String(),
                  'estimated_departure_utc': now.add(const Duration(minutes: 12)).toIso8601String(),
                  'platform_number': '4',
                },
                {
                  'stop_id': 1,
                  'departure_sequence': 1,
                  'scheduled_departure_utc': now.add(const Duration(minutes: 5)).toIso8601String(),
                  'platform_number': '1',
                },
              ],
              'stops': {
                '1': {'stop_id': 1, 'stop_name': 'Alpha Railway Station', 'route_type': 0},
                '2': {'stop_id': 2, 'stop_name': 'Bravo Railway Station', 'route_type': 0},
              },
            }),
            200,
          );
        }),
      );
      final stops = await service.fetchPatternStops('99');
      expect(url!.queryParameters['expand'], 'Stop');
      expect(stops.map((s) => s.stopSequence), [1, 2]);
      expect(stops.map((s) => s.platform), ['1', '4']);
      expect(stops[1].departureTime!.isAfter(stops[0].departureTime!), isTrue);
    });

    test('PtvRealtimeService resolves stop ID accurately for Frankston and hubs', () async {
      final ptvService = PtvRealtimeService();
      const frankston = Station(
        id: 'st_frankston',
        stopId: '1073',
        name: 'Frankston Station',
        code: 'FKN',
        lat: -38.1432,
        lon: 145.1262,
        suburb: 'Frankston',
        zone: 'Zone 2',
        routes: [],
      );

      final resolvedId = await ptvService.resolveStopIdForStation(frankston);
      expect(resolvedId, equals('1073'));
    });
  });
}
