import 'package:flutter/material.dart';
import '../value_objects/transit_type.dart';
import '../value_objects/service_status.dart';

export '../value_objects/transit_type.dart';
export '../value_objects/service_status.dart';

class PtvColors {
  static const Color metroTrain = Color(0xFF0072CE);
  static const Color yarraTram = Color(0xFF78BE20);
  static const Color vlinePurple = Color(0xFF8F1A95);
  static const Color ptvBus = Color(0xFFFF8200);
  static const Color ferryTeal = Color(0xFF00A3A6);
}

class Departure {
  final String destination;
  final String platform;
  final DateTime scheduledTime;
  final int minutesAway;
  final ServiceStatus status;

  const Departure({
    required this.destination,
    required this.platform,
    required this.scheduledTime,
    required this.minutesAway,
    required this.status,
  });
}

class TransitRoute {
  final String id;
  final String routeId;
  final String lineCode;
  final String name;
  final TransitType type;
  final Color badgeColor;
  final List<Departure> departures;
  final bool isFavorite;

  const TransitRoute({
    required this.id,
    required this.routeId,
    required this.lineCode,
    required this.name,
    required this.type,
    required this.badgeColor,
    required this.departures,
    this.isFavorite = false,
  });

  static TransitType fromGtfsRouteType(int routeType) =>
      TransitType.fromGtfsRouteType(routeType);

  static TransitType fromPtvRouteType(int routeType) =>
      TransitType.fromPtvRouteType(routeType);

  static Color ptvBrandColor(TransitType type) => type.ptvBrandColor;

  TransitRoute copyWith({
    String? id,
    String? routeId,
    String? lineCode,
    String? name,
    TransitType? type,
    Color? badgeColor,
    List<Departure>? departures,
    bool? isFavorite,
  }) {
    return TransitRoute(
      id: id ?? this.id,
      routeId: routeId ?? this.routeId,
      lineCode: lineCode ?? this.lineCode,
      name: name ?? this.name,
      type: type ?? this.type,
      badgeColor: badgeColor ?? this.badgeColor,
      departures: departures ?? this.departures,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }
}

class ServiceAlert {
  final String id;
  final String title;
  final String description;
  final String lineCode;
  final DateTime timestamp;
  final ServiceStatus severity;

  const ServiceAlert({
    required this.id,
    required this.title,
    required this.description,
    required this.lineCode,
    required this.timestamp,
    required this.severity,
  });
}
