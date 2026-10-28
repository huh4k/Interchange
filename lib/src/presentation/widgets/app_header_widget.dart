import 'package:flutter/material.dart';
import '../../core/app_info.dart';
import '../../domain/value_objects/ptv_mode.dart';
import '../../theme/app_theme.dart';
import 'common/ui_kit.dart';

class AppHeaderWidget extends StatelessWidget {
  final bool isLoading;
  final double loadingProgress;
  final int loadingPercentage;
  final String loadingStatus;
  final PtvMode activeMode;
  final bool isOffline;
  final VoidCallback onRefresh;

  /// Called with the centre of the Settings button, in global coordinates,
  /// so the page can open out of it.
  final ValueChanged<Offset>? onOpenSettings;

  const AppHeaderWidget({
    super.key,
    required this.isLoading,
    this.loadingProgress = 0.0,
    this.loadingPercentage = 0,
    this.loadingStatus = '',
    this.activeMode = PtvMode.metroTrain,
    this.isOffline = false,
    required this.onRefresh,
    this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brand = activeMode.transitType.ptvBrandColor;
    final hsl = HSLColor.fromColor(brand);
    final brandLight = hsl
        .withLightness((hsl.lightness + 0.08).clamp(0.0, 1.0))
        .toColor();
    final brandDark = hsl
        .withLightness((hsl.lightness - 0.10).clamp(0.0, 1.0))
        .toColor();
    final statusColor = isLoading
        ? AppColors.statusAmber
        : isOffline
        ? scheme.error
        : AppColors.statusGreen;
    final statusLabel = isLoading
        ? 'Syncing… $loadingPercentage%'
        : isOffline
        ? 'Offline'
        : 'Live';

    final buttons = 1 + (onOpenSettings != null ? 1 : 0);
    final titleStyle = theme.textTheme.titleLarge?.copyWith(fontSize: 21);
    const versionStyle = TextStyle(fontSize: 11, fontWeight: FontWeight.w600);
    final titleWidth =
        measureTextWidth(
          context,
          'Interchange',
          titleStyle ?? const TextStyle(),
        ) +
        6 +
        measureTextWidth(context, 'v$appVersion', versionStyle);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Logo, gaps and the round buttons take their share first; if the name
        // doesn't fit in what is left, only the logo is shown.
        final room = constraints.maxWidth - 44 - 12 - buttons * (44 + 8);
        final compact = room < titleWidth;
        return Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [brandLight, brandDark],
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Icon(
                    activeMode.transitType.icon,
                    color: Colors.white,
                    size: 24,
                  ),
                  // Without the status line, a dot on the logo still shows it.
                  if (compact)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Tooltip(
                        message: statusLabel,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: scheme.surface, width: 2),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (compact)
              const Spacer()
            else
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Flexible(
                          child: Text(
                            'Interchange',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontSize: 21,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'v$appVersion',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            statusLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isLoading || isOffline
                                  ? statusColor
                                  : scheme.onSurfaceVariant,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            const SizedBox(width: 8),
            if (onOpenSettings != null) ...[
              Builder(
                builder: (buttonContext) => _HeaderButton(
                  onPressed: () {
                    final box = buttonContext.findRenderObject() as RenderBox;
                    onOpenSettings!(
                      box.localToGlobal(box.size.center(Offset.zero)),
                    );
                  },
                  tooltip: 'Settings',
                  child: const Icon(Icons.settings_rounded, size: 20),
                ),
              ),
              const SizedBox(width: 8),
            ],
            _HeaderButton(
              onPressed: isLoading ? null : onRefresh,
              tooltip: 'Refresh Feed',
              child: isLoading
                  ? RepaintBoundary(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    )
                  : const Icon(Icons.refresh_rounded, size: 21),
            ),
          ],
        );
      },
    );
  }
}

/// Round tonal button used for the header actions.
class _HeaderButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String tooltip;
  final Widget child;

  const _HeaderButton({
    required this.onPressed,
    required this.tooltip,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: child,
      style: IconButton.styleFrom(
        backgroundColor: scheme.surfaceContainerHigh,
        disabledBackgroundColor: scheme.surfaceContainerHigh,
        foregroundColor: scheme.onSurface,
        fixedSize: const Size(42, 42),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    );
  }
}
