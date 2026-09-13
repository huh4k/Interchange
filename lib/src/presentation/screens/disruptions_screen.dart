import 'package:flutter/material.dart';
import '../../domain/entities/station.dart';
import '../../domain/entities/transit_route.dart';
import '../../theme/app_theme.dart';

class DisruptionsScreen extends StatefulWidget {
  final List<ServiceAlert> alerts;
  final List<ServiceAlert> allAlerts;
  final List<Station> favoriteStations;
  final Station selectedStation;
  final bool isLoading;
  final VoidCallback onRefresh;
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

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Station Disruptions',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
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
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            onPressed: () {
              setState(() {
                _showAllLines = !_showAllLines;
              });
            },
          ),
          IconButton(
            icon: widget.isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            onPressed: widget.isLoading ? null : widget.onRefresh,
            tooltip: 'Refresh Alerts',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => widget.onRefresh(),
        color: AppColors.primaryCyan,
        child: CustomScrollView(
          slivers: [
            // Segmented Toggle Button Bar
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: theme.dividerColor.withAlpha(35),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () {
                            if (_showAllLines) {
                              setState(() => _showAllLines = false);
                            }
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            decoration: BoxDecoration(
                              color: !_showAllLines
                                  ? AppColors.primaryCyan
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.star_rounded,
                                  size: 16,
                                  color: !_showAllLines
                                      ? Colors.white
                                      : AppColors.statusAmber,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'My Stations (${widget.alerts.length})',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: !_showAllLines
                                        ? Colors.white
                                        : theme.textTheme.bodyMedium?.color,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () {
                            if (!_showAllLines) {
                              setState(() => _showAllLines = true);
                            }
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            decoration: BoxDecoration(
                              color: _showAllLines
                                  ? AppColors.primaryCyan
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.alt_route_rounded,
                                  size: 16,
                                  color: _showAllLines
                                      ? Colors.white
                                      : theme.textTheme.bodyMedium?.color
                                          ?.withAlpha(160),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'All Lines (${allList.length})',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: _showAllLines
                                        ? Colors.white
                                        : theme.textTheme.bodyMedium?.color,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Severity / Category Quick Filter Bar
            if (displayedAlerts.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildSeverityChip(
                          theme,
                          label: 'All Alerts',
                          count: displayedAlerts.length,
                          isSelected: _selectedSeverity == null,
                          color: AppColors.primaryCyan,
                          onTap: () => setState(() => _selectedSeverity = null),
                        ),
                        const SizedBox(width: 8),
                        _buildSeverityChip(
                          theme,
                          label: 'Disrupted',
                          count: displayedAlerts
                              .where((a) =>
                                  a.severity == ServiceStatus.disrupted ||
                                  a.severity == ServiceStatus.cancelled)
                              .length,
                          isSelected: _selectedSeverity == ServiceStatus.disrupted,
                          color: AppColors.statusRose,
                          onTap: () => setState(() => _selectedSeverity =
                              _selectedSeverity == ServiceStatus.disrupted
                                  ? null
                                  : ServiceStatus.disrupted),
                        ),
                        const SizedBox(width: 8),
                        _buildSeverityChip(
                          theme,
                          label: 'Delays',
                          count: displayedAlerts
                              .where((a) => a.severity == ServiceStatus.delayed)
                              .length,
                          isSelected: _selectedSeverity == ServiceStatus.delayed,
                          color: AppColors.statusAmber,
                          onTap: () => setState(() => _selectedSeverity =
                              _selectedSeverity == ServiceStatus.delayed
                                  ? null
                                  : ServiceStatus.delayed),
                        ),
                        const SizedBox(width: 8),
                        _buildSeverityChip(
                          theme,
                          label: 'Works / Info',
                          count: displayedAlerts
                              .where((a) =>
                                  a.severity == ServiceStatus.scheduled ||
                                  a.severity == ServiceStatus.onTime)
                              .length,
                          isSelected: _selectedSeverity == ServiceStatus.scheduled,
                          color: AppColors.secondaryIndigo,
                          onTap: () => setState(() => _selectedSeverity =
                              _selectedSeverity == ServiceStatus.scheduled
                                  ? null
                                  : ServiceStatus.scheduled),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Context Header Banner
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: theme.dividerColor.withAlpha(40),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _showAllLines
                                ? Icons.alt_route_rounded
                                : Icons.star_rounded,
                            size: 18,
                            color: _showAllLines
                                ? AppColors.primaryCyan
                                : AppColors.statusAmber,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _showAllLines
                                ? 'SHOWING ALL NETWORK DISRUPTIONS'
                                : (hasFavorites
                                    ? 'MONITORING FAVORITE STATIONS'
                                    : 'MONITORING CURRENT STATION'),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                              color: theme.textTheme.bodySmall?.color
                                  ?.withAlpha(160),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_showAllLines)
                        Text(
                          'Showing live service alerts across every line on the Melbourne suburban network (${allList.length} active).',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.textTheme.bodyMedium?.color
                                ?.withAlpha(180),
                          ),
                        )
                      else if (hasFavorites)
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: widget.favoriteStations.map((st) {
                            return Chip(
                              labelPadding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 0,
                              ),
                              avatar: const Icon(
                                Icons.train_rounded,
                                size: 14,
                                color: AppColors.primaryCyan,
                              ),
                              label: Text(
                                st.name,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              backgroundColor:
                                  AppColors.primaryCyan.withAlpha(20),
                              side: BorderSide(
                                color: AppColors.primaryCyan.withAlpha(50),
                              ),
                            );
                          }).toList(),
                        )
                      else
                        Text(
                          'Showing alerts for ${widget.selectedStation.name}. Star stations in search to monitor their disruptions here.',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.textTheme.bodyMedium?.color
                                ?.withAlpha(180),
                          ),
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
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: AppColors.statusGreen.withAlpha(25),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check_circle_rounded,
                            size: 56,
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
                            fontWeight: FontWeight.bold,
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
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.grey,
                          ),
                        ),
                        if (_selectedSeverity != null) ...[
                          const SizedBox(height: 16),
                          OutlinedButton(
                            onPressed: () => setState(() => _selectedSeverity = null),
                            child: const Text('Reset Severity Filter'),
                          ),
                        ] else if (!_showAllLines && allList.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primaryCyan,
                              side: const BorderSide(
                                color: AppColors.primaryCyan,
                              ),
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
                padding: const EdgeInsets.all(20),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final alert = filteredAlerts[index];
                      final status = alert.severity;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: theme.cardColor,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: status.color.withAlpha(28),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(18),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryCyan,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    alert.lineCode,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: status.color.withAlpha(28),
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  child: Text(
                                    status.label,
                                    style: TextStyle(
                                      color: status.color,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              alert.title,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            if (alert.description.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                alert.description,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.textTheme.bodyMedium?.color
                                      ?.withAlpha(200),
                                  fontSize: 13,
                                  height: 1.45,
                                ),
                              ),
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

  Widget _buildSeverityChip(
    ThemeData theme, {
    required String label,
    required int count,
    required bool isSelected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color.withAlpha(35) : theme.cardColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? color : theme.dividerColor.withAlpha(40),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$label ($count)',
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                color: isSelected ? color : theme.textTheme.bodyMedium?.color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
