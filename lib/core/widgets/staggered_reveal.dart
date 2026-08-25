// Phase 236 — the shared staggered fade-up entrance.
//
// PROMOTED, NOT WRITTEN. This file is `home_hub_screen.dart`'s private
// `_StaggeredReveal` lifted verbatim into `core/widgets/` and made public. It
// is the SUPERSET of the two private copies that existed before it, so the
// promotion could not lose behaviour in either direction:
//
//   * `home_hub_screen.dart:618` — interval memoization + disposal (the
//     listener-leak fix, pinned by `home_hub_reveal_lifecycle_test.dart`), the
//     `TickerMode` gate, AND the `disableAnimations` short-circuit. That is
//     this file.
//   * `branch_placeholders.dart:321` — the same `FadeTransition` +
//     `SlideTransition` shape and the same `Offset(0, 0.35)` slide, but WITHOUT
//     the memoization and WITHOUT the `disableAnimations` short-circuit. Both
//     of those are strictly additive: the rendered shape, the curve, the
//     interval and the slide distance are identical, so the placeholders'
//     entrance is pixel-identical and merely stops leaking listeners.
//
// `SearchStaggeredReveal` (`features/discovery/presentation/widgets/
// staggered_reveal.dart`) is deliberately NOT folded in here. It is a
// genuinely different animation — a `Transform.translate` of a flat 18 logical
// px rather than a 0.35-fraction `SlideTransition`, started unconditionally
// from `initState` with no `TickerMode` gate — and its own file header
// documents a focus/keyboard defect that its exact shape fixes. Unifying the
// two would be a behaviour change on a shipped search screen, not a refactor.
//
// ## The shape is UNCONDITIONAL — never branch on "the entrance finished"
//
// `reveal(...)` must return the same widget SHAPE for the whole life of the
// widget. `Widget.canUpdate` compares `runtimeType`, so short-circuiting to the
// bare `child` once the controller completes unmounts the element and every
// `State` beneath it — which is how the search screen once dismissed its own
// keyboard 1000 ms after mount. A completed `FadeTransition` sits at opacity
// 1.0 (no save layer) and the slide collapses to zero, so keeping the wrappers
// costs nothing at steady state.

import 'package:flutter/material.dart';

/// `reveal(start: …, end: …, child: …)` wraps one child in its delayed fade-up
/// segment of the parent [StaggeredReveal]'s single controller.
typedef RevealFn =
    Widget Function({
      required double start,
      required double end,
      required Widget child,
    });

/// Drives one orchestrated staggered fade-up entrance for a screen.
///
/// A single 1000 ms controller runs once the subtree is actually ticking, and
/// each slot revealed through the builder's `reveal` callback fades in over its
/// own [Interval] slice while sliding up — so a soft-UI surface assembles
/// itself rather than snapping in flat.
///
/// The controller starts from [State.didChangeDependencies], gated on
/// [TickerMode], NOT from [State.initState]. The client shell is a
/// `StatefulShellRoute.indexedStack`, so every branch builds and keeps alive at
/// mount; without the gate all the off-screen 1 s controllers would fire inside
/// the post-login frame budget. `IndexedStack` sets `TickerMode` false for its
/// off-screen children, so the entrance plays exactly once — the first time the
/// branch actually becomes visible.
class StaggeredReveal extends StatefulWidget {
  const StaggeredReveal({super.key, required this.builder});

  /// Builds the body, given a `reveal(start, end, child)` helper.
  final Widget Function(BuildContext context, RevealFn reveal) builder;

  /// The whole entrance's duration; each slot's [Interval] is a fraction of it.
  static const Duration duration = Duration(milliseconds: 1000);

  /// How far a slot slides up, as a fraction of its own height.
  static const double slideFraction = 0.35;

  @override
  State<StaggeredReveal> createState() => _RevealState();
}

/// One slot's reveal animations, built once per distinct interval.
///
/// [opacity] is a [CurvedAnimation] and OWNS a status listener on the parent
/// controller — it must be disposed. [position] is only a `Tween.animate(...)`
/// view over it and needs no disposal of its own.
class _RevealAnimations {
  const _RevealAnimations({required this.opacity, required this.position});

  final CurvedAnimation opacity;
  final Animation<Offset> position;
}

class _RevealState extends State<StaggeredReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _started = false;

  // PERF: `_reveal` is invoked once per slot on EVERY build of the host body,
  // and a hub body watches four providers — so allocating a fresh
  // `CurvedAnimation` per call leaked a listener on each one.
  // `CurvedAnimation`'s constructor calls `parent.addStatusListener(...)` and
  // ONLY its `dispose()` removes it, so undisposed instances accumulated on
  // `_controller` for the whole lifetime of the screen. Building each distinct
  // `(start, end)` interval exactly once — and disposing every cached one in
  // `dispose()` — keeps the listener set bounded AND properly torn down. Keyed
  // on the interval record: Dart records have structural equality, so identical
  // bounds reuse one entry.
  final Map<(double, double), _RevealAnimations> _revealCache =
      <(double, double), _RevealAnimations>{};

  /// Upper bound on [_revealCache], asserted in [_reveal].
  ///
  /// Mirrors `_InsetShadowPainter._kMaxCachedRadii` (`neumorphic.dart:137`),
  /// and for the same reason: a memo whose key set is not closed by an enum is
  /// a leak the moment a caller starts computing its keys, and NOTHING about
  /// that failure is visible at the call site.
  ///
  /// It is not hypothetical. A favourites list computed its per-row `start`
  /// from the list LENGTH, so every removal minted a fresh interval; emptying
  /// a 40-row list one row at a time cached 486 `CurvedAnimation`s, each
  /// holding a status listener on `_controller`, on a screen that is a
  /// `StatefulShellRoute.indexedStack` branch and therefore never disposed for
  /// the whole session. That caller now QUANTIZES its interval (2 decimal
  /// places), which is what bounds the key set — see
  /// `favorites_screen.dart`'s `_quantize` (applied to the `_stepFor`-derived
  /// bounds in `_rowsSliver`).
  ///
  /// The budget: at 2-decimal quantization one screen can mint at most ~81
  /// distinct starts in the usable 0.0–0.8 band, and a screen actually
  /// revealing that many slots at once does not exist. 96 is roughly double the
  /// largest plausible legitimate set (a 40-row list plus its chrome), so a new
  /// design intent will not trip it while a genuinely UNQUANTIZED computed
  /// interval blows it within a couple of dozen mutations.
  static const int _kMaxCachedIntervals = 96;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: StaggeredReveal.duration,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Start the one-shot reveal only when this subtree is actually ticking
    // (i.e. it is the visible IndexedStack child). Off-screen branches have
    // TickerMode=false at mount and flip to true the first time their tab is
    // selected, at which point this fires and the reveal plays once.
    if (!_started && TickerMode.valuesOf(context).enabled) {
      _started = true;
      // Post-frame so the initial paint is not lost at 0.0 opacity.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // With platform animations disabled (reduced motion, a muted ticker)
        // there may be no ticks to advance the controller at all — jump
        // straight to the visible end state rather than leaving content
        // permanently invisible.
        final bool animationsDisabled =
            MediaQuery.maybeOf(context)?.disableAnimations ?? false;
        if (animationsDisabled) {
          _controller.value = 1.0;
        } else {
          _controller.forward();
        }
      });
    }
  }

  @override
  void dispose() {
    // Each cached CurvedAnimation still holds a status listener on _controller —
    // dispose them BEFORE the controller so every listener is removed.
    for (final _RevealAnimations anims in _revealCache.values) {
      anims.opacity.dispose();
    }
    _revealCache.clear();
    _controller.dispose();
    super.dispose();
  }

  Widget _reveal({
    required double start,
    required double end,
    required Widget child,
  }) {
    // Lazily memoized per interval — see the `_revealCache` comment above for
    // why re-allocating these on every build is a listener leak.
    assert(
      _revealCache.containsKey((start, end)) ||
          _revealCache.length < _kMaxCachedIntervals,
      'StaggeredReveal._revealCache grew past $_kMaxCachedIntervals entries. '
      'It is keyed by the (start, end) interval, and every caller is expected '
      'to pass either a literal constant or a QUANTIZED value, so this means '
      'a raw computed interval is now reaching it — which makes this memo an '
      'unbounded leak of CurvedAnimations (each one holds a status listener '
      'on the controller) instead of the fixed table it is meant to be. Round '
      'the interval at the call site, as favorites_screen._quantize does to '
      'its _stepFor-derived bounds; do NOT raise this cap to make the assert '
      'go away.',
    );
    final _RevealAnimations anims = _revealCache.putIfAbsent((start, end), () {
      final CurvedAnimation opacity = CurvedAnimation(
        parent: _controller,
        curve: Interval(start, end, curve: Curves.easeOutCubic),
      );
      return _RevealAnimations(
        opacity: opacity,
        position: Tween<Offset>(
          begin: const Offset(0, StaggeredReveal.slideFraction),
          end: Offset.zero,
        ).animate(opacity),
      );
    });
    return FadeTransition(
      opacity: anims.opacity,
      child: SlideTransition(position: anims.position, child: child),
    );
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _reveal);
}
