import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/repositories/gtfs_repository.dart';
import '../../theme/app_theme.dart';
import '../state/transit_view_model.dart';
import '../state/theme_view_model.dart';
import '../widgets/alert_banner_widget.dart';
import '../widgets/app_header_widget.dart';
import '../widgets/empty_state_widget.dart';
import '../widgets/station_selector_card.dart';
import '../widgets/transit_mode_slider.dart';
import '../widgets/trip_card_widget.dart';
import '../widgets/trip_details_sheet.dart';
import '../widgets/live_ride_sheet.dart';
import 'disruptions_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Trigger the first data load after the widget tree is built.
      context.read<TransitViewModel>().loadData();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<TransitViewModel>();
    final theme = Theme.of(context);
    if (_searchController.text != viewModel.searchQuery && viewModel.searchQuery.isEmpty) {
      _searchController.clear();
    }
    final displayedTrips = viewModel.displayedTrips;
    final isSavedView = viewModel.selectedNavIndex == 1;
    final isDisruptionsView = viewModel.selectedNavIndex == 2;

    if (isDisruptionsView) {
      return Scaffold(
        body: SafeArea(
          child: DisruptionsScreen(
            alerts: viewModel.favoriteStationDisruptions,
            allAlerts: viewModel.alerts,
            favoriteStations: viewModel.favoriteStations,
            selectedStation: viewModel.selectedStation,
            isLoading: viewModel.isLoading,
            onRefresh: viewModel.loadData,
          ),
        ),
        bottomNavigationBar: LayoutBuilder(
          builder: (context, constraints) {
            final sideMargin = constraints.maxWidth > 840
                ? (constraints.maxWidth - 840) / 2
                : 0.0;
            return _buildNavigationBar(viewModel, sideMargin: sideMargin);
          },
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final sideMargin = constraints.maxWidth > 840
                ? (constraints.maxWidth - 840) / 2
                : 0.0;

            return Padding(
              padding: EdgeInsets.symmetric(horizontal: sideMargin),
                  child: RefreshIndicator(
                    onRefresh: viewModel.loadData,
                    color: AppColors.primaryCyan,
                    child: CustomScrollView(
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.all(20.0),
                          sliver: SliverToBoxAdapter(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                AppHeaderWidget(
                                  isLoading: viewModel.isLoading,
                                  loadingProgress: viewModel.loadingProgress,
                                  loadingPercentage: viewModel.loadingPercentage,
                                  loadingStatus: viewModel.loadingStatus,
                                  activeMode: viewModel.activeMode,
                                  onRefresh: viewModel.loadData,
                                  onToggleTheme: () {
                                    try {
                                      final themeVm = Provider.of<ThemeViewModel>(context, listen: false);
                                      final isDark = theme.brightness == Brightness.dark;
                                      themeVm.setThemeMode(isDark ? ThemeMode.light : ThemeMode.dark);
                                    } catch (_) {}
                                  },
                                ),
                                if (viewModel.isLoading) ...[
                                  const SizedBox(height: 12),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: LinearProgressIndicator(
                                      value: viewModel.loadingProgress > 0.0
                                          ? viewModel.loadingProgress
                                          : null,
                                      backgroundColor: theme.cardColor,
                                      color: AppColors.primaryCyan,
                                      minHeight: 6,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 16),

                                // Mode Slider (Trains / Trams)
                                TransitModeSlider(
                                  activeMode: viewModel.activeMode,
                                  onModeChanged: viewModel.switchBaseMode,
                                ),
                                const SizedBox(height: 10),

                                // ── Quick Station Strip ─────────────────────
                                _QuickStationStrip(viewModel: viewModel),
                                const SizedBox(height: 10),

                                // Station Selector Card with Instant Search & Favorite Action
                                StationSelectorCard(
                                  selectedStation: viewModel.selectedStation,
                                  stations: viewModel.stations,
                                  favoriteStations: viewModel.favoriteStations,
                                  recentStations: viewModel.recentStations,
                                  userPosition: viewModel.userPosition,
                                  activeMode: viewModel.activeMode,
                                  onLocateNearest: viewModel.locateNearestStation,
                                  onStationSelected: viewModel.selectStation,
                                  onToggleFavorite: viewModel.toggleFavoriteStation,
                                ),
                                const SizedBox(height: 14),

                                // Search departures/routes for the selected station
                                TextField(
                                  controller: _searchController,
                                  onChanged: viewModel.updateSearchQuery,
                                  decoration: InputDecoration(
                                    hintText: viewModel.activeMode == PtvMode.metroTram
                                        ? 'Filter tram routes at ${viewModel.selectedStation.name}...'
                                        : 'Filter train lines at ${viewModel.selectedStation.name}...',
                                    prefixIcon: Icon(
                                      viewModel.activeMode == PtvMode.metroTram
                                          ? Icons.tram_rounded
                                          : Icons.search_rounded,
                                      color: viewModel.activeMode == PtvMode.metroTram
                                          ? AppColors.melbourneTram
                                          : null,
                                    ),
                                    suffixIcon: viewModel.searchQuery.isNotEmpty
                                        ? IconButton(
                                            icon: const Icon(Icons.clear_rounded),
                                            onPressed: () {
                                              _searchController.clear();
                                              viewModel.updateSearchQuery('');
                                            },
                                            tooltip: 'Clear filter',
                                          )
                                        : null,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        if (viewModel.errorMessage != null)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20.0,
                                vertical: 4.0,
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.statusAmber.withAlpha(26),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: AppColors.statusAmber.withAlpha(100),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.warning_amber_rounded,
                                      color: AppColors.statusAmber,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        viewModel.errorMessage!,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: viewModel.loadData,
                                      child: const Text('Retry'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                        if (viewModel.alerts.isNotEmpty)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20.0,
                                vertical: 4.0,
                              ),
                              child: AlertBannerWidget(
                                alert: viewModel.alerts.first,
                              ),
                            ),
                          ),

                        // Saved View: Favorite Stations Section
                        if (isSavedView && viewModel.favoriteStations.isNotEmpty) ...[
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                            sliver: SliverToBoxAdapter(
                              child: Text(
                                'FAVORITE STATIONS',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.0,
                                  color: theme.textTheme.bodySmall?.color?.withAlpha(150),
                                ),
                              ),
                            ),
                          ),
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 20.0),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate((context, index) {
                                final st = viewModel.favoriteStations[index];
                                final isSelected = st.name == viewModel.selectedStation.name;
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8.0),
                                  child: ListTile(
                                    leading: const Icon(
                                      Icons.star_rounded,
                                      color: AppColors.statusAmber,
                                    ),
                                    title: Text(
                                      st.name,
                                      style: TextStyle(
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: Text(st.zone.isNotEmpty ? st.zone : 'Zone 1'),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.close_rounded, size: 18),
                                      onPressed: () => viewModel.toggleFavoriteStation(st),
                                      tooltip: 'Remove Favorite',
                                    ),
                                    onTap: () {
                                      viewModel.selectStation(st);
                                      viewModel.selectNavIndex(0);
                                    },
                                  ),
                                );
                              }, childCount: viewModel.favoriteStations.length),
                            ),
                          ),
                        ],

                        // Saved View: Recent Stations Section
                        if (isSavedView && viewModel.recentStations.isNotEmpty) ...[
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                            sliver: SliverToBoxAdapter(
                              child: Text(
                                'RECENT STATIONS',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.0,
                                  color: theme.textTheme.bodySmall?.color?.withAlpha(150),
                                ),
                              ),
                            ),
                          ),
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 20.0),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate((context, index) {
                                final st = viewModel.recentStations[index];
                                final isSelected = st.name == viewModel.selectedStation.name;
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8.0),
                                  child: ListTile(
                                    leading: const Icon(
                                      Icons.history_rounded,
                                      color: AppColors.secondaryIndigo,
                                    ),
                                    title: Text(
                                      st.name,
                                      style: TextStyle(
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: Text(st.zone.isNotEmpty ? st.zone : 'Zone 1'),
                                    onTap: () {
                                      viewModel.selectStation(st);
                                      viewModel.selectNavIndex(0);
                                    },
                                  ),
                                );
                              }, childCount: viewModel.recentStations.length),
                            ),
                          ),
                        ],

                        // Section Title Header
                        SliverPadding(
                          padding: const EdgeInsets.only(
                            left: 20,
                            right: 20,
                            top: 16,
                            bottom: 8,
                          ),
                          sliver: SliverToBoxAdapter(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    isSavedView
                                        ? 'Saved Departures'
                                        : 'Scheduled Departures • ${viewModel.selectedStation.name}',
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.cardColor,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: theme.dividerColor.withAlpha(40),
                                    ),
                                  ),
                                  child: Text(
                                    '${displayedTrips.length} trips',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.primaryCyan,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        if (viewModel.isLoading)
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 20.0),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) => Card(
                                  margin: const EdgeInsets.only(bottom: 12.0),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Column(
                                      children: [
                                        Container(
                                          height: 20,
                                          color: Colors.white10,
                                        ),
                                        const SizedBox(height: 10),
                                        Container(
                                          height: 14,
                                          color: Colors.white10,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                childCount: 3,
                              ),
                            ),
                          )
                        else if (displayedTrips.isEmpty)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: EmptyStateWidget(
                              isSavedView: isSavedView,
                              onReset: isSavedView
                                  ? () => viewModel.selectNavIndex(0)
                                  : () {
                                      _searchController.clear();
                                      viewModel.resetFilters();
                                    },
                            ),
                          )
                        else
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 20.0),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate((
                                context,
                                index,
                              ) {
                                final trip = displayedTrips[index];
                                return TripCardWidget(
                                  trip: trip,
                                  isFavorite: viewModel.isFavoriteTrip(trip.tripId),
                                  hasDisruption: viewModel.hasDisruptionForTrip(trip),
                                  onToggleFavorite: () =>
                                      viewModel.toggleFavoriteTrip(trip.tripId),
                                  onTap: () => TripDetailsSheet.show(
                                    context,
                                    trip: trip,
                                    selectedStation: viewModel.selectedStation,
                                    viewModel: viewModel,
                                  ),
                                );
                              }, childCount: displayedTrips.length),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          bottomNavigationBar: LayoutBuilder(
            builder: (context, constraints) {
              final sideMargin = constraints.maxWidth > 840
                  ? (constraints.maxWidth - 840) / 2
                  : 0.0;
              return _buildNavigationBar(viewModel, sideMargin: sideMargin);
            },
          ),
        );
      }

  Widget _buildNavigationBar(TransitViewModel viewModel, {double sideMargin = 0.0}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (viewModel.isTrackingActive && viewModel.activeTrackedTrip != null)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: sideMargin),
            child: _ActiveRideMiniPlayer(viewModel: viewModel),
          ),
        NavigationBar(
          selectedIndex: viewModel.selectedNavIndex,
          onDestinationSelected: viewModel.selectNavIndex,
      destinations: [
        const NavigationDestination(
          icon: Icon(Icons.directions_transit_outlined),
          selectedIcon: Icon(Icons.directions_transit_rounded),
          label: 'Departures',
        ),
        NavigationDestination(
          icon: const Icon(Icons.star_outline_rounded),
          selectedIcon: const Icon(Icons.star_rounded),
          label: 'Saved',
        ),
        NavigationDestination(
          icon: Badge(
            isLabelVisible: viewModel.favoriteStationDisruptions.isNotEmpty,
            label: Text('${viewModel.favoriteStationDisruptions.length}'),
            child: const Icon(Icons.warning_amber_rounded),
          ),
          selectedIcon: Badge(
            isLabelVisible: viewModel.favoriteStationDisruptions.isNotEmpty,
            label: Text('${viewModel.favoriteStationDisruptions.length}'),
            child: const Icon(Icons.warning_rounded),
          ),
          label: 'Disruptions',
        ),
      ],
    ),
  ],
);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quick Station Strip
// ─────────────────────────────────────────────────────────────────────────────

/// Horizontal scrollable row of pill chips for favorite + recent stations,
/// allowing 1-tap switching without opening the full station picker.
class _QuickStationStrip extends StatelessWidget {
  final TransitViewModel viewModel;

  const _QuickStationStrip({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final favorites = viewModel.favoriteStations;
    final recents = viewModel.recentStations;

    // Show only stations relevant to the active mode; combine favorites first then recents.
    final combined = [
      ...favorites,
      ...recents.where((r) => !favorites.any((f) => f.id == r.id || f.name == r.name)),
    ];

    if (combined.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: combined.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final station = combined[index];
          final isActive = station.name == viewModel.selectedStation.name;
          final isFav = viewModel.isFavoriteStation(station);

          return Semantics(
            label: '${isActive ? 'Currently selected: ' : ''}${station.name}',
            button: true,
            child: GestureDetector(
              onTap: () {
                viewModel.selectStation(station);
                if (viewModel.selectedNavIndex != 0) {
                  viewModel.selectNavIndex(0);
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isActive
                      ? AppColors.primaryCyan
                      : Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isActive
                        ? AppColors.primaryCyan
                        : Theme.of(context).dividerColor.withAlpha(50),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isFav) ...[
                      Icon(
                        Icons.star_rounded,
                        size: 11,
                        color: isActive ? Colors.white : AppColors.statusAmber,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      // Strip " Station" suffix for compactness
                      station.name.replaceAll(RegExp(r'\s+[Ss]tation$'), ''),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                        color: isActive
                            ? Colors.white
                            : Theme.of(context).textTheme.bodyMedium?.color,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Persistent Active Ride Mini-Player
// ─────────────────────────────────────────────────────────────────────────────

/// A compact banner that stays pinned above the navigation bar when a trip
/// is being tracked, even as the user scrolls or switches tabs.
class _ActiveRideMiniPlayer extends StatelessWidget {
  final TransitViewModel viewModel;

  const _ActiveRideMiniPlayer({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final trip = viewModel.activeTrackedTrip!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => LiveRideSheet.show(context, viewModel),
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primaryCyan, AppColors.secondaryIndigo],
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryCyan.withAlpha(100),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(30),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.gps_fixed_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'ON-BOARD TRACKING ACTIVE',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          'To ${trip.destinationName}'
                          '${viewModel.currentStopStation?.name != null ? ' • ${viewModel.currentStopStation!.name}' : ''}'
                          '${viewModel.nextStopStation != null ? ' → ${viewModel.nextStopStation!.name}' : ''}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Colors.white),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
