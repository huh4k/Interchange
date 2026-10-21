import 'transit_route.dart';

final RegExp _whitespaceRun = RegExp(r'\s+');

/// Lower-cases [name] and collapses whitespace so station names from
/// different sources (GTFS, PTV API, user input) can be compared reliably.
String normalizeStationName(String name) =>
    name.toLowerCase().replaceAll(_whitespaceRun, ' ').trim();

class Station {
  final String id;
  final String stopId;
  final String name;
  final String code;
  final double lat;
  final double lon;
  final String suburb;
  final String zone;
  final bool isCityLoop;
  final List<TransitRoute> routes;

  const Station({
    required this.id,
    required this.stopId,
    required this.name,
    required this.code,
    required this.lat,
    required this.lon,
    required this.suburb,
    required this.zone,
    this.isCityLoop = false,
    required this.routes,
  });

  /// Name normalised for comparisons; see [normalizeStationName].
  String get normalizedName => normalizeStationName(name);

  /// Whether [other] is the same physical stop: matching non-empty stop id,
  /// matching non-empty id, or matching normalised name.
  bool isSameStopAs(Station other) {
    if (stopId.isNotEmpty && stopId == other.stopId) return true;
    if (id.isNotEmpty && id == other.id) return true;
    return normalizedName == other.normalizedName;
  }

  Station copyWith({
    String? id,
    String? stopId,
    String? name,
    String? code,
    double? lat,
    double? lon,
    String? suburb,
    String? zone,
    bool? isCityLoop,
    List<TransitRoute>? routes,
  }) {
    return Station(
      id: id ?? this.id,
      stopId: stopId ?? this.stopId,
      name: name ?? this.name,
      code: code ?? this.code,
      lat: lat ?? this.lat,
      lon: lon ?? this.lon,
      suburb: suburb ?? this.suburb,
      zone: zone ?? this.zone,
      isCityLoop: isCityLoop ?? this.isCityLoop,
      routes: routes ?? this.routes,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'stopId': stopId,
      'name': name,
      'code': code,
      'lat': lat,
      'lon': lon,
      'suburb': suburb,
      'zone': zone,
      'isCityLoop': isCityLoop,
    };
  }

  factory Station.fromMap(Map<String, dynamic> map) {
    return Station(
      id: map['id'] ?? '',
      stopId: map['stopId'] ?? '',
      name: map['name'] ?? '',
      code: map['code'] ?? '',
      lat: (map['lat'] as num?)?.toDouble() ?? 0.0,
      lon: (map['lon'] as num?)?.toDouble() ?? 0.0,
      suburb: map['suburb'] ?? '',
      zone: map['zone'] ?? 'Zone 1',
      isCityLoop: map['isCityLoop'] ?? false,
      routes: const [],
    );
  }

  factory Station.fromPtv(Map<String, dynamic> map, {int? routeType}) {
    final name = map['stop_name']?.toString() ?? '';
    final stopId = map['stop_id']?.toString() ?? '';

    // Determine if this is a tram stop: passed explicitly, or detected from route_type in the map
    final resolvedRouteType = routeType ?? (map['route_type'] as int?);
    final isTram = resolvedRouteType == 1;

    String cleanName;
    String code;

    if (isTram) {
      // Tram stops are intersection-based names like "Collins St/Elizabeth St #3".
      // Do NOT truncate on '/'. Normalise whitespace only.
      cleanName = name.replaceAll(RegExp(r'\s+'), ' ').trim();
      // Extract platform/stop number from "#N" or "#Na" suffix for use as code
      final stopNumMatch = RegExp(r'#\s*(\d+[a-zA-Z]?)').firstMatch(cleanName);
      code = stopNumMatch != null ? stopNumMatch.group(1)! : stopId;
    } else {
      // Train/bus stops: strip "/" platform suffixes, parenthetical qualifiers, normalise "Railway Station"
      cleanName = name;
      cleanName = cleanName.split('/')[0].trim();
      cleanName = cleanName.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();
      cleanName = cleanName.replaceAll(RegExp(r'\s+Railway Station', caseSensitive: false), ' Station');
      cleanName = cleanName.replaceAll(RegExp(r'\s+Station Station', caseSensitive: false), ' Station');
      if (cleanName.endsWith(' Station')) {
        cleanName = cleanName.substring(0, cleanName.length - 8).trim();
      }
      code = stopId;
    }

    final nameLower = cleanName.toLowerCase();
    // Tram stops are never city loop stops
    final isCityLoop = !isTram &&
        (nameLower.contains('central') ||
            nameLower.contains('flinders') ||
            nameLower.contains('parliament') ||
            nameLower.contains('flagstaff') ||
            nameLower.contains('southern cross'));

    return Station(
      id: stopId,
      stopId: stopId,
      name: cleanName.isNotEmpty ? cleanName : stopId,
      code: code,
      lat: (map['stop_latitude'] as num?)?.toDouble() ?? 0.0,
      lon: (map['stop_longitude'] as num?)?.toDouble() ?? 0.0,
      suburb: map['stop_suburb']?.toString() ?? 'Melbourne',
      zone: 'Zone 1',
      isCityLoop: isCityLoop,
      routes: const [],
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Station && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Station(id: $id, name: $name, code: $code)';
}
