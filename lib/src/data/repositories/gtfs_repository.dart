import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:gtfs_bindings/schedule.dart' as gtfs;
import 'package:gtfs_realtime_bindings/gtfs_realtime_bindings.dart' as gtfs_rt;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:flutter/foundation.dart' show visibleForTesting;
import '../../core/heavy_work.dart';
import '../datasources/gtfs_day_timetable.dart';
import '../../domain/entities/station.dart';
import '../../domain/entities/service.dart';
import '../../domain/entities/trips.dart';
import '../../domain/entities/transit_route.dart';
import '../../domain/value_objects/ptv_mode.dart';
import '../../services/ptv_rt_service.dart';
import '../../services/melbourne_gtfs_service.dart';
import '../datasources/gtfs_index_engine.dart';

export '../../domain/value_objects/ptv_mode.dart';

typedef GtfsProgressCallback = void Function(double progress, String status);

abstract interface class IGtfsRepository {
  Future<gtfs.DirectoryDataset?> getDatasetForMode(
    PtvMode mode, {
    bool forceRefresh = false,
    GtfsProgressCallback? onProgress,
  });
  Future<List<Trip>> getTripsForMode(
    PtvMode mode, {
    Station? station,
    bool forceRefresh = false,
    GtfsProgressCallback? onProgress,
  });
  Future<List<Station>> getStopsForMode(
    PtvMode mode, {
    bool forceRefresh = false,
    GtfsProgressCallback? onProgress,
  });
  Future<List<ServiceAlert>> getServiceAlerts();
  Future<void> clearCache();
}

class PtvGtfsRepository implements IGtfsRepository {
  final Uri masterZipUrl;
  final http.Client _client;
  final Duration _zipResponseTimeout;
  final Duration _zipIdleTimeout;
  final PtvRealtimeService _realtimeService;

  List<int>? _cachedMasterBytes;

  PtvGtfsRepository({
    required this.masterZipUrl,
    http.Client? client,
    this._zipResponseTimeout = const Duration(seconds: 30),
    this._zipIdleTimeout = const Duration(seconds: 60),
    PtvRealtimeService? realtimeService,
  })  : _client = client ?? http.Client(),
        _realtimeService =
            realtimeService ?? PtvRealtimeService(client: client);

  @override
  Future<gtfs.DirectoryDataset?> getDatasetForMode(
    PtvMode mode, {
    bool forceRefresh = false,
    GtfsProgressCallback? onProgress,
  }) async {
    final appSupportDir = await getApplicationSupportDirectory();
    final modeDir = Directory(
      p.join(appSupportDir.path, 'ptv_gtfs', mode.name),
    );
    final routesFile = File(p.join(modeDir.path, 'routes.txt'));

    if (!forceRefresh && await _hasFreshCache(routesFile)) {
      onProgress?.call(1.0, 'Cached Timetables Loaded');
      return gtfs.DirectoryDataset(directory: modeDir);
    }

    if (forceRefresh) _cachedMasterBytes = null;
    _cachedMasterBytes ??= await _fetchMasterZip(onProgress: onProgress);
    // The files on disk are about to change: drop anything derived from them.
    clearTimetableCache(modeDir.path);
    GtfsIndexEngine.invalidate(modeDir.path);
    await _extractModeToDirectory(_cachedMasterBytes!, mode, modeDir);
    onProgress?.call(1.0, 'Network Data Loaded: 100%');

    return gtfs.DirectoryDataset(directory: modeDir);
  }

  @override
  Future<List<Trip>> getTripsForMode(
    PtvMode mode, {
    Station? station,
    bool forceRefresh = false,
    GtfsProgressCallback? onProgress,
  }) async {
    final dataset = await getDatasetForMode(
      mode,
      forceRefresh: forceRefresh,
      onProgress: onProgress,
    );
    if (dataset != null) {
      return parseTripsFromDirectory(
        dataset.directory,
        targetStation: station,
      );
    }
    return [];
  }

  @override
  Future<List<Station>> getStopsForMode(
    PtvMode mode, {
    bool forceRefresh = false,
    GtfsProgressCallback? onProgress,
  }) async {
    return MelbourneGtfsService.loadOrDownloadStops(
      mode: mode,
      client: _client,
      onProgress: onProgress,
      forceRefresh: forceRefresh,
    );
  }

  @override
  Future<List<ServiceAlert>> getServiceAlerts() async {
    return _realtimeService.fetchLiveDisruptions();
  }

  @override
  Future<void> clearCache() async {
    _cachedMasterBytes = null;
    clearTimetableCache();
    GtfsIndexEngine.clearCache();
    final localStopsFile = await MelbourneGtfsService.getLocalStopsFile();
    if (localStopsFile != null && await localStopsFile.exists()) {
      await localStopsFile.delete();
    }
    final appSupportDir = await getApplicationSupportDirectory();
    final cacheDir = Directory(p.join(appSupportDir.path, 'ptv_gtfs'));
    if (await cacheDir.exists()) {
      await cacheDir.delete(recursive: true);
    }
  }

  // One timetable per mode directory per calendar day: building it parses
  // trips/stop_times/calendars/routes, so it is cached and built off the UI isolate.
  static final Map<String, GtfsDayTimetable> _dayTimetables = {};
  static final Map<String, Future<GtfsDayTimetable>> _dayTimetableBuilds = {};
  static int _timetableGeneration = 0;

  /// Number of timetable builds started (tests assert on caching).
  @visibleForTesting
  static int debugTimetableBuildCount = 0;

  /// Drops cached timetables for [path] (or all of them), e.g. after the GTFS
  /// files on disk are replaced.
  static void clearTimetableCache([String? path]) {
    _timetableGeneration++;
    if (path == null) {
      _dayTimetables.clear();
      _dayTimetableBuilds.clear();
      return;
    }
    _dayTimetables.removeWhere((k, _) => k.startsWith('$path|'));
    _dayTimetableBuilds.removeWhere((k, _) => k.startsWith('$path|'));
  }

  static String _dayKey(String path, DateTime now) =>
      '$path|${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';

  static Future<GtfsDayTimetable> _dayTimetableFor(String path, DateTime now) {
    final key = _dayKey(path, now);
    final cached = _dayTimetables[key];
    if (cached != null) return Future.value(cached);
    final inFlight = _dayTimetableBuilds[key];
    if (inFlight != null) return inFlight;

    // No await between the checks above and registering the build below, so
    // concurrent callers always share one build.
    debugTimetableBuildCount++;
    final generation = _timetableGeneration;
    late final Future<GtfsDayTimetable> build;
    build = _buildOffThread(path, now).then((timetable) {
      if (generation == _timetableGeneration && timetable.totalEntries > 0) {
        _dayTimetables.removeWhere((k, _) => k.startsWith('$path|') && k != key);
        _dayTimetables[key] = timetable;
      }
      return timetable;
    }).whenComplete(() {
      if (identical(_dayTimetableBuilds[key], build)) {
        _dayTimetableBuilds.remove(key);
      }
    });
    _dayTimetableBuilds[key] = build;
    return build;
  }

  /// Static and minimal so the isolate closure captures only plain values.
  static Future<GtfsDayTimetable> _buildOffThread(String path, DateTime now) {
    var length = 0;
    try {
      final f = File(p.join(path, 'stop_times.txt'));
      if (f.existsSync()) length = f.lengthSync();
    } catch (_) {}
    return runHeavy(length, () => buildDayTimetable(path, now));
  }

  /// Scheduled trips for [modeDir] today, optionally only those serving
  /// [targetStation], soonest first (at most 100).
  static Future<List<Trip>> parseTripsFromDirectory(
    Directory modeDir, {
    Station? targetStation,
    @visibleForTesting DateTime? now,
  }) async {
    final callNow = now ?? DateTime.now();
    final timetable = await _dayTimetableFor(modeDir.path, callNow);
    if (timetable.totalEntries == 0) return [];

    final index = await GtfsIndexEngine.getOrCreateIndex(modeDir);
    final stationsById = index.stops;
    final trips = timetable.trips;
    final activeServices = timetable.activeServices;

    final hasTarget = targetStation != null && targetStation.stopId.isNotEmpty;
    final tId = hasTarget ? targetStation.stopId : '';
    final altId = hasTarget ? targetStation.id : '';

    // Candidate trips, in trips.txt order.
    final List<int> candidateIdx;
    if (hasTarget) {
      final union = <int>{
        ...?timetable.tripIdxByStopKey[tId],
        ...?timetable.tripIdxByStopKey[altId],
      }.toList()
        ..sort();
      candidateIdx = union;
    } else {
      candidateIdx = [for (var i = 0; i < trips.length; i++) i];
    }

    bool matchesMain(DayStopTime e) {
      final parent = stopParentId(e.stopId);
      return e.stopId == tId || e.stopId == altId || parent == tId || parent == altId;
    }

    bool matchesFallback(DayStopTime e) {
      final parent = e.stopId.split(_stopSuffixSplit).first.trim();
      return e.stopId == tId || e.stopId == altId || parent == tId || parent == altId;
    }

    final candidates = <_TripCandidate>[];
    for (final i in candidateIdx) {
      if (trips[i].entries.isNotEmpty) candidates.add(_TripCandidate(trips[i]));
    }
    if (candidates.isEmpty) return [];

    void resolve(
      _TripCandidate c,
      bool Function(DayStopTime) matches,
      DateTime? cutoff,
      List<_TripCandidate> out,
    ) {
      final entries = c.trip.entries;
      DayStopTime? target;
      if (hasTarget) {
        for (final e in entries) {
          if (matches(e)) {
            target = e;
            break;
          }
        }
      }
      target ??= entries.first;

      final serviceDate = activeServices[c.trip.serviceId] ?? callNow;
      final scheduled = _parseGtfsTime(target.departureTime, serviceDate);
      if (cutoff != null && scheduled.isBefore(cutoff)) return;
      out.add(c.resolved(target, serviceDate, scheduled));
    }

    final cutoff = callNow.subtract(const Duration(minutes: 1));
    var resolved = <_TripCandidate>[];
    for (final c in candidates) {
      resolve(c, matchesMain, cutoff, resolved);
    }
    if (resolved.isEmpty) {
      // Nothing left today: fall back to the soonest services regardless of
      // time, using the looser stop-id predicate.
      for (final c in candidates) {
        resolve(c, matchesFallback, null, resolved);
      }
    }

    resolved.sort((a, b) => a.scheduled!.compareTo(b.scheduled!));
    final top = resolved.take(100);

    final stationCache = <String, Station>{};
    final result = <Trip>[];
    for (final c in top) {
      result.add(_buildTrip(c, timetable, stationsById, stationCache));
    }
    return result;
  }

  static final RegExp _stopSuffixSplit = RegExp(r'[:#_\-]');

  static Trip _buildTrip(
    _TripCandidate c,
    GtfsDayTimetable timetable,
    Map<String, Station> stationsById,
    Map<String, Station> stationCache,
  ) {
    final tripInfo = c.trip;
    final entries = tripInfo.entries;
    final serviceDate = c.serviceDate!;
    final targetEntry = c.target!;

    final routeInfo = timetable.routesById[tripInfo.routeId];
    final routeName = routeInfo?.longName ?? '';
    final lineCode = (routeInfo?.shortName.isNotEmpty == true)
        ? routeInfo!.shortName
        : tripInfo.routeId;

    final fullStops = <ServiceStop>[];
    for (int i = 0; i < entries.length; i++) {
      final e = entries[i];
      final stTime = _parseGtfsTime(e.departureTime, serviceDate);
      final stationObj = stationCache.putIfAbsent(
        e.stopId,
        () => _resolveStation(e.stopId, stationsById),
      );

      fullStops.add(
        ServiceStop(
          station: stationObj,
          arrivalTime: stTime,
          departureTime: stTime,
          platform: e.platform,
          stopSequence: i + 1,
        ),
      );
    }

    final destinationTerminus = fullStops.isNotEmpty
        ? fullStops.last.station.name
        : (tripInfo.headsign.isNotEmpty
              ? GtfsIndexEngine.normalizeStationName(tripInfo.headsign)
              : routeName);

    final headsign = tripInfo.headsign.isNotEmpty
        ? GtfsIndexEngine.normalizeStationName(tripInfo.headsign)
        : destinationTerminus;

    return Trip(
      tripId: tripInfo.tripId,
      routeId: tripInfo.routeId,
      serviceId: tripInfo.serviceId,
      headsign: headsign,
      shortName: routeInfo?.shortName,
      directionId: tripInfo.directionId,
      stops: fullStops,
      departure: TripDeparture(
        scheduledTime: c.scheduled!,
        platform: targetEntry.platform,
        lineCode: lineCode,
        routeName: routeName,
        destination: destinationTerminus,
        type: routeInfo?.type ?? TransitType.bus,
      ),
    );
  }

  static Station _resolveStation(String stopId, Map<String, Station> stationsById) {
    if (stationsById.containsKey(stopId)) {
      return stationsById[stopId]!;
    }

    final parentId = stopId.split(_stopSuffixSplit).first.trim();
    if (stationsById.containsKey(parentId)) {
      return stationsById[parentId]!;
    }

    if (stopId == MelbourneGtfsService.defaultStation.stopId ||
        parentId == MelbourneGtfsService.defaultStation.stopId) {
      return MelbourneGtfsService.defaultStation;
    }

    final cleanName = GtfsIndexEngine.normalizeStationName('Station $parentId');
    return Station(
      id: parentId,
      stopId: parentId,
      name: cleanName,
      code: parentId,
      lat: 0.0,
      lon: 0.0,
      suburb: 'Melbourne',
      zone: 'Zone 1',
      routes: const [],
    );
  }

  static Future<List<Station>> parseStopsFromDirectory(
    Directory modeDir,
  ) async {
    final index = await GtfsIndexEngine.getOrCreateIndex(modeDir);
    final rawStations = index.stops.values.toList();

    final uniqueByName = <String, Station>{};
    for (final s in rawStations) {
      if (GtfsIndexEngine.isReplacementBusStop(s.name)) continue;
      final cleanName = GtfsIndexEngine.normalizeStationName(s.name);
      if (GtfsIndexEngine.isReplacementBusStop(cleanName)) continue;
      final key = cleanName.toLowerCase();
      if (!uniqueByName.containsKey(key)) {
        uniqueByName[key] = s.copyWith(name: cleanName);
      }
    }

    final stationsList = uniqueByName.values.toList();
    stationsList.sort((a, b) => a.name.compareTo(b.name));
    return stationsList;
  }

  static DateTime _parseGtfsTime(String timeStr, DateTime serviceDate) {
    final parts = timeStr.split(':');
    if (parts.length < 2) return serviceDate;

    final hours = int.tryParse(parts[0]) ?? 0;
    final minutes = int.tryParse(parts[1]) ?? 0;
    final seconds = parts.length > 2 ? (int.tryParse(parts[2]) ?? 0) : 0;

    return DateTime(
      serviceDate.year,
      serviceDate.month,
      serviceDate.day,
    ).add(Duration(hours: hours, minutes: minutes, seconds: seconds));
  }

  static Future<bool> _hasFreshCache(File routesFile) async {
    if (!await routesFile.exists()) return false;
    final modified = await routesFile.lastModified();
    return DateTime.now().difference(modified) < const Duration(days: 7);
  }


  Future<List<int>> _fetchMasterZip({GtfsProgressCallback? onProgress}) async {
    onProgress?.call(0.05, 'Connecting to PTV Feed... 5%');
    final request = http.Request('GET', masterZipUrl);
    final streamedResponse = await _client.send(request).timeout(_zipResponseTimeout);
    if (streamedResponse.statusCode != 200) {
      throw HttpException(
        'Failed to download GTFS feed (HTTP ${streamedResponse.statusCode})',
      );
    }

    final contentLength = streamedResponse.contentLength ?? 0;
    final builder = BytesBuilder(copy: false);
    int downloaded = 0;

    await for (final chunk in streamedResponse.stream.timeout(_zipIdleTimeout)) {
      builder.add(chunk);
      downloaded += chunk.length;
      if (contentLength > 0 && onProgress != null) {
        final p = (downloaded / contentLength).clamp(0.05, 0.90);
        final pct = (p * 100).toInt();
        onProgress(p, 'Streaming Feed to Memory: $pct%');
      }
    }

    onProgress?.call(0.95, 'Decompressing Archive: 95%');
    return builder.takeBytes();
  }

  Future<void> _extractModeToDirectory(
    List<int> masterBytes,
    PtvMode mode,
    Directory targetDir,
  ) async {
    if (await targetDir.exists()) {
      await targetDir.delete(recursive: true);
    }
    await targetDir.create(recursive: true);

    final masterArchive = ZipDecoder().decodeBytes(masterBytes);

    for (final file in masterArchive) {
      if (!file.isFile) continue;

      final normName = file.name.replaceAll('\\', '/');

      final isTargetMode =
          normName.startsWith('${mode.id}/') ||
          normName.contains('/${mode.id}/') ||
          normName.endsWith('/${mode.id}.zip') ||
          normName == '${mode.id}.zip';

      if (!isTargetMode) continue;

      final bytes = _getArchiveFileBytes(file);

      if (normName.endsWith('.zip')) {
        final innerArchive = ZipDecoder().decodeBytes(bytes);
        for (final innerFile in innerArchive) {
          if (innerFile.isFile) {
            final innerBytes = _getArchiveFileBytes(innerFile);
            final outFile = File(
              p.join(targetDir.path, p.basename(innerFile.name)),
            );
            await outFile.create(recursive: true);
            await outFile.writeAsBytes(innerBytes);
          }
        }
      } else if (normName.endsWith('.txt')) {
        final outFile = File(p.join(targetDir.path, p.basename(normName)));
        await outFile.create(recursive: true);
        await outFile.writeAsBytes(bytes);
      }
    }
  }

  static List<int> _getArchiveFileBytes(ArchiveFile file) {
    return file.content as List<int>;
  }

  static List<ServiceAlert> parseRealtimeServiceAlerts(List<int> bytes) {
    final feed = gtfs_rt.FeedMessage.fromBuffer(bytes);
    final alerts = <ServiceAlert>[];

    for (final entity in feed.entity) {
      if (entity.hasAlert()) {
        final alert = entity.alert;
        final headerText = alert.headerText.translation.isNotEmpty
            ? alert.headerText.translation.first.text
            : 'Melbourne Network Alert';
        final descriptionText = alert.descriptionText.translation.isNotEmpty
            ? alert.descriptionText.translation.first.text
            : '';

        final lineCode = alert.informedEntity.isNotEmpty
            ? alert.informedEntity.first.routeId
            : 'PTV Network';

        final timestampSeconds = alert.activePeriod.isNotEmpty
            ? alert.activePeriod.first.start.toInt()
            : (DateTime.now().millisecondsSinceEpoch ~/ 1000);

        alerts.add(
          ServiceAlert(
            id: entity.id,
            title: headerText,
            description: descriptionText,
            lineCode: lineCode,
            timestamp: DateTime.fromMillisecondsSinceEpoch(
              timestampSeconds * 1000,
            ),
            severity: ServiceStatus.disrupted,
          ),
        );
      }
    }

    return alerts;
  }
}

class _TripCandidate {
  final DayTrip trip;
  DayStopTime? target;
  DateTime? serviceDate;
  DateTime? scheduled;

  _TripCandidate(this.trip);

  _TripCandidate resolved(DayStopTime target, DateTime serviceDate, DateTime scheduled) =>
      _TripCandidate(trip)
        ..target = target
        ..serviceDate = serviceDate
        ..scheduled = scheduled;
}
