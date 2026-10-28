import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../domain/entities/live_connection.dart';
import '../../domain/entities/station.dart';
import '../../domain/entities/trips.dart';
import '../../domain/entities/transit_route.dart';
import '../../data/repositories/gtfs_repository.dart';
import '../../services/location_service.dart';
import '../../services/ride_progress.dart';
import '../../services/connection_advisor_service.dart';
import '../../services/melbourne_gtfs_service.dart';
import '../../services/ptv_rt_service.dart';
import '../../services/favorite_service.dart';
import '../../services/settings_service.dart';

class TransitViewModel extends ChangeNotifier with WidgetsBindingObserver {
  final IGtfsRepository repository;
  final PtvRealtimeService ptvService;
  final FavoriteService favoriteService = FavoriteService();
  final LocationService locationService;
  final SettingsService _settings;
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

  // Walking time to the selected station (opt-in, persisted).
  bool _walkTimeEnabled = false;
  DateTime? _lastWalkLocationAt;
  static const Duration _walkLocationInterval = Duration(minutes: 1);

  /// Beyond this the walking time isn't meaningful, so it is hidden.
  static const double walkMaxMeters = 5000;

  // Active On-Board Ride Tracking & Connection Advisory State
  Trip? _activeTrackedTrip;
  Station? _onBoardStation;
  /// Index into the tracked trip's stops of the current / last-passed stop.
  int _rideIndex = 0;
  /// True when the rider is at [_onBoardStation]; false when travelling past it
  /// towards [_nextStopStation].
  bool _atStop = true;
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
  bool _isOffline = false;
  bool _usingStaticFallback = false;

  /// Data younger than this is not refetched when the app resumes.
  static const Duration _resumeRefreshThreshold = Duration(seconds: 15);
  final DateTime Function() _clock;
  DateTime? _lastRefreshAt;
  StreamSubscription<Position>? _positionSub;

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
    SettingsService? settingsService,
    DateTime Function()? clock,
  })  : _clock = clock ?? DateTime.now,
        _settings = settingsService ?? SettingsService(),
        ptvService = ptvService ?? PtvRealtimeService(),
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
    _walkTimeEnabled = await _settings.getWalkTimeEnabled();
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _autoRefreshTimer?.cancel();
    _trackingPollingTimer?.cancel();
    _positionSub?.cancel();
    _positionSub = null;
    if (_isTrackingActive) locationService.stopLocationTracking();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Starts a 30-second periodic timer that re-fetches departure data.
  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = _newAutoRefreshTimer();
  }

  Timer _newAutoRefreshTimer() => Timer.periodic(const Duration(seconds: 30), (_) {
        if (!_isDisposed && !_isLoading && !_isSilentRefreshing) {
          loadData(station: _selectedStation, isSilent: true);
        }
      });

  /// Pauses or resumes the auto-refresh timer based on the app lifecycle.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        // Restart only timers that were stopped while in the background.
        _autoRefreshTimer ??= _newAutoRefreshTimer();
        if (_isTrackingActive && _trackingPollingTimer == null) {
          _startTrackingPolling();
        }
        // Skip the refetch for brief inactive->resumed blips (permission
        // dialogs, notification shade) when the data is still fresh.
        final last = _lastRefreshAt;
        final fresh =
            last != null && _clock().difference(last) < _resumeRefreshThreshold;
        if (!fresh && !_isLoading && !_isSilentRefreshing) {
          loadData(station: _selectedStation, isSilent: true);
        }
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _autoRefreshTimer?.cancel();
        _autoRefreshTimer = null;
        _stopTrackingPolling();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  /// Connections are only displayed in the Live Ride sheet, so poll quickly
  /// while it is open and slowly (just to keep data warm) while it is closed.
  static const Duration _visiblePollInterval = Duration(seconds: 20);
  static const Duration _hiddenPollInterval = Duration(seconds: 90);

  int _liveRideViewers = 0;
  DateTime? _connectionsRefreshedAt;
  bool get _liveRideVisible => _liveRideViewers > 0;

  /// Called by the Live Ride sheet when it mounts.
  void liveRideSheetOpened() {
    if (_isDisposed) return;
    _liveRideViewers++;
    if (_liveRideViewers != 1) return;
    if (_isTrackingActive && _trackingPollingTimer != null) {
      _startTrackingPolling();
    }
    final refreshedAt = _connectionsRefreshedAt;
    if (_isTrackingActive &&
        (refreshedAt == null ||
            DateTime.now().difference(refreshedAt) > _visiblePollInterval)) {
      // Never refresh synchronously: the sheet builds inside a ListenableBuilder.
      Future.microtask(() {
        if (!_isDisposed) refreshUpcomingConnections();
      });
    }
  }

  /// Called by the Live Ride sheet when it is disposed.
  void liveRideSheetClosed() {
    if (_isDisposed || _liveRideViewers == 0) return;
    _liveRideViewers--;
    if (_liveRideViewers == 0 && _isTrackingActive && _trackingPollingTimer != null) {
      _startTrackingPolling();
    }
  }

  /// Starts periodic polling for upcoming connections while tracking a trip.
  void _startTrackingPolling() {
    _trackingPollingTimer?.cancel();
    final interval = _liveRideVisible ? _visiblePollInterval : _hiddenPollInterval;
    _trackingPollingTimer = Timer.periodic(interval, (_) {
      if (!_isDisposed && _isTrackingActive) {
        refreshUpcomingConnections(showSpinner: false);
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

  /// Bumped on every favourites change; lets widgets select on a cheap value
  /// (the favourites collections are mutated in place).
  int get favoriteStationsVersion => _favoriteStationsVersion;
  int get favoriteTripsVersion => _favoriteTripsVersion;
  Position? get userPosition => _userPosition;
  bool get isLocating => _isLocating;
  bool get isLoading => _isLoading;

  /// True when the last live departures request failed (no connection).
  bool get isOffline => _isOffline;

  /// True when the departures shown come from the static timetable because
  /// the live feed returned nothing, so times may be inaccurate.
  bool get usingStaticFallback => _usingStaticFallback;
  double get loadingProgress => _loadingProgress;
  String get loadingStatus => _loadingStatus;
  int get loadingPercentage => (_loadingProgress * 100).clamp(0, 100).toInt();
  String? get errorMessage => _errorMessage;

  // Active Live Ride Tracking & Connections
  Trip? get activeTrackedTrip => _activeTrackedTrip;
  Station? get onBoardStation => _onBoardStation;
  Station? get currentStopStation => _onBoardStation;
  /// True while the train is travelling between [currentStopStation] (last stop
  /// passed) and [nextStopStation]; false when at a stop.
  bool get isBetweenStops => _isTrackingActive && !_atStop && _nextStopStation != null;
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
    _rideIndex = 0;
    _atStop = true;
    _previousStopStation = null;
    _nextStopStation = null;
    if (stops.isNotEmpty) {
      final curIdx = stops.indexWhere((s) => s.station.isSameStopAs(currentSt));
      if (curIdx != -1) {
        _setRideIndex(curIdx);
      } else {
        // Boarding stop isn't on the trip: don't guess a neighbour (the old
        // stops[1] could be behind the rider). Use timetable times if we have
        // them; otherwise wait for the first GPS fix.
        final now = _clock();
        final nextIdx = stops.indexWhere((s) {
          final t = s.arrivalTime ?? s.departureTime;
          return t != null && t.isAfter(now);
        });
        if (nextIdx != -1) {
          _rideIndex = nextIdx > 0 ? nextIdx - 1 : 0;
          _atStop = nextIdx == 0;
          _previousStopStation = nextIdx > 1 ? stops[nextIdx - 2].station : null;
          _onBoardStation = nextIdx > 0 ? stops[nextIdx - 1].station : currentSt;
          _nextStopStation = stops[nextIdx].station;
        }
      }
    }

    notifyListeners();

    // Don't block the first connections refresh on the (possibly interactive)
    // location-permission flow.
    // Single delivery path: the stream feeds handlePositionUpdate once per fix
    // whether or not the Live Ride sheet is open.
    _positionSub ??= locationService.positionStream.listen(handlePositionUpdate);
    final locationFuture = locationService.startLocationTracking();

    await refreshUpcomingConnections();
    if (_isTrackingActive) _startTrackingPolling();

    await locationFuture;
    if (!_isTrackingActive) {
      // Tracking ended while the location service was still starting.
      _positionSub?.cancel();
      _positionSub = null;
      await locationService.stopLocationTracking();
    }
  }

  void stopTracking() {
    _activeTrackedTrip = null;
    _isTrackingActive = false;
    _onBoardStation = null;
    _rideIndex = 0;
    _atStop = true;
    _previousStopStation = null;
    _nextStopStation = null;
    _upcomingConnections = {};
    _connectionsRefreshedAt = null;
    _stopTrackingPolling();
    _positionSub?.cancel();
    _positionSub = null;
    locationService.stopLocationTracking();
    notifyListeners();
  }

  /// Recomputes connecting services for the tracked trip. Background polls pass
  /// [showSpinner] false so the sheet doesn't flash a spinner every cycle.
  Future<void> refreshUpcomingConnections({bool showSpinner = true}) async {
    if (_activeTrackedTrip == null) return;
    if (_isRefreshingConnections) {
      // A poll is already running: reflect it in the UI for a manual refresh.
      if (showSpinner && !_isLoadingConnections) {
        _isLoadingConnections = true;
        notifyListeners();
      }
      return;
    }
    _isRefreshingConnections = true;
    if (showSpinner) {
      _isLoadingConnections = true;
      notifyListeners();
    }

    final trackedTrip = _activeTrackedTrip!;
    try {
      final connections = await connectionAdvisor.computeUpcomingConnections(
        activeTrip: trackedTrip,
        currentOrNextStation: _nextStopStation ?? _onBoardStation ?? _selectedStation,
        allStations: _stations,
      );
      // Ignore a result that arrives after tracking ended or switched trips.
      if (identical(_activeTrackedTrip, trackedTrip)) {
        _upcomingConnections = connections;
        _connectionsRefreshedAt = DateTime.now();
      }
    } catch (_) {
      // Keep existing
    } finally {
      _isRefreshingConnections = false;
      _isLoadingConnections = false;
      notifyListeners();
    }
  }

  /// Points on-board / previous / next at the stop [index] of the tracked trip.
  void _setRideIndex(int index, {bool atStop = true}) {
    final stops = _activeTrackedTrip!.stops;
    _rideIndex = index;
    _atStop = atStop;
    _onBoardStation = stops[index].station;
    _previousStopStation = index > 0 ? stops[index - 1].station : null;
    _nextStopStation = index + 1 < stops.length ? stops[index + 1].station : null;
  }

  void handlePositionUpdate(Position position) {
    if (!_isTrackingActive || _activeTrackedTrip == null) return;

    final oldOn = _onBoardStation;
    final oldPrev = _previousStopStation;
    final oldNext = _nextStopStation;
    final oldAtStop = _atStop;
    final tripStops = _activeTrackedTrip!.stops;

    // Locate the fix along the trip's own ordered stops. This tracks the rider
    // between stations too (current = last stop passed, next = the one ahead)
    // and never moves backwards.
    final progress = tripStops.isEmpty
        ? null
        : locateOnTrip(
            tripStops,
            position.latitude,
            position.longitude,
            minIndex: _rideIndex,
          );

    if (progress != null) {
      _setRideIndex(progress.index, atStop: progress.atStop);
    } else if (!tripStops.any((s) => s.station.lat != 0.0 || s.station.lon != 0.0)) {
      // Trip stops carry no coordinates: fall back to the global station list.
      final closest = LocationService.findClosestStation(
        position.latitude,
        position.longitude,
        _stations,
        maxDistanceMeters: 1500,
      );
      if (closest != null) {
        final idx = tripStops.indexWhere((s) => s.station.isSameStopAs(closest));
        if (idx != -1) {
          _setRideIndex(idx);
        } else {
          _onBoardStation = closest;
        }
      }
    }

    // GPS fixes arrive constantly but the stop only changes every few
    // minutes; avoid rebuilding listeners when nothing visible moved.
    if (oldAtStop != _atStop ||
        !identical(oldOn, _onBoardStation) ||
        !identical(oldPrev, _previousStopStation) ||
        !identical(oldNext, _nextStopStation)) {
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
    _usingStaticFallback = false;
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
          ? PtvMode.fromTransitType(activeType)
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
  /// Live stop search for modes without a downloaded stop list.
  Future<List<Station>> searchLiveStops(String query) => ptvService
      .searchStations(query, routeType: _activeMode.ptvRouteType);

  Future<Station?> locateNearestStation() async {
    _isLocating = true;
    notifyListeners();
    try {
      final pos = await locationService.getCurrentPosition();
      if (pos != null && _activeMode.isLiveOnly) {
        _userPosition = pos;
        final nearby = await ptvService.nearbyStops(
          pos.latitude,
          pos.longitude,
          routeType: _activeMode.ptvRouteType,
        );
        return nearby.isEmpty ? null : nearby.first;
      }
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

  bool get walkTimeEnabled => _walkTimeEnabled;

  /// Straight-line metres from the user to the selected station, or null when
  /// walking time is off, the position or station coordinates are unknown, or
  /// the station is too far for a walk to make sense.
  double? get walkDistanceMeters {
    final pos = _userPosition;
    final station = _selectedStation;
    if (!_walkTimeEnabled || pos == null) return null;
    if (station.lat == 0.0 && station.lon == 0.0) return null;
    final meters = LocationService.calculateDistanceMeters(
      pos.latitude,
      pos.longitude,
      station.lat,
      station.lon,
    );
    return meters <= walkMaxMeters ? meters : null;
  }

  /// Walking time to the selected station, see [walkDistanceMeters].
  Duration? get walkToSelectedStation {
    final meters = walkDistanceMeters;
    if (meters == null) return null;
    return Duration(minutes: LocationService.walkingMinutes(meters));
  }

  /// When the user must set off to catch [trip], or null without a walk time.
  DateTime? leaveByFor(Trip trip) {
    final walk = walkToSelectedStation;
    final departs = trip.departure?.scheduledTime;
    if (walk == null || departs == null) return null;
    return departs.subtract(
      walk + const Duration(minutes: LocationService.walkingBufferMinutes),
    );
  }

  /// False only when the walk time is known and [trip] leaves before the user
  /// could get there.
  bool canCatch(Trip trip) {
    final leaveBy = leaveByFor(trip);
    return leaveBy == null || !leaveBy.isBefore(_clock());
  }

  /// Turns walking time on or off. Turning it on asks for location permission.
  Future<void> toggleWalkTime() async {
    _walkTimeEnabled = !_walkTimeEnabled;
    notifyListeners();
    await _settings.setWalkTimeEnabled(_walkTimeEnabled);
    if (_walkTimeEnabled) {
      _lastWalkLocationAt = _clock();
      await refreshUserLocation();
    }
  }

  /// Keeps the position fresh for walking time without ever prompting: only
  /// runs when it is enabled and permission was already granted.
  Future<void> _refreshWalkLocation() async {
    if (!_walkTimeEnabled) return;
    final now = _clock();
    final last = _lastWalkLocationAt;
    if (last != null && now.difference(last) < _walkLocationInterval) return;
    _lastWalkLocationAt = now;
    if (!await locationService.hasPermission()) return;
    await refreshUserLocation();
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
  Future<void>? _initialLoad;

  // Alerts load alongside departures but are applied after them, so the list
  // appears without waiting for the (larger) disruptions feed.
  int _alertLoadsInFlight = 0;

  static bool _sameAlerts(List<ServiceAlert> a, List<ServiceAlert> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].title != b[i].title ||
          a[i].description != b[i].description) {
        return false;
      }
    }
    return true;
  }
  bool get isLoadingAlerts => _alertLoadsInFlight > 0;

  /// Starts the first data load once; later calls return the same future.
  /// main() calls this before the first frame so loading overlaps theme and UI
  /// startup, and HomeScreen calls it again harmlessly.
  Future<void> ensureInitialLoad() => _initialLoad ??= loadData();

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
      _lastRefreshAt = null;
      _isLoading = true;
      _loadingProgress = 0.05;
      _loadingStatus = 'Downloading ${switch (_activeMode) {
        PtvMode.metroTram => 'Tram',
        PtvMode.regionalTrain => 'V/Line',
        PtvMode.metroBus => 'Bus',
        _ => 'Metro Train',
      }} Timetable: 5%';
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

    var alertLoadHeld = false;
    bool releaseAlertLoad() {
      if (!alertLoadHeld) return false;
      alertLoadHeld = false;
      _alertLoadsInFlight--;
      return true;
    }

    try {
      final routeType = _activeMode.ptvRouteType; // 0 = Trains, 1 = Trams, 3 = V/Line

      // Disruptions are independent of the station, so start them straight away.
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

      final alertsFuture = loadAlerts();
      if (!isSilent) {
        _alertLoadsInFlight++;
        alertLoadHeld = true;
      }

      // Favourites restored by _init can change the default selection.
      if (station == null) {
        try {
          await initFuture;
        } catch (_) {}
      }
      final requestedStation = station ?? _selectedStation;

      var liveFeedFailed = false;
      Future<List<Trip>> loadLiveTrips(Station s) async {
        // Live-only modes have no stop until the user picks one.
        if (_activeMode.isLiveOnly && s.stopId.isEmpty) return <Trip>[];
        try {
          final trips = await ptvService.fetchDepartures(
            s.stopId,
            station: s,
            routeType: routeType,
            maxResults: 20,
          );
          liveFeedFailed = false;
          return trips;
        } catch (_) {
          liveFeedFailed = true;
          return <Trip>[];
        }
      }

      // 1. Load GTFS Stations for the active mode from remote-streamed stops.txt
      // Silent refreshes and station taps reuse the list already loaded for this mode.
      // The mode is captured before the await: switchBaseMode can change
      // _activeMode while the stations load is in flight.
      final stationsMode = _activeMode;
      final cachedStops = _stationsByMode[stationsMode];
      final canReuseStations =
          (isSilent || reuseStations) && cachedStops != null && cachedStops.isNotEmpty;

      // When the requested station's PTV id is known offline, start its
      // departures request now instead of waiting for the stations step.
      final specId = canReuseStations
          ? null
          : ptvService.peekResolvedStopId(requestedStation, routeType: routeType);
      final Future<List<Trip>>? speculativeTrips =
          specId != null ? loadLiveTrips(requestedStation) : null;

      List<Station> dynamicStops;
      if (canReuseStations) {
        dynamicStops = cachedStops;
      } else if (stationsMode.isLiveOnly) {
        // Static data may not be hosted (or may fail to load): carry on with
        // live PTV search and departures alone.
        try {
          dynamicStops = await repository.getStopsForMode(
            stationsMode,
            onProgress: updateProgress,
          );
        } catch (_) {
          dynamicStops = <Station>[];
        }
      } else {
        dynamicStops = await repository.getStopsForMode(
          stationsMode,
          onProgress: updateProgress,
        );
      }
      if (!canReuseStations && dynamicStops.isNotEmpty) {
        _stationsByMode[stationsMode] = dynamicStops;
      }

      final stationList = dynamicStops.isNotEmpty
          ? dynamicStops
          : stationsMode.isLiveOnly
          ? [if (requestedStation.stopId.isNotEmpty) requestedStation]
          : [MelbourneGtfsService.defaultStationForMode(stationsMode)];

      final reqNameClean = requestedStation.normalizedName;
      final currentSelected = stationList.firstWhere(
        (s) =>
            (requestedStation.stopId.isNotEmpty && s.stopId == requestedStation.stopId) ||
            (requestedStation.id.isNotEmpty && s.id == requestedStation.id) ||
            s.normalizedName == reqNameClean,
        orElse: () => requestedStation,
      );

      // Immediately register the full station list so station selector/search is populated
      if (requestId == _loadRequestId &&
          !_isDisposed &&
          (!identical(_stations, stationList) ||
              !identical(_selectedStation, currentSelected))) {
        _stations = stationList;
        _selectedStation = currentSelected;
        notifyListeners();
      }

      // 2. Fetch Live Realtime Departures (Next 1 hour window) and Disruptions directly from PTV API
      updateProgress(0.60, 'Fetching Live Realtime Departures: 60%');
      final reuseSpeculative = speculativeTrips != null &&
          (identical(currentSelected, requestedStation) ||
              specId ==
                  ptvService.peekResolvedStopId(currentSelected, routeType: routeType));
      final tripsFuture =
          reuseSpeculative ? speculativeTrips : loadLiveTrips(currentSelected);

      final livePtvTrips = await tripsFuture;

      final now = DateTime.now();
      final oneHourFromNow = now.add(const Duration(hours: 1));

      List<Trip> mergedTrips = [];
      var fromStaticFallback = false;
      if (livePtvTrips.isNotEmpty) {
        mergedTrips = livePtvTrips;
      } else if (_activeMode.isLiveOnly && currentSelected.stopId.isEmpty) {
        // No stop chosen yet, so there is nothing to look up.
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
          fromStaticFallback = mergedTrips.isNotEmpty;
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
        _usingStaticFallback = fromStaticFallback;
        _stations = stationList;
        _selectedStation = currentSelected;
        if (!isSilent) {
          _isLoading = false;
          _loadingProgress = 1.0;
          _loadingStatus = 'Complete';
        }
        _isOffline = liveFeedFailed;
        _lastRefreshAt = _clock();
        // Count the next auto-refresh from this load, not from app start.
        if (_autoRefreshTimer != null) _startAutoRefresh();
        notifyListeners();
        unawaited(_refreshWalkLocation());
      }

      // Alerts were requested in parallel; apply them now (usually already done).
      final fetchedAlerts = await alertsFuture;
      final released = releaseAlertLoad();
      if (requestId == _loadRequestId && !_isDisposed) {
        final changed = !_sameAlerts(fetchedAlerts, _alerts);
        if (changed) _alerts = fetchedAlerts;
        if (changed || released) notifyListeners();
      }
    } catch (e) {
      if (requestId == _loadRequestId && !_isDisposed) {
        if (!_isOffline) {
          _isOffline = true;
          if (isSilent) notifyListeners();
        }
        if (!isSilent) {
          _errorMessage = e is GtfsNetworkException
              ? e.message
              : 'Unable to refresh departures. Please check connection.';
          _isLoading = false;
          notifyListeners();
        }
      }
    } finally {
      if (releaseAlertLoad() && !_isDisposed) notifyListeners();
      if (isSilent) _isSilentRefreshing = false;
    }
  }
}
