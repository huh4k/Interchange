import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/value_objects/ptv_mode.dart';
import '../../theme/app_theme.dart';
import '../state/theme_view_model.dart';
import '../state/transit_view_model.dart';
import '../widgets/common/ui_kit.dart';

/// Switches for what the app shows, so it only has what you want.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static String _modeLabel(PtvMode mode) => switch (mode) {
    PtvMode.metroTrain => 'Metro trains',
    PtvMode.metroTram => 'Yarra trams',
    PtvMode.regionalTrain => 'V/Line',
    _ => 'Metro buses',
  };

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TransitViewModel>();
    final themeVm = context.watch<ThemeViewModel>();
    final enabled = vm.enabledModes;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          const SectionLabel('APPEARANCE'),
          const SizedBox(height: 8),
          SegmentedButton<ThemeMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('System')),
              ButtonSegment(value: ThemeMode.light, label: Text('Light')),
              ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
            ],
            selected: {themeVm.themeMode},
            onSelectionChanged: (s) => themeVm.setThemeMode(s.first),
          ),
          const SizedBox(height: 24),
          const SectionLabel('TRANSPORT MODES'),
          const SizedBox(height: 4),
          for (final mode in TransitViewModel.selectableModes)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: Icon(
                mode.transitType.icon,
                color: mode.transitType.ptvBrandColor,
              ),
              title: Text(_modeLabel(mode)),
              // The last mode left on can't be switched off.
              value: enabled.contains(mode),
              onChanged: enabled.contains(mode) && enabled.length == 1
                  ? null
                  : (v) => vm.setModeEnabled(mode, v),
            ),
          const SizedBox(height: 16),
          const SectionLabel('DEPARTURES'),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.directions_walk_rounded),
            title: const Text('Walking time and "Leave by"'),
            subtitle: const Text('Uses your location'),
            value: vm.walkTimeEnabled,
            onChanged: (_) => vm.toggleWalkTime(),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(
              Icons.warning_amber_rounded,
              color: AppColors.statusAmber,
            ),
            title: const Text('Service alert banner'),
            subtitle: const Text('Shown on the home screen'),
            value: vm.showAlertBanner,
            onChanged: vm.setShowAlertBanner,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(
              Icons.schedule_rounded,
              color: AppColors.statusAmber,
            ),
            title: const Text('Timetable accuracy warning'),
            subtitle: const Text(
              'When scheduled times are shown instead of live ones',
            ),
            value: vm.showStaticWarning,
            onChanged: vm.setShowStaticWarning,
          ),
        ],
      ),
    );
  }
}
