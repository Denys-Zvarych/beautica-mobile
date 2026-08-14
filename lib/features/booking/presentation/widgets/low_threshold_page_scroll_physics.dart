import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/widgets.dart';

/// Fraction of the viewport a position-only (near-zero-velocity) drag must
/// cross before [LowThresholdPageScrollPhysics] commits to the adjacent
/// page, instead of springing back to the page it started from.
///
/// Stock `PageScrollPhysics` uses 0.5 here (see its private
/// `_getTargetPixels`, `package:flutter/src/widgets/page_view.dart`): when a
/// drag's release velocity is below `tolerance.velocity` (~7px/s at typical
/// Android DPR — a paused-before-lift release), it just rounds the current
/// fractional page, so the drag has to cross HALF the viewport to commit.
/// That mismatch — a light flick pages on a ±0.5-page nudge, a paused
/// release needs a full half-screen drag — is the root cause of the
/// «Мої записи» month grid and week rail feeling "strange, and not easy" to
/// swipe. This constant halves the position-only requirement to 0.25.
///
/// The velocity branch (a drag still moving at release) is intentionally
/// **untouched** — it already commits generously on a ±0.5-page nudge and
/// was never the problem.
const double kPageCommitFraction = 0.25;

/// [PageScrollPhysics] with a lower distance-only commit threshold.
///
/// Reproduces stock `PageScrollPhysics.createBallisticSimulation` exactly,
/// except in the branch where the release `velocity` is below
/// `tolerance.velocity` (the finger paused before lifting). There, instead of
/// rounding the current fractional page to the nearest whole page — a 50%
/// threshold — it commits to the neighbouring page once the drag has crossed
/// [kPageCommitFraction] of the viewport **in the direction the drag was
/// already heading**.
///
/// Direction still has to come from somewhere: a fractional page value alone
/// is ambiguous at a lowered threshold. A page sitting 70% of the way between
/// page 1 and page 2 could be a barely-committed 2→1 excursion (should spring
/// back to 2) or an almost-committed 1→2 excursion (should commit to 2) — the
/// same number, two different correct answers.
///
/// `velocity`'s sign is **not** a safe direction signal here, despite being
/// tempting: this branch exists precisely for the "finger paused before
/// lifting" case, and its defining condition — `|velocity| <=
/// tolerance.velocity` — is satisfied by a genuine `velocity == 0.0`, not
/// just small values either side of it. At exactly zero, `sign >= 0` always
/// reads "forward" regardless of which way the drag actually went, so a
/// paused backward release beyond the threshold would spring back to where
/// it started instead of committing. (This was shipped and empirically
/// reproduced — see `bookings_pager_commit_threshold_test.dart`.) Instead,
/// direction comes from [ScrollPosition.userScrollDirection] on `position`:
/// it records the direction of the most recent *user* drag input and does
/// not decay towards zero the way velocity does when the finger stops, so it
/// is still meaningful at the exact instant velocity reads zero. Note
/// Flutter names [ScrollDirection] from the content's point of view, which
/// is the inverse of "page number increasing" — see `_isForwardPaging`
/// below for the exact mapping. `velocity`'s sign is kept only as a
/// last-resort fallback for a bare `ScrollMetrics` that isn't a
/// `ScrollPosition` (never true at either real call site — see `_getPage`
/// above) or the rare case `userScrollDirection` reads `idle`.
///
/// The velocity-magnitude branches (a fling commits on a ±0.5-page nudge) are
/// copied verbatim from the stock implementation and are **not** the fix —
/// this class only changes what happens when the finger stops before
/// lifting.
class LowThresholdPageScrollPhysics extends PageScrollPhysics {
  const LowThresholdPageScrollPhysics({super.parent});

  @override
  LowThresholdPageScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return LowThresholdPageScrollPhysics(parent: buildParent(ancestor));
  }

  /// Mirrors stock `PageScrollPhysics._getPage`. `position` is a `PageMetrics`
  /// at every real `PageView` call site (its concrete `_PagePosition` both
  /// implements the public `PageMetrics` interface and overrides `page` with
  /// the exact fractional value), so `position.page` resolves through dynamic
  /// dispatch to the same figure the stock implementation reads — the
  /// pixels-over-viewport fallback below only serves a bare `ScrollMetrics`
  /// this physics is never actually attached to.
  double _getPage(ScrollMetrics position) {
    if (position is PageMetrics) {
      return position.page ?? position.pixels / position.viewportDimension;
    }
    return position.pixels / position.viewportDimension;
  }

  /// Mirrors stock `PageScrollPhysics._getPixels`. The stock version calls
  /// `_PagePosition.getPixelsFromPage`, which is not part of the public
  /// `PageMetrics` interface and so cannot be reached from outside the
  /// framework library; this recomputes the same figure from `viewportFraction`
  /// (public on `PageMetrics`), correct as long as `viewportFraction` stays at
  /// its default 1.0 — true at both `beautica-mobile` call sites, where the
  /// centred-page offset stock `_PagePosition` adds for `viewportFraction > 1`
  /// is always zero.
  double _getPixels(ScrollMetrics position, double page) {
    if (position is PageMetrics) {
      return page * position.viewportDimension * position.viewportFraction;
    }
    return page * position.viewportDimension;
  }

  /// True when the direction of travel that led into this ballistic
  /// simulation was *increasing* `page` — i.e. what this codebase calls
  /// "forward" paging. False for decreasing `page` ("backward").
  ///
  /// Primary signal: [ScrollPosition.userScrollDirection], set on every
  /// drag-update by [ScrollPositionWithSingleContext.applyUserOffset] from
  /// the sign of that update's pixel delta, and left untouched by a pause —
  /// it only resets to [ScrollDirection.idle] when a *new*, non-scrolling
  /// activity begins, which has not yet happened at the point
  /// `createBallisticSimulation` runs. Flutter names the enum from the
  /// content's point of view, which inverts the mapping you'd guess:
  /// [ScrollDirection.reverse] means pixels (and so `page`) are
  /// *increasing* ("reversing away from zero"), [ScrollDirection.forward]
  /// means they're *decreasing* ("forward towards zero") — see the enum's
  /// own doc comment in `scroll_activity.dart`. Both this signal and its
  /// fallback are unambiguous exactly at `velocity == 0.0` and correct for
  /// drags past 50% of a page, because neither reads `fraction` at all.
  ///
  /// Fallback: `velocity`'s sign, for a bare `ScrollMetrics` that isn't a
  /// `ScrollPosition` (defensive only — never true at either real call
  /// site, see `_getPage` above) or the rare case `userScrollDirection`
  /// reads [ScrollDirection.idle] (e.g. a simulation entered without a
  /// preceding user drag). This mirrors the stock `>= 0` tie-break so an
  /// undecided signal still resolves deterministically.
  bool _isForwardPaging(ScrollMetrics position, double velocity) {
    if (position is ScrollPosition) {
      switch (position.userScrollDirection) {
        case ScrollDirection.reverse:
          return true;
        case ScrollDirection.forward:
          return false;
        case ScrollDirection.idle:
          break;
      }
    }
    return velocity >= 0;
  }

  double _getTargetPixels(
    ScrollMetrics position,
    Tolerance tolerance,
    double velocity,
  ) {
    double page = _getPage(position);
    if (velocity < -tolerance.velocity) {
      page -= 0.5;
    } else if (velocity > tolerance.velocity) {
      page += 0.5;
    } else {
      // Position-only branch — see the class doc and `_isForwardPaging` for
      // why direction comes from `userScrollDirection`, not `velocity`'s
      // sign, which is meaningless at the exact `velocity == 0.0` this
      // branch exists to serve.
      final double base = page.floorToDouble();
      final double fraction = page - base;
      page = _isForwardPaging(position, velocity)
          ? (fraction > kPageCommitFraction ? base + 1 : base)
          : (fraction < 1 - kPageCommitFraction ? base : base + 1);
    }
    return _getPixels(position, page.roundToDouble());
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    // Out of range and not headed back in range — defer to the parent
    // ballistics, exactly as stock `PageScrollPhysics` does.
    if ((velocity <= 0.0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0.0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final Tolerance tolerance = toleranceFor(position);
    final double target = _getTargetPixels(position, tolerance, velocity);
    if (target != position.pixels) {
      return ScrollSpringSimulation(
        spring,
        position.pixels,
        target,
        velocity,
        tolerance: tolerance,
      );
    }
    return null;
  }
}
