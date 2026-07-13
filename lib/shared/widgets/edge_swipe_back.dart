import 'package:flutter/material.dart';

/// Left-edge swipe-back affordance.
///
/// Reuses — verbatim — the edge-strip + rightward-drag mechanics established in
/// `features/booking/presentation/widgets/master_schedule_page.dart` (the
/// `_onEdgeSwipe*` handlers there): a narrow LEFT-EDGE hit-strip whose width
/// matches Cupertino's own `_kBackGestureWidth` (20 logical px), a net-rightward
/// distance threshold, and a rightward fling-velocity escape hatch. The same
/// constants are kept here so the gesture feels identical everywhere it is used.
///
/// [child] is rendered full-size; the drag recognizer is confined to a
/// [Positioned] strip painted ON TOP of [child] at its true left edge. Because
/// the strip is `HitTestBehavior.translucent` and only 20px wide, it never
/// competes with horizontally-scrolling content further inside [child]
/// (filter rails, calendars, carousels) — those start well past the strip, so a
/// touch mid-content never even hit-tests the detector.
///
/// A committed rightward edge drag fires [onSwipeBack]. When [enabled] is false
/// the strip is simply omitted from the [Stack] and [child] renders alone (the
/// caller's default system behaviour is left intact — e.g. on a root tab).
/// [child] always occupies the stable `children[0]` slot regardless of
/// [enabled], so toggling the flag never reparents / re-inflates the subtree.
class EdgeSwipeBack extends StatefulWidget {
  const EdgeSwipeBack({
    super.key,
    required this.child,
    required this.onSwipeBack,
    this.enabled = true,
  });

  /// The content the edge-swipe strip overlays.
  final Widget child;

  /// Fired once a rightward edge drag commits (distance OR velocity threshold).
  final VoidCallback onSwipeBack;

  /// When false the detector is not mounted — [child] is returned as-is.
  final bool enabled;

  /// Left-edge hit-strip width — same order of magnitude as Cupertino's own
  /// `_kBackGestureWidth` (`cupertino/route.dart`, 20.0).
  static const double kEdgeSwipeWidth = 20;

  /// Net rightward travel (logical px) that alone commits the gesture, even at
  /// low velocity — roughly 2.4x the hit-strip width.
  static const double kEdgeSwipeDistanceThreshold = 48;

  /// Rightward fling velocity (logical px/s) that alone commits the gesture even
  /// if [kEdgeSwipeDistanceThreshold] was not reached — mirrors Cupertino's
  /// `_kMinFlingVelocity`.
  static const double kEdgeSwipeVelocityThreshold = 400;

  @override
  State<EdgeSwipeBack> createState() => _EdgeSwipeBackState();
}

class _EdgeSwipeBackState extends State<EdgeSwipeBack> {
  /// Net signed horizontal travel accumulated since `onHorizontalDragStart` —
  /// reset at both the start and end of every gesture.
  double _edgeSwipeDx = 0;

  void _onEdgeSwipeStart(DragStartDetails details) {
    _edgeSwipeDx = 0;
  }

  void _onEdgeSwipeUpdate(DragUpdateDetails details) {
    _edgeSwipeDx += details.delta.dx;
  }

  void _onEdgeSwipeEnd(DragEndDetails details) {
    final double dx = _edgeSwipeDx;
    final double velocity = details.primaryVelocity ?? 0;
    _edgeSwipeDx = 0;
    // Rightward only (the standard "back" direction) — a leftward or negligible
    // drag never fires.
    if (dx >= EdgeSwipeBack.kEdgeSwipeDistanceThreshold ||
        velocity >= EdgeSwipeBack.kEdgeSwipeVelocityThreshold) {
      widget.onSwipeBack();
    }
  }

  @override
  Widget build(BuildContext context) {
    // ALWAYS return a Stack with [child] pinned at the stable children[0] slot so
    // the subtree (a StatefulNavigationShell + its IndexedStack branches) keeps
    // reconciling in place across enable/disable toggles instead of being
    // unmounted and re-inflated. Only the edge strip is gated on [enabled].
    return Stack(
      children: <Widget>[
        widget.child,
        if (widget.enabled)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: EdgeSwipeBack.kEdgeSwipeWidth,
            child: GestureDetector(
              key: const Key('edge-swipe-back'),
              behavior: HitTestBehavior.translucent,
              onHorizontalDragStart: _onEdgeSwipeStart,
              onHorizontalDragUpdate: _onEdgeSwipeUpdate,
              onHorizontalDragEnd: _onEdgeSwipeEnd,
            ),
          ),
      ],
    );
  }
}
