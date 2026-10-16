import 'dart:math' as math;
import '../domain/entities/service.dart';
import 'location_service.dart';

/// Where a rider is along a trip's ordered stops.
class RideProgress {
  /// Index of the stop the rider is at, or the last stop they passed when
  /// [atStop] is false (so the next stop is `index + 1`).
  final int index;
  final bool atStop;

  const RideProgress(this.index, {required this.atStop});
}

/// Locates a GPS fix along [stops].
///
/// Only stops from [minIndex] onward are considered, so progress never jumps
/// backwards because of GPS noise or a line that doubles back near an earlier
/// stop. Within [atStopMeters] of a stop the rider is "at" it; otherwise the
/// fix is projected onto the nearest segment between consecutive stops and the
/// rider is reported as past the segment's first stop. Returns null when the
/// fix is not within [corridorMeters] of the remaining route, or no stop has
/// coordinates.
RideProgress? locateOnTrip(
  List<ServiceStop> stops,
  double lat,
  double lon, {
  int minIndex = 0,
  double atStopMeters = 400,
  double corridorMeters = 3000,
}) {
  final start = minIndex.clamp(0, stops.length);
  bool hasCoords(int i) => stops[i].station.lat != 0.0 || stops[i].station.lon != 0.0;

  var nearestIdx = -1;
  var nearestDist = double.infinity;
  for (var i = start; i < stops.length; i++) {
    if (!hasCoords(i)) continue;
    final d = LocationService.calculateDistanceMeters(
      lat, lon, stops[i].station.lat, stops[i].station.lon);
    if (d < nearestDist) {
      nearestDist = d;
      nearestIdx = i;
    }
  }
  if (nearestIdx == -1) return null;
  if (nearestDist <= atStopMeters) {
    return RideProgress(nearestIdx, atStop: true);
  }

  var bestSeg = -1;
  var bestDist = double.infinity;
  for (var j = start; j + 1 < stops.length; j++) {
    if (!hasCoords(j) || !hasCoords(j + 1)) continue;
    final d = _distanceToSegmentMeters(
      lat, lon,
      stops[j].station.lat, stops[j].station.lon,
      stops[j + 1].station.lat, stops[j + 1].station.lon,
    );
    if (d < bestDist) {
      bestDist = d;
      bestSeg = j;
    }
  }
  if (bestSeg == -1 || bestDist > corridorMeters) return null;
  return RideProgress(bestSeg, atStop: false);
}

double _distanceToSegmentMeters(
  double lat, double lon,
  double lat1, double lon1,
  double lat2, double lon2,
) {
  // Local flat-earth projection around the segment start; fine at stop spacing.
  final kx = 111320.0 * math.cos(lat1 * math.pi / 180);
  const ky = 110540.0;
  final px = (lon - lon1) * kx, py = (lat - lat1) * ky;
  final bx = (lon2 - lon1) * kx, by = (lat2 - lat1) * ky;
  final len2 = bx * bx + by * by;
  final t = len2 == 0 ? 0.0 : ((px * bx + py * by) / len2).clamp(0.0, 1.0);
  final dx = px - bx * t, dy = py - by * t;
  return math.sqrt(dx * dx + dy * dy);
}
