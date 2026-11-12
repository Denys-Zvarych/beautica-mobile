// Phase 482 — the «3 дні» week grid's horizontal physics. Transcribed from
// the MasterWeekBookings preview (`widgets/week_time_grid.dart:870+`).

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// Free-momentum horizontal scrolling that comes to rest on a day boundary.
///
/// Momentum comes from [parent] (`ClampingScrollPhysics` at the call site, so
/// a fling always has a natural landing point). Only FLINGS are snapped here;
/// zero-velocity ends (a slow drag released in place) are left to the grid's
/// 180 ms settle timer, so input is never yanked back mid-gesture.
///
/// The fling runs its natural (parent) ballistic distance — a fast fling
/// travels several days, up to the whole week — and the landing point is
/// rounded to the nearest whole column. Pattern from Flutter's
/// `FixedExtentScrollPhysics`: friction THROUGH the snapped target when the
/// fling is heading toward it, a spring when it is already close or the
/// rounding lands behind the finger. Bounds come from the pager: first page
/// = Monday at the left, last page = Sunday as the last visible column.
///
/// The hosting `PageView` MUST set `pageSnapping: false` — with
/// `pageSnapping: true` it wraps these physics in its own page physics and
/// they are silently replaced (one page per swipe).
class DaySnapScrollPhysics extends ScrollPhysics {
  const DaySnapScrollPhysics({required this.visibleColumns, super.parent})
    : assert(visibleColumns > 0, 'visibleColumns must be positive');

  /// Day columns on screen at once — one column = viewport / this.
  final int visibleColumns;

  @override
  DaySnapScrollPhysics applyTo(ScrollPhysics? ancestor) => DaySnapScrollPhysics(
    visibleColumns: visibleColumns,
    parent: buildParent(ancestor),
  );

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    // Out of range: let the parent clamp first.
    if (position.outOfRange) {
      return super.createBallisticSimulation(position, velocity);
    }
    final Tolerance tol = toleranceFor(position);
    // Zero-velocity end: stay put; the grid's settle timer snaps once input
    // has stopped.
    if (velocity.abs() < tol.velocity) return null;
    final double extent = position.viewportDimension / visibleColumns;
    final Simulation? natural = super.createBallisticSimulation(
      position,
      velocity,
    );
    final double landing = natural == null
        ? position.pixels
        : natural.x(double.infinity);
    final double target = ((landing / extent).round() * extent)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();

    final double delta = target - position.pixels;
    // FrictionSimulation.through needs the target strictly ahead of the
    // fling; anything else (already close, or rounding lands behind the
    // finger) springs onto the target instead.
    final bool headingToTarget =
        delta.sign == velocity.sign && delta.abs() > extent / 2;
    if (headingToTarget) {
      return FrictionSimulation.through(
        position.pixels,
        target,
        velocity,
        tol.velocity * velocity.sign,
      );
    }
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      target,
      velocity,
      tolerance: tol,
    );
  }
}
