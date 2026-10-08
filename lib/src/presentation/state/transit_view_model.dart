import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../domain/entities/live_connection.dart';
import '../../domain/entities/station.dart';
import '../../domain/entities/trips.dart';
import '../../domain/entities/transit_route.dart';
import '../../data/repositories/gtfs_repository.dart';
import '../../services/location_service.dart';
import '../../services/connection_advisor_service.dart';
import '../../services/melbourne_gtfs_service.dart';
import '../../services/ptv_rt_service.dart';
import '../../services/favorite_service.dart';

class TransitViewModel extends ChangeNotifier with WidgetsBindingObserver {
  final IGtfsRepository repository;
  final PtvRealtimeService ptvService;
  final FavoriteService favoriteService = FavoriteService();
  final LocationService locationService;
  late final ConnectionAdvisorService connectionAdvisor;
  bool _isDisposed = false;

  /// Periodically re-fetches departures every 30 seconds while the app is in the foreground.
  Timer? _autoRefreshTimer;

  /// Periodically refreshes upcoming connections while a trip is being tracked.
  Timer? _trackingPollingTimer;

  int _selectedNavIndex = 0;
  PtvMode _activeMode = PtvMode.metroTrain;
  final Map<PtvMode, Station> _savedStationByMode = {};
  String _searchQuery = '';
  Station _selectedStation = MelbourneGtfsService.defaultStation;

  List<Trip> _trips = [];
  List<ServiceAlert> _alerts = [];
  List<Station> _stations = [MelbourneGtfsService.defaultStation];
  List<Station> _favoriteStations = [];
  List<Station> _recentStations = [];
  Set<String> _favoriteTrips = {};

  Position? _userPosition;
  bool _isLocating = false;

  // Active On-Board Ride Tracking & Connection Advisory State
  Trip? _activeTrackedTrip;
  Station? _onBoardStation;
  Station? _previousStopStation;
  Station? _nextStopStation;
  bool _isTrackingActive = false;
  bool _isLoadingConnections = false;
  Map<String, List<LiveConnection>> _upcomingConnections = {};

  bool _isLoading = true;
  double _loadingProgress = 0.0;
  String _loadingStatus = 'Initializing...';
  String? _errorMessage;
  int _loadRequestId = 0;
  bool _isSilentRefreshing = false;

  // Memoised derived lists. Widgets read these getters on every rebuild, so the
  // results are recomputed only when their inputs change.
  int _favoriteTripsVersion = 0;
  int _favoriteStationsVersion = 0;
  List<Trip>? _displayedCache;
  List<Trip>? _displayedCacheTrips;
  String? _displayedCacheQuery;
  int? _displayedCacheNav;
  int? _displayedCacheFavVersion;
  List<ServiceAlert>? _disruptionsCache;
  List<ServiceAlert>? _disruptionsCacheAlerts;
  int? _disruptionsCacheFavVersion;
  String? _disruptionsCacheStation;
  bool _isRefreshingConnections = false;
  /// Station lists already loaded per mode. Lists are never mutated in place:
  /// identity-based memoisation elsewhere depends on that.
  final Map<PtvMode, List<Station>> _stationsByMode = {};
  late final Future<void> initFuture;

  TransitViewModel({
    required this.repository,
    PtvRealtimeService? ptvService,
    LocationService? locationService,
    ConnectionAdvisorService? connectionAdvisor,
  })  : ptvService = ptvService ?? PtvRealtimeService(),
        locationService = locationService ?? LocationService() {
    // Built here (not in the initializer list) so the advisor shares this
    // view model's PtvRealtimeService, including its caches and connection.
    this.connectionAdvisor = connectionAdvisor ??
        ConnectionAdvisorService(
          ptvService: this.ptvService,
          repository: repository,
        );
    WidgetsBinding.instance.addObserver(this);
    initFuture = _init();
    _startAutoRefresh();
  }

  Future<void> _init() async {
    final favs = await favoriteService.getFavorites();
    final trips = await favoriteService.getFavoriteTrips();
    final recents = await favoriteService.getRecentStations();
    if (_favoriteStations.isEmpty && favs.isNotEmpty) {
      _favoriteStationsVersion++;
      _favoriteStations = favs;
      _selectedStation = _favoriteStations.first;
    }
    if (_favoriteTrips.isEmpty && trips.isNotEmpty) {
      _favoriteTripsVersion++;
      _favoriteTrips = trips;
    }
    if (recents.isNotEmpty) {
      _recentStations = recents;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _autoRefreshTimer?.cancel();
    _trackingPollingTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Starts a 30-second periodic timer that re-fetches departure data.
  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_isDisposed && !_isLoading && !_isSilentRefreshing) {
        loadData(station: _selectedStation, isSilent: true);
      }
    });
  }

  /// Pauses or resumes the auto-refresh timer based on the app lifecycle.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startAutoRefresh();
      // Data may be stale after time in the background; refresh straight away.
      if (!_isLoading && !_isSilentRefreshing) {
        loadData(station: _selectedStation, isSilent: true);
      }
      if (_isTrackingActive) _startTrackingPolling();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _autoRefreshTimer?.cancel();
      _autoRefreshTimer = null;
      _stopTrackingPolling();
    }
  }

  /// Starts periodic polling for upcoming connections while tracking a trip.
  void _startTrackingPolling() {
    _trackingPollingTimer?.cancel();
    _trackingPollingTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!_isDisposed && _isTrackingActive) {
        refreshUpcomingConnections();
      }
    });
  }

  /// Stops the tracking connection polling timer.
  void _stopTrackingPolling() {
    _trackingPollingTimer?.cancel();
    _trackingPollingTimer = null;
  }


  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }

  int get selectedNavIndex => _selectedNavIndex;
  PtvMode get activeMode => _activeMode;
  String get searchQuery => _searchQuery;
  Station get selectedStation => _selectedStation;
  List<Trip> get trips => _trips;
  List<ServiceAlert> get alerts => _alerts;

  /// Disruptions filtered strictly to favorited stations (or current station if no favorites yet).
  List<ServiceAlert> get favoriteStationDisruptions {
    final stationKey = _favoriteStations.isEmpty ? _selectedStation.name : '';
    final cached = _disruptionsCache;
    if (cached != null &&
        identical(_disruptionsCacheAlerts, _alerts) &&
        _disruptionsCacheFavVersion == _favoriteStationsVersion &&
        _disruptionsCacheStation == stationKey) {
      return cached;
    }

    // Match against favourites, or the current station until any are saved.
    final names = (_favoriteStations.isEmpty
            ? [_selectedStation]
            : _favoriteStations)
        .map((st) => st.name.toLowerCase().replaceAll(' station', '').trim())
        .toList();

    final result = _alerts.where((alert) {
      final title = alert.title.toLowerCase();
      final desc = alert.description.toLowerCase();
      final line = alert.lineCode.toLowerCase();
      return names.any(
        (n) => title.contains(n) || desc.contains(n) || line.contains(n),
      );
    }).toList();

    _disruptionsCache = result;
    _disruptionsCacheAlerts = _alerts;
    _disruptionsCacheFavVersion = _favoriteStationsVersion;
    _disruptionsCacheStation = stationKey;
    return result;
  }

  List<Station> get stations => _stations;
  List<Station> get favoriteStations => _favoriteStations;
  List<Station> get recentStations => _recentStations;
  Set<String> get favoriteTrips => _favoriteTrips;
  Position? get userPosition => _userPosition;
  bool get isLocating => _isLocating;
  bool get isLoading => _isLoading;
  double get loadingProgress => _loadingProgress;
  String get loadingStatus => _loadingStatus;
  int get loadingPercentage => (_loadingProgress * 100).clamp(0, 100).toInt();
  String? get errorMessage => _errorMessage;

  // Active Live Ride Tracking & Connections
  Trip? get activeTrackedTrip => _activeTrackedTrip;
  Station? get onBoardStation => _onBoardStation;
  Station? get currentStopStation => _onBoardStation;
  Station? get previousStopStation => _previousStopStation;
  Station? get nextStopStation => _nextStopStation;
  bool get isTrackingActive => _isTrackingActive;
  bool get isLoadingConnections => _isLoadingConnections;
  Map<String, List<LiveConnection>> get upcomingConnections => _upcomingConnections;

  Future<void> startTrackingTrip(Trip trip, {Station? initialStation}) async {
    Trip activeTrip = trip;

    // Automatically fetch real-time intermediate stops from PTV API if empty
    if (activeTrip.stops.isEmpty && activeTrip.tripId.isNotEmpty) {
      try {
        final patternStops = await ptvService.fetchPatternStops(
          activeTrip.tripId,
          routeType: activeTrip.departure?.type.value ?? 0,
        );
        if (patternStops.isNotEmpty) {
          activeTrip = activeTrip.copyWith(stops: patternStops);
        }
      } catch (_) {}
    }

    _activeTrackedTrip = activeTrip;
    _isTrackingActive = true;

    final currentSt = initialStation ?? _selectedStation;
    _onBoardStation = currentSt;

    final stops = activeTrip.stops;
    if (stops.isNotEmpty) {
      final curIdx = stops.indexWhere((s) => s.station.isSameStopAs(currentSt));
      if (curIdx != -1) {
        _onBoardStation = stops[curIdx].station;
        _previousStopStation = curIdx > 0 ? stops[curIdx - 1].station : null;
        _nextStopStation = curIdx + 1 < stops.length ? stops[curIdx + 1].station : null;
      } else {
        _previousStopStation = null;
        _nextStopStation = stops.length > 1 ? stops[1].station : null;
      }
    } else {
      _previousStopStation = null;
      _nextStopStation = null;
    }

    notifyListeners();

    await locationService.startLocationTracking(
      onPositionChanged: handlePositionUpdate,
    );

    await refreshUpcomingConnections();
    _startTrackingPolling();
  }

  void stopTracking() {
    _activeTrackedTrip = null;
    _isTrackingActive = false;
    _onBoardStation = null;
    _previousStopStation = null;
    _nextStopStation = null;
    _upcomingConnections = {};
    _stopTrackingPolling();
    locationService.stopLocationTracking();
    notifyListeners();
  }

  Future<void> refreshUpcomingConnections() async {
    if (_activeTrackedTrip == null || _isRefreshingConnections) return;
    _isRefreshingConnections = true;
    _isLoadingConnections = true;
    notifyListeners();

    try {
      final connections = await connectionAdvisor.computeUpcomingConnections(
        activeTrip: _activeTrackedTrip!,
        currentOrNextStation: _nextStopStation ?? _onBoardStation ?? _selectedStation,
        allStations: _stations,
      );
      _upcomingConnections = connections;
    } catch (_) {
      // Keep existing
    } finally {
      _isRefreshingConnections = false;
      _isLoadingConnections = false;
      notifyListeners();
    }
  }

  void handlePositionUpdate(Position position) {
    if (!_isTrackingActive || _activeTrackedTrip == null) return;

    // When tracking an active trip, search only among that trip's stops for accurate matching.
    // Fall back to global station list if the trip has no resolved stops.
    final tripStops = _activeTrackedTrip!.stops;
    final Station? closestStation;

    if (tripStops.isNotEmpty) {
      // Find the closest stop on the current trip (tighter 500m radius for trams)
      closestStation = LocationService.findClosestStation(
        position.latitude,
        position.longitude,
        tripStops.map((s) => s.station).toList(),
        maxDistanceMeters: 500,
      );
    } else {
      // Global fallback (trains with large station spacing)
      closestStation = LocationService.findClosestStation(
        position.latitude,
        position.longitude,
        _stations,
        maxDistanceMeters: 1500,
      );
    }

    if (closestStation != null) {
      final stops = _activeTrackedTrip!.stops;
      final curIdx = stops.indexWhere((s) =>
          s.station.id == closestStation!.id ||
          s.station.stopId == closestStation.stopId ||
          s.station.name.toLowerCase() == closestStation.name.toLowerCase());

      if (curIdx != -1) {
        _onBoardStation = stops[curIdx].station;
        _previousStopStation = curIdx > 0 ? stops[curIdx - 1].station : null;
        _nextStopStation = curIdx + 1 < stops.length ? stops[curIdx + 1].station : null;
      } else {
        _onBoardStation = closestStation;
      }
      notifyListeners();
    }
  }

  List<Station> get searchResults {
    if (_searchQuery.isEmpty) return [];
    final query = _searchQuery.toLowerCase();
    return stations.where((s) => s.name.toLowerCase().contains(query)).toList();
  }

  /// Switches the active transit network mode (e.g. Trains → Trams).
  /// Saves the current station to a per-mode cache so it is restored on the way back.
  void switchBaseMode(PtvMode newMode) {
    if (_activeMode == newMode) return;
    _savedStationByMode[_activeMode] = _selectedStation;
    _activeMode = newMode;
    // Restore last-used stop for this mode, or fall back to default
    _selectedStation =
        _savedStationByMode[newMode] ?? MelbourneGtfsService.defaultStationForMode(newMode);
    _trips = [];
    _searchQuery = '';
    notifyListeners();
    loadData(station: _selectedStation, reuseStations: true);
  }
  void selectNavIndex(int index) {
    if (_selectedNavIndex != index) {
      _selectedNavIndex = index;
      notifyListeners();
    }
  }

  void updateSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void selectStation(Station station) {
    _selectedStation = station;
    _saveRecent(station);
    notifyListeners();
    loadData(station: station, reuseStations: true);
  }

  /// Fetches departures for a given interchange [station] **without** changing
  /// the currently tracked trip or selected station. Used by LiveRideSheet to
  /// peek at departures at a connecting station while the on-board ride stays active.
  Future<List<Trip>> fetchTripsForStation(Station station) async {
    try {
      // Use the route type of the active tracked trip if one is in progress,
      // otherwise fall back to the base mode's route type.
      final activeType = _activeTrackedTrip?.departure?.type;
      final effectiveRouteType = activeType?.value ?? _activeMode.ptvRouteType;
      final effectiveMode = activeType != null
          ? (activeType == TransitType.tram ? PtvMode.metroTram : PtvMode.metroTrain)
          : _activeMode;

      final livePtvTrips = await ptvService.fetchDepartures(
        station.stopId,
        station: station,
        routeType: effectiveRouteType,
        maxResults: 20,
      );
      if (livePtvTrips.isNotEmpty) return livePtvTrips;

      // Fallback: GTFS static timetable
      final scheduled = await repository.getTripsForMode(
        effectiveMode,
        station: station,
      );
      final now = DateTime.now();
      return scheduled.where((t) {
        final sched = t.departure?.scheduledTime;
        if (sched == null) return false;
        return sched.isAfter(now.subtract(const Duration(minutes: 2))) &&
               sched.isBefore(now.add(const Duration(hours: 1)));
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _saveRecent(Station station) async {
    try {
      final updated = await favoriteService.saveRecentStation(station);
      _recentStations = updated;
      notifyListeners();
    } catch (_) {}
  }

  /// Locates the device and returns the closest station; callers are
  /// responsible for selecting it.
  Future<Station?> locateNearestStation() async {
    _isLocating = true;
    notifyListeners();
    try {
      final pos = await locationService.getCurrentPosition();
      if (pos != null) {
        _userPosition = pos;
        final nearest = LocationService.findClosestStation(
          pos.latitude,
          pos.longitude,
          _stations,
          maxDistanceMeters: 100000,
        );
        if (nearest != null) return nearest;
      }
    } catch (_) {
    } finally {
      _isLocating = false;
      notifyListeners();
    }
    return null;
  }

  /// Refreshes the user's current GPS position.
  Future<void> refreshUserLocation() async {
    try {
      final pos = await locationService.getCurrentPosition();
      if (pos != null) {
        _userPosition = pos;
        notifyListeners();
      }
    } catch (_) {}
  }

  /// Checks if any current active service alert matches this trip's line, destination, or route.
  bool hasDisruptionForTrip(Trip trip) {
    if (_alerts.isEmpty) return false;
    final departure = trip.departure;
    final lineCode = (departure?.lineCode ?? trip.shortName ?? trip.routeId).toLowerCase().trim();
    final routeName = (departure?.routeName ?? '').toLowerCase().trim();
    final dest = trip.destinationName.toLowerCase().trim();

    return _alerts.any((alert) {
      final aLine = alert.lineCode.toLowerCase().trim();
      final aTitle = alert.title.toLowerCase().trim();
      final aDesc = alert.description.toLowerCase().trim();

      if (lineCode.isNotEmpty && (aLine.contains(lineCode) || lineCode.contains(aLine))) {
        return true;
      }
      if (routeName.isNotEmpty &&
          (aTitle.contains(routeName) || aDesc.contains(routeName) || aLine.contains(routeName))) {
        return true;
      }
      if (dest.isNotEmpty &&
          (aTitle.contains(dest) || aDesc.contains(dest))) {
        return true;
      }
      return false;
    });
  }

  void resetFilters() {
    _searchQuery = '';
    notifyListeners();
    loadData(station: _selectedStation, reuseStations: true);
  }

  Future<void> toggleFavoriteTrip(String tripId) async {
    await initFuture;
    _favoriteTripsVersion++;
    if (_favoriteTrips.contains(tripId)) {
      _favoriteTrips.remove(tripId);
    } else {
      _favoriteTrips.add(tripId);
    }
    notifyListeners();
    await favoriteService.saveFavoriteTrips(Set.of(_favoriteTrips));
  }

  bool isFavoriteTrip(String tripId) => _favoriteTrips.contains(tripId);

  Future<void> toggleFavoriteStation(Station station) async {
    await initFuture;
    _favoriteStationsVersion++;
    if (_favoriteStations.any((s) => s.id == station.id || s.name == station.name)) {
      _favoriteStations.removeWhere((s) => s.id == station.id || s.name == station.name);
    } else {
      _favoriteStations.add(station);
    }
    notifyListeners();
    await favoriteService.saveFavorites(List.of(_favoriteStations));
  }

  bool isFavoriteStation(Station station) =>
      _favoriteStations.any((s) => s.id == station.id || s.name == station.name);

  List<Trip> get filteredTrips {
    final query = _searchQuery.trim().toLowerCase();
    final filtered = _trips.where((trip) {
      final departure = trip.departure;
      final matchesQuery =
          query.isEmpty ||
          trip.destinationName.toLowerCase().contains(query) ||
          trip.destination.toLowerCase().contains(query) ||
          trip.headsign.toLowerCase().contains(query) ||
          (trip.shortName?.toLowerCase().contains(query) ?? false) ||
          (departure?.lineCode.toLowerCase().contains(query) ?? false) ||
          (departure?.routeName.toLowerCase().contains(query) ?? false);
      return matchesQuery;
    }).toList();

    return filtered;
  }

  List<Trip> get displayedTrips {
    final cached = _displayedCache;
    if (cached != null &&
        identical(_displayedCacheTrips, _trips) &&
        _displayedCacheQuery == _searchQuery &&
        _displayedCacheNav == _selectedNavIndex &&
        _displayedCacheFavVersion == _favoriteTripsVersion) {
      return cached;
    }

    final filtered = filteredTrips;
    final result = _selectedNavIndex == 1
        ? filtered.where((t) => _favoriteTrips.contains(t.tripId)).toList()
        : filtered;

    _displayedCache = result;
    _displayedCacheTrips = _trips;
    _displayedCacheQuery = _searchQuery;
    _displayedCacheNav = _selectedNavIndex;
    _displayedCacheFavVersion = _favoriteTripsVersion;
    return result;
  }

  /// Loads departures (and stations/alerts) for [station] in the active mode.
  ///
  /// Silent refreshes and loads with [reuseStations] set reuse the station list
  /// already loaded for the mode instead of re-checking stops.txt.
  Future<void> loadData({
    PtvMode? mode,
    Station? station,
    bool isSilent = false,
    bool reuseStations = false,
  }) async {
    final requestId = ++_loadRequestId;
    if (isSilent) _isSilentRefreshing = true;
    if (mode != null) {
      _activeMode = mode;
    }
    if (!isSilent) {
      _isLoading = true;
      _loadingProgress = 0.05;
      _loadingStatus = 'Downloading ${_activeMode == PtvMode.metroTram ? 'Tram' : 'Metro Train'} Timetable: 5%';
      _errorMessage = null;
      notifyListeners();
    }

    void updateProgress(double progress, String status) {
      if (!isSilent && requestId == _loadRequestId && !_isDisposed) {
        // Skip sub-percent updates: each notify rebuilds the whole home screen.
        if ((progress * 100).floor() == (_loadingProgress * 100).floor() &&
            status == _loadingStatus) {
          return;
        }
        _loadingProgress = progress;
        _loadingStatus = status;
        notifyListeners();
      }
    }

    try {
      // 1. Load GTFS Stations for the active mode from remote-streamed stops.txt
      // Silent refreshes reuse the station list already loaded for this mode.
      // The mode is captured before the await: switchBaseMode can change
      // _activeMode while the stations load is in flight.
      final stationsMode = _activeMode;
      final cachedStops = _stationsByMode[stationsMode];
      final canReuseStations =
          (isSilent || reuseStations) && cachedStops != null && cachedStops.isNotEmpty;
      final dynamicStops = canReuseStations
          ? cachedStops
          : await repository.getStopsForMode(
              stationsMode,
              onProgress: updateProgress,
            );
      if (!canReuseStations && dynamicStops.isNotEmpty) {
        _stationsByMode[stationsMode] = dynamicStops;
      }

      final stationList = dynamicStops.isNotEmpty
          ? dynamicStops
          : [MelbourneGtfsService.defaultStationForMode(stationsMode)];

      final requestedStation = station ?? _selectedStation;
      final reqNameClean = requestedStation.normalizedName;
      final currentSelected = stationList.firstWhere(
        (s) =>
            (requestedStation.stopId.isNotEmpty && s.stopId == requestedStation.stopId) ||
            (requestedStation.id.isNotEmpty && s.id == requestedStation.id) ||
            s.normalizedName == reqNameClean,
        orElse: () => requestedStation,
      );

      // Immediately register the full station list so station selector/search is populated
      if (requestId == _loadRequestId && !_isDisposed) {
        _stations = stationList;
        _selectedStation = currentSelected;
        notifyListeners();
      }

      // 2. Fetch Live Realtime Departures (Next 1 hour window) and Disruptions directly from PTV API
      updateProgress(0.60, 'Fetching Live Realtime Departures: 60%');
      // Disruptions and departures are independent, so fetch them concurrently.
      Future<List<ServiceAlert>> loadAlerts() async {
        try {
          final live = await ptvService.fetchLiveDisruptions();
          if (live.isNotEmpty) return live;
        } catch (_) {}
        try {
          return await repository.getServiceAlerts();
        } catch (_) {
          return <ServiceAlert>[];
        }
      }

      Future<List<Trip>> loadLiveTrips() async {
        try {
          return await ptvService.fetchDepartures(
            currentSelected.stopId,
            station: currentSelected,
            routeType: _activeMode.ptvRouteType, // 0 = Trains, 1 = Trams
            maxResults: 30,
          );
        } catch (_) {
          return <Trip>[];
        }
      }

      final results = await Future.wait<Object>([loadAlerts(), loadLiveTrips()]);
      final fetchedAlerts = results[0] as List<ServiceAlert>;
      final livePtvTrips = results[1] as List<Trip>;

      final now = DateTime.now();
      final oneHourFromNow = now.add(const Duration(hours: 1));

      List<Trip> mergedTrips = [];
      if (livePtvTrips.isNotEmpty) {
        mergedTrips = livePtvTrips;
      } else {
        // Fallback to static GTFS scheduled trips only if live PTV API returned empty
        updateProgress(0.85, 'Loading Scheduled Timetable Fallback...');
        try {
          final scheduledTrips = await repository.getTripsForMode(
            _activeMode,
            station: currentSelected,
            onProgress: updateProgress,
          );
          mergedTrips = scheduledTrips.where((t) {
            final sched = t.departure?.scheduledTime;
            if (sched == null) return false;
            return sched.isAfter(now.subtract(const Duration(minutes: 2))) &&
                   sched.isBefore(oneHourFromNow);
          }).toList();
        } catch (_) {}
      }

      // Departures are sorted chronologically by departure time (next arriving vehicle first)
      mergedTrips.sort((a, b) {
        final aTime = a.departure?.scheduledTime ?? now;
        final bTime = b.departure?.scheduledTime ?? now;
        final timeComparison = aTime.compareTo(bTime);
        if (timeComparison != 0) return timeComparison;

        final aLine = a.departure?.lineCode.isNotEmpty == true
            ? a.departure!.lineCode
            : a.destinationName;
        final bLine = b.departure?.lineCode.isNotEmpty == true
            ? b.departure!.lineCode
            : b.destinationName;
        return aLine.toLowerCase().compareTo(bLine.toLowerCase());
      });

      if (requestId == _loadRequestId && !_isDisposed) {
        _trips = mergedTrips;
        _alerts = fetchedAlerts;
        _stations = stationList;
        _selectedStation = currentSelected;
        if (!isSilent) {
          _isLoading = false;
          _loadingProgress = 1.0;
          _loadingStatus = 'Complete';
        }
        notifyListeners();
      }
    } catch (e) {
      if (requestId == _loadRequestId && !_isDisposed) {
        if (!isSilent) {
          _errorMessage = e is GtfsNetworkException
              ? e.message
              : 'Unable to refresh departures. Please check connection.';
          _isLoading = false;
          notifyListeners();
        }
      }
    } finally {
      if (isSilent) _isSilentRefreshing = false;
    }
  }
}
