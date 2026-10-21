import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transit_app/src/data/datasources/gtfs_day_timetable.dart';
import 'package:transit_app/src/data/repositories/gtfs_repository.dart';
import 'package:transit_app/src/domain/entities/station.dart';
import 'package:transit_app/src/domain/entities/trips.dart';

import 'support/reference_gtfs.dart';

Station _st(String id, String stopId) => Station(
      id: id,
      stopId: stopId,
      name: 'S $id',
      code: id,
      lat: -37.8,
      lon: 144.9,
      suburb: '',
      zone: 'Zone 1',
      routes: const [],
    );

String _hhmm(int minutes) {
  final h = (minutes ~/ 60).toString().padLeft(2, '0');
  final m = (minutes % 60).toString().padLeft(2, '0');
  return '$h:$m:00';
}

/// Writes a GTFS directory that exercises the awkward cases.
Directory _writeFixture() {
  final dir = Directory.systemTemp.createTempSync('gtfs_day_');
  File('${dir.path}/stops.txt').writeAsStringSync(
    'stop_id,stop_name,stop_lat,stop_lon,stop_url,location_type,parent_station\n'
    '"19842","Alpha Railway Station","-37.80","144.90","https://x/stop/1071/","",""\n'
    '"1162","Richmond Railway Station","-37.82","144.99","https://x/stop/1162/","",""\n',
  );
  File('${dir.path}/routes.txt').writeAsStringSync(
    'route_id,route_short_name,route_long_name,route_type\n'
    'r1,ALP,Alpha Line,2\n'
    'r2,,Beta Line,0\n'
    '"r3","GAM","Gamma, Long Line",1\n',
  );
  File('${dir.path}/calendar.txt').writeAsStringSync(
    'service_id,monday,tuesday,wednesday,thursday,friday,saturday,sunday,start_date,end_date\n'
    'WK,1,1,1,1,1,0,0,20260101,20261231\n'
    'SAT,0,0,0,0,0,1,0,20260101,20261231\n'
    'REM,1,1,1,1,1,0,0,20260101,20261231\n'
    'OLD,1,1,1,1,1,0,0,20200101,20201231\n',
  );
  File('${dir.path}/calendar_dates.txt').writeAsStringSync(
    'service_id,date,exception_type\n'
    'EXC,20261012,1\n'
    'REM,20261012,2\n'
    'WK,20261013,2\n',
  );

  const services = ['WK', 'SAT', 'EXC', 'REM', 'OLD', 'WK'];
  const stopsets = [
    ['19842', '1162', '1071_2', '1071#3'],
    ['19842:1', '1071-4', '1162:1', '19842'],
    ['1162', '19842', 'zzz', '1071_2'],
  ];
  final trips = StringBuffer('route_id,service_id,trip_id,trip_headsign,direction_id\n');
  final rows = <String>[];
  for (var i = 0; i < 60; i++) {
    final id = 't$i';
    trips.writeln('r${1 + i % 3},${services[i % services.length]},$id,${i % 4 == 0 ? '' : 'Head $i Railway Station'},${i % 2}');
    final stops = stopsets[i % stopsets.length];
    final base = 9 * 60 + (i % 20) * 7; // many ties between trips
    for (var k = 0; k < stops.length; k++) {
      final dep = (i == 7 && k == 0) ? '' : _hhmm(base + k * 3);
      rows.add('$id,${_hhmm(base + k * 3)},$dep,${stops[k]},${k + 1},${k % 2 == 0 ? '1' : ''}');
    }
  }
  trips.writeln('r1,WK,t3,Dup Head,1'); // duplicate trip row overwrites t3
  // Interleave rows so a trip's rows are not contiguous.
  final interleaved = <String>[];
  for (var k = 0; k < 4; k++) {
    for (var i = 0; i < 60; i++) {
      interleaved.add(rows[i * 4 + k]);
    }
  }
  File('${dir.path}/trips.txt').writeAsStringSync(trips.toString());
  File('${dir.path}/stop_times.txt').writeAsStringSync(
    'trip_id,arrival_time,departure_time,stop_id,stop_sequence,platform_code\n${interleaved.join('\n')}\n',
  );
  return dir;
}

List<Object?> _shape(List<Trip> trips) => [
      for (final t in trips)
        [
          t.tripId,
          t.routeId,
          t.serviceId,
          t.headsign,
          t.shortName,
          t.directionId,
          t.departure!.scheduledTime,
          t.departure!.platform,
          t.departure!.lineCode,
          t.departure!.routeName,
          t.departure!.destination,
          t.departure!.type,
          [
            for (final s in t.stops)
              [s.station.id, s.station.stopId, s.station.name, s.arrivalTime, s.departureTime, s.platform, s.stopSequence],
          ],
        ],
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('stopParentId matches the split chain', () {
    for (final id in ['', '1071', '1071:2', '19843#2', 'a_b:c#d', ':x', 'x-y', '_', '#a']) {
      expect(stopParentId(id), id.split(':').first.split('#').first.split('_').first, reason: id);
    }
  });

  group('day timetable equivalence with the original implementation', () {
    late Directory dir;
    final morning = DateTime(2026, 10, 12, 9, 30); // Monday
    final lateNight = DateTime(2026, 10, 12, 23, 30); // everything is in the past

    setUpAll(() => dir = _writeFixture());
    tearDownAll(() => dir.deleteSync(recursive: true));

    final targets = <String, Station?>{
      'no target': null,
      'parent id': _st('1071', '19842'),
      'other id': _st('x', '1162'),
      'alt id only': _st('1071_2', '777'),
      'unknown stop': _st('nope', 'nope'),
    };

    for (final entry in targets.entries) {
      for (final nowEntry in {'morning': morning, 'late night (fallback path)': lateNight}.entries) {
        test('${entry.key} / ${nowEntry.key}', () async {
          final want = await ReferenceGtfs.parseTripsFromDirectory(
            dir,
            targetStation: entry.value,
            nowOverride: nowEntry.value,
          );
          final got = await PtvGtfsRepository.parseTripsFromDirectory(
            dir,
            targetStation: entry.value,
            now: nowEntry.value,
          );
          expect(_shape(got), _shape(want));
        });
      }
    }

    test('fixture produces non-trivial results in both paths', () async {
      final a = await PtvGtfsRepository.parseTripsFromDirectory(dir, now: morning);
      final b = await PtvGtfsRepository.parseTripsFromDirectory(dir, now: lateNight);
      expect(a.length, greaterThan(10));
      expect(b.length, greaterThan(10));
    });
  });

  test('a large dataset is built on an isolate and still matches the original', () async {
    final dir = Directory.systemTemp.createTempSync('gtfs_big_');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/stops.txt').writeAsStringSync(
      'stop_id,stop_name,stop_lat,stop_lon,stop_url\n'
      '"19842","Alpha Railway Station","-37.80","144.90","https://x/stop/1071/"\n',
    );
    File('${dir.path}/routes.txt').writeAsStringSync('route_id,route_short_name,route_long_name,route_type\nr1,ALP,Alpha Line,2\n');
    File('${dir.path}/calendar.txt').writeAsStringSync(
      'service_id,monday,tuesday,wednesday,thursday,friday,saturday,sunday,start_date,end_date\n'
      'WK,1,1,1,1,1,1,1,20260101,20261231\n',
    );
    final trips = StringBuffer('route_id,service_id,trip_id,trip_headsign,direction_id\n');
    final times = StringBuffer('trip_id,arrival_time,departure_time,stop_id,stop_sequence,platform_code\n');
    for (var i = 0; i < 4000; i++) {
      trips.writeln('r1,WK,trip_number_$i,Head $i,${i % 2}');
      for (var k = 0; k < 6; k++) {
        times.writeln('trip_number_$i,${_hhmm(600 + (i % 90) + k * 2)},${_hhmm(600 + (i % 90) + k * 2)},${k == 2 ? '19842' : '${2000 + k}_$i'},${k + 1},1');
      }
    }
    File('${dir.path}/trips.txt').writeAsStringSync(trips.toString());
    File('${dir.path}/stop_times.txt').writeAsStringSync(times.toString());
    expect(File('${dir.path}/stop_times.txt').lengthSync(), greaterThan(128 * 1024));

    final now = DateTime(2026, 10, 12, 9, 0);
    for (final target in [null, _st('1071', '19842')]) {
      final want = await ReferenceGtfs.parseTripsFromDirectory(dir, targetStation: target, nowOverride: now);
      final got = await PtvGtfsRepository.parseTripsFromDirectory(dir, targetStation: target, now: now);
      expect(want, isNotEmpty);
      expect(_shape(got), _shape(want));
    }
  });

  group('timetable cache', () {
    test('is reused, shared by concurrent calls and cleared on demand', () async {
      final dir = _writeFixture();
      addTearDown(() => dir.deleteSync(recursive: true));
      final now = DateTime(2026, 10, 12, 9, 30);
      PtvGtfsRepository.clearTimetableCache();
      final before = PtvGtfsRepository.debugTimetableBuildCount;

      final results = await Future.wait([
        PtvGtfsRepository.parseTripsFromDirectory(dir, now: now),
        PtvGtfsRepository.parseTripsFromDirectory(dir, now: now),
      ]);
      expect(PtvGtfsRepository.debugTimetableBuildCount, before + 1);
      expect(results[0].length, results[1].length);

      File('${dir.path}/stop_times.txt').deleteSync();
      final again = await PtvGtfsRepository.parseTripsFromDirectory(dir, now: now);
      expect(again.length, results[0].length); // served from cache

      PtvGtfsRepository.clearTimetableCache(dir.path);
      expect(await PtvGtfsRepository.parseTripsFromDirectory(dir, now: now), isEmpty);

      final other = DateTime(2026, 10, 13, 9, 30);
      await PtvGtfsRepository.parseTripsFromDirectory(dir, now: other);
      expect(PtvGtfsRepository.debugTimetableBuildCount, greaterThanOrEqualTo(before + 3));
    });
  });
}
