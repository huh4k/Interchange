import 'package:flutter/material.dart';

/// Placeholder shaped like a [TripCardWidget] with a gentle pulse, shown while
/// departures load.
class TripCardSkeleton extends StatefulWidget {
  const TripCardSkeleton({super.key});

  @override
  State<TripCardSkeleton> createState() => _TripCardSkeletonState();
}

class _TripCardSkeletonState extends State<TripCardSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.onSurface;
    Widget bar(double? width, double height, {double radius = 6}) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: base.withAlpha(28),
        borderRadius: BorderRadius.circular(radius),
      ),
    );

    return ExcludeSemantics(
      child: FadeTransition(
        opacity: Tween<double>(begin: 0.45, end: 1).animate(_controller),
        child: Card(
          margin: const EdgeInsets.only(bottom: 12.0),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                bar(48, 36, radius: 12),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      bar(160, 14),
                      const SizedBox(height: 8),
                      bar(100, 11),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                bar(40, 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
