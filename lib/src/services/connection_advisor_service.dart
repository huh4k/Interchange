import 'dart:math' as math;

import '../data/repositories/gtfs_repository.dart';
import '../domain/entities/live_connection.dart';
import '../domain/entities/service.dart';
import '../domain/entities/station.dart';
import '../domain/entities/trips.dart';
import '../domain/value_objects/transit_type.dart';
import 'connection_service.dart';
import 'ptv_rt_service.dart';

class ConnectionAdvisorService {
  static const int _maxConcurrentFetches = 4;

  final PtvRealtimeService ptvService;
  final IGtfsRepository? repository;

  ConnectionAdvisorService({
    PtvRealtimeService? ptvService,
    this.repository,
  }) : ptvService = ptvService ?? PtvRealtimeService();

  /// Computes live connecting services for all upcoming stops on an active trip.
  Future<Map<String, List<LiveConnection>>> computeUpcomingConnections({
    required Trip activeTrip,
    required Station currentOrNextStation,
    required List<Station> allStations,
  }) async {
    final results = <String, List<LiveConnection>>{};

    final stops = activeTrip.stops;
    if (stops.isEmpty) return results;

    // Determine route type from the active trip so we use the correct PTV API endpoint
    final tripType = activeTrip.departure?.type;
    final activeRouteType = tripType?.value ?? 0;
    final activeMode = tripType == TransitType.tram ? PtvMode.metroTram : PtvMode.metroTrain;

    // Find index of current / next station in trip stop sequence
    int startIndex = 0;
    for (int i = 0; i < stops.length; i++) {
      if (stops[i].station.name.toLowerCase() ==
              currentOrNextStation.name.toLowerCase() ||
          stops[i].station.id == currentOrNextStation.id) {
        startIndex = i;
        break;
      }
    }

    final upcomingStops = stops.sublist(startIndex);
    final now = DateTime.now();

    // Designated interchange stops ahead, with their index for arrival estimates.
    final targets = <({int offset, ServiceStop stop})>[];
    for (int i = 0; i < upcomingStops.length; i++) {
      if (ConnectionService.isDesignatedInterchange(upcomingStops[i].station)) {
        targets.add((offset: i, stop: upcomingStops[i]));
      }
    }
    if (targets.isEmpty) return results;

    // Live phase: fetch departures for every interchange concurrently (bounded
    // pool; identical stops share one request) instead of one round trip each.
    Future<List<Trip>> safeFetch(Station st) async {
      try {
        return await ptvService.fetchDepartures(
          st.stopId,
          station: st,
          routeType: activeRouteType,
          maxResults: 20,
        );
      } catch (_) {
        return const <Trip>[];
      }
    }

    final live = List<List<Trip>>.filled(targets.length, const <Trip>[]);
    final inFlightByStop = <String, Future<List<Trip>>>{};
    var nextTarget = 0;
    Future<void> worker() async {
      while (nextTarget < targets.length) {
        final k = nextTarget++;
        final st = targets[k].stop.station;
        live[k] = await (inFlightByStop['${st.stopId}|${st.name}'] ??= safeFetch(st));
      }
    }

    await Future.wait(
      List.generate(math.min(_maxConcurrentFetches, targets.length), (_) => worker()),
    );

    // Fallback and grouping phase: sequential, in stop order.
    for (int k = 0; k < targets.length; k++) {
      final stop = targets[k].stop;
      final station = stop.station;

      // Estimate train arrival time at this platform
      final arrivalTime = _estimateArrivalTime(
        activeTrip: activeTrip,
        stop: stop,
        stopOffsetIndex: targets[k].offset,
        baseTime: now,
      );

      try {
        var stationDepartures = live[k];

        // Offline-First Fallback: If network drops, rate limiting (HTTP 429), or empty response occurs,
        // degrade gracefully to static GTFS scheduled timetable data.
        if (stationDepartures.isEmpty && repository != null) {
          try {
            final staticTrips = await repository!.getTripsForMode(
              activeMode,
              station: station,
            );
            stationDepartures = staticTrips;
          } catch (_) {
            // Keep empty if both fail
          }
        }

        // Group departures by destination name
        final byDestination = <String, List<Trip>>{};
        for (final depTrip in stationDepartures) {
          // Skip the trip the user is already on
          if (depTrip.tripId == activeTrip.tripId ||
              (depTrip.routeId == activeTrip.routeId &&
                  depTrip.headsign == activeTrip.headsign)) {
            continue;
          }

          final depTime = depTrip.departure?.scheduledTime;
          if (depTime == null) continue;

          final buffer = depTime.difference(arrivalTime);
          // Keep connections departing within -1 min to +45 mins of arrival
          if (buffer.inMinutes >= -1 && buffer.inMinutes <= 45) {
            final destKey = depTrip.destinationName.toLowerCase();
            byDestination.putIfAbsent(destKey, () => []).add(depTrip);
          }
        }

        final liveConnections = <LiveConnection>[];

        byDestination.forEach((destKey, tripsForDest) {
          // Sort chronologically
          tripsForDest.sort((a, b) {
            final aTime = a.departure?.scheduledTime ?? arrivalTime;
            final bTime = b.departure?.scheduledTime ?? arrivalTime;
            return aTime.compareTo(bTime);
          });

          if (tripsForDest.isEmpty) return;

          final primaryTrip = tripsForDest.first;
          final primaryDepTime =
              primaryTrip.departure?.scheduledTime ?? arrivalTime;
          final primaryBuffer = primaryDepTime.difference(arrivalTime);

          Trip? secondTrip;
          // If within 4 minute mark (buffer <= 4 mins), show a 2nd departure if available
          if (primaryBuffer.inMinutes <= 4 && tripsForDest.length > 1) {
            secondTrip = tripsForDest[1];
          }

          liveConnections.add(
            LiveConnection.calculate(
              connectingTrip: primaryTrip,
              interchangeStation: station,
              currentTrainArrival: arrivalTime,
              subsequentTrip: secondTrip,
            ),
          );
        });

        // Sort by transfer feasibility (feasible first) then departure time
        liveConnections.sort((a, b) {
          if (a.feasibility.isFeasible && !b.feasibility.isFeasible) return -1;
          if (!a.feasibility.isFeasible && b.feasibility.isFeasible) return 1;
          return a.connectingTrainDeparture.compareTo(b.connectingTrainDeparture);
        });

        results[station.name] = liveConnections;
      } catch (_) {
        // Continue to next stop if a stop lookup fails
      }
    }

    return results;
  }

  DateTime _estimateArrivalTime({
    required Trip activeTrip,
    required ServiceStop stop,
    required int stopOffsetIndex,
    required DateTime baseTime,
  }) {
    if (stop.departureTime != null) {
      return stop.departureTime!;
    }
    final tripDepTime = activeTrip.departure?.scheduledTime;
    if (tripDepTime != null && tripDepTime.isAfter(baseTime)) {
      return tripDepTime.add(Duration(minutes: stopOffsetIndex * 3));
    }
    // Estimated: ~3 minutes between suburban stops
    return baseTime.add(Duration(minutes: (stopOffsetIndex + 1) * 3));
  }
}
