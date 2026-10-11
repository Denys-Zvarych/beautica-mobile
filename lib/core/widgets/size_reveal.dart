// Phase 076 — the per-item "grow in / shrink out" primitive for a LAZY list.
//
// A `ListView.builder` cannot wrap its items in one `AnimatedSize`, so when a
// section expands into N sibling items the old whole-body 220 ms reveal is
// gone. This is its per-item equivalent: every item built BECAUSE of the
// user's action grows from 0 to its natural height over the same 220 ms /
// `easeOutCubic` as that `AnimatedSize`. All N items grow in parallel, so the
// summed height tracks the old single animation; only the items the lazy list
// actually built animate, so the list stays lazy.
//
// ## Cost model
//
//  * Idle: the controller is stopped at 1.0 — no ticker is scheduled, no
//    per-frame work. The clip is `Clip.none` at rest, so neither a save layer
//    nor a clip is pushed and the item's own outer shadow is not cropped.
//  * Re-mount (a lazy list disposing and rebuilding the item on scroll-back):
//    the host passes [revealOnMount] `false`, so the item is born at 1.0 and
//    nothing plays.
//
// ## The shape is UNCONDITIONAL
//
// Same contract as `RevealTransition` / `StaggeredReveal`: the tree below is
// the same for the whole life of the host (never short-circuit to the bare
// `child` once settled) — `Widget.canUpdate` would otherwise unmount every
// `State` underneath.

import 'package:flutter/material.dart';

/// Animates its [child]'s height between 0 and natural size.
///
/// Both params default to `false`, so a bare `SizeReveal(child: x)` is
/// layout- and paint-transparent.
class SizeReveal extends StatefulWidget {
  const SizeReveal({
    super.key,
    required this.child,
    this.revealOnMount = false,
    this.collapsing = false,
  });

  final Widget child;

  /// `true` grows the child in from 0 on first mount. Read ONCE, in
  /// `initState` — later changes are ignored, so a rebuild mid-animation or
  /// after it can never restart it.
  final bool revealOnMount;

  /// `true` shrinks the child to 0; flipping back to `false` grows it again
  /// from wherever it is.
  final bool collapsing;

  /// Matches the `AnimatedSize` this replaces in `CategorySection`.
  static const Duration duration = Duration(milliseconds: 220);
  static const Curve curve = Curves.easeOutCubic;

  @override
  State<SizeReveal> createState() => _SizeRevealState();
}

class _SizeRevealState extends State<SizeReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _curved;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: SizeReveal.duration,
      value: (widget.revealOnMount || widget.collapsing) ? 0 : 1,
    );
    _curved = CurvedAnimation(parent: _controller, curve: SizeReveal.curve);
    if (widget.collapsing) {
      // Born already collapsing (a re-mount mid-collapse): start from full.
      _controller.value = 1;
      _controller.reverse();
    } else if (widget.revealOnMount) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(SizeReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.collapsing != oldWidget.collapsing) {
      if (widget.collapsing) {
        _controller.reverse();
      } else {
        _controller.forward();
      }
    }
  }

  @override
  void dispose() {
    _curved.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curved,
      child: widget.child,
      builder: (BuildContext context, Widget? child) {
        final double v = _curved.value;
        return ClipRect(
          // Clip only while animating: at rest (1.0) `Clip.none` keeps the
          // child's neumorphic shadow uncropped and pushes no clip layer.
          clipBehavior: v >= 1 ? Clip.none : Clip.hardEdge,
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: v,
            child: child,
          ),
        );
      },
    );
  }
}
