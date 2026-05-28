// Phase 4.2 — Skeleton shimmer widgets for the loading state.
//
// Ported verbatim from the approved preview app at
// `docs/signup-designs/MasterProfileScreen/lib/widgets/profile_widgets.dart`
// (lines 231–381). Only the color references were changed from
// `VelvetColors.*` to `BrandColors.*` for production source compatibility.
//
// Two exported widgets:
//   • [SkeletonShimmerScope] — wraps the skeleton tree; owns the single
//     [AnimationController] shared by all [SkeletonBlock] descendants.
//   • [SkeletonBlock] — a recessed neumorphic well with a camel shimmer
//     sweep. Must be a descendant of [SkeletonShimmerScope].

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';

// ---------------------------------------------------------------------------
// SkeletonShimmerScope
// ---------------------------------------------------------------------------

/// Provides a single [AnimationController] to all [SkeletonBlock] descendants.
///
/// Wrap the root of the loading skeleton tree with this widget so that every
/// block shares one ticker instead of creating its own — many blocks → 1
/// ticker, 1 [AnimatedBuilder] rebuild per frame (via [RepaintBoundary]).
class SkeletonShimmerScope extends StatefulWidget {
  const SkeletonShimmerScope({super.key, required this.child});

  final Widget child;

  /// Reads the shared [Animation<double>] from the nearest [SkeletonShimmerScope].
  ///
  /// Throws if called outside a [SkeletonShimmerScope] subtree.
  static Animation<double> of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_SkeletonShimmerInherited>()!
        .animation;
  }

  @override
  State<SkeletonShimmerScope> createState() => _SkeletonShimmerScopeState();
}

class _SkeletonShimmerScopeState extends State<SkeletonShimmerScope>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SkeletonShimmerInherited(
      animation: _controller,
      child: widget.child,
    );
  }
}

class _SkeletonShimmerInherited extends InheritedWidget {
  const _SkeletonShimmerInherited({
    required this.animation,
    required super.child,
  });

  final Animation<double> animation;

  @override
  bool updateShouldNotify(_SkeletonShimmerInherited oldWidget) =>
      animation != oldWidget.animation;
}

// ---------------------------------------------------------------------------
// SkeletonBlock
// ---------------------------------------------------------------------------

/// A neumorphic shimmer block used to build the loading skeleton.
///
/// Renders as an inset well with a soft camel highlight sweeping across it —
/// the recessed look keeps the skeleton in the same depth language as the
/// resting screen.
///
/// Must be a descendant of [SkeletonShimmerScope], which owns the single
/// shared [AnimationController]. Each [SkeletonBlock] drives one
/// [AnimatedBuilder] rebuild per frame via the inherited animation — the
/// [RepaintBoundary] inside each block confines those repaints to the block
/// itself.
class SkeletonBlock extends StatelessWidget {
  const SkeletonBlock({
    super.key,
    required this.width,
    required this.height,
    this.radius = 10,
    this.circle = false,
  });

  final double width;
  final double height;
  final double radius;
  final bool circle;

  // Stops are constant — extracted to avoid List allocation inside builder.
  static const List<double> _shimmerStops = <double>[0.35, 0.5, 0.65];

  // Fix 4 (PERF MEDIUM-2): Pre-computed Color instances so _ShimmerFill.build()
  // never calls withValues() on every animation frame. withValues() is a
  // runtime allocation; computing once here reduces per-frame overhead to zero.
  static final Color _shimmerBase = BrandColors.base.withValues(alpha: 0);
  static final Color _shimmerHighlight = BrandColors.accent.withValues(
    alpha: 0.22,
  );

  @override
  Widget build(BuildContext context) {
    final Animation<double> animation = SkeletonShimmerScope.of(context);
    return ExcludeSemantics(
      child: SizedBox(
        height: height,
        width: width,
        child: circle
            // Circular skeleton block: paint the inset effect directly on the
            // circle shape (production NeumorphicInset doesn't support circle).
            ? CustomPaint(
                painter: const _CircleInsetPainter(),
                child: ClipOval(
                  child: RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: animation,
                      builder: (BuildContext ctx, _) => _ShimmerFill(
                        value: animation.value,
                        stops: _shimmerStops,
                        shimmerBase: _shimmerBase,
                        shimmerHighlight: _shimmerHighlight,
                      ),
                    ),
                  ),
                ),
              )
            : NeumorphicInset(
                radius: radius,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(radius),
                  child: RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: animation,
                      builder: (BuildContext ctx, _) => _ShimmerFill(
                        value: animation.value,
                        stops: _shimmerStops,
                        shimmerBase: _shimmerBase,
                        shimmerHighlight: _shimmerHighlight,
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _CircleInsetPainter (internal, shared with profile_avatar.dart)
// ---------------------------------------------------------------------------

/// Paints the neumorphic inset inner-shadow effect on a circular shape.
///
/// Used by [SkeletonBlock] with `circle: true` and [ProfileAvatar] since the
/// production [NeumorphicInset] widget does not support a `circle` parameter.
class _CircleInsetPainter extends CustomPainter {
  const _CircleInsetPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final double r = size.width / 2;
    final Offset center = Offset(r, r);

    final Paint dark = Paint()
      ..color = BrandColors.shadowDarkButton
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    final Paint light = Paint()
      ..color = BrandColors.shadowLightStrong
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    final Paint fill = Paint()..color = BrandColors.base;

    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: center, radius: r)),
    );

    canvas.drawCircle(center.translate(-5, -5), r, dark);
    canvas.drawCircle(center.translate(5, 5), r, light);
    canvas.drawCircle(center, r - 4, fill);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_CircleInsetPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// _ShimmerFill (internal)
// ---------------------------------------------------------------------------

/// Internal stateless leaf that paints the gradient — extracted so the
/// [AnimatedBuilder] builder closure allocates nothing beyond the widget itself.
///
/// Fix 4 (PERF MEDIUM-2): [shimmerBase] and [shimmerHighlight] are pre-built
/// [Color] instances passed from [SkeletonBlock]'s static fields — no
/// [withValues()] call occurs inside [build()].
class _ShimmerFill extends StatelessWidget {
  const _ShimmerFill({
    required this.value,
    required this.stops,
    required this.shimmerBase,
    required this.shimmerHighlight,
  });

  final double value;
  final List<double> stops;
  final Color shimmerBase;
  final Color shimmerHighlight;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment(-1 - 2 * value, -0.3),
          end: Alignment(1 - 2 * value, 0.3),
          colors: <Color>[shimmerBase, shimmerHighlight, shimmerBase],
          stops: stops,
        ),
      ),
    );
  }
}
