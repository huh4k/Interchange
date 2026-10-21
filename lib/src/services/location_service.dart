import 'dart:async';
import 'dart:math' as math;
import 'package:geolocator/geolocator.dart';
import '../domain/entities/station.dart';

class LocationService {
  StreamSubscription<Position>? _positionSubscription;
  final _positionController = StreamController<Position>.broadcast();

  Stream<Position> get positionStream => _positionController.stream;

  /// Checks and requests location permission.
  Future<bool> requestPermission() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return false;
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  /// Retrieves instantaneous GPS position if permission is granted.
  Future<Position?> getCurrentPosition() async {
    try {
      final hasPermission = await requestPermission();
      if (!hasPermission) return null;
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 5),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  /// Starts listening to real-time GPS location updates.
  Future<void> startLocationTracking({
    void Function(Position position)? onPositionChanged,
  }) async {
    try {
      final hasPermission = await requestPermission();
      if (!hasPermission) return;

      await _positionSubscription?.cancel();
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 25,
        ),
      ).listen((position) {
        _positionController.add(position);
        onPositionChanged?.call(position);
      });
    } catch (_) {}
  }

  /// Manually emit a position update (useful for testing and ride simulation).
  void emitMockPosition(Position position) {
    _positionController.add(position);
  }

  /// Stops tracking position.
  Future<void> stopLocationTracking() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  void dispose() {
    _positionSubscription?.cancel();
    _positionController.close();
  }

  /// Calculates Haversine distance in meters between two lat/lon coordinates.
  static double calculateDistanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadiusMeters = 6371000.0;
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degreesToRadians(lat1)) *
            math.cos(_degreesToRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  /// Finds the closest station to the given coordinates.
  static Station? findClosestStation(
    double latitude,
    double longitude,
    List<Station> stations, {
    double maxDistanceMeters = 5000,
  }) {
    if (stations.isEmpty) return null;

    Station? closest;
    double minDistance = double.infinity;

    for (final station in stations) {
      if (station.lat == 0.0 && station.lon == 0.0) continue;
      final distance = calculateDistanceMeters(
        latitude,
        longitude,
        station.lat,
        station.lon,
      );
      if (distance < minDistance && distance <= maxDistanceMeters) {
        minDistance = distance;
        closest = station;
      }
    }

    return closest;
  }

  /// Formats distance in meters to a concise string e.g. "350 m" or "1.4 km".
  static String formatDistance(double distanceMeters) {
    if (distanceMeters < 1000) {
      return '${distanceMeters.round()} m';
    } else {
      final km = distanceMeters / 1000.0;
      return '${km.toStringAsFixed(1)} km';
    }
  }

  static double _degreesToRadians(double degrees) {
    return degrees * (math.pi / 180.0);
  }
}
