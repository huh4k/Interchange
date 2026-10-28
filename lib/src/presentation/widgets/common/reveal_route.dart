import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Full-screen route that grows out of [origin] as a circle and shrinks back
/// into it on the way out, with a soft accent ring riding the edge.
///
/// [origin] is in global coordinates, usually the centre of the button that
/// opened the route.
class RevealRoute<T> extends PageRouteBuilder<T> {
  RevealRoute({required WidgetBuilder builder, required Offset origin})
    : super(
        pageBuilder: (context, _, _) => builder(context),
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 230),
        transitionsBuilder: (context, animation, _, child) {
          final accent = Theme.of(context).colorScheme.primary;
          final reveal = CurvedAnimation(
            parent: animation,
            curve: Curves.easeInOutCubic,
            // Closing is a quick swoop back into the gear.
            reverseCurve: Curves.easeInCubic,
          );
          // Opening: the page starts a little oversized and settles as the
          // circle opens. It stays opaque (fading would let Home show
          // through) and holds still while closing.
          final settle = Tween<double>(begin: 1.05, end: 1).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          );

          return AnimatedBuilder(
            animation: animation,
            builder: (context, _) => Stack(
              fit: StackFit.expand,
              children: [
                ClipPath(
                  clipper: _CircleReveal(origin, reveal.value),
                  child: ScaleTransition(
                    scale: animation.status == AnimationStatus.reverse
                        ? const AlwaysStoppedAnimation(1.0)
                        : settle,
                    child: child,
                  ),
                ),
                IgnorePointer(
                  child: CustomPaint(
                    painter: _RingPainter(origin, reveal.value, accent),
                  ),
                ),
              ],
            ),
          );
        },
      );
}

/// Radius that covers the whole screen from [origin].
double _coverRadius(Offset origin, Size size) => [
  origin.distance,
  (origin - Offset(size.width, 0)).distance,
  (origin - Offset(0, size.height)).distance,
  (origin - Offset(size.width, size.height)).distance,
].reduce(math.max);

class _CircleReveal extends CustomClipper<Path> {
  final Offset origin;
  final double t;

  const _CircleReveal(this.origin, this.t);

  @override
  Path getClip(Size size) => Path()
    ..addOval(
      Rect.fromCircle(
        center: origin,
        radius: _coverRadius(origin, size) * t.clamp(0.0, 1.0),
      ),
    );

  @override
  bool shouldReclip(_CircleReveal old) => old.t != t || old.origin != origin;
}

class _RingPainter extends CustomPainter {
  final Offset origin;
  final double t;
  final Color color;

  const _RingPainter(this.origin, this.t, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    // Brightest while the circle is small, gone once it covers the screen.
    final fade = (1 - t).clamp(0.0, 1.0);
    canvas.drawCircle(
      origin,
      _coverRadius(origin, size) * t,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 + 3 * fade
        ..color = color.withAlpha((170 * fade).round()),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.t != t || old.origin != origin || old.color != color;
}
