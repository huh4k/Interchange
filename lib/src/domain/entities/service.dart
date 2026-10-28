import 'station.dart';

class ServiceStop {
  final Station station;
  final DateTime? arrivalTime;
  final DateTime? departureTime;
  final String? platform;
  final int stopSequence;

  const ServiceStop({
    required this.station,
    this.arrivalTime,
    this.departureTime,
    this.platform,
    this.stopSequence = 1,
  });

  ServiceStop copyWith({
    Station? station,
    DateTime? arrivalTime,
    DateTime? departureTime,
    String? platform,
    int? stopSequence,
  }) {
    return ServiceStop(
      station: station ?? this.station,
      arrivalTime: arrivalTime ?? this.arrivalTime,
      departureTime: departureTime ?? this.departureTime,
      platform: platform ?? this.platform,
      stopSequence: stopSequence ?? this.stopSequence,
    );
  }
}

class Service {
  final String id;
  final String tripId;
  final String routeId;
  final String serviceNumber;
  final String headsign;
  final String? shapeId;
  final Station originStation;
  final Station destinationStation;
  final List<ServiceStop> stops;

  const Service({
    required this.id,
    required this.tripId,
    required this.routeId,
    required this.serviceNumber,
    required this.headsign,
    this.shapeId,
    required this.originStation,
    required this.destinationStation,
    required this.stops,
  });

  DateTime? get originDepartureTime {
    if (stops.isEmpty) return null;
    return stops.first.departureTime ?? stops.first.arrivalTime;
  }

  DateTime? get destinationArrivalTime {
    if (stops.isEmpty) return null;
    return stops.last.arrivalTime ?? stops.last.departureTime;
  }

  Duration? get totalDuration {
    final start = originDepartureTime;
    final end = destinationArrivalTime;
    if (start != null && end != null) {
      return end.difference(start);
    }
    return null;
  }

  Service copyWith({
    String? id,
    String? tripId,
    String? routeId,
    String? serviceNumber,
    String? headsign,
    String? shapeId,
    Station? originStation,
    Station? destinationStation,
    List<ServiceStop>? stops,
  }) {
    return Service(
      id: id ?? this.id,
      tripId: tripId ?? this.tripId,
      routeId: routeId ?? this.routeId,
      serviceNumber: serviceNumber ?? this.serviceNumber,
      headsign: headsign ?? this.headsign,
      shapeId: shapeId ?? this.shapeId,
      originStation: originStation ?? this.originStation,
      destinationStation: destinationStation ?? this.destinationStation,
      stops: stops ?? this.stops,
    );
  }
}

/// The platform [station] is served from on this run, or '' when the run's
/// stop list has no platform for it. Matches by stop id, id, then name.
String platformAtStation(List<ServiceStop> stops, Station station) {
  for (final s in stops) {
    final st = s.station;
    final matches = (station.stopId.isNotEmpty && st.stopId == station.stopId) ||
        (station.id.isNotEmpty && st.id == station.id) ||
        st.normalizedName == station.normalizedName;
    if (matches) return s.platform ?? '';
  }
  return '';
}
