import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import '../core/heavy_work.dart';
import '../domain/entities/service.dart';
import '../domain/entities/transit_route.dart';
import '../domain/entities/station.dart';
import '../domain/entities/trips.dart';

class EnvService {
  static String _userId = const String.fromEnvironment('PTV_USER_ID', defaultValue: '3003979');
  static String _apiKey = const String.fromEnvironment('PTV_API_KEY', defaultValue: '75e01f6e-339a-4a01-ab13-b7524490ec83');
  static String _baseUrl = const String.fromEnvironment('PTV_BASE_URL', defaultValue: 'https://timetableapi.ptv.vic.gov.au');

  static String get userId => _userId;
  static String get apiKey => _apiKey;
  static String get baseUrl => _baseUrl;
  static bool get isConfigured => userId.isNotEmpty && apiKey.isNotEmpty;

  static void setCredentials({
    required String userId,
    required String apiKey,
    String? baseUrl,
  }) {
    _userId = userId;
    _apiKey = apiKey;
    if (baseUrl != null) _baseUrl = baseUrl;
  }

  static Future<void> loadEnv() async {
    String? envString;
    try {
      envString = await rootBundle.loadString('.env');
    } catch (_) {
      try {
        envString = await rootBundle.loadString('assets/.env');
      } catch (_) {}
    }

    if (envString != null && envString.isNotEmpty) {
      final lines = const LineSplitter().convert(envString);
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
        final parts = trimmed.split('=');
        if (parts.length >= 2) {
          final key = parts[0].trim();
          final val = parts.sublist(1).join('=').trim();
          if (key == 'PTV_USER_ID' && val.isNotEmpty) _userId = val;
          if (key == 'PTV_API_KEY' && val.isNotEmpty) _apiKey = val;
          if (key == 'PTV_BASE_URL' && val.isNotEmpty) _baseUrl = val;
        }
      }
    }
  }
}

class PtvRealtimeService {
  final http.Client _client;
  final Duration _responseTimeout;
  final Duration _idleTimeout;
  final Map<String, String> _resolvedStopIdCache = {};

  static final RegExp _numericStopIdRegex = RegExp(r'^\d{3,5}$');

  /// Disruptions change slowly; reuse a recent result across refresh cycles.
  static const Duration _disruptionsTtl = Duration(seconds: 60);
  List<ServiceAlert>? _cachedDisruptions;
  Future<List<ServiceAlert>>? _disruptionsInFlight;

  /// Disruption buckets the app shows: metro train/tram, V/Line and network-wide
  /// notices. Bus, coach, ferry and similar buckets are skipped.
  static const Set<String> _relevantDisruptionModes = {
    'metro_train',
    'metro_tram',
    'regional_train',
    'general',
  };
  DateTime? _disruptionsFetchedAt;

  static const Map<String, String> _defaultHeaders = {
    'Accept': 'application/json',
    'User-Agent': 'Mozilla/5.0 (Linux; Android) TransitApp/1.0',
  };

  /// [responseTimeout] bounds the wait for response headers; [idleTimeout]
  /// bounds the gap between body chunks. There is deliberately no total
  /// timeout so large bodies on slow links can still complete.
  PtvRealtimeService({
    http.Client? client,
    this._responseTimeout = const Duration(seconds: 15),
    this._idleTimeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client();

  /// GET [signedUrl] with a response-header timeout and a per-chunk idle
  /// timeout. Equivalent to `Client.get` + `Response.fromStream` otherwise.
  Future<http.Response> _get(String signedUrl) async {
    final request = http.Request('GET', Uri.parse(signedUrl))
      ..headers.addAll(_defaultHeaders);
    final streamed = await _client.send(request).timeout(_responseTimeout);
    final bytes =
        await http.ByteStream(streamed.stream.timeout(_idleTimeout)).toBytes();
    return http.Response.bytes(
      bytes,
      streamed.statusCode,
      request: streamed.request,
      headers: streamed.headers,
      isRedirect: streamed.isRedirect,
      persistentConnection: streamed.persistentConnection,
      reasonPhrase: streamed.reasonPhrase,
    );
  }

  static String generateSignedUrl(String requestPath) {
    final devId = EnvService.userId;
    final key = EnvService.apiKey;
    final uriWithDevId = requestPath.contains('?')
        ? '$requestPath&devid=$devId'
        : '$requestPath?devid=$devId';

    final hmac = Hmac(sha1, utf8.encode(key));
    final digest = hmac.convert(utf8.encode(uriWithDevId));
    final signature = digest.toString().toUpperCase();

    return '${EnvService.baseUrl}$uriWithDevId&signature=$signature';
  }

  static String _resolverCleanName(Station station) => station.name
      .toLowerCase()
      .replaceAll(' railway station', '')
      .replaceAll(' station', '')
      .trim();

  /// Whether [stopId] is already a valid PTV API stop id for [routeType], so no
  /// search request is needed to resolve it.
  ///
  /// For tram stops (routeType 1), valid PTV stop IDs are in the 2001-3500 range.
  /// The 19xx/20xx/22xx rejection is only for metro train GTFS platform IDs.
  static bool isDirectStopId(String stopId, int routeType) {
    if (!_numericStopIdRegex.hasMatch(stopId)) return false;
    final idInt = int.tryParse(stopId) ?? 0;
    if (routeType == 1) {
      return idInt >= 2001 && idInt <= 3500;
    }
    return !stopId.startsWith('19') &&
        !stopId.startsWith('20') &&
        !stopId.startsWith('22');
  }

  /// Network-free lookup of the stop id [resolveStopIdForStation] would return
  /// without a search request, or null when a request would be needed.
  String? peekResolvedStopId(Station station, {int routeType = 0}) {
    final hit = _resolvedStopIdCache['$routeType:${_resolverCleanName(station)}'];
    if (hit != null) return hit;
    return isDirectStopId(station.stopId, routeType) ? station.stopId : null;
  }

  /// Dynamically resolves the official PTV API v3 numeric stop ID for a given station.
  Future<String> resolveStopIdForStation(Station station, {int routeType = 0}) async {
    final cleanName = _resolverCleanName(station);

    // Cache key includes routeType to prevent train/tram ID collisions for stations
    // sharing a name (e.g. "Flinders Street" is stop 1071 for trains, 2722 for trams)
    final cacheKey = '$routeType:$cleanName';

    if (_resolvedStopIdCache.containsKey(cacheKey)) {
      return _resolvedStopIdCache[cacheKey]!;
    }

    // For tram stops (routeType 1), valid PTV stop IDs are in the 2001-3418 range.
    // Do NOT apply the 19xx/20xx/22xx rejection that was intended only for metro train
    // GTFS internal platform IDs. For trains (routeType 0), keep the existing guard.
    if (isDirectStopId(station.stopId, routeType)) {
      _resolvedStopIdCache[cacheKey] = station.stopId;
      return station.stopId;
    }

    if (!EnvService.isConfigured) return station.stopId;

    try {
      String searchQuery = cleanName;
      if (routeType == 1) {
        // Strip stop number '#\d+' and simplify query for PTV API search
        searchQuery = cleanName.replaceAll(RegExp(r'#\s*\d+[a-zA-Z]?'), '').replaceAll('/', ' ').trim();
        // If multi-word intersection, search by the first distinct street name
        if (cleanName.contains('/')) {
          final parts = cleanName.split('/');
          if (parts.isNotEmpty && parts[0].trim().length > 3) {
            searchQuery = parts[0].replaceAll(RegExp(r'#\s*\d+[a-zA-Z]?'), '').trim();
          }
        }
      }

      final searchResults = await searchStations(searchQuery, routeType: routeType);
      if (searchResults.isNotEmpty) {
        // Find exact or closest match, respecting stop number/code if present
        final stopNumMatch = RegExp(r'#\s*(\d+[a-zA-Z]?)').firstMatch(station.name);
        final targetCode = stopNumMatch?.group(1) ?? station.code;

        final exactMatch = searchResults.firstWhere(
          (s) {
            final sClean = s.name.toLowerCase().replaceAll(' station', '').trim();
            final matchesCode = targetCode.isNotEmpty && (s.code == targetCode || s.name.contains('#$targetCode'));
            final matchesName = sClean == cleanName;
            return matchesCode && (matchesName || sClean.contains(cleanName) || cleanName.contains(sClean));
          },
          orElse: () => searchResults.firstWhere(
            (s) => s.name.toLowerCase().replaceAll(' station', '').trim() == cleanName,
            orElse: () => searchResults.firstWhere(
              (s) => s.name.toLowerCase().contains(cleanName) || cleanName.contains(s.name.toLowerCase()),
              orElse: () => searchResults.first,
            ),
          ),
        );
        _resolvedStopIdCache[cacheKey] = exactMatch.stopId;
        return exactMatch.stopId;
      }
    } catch (_) {
      // Fallback
    }

    return station.stopId;
  }

  Future<List<ServiceAlert>> fetchLiveDisruptions() async {
    if (!EnvService.isConfigured) return [];

    final fetchedAt = _disruptionsFetchedAt;
    final cached = _cachedDisruptions;
    if (cached != null &&
        fetchedAt != null &&
        DateTime.now().difference(fetchedAt) < _disruptionsTtl) {
      return cached;
    }

    // Share one download between concurrent callers.
    final inFlight = _disruptionsInFlight;
    if (inFlight != null) return inFlight;

    final download = _downloadDisruptions();
    _disruptionsInFlight = download;
    try {
      return await download;
    } finally {
      if (identical(_disruptionsInFlight, download)) {
        _disruptionsInFlight = null;
      }
    }
  }

  Future<List<ServiceAlert>> _downloadDisruptions() async {
    final signedUrl = generateSignedUrl('/v3/disruptions');
    try {
      final response = await _get(signedUrl);
      if (response.statusCode != 200) return [];

      final body = response.body;
      final data = await runHeavy<Map<String, dynamic>>(
        body.length,
        () => json.decode(body) as Map<String, dynamic>,
      );
      final disruptionsObj = data['disruptions'] as Map<String, dynamic>?;
      if (disruptionsObj == null) return [];

      final alerts = <ServiceAlert>[];
      disruptionsObj.forEach((modeKey, list) {
        if (!_relevantDisruptionModes.contains(modeKey)) return;
        if (list is List) {
          for (final item in list) {
            if (item is Map<String, dynamic>) {
              final id = item['disruption_id']?.toString() ?? '';
              final title = item['title']?.toString() ?? 'PTV Service Alert';
              final desc = item['description']?.toString() ?? '';
              final routes = item['routes'] as List?;
              final lineCode = (routes != null && routes.isNotEmpty)
                  ? (routes.first['route_short_name'] ??
                          routes.first['route_name'] ??
                          'Metro Network')
                      .toString()
                  : 'Metro Network';

              alerts.add(
                ServiceAlert(
                  id: id,
                  title: title,
                  description: desc,
                  lineCode: lineCode,
                  timestamp: DateTime.now(),
                  severity: ServiceStatus.disrupted,
                ),
              );
            }
          }
        }
      });
      _cachedDisruptions = alerts;
      _disruptionsFetchedAt = DateTime.now();
      return alerts;
    } catch (_) {
      return [];
    }
  }

  Future<List<Station>> searchStations(String query, {int routeType = 0}) async {
    if (query.trim().isEmpty || !EnvService.isConfigured) return [];

    final encodedQuery = Uri.encodeComponent(query.trim());
    // Pass route_types to ensure search results are scoped to the right mode
    final signedUrl = generateSignedUrl('/v3/search/$encodedQuery?route_types=$routeType');

    try {
      final response = await _get(signedUrl);
      if (response.statusCode != 200) return [];

      final data = json.decode(response.body) as Map<String, dynamic>;
      final stops = data['stops'] as List?;
      if (stops == null) return [];

      final stations = <Station>[];
      for (final stop in stops) {
        if (stop is Map<String, dynamic>) {
          final name = stop['stop_name']?.toString() ?? '';
          if (!name.toLowerCase().contains('replacement bus')) {
            stations.add(Station.fromPtv(stop, routeType: routeType));
          }
        }
      }
      return stations;
    } catch (_) {
      return [];
    }
  }

  Future<List<Trip>> fetchDepartures(
    String stopId, {
    int routeType = 0,
    int maxResults = 30,
    Station? station,
  }) async {
    if (!EnvService.isConfigured) return [];

    String numericStopId = stopId;
    if (station != null) {
      numericStopId = await resolveStopIdForStation(station, routeType: routeType);
    } else if (!_numericStopIdRegex.hasMatch(stopId)) {
      final tempStation = Station(
        id: stopId,
        stopId: stopId,
        name: stopId,
        code: stopId,
        lat: 0,
        lon: 0,
        suburb: '',
        zone: 'Zone 1',
        routes: const [],
      );
      numericStopId = await resolveStopIdForStation(tempStation, routeType: routeType);
    }

    final signedUrl = generateSignedUrl(
      '/v3/departures/route_type/$routeType/stop/$numericStopId?max_results=$maxResults&expand=all',
    );

    try {
      final response = await _get(signedUrl);
      if (response.statusCode != 200) return [];

      final data = json.decode(response.body) as Map<String, dynamic>;
      final deps = data['departures'] as List?;
      final runs = data['runs'] as Map<String, dynamic>?;
      final routes = data['routes'] as Map<String, dynamic>?;

      if (deps == null || runs == null || routes == null) return [];

      final now = DateTime.now();
      final oneHourFromNow = now.add(const Duration(hours: 1));
      final trips = <Trip>[];

      for (final d in deps) {
        if (d is Map<String, dynamic>) {
          final runRef = d['run_ref']?.toString() ?? '';
          final routeId = d['route_id']?.toString() ?? '';

          final run = runs[runRef] as Map<String, dynamic>?;
          final route = routes[routeId] as Map<String, dynamic>?;

          if (run != null && route != null) {
            final trip = Trip.fromPtvDeparture(d, run, route);
            final sched = trip.departure?.scheduledTime;
            // Filter departures from current time (now - 2m) to 1 hour from now
            if (sched != null &&
                sched.isAfter(now.subtract(const Duration(minutes: 2))) &&
                sched.isBefore(oneHourFromNow)) {
              trips.add(trip);
            }
          }
        }
      }

      // Departures are sorted chronologically by departure time (next arriving vehicle first)
      trips.sort((a, b) {
        final aTime = a.departure?.scheduledTime ?? now;
        final bTime = b.departure?.scheduledTime ?? now;
        final timeComparison = aTime.compareTo(bTime);
        if (timeComparison != 0) return timeComparison;

        final aLine = a.departure?.lineCode.isNotEmpty == true
            ? a.departure!.lineCode
            : a.destinationName;
        final bLine = b.departure?.lineCode.isNotEmpty == true
            ? b.departure!.lineCode
            : b.destinationName;
        return aLine.toLowerCase().compareTo(bLine.toLowerCase());
      });

      return trips;
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>?> fetchPattern(String runRef, int routeType) async {
    if (!EnvService.isConfigured) return null;

    final signedUrl = generateSignedUrl(
      '/v3/pattern/run/$runRef/route_type/$routeType?expand=all',
    );

    try {
      final response = await _get(signedUrl);
      if (response.statusCode != 200) return null;
      return json.decode(response.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Fetches intermediate stops and schedule times for a given run from PTV API.
  Future<List<ServiceStop>> fetchPatternStops(
    String runRef, {
    int routeType = 0,
  }) async {
    final pattern = await fetchPattern(runRef, routeType);
    if (pattern == null) return [];

    final deps = pattern['departures'] as List?;
    final stops = pattern['stops'] as Map<String, dynamic>?;
    if (deps == null || stops == null || deps.isEmpty) return [];

    final serviceStops = <ServiceStop>[];
    for (final d in deps) {
      if (d is Map<String, dynamic>) {
        final stopId = d['stop_id']?.toString() ?? '';
        final stopData = stops[stopId] as Map<String, dynamic>?;
        final stopName = stopData?['stop_name']?.toString() ?? 'Stop $stopId';

        final sched = d['scheduled_departure_utc']?.toString();
        final est = d['estimated_departure_utc']?.toString();
        final timeStr = est ?? sched;
        final time =
            timeStr != null ? DateTime.tryParse(timeStr)?.toLocal() : null;

        final stationObj = Station.fromPtv(
          stopData ?? {'stop_name': stopName, 'stop_id': stopId, 'route_type': routeType},
          routeType: routeType,
        );

        serviceStops.add(
          ServiceStop(
            station: stationObj,
            departureTime: time,
            platform: d['platform_number']?.toString() ?? '',
            stopSequence: d['departure_sequence'] as int? ?? 0,
          ),
        );
      }
    }

    serviceStops.sort((a, b) => a.stopSequence.compareTo(b.stopSequence));
    return serviceStops;
  }
}
