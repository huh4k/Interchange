import 'dart:async';
import 'package:flutter/material.dart';
import '../../domain/entities/station.dart';
import '../../domain/entities/transit_route.dart';
import '../../theme/app_theme.dart';
import '../widgets/common/ui_kit.dart';

class DisruptionsScreen extends StatefulWidget {
  final List<ServiceAlert> alerts;
  final List<ServiceAlert> allAlerts;
  final List<Station> favoriteStations;
  final Station selectedStation;
  final bool isLoading;
  final FutureOr<void> Function() onRefresh;
  final bool initialShowAllLines;

  const DisruptionsScreen({
    super.key,
    required this.alerts,
    this.allAlerts = const [],
    this.favoriteStations = const [],
    required this.selectedStation,
    required this.isLoading,
    required this.onRefresh,
    this.initialShowAllLines = false,
  });

  @override
  State<DisruptionsScreen> createState() => _DisruptionsScreenState();
}

class _DisruptionsScreenState extends State<DisruptionsScreen> {
  late bool _showAllLines;
  ServiceStatus? _selectedSeverity;

  @override
  void initState() {
    super.initState();
    _showAllLines = widget.initialShowAllLines;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasFavorites = widget.favoriteStations.isNotEmpty;
    final allList = widget.allAlerts.isNotEmpty ? widget.allAlerts : widget.alerts;
    final displayedAlerts = _showAllLines ? allList : widget.alerts;
    final filteredAlerts = _selectedSeverity == null
        ? displayedAlerts
        : displayedAlerts.where((a) {
            if (_selectedSeverity == ServiceStatus.disrupted) {
              return a.severity == ServiceStatus.disrupted ||
                  a.severity == ServiceStatus.cancelled;
            }
            if (_selectedSeverity == ServiceStatus.scheduled) {
              return a.severity == ServiceStatus.scheduled ||
                  a.severity == ServiceStatus.onTime;
            }
            return a.severity == _selectedSeverity;
          }).toList();
    final mutedBody = TextStyle(
      fontSize: 13,
      height: 1.4,
      color: scheme.onSurfaceVariant,
    );

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Text('Station Disruptions', style: theme.textTheme.titleLarge),
        actions: [
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primaryCyan,
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            icon: Icon(
              _showAllLines ? Icons.star_rounded : Icons.alt_route_rounded,
              size: 18,
            ),
            label: Text(
              _showAllLines ? 'My Stations' : 'All Lines',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            onPressed: () {
              setState(() {
                _showAllLines = !_showAllLines;
              });
            },
          ),
          IconButton(
            icon: widget.isLoading
                ? const RepaintBoundary(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : const Icon(Icons.refresh_rounded),
            onPressed: widget.isLoading ? null : widget.onRefresh,
            tooltip: 'Refresh Alerts',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => await widget.onRefresh(),
        color: AppColors.primaryCyan,
        child: CustomScrollView(
          slivers: [
            // My Stations / All Lines toggle, styled like the mode slider
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
                child: Container(
                  height: 46,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      _segment(
                        selected: !_showAllLines,
                        icon: Icons.star_rounded,
                        iconColor: AppColors.statusAmber,
                        label: 'My Stations (${widget.alerts.length})',
                        onTap: () => setState(() => _showAllLines = false),
                      ),
                      _segment(
                        selected: _showAllLines,
                        icon: Icons.alt_route_rounded,
                        iconColor: AppColors.primaryCyan,
                        label: 'All Lines (${allList.length})',
                        onTap: () => setState(() => _showAllLines = true),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Severity quick filters
            if (displayedAlerts.isNotEmpty)
              SliverToBoxAdapter(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      _buildSeverityChip(
                        label: 'All Alerts',
                        count: displayedAlerts.length,
                        isSelected: _selectedSeverity == null,
                        color: AppColors.primaryCyan,
                        onTap: () => setState(() => _selectedSeverity = null),
                      ),
                      const SizedBox(width: 6),
                      _buildSeverityChip(
                        label: 'Disrupted',
                        count: displayedAlerts
                            .where((a) =>
                                a.severity == ServiceStatus.disrupted ||
                                a.severity == ServiceStatus.cancelled)
                            .length,
                        isSelected: _selectedSeverity == ServiceStatus.disrupted,
                        color: AppColors.statusRose,
                        onTap: () => _toggleSeverity(ServiceStatus.disrupted),
                      ),
                      const SizedBox(width: 6),
                      _buildSeverityChip(
                        label: 'Delays',
                        count: displayedAlerts
                            .where((a) => a.severity == ServiceStatus.delayed)
                            .length,
                        isSelected: _selectedSeverity == ServiceStatus.delayed,
                        color: AppColors.statusAmber,
                        onTap: () => _toggleSeverity(ServiceStatus.delayed),
                      ),
                      const SizedBox(width: 6),
                      _buildSeverityChip(
                        label: 'Works / Info',
                        count: displayedAlerts
                            .where((a) =>
                                a.severity == ServiceStatus.scheduled ||
                                a.severity == ServiceStatus.onTime)
                            .length,
                        isSelected: _selectedSeverity == ServiceStatus.scheduled,
                        color: AppColors.secondaryIndigo,
                        onTap: () => _toggleSeverity(ServiceStatus.scheduled),
                      ),
                    ],
                  ),
                ),
              ),

            // What this view is monitoring
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                child: SurfacePanel(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _showAllLines
                                ? Icons.alt_route_rounded
                                : Icons.star_rounded,
                            size: 16,
                            color: _showAllLines
                                ? AppColors.primaryCyan
                                : AppColors.statusAmber,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SectionLabel(
                              _showAllLines
                                  ? 'SHOWING ALL NETWORK DISRUPTIONS'
                                  : (hasFavorites
                                      ? 'MONITORING FAVORITE STATIONS'
                                      : 'MONITORING CURRENT STATION'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_showAllLines)
                        Text(
                          'Showing live service alerts across every line on the Melbourne suburban network (${allList.length} active).',
                          style: mutedBody,
                        )
                      else if (hasFavorites)
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final st in widget.favoriteStations)
                              TintPill(
                                label: st.name,
                                color: AppColors.primaryCyan,
                                icon: Icons.train_rounded,
                              ),
                          ],
                        )
                      else
                        Text(
                          'Showing alerts for ${widget.selectedStation.name}. Star stations in search to monitor their disruptions here.',
                          style: mutedBody,
                        ),
                    ],
                  ),
                ),
              ),
            ),

            if (filteredAlerts.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: AppColors.statusGreen.withAlpha(25),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            size: 44,
                            color: AppColors.statusGreen,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          _selectedSeverity != null
                              ? 'No ${_selectedSeverity!.label} Alerts'
                              : (_showAllLines
                                  ? 'No Disruptions Across Network'
                                  : 'No Active Disruptions'),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _selectedSeverity != null
                              ? 'There are no active ${_selectedSeverity!.label.toLowerCase()} alerts in this view.'
                              : (_showAllLines
                                  ? 'All Melbourne train lines are running normally with no reported disruptions.'
                                  : (hasFavorites
                                      ? 'All lines serving your favorite stations are operating normally.'
                                      : 'No active disruptions reported for ${widget.selectedStation.name}.')),
                          textAlign: TextAlign.center,
                          style: mutedBody,
                        ),
                        if (_selectedSeverity != null) ...[
                          const SizedBox(height: 16),
                          OutlinedButton(
                            onPressed: () =>
                                setState(() => _selectedSeverity = null),
                            child: const Text('Reset Severity Filter'),
                          ),
                        ] else if (!_showAllLines && allList.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          FilledButton.tonalIcon(
                            style: FilledButton.styleFrom(
                              backgroundColor:
                                  AppColors.primaryCyan.withAlpha(30),
                              foregroundColor: AppColors.primaryCyan,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: const Icon(Icons.alt_route_rounded, size: 16),
                            label: Text(
                              'Show All Network Disruptions (${allList.length})',
                            ),
                            onPressed: () {
                              setState(() {
                                _showAllLines = true;
                              });
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final alert = filteredAlerts[index];
                      final status = alert.severity;

                      return SurfacePanel(
                        accent: status.color,
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                TintPill(
                                  label: status.label,
                                  color: status.color,
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    alert.lineCode,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              alert.title,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                height: 1.3,
                              ),
                            ),
                            if (alert.description.isNotEmpty &&
                                alert.description.trim() !=
                                    alert.title.trim()) ...[
                              const SizedBox(height: 6),
                              Text(alert.description, style: mutedBody),
                            ],
                          ],
                        ),
                      );
                    },
                    childCount: filteredAlerts.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _toggleSeverity(ServiceStatus severity) => setState(() {
        _selectedSeverity = _selectedSeverity == severity ? null : severity;
      });

  Widget _segment({
    required bool selected,
    required IconData icon,
    required Color iconColor,
    required String label,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: selected ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: selected ? AppColors.primaryCyan : Colors.transparent,
            borderRadius: BorderRadius.circular(100),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: selected ? Colors.white : iconColor),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    fontSize: 13,
                    color: selected ? Colors.white : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSeverityChip({
    required String label,
    required int count,
    required bool isSelected,
    required Color color,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? color.withAlpha(35) : scheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : scheme.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              '$label ($count)',
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                color: isSelected ? color : scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
