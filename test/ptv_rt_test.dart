import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
