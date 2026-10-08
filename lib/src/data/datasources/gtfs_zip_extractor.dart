import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

/// GTFS files the app reads. shapes.txt, agency.txt, etc. are never written to
/// disk. If you start consuming another file, add it here.
const Set<String> kGtfsExtractAllowList = {
  'stops.txt',
  'routes.txt',
  'trips.txt',
  'stop_times.txt',
  'calendar.txt',
  'calendar_dates.txt',
};

/// Whether archive entry [normName] (forward-slash separated) belongs to the
/// transit mode with folder id [modeId] in the statewide master feed.
bool isGtfsModeEntry(String normName, String modeId) =>
    normName.startsWith('$modeId/') ||
    normName.contains('/$modeId/') ||
    normName.endsWith('/$modeId.zip') ||
    normName == '$modeId.zip';

/// Extracts the allow-listed files for [modeId] from the master feed zip at
/// [masterPath] into [targetPath], streaming from disk (the master is never
/// loaded into memory).
///
/// Writes to a sibling `.staging` directory and swaps it in on success, so a
/// failure or crash never leaves a partial dataset at [targetPath]. Blocking:
/// run it through `runHeavy`.
void extractGtfsModeSync(String masterPath, String modeId, String targetPath) {
  final staging = Directory('$targetPath.staging');
  if (staging.existsSync()) staging.deleteSync(recursive: true);
  staging.createSync(recursive: true);

  InputFileStream? masterInput;
  try {
    masterInput = InputFileStream(masterPath);
    final master = ZipDecoder().decodeStream(masterInput);

    for (final entry in master) {
      if (!entry.isFile) continue;
      final normName = entry.name.replaceAll('\\', '/');
      if (!isGtfsModeEntry(normName, modeId)) continue;

      if (normName.endsWith('.zip')) {
        _extractInnerZip(entry, staging.path);
      } else if (normName.endsWith('.txt')) {
        final base = p.basename(normName);
        if (!kGtfsExtractAllowList.contains(base)) continue;
        final out = OutputFileStream(p.join(staging.path, base));
        try {
          entry.writeContent(out);
        } finally {
          out.closeSync();
        }
      }
    }

    // A corrupt or unrelated archive can decode to "no entries"; never swap
    // that in over a good dataset.
    if (!File(p.join(staging.path, 'routes.txt')).existsSync()) {
      throw FormatException('No GTFS data for mode $modeId in $masterPath');
    }
  } catch (_) {
    masterInput?.closeSync();
    masterInput = null;
    if (staging.existsSync()) staging.deleteSync(recursive: true);
    rethrow;
  } finally {
    masterInput?.closeSync();
  }

  final target = Directory(targetPath);
  if (target.existsSync()) target.deleteSync(recursive: true);
  staging.renameSync(targetPath);
}

void _extractInnerZip(ArchiveFile innerZipEntry, String stagingPath) {
  final innerPath = p.join(stagingPath, '_inner.zip');
  final innerOut = OutputFileStream(innerPath);
  try {
    innerZipEntry.writeContent(innerOut);
  } finally {
    innerOut.closeSync();
  }

  final innerIn = InputFileStream(innerPath);
  try {
    final inner = ZipDecoder().decodeStream(innerIn);
    for (final file in inner) {
      if (!file.isFile) continue;
      final base = p.basename(file.name);
      if (!kGtfsExtractAllowList.contains(base)) continue;
      final out = OutputFileStream(p.join(stagingPath, base));
      try {
        file.writeContent(out);
      } finally {
        out.closeSync();
      }
    }
  } finally {
    innerIn.closeSync();
    File(innerPath).deleteSync();
  }
}
