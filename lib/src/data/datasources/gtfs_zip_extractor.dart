import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

/// GTFS files the app reads. Anything else in a mode zip is never written to
/// disk. If you start consuming another file, add it here and to
/// `tool/build_gtfs_r2.py`.
const Set<String> kGtfsExtractAllowList = {
  'stops.txt',
  'routes.txt',
  'trips.txt',
  'stop_times.txt',
  'calendar.txt',
  'calendar_dates.txt',
};

/// Extracts the allow-listed files from the mode zip at [zipPath] into
/// [targetPath], streaming from disk (the zip is never loaded into memory).
///
/// Writes to a sibling `.staging` directory and swaps it in on success, so a
/// failure or crash never leaves a partial dataset at [targetPath]. Blocking:
/// run it through `runHeavy`.
void extractGtfsZipSync(String zipPath, String targetPath) {
  final staging = Directory('$targetPath.staging');
  if (staging.existsSync()) staging.deleteSync(recursive: true);
  staging.createSync(recursive: true);

  InputFileStream? input;
  try {
    input = InputFileStream(zipPath);
    for (final entry in ZipDecoder().decodeStream(input)) {
      if (!entry.isFile) continue;
      final base = p.basename(entry.name.replaceAll('\\', '/'));
      if (!kGtfsExtractAllowList.contains(base)) continue;
      final out = OutputFileStream(p.join(staging.path, base));
      try {
        entry.writeContent(out);
      } finally {
        out.closeSync();
      }
    }

    // A corrupt or unrelated archive can decode to "no entries"; never swap
    // that in over a good dataset.
    if (!File(p.join(staging.path, 'routes.txt')).existsSync()) {
      throw FormatException('No GTFS data in $zipPath');
    }
  } catch (_) {
    input?.closeSync();
    input = null;
    if (staging.existsSync()) staging.deleteSync(recursive: true);
    rethrow;
  } finally {
    input?.closeSync();
  }

  final target = Directory(targetPath);
  if (target.existsSync()) target.deleteSync(recursive: true);
  staging.renameSync(targetPath);
}
