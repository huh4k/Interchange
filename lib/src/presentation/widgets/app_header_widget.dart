import 'package:flutter/material.dart';
import '../../core/app_info.dart';
import '../../domain/value_objects/ptv_mode.dart';
import '../../theme/app_theme.dart';

class AppHeaderWidget extends StatelessWidget {
  final bool isLoading;
  final double loadingProgress;
  final int loadingPercentage;
  final String loadingStatus;
  final PtvMode activeMode;
  final bool isOffline;
  final VoidCallback onRefresh;
  final VoidCallback? onToggleTheme;

  const AppHeaderWidget({
    super.key,
    required this.isLoading,
    this.loadingProgress = 0.0,
    this.loadingPercentage = 0,
    this.loadingStatus = '',
    this.activeMode = PtvMode.metroTrain,
    this.isOffline = false,
    required this.onRefresh,
    this.onToggleTheme,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final brand = activeMode.transitType.ptvBrandColor;
    final hsl = HSLColor.fromColor(brand);
    final brandDark = hsl
        .withLightness((hsl.lightness - 0.15).clamp(0.0, 1.0))
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

    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [brand, brandDark],
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            activeMode.transitType.icon,
            color: Colors.white,
            size: 24,
          ),
        ),
        const SizedBox(width: 12),
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
                      style: theme.textTheme.titleLarge?.copyWith(fontSize: 21),
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
        if (onToggleTheme != null) ...[
          _HeaderButton(
            onPressed: onToggleTheme,
            tooltip: isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode',
            child: Icon(
              isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              size: 20,
            ),
          ),
          const SizedBox(width: 8),
        ],
        _HeaderButton(
          onPressed: isLoading ? null : onRefresh,
          tooltip: 'Refresh Feed',
          child: isLoading
              ? const RepaintBoundary(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.primaryCyan,
                      ),
                    ),
                  ),
                )
              : const Icon(Icons.refresh_rounded, size: 21),
        ),
      ],
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
