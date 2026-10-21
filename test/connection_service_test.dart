import 'package:flutter_test/flutter_test.dart';
import 'package:transit_app/src/domain/entities/station.dart';
import 'package:transit_app/src/domain/value_objects/transit_type.dart';
import 'package:transit_app/src/services/connection_service.dart';

void main() {
  group('ConnectionService Tests', () {
    test('Discovers train & tram interchange connections for Flinders Street', () {
      const flinders = Station(
        id: '1071',
        stopId: '1071',
        name: 'Flinders Street Station',
        code: 'FSS',
        lat: -37.8183,
        lon: 144.9671,
        suburb: 'Melbourne CBD',
        zone: 'Zone 1',
        isCityLoop: true,
        routes: [],
      );

      final connections = ConnectionService.getConnectionsForStation(flinders);
      expect(connections.isNotEmpty, isTrue);
      expect(connections.any((c) => c.type == TransitType.metro), isTrue);
      expect(connections.any((c) => c.type == TransitType.tram), isTrue);
    });

    test('Discovers V/Line, SkyBus, and Tram connections for Southern Cross', () {
      const southernCross = Station(
        id: '1181',
        stopId: '1181',
        name: 'Southern Cross Station',
        code: 'SSS',
        lat: -37.8185,
        lon: 144.9525,
        suburb: 'Docklands',
        zone: 'Zone 1',
        isCityLoop: true,
        routes: [],
      );

      final connections = ConnectionService.getConnectionsForStation(southernCross);
      expect(connections.length, greaterThanOrEqualTo(2));
      expect(connections.any((c) => c.type == TransitType.regionalTrain), isTrue);
      expect(connections.any((c) => c.lineBadges.contains('SkyBus')), isTrue);
    });

    test('Discovers 8-line junction connections for Richmond Station', () {
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

      final connections = ConnectionService.getConnectionsForStation(richmond);
      expect(connections.isNotEmpty, isTrue);
      final metroConn = connections.firstWhere((c) => c.type == TransitType.metro);
      expect(metroConn.lineBadges, contains('BEL'));
      expect(metroConn.lineBadges, contains('FKN'));
    });

    test('Falls back to City Loop Transfer for generic City Loop station', () {
      const loopStation = Station(
        id: '9999',
        stopId: '9999',
        name: 'Custom Loop Hub',
        code: 'CLH',
        lat: 0,
        lon: 0,
        suburb: 'Melbourne',
        zone: 'Zone 1',
        isCityLoop: true,
        routes: [],
      );

      final connections = ConnectionService.getConnectionsForStation(loopStation);
      expect(connections.length, equals(1));
      expect(connections.first.title, equals('City Loop Transfer'));
    });

    test('Returns empty connections list for minor non-interchange station', () {
      const minorStation = Station(
        id: '5555',
        stopId: '5555',
        name: 'Quiet Suburban Platform',
        code: 'QSP',
        lat: 0,
        lon: 0,
        suburb: 'Suburbs',
        zone: 'Zone 2',
        routes: [],
      );

      final connections = ConnectionService.getConnectionsForStation(minorStation);
      expect(connections.isEmpty, isTrue);
    });

    test('isDesignatedInterchange accurately identifies map interchange stations vs local stops', () {
      const burnley = Station(
        id: '1029',
        stopId: '1029',
        name: 'Burnley Station',
        code: 'BLY',
        lat: -37.8280,
        lon: 145.0066,
        suburb: 'Burnley',
        zone: 'Zone 1',
        routes: [],
      );

      const hawthorn = Station(
        id: '1088',
        stopId: '1088',
        name: 'Hawthorn Station',
        code: 'HAW',
        lat: -37.8220,
        lon: 145.0232,
        suburb: 'Hawthorn',
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

      expect(ConnectionService.isDesignatedInterchange(burnley), isTrue);
      expect(ConnectionService.isDesignatedInterchange(richmond), isTrue);
      expect(ConnectionService.isDesignatedInterchange(hawthorn), isFalse);
    });
  });
}
