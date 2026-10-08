import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:gtfs_bindings/schedule.dart' as gtfs;
import 'package:gtfs_realtime_bindings/gtfs_realtime_bindings.dart' as gtfs_rt;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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

  static Future<List<Trip>> parseTripsFromDirectory(
    Directory modeDir, {
    Station? targetStation,
  }) async {
    final now = DateTime.now();
    final activeServices = await _activeServiceDates(modeDir, now);

    final index = await GtfsIndexEngine.getOrCreateIndex(modeDir);
    final stationsById = index.stops;

    final allStopTimes = await _parseAllStopTimesMap(modeDir);
    if (allStopTimes.isEmpty) return [];

    final targetTripIds = <String>{};
    if (targetStation != null && targetStation.stopId.isNotEmpty) {
      final tId = targetStation.stopId;
      final altId = targetStation.id;
      allStopTimes.forEach((tripId, entries) {
        if (entries.any((e) {
          final parentE = e.stopId.split(':').first.split('#').first.split('_').first;
          return e.stopId == tId || e.stopId == altId || parentE == tId || parentE == altId;
        })) {
          targetTripIds.add(tripId);
        }
      });
    } else {
      targetTripIds.addAll(allStopTimes.keys);
    }

    if (targetTripIds.isEmpty) return [];

    final tripsById = await _parseTripsMap(
      modeDir,
      tripIds: targetTripIds,
      activeServices: activeServices,
    );
    if (tripsById.isEmpty) return [];

    final routeIds = tripsById.values.map((trip) => trip.routeId).toSet();
    final routesById = await _parseRoutesMap(modeDir, routeIds: routeIds);

    final scheduledTrips = <Trip>[];
    final cutoffTime = now.subtract(const Duration(minutes: 1));

    for (final tripId in tripsById.keys) {
      final tripInfo = tripsById[tripId];
      final entries = allStopTimes[tripId];
      if (tripInfo == null || entries == null || entries.isEmpty) continue;

      _GtfsStopTimeEntry? targetEntry;
      if (targetStation != null && targetStation.stopId.isNotEmpty) {
        final tId = targetStation.stopId;
        final altId = targetStation.id;
        for (final e in entries) {
          final parentE = e.stopId.split(':').first.split('#').first.split('_').first;
          if (e.stopId == tId || e.stopId == altId || parentE == tId || parentE == altId) {
            targetEntry = e;
            break;
          }
        }
      }
      targetEntry ??= entries.first;

      final serviceDate = activeServices[tripInfo.serviceId] ?? now;
      final scheduledTime = _parseGtfsTime(
        targetEntry.departureTime,
        serviceDate,
      );
      if (scheduledTime.isBefore(cutoffTime)) continue;

      final routeInfo = routesById[tripInfo.routeId];
      final routeName = routeInfo?.longName ?? '';
      final lineCode = (routeInfo?.shortName.isNotEmpty == true)
          ? routeInfo!.shortName
          : tripInfo.routeId;

      final fullStops = <ServiceStop>[];
      for (int i = 0; i < entries.length; i++) {
        final e = entries[i];
        final stTime = _parseGtfsTime(e.departureTime, serviceDate);
        final stationObj = _resolveStation(e.stopId, stationsById);

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

      scheduledTrips.add(
        Trip(
          tripId: tripId,
          routeId: tripInfo.routeId,
          serviceId: tripInfo.serviceId,
          headsign: headsign,
          shortName: routeInfo?.shortName,
          directionId: tripInfo.directionId,
          stops: fullStops,
          departure: TripDeparture(
            scheduledTime: scheduledTime,
            platform: targetEntry.platform,
            lineCode: lineCode,
            routeName: routeName,
            destination: destinationTerminus,
            type: routeInfo?.type ?? TransitType.bus,
          ),
        ),
      );
    }

    scheduledTrips.sort(
      (a, b) =>
          a.departure!.scheduledTime.compareTo(b.departure!.scheduledTime),
    );

    if (scheduledTrips.isEmpty && tripsById.isNotEmpty) {
      for (final tripId in tripsById.keys) {
        final tripInfo = tripsById[tripId];
        final entries = allStopTimes[tripId];
        if (tripInfo == null || entries == null || entries.isEmpty) continue;

        _GtfsStopTimeEntry? targetEntry;
        if (targetStation != null && targetStation.stopId.isNotEmpty) {
          final tId = targetStation.stopId;
          final altId = targetStation.id;
          for (final e in entries) {
            final parentE = e.stopId.split(RegExp(r'[:#_\-]')).first.trim();
            if (e.stopId == tId || e.stopId == altId || parentE == tId || parentE == altId) {
              targetEntry = e;
              break;
            }
          }
        }
        targetEntry ??= entries.first;

        final serviceDate = activeServices[tripInfo.serviceId] ?? now;
        final scheduledTime = _parseGtfsTime(
          targetEntry.departureTime,
          serviceDate,
        );

        final routeInfo = routesById[tripInfo.routeId];
        final routeName = routeInfo?.longName ?? '';
        final lineCode = (routeInfo?.shortName.isNotEmpty == true)
            ? routeInfo!.shortName
            : tripInfo.routeId;

        final fullStops = <ServiceStop>[];
        for (int i = 0; i < entries.length; i++) {
          final e = entries[i];
          final stTime = _parseGtfsTime(e.departureTime, serviceDate);
          final stationObj = _resolveStation(e.stopId, stationsById);

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

        scheduledTrips.add(
          Trip(
            tripId: tripId,
            routeId: tripInfo.routeId,
            serviceId: tripInfo.serviceId,
            headsign: headsign,
            shortName: routeInfo?.shortName,
            directionId: tripInfo.directionId,
            stops: fullStops,
            departure: TripDeparture(
              scheduledTime: scheduledTime,
              platform: targetEntry.platform,
              lineCode: lineCode,
              routeName: routeName,
              destination: destinationTerminus,
              type: routeInfo?.type ?? TransitType.bus,
            ),
          ),
        );
      }

      scheduledTrips.sort(
        (a, b) =>
            a.departure!.scheduledTime.compareTo(b.departure!.scheduledTime),
      );
    }

    return scheduledTrips.take(100).toList();
  }

  static Station _resolveStation(String stopId, Map<String, Station> stationsById) {
    if (stationsById.containsKey(stopId)) {
      return stationsById[stopId]!;
    }

    final parentId = stopId.split(RegExp(r'[:#_\-]')).first.trim();
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

  static Future<Map<String, DateTime>> _activeServiceDates(
    Directory modeDir,
    DateTime now,
  ) async {
    final serviceDate = DateTime(now.year, now.month, now.day);
    final activeServices = <String, DateTime>{};
    final calendarFile = File(p.join(modeDir.path, 'calendar.txt'));

    if (await calendarFile.exists()) {
      final lines = (await calendarFile.readAsString()).split(RegExp(r'\r?\n'));
      if (lines.isNotEmpty) {
        final headers = _parseCsvRow(lines.first);
        final serviceIdIdx = headers.indexOf('service_id');
        final startDateIdx = headers.indexOf('start_date');
        final endDateIdx = headers.indexOf('end_date');
        final weekdayIdx = headers.indexOf(_weekdayColumn(serviceDate.weekday));

        for (final line in lines.skip(1)) {
          final columns = _parseCsvRow(line);
          if (serviceIdIdx == -1 || columns.length <= serviceIdIdx) continue;
          if (weekdayIdx == -1 ||
              columns.length <= weekdayIdx ||
              columns[weekdayIdx] != '1') {
            continue;
          }

          final startDate = _dateAt(columns, startDateIdx);
          final endDate = _dateAt(columns, endDateIdx);
          if ((startDate == null || !serviceDate.isBefore(startDate)) &&
              (endDate == null || !serviceDate.isAfter(endDate))) {
            activeServices[columns[serviceIdIdx]] = serviceDate;
          }
        }
      }
    }

    final exceptionsFile = File(p.join(modeDir.path, 'calendar_dates.txt'));
    if (!await exceptionsFile.exists()) return activeServices;

    final lines = (await exceptionsFile.readAsString()).split(RegExp(r'\r?\n'));
    if (lines.isEmpty) return activeServices;

    final headers = _parseCsvRow(lines.first);
    final serviceIdIdx = headers.indexOf('service_id');
    final dateIdx = headers.indexOf('date');
    final exceptionTypeIdx = headers.indexOf('exception_type');

    for (final line in lines.skip(1)) {
      final columns = _parseCsvRow(line);
      if (serviceIdIdx == -1 || dateIdx == -1 || exceptionTypeIdx == -1) {
        continue;
      }
      if (columns.length <= serviceIdIdx ||
          columns.length <= dateIdx ||
          columns.length <= exceptionTypeIdx ||
          _dateAt(columns, dateIdx) != serviceDate) {
        continue;
      }

      final serviceId = columns[serviceIdIdx];
      if (columns[exceptionTypeIdx] == '1') {
        activeServices[serviceId] = serviceDate;
      } else if (columns[exceptionTypeIdx] == '2') {
        activeServices.remove(serviceId);
      }
    }

    return activeServices;
  }

  static String _weekdayColumn(int weekday) => const [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ][weekday - 1];

  static DateTime? _dateAt(List<String> columns, int index) {
    if (index == -1 || columns.length <= index || columns[index].length != 8) {
      return null;
    }

    final value = columns[index];
    final year = int.tryParse(value.substring(0, 4));
    final month = int.tryParse(value.substring(4, 6));
    final day = int.tryParse(value.substring(6, 8));
    if (year == null || month == null || day == null) return null;
    return DateTime(year, month, day);
  }

  static Future<Map<String, _GtfsRouteInfo>> _parseRoutesMap(
    Directory modeDir, {
    Set<String>? routeIds,
  }) async {
    final routesFile = File(p.join(modeDir.path, 'routes.txt'));
    if (!await routesFile.exists()) return {};

    final map = <String, _GtfsRouteInfo>{};
    int? routeIdIdx;
    int? shortNameIdx;
    int? longNameIdx;
    int? routeTypeIdx;

    await _forEachCsvRow(routesFile, (headers, cols) {
      routeIdIdx ??= headers.indexOf('route_id');
      shortNameIdx ??= headers.indexOf('route_short_name');
      longNameIdx ??= headers.indexOf('route_long_name');
      routeTypeIdx ??= headers.indexOf('route_type');
      if (routeIdIdx == -1 || cols.length <= routeIdIdx!) return;

      final routeId = cols[routeIdIdx!];
      if (routeIds != null && !routeIds.contains(routeId)) return;
      final shortName = (shortNameIdx != -1 && cols.length > shortNameIdx!)
          ? cols[shortNameIdx!]
          : routeId;
      final longName = (longNameIdx != -1 && cols.length > longNameIdx!)
          ? cols[longNameIdx!]
          : shortName;
      final routeTypeInt = (routeTypeIdx != -1 && cols.length > routeTypeIdx!)
          ? int.tryParse(cols[routeTypeIdx!]) ?? 3
          : 3;

      final type = TransitRoute.fromGtfsRouteType(routeTypeInt);
      map[routeId] = _GtfsRouteInfo(
        shortName: shortName,
        longName: longName,
        type: type,
      );
    });

    return map;
  }

  static Future<Map<String, _GtfsTripInfo>> _parseTripsMap(
    Directory modeDir, {
    required Set<String> tripIds,
    required Map<String, DateTime> activeServices,
  }) async {
    final tripsFile = File(p.join(modeDir.path, 'trips.txt'));
    if (!await tripsFile.exists()) return {};

    final map = <String, _GtfsTripInfo>{};
    int? routeIdIdx;
    int? serviceIdIdx;
    int? tripIdIdx;
    int? headsignIdx;
    int? directionIdIdx;

    await _forEachCsvRow(tripsFile, (headers, cols) {
      routeIdIdx ??= headers.indexOf('route_id');
      serviceIdIdx ??= headers.indexOf('service_id');
      tripIdIdx ??= headers.indexOf('trip_id');
      headsignIdx ??= headers.indexOf('trip_headsign');
      directionIdIdx ??= headers.indexOf('direction_id');
      if (tripIdIdx == -1 || cols.length <= tripIdIdx!) return;

      final tripId = cols[tripIdIdx!];
      if (!tripIds.contains(tripId)) return;
      final routeId = (routeIdIdx != -1 && cols.length > routeIdIdx!)
          ? cols[routeIdIdx!]
          : '';
      final serviceId = (serviceIdIdx != -1 && cols.length > serviceIdIdx!)
          ? cols[serviceIdIdx!]
          : '';
      if (activeServices.isNotEmpty && !activeServices.containsKey(serviceId)) {
        return;
      }
      final headsign = (headsignIdx != -1 && cols.length > headsignIdx!)
          ? cols[headsignIdx!]
          : '';
      final directionId =
          (directionIdIdx != -1 && cols.length > directionIdIdx!)
          ? int.tryParse(cols[directionIdIdx!]) ?? 0
          : 0;

      map[tripId] = _GtfsTripInfo(
        routeId: routeId,
        serviceId: serviceId,
        headsign: headsign,
        directionId: directionId,
      );
    });

    return map;
  }

  static Future<Map<String, List<_GtfsStopTimeEntry>>> _parseAllStopTimesMap(
    Directory modeDir,
  ) async {
    final stopTimesFile = File(p.join(modeDir.path, 'stop_times.txt'));
    if (!await stopTimesFile.exists()) return {};

    final map = <String, List<_GtfsStopTimeEntry>>{};
    int? tripIdIdx;
    int? arrivalTimeIdx;
    int? departureTimeIdx;
    int? stopIdIdx;
    int? platformIdx;

    await _forEachCsvRow(stopTimesFile, (headers, cols) {
      tripIdIdx ??= headers.indexOf('trip_id');
      arrivalTimeIdx ??= headers.indexOf('arrival_time');
      departureTimeIdx ??= headers.indexOf('departure_time');
      stopIdIdx ??= headers.indexOf('stop_id');
      platformIdx ??= headers.indexOf('platform_code');
      if (tripIdIdx == -1 || cols.length <= tripIdIdx!) return;

      final tripId = cols[tripIdIdx!];
      final stopId = (stopIdIdx != -1 && cols.length > stopIdIdx!)
          ? cols[stopIdIdx!]
          : '';

      final depTimeStr =
          (departureTimeIdx != -1 && cols.length > departureTimeIdx!)
          ? cols[departureTimeIdx!]
          : ((arrivalTimeIdx != -1 && cols.length > arrivalTimeIdx!)
                ? cols[arrivalTimeIdx!]
                : '00:00:00');

      final platform = (platformIdx != -1 && cols.length > platformIdx!)
          ? cols[platformIdx!]
          : '';

      map.putIfAbsent(tripId, () => []).add(
            _GtfsStopTimeEntry(
              tripId: tripId,
              stopId: stopId,
              departureTime: depTimeStr,
              platform: platform,
            ),
          );
    });

    return map;
  }

  static Future<void> _forEachCsvRow(
    File file,
    void Function(List<String> headers, List<String> row) onRow,
  ) async {
    List<String>? headers;
    final lines = file
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final line in lines) {
      if (line.isEmpty) continue;
      final row = _parseCsvRow(line);
      if (headers == null) {
        headers = row;
      } else {
        onRow(headers, row);
      }
    }
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

  static List<String> _parseCsvRow(String line) {
    final values = <String>[];
    final buffer = StringBuffer();
    bool inQuotes = false;

    for (int i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        inQuotes = !inQuotes;
      } else if (char == ',' && !inQuotes) {
        values.add(buffer.toString().trim().replaceAll('"', ''));
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    values.add(buffer.toString().trim().replaceAll('"', ''));
    return values;
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

class _GtfsRouteInfo {
  final String shortName;
  final String longName;
  final TransitType type;

  const _GtfsRouteInfo({
    required this.shortName,
    required this.longName,
    required this.type,
  });
}

class _GtfsTripInfo {
  final String routeId;
  final String serviceId;
  final String headsign;
  final int directionId;

  const _GtfsTripInfo({
    required this.routeId,
    this.serviceId = '',
    required this.headsign,
    this.directionId = 0,
  });
}

class _GtfsStopTimeEntry {
  final String tripId;
  final String stopId;
  final String departureTime;
  final String platform;

  const _GtfsStopTimeEntry({
    required this.tripId,
    required this.stopId,
    required this.departureTime,
    required this.platform,
  });
}
