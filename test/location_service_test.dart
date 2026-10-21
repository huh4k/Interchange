import 'package:flutter_test/flutter_test.dart';
import 'package:transit_app/src/domain/entities/station.dart';
import 'package:transit_app/src/services/location_service.dart';

void main() {
  group('LocationService Tests', () {
    test('Calculates Haversine distance correctly between Flinders St and Richmond', () {
      // Flinders St: -37.8183, 144.9671
      // Richmond: -37.8240, 144.9896
      final distance = LocationService.calculateDistanceMeters(
        -37.8183,
        144.9671,
        -37.8240,
        144.9896,
      );

      // Distance should be ~2.06 km (2060 meters)
      expect(distance, greaterThan(1900));
      expect(distance, lessThan(2300));
    });

    test('Finds closest station accurately', () {
      const flinders = Station(
        id: '1071',
        stopId: '1071',
        name: 'Flinders Street Station',
        code: 'FSS',
        lat: -37.8183,
        lon: 144.9671,
        suburb: 'CBD',
        zone: 'Zone 1',
        routes: [],
      );

      const richmond = Station(
        id: '1162',
        stopId: '1162',
        name: 'Richmond Station',
        code: 'RMD',
        lat: -37.8240,
        lon: 144.9896,
        suburb: 'Richmond',
        zone: 'Zone 1',
        routes: [],
      );

      // Point very close to Flinders Street (Federation Square: -37.8179, 144.9690)
      final closest = LocationService.findClosestStation(
        -37.8179,
        144.9690,
        [flinders, richmond],
      );

      expect(closest?.id, equals('1071'));
      expect(closest?.name, equals('Flinders Street Station'));
    });
  });
}
