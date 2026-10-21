import 'service.dart';
import '../value_objects/transit_type.dart';
import '../value_objects/service_status.dart';

class TripDeparture {
  final DateTime scheduledTime;
  final String platform;
  final String lineCode;
  final String routeName;
  final String destination;
  final TransitType type;
  final ServiceStatus status;

  const TripDeparture({
    required this.scheduledTime,
    required this.platform,
    required this.lineCode,
    required this.routeName,
    this.destination = '',
    required this.type,
    this.status = ServiceStatus.scheduled,
  });

  int minutesUntil(DateTime now) => scheduledTime.difference(now).inMinutes;

  TripDeparture copyWith({
    DateTime? scheduledTime,
    String? platform,
    String? lineCode,
    String? routeName,
    String? destination,
    TransitType? type,
    ServiceStatus? status,
  }) {
    return TripDeparture(
      scheduledTime: scheduledTime ?? this.scheduledTime,
      platform: platform ?? this.platform,
      lineCode: lineCode ?? this.lineCode,
      routeName: routeName ?? this.routeName,
      destination: destination ?? this.destination,
      type: type ?? this.type,
      status: status ?? this.status,
    );
  }
}

class Trip {
  final String tripId;
  final String routeId;
  final String serviceId;
  final String headsign;
  final String? shortName;
  final int directionId;
  final String? blockId;
  final String? shapeId;
  final int wheelchairAccessible;
  final List<ServiceStop> stops;
  final TripDeparture? departure;

  const Trip({
    required this.tripId,
    required this.routeId,
    required this.serviceId,
    required this.headsign,
    this.shortName,
    this.directionId = 0,
    this.blockId,
    this.shapeId,
    this.wheelchairAccessible = 0,
    this.stops = const [],
    this.departure,
  });

  String get destination {
    if (departure?.destination.isNotEmpty == true) {
      return departure!.destination;
    }
    if (stops.isNotEmpty) {
      return stops.last.station.name;
    }
    return headsign;
  }

  String get destinationName => destination.isNotEmpty ? destination : headsign;

  DateTime? get originDepartureTime =>
      stops.isNotEmpty ? stops.first.departureTime : null;

  DateTime? get destinationArrivalTime =>
      stops.isNotEmpty ? stops.last.arrivalTime : null;

  int? get durationMinutes {
    final start = originDepartureTime;
    final end = destinationArrivalTime;
    if (start != null && end != null) {
      return end.difference(start).inMinutes;
    }
    return null;
  }

  Trip copyWith({
    String? tripId,
    String? routeId,
    String? serviceId,
    String? headsign,
    String? shortName,
    int? directionId,
    String? blockId,
    String? shapeId,
    int? wheelchairAccessible,
    List<ServiceStop>? stops,
    TripDeparture? departure,
  }) {
    return Trip(
      tripId: tripId ?? this.tripId,
      routeId: routeId ?? this.routeId,
      serviceId: serviceId ?? this.serviceId,
      headsign: headsign ?? this.headsign,
      shortName: shortName ?? this.shortName,
      directionId: directionId ?? this.directionId,
      blockId: blockId ?? this.blockId,
      shapeId: shapeId ?? this.shapeId,
      wheelchairAccessible: wheelchairAccessible ?? this.wheelchairAccessible,
      stops: stops ?? this.stops,
      departure: departure ?? this.departure,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Trip && tripId == other.tripId);

  @override
  int get hashCode => tripId.hashCode;

  @override
  String toString() =>
      'Trip(tripId: $tripId, routeId: $routeId, headsign: $headsign, destination: $destination)';

  factory Trip.fromPtvDeparture(
    Map<String, dynamic> dep,
    Map<String, dynamic> run,
    Map<String, dynamic> route,
  ) {
    final schedStr = dep['scheduled_departure_utc']?.toString();
    final estStr = dep['estimated_departure_utc']?.toString();
    final schedTime = schedStr != null ? DateTime.tryParse(schedStr)?.toLocal() : null;
    final estTime = estStr != null ? DateTime.tryParse(estStr)?.toLocal() : null;
    
    final finalTime = estTime ?? schedTime ?? DateTime.now();
    final delay = estTime != null && schedTime != null 
        ? estTime.difference(schedTime).inMinutes 
        : 0;

    // PTV API route_type: 0 = Metro Train, 1 = Tram, 2 = Bus, 3 = V/Line
    final routeType = (route['route_type'] as int?) ??
        (run['route_type'] as int?) ??
        0;
    final type = TransitType.fromPtvRouteType(routeType);

    final statusStr = run['status']?.toString().toLowerCase();
    ServiceStatus status = ServiceStatus.scheduled;
    if (statusStr == 'cancelled') {
      status = ServiceStatus.cancelled;
    } else if (delay > 2) {
      status = ServiceStatus.delayed;
    } else if (estTime != null) {
      status = ServiceStatus.onTime;
    }

    final dest = run['destination_name']?.toString() ?? 'Unknown';
    final routeName = route['route_name']?.toString() ?? 'Unknown Route';
    final routeShort = route['route_number']?.toString();

    final departure = TripDeparture(
      scheduledTime: finalTime,
      platform: dep['platform_number']?.toString() ?? '',
      lineCode: routeShort?.isNotEmpty == true ? routeShort! : routeName.split(' ').first,
      routeName: routeName,
      destination: dest,
      type: type,
      status: status,
    );

    final rawRunRef = run['run_ref']?.toString() ?? dep['run_ref']?.toString() ?? '';
    final fallbackId = '${route['route_id']}_${dep['scheduled_departure_utc'] ?? DateTime.now().millisecondsSinceEpoch}';
    final tripId = rawRunRef.isNotEmpty ? rawRunRef : fallbackId;

    return Trip(
      tripId: tripId,
      routeId: route['route_id']?.toString() ?? '',
      serviceId: '',
      headsign: dest,
      shortName: routeShort?.isNotEmpty == true ? routeShort : routeName.split(' ').first,
      directionId: dep['direction_id'] ?? 0,
      departure: departure,
    );
  }
}

class Trips extends Trip {
  const Trips({
    required super.tripId,
    required super.routeId,
    required super.serviceId,
    required super.headsign,
    super.shortName,
    super.directionId = 0,
    super.blockId,
    super.shapeId,
    super.wheelchairAccessible = 0,
    super.stops = const [],
    super.departure,
  });
}
