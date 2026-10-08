import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_app/src/domain/entities/service.dart';
import 'package:transit_app/src/domain/entities/station.dart';
import 'package:transit_app/src/domain/entities/trips.dart';
import 'package:transit_app/src/domain/value_objects/transit_type.dart';
import 'package:transit_app/src/presentation/widgets/trip_details_sheet.dart';
import 'package:transit_app/src/services/ptv_rt_service.dart';

void main() {
  // Keep the sheet offline: with credentials unset, pattern lookups return
  // immediately instead of waiting on the (test-bound) HTTP client.
  setUpAll(() => EnvService.setCredentials(userId: '', apiKey: ''));

  const stationFlinders = Station(
    id: '1071',
    stopId: '1071',
    name: 'Flinders Street',
    code: 'FSS',
    lat: -37.8183,
    lon: 144.9671,
    suburb: 'CBD',
    zone: 'Zone 1',
    isCityLoop: true,
    routes: [],
  );

  const stationRichmond = Station(
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

  const stationBelgrave = Station(
    id: '1023',
    stopId: '1023',
    name: 'Belgrave Station',
    code: 'BEL',
    lat: -37.9150,
    lon: 145.3560,
    suburb: 'Belgrave',
    zone: 'Zone 2',
    routes: [],
  );

  final sampleTrip = Trip(
    tripId: 'test_run_123',
    routeId: 'route_belgrave',
    serviceId: 'svc_01',
    headsign: 'Belgrave',
    stops: [
      const ServiceStop(
        station: stationFlinders,
        departureTime: null,
        platform: '1',
        stopSequence: 1,
      ),
      const ServiceStop(
        station: stationRichmond,
        departureTime: null,
        platform: '9',
        stopSequence: 2,
      ),
      const ServiceStop(
        station: stationBelgrave,
        departureTime: null,
        platform: '1',
        stopSequence: 3,
      ),
    ],
    departure: TripDeparture(
      scheduledTime: DateTime.now().add(const Duration(minutes: 8)),
      platform: '1',
      lineCode: 'BEL',
      routeName: 'Belgrave Line',
      destination: 'Belgrave',
      type: TransitType.metro,
    ),
  );

  testWidgets('TripDetailsSheet renders stopping sequence and connections', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TripDetailsSheet(
            trip: sampleTrip,
            selectedStation: stationFlinders,
          ),
        ),
      ),
    );

    // Initial render
    await tester.pumpAndSettle();

    expect(find.text('To Belgrave'), findsOneWidget);
    expect(find.text('BEL'), findsOneWidget);
    expect(find.text('Plat 1'), findsOneWidget);
    expect(find.text('NEXT STOP'), findsOneWidget);
    expect(find.textContaining('Route Stop Sequence'), findsOneWidget);
  });
}
