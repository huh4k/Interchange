import '../data/repositories/gtfs_repository.dart';
import '../domain/entities/live_connection.dart';
import '../domain/entities/service.dart';
import '../domain/entities/station.dart';
import '../domain/entities/trips.dart';
import '../domain/value_objects/transit_type.dart';
import 'connection_service.dart';
import 'ptv_rt_service.dart';

class ConnectionAdvisorService {
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

    for (int i = 0; i < upcomingStops.length; i++) {
      final stop = upcomingStops[i];
      final station = stop.station;

      // Only compute live connections for designated interchange stations on the map
      if (!ConnectionService.isDesignatedInterchange(station)) {
        continue;
      }

      // Estimate train arrival time at this platform
      final arrivalTime = _estimateArrivalTime(
        activeTrip: activeTrip,
        stop: stop,
        stopOffsetIndex: i,
        baseTime: now,
      );

      // Fetch departures at this upcoming station (Real-time PTV API with Offline GTFS Timetable Fallback)
      try {
        List<Trip> stationDepartures = [];

        try {
          stationDepartures = await ptvService.fetchDepartures(
            station.stopId,
            station: station,
            routeType: activeRouteType,
            maxResults: 20,
          );
        } catch (_) {
          stationDepartures = [];
        }

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
