import 'package:flutter/material.dart';
import '../../../domain/entities/station.dart';
import '../../../domain/entities/trips.dart';
import '../../../theme/app_theme.dart';
import '../../state/transit_view_model.dart';
import '../common/ui_kit.dart';
import '../trip_card_widget.dart';
import '../trip_details_sheet.dart';

// ---------------------------------------------------------------------------
// StationDeparturesSheet
// ---------------------------------------------------------------------------

/// A self-contained bottom sheet that shows live departures for a connecting
/// [station] while leaving the parent [LiveRideSheet] and its tracked ride
/// completely undisturbed.
class StationDeparturesSheet extends StatefulWidget {
  final Station station;
  final TransitViewModel viewModel;

  const StationDeparturesSheet({
    super.key,
    required this.station,
    required this.viewModel,
  });

  @override
  State<StationDeparturesSheet> createState() => StationDeparturesSheetState();
}

class StationDeparturesSheetState extends State<StationDeparturesSheet> {
  bool _isLoading = true;
  List<Trip> _trips = [];

  @override
  void initState() {
    super.initState();
    _fetchDepartures();
  }

  Future<void> _fetchDepartures() async {
    final trips = await widget.viewModel.fetchTripsForStation(widget.station);
    if (mounted) {
      setState(() {
        _trips = trips;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final station = widget.station;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.45,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Header
            const SizedBox(height: 12),
            const SheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
              child: Row(
                children: [
                  IconTile(
                    icon: Icons.alt_route_rounded,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          station.name,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontSize: 19,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            TintPill(
                              label: 'Connecting station',
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            TintPill(
                              label: 'Ride tracking on',
                              color: AppColors.statusGreen,
                              dot: true,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: 'Refresh departures',
                    onPressed: () {
                      setState(() => _isLoading = true);
                      _fetchDepartures();
                    },
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              color: theme.colorScheme.outlineVariant,
              indent: 20,
              endIndent: 20,
            ),
            const SizedBox(height: 8),

            // Departures list
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _trips.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.train_outlined,
                              size: 48,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No departures found',
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'No upcoming departures at ${station.name} in the next hour.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      itemCount: _trips.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 2),
                      itemBuilder: (context, index) {
                        final trip = _trips[index];
                        return TripCardWidget(
                          trip: trip,
                          isFavorite: widget.viewModel.isFavoriteTrip(
                            trip.tripId,
                          ),
                          hasDisruption: widget.viewModel.hasDisruptionForTrip(
                            trip,
                          ),
                          onToggleFavorite: () =>
                              widget.viewModel.toggleFavoriteTrip(trip.tripId),
                          onTap: () => TripDetailsSheet.show(
                            context,
                            trip: trip,
                            selectedStation: station,
                            viewModel: widget.viewModel,
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
