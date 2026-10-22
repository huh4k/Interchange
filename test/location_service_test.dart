import 'package:flutter_test/flutter_test.dart';
import 'package:interchange/src/domain/entities/station.dart';
import 'package:interchange/src/services/location_service.dart';

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

    test('walkingMinutes scales straight-line distance and rounds up', () {
      expect(LocationService.walkingMinutes(0), 0);
      expect(LocationService.walkingMinutes(-5), 0);
      // 80 m * 1.3 detour / 80 m per min = 1.3 min -> 2
      expect(LocationService.walkingMinutes(80), 2);
      // 400 m -> 6.5 min -> 7
      expect(LocationService.walkingMinutes(400), 7);
      // 5 km -> 81.25 min -> 82
      expect(LocationService.walkingMinutes(5000), 82);
    });
  });
}
