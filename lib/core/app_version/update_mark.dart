import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/brand_colors.dart';
import '../theme/velvet_geometry.dart';
import '../widgets/neumorphic.dart';

/// The screen's one memorable element: the brand "B" pillow resting in a
/// recessed circular well, wrapped by a camel arc with an arrowhead — the logo
/// itself becomes the "update / refresh" glyph.
///
/// [progress] (0→1) drives the single load moment: the pillow lifts out of the
/// well (scale + fade), then the arc draws clockwise and its arrowhead lands.
/// Pass 1 for a static render (reduced motion).
///
/// Ported verbatim from `docs/signup-designs/UpdateRequired/` (phase 438).
/// `NeumorphicInset` + `VelvetLogo(showWordmark: false)` are the production
/// widgets used as-is; only [_UpdateRingPainter] is new. The preview's
/// `NeumorphicInset(circle: true)` is expressed as a radius of half the well
/// ([_wellRadius]) — an identical circle, with no new parameter on the shared
/// widget.
class UpdateMark extends StatelessWidget {
  const UpdateMark({super.key, required this.progress});

  final Animation<double> progress;

  static const double wellSize = 156;

  /// Half of [wellSize]: the rounded-rect well becomes a circle.
  static const double _wellRadius = wellSize / 2;

  /// The pillow's lift-out (scale + fade) slice of [progress].
  static const Curve _liftCurve = Interval(0, 0.45, curve: Curves.easeOutBack);

  /// The arc's draw slice of [progress].
  static const Curve _ringCurve = Interval(
    0.3,
    0.85,
    curve: Curves.easeInOutCubic,
  );

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: wellSize,
        child: NeumorphicInset(
          radius: _wellRadius,
          animatedRing: false,
          child: AnimatedBuilder(
            animation: progress,
            builder: (BuildContext context, Widget? child) {
              // Curves applied to the raw value: no per-build CurvedAnimation
              // (each one registers a listener on [progress] and is never
              // disposed). [progress] only runs forward, so this is identical.
              final double t = progress.value;
              final double lift = _liftCurve.transform(t);
              return CustomPaint(
                foregroundPainter: _UpdateRingPainter(
                  sweep: _ringCurve.transform(t),
                ),
                child: Center(
                  // dim-decorative: one-shot intro fade; rests at 1.
                  child: Opacity(
                    opacity: lift.clamp(0.0, 1.0),
                    child: Transform.scale(
                      scale: 0.86 + 0.14 * lift,
                      child: child,
                    ),
                  ),
                ),
              );
            },
            // The production VelvetLogo's Column is max-height (the preview's
            // copy was min), so pin it to the pillow's own square — otherwise
            // `Center` lets it fill the well and the pillow rides to the top.
            child: const SizedBox.square(
              dimension: VelvetSizes.logoTile,
              child: VelvetLogo(showWordmark: false),
            ),
          ),
        ),
      ),
    );
  }
}

/// A 300° camel arc starting at 12 o'clock, ending in a rounded arrowhead —
/// the familiar "update" glyph, drawn around the logo pillow.
class _UpdateRingPainter extends CustomPainter {
  const _UpdateRingPainter({required this.sweep});

  /// 0 = nothing drawn, 1 = full 300° arc with arrowhead.
  final double sweep;

  static const double _maxSweep = math.pi * 2 * (300 / 360);
  static const double _start = -math.pi / 2 + 0.35;
  static const double _stroke = 3.2;

  @override
  void paint(Canvas canvas, Size size) {
    if (sweep <= 0) return;
    final Offset c = size.center(Offset.zero);
    final double r = size.shortestSide / 2 - 17;
    final double angle = _maxSweep * sweep;

    final Paint arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round
      ..color = BrandColors.accent;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      _start,
      angle,
      false,
      arc,
    );

    // Arrowhead at the arc's leading end, pointing along the tangent; it
    // grows in over the last 20 % of the sweep.
    final double headT = ((sweep - 0.8) / 0.2).clamp(0.0, 1.0);
    if (headT == 0) return;
    final double a = _start + angle;
    final Offset tip = c + Offset(math.cos(a), math.sin(a)) * r;
    final Offset tangent = Offset(-math.sin(a), math.cos(a));
    final Offset normal = Offset(math.cos(a), math.sin(a));
    final double len = 8 * headT;
    final Path head = Path()
      ..moveTo(tip.dx + tangent.dx * len * 0.9, tip.dy + tangent.dy * len * 0.9)
      ..lineTo(
        tip.dx + normal.dx * len - tangent.dx * len * 0.2,
        tip.dy + normal.dy * len - tangent.dy * len * 0.2,
      )
      ..lineTo(
        tip.dx - normal.dx * len - tangent.dx * len * 0.2,
        tip.dy - normal.dy * len - tangent.dy * len * 0.2,
      )
      ..close();
    canvas.drawPath(
      head,
      Paint()
        ..color = BrandColors.accent
        ..style = PaintingStyle.fill
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      head,
      Paint()
        ..color = BrandColors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_UpdateRingPainter old) => old.sweep != sweep;
}
