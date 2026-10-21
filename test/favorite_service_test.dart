import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transit_app/src/domain/entities/station.dart';
import 'package:transit_app/src/services/favorite_service.dart';

void main() {
  group('FavoriteService Tests', () {
    late FavoriteService favoriteService;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      favoriteService = FavoriteService();
    });

    test('Initializes with empty favorites', () async {
      final stations = await favoriteService.getFavorites();
      final trips = await favoriteService.getFavoriteTrips();

      expect(stations, isEmpty);
      expect(trips, isEmpty);
    });

    test('Saves and retrieves favorite stations', () async {
      const station1 = Station(
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

      const station2 = Station(
        id: '1162',
        stopId: '1162',
        name: 'Richmond',
        code: 'RMD',
        lat: -37.8240,
        lon: 144.9896,
        suburb: 'Richmond',
        zone: 'Zone 1',
        isCityLoop: false,
        routes: [],
      );

      await favoriteService.saveFavorites([station1, station2]);

      final retrieved = await favoriteService.getFavorites();
      expect(retrieved.length, equals(2));
      expect(retrieved.first.name, equals('Flinders Street'));
      expect(retrieved.last.name, equals('Richmond'));
      expect(retrieved.first.isCityLoop, isTrue);
    });

    test('Saves and retrieves favorite trip IDs', () async {
      final tripIds = {'trip_belgrave_01', 'trip_frankston_02'};

      await favoriteService.saveFavoriteTrips(tripIds);

      final retrieved = await favoriteService.getFavoriteTrips();
      expect(retrieved.length, equals(2));
      expect(retrieved.contains('trip_belgrave_01'), isTrue);
      expect(retrieved.contains('trip_frankston_02'), isTrue);
    });
  });
}
