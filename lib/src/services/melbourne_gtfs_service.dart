import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../core/gtfs_csv.dart';
import '../core/heavy_work.dart';
import '../domain/entities/station.dart';
import '../domain/value_objects/ptv_mode.dart';
import '../data/datasources/gtfs_index_engine.dart';

typedef GtfsProgressCallback = void Function(double progress, String status);

class GtfsNetworkException implements Exception {
  final String message;
  const GtfsNetworkException(this.message);

  @override
  String toString() => message;
}

class MelbourneGtfsService {
  static const String metroStopsUrl =
      'https://raw.githubusercontent.com/huh4k/h4k-lib/main/metro/stops.txt';
  static const String tramStopsUrl =
      'https://raw.githubusercontent.com/huh4k/h4k-lib/main/tram/stops.txt';

  static const String stopsUrl = metroStopsUrl;

  static String stopsUrlForMode(PtvMode mode) {
    switch (mode) {
      case PtvMode.metroTram:
        return tramStopsUrl;
      case PtvMode.metroTrain:
      default:
        return metroStopsUrl;
    }
  }

  static const Station defaultStation = Station(
    id: 'vic:rail:FSS',
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

  static const Station defaultTramStop = Station(
    id: '2722',
    stopId: '2722',
    name: 'Flinders Street Railway Station/Elizabeth St #1',
    code: '1',
    lat: -37.81771743,
    lon: 144.96476527,
    suburb: 'Melbourne CBD',
    zone: 'Zone 1',
    isCityLoop: false,
    routes: [],
  );

  static Station defaultStationForMode(PtvMode mode) {
    switch (mode) {
      case PtvMode.metroTram:
        return defaultTramStop;
      case PtvMode.metroTrain:
      default:
        return defaultStation;
    }
  }

  static Future<File?> getLocalStopsFile([PtvMode mode = PtvMode.metroTrain]) async {
    try {
      Directory? baseDir;
      try {
        baseDir = await getApplicationSupportDirectory();
      } catch (_) {
        try {
          baseDir = await getApplicationDocumentsDirectory();
        } catch (_) {
          baseDir = await getTemporaryDirectory();
        }
      }
      final subFolder = mode == PtvMode.metroTram ? 'tram' : 'metro';
      final stopsDir = Directory(p.join(baseDir.path, 'ptv_gtfs', subFolder));
      if (!await stopsDir.exists()) {
        await stopsDir.create(recursive: true);
      }
      final newStopsFile = File(p.join(stopsDir.path, 'stops.txt'));

      // Backward compatibility check for older single-file cache
      if (mode == PtvMode.metroTrain && !await newStopsFile.exists()) {
        final legacyFile = File(p.join(baseDir.path, 'ptv_gtfs', 'stops.txt'));
        if (await legacyFile.exists()) {
          try {
            await legacyFile.copy(newStopsFile.path);
            final legacyEtag = File(p.join(baseDir.path, 'ptv_gtfs', 'stops.etag'));
            if (await legacyEtag.exists()) {
              await legacyEtag.copy(p.join(stopsDir.path, 'stops.etag'));
            }
          } catch (_) {}
        }
      }

      return newStopsFile;
    } catch (_) {
      return null;
    }
  }

  static File _getEtagFile(File targetFile) {
    return File(p.join(targetFile.parent.path, 'stops.etag'));
  }

  static Future<List<Station>?> _loadCachedStations(
    File targetFile, {
    PtvMode mode = PtvMode.metroTrain,
  }) async {
    // 1. Fast Path: Binary index
    final binFile = File(p.join(targetFile.parent.path, GtfsIndexEngine.binaryIndexFilename));
    if (await binFile.exists()) {
      try {
        final binCache = await GtfsIndexEngine.loadBinaryIndex(binFile);
        if (binCache != null && binCache.stops.isNotEmpty) {
          final rawStations = binCache.stops.values.toList();
          final uniqueByName = <String, Station>{};
          for (final s in rawStations) {
            final cleanName = mode == PtvMode.metroTram
                ? s.name
                : GtfsIndexEngine.normalizeStationName(s.name);
            if (GtfsIndexEngine.isReplacementBusStop(cleanName)) continue;
            final key = mode == PtvMode.metroTram ? s.stopId : cleanName.toLowerCase();
            if (!uniqueByName.containsKey(key)) {
              uniqueByName[key] = s.copyWith(name: cleanName);
            }
          }
          final stations = uniqueByName.values.toList()
            ..sort((a, b) => a.name.compareTo(b.name));
          if (stations.isNotEmpty) {
            // Validate that tram mode stops have proper PTV API stop IDs (2001-3500)
            if (mode == PtvMode.metroTram) {
              final hasValidTramIds = stations.any((s) {
                final idInt = int.tryParse(s.stopId) ?? 0;
                return idInt >= 2001 && idInt <= 3500;
              });
              if (!hasValidTramIds) {
                // Outdated binary cache with internal GTFS IDs: delete and re-parse
                try {
                  await binFile.delete();
                } catch (_) {}
                return null;
              }
            }
            return stations;
          }
        }
      } catch (_) {}
    }

    // 2. Text CSV cache
    if (await targetFile.exists()) {
      try {
        final content = await targetFile.readAsString();
        if (content.trim().isNotEmpty) {
          final stations = await runHeavy(
            content.length,
            () => parseStopsTxt(content, mode: mode),
          );
          final fallbackStation = defaultStationForMode(mode);
          if (stations.isNotEmpty &&
              (stations.length > 1 || stations.first.id != fallbackStation.id || content.contains('stop_id'))) {
            try {
              GtfsIndexEngine.getOrCreateIndex(targetFile.parent);
            } catch (_) {}
            return stations;
          }
        }
      } catch (_) {}
    }

    return null;
  }

  /// Streams stops.txt for the given [mode] from remote repository, saves it to local disk, and parses stations.
  /// Uses HTTP ETag conditional headers (If-None-Match) to avoid downloading when repo is unchanged.
  /// Throws [GtfsNetworkException] if network is not connected and no local cache exists.
  static Future<List<Station>> loadOrDownloadStops({
    PtvMode mode = PtvMode.metroTrain,
    File? localFile,
    http.Client? client,
    GtfsProgressCallback? onProgress,
    bool forceRefresh = false,
    Duration responseTimeout = const Duration(seconds: 10),
    Duration idleTimeout = const Duration(seconds: 20),
  }) async {
    File? targetFile = localFile;
    targetFile ??= await getLocalStopsFile(mode);

    final etagFile = targetFile != null ? _getEtagFile(targetFile) : null;
    String? savedEtag;
    if (etagFile != null && await etagFile.exists()) {
      try {
        savedEtag = (await etagFile.readAsString()).trim();
      } catch (_) {}
    }

    final hasLocalCache = targetFile != null && await targetFile.exists();

    final httpClient = client ?? http.Client();
    final modeLabel = mode == PtvMode.metroTram ? 'Tram' : 'Metro';
    onProgress?.call(0.05, 'Checking $modeLabel Stations Feed: 5%');

    final url = stopsUrlForMode(mode);

    try {
      final request = http.Request('GET', Uri.parse(url));
      if (!forceRefresh && savedEtag != null && savedEtag.isNotEmpty && hasLocalCache) {
        request.headers['If-None-Match'] = savedEtag;
      }

      final streamedResponse = await httpClient.send(request).timeout(responseTimeout);

      if (streamedResponse.statusCode == 304) {
        // Repo is unchanged: load from local cache
        if (targetFile != null) {
          final cached = await _loadCachedStations(targetFile, mode: mode);
          if (cached != null && cached.isNotEmpty) {
            onProgress?.call(1.0, '$modeLabel Stations Up-to-Date: 100%');
            return cached;
          }
        }
      }

      if (streamedResponse.statusCode == 200) {
        // Repo updated or first download: stream chunks to temp file and parse
        final stations = await _streamAndParseStops(
          streamedResponse: streamedResponse,
          targetFile: targetFile,
          etagFile: etagFile,
          mode: mode,
          onProgress: onProgress,
          idleTimeout: idleTimeout,
        );
        return stations;
      }

      throw GtfsNetworkException(
        'Failed to download stations (HTTP ${streamedResponse.statusCode}).',
      );
    } catch (e) {
      // If we already have cached data, fall back to offline cache
      if (targetFile != null) {
        final cached = await _loadCachedStations(targetFile, mode: mode);
        if (cached != null && cached.isNotEmpty) {
          onProgress?.call(1.0, 'Loaded Cached $modeLabel Stations (Offline): 100%');
          return cached;
        }
      }

      if (e is GtfsNetworkException) {
        rethrow;
      }
      throw const GtfsNetworkException(
        'Network not connected. Unable to download stations.',
      );
    }
  }

  static Future<List<Station>> _streamAndParseStops({
    required http.StreamedResponse streamedResponse,
    File? targetFile,
    File? etagFile,
    PtvMode mode = PtvMode.metroTrain,
    GtfsProgressCallback? onProgress,
    Duration idleTimeout = const Duration(seconds: 20),
  }) async {
    File? tempFile;
    IOSink? sink;
    StreamController<List<int>>? lineController;

    try {
      if (targetFile != null) {
        if (!await targetFile.parent.exists()) {
          await targetFile.parent.create(recursive: true);
        }
        tempFile = File('${targetFile.path}.tmp');
        sink = tempFile.openWrite();
      }

      lineController = StreamController<List<int>>();

      final parseFuture = parseStopsStream(
        lineController.stream.transform(utf8.decoder).transform(const LineSplitter()),
        mode: mode,
      );

      final contentLength = streamedResponse.contentLength ?? 0;
      int downloaded = 0;
      final modeLabel = mode == PtvMode.metroTram ? 'Tram' : 'Metro';

      await for (final chunk in streamedResponse.stream.timeout(idleTimeout)) {
        sink?.add(chunk);
        lineController.add(chunk);
        downloaded += chunk.length;
        if (contentLength > 0 && onProgress != null) {
          final pVal = (downloaded / contentLength).clamp(0.05, 0.90);
          final pct = (pVal * 100).toInt();
          onProgress(pVal, 'Streaming $modeLabel Stations: $pct%');
        }
      }

      await lineController.close();
      if (sink != null) {
        await sink.flush();
        await sink.close();
        sink = null;
      }

      onProgress?.call(0.95, 'Parsing $modeLabel Stations: 95%');
      final stations = await parseFuture;

      final fallbackStation = defaultStationForMode(mode);
      if (stations.isEmpty || (stations.length == 1 && stations.first == fallbackStation)) {
        throw const GtfsNetworkException('Downloaded station feed was empty or invalid.');
      }

      if (tempFile != null && targetFile != null) {
        try {
          if (await targetFile.exists()) {
            await targetFile.delete();
          }
          await tempFile.rename(targetFile.path);
        } catch (_) {
          await tempFile.copy(targetFile.path);
          await tempFile.delete();
        }

        final etag = streamedResponse.headers['etag'];
        if (etag != null && etag.trim().isNotEmpty && etagFile != null) {
          try {
            await etagFile.writeAsString(etag.trim());
          } catch (_) {}
        }

        // stops.txt changed: drop the stale binary index and in-memory index
        // so later cache reads cannot serve the old station list.
        try {
          await File(p.join(targetFile.parent.path, GtfsIndexEngine.binaryIndexFilename)).delete();
        } catch (_) {}
        GtfsIndexEngine.invalidate(targetFile.parent.path);
        try {
          GtfsIndexEngine.getOrCreateIndex(targetFile.parent);
        } catch (_) {}
      }

      onProgress?.call(1.0, '$modeLabel Stations Ready: 100%');
      return stations;
    } catch (e) {
      await lineController?.close();
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {}
      }
      if (tempFile != null && await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// Parses lines from a streaming GTFS stops CSV into deduplicated Station objects.
  static Future<List<Station>> parseStopsStream(
    Stream<String> lineStream, {
    PtvMode mode = PtvMode.metroTrain,
  }) async {
    final stopIdRegex = RegExp(r'/stop/(\d+)');
    final stationMap = <String, Station>{};
    List<String>? headers;
    int stopIdIdx = -1;
    int stopNameIdx = -1;
    int stopLatIdx = -1;
    int stopLonIdx = -1;
    int stopUrlIdx = -1;
    int parentStationIdx = -1;
    final fallbackStation = defaultStationForMode(mode);

    await for (var line in lineStream) {
      line = line.trim();
      if (line.isEmpty) continue;

      if (headers == null) {
        final headerLine = line.replaceAll('\uFEFF', '');
        headers = parseGtfsCsvRow(headerLine);
        stopIdIdx = headers.indexOf('stop_id');
        stopNameIdx = headers.indexOf('stop_name');
        stopLatIdx = headers.indexOf('stop_lat');
        stopLonIdx = headers.indexOf('stop_lon');
        stopUrlIdx = headers.indexOf('stop_url');
        parentStationIdx = headers.indexOf('parent_station');
        if (stopNameIdx == -1) {
          return [fallbackStation];
        }
        continue;
      }

      final cols = parseGtfsCsvRow(line);
      if (cols.length <= stopNameIdx) continue;

      final rawStopId = stopIdIdx != -1 && cols.length > stopIdIdx ? cols[stopIdIdx] : '';
      final rawName = cols[stopNameIdx];
      if (rawName.toLowerCase().contains('replacement bus')) continue;

      final cleanName = _normalizeStationName(rawName, mode: mode);
      final stopLat = (stopLatIdx != -1 && cols.length > stopLatIdx)
          ? double.tryParse(cols[stopLatIdx]) ?? 0.0
          : 0.0;
      final stopLon = (stopLonIdx != -1 && cols.length > stopLonIdx)
          ? double.tryParse(cols[stopLonIdx]) ?? 0.0
          : 0.0;

      final stopUrl = (stopUrlIdx != -1 && cols.length > stopUrlIdx) ? cols[stopUrlIdx] : '';
      final urlMatch = stopIdRegex.firstMatch(stopUrl);
      final ptvStopId = urlMatch != null ? urlMatch.group(1)! : rawStopId;

      final parentStationVal = (parentStationIdx != -1 && cols.length > parentStationIdx)
          ? cols[parentStationIdx].trim()
          : '';

      final parentKey = mode == PtvMode.metroTram
          ? (ptvStopId.isNotEmpty ? ptvStopId : rawStopId)
          : (parentStationVal.isNotEmpty ? parentStationVal : cleanName.toLowerCase());

      String code;
      if (mode == PtvMode.metroTram) {
        final stopNumberMatch = RegExp(r'#\s*(\d+[a-zA-Z]?)').firstMatch(cleanName);
        code = stopNumberMatch != null ? stopNumberMatch.group(1)! : ptvStopId;
      } else {
        code = parentStationVal.contains(':')
            ? parentStationVal.split(':').last
            : (parentStationVal.isNotEmpty ? parentStationVal : ptvStopId);
      }

      final nameLower = cleanName.toLowerCase();
      final isCityLoop = mode == PtvMode.metroTrain &&
          (nameLower.contains('central') ||
              nameLower.contains('flinders') ||
              nameLower.contains('parliament') ||
              nameLower.contains('flagstaff') ||
              nameLower.contains('southern cross') ||
              ['FSS', 'SSS', 'MCE', 'PAR', 'FGS'].contains(code));

      if (!stationMap.containsKey(parentKey)) {
        stationMap[parentKey] = Station(
          id: parentStationVal.isNotEmpty ? parentStationVal : ptvStopId,
          stopId: ptvStopId,
          name: cleanName,
          code: code,
          lat: stopLat,
          lon: stopLon,
          suburb: 'Melbourne',
          zone: 'Zone 1',
          isCityLoop: isCityLoop,
          routes: const [],
        );
      }
    }

    if (stationMap.isEmpty) return [fallbackStation];

    final stationList = stationMap.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return stationList;
  }

  /// Parses CSV content of stops.txt into deduplicated Station objects.
  static List<Station> parseStopsTxt(
    String csvContent, {
    PtvMode mode = PtvMode.metroTrain,
  }) {
    final fallbackStation = defaultStationForMode(mode);
    if (csvContent.trim().isEmpty) return [fallbackStation];

    final lines = const LineSplitter().convert(csvContent);
    if (lines.isEmpty) return [fallbackStation];

    final headerLine = lines.first.replaceAll('\uFEFF', ''); // Strip BOM
    final headers = parseGtfsCsvRow(headerLine);

    final stopIdIdx = headers.indexOf('stop_id');
    final stopNameIdx = headers.indexOf('stop_name');
    final stopLatIdx = headers.indexOf('stop_lat');
    final stopLonIdx = headers.indexOf('stop_lon');
    final stopUrlIdx = headers.indexOf('stop_url');
    final parentStationIdx = headers.indexOf('parent_station');

    if (stopNameIdx == -1) return [fallbackStation];

    final stopIdRegex = RegExp(r'/stop/(\d+)');
    final stationMap = <String, Station>{};

    for (int i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      final cols = parseGtfsCsvRow(line);
      if (cols.length <= stopNameIdx) continue;

      final rawStopId = stopIdIdx != -1 && cols.length > stopIdIdx ? cols[stopIdIdx] : '';
      final rawName = cols[stopNameIdx];
      if (rawName.toLowerCase().contains('replacement bus')) continue;

      final cleanName = _normalizeStationName(rawName, mode: mode);
      final stopLat = (stopLatIdx != -1 && cols.length > stopLatIdx)
          ? double.tryParse(cols[stopLatIdx]) ?? 0.0
          : 0.0;
      final stopLon = (stopLonIdx != -1 && cols.length > stopLonIdx)
          ? double.tryParse(cols[stopLonIdx]) ?? 0.0
          : 0.0;

      final stopUrl = (stopUrlIdx != -1 && cols.length > stopUrlIdx) ? cols[stopUrlIdx] : '';
      final urlMatch = stopIdRegex.firstMatch(stopUrl);
      final ptvStopId = urlMatch != null ? urlMatch.group(1)! : rawStopId;

      final parentStationVal = (parentStationIdx != -1 && cols.length > parentStationIdx)
          ? cols[parentStationIdx].trim()
          : '';

      final parentKey = mode == PtvMode.metroTram
          ? (ptvStopId.isNotEmpty ? ptvStopId : rawStopId)
          : (parentStationVal.isNotEmpty ? parentStationVal : cleanName.toLowerCase());

      String code;
      if (mode == PtvMode.metroTram) {
        final stopNumberMatch = RegExp(r'#\s*(\d+[a-zA-Z]?)').firstMatch(cleanName);
        code = stopNumberMatch != null ? stopNumberMatch.group(1)! : ptvStopId;
      } else {
        code = parentStationVal.contains(':')
            ? parentStationVal.split(':').last
            : (parentStationVal.isNotEmpty ? parentStationVal : ptvStopId);
      }

      final nameLower = cleanName.toLowerCase();
      final isCityLoop = mode == PtvMode.metroTrain &&
          (nameLower.contains('central') ||
              nameLower.contains('flinders') ||
              nameLower.contains('parliament') ||
              nameLower.contains('flagstaff') ||
              nameLower.contains('southern cross') ||
              ['FSS', 'SSS', 'MCE', 'PAR', 'FGS'].contains(code));

      if (!stationMap.containsKey(parentKey)) {
        stationMap[parentKey] = Station(
          id: parentStationVal.isNotEmpty ? parentStationVal : ptvStopId,
          stopId: ptvStopId,
          name: cleanName,
          code: code,
          lat: stopLat,
          lon: stopLon,
          suburb: 'Melbourne',
          zone: 'Zone 1',
          isCityLoop: isCityLoop,
          routes: const [],
        );
      }
    }

    if (stationMap.isEmpty) return [fallbackStation];

    final stationList = stationMap.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return stationList;
  }

  static String _normalizeStationName(String raw, {PtvMode mode = PtvMode.metroTrain}) {
    if (mode == PtvMode.metroTram) {
      return raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    }
    var name = raw
        .replaceAll(RegExp(r'\s*Railway Station', caseSensitive: false), ' Station')
        .replaceAll(RegExp(r'\s*\([^)]*\)'), '')
        .trim();
    if (!name.toLowerCase().endsWith(' station')) {
      name = '$name Station';
    }
    return name;
  }

}
