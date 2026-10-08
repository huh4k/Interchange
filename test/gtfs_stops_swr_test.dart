import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:transit_app/src/data/repositories/gtfs_repository.dart';
import 'package:transit_app/src/services/melbourne_gtfs_service.dart';

const _header = 'stop_id,stop_name,stop_lat,stop_lon,stop_url,location_type,parent_station';
String _csv(String name, String id) =>
    '$_header\n"$id","$name Railway Station","-37.8","144.9","https://x/stop/$id/","",""\n';

void main() {
  late Directory root;
  late File stopsFile;
  late List<Completer<http.StreamedResponse>> pending;
  var requests = 0;

  setUp(() {
    root = Directory.systemTemp.createTempSync('stops_swr_');
    final dir = Directory('${root.path}/train')..createSync();
    stopsFile = File('${dir.path}/stops.txt');
    requests = 0;
    pending = [];
  });
  tearDown(() => root.deleteSync(recursive: true));

  PtvGtfsRepository repo({bool throwing = false}) => PtvGtfsRepository(
        masterZipUrl: Uri.parse('https://example.test/gtfs.zip'),
        client: MockClient.streaming((request, _) {
          requests++;
          if (throwing) throw const SocketException('offline');
          final c = Completer<http.StreamedResponse>();
          pending.add(c);
          return c.future;
        }),
        stopsFileFor: (_) => stopsFile,
        supportDir: () async => Directory('${root.path}/support')..createSync(),
        tempDir: () async => Directory('${root.path}/tmp')..createSync(),
      );

  http.StreamedResponse ok(String body) =>
      http.StreamedResponse(Stream.value(utf8.encode(body)), 200, headers: {'etag': '"e"'});

  test('serves the cache immediately while the revalidation is pending', () async {
    stopsFile.writeAsStringSync(_csv('Alpha', '1001'));
    final r = repo();
    final stations = await r.getStopsForMode(PtvMode.metroTrain);
    expect(stations.single.name, 'Alpha Station');
    await pumpEventQueue();
    expect(requests, 1);
    expect(pending.single.isCompleted, isFalse); // returned without waiting for it

    // Another call reuses the memo: no new request, same list instance.
    final again = await r.getStopsForMode(PtvMode.metroTrain);
    expect(identical(stations, again), isTrue);
    expect(requests, 1);
  });

  test('a newer feed replaces the memo for later calls', () async {
    stopsFile.writeAsStringSync(_csv('Alpha', '1001'));
    final r = repo();
    await r.getStopsForMode(PtvMode.metroTrain);
    await pumpEventQueue();
    pending.single.complete(ok(_csv('Bravo', '1002')));
    await pumpEventQueue(times: 50);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final later = await r.getStopsForMode(PtvMode.metroTrain);
    expect(later.single.name, 'Bravo Station');
  });

  test('concurrent first calls make one request', () async {
    final r = repo();
    final a = r.getStopsForMode(PtvMode.metroTrain);
    final b = r.getStopsForMode(PtvMode.metroTrain);
    await pumpEventQueue();
    expect(requests, 1);
    pending.single.complete(ok(_csv('Alpha', '1001')));
    expect((await a).single.name, 'Alpha Station');
    expect((await b).single.name, 'Alpha Station');
  });

  test('forceRefresh and clearCache refetch', () async {
    stopsFile.writeAsStringSync(_csv('Alpha', '1001'));
    final r = repo();
    await r.getStopsForMode(PtvMode.metroTrain);
    await pumpEventQueue();
    expect(requests, 1);

    final forced = r.getStopsForMode(PtvMode.metroTrain, forceRefresh: true);
    await pumpEventQueue();
    expect(requests, 2);
    pending.last.complete(ok(_csv('Charlie', '1003')));
    expect((await forced).single.name, 'Charlie Station');

    // clearCache drops the memo, so the next call goes back to disk/network.
    await r.clearCache();
    stopsFile.writeAsStringSync(_csv('Delta', '1004'));
    final afterClear = await r.getStopsForMode(PtvMode.metroTrain);
    expect(afterClear.single.name, 'Delta Station');
  });

  test('a failing first load is not cached', () async {
    final r = repo(throwing: true);
    await expectLater(r.getStopsForMode(PtvMode.metroTrain), throwsA(isA<GtfsNetworkException>()));
    await expectLater(r.getStopsForMode(PtvMode.metroTrain), throwsA(isA<GtfsNetworkException>()));
    expect(requests, 2);
  });
}
