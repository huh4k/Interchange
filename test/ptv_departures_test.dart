import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:transit_app/src/services/ptv_rt_service.dart';

String _utc(DateTime t) => t.toUtc().toIso8601String();

Map<String, dynamic> _dep(String runRef, {DateTime? sched, DateTime? est, String routeId = '1'}) => {
      'run_ref': runRef,
      'route_id': routeId,
      'direction_id': 1,
      'platform_number': '3',
      if (sched != null) 'scheduled_departure_utc': _utc(sched),
      if (est != null) 'estimated_departure_utc': _utc(est),
    };

Map<String, dynamic> _runs(Iterable<String> refs) => {
      for (final r in refs) r: {'run_ref': r, 'destination_name': 'Dest $r', 'status': 'scheduled'},
    };

final _routes = {
  '1': {'route_id': 1, 'route_name': 'Belgrave', 'route_type': 0, 'route_number': ''},
};

void main() {
  setUpAll(() {
    EnvService.setCredentials(userId: 'test_dev_id', apiKey: 'test_api_key_hash');
  });

  test('fetchDepartures keeps in-window departures, sorted, and drops the rest', () async {
    final now = DateTime.now();
    final deps = [
      _dep('late', sched: now.add(const Duration(minutes: 40))),
      _dep('past', sched: now.subtract(const Duration(minutes: 30))),
      _dep('soon', sched: now.add(const Duration(minutes: 5))),
      _dep('estimated', sched: now.subtract(const Duration(minutes: 10)), est: now.add(const Duration(minutes: 8))),
      _dep('far', sched: now.add(const Duration(hours: 3))),
      _dep('est-only', est: now.add(const Duration(minutes: 12))),
      _dep('no-time'),
      _dep('missing-run', sched: now.add(const Duration(minutes: 6))),
      _dep('missing-route', sched: now.add(const Duration(minutes: 7)), routeId: '99'),
    ];
    final body = jsonEncode({
      'departures': deps,
      'runs': _runs(['late', 'past', 'soon', 'estimated', 'far', 'est-only', 'no-time', 'missing-route']),
      'routes': _routes,
    });

    Uri? requested;
    final service = PtvRealtimeService(
      client: MockClient((req) async {
        requested = req.url;
        return http.Response(body, 200);
      }),
    );
    final trips = await service.fetchDepartures('1071', maxResults: 20);

    expect(requested!.queryParameters['max_results'], '20');
    final ids = trips.map((t) => t.tripId).toList();
    // 'no-time' falls back to "now" so it sorts first; the others by time.
    expect(ids, ['no-time', 'soon', 'estimated', 'est-only', 'late']);
  });

  test('fetchDepartures handles a response over the isolate threshold', () async {
    final now = DateTime.now();
    final refs = List.generate(700, (i) => 'r$i');
    final deps = [
      for (var i = 0; i < refs.length; i++)
        _dep(refs[i], sched: now.add(Duration(minutes: 1 + (i % 50) + (i > 500 ? 90 : 0)))),
    ];
    final runs = {
      for (final r in refs)
        r: {'run_ref': r, 'destination_name': 'Destination ${'x' * 200}', 'status': 'scheduled'},
    };
    final body = jsonEncode({'departures': deps, 'runs': runs, 'routes': _routes});
    expect(body.length, greaterThan(128 * 1024));

    final service = PtvRealtimeService(client: MockClient((_) async => http.Response(body, 200)));
    final trips = await service.fetchDepartures('1071');
    expect(trips.length, 501); // the 199 later than +1h are dropped
    final times = trips.map((t) => t.departure!.scheduledTime).toList();
    expect([...times]..sort(), times);
  });
}
