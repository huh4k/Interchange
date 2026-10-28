import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_info.dart';
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

  static String _modeHint(PtvMode mode) => switch (mode) {
    PtvMode.metroTrain => 'Suburban train network',
    PtvMode.metroTram => 'Melbourne tram network',
    PtvMode.regionalTrain => 'Regional trains',
    _ => 'Live departures and bays',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final vm = context.watch<TransitViewModel>();
    final themeVm = context.watch<ThemeViewModel>();
    final enabled = vm.enabledModes;
    final total = TransitViewModel.selectableModes.length;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                const _Header(),
                const SizedBox(height: 24),

                const _Section('Appearance'),
                SurfacePanel(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      for (final option in const [
                        (ThemeMode.system, 'System', Icons.brightness_auto_rounded),
                        (ThemeMode.light, 'Light', Icons.light_mode_rounded),
                        (ThemeMode.dark, 'Dark', Icons.dark_mode_rounded),
                      ]) ...[
                        Expanded(
                          child: _ThemeOption(
                            label: option.$2,
                            icon: option.$3,
                            selected: themeVm.themeMode == option.$1,
                            onTap: () => themeVm.setThemeMode(option.$1),
                          ),
                        ),
                        if (option.$1 != ThemeMode.dark) const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                _Section(
                  'Transport modes',
                  trailing: TintPill(
                    label: '${enabled.length} of $total on',
                    color: scheme.primary,
                  ),
                ),
                SurfacePanel(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (final mode in TransitViewModel.selectableModes) ...[
                        _SettingRow(
                          icon: mode.transitType.icon,
                          color: mode.transitType.ptvBrandColor,
                          title: _modeLabel(mode),
                          subtitle: _modeHint(mode),
                          value: enabled.contains(mode),
                          // The last mode left on can't be switched off.
                          onChanged: enabled.contains(mode) && enabled.length == 1
                              ? null
                              : (v) => vm.setModeEnabled(mode, v),
                        ),
                        if (mode != TransitViewModel.selectableModes.last)
                          const _RowDivider(),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'At least one mode stays on. Hidden modes disappear from the mode switcher.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                const _Section('Departures'),
                SurfacePanel(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _SettingRow(
                        icon: Icons.directions_walk_rounded,
                        color: scheme.primary,
                        title: 'Walking time',
                        subtitle: 'Adds "Leave by" times. Uses your location',
                        value: vm.walkTimeEnabled,
                        onChanged: (_) => vm.toggleWalkTime(),
                      ),
                      const _RowDivider(),
                      _SettingRow(
                        icon: Icons.warning_amber_rounded,
                        color: AppColors.statusAmber,
                        title: 'Service alert banner',
                        subtitle: 'Shown at the top of the home screen',
                        value: vm.showAlertBanner,
                        onChanged: vm.setShowAlertBanner,
                      ),
                      const _RowDivider(),
                      _SettingRow(
                        icon: Icons.schedule_rounded,
                        color: AppColors.statusAmber,
                        title: 'Timetable accuracy warning',
                        subtitle: 'When scheduled times replace live ones',
                        value: vm.showStaticWarning,
                        onChanged: vm.setShowStaticWarning,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                Center(
                  child: Text(
                    'Interchange  ·  v$appVersion',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hsl = HSLColor.fromColor(scheme.primary);
    final light = hsl
        .withLightness((hsl.lightness + 0.08).clamp(0.0, 1.0))
        .toColor();
    final dark = hsl
        .withLightness((hsl.lightness - 0.10).clamp(0.0, 1.0))
        .toColor();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _BackPill(onTap: () => Navigator.of(context).maybePop()),
            const Spacer(),
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [light, dark],
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.tune_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          'Settings',
          style: theme.textTheme.titleLarge?.copyWith(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Only show what you use',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// "‹ Home" pill in the accent colour. A label says where it goes, which a
/// bare arrow doesn't, and the tint ties it to the rest of the screen.
class _BackPill extends StatelessWidget {
  final VoidCallback onTap;

  const _BackPill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return Semantics(
      button: true,
      label: 'Back to home',
      child: ExcludeSemantics(
        child: Material(
          color: accent.withAlpha(28),
          shape: StadiumBorder(side: BorderSide(color: accent.withAlpha(80))),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 16, 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chevron_left_rounded, size: 22, color: accent),
                  const SizedBox(width: 2),
                  Text(
                    'Home',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const _Section(this.title, {this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Row(
        children: [
          Expanded(child: SectionLabel(title.toUpperCase())),
          ?trailing,
        ],
      ),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) => Divider(
    height: 1,
    thickness: 1,
    indent: 70,
    endIndent: 16,
    color: Theme.of(context).colorScheme.outlineVariant,
  );
}

/// One switch: coloured icon tile, title, hint and the switch itself. The
/// whole row toggles, so the tap target is large.
class _SettingRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _SettingRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locked = onChanged == null;

    return Semantics(
      container: true,
      toggled: value,
      label: title,
      hint: locked ? 'At least one mode must stay on' : subtitle,
      child: InkWell(
        onTap: locked ? null : () => onChanged!(!value),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            children: [
              ExcludeSemantics(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: value ? 1 : 0.5,
                  child: IconTile(icon: icon, color: color, size: 42),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: ExcludeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.3,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              ExcludeSemantics(
                child: Switch.adaptive(
                  value: value,
                  onChanged: onChanged,
                  activeThumbColor: Colors.white,
                  activeTrackColor: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.primary;

    return Semantics(
      button: true,
      selected: selected,
      label: '$label theme',
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: selected ? accent.withAlpha(28) : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? accent : scheme.outlineVariant,
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  icon,
                  size: 24,
                  color: selected ? accent : scheme.onSurfaceVariant,
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: selected ? accent : scheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
