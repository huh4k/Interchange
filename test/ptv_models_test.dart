import 'package:flutter_test/flutter_test.dart';
import 'package:transit_app/src/domain/entities/station.dart';
import 'package:transit_app/src/domain/entities/trips.dart';

void main() {
  group('PTV Domain Models', () {
    test('Station.fromPtv parses correctly', () {
      final json = {
        'stop_id': 1071,
        'stop_name': 'Flinders Street Railway Station',
        'stop_latitude': -37.818305,
        'stop_longitude': 144.966964,
        'route_type': 0,
      };

      final station = Station.fromPtv(json);
      expect(station.id, '1071');
      expect(station.stopId, '1071');
      expect(station.name, 'Flinders Street');
      expect(station.lat, -37.818305);
      expect(station.lon, 144.966964);
    });

    test('Trip.fromPtvDeparture parses correctly', () {
      final json = {
        'run_ref': 'run-123',
        'route_id': 3,
        'platform_number': '4',
        'scheduled_departure_utc': '2026-08-13T12:00:00Z',
        'estimated_departure_utc': '2026-08-13T12:05:00Z',
      };
      
      final route = {
        'route_name': 'Frankston',
        'route_number': 'FKN',
        'route_type': 0,
      };
      
      final run = {
        'destination_name': 'Frankston',
        'status': 'on time',
      };

      final trip = Trip.fromPtvDeparture(json, run, route);
      expect(trip.tripId, 'run-123');
      expect(trip.destinationName, 'Frankston');
      expect(trip.departure?.platform, '4');
      expect(trip.departure?.type.value, 0); // Metro
      expect(trip.departure?.scheduledTime, isNotNull);
    });
  });
}
