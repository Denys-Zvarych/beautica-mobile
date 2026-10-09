// Phase 21.12 — the timeline's geometry, expressed as ONE density token.
//
// Every vertical and horizontal constant the booking timeline needs — hour
// height, half-hour slot, ruler gutter width, column-width ceiling, inter-
// column gutter — is derived here from a single [scale]. [BookingsTimelineGrid]
// and [TimelineHourRuler] both read THIS object and nothing else, so the
// master scope and the salon scope are the SAME two widgets handed two
// different densities rather than four widgets.
//
// ============================================================================
// THE LOCKSTEP THIS REPLACES
// ============================================================================
// `BookingsTimelineGrid._kHourH` and `TimelineHourRuler._kHourH` were the same
// number spelled TWICE, in two files, coupled only by a comment ("MUST stay in
// LOCKSTEP … or the ruler labels and the lane hairlines desync") plus a test
// asserting they agree. Both now read [hourHeight] off one token, so the
// coupling is STRUCTURAL: there is no second number left to drift. The two
// constants survive as `static const` mirrors of `TimelineDensity.master`'s
// getters purely so the historical ADDENDUM prose in those files still has
// something to name — they are never read on a render path.
//
// ============================================================================
// WHAT SCALES, AND WHAT DELIBERATELY DOES NOT
// ============================================================================
// **Geometry scales. Typography does not.**
//
// [MasterBookingCard] chooses one of three bodies from the `minHeight` its
// caller hands it — full (>= `fullLayoutMinHeight`), compact
// (>= `estimatedNaturalHeight`), micro (below that) — and all three thresholds
// are MEASURED natural heights of real, UNSCALED text (see that widget's class
// doc and `master_booking_card_layout_height_test.dart`, which pins them to
// the pixel). Multiplying them by [scale] would be a font change dressed up as
// a layout change: it would shrink the very text a salon owner is scanning,
// which is the opposite of what the salon board was asked for ("see more of
// the day and more masters at once").
//
// So the thresholds stay put and only the BANDS shrink. That re-tiers the day
// exactly as intended and nothing clips, because the card's height argument is
// a `BoxConstraints.minHeight` FLOOR, never an exact `height:` — a card may
// always grow past its band (the R2 `OverflowBox`/`ClipRect` ban in
// `bookings_timeline_grid.dart` still holds):
//
//   | booking | band @1.0 | tier    | band @0.7 | tier    |
//   |---------|-----------|---------|-----------|---------|
//   | 120 min | 240dp     | full    | 168dp     | full    |
//   |  90 min | 180dp     | full    | 126dp     | full    |
//   |  60 min | 120dp     | full*   |  84dp     | compact |
//   |  45 min |  90dp     | compact |  63dp     | compact |
//   |  30 min |  60dp     | compact |  42dp     | micro   |
//   |  15 min |  30dp     | micro   |  28dp**   | micro   |
//
//   * 120dp clears the 118dp full threshold by 2dp — see
//     `bookings_timeline_grid.dart`'s ADDENDUM 8, which is why `_kHourH` may
//     not go below 120 for the MASTER scope.
//  ** floored at `MasterBookingCard.microLayoutNaturalHeight` by
//     `_cardMinHeightFor`, which this token deliberately does not touch.
//
// [salonScale] 0.7 is the LOWEST clean step: a 45-minute booking keeps the
// compact body only while `0.75 * hourHeight >= 56`, i.e. while
// `hourHeight >= 75` (`scale >= 0.625`). Below that three-quarters of an hour
// collapses to a one-line micro card and the board stops reading as a
// schedule.
//
// ============================================================================
// WHAT IS NOT HERE, AND WHY
// ============================================================================
//  * `TimelineHourRuler.labelCenteringNudge` (7dp) is NOT scaled, and is not a
//    member of this class. It centres each hour LABEL on its own gridline, so
//    it is half a measured text height — and text does not scale (above). The
//    partial design preview under `docs/signup-designs/SalonBookingsBoard/`
//    scales it (`7 * scale`); that contradicts the preview's own
//    typography-does-not-scale rule and would hang every salon-scope label
//    ~2dp below its line. Verified against the source rather than the prose,
//    per this track's brief.
//  * The card's height FLOOR (`microLayoutNaturalHeight`) is not scaled for
//    the same reason; `_cardMinHeightFor` reads it directly.
//  * `_kTimelineLeftInset` (`bookings_discovery_view.dart`) is a page-edge
//    rhythm shared with the day header above the grid, not timeline geometry.

import 'dart:math' as math;

import 'package:beautica_mobile/core/theme/velvet_geometry.dart';

/// One timeline scope's geometry. Two canonical instances only —
/// [TimelineDensity.master] and [TimelineDensity.salon] — behind a private
/// const constructor, so `==` is identity and a `const` instance is
/// canonicalised by the compiler. That is what lets `didUpdateWidget` compare
/// densities with a bare `!=` and what keeps this class off the
/// hand-written-`==` ban (there is nothing to write).
final class TimelineDensity {
  const TimelineDensity._({
    required this.scale,
    required this.columnsPerViewport,
    this.denseCards = false,
  });

  /// The single-master scope — the INDEPENDENT_MASTER's «Мої записи» and the
  /// invited SALON_MASTER's read-only «Записи». Reproduces the shipped
  /// timeline pixel-for-pixel: every getter below returns exactly the literal
  /// the corresponding retired constant held.
  static const TimelineDensity master = TimelineDensity._(
    scale: 1,
    columnsPerViewport: 1,
  );

  /// The salon-wide owner/admin board — 70 % bands, at least two master
  /// columns on screen at the 360dp Android baseline. See [columnWidth] for
  /// that arithmetic.
  static const TimelineDensity salon = TimelineDensity._(
    scale: salonScale,
    columnsPerViewport: 2,
    denseCards: true,
  );

  /// The salon board's multiplier, named so the derivations above and the
  /// phase doc can cite one number. 30 % denser than the master board, per the
  /// user's request.
  static const double salonScale = 0.7;

  /// Multiplier on every scaled constant below. `1` reproduces the shipped
  /// master timeline exactly.
  final double scale;

  /// How many master columns must fit inside the lane viewport — the divisor
  /// in [columnWidth]'s clamp. `1` for a single-master scope, where the clamp
  /// reduces to the shipped `math.min(_kCardW, constraints.maxWidth)`.
  final int columnsPerViewport;

  /// Whether booking cards on this board render their DENSE layout
  /// (`MasterBookingCard.dense`). `true` only for [salon]: its 136-148dp lanes
  /// cannot hold the 203-272dp-budgeted standard card rows.
  final bool denseCards;

  // ── Vertical ───────────────────────────────────────────────────────────

  /// One hour of vertical space. `120` at [master] — the value
  /// `BookingsTimelineGrid._kHourH` and `TimelineHourRuler._kHourH` both held
  /// (history `72` → `112` → `168` → `120`; see the grid's ADDENDUM 8 for why
  /// the MASTER scope may not go lower).
  double get hourHeight => 120 * scale;

  /// One 30-minute slot — half [hourHeight] by construction, exactly as the
  /// retired `_kSlotH`. Drives the half-hour GRIDLINE only; it has governed
  /// neither the card floor nor the ruler labels since the grid's ADDENDUM 7.
  double get slotHeight => hourHeight / 2;

  /// The hour-label gutter. `42` at [master] — sized to fit "23:00"
  /// right-aligned at [VelvetText.timelineHourLabel]'s 11 sp.
  ///
  /// This is the ONE place where scaling geometry without scaling type has a
  /// real floor: the label is unscaled, so the gutter cannot shrink below what
  /// "23:00" actually occupies. `42 * 0.7 = 29.4` rounds UP to 30, which still
  /// fits at 11 sp because the shipped 42 was itself chosen with headroom for
  /// accessibility text scales. Clamped at 30 anyway so no future, smaller
  /// [scale] can silently clip a clock reading.
  double get rulerWidth => math.max(30, (42 * scale).roundToDouble());

  // ── Horizontal ─────────────────────────────────────────────────────────

  /// The column-width CEILING — the retired `_kCardW` (`272`) scaled, so `272`
  /// at [master] and `190` at [salon].
  ///
  /// Never a rendered width on its own: the grid's ADDENDUM 3 documents 272 as
  /// "a CEILING, clamped to `constraints.maxWidth`", and [columnWidth] extends
  /// that same clamp rather than inventing a second sizing rule.
  double get columnWidthCeiling => (272 * scale).roundToDouble();

  /// The gap between two adjacent MASTER columns. `8` (`VelvetSpacing.sm`) at
  /// [master] — where it is also the gap between two overlap LANES, which is
  /// what the shipped grid has always used — and `6` at [salon].
  double get columnGutter =>
      math.max(4, (VelvetSpacing.sm * scale).roundToDouble());

  /// The rendered width of one master column inside a lane viewport of
  /// [laneViewportWidth].
  ///
  /// ## THE N-COLUMN CLAMP
  ///
  /// `min(ceiling, (viewport − gutters) / columnsPerViewport)` — the same
  /// SHAPE as the shipped grid's `math.min(_kCardW, constraints.maxWidth)`,
  /// with the divisor generalised from 1 to [columnsPerViewport]. At
  /// `columnsPerViewport == 1` the gutter term is `columnGutter * 0 == 0` and
  /// the divisor is 1, so this IS the shipped expression, term for term — the
  /// master scope is unchanged BY CONSTRUCTION, not by a test.
  ///
  /// There is deliberately no lower floor. The partial preview clamps the
  /// result up to 96dp; on a viewport narrower than that, a column wider than
  /// the viewport is exactly the ADDENDUM 3 right-edge clipping bug this clamp
  /// exists to prevent, so the floor is omitted in both scopes.
  ///
  /// At the 360dp baseline the salon scope resolves to:
  ///
  ///   lane viewport = 360 − 12 (left inset) − 12 (right inset)
  ///                       − 30 (rulerWidth) − 4 (ruler↔grid gap) = 302
  ///   column        = min(190, (302 − 6) / 2) = **148dp**
  ///
  /// so two masters are always on screen, and on a 430dp device the columns
  /// grow TOWARD — never past — the 190dp ceiling instead of stretching.
  double columnWidth(double laneViewportWidth) {
    final double gutters = columnGutter * (columnsPerViewport - 1);
    return math.min(
      columnWidthCeiling,
      (laneViewportWidth - gutters) / columnsPerViewport,
    );
  }
}
