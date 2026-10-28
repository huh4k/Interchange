import 'package:flutter/material.dart';

/// Small shared building blocks so screens and sheets look like one app.
/// Colours come from the theme's colour scheme (see `AppTheme`).

/// Rendered width of single-line [text], for deciding whether it fits before
/// falling back to something shorter (an icon, say).
double measureTextWidth(BuildContext context, String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    maxLines: 1,
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

/// Drag handle shown at the top of bottom sheets.
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onSurfaceVariant.withAlpha(90),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// Small upper-case label that introduces a section.
class SectionLabel extends StatelessWidget {
  final String text;
  final Color? color;

  const SectionLabel(this.text, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.9,
        color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// Tinted pill for statuses and tags ("On Time", "Next", "Live").
class TintPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  /// Shows a small solid dot before the label, e.g. for live states.
  final bool dot;

  const TintPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.dot = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(90)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
          ] else if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Solid line badge in a network's brand colour ("FKN", "86").
class LineBadge extends StatelessWidget {
  final String code;
  final Color color;
  final bool large;

  const LineBadge({
    super.key,
    required this.code,
    required this.color,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minWidth: large ? 48 : 34),
      padding: EdgeInsets.symmetric(
        horizontal: large ? 10 : 7,
        vertical: large ? 8 : 3,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(large ? 12 : 7),
      ),
      child: Text(
        code,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: large ? 15 : 11,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// Bordered surface used for cards and grouped content. An [accent] adds a
/// coloured strip down the left edge, matching the departure cards.
class SurfacePanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? accent;
  final Color? borderColor;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;

  const SurfacePanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.accent,
    this.borderColor,
    this.margin = EdgeInsets.zero,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget content = Padding(padding: padding, child: child);
    if (accent != null) {
      content = DecoratedBox(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: accent!, width: 4)),
        ),
        child: content,
      );
    }
    return Padding(
      padding: margin,
      child: Material(
        color: scheme.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: borderColor ?? scheme.outlineVariant),
        ),
        child: onTap == null ? content : InkWell(onTap: onTap, child: content),
      ),
    );
  }
}

/// Rounded square holding an icon, as used by the station card.
class IconTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;

  const IconTile({
    super.key,
    required this.icon,
    required this.color,
    this.size = 42,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(icon, color: color, size: size * 0.52),
    );
  }
}

/// Selectable pill matching the quick station strip on the home screen.
class SelectPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final Color? color;

  const SelectPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = color ?? scheme.primary;
    final foreground = selected ? Colors.white : scheme.onSurface;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? active : scheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? active : scheme.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: selected ? Colors.white : active),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
