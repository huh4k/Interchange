import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interchange/src/domain/entities/service.dart';
import 'package:interchange/src/domain/entities/station.dart';
import 'package:interchange/src/domain/entities/trips.dart';
import 'package:interchange/src/domain/value_objects/transit_type.dart';
import 'package:interchange/src/presentation/widgets/trip_details_sheet.dart';
import 'package:interchange/src/services/ptv_rt_service.dart';

Station _station(String id, String name) => Station(
      id: id,
      stopId: id,
      name: name,
      code: '',
      lat: 0,
      lon: 0,
      suburb: '',
      zone: 'Zone 1',
      routes: const [],
    );

void main() {
  setUpAll(() {
    EnvService.setCredentials(userId: '', apiKey: '');
    EnvService.setProxyUrl('');
  });

  group('platformAtStation', () {
    final southern = _station('1181', 'Southern Cross Station');
    final stops = [
      ServiceStop(station: southern, platform: '5', stopSequence: 1),
      ServiceStop(
          station: _station('1002', 'Geelong Station'),
          platform: '',
          stopSequence: 2),
    ];

    test('matches by stop id', () {
      expect(platformAtStation(stops, southern), '5');
    });

    test('falls back to normalised name', () {
      final other = _station('x', 'Southern Cross Station');
      expect(platformAtStation(stops, other), '5');
    });

    test('empty when station absent or platform unset', () {
      expect(platformAtStation(stops, _station('9', 'Nowhere')), '');
      expect(platformAtStation(stops, _station('1002', 'Geelong Station')), '');
    });
  });

  group('TripDetailsSheet platform', () {
    final geelong = _station('1002', 'Geelong Station');
    final southern = _station('1181', 'Southern Cross Station');

    Trip trip(TransitType type, {String platform = ''}) => Trip(
          tripId: 'run_1',
          routeId: 'r',
          serviceId: 's',
          headsign: 'Geelong',
          stops: [
            ServiceStop(station: southern, platform: '7', stopSequence: 1),
            ServiceStop(station: geelong, platform: '1', stopSequence: 2),
          ],
          departure: TripDeparture(
            scheduledTime: DateTime.now().add(const Duration(minutes: 10)),
            platform: platform,
            lineCode: 'GEL',
            routeName: 'Geelong',
            destination: 'Geelong',
            type: type,
          ),
        );

    Future<void> open(WidgetTester tester, Trip t) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TripDetailsSheet(trip: t, selectedStation: southern),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('V/Line says platform info is unavailable, never TBA',
        (tester) async {
      await open(tester, trip(TransitType.regionalTrain));
      expect(
        find.text('Platform information is not available for V/Line services.'),
        findsOneWidget,
      );
      expect(find.text('TBA'), findsNothing);
      expect(find.textContaining('Plat '), findsNothing);
    });

    testWidgets('metro keeps the compact tile', (tester) async {
      await open(tester, trip(TransitType.metro, platform: '2'));
      expect(find.text('Plat 2'), findsOneWidget);
    });

    testWidgets('metro with no platform shows TBA', (tester) async {
      await open(tester, trip(TransitType.metro));
      expect(find.text('TBA'), findsOneWidget);
    });

    testWidgets('bus with a bay shows "Bay N", never "Plat"', (tester) async {
      await open(tester, trip(TransitType.bus, platform: '3'));
      expect(find.text('Bay 3'), findsOneWidget);
      expect(find.textContaining('Plat '), findsNothing);
    });

    testWidgets('bus with no bay hides the tile', (tester) async {
      await open(tester, trip(TransitType.bus));
      expect(find.text('Bay'), findsNothing);
      expect(find.text('TBA'), findsNothing);
    });

    testWidgets('tram with no platform hides the tile', (tester) async {
      await open(tester, trip(TransitType.tram));
      expect(find.text('Platform'), findsNothing);
      expect(find.text('TBA'), findsNothing);
    });
  });

  group('bus stations', () {
    test('Station.fromPtv keeps the road for bus stops', () {
      final st = Station.fromPtv({
        'stop_id': 22345,
        'stop_name': 'Huntingdale Station/Haughton Rd (Oakleigh)',
      }, routeType: 2);
      expect(st.name, 'Huntingdale Station/Haughton Rd');
      expect(st.code, '22345');
    });

    test('bus badge: number, route id fallback, or BUS', () {
      expect(busRouteCode('200'), '200');
      expect(busRouteCode('57-W88-aus-1'), 'W88');
      expect(busRouteCode(''), 'BUS');
    });

    test('live bus without a route number does not use the first word of its name', () {
      final trip = Trip.fromPtvDeparture(
        {'scheduled_departure_utc': '2026-10-28T01:00:00Z'},
        {'destination_name': 'Wallan'},
        {'route_type': 2, 'route_name': 'Wallan Station - Springridge', 'route_id': 9, 'route_number': ''},
      );
      expect(trip.departure!.displayCode, 'BUS');
      expect(trip.departure!.type, TransitType.bus);
    });

    test('bus stop ids are always direct PTV ids', () {
      expect(PtvRealtimeService.isDirectStopId('22345', 2), isTrue);
    });

    test('bay labels', () {
      expect(TransitType.bus.platformLabel, 'Bay');
      expect(TransitType.metro.platformLabel, 'Plat');
    });
  });
}
