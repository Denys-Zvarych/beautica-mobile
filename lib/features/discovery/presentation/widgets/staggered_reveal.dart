// Phase 13.x (Variant A — «Рейка + послуги») — staggered fade-up load entrance.
//
// Transcribed verbatim from the approved preview
// `docs/signup-designs/SearchCategoryDisplay/lib/widgets/staggered_reveal.dart`
// (itself the `_reveal` pattern shared with the home hub). A single 1000 ms
// controller runs on mount; each child reveals on its own [Interval] slice —
// opacity 0→1 while sliding up 18 px — so the soft-UI search surface assembles
// itself rather than snapping in flat. This is the one high-impact motion
// moment of the screen; everything else stays calm and tactile.
//
// STRUCTURAL STABILITY (focus/keyboard bug, defect F):
//   `reveal(...)` MUST return the same widget SHAPE for the whole life of the
//   widget. An earlier version short-circuited to the bare `child` once the
//   controller completed (plus a `setState` from a status listener), which
//   changed the slot's widget runtimeType from `FadeTransition` to whatever the
//   child was. `Widget.canUpdate` compares runtimeType, so the element — and
//   every `State` beneath it, including the `EditableText` inside the search
//   field — was unmounted and re-inflated 1000 ms after mount. Anyone who
//   tapped the field and started typing within that first second lost focus and
//   had the keyboard dismissed. The wrappers are therefore UNCONDITIONAL: the
//   curves themselves short-circuit (a completed `CurvedAnimation` sits at 1.0,
//   the `Transform` offset collapses to zero, and the controller stops ticking),
//   so keeping them costs nothing at steady state. Never reintroduce a branch
//   here that returns a differently-shaped subtree.

import 'package:flutter/material.dart';

/// `reveal(start, end, child)` wraps a child in its delayed fade-up segment.
typedef SearchRevealFn =
    Widget Function({
      required double start,
      required double end,
      required Widget child,
    });

/// Drives one orchestrated staggered fade-up entrance for the search screen.
class SearchStaggeredReveal extends StatefulWidget {
  const SearchStaggeredReveal({super.key, required this.builder});

  /// Builds the body given a `reveal(start, end, child)` helper.
  final Widget Function(BuildContext context, SearchRevealFn reveal) builder;

  @override
  State<SearchStaggeredReveal> createState() => _SearchStaggeredRevealState();
}

class _SearchStaggeredRevealState extends State<SearchStaggeredReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// Per-interval curved animations, created once on first request and reused
  /// across rebuilds. Keyed by `(start, end)` so no `CurvedAnimation` is
  /// allocated (and no listener attached to `_controller`) on rebuild.
  final Map<(double, double), CurvedAnimation> _curves =
      <(double, double), CurvedAnimation>{};

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    // No completion status listener: nothing about this widget's OUTPUT changes
    // when the entrance finishes, so a `setState` there would only risk
    // re-inflating the revealed subtrees (see the file header).
    _controller.forward();
  }

  @override
  void dispose() {
    for (final CurvedAnimation curve in _curves.values) {
      curve.dispose();
    }
    _controller.dispose();
    super.dispose();
  }

  Widget _reveal({
    required double start,
    required double end,
    required Widget child,
  }) {
    // ALWAYS the same shape — FadeTransition > AnimatedBuilder — running or
    // completed, so the element (and any `State` inside `child`, e.g. an
    // `EditableText`) is never re-inflated mid-interaction.
    //
    // What is actually free at steady state (perf-VERIFIED, LOW-4):
    //   • the curve is cached per interval, so a rebuild allocates neither a
    //     `CurvedAnimation` nor a `_controller` listener;
    //   • the controller stops ticking once the entrance completes
    //     (`transientCallbacks` drops back to 0) and drives zero rebuilds;
    //   • a completed `FadeTransition` sits at opacity 1.0, where
    //     `RenderAnimatedOpacity.alwaysNeedsCompositing` is false — no save
    //     layer;
    //   • the `Transform` offset collapses to zero.
    //
    // NOT free, and therefore NOT here: a `RepaintBoundary`. Every call site
    // hands these slots to a `ListView`, which already sets
    // `addRepaintBoundaries: true` — wrapping again produced a second
    // `RenderRepaintBoundary` per slot, retained for the life of the (persistent
    // shell) Пошук branch, buying nothing.
    final CurvedAnimation curved = _curves.putIfAbsent(
      (start, end),
      () => CurvedAnimation(
        parent: _controller,
        curve: Interval(start, end, curve: Curves.easeOutCubic),
      ),
    );
    return FadeTransition(
      opacity: curved,
      child: AnimatedBuilder(
        animation: curved,
        builder: (BuildContext context, Widget? c) {
          return Transform.translate(
            offset: Offset(0, (1 - curved.value) * 18),
            child: c,
          );
        },
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _reveal);
}
