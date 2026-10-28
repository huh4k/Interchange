import 'transit_type.dart';

enum PtvMode {
  regionalTrain('1'),
  metroTrain('2'),
  metroTram('3'),
  metroBus('4'),
  regionalCoach('5'),
  regionalBus('6');

  final String id;
  const PtvMode(this.id);

  /// Bus can run without static GTFS (not hosted yet, or failed to load):
  /// stops and departures then come from the PTV API only.
  bool get isLiveOnly => this == PtvMode.metroBus;

  /// Modes whose GTFS stops are individual kerbside stops (full names, keyed
  /// by PTV stop id) rather than stations grouped by parent.
  bool get isPerStop =>
      this == PtvMode.metroTram ||
      this == PtvMode.metroBus ||
      this == PtvMode.regionalBus;

  /// Name of this mode's static GTFS files on the data host (see `gtfs_config.dart`).
  String get gtfsKey {
    switch (this) {
      case PtvMode.metroTrain:
        return 'metro';
      case PtvMode.metroTram:
        return 'tram';
      case PtvMode.regionalTrain:
        return 'vline';
      case PtvMode.metroBus:
      case PtvMode.regionalCoach:
      case PtvMode.regionalBus:
        return name;
    }
  }

  int get ptvRouteType {
    switch (this) {
      case PtvMode.metroTrain:
        return 0;
      case PtvMode.metroTram:
        return 1;
      case PtvMode.metroBus:
      case PtvMode.regionalBus:
        return 2;
      case PtvMode.regionalTrain:
      case PtvMode.regionalCoach:
        return 3;
    }
  }

  TransitType get transitType {
    switch (this) {
      case PtvMode.metroTrain:
        return TransitType.metro;
      case PtvMode.metroTram:
        return TransitType.tram;
      case PtvMode.regionalTrain:
        return TransitType.regionalTrain;
      case PtvMode.metroBus:
      case PtvMode.regionalBus:
        return TransitType.bus;
      case PtvMode.regionalCoach:
        return TransitType.ferry;
    }
  }

  static PtvMode fromTransitType(TransitType type) {
    switch (type) {
      case TransitType.metro:
        return PtvMode.metroTrain;
      case TransitType.tram:
        return PtvMode.metroTram;
      case TransitType.regionalTrain:
        return PtvMode.regionalTrain;
      case TransitType.bus:
        return PtvMode.metroBus;
      case TransitType.ferry:
        return PtvMode.regionalCoach;
    }
  }
}
