import 'package:flutter_test/flutter_test.dart';
import 'package:transit_app/src/domain/entities/service.dart';
import 'package:transit_app/src/domain/entities/station.dart';
import 'package:transit_app/src/domain/entities/trips.dart';

void main() {
  group('Trip GTFS Domain Model Tests', () {
    test('Calculates origin departure, destination arrival, and duration', () {
      final now = DateTime.now();
      final trip = Trip(
        tripId: 'trip_123',
        routeId: 'route_belgrave',
        serviceId: 'service_weekday',
        headsign: 'Flinders Street',
        directionId: 0,
        stops: [
          ServiceStop(
            station: const Station(
              id: 'st_1',
              stopId: '1',
              name: 'Belgrave',
              code: 'BEL',
              lat: 0.0,
              lon: 0.0,
              suburb: 'Belgrave',
              zone: 'Zone 2',
              routes: [],
            ),
            arrivalTime: now,
            departureTime: now,
          ),
          ServiceStop(
            station: const Station(
              id: 'st_2',
              stopId: '2',
              name: 'Flinders Street',
              code: 'FSS',
              lat: 0.0,
              lon: 0.0,
              suburb: 'Melbourne',
              zone: 'Zone 1',
              routes: [],
            ),
            arrivalTime: now.add(const Duration(minutes: 45)),
            departureTime: now.add(const Duration(minutes: 45)),
          ),
        ],
      );

      expect(trip.originDepartureTime, equals(now));
      expect(
        trip.destinationArrivalTime,
        equals(now.add(const Duration(minutes: 45))),
      );
      expect(trip.durationMinutes, equals(45));
    });

    test('Supports equality based on tripId and typedef Trips alias', () {
      const tripA = Trips(
        tripId: 'trip_abc',
        routeId: 'route_1',
        serviceId: 'svc_1',
        headsign: 'City',
      );

      const tripB = Trip(
        tripId: 'trip_abc',
        routeId: 'route_1',
        serviceId: 'svc_1',
        headsign: 'City',
      );

      expect(tripA, equals(tripB));
      expect(tripA.hashCode, equals(tripB.hashCode));
    });
  });
}
