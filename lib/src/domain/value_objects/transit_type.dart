import 'package:flutter/material.dart';

enum TransitType {
  metro,
  tram,
  regionalTrain,
  bus,
  ferry;

  static TransitType fromGtfsRouteType(int routeType) {
    switch (routeType) {
      case 0:
        return TransitType.tram;
      case 1:
        return TransitType.metro;
      case 2:
        return TransitType.regionalTrain;
      case 3:
        return TransitType.bus;
      case 4:
        return TransitType.ferry;
      default:
        return TransitType.bus;
    }
  }

  static TransitType fromPtvRouteType(int routeType) {
    switch (routeType) {
      case 0:
        return TransitType.metro;
      case 1:
        return TransitType.tram;
      case 2:
      case 4:
        return TransitType.bus;
      case 3:
        return TransitType.regionalTrain;
      default:
        return TransitType.bus;
    }
  }

  int get value {
    switch (this) {
      case TransitType.metro: return 0;
      case TransitType.tram: return 1;
      case TransitType.bus: return 2;
      case TransitType.regionalTrain: return 3;
      case TransitType.ferry: return 4;
    }
  }

  Color get ptvBrandColor {
    switch (this) {
      case TransitType.metro:
        return const Color(0xFF0072CE);
      case TransitType.tram:
        return const Color(0xFF78BE20);
      case TransitType.regionalTrain:
        return const Color(0xFF8F1A95);
      case TransitType.bus:
        return const Color(0xFFFF8200);
      case TransitType.ferry:
        return const Color(0xFF00A3A6);
    }
  }

  IconData get icon {
    switch (this) {
      case TransitType.metro:
        return Icons.subway_rounded;
      case TransitType.tram:
        return Icons.tram_rounded;
      case TransitType.regionalTrain:
        return Icons.train_rounded;
      case TransitType.bus:
        return Icons.directions_bus_rounded;
      case TransitType.ferry:
        return Icons.directions_boat_rounded;
    }
  }

  String get displayName {
    switch (this) {
      case TransitType.metro:
        return 'Metro Train';
      case TransitType.tram:
        return 'Yarra Tram';
      case TransitType.regionalTrain:
        return 'V/Line';
      case TransitType.bus:
        return 'PTV Bus';
      case TransitType.ferry:
        return 'Ferry';
    }
  }
}
