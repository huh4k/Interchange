import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/repositories/gtfs_repository.dart';
import '../../theme/app_theme.dart';
import '../state/transit_view_model.dart';
import '../state/theme_view_model.dart';
import '../widgets/active_ride_mini_player.dart';
import '../widgets/alert_banner_widget.dart';
import '../widgets/app_header_widget.dart';
import '../widgets/empty_state_widget.dart';
import '../widgets/quick_station_strip.dart';
import '../widgets/station_selector_card.dart';
import '../widgets/transit_mode_slider.dart';
import '../widgets/trip_card_widget.dart';
import '../widgets/trip_details_sheet.dart';
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
    // Rebuild only when something this screen actually renders changes. Lists
    // compare by identity (they are replaced, never mutated), favourites by
    // version, and stations by their key fields (Station == compares id only).
    // GPS fixes, connection polls and progress ticks are deliberately absent.
    context.select<TransitViewModel, Object>(
      (vm) => (
        vm.selectedNavIndex,
        vm.activeMode,
        vm.searchQuery,
        vm.displayedTrips,
        vm.alerts,
        vm.errorMessage,
        vm.isLoading,
        vm.favoriteStationsVersion,
        vm.favoriteTripsVersion,
        vm.recentStations,
        vm.stations,
        vm.selectedStation.id,
        vm.selectedStation.stopId,
        vm.selectedStation.name,
        vm.userPosition,
        vm.favoriteStationDisruptions,
      ),
    );
    final viewModel = context.read<TransitViewModel>();
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

    // Built once per HomeScreen build (not per LayoutBuilder pass) so keyboard
    // inset animations don't rebuild the whole sliver tree.
    final Widget content = RefreshIndicator(
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
                    const _HeaderSection(),
                    const SizedBox(height: 16),

                    // Mode Slider (Trains / Trams)
                    TransitModeSlider(
                      activeMode: viewModel.activeMode,
                      onModeChanged: viewModel.switchBaseMode,
                    ),
                    const SizedBox(height: 10),

                    // ── Quick Station Strip ─────────────────────
                    QuickStationStrip(viewModel: viewModel),
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
      );

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final sideMargin = constraints.maxWidth > 840
                ? (constraints.maxWidth - 840) / 2
                : 0.0;

            return Padding(
              padding: EdgeInsets.symmetric(horizontal: sideMargin),
              child: content,
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
        Padding(
          padding: EdgeInsets.symmetric(horizontal: sideMargin),
          child: const ActiveRideMiniPlayer(),
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

/// App header plus the loading progress bar. Selects only the loading fields so
/// progress ticks rebuild this small subtree instead of the whole screen.
class _HeaderSection extends StatelessWidget {
  const _HeaderSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (isLoading, progress, percentage, status, mode) =
        context.select<TransitViewModel, (bool, double, int, String, PtvMode)>(
      (vm) => (
        vm.isLoading,
        vm.loadingProgress,
        vm.loadingPercentage,
        vm.loadingStatus,
        vm.activeMode,
      ),
    );
    final viewModel = context.read<TransitViewModel>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppHeaderWidget(
          isLoading: isLoading,
          loadingProgress: progress,
          loadingPercentage: percentage,
          loadingStatus: status,
          activeMode: mode,
          onRefresh: viewModel.loadData,
          onToggleTheme: () {
            try {
              final themeVm = Provider.of<ThemeViewModel>(context, listen: false);
              final isDark = theme.brightness == Brightness.dark;
              themeVm.setThemeMode(isDark ? ThemeMode.light : ThemeMode.dark);
            } catch (_) {}
          },
        ),
        if (isLoading) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: RepaintBoundary(
              child: LinearProgressIndicator(
                value: progress > 0.0 ? progress : null,
                backgroundColor: theme.cardColor,
                color: AppColors.primaryCyan,
                minHeight: 6,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
