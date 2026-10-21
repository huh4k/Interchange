import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:transit_app/src/data/datasources/gtfs_zip_extractor.dart';
import 'package:transit_app/src/data/repositories/gtfs_repository.dart';

Uint8List _modeZip(String tag) {
  final zip = Archive();
  for (final name in [...kGtfsExtractAllowList, 'shapes.txt', 'agency.txt']) {
    final bytes = Uint8List.fromList('$tag:$name\n'.codeUnits);
    zip.add(ArchiveFile(name, bytes.length, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(zip));
}

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('gtfs_zip_'));
  tearDown(() => root.deleteSync(recursive: true));

  group('extractGtfsZipSync', () {
    test('extracts only allow-listed files', () {
      final zip = File('${root.path}/m.zip')..writeAsBytesSync(_modeZip('metro'));
      final target = '${root.path}/out/metroTrain';
      extractGtfsZipSync(zip.path, target);

      final names = Directory(target).listSync().map((e) => e.uri.pathSegments.last).toSet();
      expect(names, kGtfsExtractAllowList);
      expect(File('$target/stops.txt').readAsStringSync(), 'metro:stops.txt\n');
      expect(Directory('$target.staging').existsSync(), isFalse);
    });

    test('a corrupt zip leaves an existing dataset intact and no staging dir', () {
      final target = '${root.path}/out/metroTrain';
      Directory(target).createSync(recursive: true);
      File('$target/stops.txt').writeAsStringSync('old');

      final bad = File('${root.path}/bad.zip')..writeAsBytesSync(Uint8List.fromList(List.filled(64, 7)));
      expect(() => extractGtfsZipSync(bad.path, target), throwsA(anything));

      expect(File('$target/stops.txt').readAsStringSync(), 'old');
      expect(Directory('$target.staging').existsSync(), isFalse);
    });

    test('replaces a previous dataset on success', () {
      final zip = File('${root.path}/t.zip')..writeAsBytesSync(_modeZip('tram'));
      final target = '${root.path}/out/metroTram';
      Directory(target).createSync(recursive: true);
      File('$target/leftover.txt').writeAsStringSync('x');
      extractGtfsZipSync(zip.path, target);
      expect(File('$target/leftover.txt').existsSync(), isFalse);
      expect(File('$target/stops.txt').readAsStringSync(), 'tram:stops.txt\n');
    });
  });

  group('PtvGtfsRepository timetable download', () {
    late List<String> requested;
    late Completer<void> gate;

    PtvGtfsRepository makeRepo({bool failFirst = false}) {
      requested = [];
      gate = Completer<void>();
      return PtvGtfsRepository(
        baseUrl: Uri.parse('https://example.test'),
        client: MockClient.streaming((request, _) async {
          requested.add(request.url.path);
          if (failFirst && requested.length == 1) {
            return http.StreamedResponse(const Stream.empty(), 500);
          }
          await gate.future;
          final tag = request.url.path.contains('vline') ? 'vline' : 'metro';
          final bytes = _modeZip(tag);
          return http.StreamedResponse(Stream.value(bytes), 200, contentLength: bytes.length);
        }),
        supportDir: () async => Directory('${root.path}/support')..createSync(recursive: true),
        tempDir: () async => Directory('${root.path}/tmp')..createSync(recursive: true),
      );
    }

    test('concurrent loads share one download; each mode fetches its own zip', () async {
      final repo = makeRepo();
      final a = repo.getDatasetForMode(PtvMode.metroTrain);
      final b = repo.getDatasetForMode(PtvMode.metroTrain);
      final c = repo.getDatasetForMode(PtvMode.regionalTrain);
      await pumpEventQueue();
      gate.complete();
      final results = await Future.wait([a, b, c]);

      expect(requested..sort(), ['/metro.zip', '/vline.zip']);
      expect(File('${results[0]!.directory.path}/stops.txt').readAsStringSync(), 'metro:stops.txt\n');
      expect(File('${results[2]!.directory.path}/stops.txt').readAsStringSync(), 'vline:stops.txt\n');
      // The downloaded zip is removed once extracted.
      expect(Directory('${root.path}/tmp').listSync(), isEmpty);

      await repo.getDatasetForMode(PtvMode.metroTrain, forceRefresh: true);
      expect(requested.length, 3);
    });

    test('a failed download is retried by the next call', () async {
      final repo = makeRepo(failFirst: true);
      gate.complete();
      await expectLater(repo.getDatasetForMode(PtvMode.metroTrain), throwsA(anything));
      expect(await repo.getDatasetForMode(PtvMode.metroTrain), isNotNull);
      expect(requested.length, 2);
    });
  });
}
