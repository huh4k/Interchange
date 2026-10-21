import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/entities/station.dart';

class FavoriteService {
  static const String _favoriteStationsKey = 'favorite_stations';
  static const String _favoriteTripsKey = 'favorite_trips';
  static const String _recentStationsKey = 'recent_stations';
  static const int maxRecentStations = 8;

  Future<List<Station>> getFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final String? favoritesJson = prefs.getString(_favoriteStationsKey);
    
    if (favoritesJson == null || favoritesJson.isEmpty) {
      return [];
    }

    try {
      final List<dynamic> decodedList = json.decode(favoritesJson);
      return decodedList.map((item) => Station.fromMap(item as Map<String, dynamic>)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> saveFavorites(List<Station> stations) async {
    final prefs = await SharedPreferences.getInstance();
    final List<Map<String, dynamic>> mapList = stations.map((s) => s.toMap()).toList();
    await prefs.setString(_favoriteStationsKey, json.encode(mapList));
  }

  Future<Set<String>> getFavoriteTrips() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? tripIds = prefs.getStringList(_favoriteTripsKey);
    return tripIds?.toSet() ?? {};
  }

  Future<void> saveFavoriteTrips(Set<String> tripIds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_favoriteTripsKey, tripIds.toList());
  }

  Future<List<Station>> getRecentStations() async {
    final prefs = await SharedPreferences.getInstance();
    final String? recentsJson = prefs.getString(_recentStationsKey);
    if (recentsJson == null || recentsJson.isEmpty) {
      return [];
    }
    try {
      final List<dynamic> decoded = json.decode(recentsJson);
      return decoded.map((item) => Station.fromMap(item as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<Station>> saveRecentStation(Station station) async {
    final recents = await getRecentStations();
    recents.removeWhere((s) =>
        s.id == station.id ||
        (s.stopId.isNotEmpty && s.stopId == station.stopId) ||
        s.name.toLowerCase() == station.name.toLowerCase());
    recents.insert(0, station);
    if (recents.length > maxRecentStations) {
      recents.removeRange(maxRecentStations, recents.length);
    }
    final prefs = await SharedPreferences.getInstance();
    final List<Map<String, dynamic>> mapList = recents.map((s) => s.toMap()).toList();
    await prefs.setString(_recentStationsKey, json.encode(mapList));
    return recents;
  }

  Future<void> clearRecentStations() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_recentStationsKey);
  }
}
