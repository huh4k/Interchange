import 'package:flutter_test/flutter_test.dart';
import 'package:transit_app/src/domain/entities/service.dart';
import 'package:transit_app/src/domain/entities/station.dart';

void main() {
  test('Service model calculates origin departure, destination arrival, and duration', () {
    const originStation = Station(
      id: 'st_1',
      stopId: '19842',
      name: 'Central Station',
      code: 'CEN',
      lat: -33.8830,
      lon: 151.2065,
      suburb: 'CBD',
      zone: 'Zone 1',
      routes: [],
    );

    const midStation = Station(
      id: 'st_2',
      stopId: '19843',
      name: 'Town Hall',
      code: 'TH',
      lat: -33.8732,
      lon: 151.2061,
      suburb: 'CBD',
      zone: 'Zone 1',
      routes: [],
    );

    const destStation = Station(
      id: 'st_3',
      stopId: '19844',
      name: 'Wynyard',
      code: 'WY',
      lat: -33.8656,
      lon: 151.2054,
      suburb: 'CBD',
      zone: 'Zone 1',
      routes: [],
    );

    final now = DateTime.now();
    final originTime = now;
    final destTime = now.add(const Duration(minutes: 10));

    final service = Service(
      id: 'srv_101',
      tripId: 'TRIP-101',
      routeId: 'ROUTE-T4',
      serviceNumber: 'T4-101',
      headsign: 'Wynyard Express',
      originStation: originStation,
      destinationStation: destStation,
      stops: [
        ServiceStop(
          station: originStation,
          departureTime: originTime,
          platform: 'Platform 24',
        ),
        ServiceStop(
          station: midStation,
          arrivalTime: now.add(const Duration(minutes: 4)),
          departureTime: now.add(const Duration(minutes: 5)),
          platform: 'Platform 3',
        ),
        ServiceStop(
          station: destStation,
          arrivalTime: destTime,
          platform: 'Platform 4',
        ),
      ],
    );

    expect(service.originStation.name, equals('Central Station'));
    expect(service.destinationStation.name, equals('Wynyard'));
    expect(service.stops.length, equals(3));
    expect(service.originDepartureTime, equals(originTime));
    expect(service.destinationArrivalTime, equals(destTime));
    expect(service.totalDuration, equals(const Duration(minutes: 10)));
  });
}
