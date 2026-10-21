import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/gtfs_csv.dart';
import '../../domain/entities/transit_route.dart';

/// Route metadata from routes.txt.
class GtfsRouteInfo {
  final String shortName;
  final String longName;
  final TransitType type;

  const GtfsRouteInfo({
    required this.shortName,
    required this.longName,
    required this.type,
  });
}

/// One stop_times.txt row (departure time kept as the raw GTFS string).
class DayStopTime {
  final String stopId;
  final String departureTime;
  final String platform;

  const DayStopTime({
    required this.stopId,
    required this.departureTime,
    required this.platform,
  });
}

/// A trip that runs on the timetable's day, with its stop times in file order.
class DayTrip {
  final String tripId;
  String routeId;
  String serviceId;
  String headsign;
  int directionId;
  final List<DayStopTime> entries = [];

  DayTrip({
    required this.tripId,
    required this.routeId,
    required this.serviceId,
    required this.headsign,
    required this.directionId,
  });
}

/// Everything needed to answer "what departs from stop X today" for one mode,
/// built once per mode per day instead of re-parsing the GTFS files per call.
///
/// Plain data only, so it can be built on a background isolate and sent back.
class GtfsDayTimetable {
  /// service_id -> service date, for services active on the day.
  final Map<String, DateTime> activeServices;

  /// Trips in trips.txt first-seen order.
  final List<DayTrip> trips;

  /// Stop key (raw stop_id and its parent id) -> ascending indices into [trips].
  final Map<String, List<int>> tripIdxByStopKey;
  final Map<String, GtfsRouteInfo> routesById;
  final int totalEntries;

  const GtfsDayTimetable({
    required this.activeServices,
    required this.trips,
    required this.tripIdxByStopKey,
    required this.routesById,
    required this.totalEntries,
  });
}

/// The stop id up to the first `:`, `#` or `_`. Equivalent to
/// `id.split(':').first.split('#').first.split('_').first`.
String stopParentId(String id) {
  for (var i = 0; i < id.length; i++) {
    final c = id.codeUnitAt(i);
    if (c == 0x3A || c == 0x23 || c == 0x5F) return id.substring(0, i);
  }
  return id;
}

/// Parses calendar.txt / calendar_dates.txt into the services active on [now]'s date.
Future<Map<String, DateTime>> activeServiceDates(
  String dirPath,
  DateTime now,
) async {
  final serviceDate = DateTime(now.year, now.month, now.day);
  final activeServices = <String, DateTime>{};
  final calendarFile = File(p.join(dirPath, 'calendar.txt'));

  if (await calendarFile.exists()) {
    final lines = (await calendarFile.readAsString()).split(RegExp(r'\r?\n'));
    if (lines.isNotEmpty) {
      final headers = parseGtfsCsvRow(lines.first);
      final serviceIdIdx = headers.indexOf('service_id');
      final startDateIdx = headers.indexOf('start_date');
      final endDateIdx = headers.indexOf('end_date');
      final weekdayIdx = headers.indexOf(_weekdayColumn(serviceDate.weekday));

      for (final line in lines.skip(1)) {
        final columns = parseGtfsCsvRow(line);
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

  final exceptionsFile = File(p.join(dirPath, 'calendar_dates.txt'));
  if (!await exceptionsFile.exists()) return activeServices;

  final lines = (await exceptionsFile.readAsString()).split(RegExp(r'\r?\n'));
  if (lines.isEmpty) return activeServices;

  final headers = parseGtfsCsvRow(lines.first);
  final serviceIdIdx = headers.indexOf('service_id');
  final dateIdx = headers.indexOf('date');
  final exceptionTypeIdx = headers.indexOf('exception_type');

  for (final line in lines.skip(1)) {
    final columns = parseGtfsCsvRow(line);
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

String _weekdayColumn(int weekday) => const [
      'monday',
      'tuesday',
      'wednesday',
      'thursday',
      'friday',
      'saturday',
      'sunday',
    ][weekday - 1];

DateTime? _dateAt(List<String> columns, int index) {
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

Stream<String> _lines(File file) =>
    file.openRead().transform(utf8.decoder).transform(const LineSplitter());

/// Reads [file] as CSV, handing each data row (with the header row) to [onRow].
Future<void> _forEachRow(
  File file,
  void Function(List<String> headers, List<String> row) onRow,
) async {
  List<String>? headers;
  await _lines(file).forEach((line) {
    if (line.isEmpty) return;
    final row = parseGtfsCsvRow(line);
    final h = headers;
    if (h == null) {
      headers = row;
    } else {
      onRow(h, row);
    }
  });
}

/// Builds the [GtfsDayTimetable] for the GTFS files in [dirPath] on [now]'s date.
///
/// Top-level and free of captured state so it can run on a background isolate.
Future<GtfsDayTimetable> buildDayTimetable(String dirPath, DateTime now) async {
  final activeServices = await activeServiceDates(dirPath, now);

  // --- trips.txt: only trips running today, in first-seen order. ---
  final trips = <DayTrip>[];
  final idxByTripId = <String, int>{};
  final tripsFile = File(p.join(dirPath, 'trips.txt'));
  if (await tripsFile.exists()) {
    int? routeIdIdx, serviceIdIdx, tripIdIdx, headsignIdx, directionIdIdx;
    await _forEachRow(tripsFile, (headers, cols) {
      routeIdIdx ??= headers.indexOf('route_id');
      serviceIdIdx ??= headers.indexOf('service_id');
      tripIdIdx ??= headers.indexOf('trip_id');
      headsignIdx ??= headers.indexOf('trip_headsign');
      directionIdIdx ??= headers.indexOf('direction_id');
      if (tripIdIdx == -1 || cols.length <= tripIdIdx!) return;

      final tripId = cols[tripIdIdx!];
      final routeId =
          (routeIdIdx != -1 && cols.length > routeIdIdx!) ? cols[routeIdIdx!] : '';
      final serviceId = (serviceIdIdx != -1 && cols.length > serviceIdIdx!)
          ? cols[serviceIdIdx!]
          : '';
      if (activeServices.isNotEmpty && !activeServices.containsKey(serviceId)) {
        return;
      }
      final headsign = (headsignIdx != -1 && cols.length > headsignIdx!)
          ? cols[headsignIdx!]
          : '';
      final directionId = (directionIdIdx != -1 && cols.length > directionIdIdx!)
          ? int.tryParse(cols[directionIdIdx!]) ?? 0
          : 0;

      final existing = idxByTripId[tripId];
      if (existing != null) {
        // A later duplicate overwrites the fields but keeps its position.
        final t = trips[existing];
        t.routeId = routeId;
        t.serviceId = serviceId;
        t.headsign = headsign;
        t.directionId = directionId;
      } else {
        idxByTripId[tripId] = trips.length;
        trips.add(DayTrip(
          tripId: tripId,
          routeId: routeId,
          serviceId: serviceId,
          headsign: headsign,
          directionId: directionId,
        ));
      }
    });
  }

  // --- stop_times.txt: attach rows to today's trips only. ---
  var totalEntries = 0;
  final stopTimesFile = File(p.join(dirPath, 'stop_times.txt'));
  if (idxByTripId.isNotEmpty && await stopTimesFile.exists()) {
    final interned = <String, String>{};
    String intern(String s) => interned.putIfAbsent(s, () => s);

    List<String>? headers;
    int tripIdIdx = -1, depIdx = -1, arrIdx = -1, stopIdIdx = -1, platIdx = -1;
    var tripIdIsFirstColumn = false;

    await _lines(stopTimesFile).forEach((line) {
      if (line.isEmpty) return;
      if (headers == null) {
        final h = parseGtfsCsvRow(line);
        headers = h;
        tripIdIdx = h.indexOf('trip_id');
        arrIdx = h.indexOf('arrival_time');
        depIdx = h.indexOf('departure_time');
        stopIdIdx = h.indexOf('stop_id');
        platIdx = h.indexOf('platform_code');
        tripIdIsFirstColumn = tripIdIdx == 0;
        return;
      }

      // Cheap pre-filter: skip rows of trips not running today without
      // parsing the whole line.
      if (tripIdIsFirstColumn) {
        final comma = line.indexOf(',');
        final head = comma == -1 ? line : line.substring(0, comma);
        if (!head.contains('"') && !idxByTripId.containsKey(head.trim())) {
          return;
        }
      }

      final cols = parseGtfsCsvRow(line);
      if (tripIdIdx == -1 || cols.length <= tripIdIdx) return;
      final tripIdx = idxByTripId[cols[tripIdIdx]];
      if (tripIdx == null) return;

      final stopId =
          (stopIdIdx != -1 && cols.length > stopIdIdx) ? cols[stopIdIdx] : '';
      final depTimeStr = (depIdx != -1 && cols.length > depIdx)
          ? cols[depIdx]
          : ((arrIdx != -1 && cols.length > arrIdx) ? cols[arrIdx] : '00:00:00');
      final platform =
          (platIdx != -1 && cols.length > platIdx) ? cols[platIdx] : '';

      trips[tripIdx].entries.add(DayStopTime(
        stopId: intern(stopId),
        departureTime: intern(depTimeStr),
        platform: intern(platform),
      ));
      totalEntries++;
    });
  }

  // --- index trips by every stop they serve (raw id and parent id). ---
  final byStop = <String, List<int>>{};
  void add(String key, int idx) {
    final list = byStop.putIfAbsent(key, () => []);
    if (list.isEmpty || list.last != idx) list.add(idx);
  }

  for (var i = 0; i < trips.length; i++) {
    for (final e in trips[i].entries) {
      add(e.stopId, i);
      add(stopParentId(e.stopId), i);
    }
  }

  // --- routes.txt ---
  final routes = <String, GtfsRouteInfo>{};
  final routesFile = File(p.join(dirPath, 'routes.txt'));
  if (await routesFile.exists()) {
    int? routeIdIdx, shortNameIdx, longNameIdx, routeTypeIdx;
    await _forEachRow(routesFile, (headers, cols) {
      routeIdIdx ??= headers.indexOf('route_id');
      shortNameIdx ??= headers.indexOf('route_short_name');
      longNameIdx ??= headers.indexOf('route_long_name');
      routeTypeIdx ??= headers.indexOf('route_type');
      if (routeIdIdx == -1 || cols.length <= routeIdIdx!) return;

      final routeId = cols[routeIdIdx!];
      final shortName = (shortNameIdx != -1 && cols.length > shortNameIdx!)
          ? cols[shortNameIdx!]
          : routeId;
      final longName = (longNameIdx != -1 && cols.length > longNameIdx!)
          ? cols[longNameIdx!]
          : shortName;
      final routeTypeInt = (routeTypeIdx != -1 && cols.length > routeTypeIdx!)
          ? int.tryParse(cols[routeTypeIdx!]) ?? 3
          : 3;

      routes[routeId] = GtfsRouteInfo(
        shortName: shortName,
        longName: longName,
        type: TransitRoute.fromGtfsRouteType(routeTypeInt),
      );
    });
  }

  return GtfsDayTimetable(
    activeServices: activeServices,
    trips: trips,
    tripIdxByStopKey: byStop,
    routesById: routes,
    totalEntries: totalEntries,
  );
}
