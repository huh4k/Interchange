import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/repositories/gtfs_repository.dart';
import '../../theme/app_theme.dart';
import '../state/transit_view_model.dart';
import '../widgets/active_ride_mini_player.dart';
import '../widgets/alert_banner_widget.dart';
import '../widgets/app_header_widget.dart';
import '../widgets/common/ui_kit.dart';
import '../widgets/empty_state_widget.dart';
import '../widgets/quick_station_strip.dart';
import '../widgets/walk_time_chip.dart';
import '../widgets/station_selector_card.dart';
import '../widgets/trip_card_skeleton.dart';
import '../widgets/transit_mode_slider.dart';
import '../widgets/trip_card_widget.dart';
import '../widgets/trip_details_sheet.dart';
import 'disruptions_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();

  /// Bus timetables are far bigger than the other modes, so ask before the
  /// first download. Declining keeps live departures only.
  Future<void> _askBusDataConsent(
    BuildContext context,
    TransitViewModel viewModel,
  ) async {
    final download = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.download_rounded, color: AppColors.melbourneBus),
        title: const Text('Download bus timetable?'),
        content: const Text(
          'The metro bus timetable is much larger than the other modes and '
          'may use a lot of mobile data. It gives scheduled times when live '
          'data is unavailable.\n\nWithout it, buses still show live '
          'departures.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Live only'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Download'),
          ),
        ],
      ),
    );
    if (download == true) await viewModel.allowBusDataDownload();
  }

  /// Hint for the filter box. The station name goes in it when there is room;
  /// otherwise the hint drops it rather than being cut off mid-word.
  String _filterHint(
    BuildContext context,
    TransitViewModel vm,
    bool isSavedView,
    double width,
  ) {
    if (isSavedView) return 'Filter saved departures...';
    final what = switch (vm.activeMode) {
      PtvMode.metroTram => 'tram routes',
      PtvMode.metroBus => 'bus routes',
      PtvMode.regionalTrain => 'V/Line services',
      _ => 'train lines',
    };
    final full = 'Filter $what at ${vm.selectedStation.name}...';
    final style =
        Theme.of(context).textTheme.bodyLarge ?? const TextStyle(fontSize: 16);
    // Room beside the leading icon, the padding and the clear button.
    final fits = measureTextWidth(context, full, style) < width - 100;
    return fits ? full : 'Filter $what...';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Trigger the first data load after the widget tree is built.
      context.read<TransitViewModel>().ensureInitialLoad();
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
        vm.enabledModes,
        vm.showAlertBanner,
        vm.showStaticWarning,
        vm.usingStaticFallback,
        vm.searchQuery,
        vm.displayedTrips,
        vm.alerts,
        vm.errorMessage,
        vm.isLoading,
        vm.isLoadingAlerts,
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
    if (_searchController.text != viewModel.searchQuery &&
        viewModel.searchQuery.isEmpty) {
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
            isLoading: viewModel.isLoading || viewModel.isLoadingAlerts,
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
      color: Theme.of(context).colorScheme.primary,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _HeaderSection(),
                  if (!isSavedView) ...[
                    const SizedBox(height: 12),

                    // Mode Slider (Trains / Trams)
                    if (viewModel.enabledModes.length > 1)
                      TransitModeSlider(
                        modes: viewModel.enabledModes,
                        activeMode: viewModel.activeMode,
                        onModeChanged: (mode) {
                          viewModel.switchBaseMode(mode);
                          if (viewModel.needsBusDataConsent) {
                            _askBusDataConsent(context, viewModel);
                          }
                        },
                      ),
                    const SizedBox(height: 8),

                    QuickStationStrip(viewModel: viewModel),
                    const SizedBox(height: 8),

                    // Station Selector Card with Instant Search & Favorite Action
                    StationSelectorCard(
                      selectedStation: viewModel.selectedStation,
                      stations: viewModel.stations,
                      favoriteStations: viewModel.favoriteStations,
                      recentStations: viewModel.recentStations,
                      userPosition: viewModel.userPosition,
                      activeMode: viewModel.activeMode,
                      onLocateNearest: viewModel.locateNearestStation,
                      onRemoteSearch: viewModel.activeMode.isLiveOnly
                          ? viewModel.searchLiveStops
                          : null,
                      onStationSelected: viewModel.selectStation,
                      onToggleFavorite: viewModel.toggleFavoriteStation,
                    ),
                    const SizedBox(height: 8),
                    WalkTimeChip(viewModel: viewModel),
                  ],
                  const SizedBox(height: 10),

                  // Search departures/routes for the selected station
                  LayoutBuilder(
                    builder: (context, box) => TextField(
                      controller: _searchController,
                      onChanged: viewModel.updateSearchQuery,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: _filterHint(
                          context,
                          viewModel,
                          isSavedView,
                          box.maxWidth,
                        ),
                        prefixIcon: Icon(
                          viewModel.activeMode == PtvMode.metroTram
                              ? Icons.tram_rounded
                              : viewModel.activeMode == PtvMode.metroBus
                              ? Icons.directions_bus_rounded
                              : Icons.search_rounded,
                          color: viewModel.activeMode == PtvMode.metroTram
                              ? AppColors.melbourneTram
                              : viewModel.activeMode == PtvMode.metroBus
                              ? AppColors.melbourneBus
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
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: viewModel.isLoading
                            ? null
                            : viewModel.loadData,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          if (viewModel.showAlertBanner && viewModel.alerts.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20.0,
                  vertical: 4.0,
                ),
                child: AlertBannerWidget(alert: viewModel.alerts.first),
              ),
            ),

          if (!isSavedView &&
              viewModel.showStaticWarning &&
              viewModel.usingStaticFallback)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 4.0),
                child: StaticFallbackBanner(),
              ),
            ),

          // Saved View: Favorite Stations Section
          if (isSavedView && viewModel.favoriteStations.isNotEmpty) ...[
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: 20.0,
                vertical: 8.0,
              ),
              sliver: const SliverToBoxAdapter(
                child: SectionLabel('FAVORITE STATIONS'),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final st = viewModel.favoriteStations[index];
                  return _SavedStationRow(
                    name: st.name,
                    zone: st.zone,
                    icon: Icons.star_rounded,
                    color: AppColors.statusAmber,
                    isSelected: st.name == viewModel.selectedStation.name,
                    trailing: IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () => viewModel.toggleFavoriteStation(st),
                      tooltip: 'Remove Favorite',
                    ),
                    onTap: () {
                      viewModel.selectStation(st);
                      viewModel.selectNavIndex(0);
                    },
                  );
                }, childCount: viewModel.favoriteStations.length),
              ),
            ),
          ],

          // Saved View: Recent Stations Section
          if (isSavedView && viewModel.recentStations.isNotEmpty) ...[
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: 20.0,
                vertical: 8.0,
              ),
              sliver: const SliverToBoxAdapter(
                child: SectionLabel('RECENT STATIONS'),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final st = viewModel.recentStations[index];
                  return _SavedStationRow(
                    name: st.name,
                    zone: st.zone,
                    icon: Icons.history_rounded,
                    color: Theme.of(context).colorScheme.primary,
                    isSelected: st.name == viewModel.selectedStation.name,
                    onTap: () {
                      viewModel.selectStation(st);
                      viewModel.selectNavIndex(0);
                    },
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
                      isSavedView ? 'Saved Departures' : 'Next departures',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!viewModel.isLoading)
                    Text(
                      '${displayedTrips.length} '
                      '${displayedTrips.length == 1 ? 'service' : 'services'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurfaceVariant,
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
                  (context, index) => const TripCardSkeleton(),
                  childCount: 3,
                ),
              ),
            )
          else if (displayedTrips.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyStateWidget(
                isSavedView: isSavedView,
                filterText: viewModel.searchQuery,
                hasError: viewModel.errorMessage != null,
                noStopSelected:
                    !isSavedView &&
                    viewModel.activeMode.isLiveOnly &&
                    viewModel.selectedStation.stopId.isEmpty,
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
                delegate: SliverChildBuilderDelegate((context, index) {
                  final trip = displayedTrips[index];
                  return TripCardWidget(
                    trip: trip,
                    isFavorite: viewModel.isFavoriteTrip(trip.tripId),
                    hasDisruption: viewModel.hasDisruptionForTrip(trip),
                    leaveBy: viewModel.leaveByFor(trip),
                    reachable: viewModel.canCatch(trip),
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

  Widget _buildNavigationBar(
    TransitViewModel viewModel, {
    double sideMargin = 0.0,
  }) {
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

/// A favourite or recent station on the Saved tab.
class _SavedStationRow extends StatelessWidget {
  final String name;
  final String zone;
  final IconData icon;
  final Color color;
  final bool isSelected;
  final Widget? trailing;
  final VoidCallback onTap;

  const _SavedStationRow({
    required this.name,
    required this.zone,
    required this.icon,
    required this.color,
    required this.isSelected,
    this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SurfacePanel(
      margin: const EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.fromLTRB(12, 10, trailing == null ? 14 : 4, 10),
      borderColor: isSelected
          ? Theme.of(context).colorScheme.primary.withAlpha(140)
          : null,
      onTap: onTap,
      child: Row(
        children: [
          IconTile(icon: icon, color: color, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                Text(
                  zone.isNotEmpty ? zone : 'Zone 1',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          trailing ??
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
        ],
      ),
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
    final (isLoading, progress, percentage, status, mode, isOffline) = context
        .select<TransitViewModel, (bool, double, int, String, PtvMode, bool)>(
          (vm) => (
            vm.isLoading,
            vm.loadingProgress,
            vm.loadingPercentage,
            vm.loadingStatus,
            vm.activeMode,
            vm.isOffline,
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
          isOffline: isOffline,
          onRefresh: viewModel.loadData,
          onOpenSettings: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
          ),
        ),
        if (isLoading) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: RepaintBoundary(
              child: LinearProgressIndicator(
                value: progress > 0.0 ? progress : null,
                backgroundColor: theme.cardColor,
                color: Theme.of(context).colorScheme.primary,
                minHeight: 6,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
