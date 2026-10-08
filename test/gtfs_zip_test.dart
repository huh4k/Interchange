import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:transit_app/src/data/datasources/gtfs_zip_extractor.dart';
import 'package:transit_app/src/data/repositories/gtfs_repository.dart';

Uint8List _innerZip(String tag) {
  final inner = Archive();
  for (final name in [
    'stops.txt',
    'routes.txt',
    'trips.txt',
    'stop_times.txt',
    'calendar.txt',
    'calendar_dates.txt',
    'shapes.txt',
    'agency.txt',
  ]) {
    final bytes = Uint8List.fromList('$tag:$name\n'.codeUnits);
    inner.add(ArchiveFile(name, bytes.length, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(inner));
}

Uint8List _masterZip() {
  final master = Archive();
  for (final mode in ['2', '3']) {
    final inner = _innerZip('mode$mode');
    master.add(ArchiveFile('$mode/google_transit.zip', inner.length, inner));
  }
  return Uint8List.fromList(ZipEncoder().encode(master));
}

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('gtfs_zip_'));
  tearDown(() => root.deleteSync(recursive: true));

  group('extractGtfsModeSync', () {
    test('extracts only allow-listed files of the requested mode', () {
      final master = File('${root.path}/master.zip')..writeAsBytesSync(_masterZip());
      final target = '${root.path}/out/metroTrain';
      extractGtfsModeSync(master.path, '2', target);

      final names = Directory(target).listSync().map((e) => e.uri.pathSegments.last).toSet();
      expect(names, kGtfsExtractAllowList);
      expect(File('$target/stops.txt').readAsStringSync(), 'mode2:stops.txt\n');
      expect(File('$target/stop_times.txt').readAsStringSync(), 'mode2:stop_times.txt\n');
      expect(Directory('$target.staging').existsSync(), isFalse);
    });

    test('a corrupt master leaves an existing dataset intact and no staging dir', () {
      final target = '${root.path}/out/metroTrain';
      Directory(target).createSync(recursive: true);
      File('$target/stops.txt').writeAsStringSync('old');

      final bad = File('${root.path}/bad.zip')..writeAsBytesSync(Uint8List.fromList(List.filled(64, 7)));
      expect(() => extractGtfsModeSync(bad.path, '2', target), throwsA(anything));

      expect(File('$target/stops.txt').readAsStringSync(), 'old');
      expect(Directory('$target.staging').existsSync(), isFalse);
    });

    test('replaces a previous dataset on success', () {
      final master = File('${root.path}/master.zip')..writeAsBytesSync(_masterZip());
      final target = '${root.path}/out/metroTram';
      Directory(target).createSync(recursive: true);
      File('$target/leftover.txt').writeAsStringSync('x');
      extractGtfsModeSync(master.path, '3', target);
      expect(File('$target/leftover.txt').existsSync(), isFalse);
      expect(File('$target/stops.txt').readAsStringSync(), 'mode3:stops.txt\n');
    });
  });

  group('PtvGtfsRepository master download', () {
    late int downloads;
    late Completer<void> gate;
    late PtvGtfsRepository repo;

    PtvGtfsRepository makeRepo({bool failFirst = false}) {
      downloads = 0;
      gate = Completer<void>();
      final bytes = _masterZip();
      return PtvGtfsRepository(
        masterZipUrl: Uri.parse('https://example.test/gtfs.zip'),
        client: MockClient.streaming((request, _) async {
          downloads++;
          if (failFirst && downloads == 1) {
            return http.StreamedResponse(const Stream.empty(), 500);
          }
          await gate.future;
          return http.StreamedResponse(Stream.value(bytes), 200, contentLength: bytes.length);
        }),
        supportDir: () async => Directory('${root.path}/support')..createSync(recursive: true),
        tempDir: () async => Directory('${root.path}/tmp')..createSync(recursive: true),
      );
    }

    test('concurrent loads share one download; other modes reuse the file', () async {
      repo = makeRepo();
      final a = repo.getDatasetForMode(PtvMode.metroTrain);
      final b = repo.getDatasetForMode(PtvMode.metroTrain);
      final c = repo.getDatasetForMode(PtvMode.metroTram);
      await pumpEventQueue();
      gate.complete();
      final results = await Future.wait([a, b, c]);

      expect(downloads, 1);
      expect(File('${results[0]!.directory.path}/stops.txt').readAsStringSync(), 'mode2:stops.txt\n');
      expect(File('${results[2]!.directory.path}/stops.txt').readAsStringSync(), 'mode3:stops.txt\n');
      expect(File('${root.path}/tmp/ptv_gtfs_master.zip').existsSync(), isTrue);
      expect(File('${root.path}/tmp/ptv_gtfs_master.zip.part').existsSync(), isFalse);

      // A later forced refresh downloads again.
      await repo.getDatasetForMode(PtvMode.metroTrain, forceRefresh: true);
      expect(downloads, 2);
    });

    test('a failed download is retried by the next call', () async {
      repo = makeRepo(failFirst: true);
      gate.complete();
      await expectLater(repo.getDatasetForMode(PtvMode.metroTrain), throwsA(anything));
      final ok = await repo.getDatasetForMode(PtvMode.metroTrain);
      expect(ok, isNotNull);
      expect(downloads, 2);
    });
  });
}
