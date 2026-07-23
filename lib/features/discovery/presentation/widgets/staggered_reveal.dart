// Phase 13.x (Variant A — «Рейка + послуги») — staggered fade-up load entrance.
//
// Transcribed verbatim from the approved preview
// `docs/signup-designs/SearchCategoryDisplay/lib/widgets/staggered_reveal.dart`
// (itself the `_reveal` pattern shared with the home hub). A single 1000 ms
// controller runs on mount; each child reveals on its own [Interval] slice —
// opacity 0→1 while sliding up 18 px — so the soft-UI search surface assembles
// itself rather than snapping in flat. This is the one high-impact motion
// moment of the screen; everything else stays calm and tactile.

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
    // Flip the gate once the entrance finishes so subsequent rebuilds skip the
    // animation machinery entirely and return children directly.
    _controller.addStatusListener(_onStatus);
    _controller.forward();
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    for (final CurvedAnimation curve in _curves.values) {
      curve.dispose();
    }
    _controller.removeStatusListener(_onStatus);
    _controller.dispose();
    super.dispose();
  }

  Widget _reveal({
    required double start,
    required double end,
    required Widget child,
  }) {
    // Entrance only runs once on mount — after it completes, return the child
    // directly with no animation wrappers and no per-rebuild allocation.
    if (_controller.isCompleted) {
      return child;
    }
    final CurvedAnimation curved = _curves.putIfAbsent(
      (start, end),
      () => CurvedAnimation(
        parent: _controller,
        curve: Interval(start, end, curve: Curves.easeOutCubic),
      ),
    );
    return FadeTransition(
      opacity: curved,
      child: RepaintBoundary(
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _reveal);
}
