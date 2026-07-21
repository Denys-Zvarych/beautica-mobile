// Phase 7.10 — the master timeline body: the hour ruler + the booking-card
// grid, laid out from the overlap-lane assignment in `booking_lane_layout
// .dart`. Each lane renders as a `Column` of cards, not a `Stack` of
// absolutely-`Positioned` ones — see "R3" below.
//
// Transcribed from the approved design's `_TimelineGrid`
// (`docs/signup-designs/SalonManagementDesign/lib/widgets/
// bookings_toolbar.dart:1336-1459`), WITH the design's latent negative-height
// bug fixed — see "R1" below. No providers, no navigation, no async: this is
// a pure rendering layer over a plain `List<Booking>`; Phase 7.11 wires it
// into the screen.
//
// ============================================================================
// R1 — THE BUG THE DESIGN HIDES, FIXED HERE
// ============================================================================
// The design computes its vertical extent from SCALAR hours-of-day:
//   final int firstHour = bookings.map((b) => b.dateTime.hour).reduce(min);
//   final double latestEndH = (latestEnd.hour - firstHour) + latestEnd.minute / 60.0;
//   final double gridHeight = latestEndH * _kHourH;
// `latestEnd.hour` discards the DATE, so `gridHeight` goes NEGATIVE whenever
// the last booking's end hour-of-day is numerically smaller than the first
// booking's start hour-of-day — reachable on a SINGLE day: a 23:30 booking
// with a 60-minute service ends 00:30 the next day (hour `0`), so with
// `firstHour = 9` the design's formula yields `(0 - 9) + 0.5 = -8.5` and the
// unguarded `SizedBox(height:)` throws. Single-day rendering (Phase 7.9)
// does NOT close this hole — it only closes the design's OTHER latent bug,
// cards from different days superimposing (moot here since every list this
// widget ever receives is one day's worth).
//
// THE FIX: compute the extent in MINUTES-SINCE-THE-SELECTED-KYIV-DAY'S-
// MIDNIGHT instead of scalar hours. A booking ending after midnight then
// yields a value > 1440 rather than wrapping to a small number, so
// monotonicity holds by construction and the subtraction cannot go negative.
// [_lastMinuteFloor] is the belt-and-braces floor on top of that: even if
// every booking were somehow malformed, the grid is never shorter than one
// hour.
//
// ============================================================================
// R2 — THE CLIPPING BUG: A DURATION-SCALED HEIGHT ON A FIXED-CONTENT CARD
// ============================================================================
// `MasterBookingCard` renders a FIXED grid of rows (avatar, divider, service
// line, price/status line) — its natural height is ~150dp REGARDLESS of the
// booking's duration. An earlier version of this file set each Positioned
// card's `height:` to `booking.durationMinutes / 60.0 * _kHourH`, floored at
// a `_kMinCardHeight` of 48dp for a 15-minute booking — i.e. as little as
// 48dp of box for content that needs ~150dp+. `MasterBookingCard` then
// honoured that undersized box via an `OverflowBox` + `ClipRect` pair, which
// laid the card out at its full natural height and then CROPPED the paint
// (and the hit-test region) down to the duration-derived box. That is the
// exact mechanism behind the real-device report: "I can see only half of the
// card, and another card is cut off" — any booking shorter than ~50 minutes
// rendered with its bottom rows sliced away.
//
// The design (`_TimelineGrid`, bookings_toolbar.dart:1438-1448) never
// constrains card height at all —
// `Positioned(top:, left:, width: _kCardW, child: BookingCard(...))`, no
// `height:` — so the card always renders its full natural size, independent
// of the booking's duration. That is now authoritative here too: nothing in
// this file computes or passes a card height (the R3 fix below constrains
// only `width`), and `MasterBookingCard` no longer accepts one (its former
// `width`/`height` params existed ONLY for the old call site — see that
// widget's class doc).
//
// The knock-on effect, closed by the R3 fix below: whatever decides each
// card's vertical position must reserve real room for that ~150-190dp of
// content, not just the `durationMinutes`-derived slice of the ruler the
// booking nominally occupies.
//
// ============================================================================
// R3 — HIGH-1: SAME-LANE CARDS OVERLAPPING (AND STEALING EACH OTHER'S TAPS)
// ============================================================================
// R2 fixed the clip; it also reintroduced, in a worse shape, the exact
// problem R2 itself replaced. Once every card paints its full ~150-190dp
// regardless of duration, two back-to-back bookings in the SAME lane — the
// ordinary case for a working master, e.g. 09:00-09:30 then 09:30-10:00 —
// only advance `top` by `durationMinutes / 60 * _kHourH` (36dp for a 30-minute
// booking), so the second card's top lands well inside the first card's real
// ~150-190dp body. Both were plain `Positioned` children of one `Stack`,
// painted in ascending `startAt` order, so the LATER booking painted on top
// and WON every hit-test in the overlapping region — tapping what visually
// reads as client A's row could silently open client B's booking.
//
// TWO CANDIDATE FIXES, AND WHY THIS FILE DOES NOT TAKE THE FIRST ONE:
//
//  (a) Make lane OCCUPANCY height-aware — treat a booking as occupying its
//      lane until `max(endAt, startAt + <card's real height as a duration>)`
//      rather than just `endAt`, so `assignLanes` opens a new lane whenever a
//      card's real footprint would collide. Rejected: a card is 272dp wide;
//      a day with several short back-to-back bookings (exactly the case that
//      exposed this bug) would then need 3-4+ SIDE-BY-SIDE lanes just to fit
//      cards whose real conflict is vertical, not temporal — on a phone that
//      pushes most of the day's bookings off the right edge of the screen,
//      trading a misdirected-tap bug for a hidden-bookings bug. Also would
//      require touching `booking_lane_layout.dart`'s `assignLanes`, which
//      today is a clean, pure, time-only interval-partition — correct on its
//      own terms and unit-tested in isolation; entangling it with a
//      PRESENTATION-layer widget's pixel geometry (a card's rendered height)
//      would break that separation for a horizontal-layout decision that
//      doesn't actually need it (see (b)).
//
//  (b) THE FIX TAKEN — keep lanes exactly as `assignLanes` computes them
//      (still pure time-overlap; `booking_lane_layout.dart` is UNCHANGED),
//      but stop positioning cards WITHIN a lane by absolute, duration-derived
//      `top` alone. Each lane's bookings (already in ascending `startAt`
//      order — [bookings] arrives pre-sorted and lane membership preserves
//      that order) are laid out as a plain flex `Column`, one card after
//      another, with a `SizedBox` spacer in between sized to the WALL-CLOCK
//      gap between the two bookings' starts (so a lane with genuine idle time
//      still reads as idle time against the ruler) — see [_LaneColumn]. This
//      is "time-anchored `top`, nudged down so a card never starts above the
//      previous card's bottom", and it is safe by CONSTRUCTION: a `Column`
//      physically cannot lay out child N+1 starting above child N's real
//      bottom edge, regardless of how any spacer was computed. Compare (a),
//      where safety depends on `assignLanes` correctly predicting a card's
//      real height ahead of time — get that estimate wrong (a locale with
//      longer strings, an accessibility text-scale bump) and cards can
//      overlap again despite the "fix". [_LaneColumn]'s spacer maths uses
//      `MasterBookingCard.estimatedNaturalHeight` (see its doc) purely to
//      decide how much blank space LOOKS right when there's slack — an
//      estimate error there only ever compresses or loosens that blank
//      space, never lets two cards intersect.
//
// The knock-on effect on hit-testing: since same-lane cards can no longer
// overlap at all, "the later booking wins the tap" is eliminated structurally
// too — there is no longer a shared paint order to race, because there is no
// longer any region two cards both claim.
//
// The knock-on effect on [gridHeight]: it no longer exists as a computed
// number. The old `_kCardBottomBuffer` guess (a fixed +190dp margin added to
// a minutes-derived extent, so the scroll area was "probably" tall enough)
// is GONE — replaced by letting the `Stack`'s non-`Positioned` sizing child
// (the `Row` of per-lane `Column`s) determine the `Stack`'s real height via
// ordinary box layout, i.e. the ACTUAL summed height of the tallest lane's
// spacers + real card sizes. See [build]'s final `Stack` for how a
// non-`Positioned` child drives a `Stack`'s size while `Positioned` siblings
// (the hour gridlines) still layer on top of whatever size that resolves to.
//
// ============================================================================
// ADDENDUM (2026-07-20) — THE COMPACT-TIMELINE PASS, AND WHY THIS FILE DIDN'T
// NEED TO CHANGE FOR IT
// ============================================================================
// The ~150-190dp figures throughout R2/R3 above are HISTORICAL — they were
// true when this file's `_LaneColumn` fix landed, and are the reason that fix
// was necessary at all. `MasterBookingCard` has since dropped its avatar row
// and moved to a two-line grid targeting ~52-56dp (`estimatedNaturalHeight`,
// see that widget's class doc), specifically so real bookings reach their
// true `desiredTop` more often and the collision-nudge this file computes
// stays a rare, small correction instead of a growing drift. Nothing in R1,
// R2, or R3 above needed to change for that: [_LaneColumn]'s
// `max(_kMinInterCardGap, desiredTop - plannedBottom)` nudge is correct for
// ANY card height, tall or short — it is the mechanism that made the height
// reduction safe to ship without touching this file's collision logic at
// all. A 15-minute slot (18dp of ruler) is still shorter than any realistic
// card, so the nudge remains load-bearing in that case; it is simply idle
// (contributes `desiredTop - plannedBottom`, its normal no-collision branch)
// for everything roomier.
//
// ============================================================================
// ADDENDUM 2 (2026-07-20) — PROPORTIONAL-DURATION-HEIGHT PASS
// ============================================================================
// The compact-timeline pass above (`MasterBookingCard`'s own class doc) fixed
// the DRIFT report by shrinking the card so it usually fit inside its own
// slot. It deliberately left every card the SAME height regardless of
// duration — a 90-minute service and a 30-minute service rendered
// identically, so the grid never visually communicated "this service takes
// three times as long". This pass makes the card's real footprint track its
// `durationMinutes`, floored at one 30-minute slot, WITHOUT reopening the R2
// clipping bug — the mechanism matters, so read this before touching either
// number below.
//
// THE MEASUREMENT THAT PICKED THE NEW SCALE:
//   `MasterBookingCard`'s real rendered height (no forced height, `Center`-
//   loosened constraints, a 20-minute booking) measures **54dp** — see
//   `master_booking_card_test.dart`'s "compact card height" group for the
//   harness this number is pinned against. A 30-minute grid slot MUST be
//   `>=` that, or a card would need to grow past its own slot for every
//   ordinary (< ~35 minute) booking, right back to the drift `_LaneColumn`'s
//   nudge exists to absorb only for the RARE sub-30-minute case.
//
//   Chosen: slot height **56dp** (54dp measured + 2dp headroom, not a bare
//   equality — avoids a test asserting `>=` failing on a sub-pixel rounding
//   difference between runs). `_kHourH` = 2 x 56 = **112dp**, up from 72.
//   A working day now scrolls noticeably further — an accepted consequence
//   of the request, not something to claw back by shrinking the card again
//   (it was already compacted once; see that widget's class doc for why a
//   THIRD density pass was rejected as a shape change, not a bug fix).
//
// THE MECHANISM — A FLOOR (`BoxConstraints.minHeight`), NEVER AN EXACT
// `height:`:
//   Each card's box gets `MasterBookingCard(minHeight: ...)`, computed as
//   `max(durationMinutes / 60 * _kHourH, _kHourH / 2)` — proportional to
//   duration, floored at one slot for anything under 30 minutes. Critically
//   this is a MINIMUM constraint on the widget's own `AnimatedContainer`
//   (`constraints: BoxConstraints(minHeight: ...)`), not a `SizedBox`-style
//   exact `height:`. A `ConstrainedBox`/`Container` with only a `minHeight`
//   can grow PAST that floor to fit its child but can never force the child
//   to render smaller than its natural size — the exact opposite of the R2
//   bug's `OverflowBox` + `ClipRect` pair, which forced an EXACT box and then
//   cropped whatever didn't fit. If a future locale, font-scale bump, or
//   content change ever makes the card's natural content taller than the
//   computed floor, the box simply grows with it — content always wins, by
//   construction, not by convention. See `MasterBookingCard`'s own class doc
//   for the widget-side half of this contract.
//
//   Because slot height (56dp) was chosen to already clear the card's real
//   content height (54dp), the duration-derived floor is ALSO always `>=`
//   natural content height for every booking `>= 30` minutes — the two
//   constraints coincide in the common case and only diverge for the
//   sub-30-minute floor, which is exactly where `_LaneColumn`'s
//   collision-nudge remains load-bearing (see below).
//
// WHY `_LaneColumn` IS STILL NECESSARY, NOT VESTIGIAL:
//   For a booking `>= 30` minutes, its computed height now equals its real
//   wall-clock footprint, so back-to-back bookings tile with (at most) the
//   cosmetic `_kMinInterCardGap` between them — the nudge's `max(...)` branch
//   degenerates to its floor branch every time. For a booking `< 30`
//   minutes, though, the slot floor forces a box TALLER than the booking's
//   own scheduled duration (a 10-minute touch-up still gets a 56dp box in a
//   28dp-wide wall-clock slot) — exactly the case R3's header describes,
//   just with different numbers. `_LaneColumn`'s Column-layout guarantee
//   (child N+1 physically cannot start above child N's real bottom) is what
//   keeps that case safe, and nothing about proportional height changes that
//   guarantee's mechanism — see the R3 section above, unmodified.
//
//   `plannedBottom`'s bookkeeping now advances by each card's actual computed
//   `minHeight` (see `_cardMinHeightFor`) rather than the fixed
//   `MasterBookingCard.estimatedNaturalHeight` constant the R3-era code used
//   — a strictly better "planned" number now that a real duration-derived
//   floor exists, though (per the R3 section) the Column's real layout would
//   still be safe even if this planning number were wrong.
//
// THE HALF-HOUR GRIDLINES:
//   The stated minimum grid unit is 30 minutes, so the gridline `Stack` now
//   draws one hairline every half hour, not every hour. The HOUR lines keep
//   the original full-opacity `BrandColors.faint` so the hour rhythm still
//   reads as primary; the new HALF-HOUR lines use the same hue at a lighter
//   alpha (`_halfHourLineColor`) so they register as secondary structure,
//   not visual noise competing with the hour lines. `TimelineHourRuler`'s
//   LABELS stay hourly on purpose — a label every 30 minutes would clutter
//   the gutter without adding legibility the gridline itself doesn't already
//   provide.
//
// ============================================================================
// ADDENDUM 3 (2026-07-21) — THE NARROW-DEVICE CLIPPED-CARD FIX
// ============================================================================
// Real-device report: on a 360dp-wide Android phone the "Мої записи" timeline
// card was clipped at its right edge and only readable by scrolling the inner
// horizontal `SingleChildScrollView` sideways — a bug no widget test caught
// because that scroll view absorbs overflow instead of throwing a RenderFlex
// overflow error (there is no exception to assert against; the content is
// just off-screen).
//
// THE ARITHMETIC: the lane area's available width is
//   deviceWidth − 24 (screen padding L) − 24 (screen padding R)
//              − 42 (`TimelineHourRuler._kRulerWidth`)
//              − 4  (`VelvetSpacing.xs`, the ruler↔grid gap above)
//   = deviceWidth − 94.
// [_kCardW] (272) only fits once `deviceWidth − 94 >= 272`, i.e.
// `deviceWidth >= 366`. The common 360dp Android baseline clears every term
// above EXCEPT this one — it has only 266dp of lane area, 6dp short of the
// fixed 272dp card, so the card's right edge is permanently clipped on first
// paint.
//
// THE FIX: [_kCardW] stays defined as-is but becomes a CEILING, not a fixed
// width — [build]'s `LayoutBuilder` computes
// `effectiveCardW = math.min(_kCardW, constraints.maxWidth)` and uses that
// (never the raw constant) for both [contentWidth] and every lane's
// `cardWidth`. The clamp is computed from `constraints.maxWidth`, so it can
// only be known inside the `LayoutBuilder` callback — [contentWidth] moved in
// there with it (it used to be computed once in [build], before the
// available width was known).
//
// THE CLAMP IS UNCONDITIONAL — APPLIED FOR EVERY [lanesCount], NOT ONLY
// `lanesCount <= 1`: with 2+ overlap lanes the grid still scrolls
// horizontally to reach lane 2 and beyond (that is inherent to laying
// multiple lanes side-by-side and is not this bug), but the LEADING lane's
// card — the one visible without any horizontal scrolling — must never clip
// at the viewport's right border on first paint, exactly as in the
// single-lane case. Clamping only when `lanesCount <= 1` would leave that
// leading-card clip in place on any narrow device whose day happens to have
// an overlapping booking. Clamping every lane to the same `effectiveCardW`
// also keeps all lanes' cards a uniform width, matching every other
// assumption in this file (`_LaneColumn`'s spacer math, [_cardMinHeightFor]'s
// height side of the layout, R2/R3 above) — none of which depend on the
// card's width value, only on it being decided once per render and applied
// consistently.
//
// ============================================================================
// THE RULER IS THE KYIV WALL-CLOCK
// ============================================================================
// Every card's vertical position reads through [toBeauticaTime] — `Booking
// .startAt` is canonical UTC, so reading `.hour`/`.minute` off it directly
// would render the wrong row on any non-Kyiv device (and on CI's UTC
// runner). Never `.toLocal()`.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../domain/booking.dart';
import '../../domain/booking_lane_layout.dart';
import 'master_booking_card.dart';
import 'timeline_hour_ruler.dart';

/// The master timeline body for ONE Kyiv calendar day: an hour ruler plus a
/// non-lazy card grid, one flex `Column` per overlap lane (see the file
/// header's "R3" section for why lanes are `Column`s of cards rather than a
/// flat `Stack` of absolutely-`Positioned` ones). Acceptable to fully
/// materialise (no lazy building) because the input is provably bounded to a
/// single day (Phase 7.9) — do NOT generalise this widget to an unbounded
/// list.
///
/// SEC (LOW-5): the non-lazy grid has a second cost beyond render work —
/// EVERY card's client-name-bearing `Semantics` node (`master_booking_card
/// .dart`) exists in the accessibility tree for the whole day at once, not
/// just the on-screen ones. The retired `ListView.builder` virtualized, so
/// only visible cards were ever exposed. `FLAG_SECURE` (acquired by the
/// hosting screen's `ScreenProtectionManager`) blocks screenshots/screen
/// recording but does NOT gate the Android Accessibility API, so a hostile
/// accessibility-service app can enumerate a full day's client names in one
/// sweep instead of only what is visible on screen. This is an ACCEPTED
/// trade-off, not an oversight: `size: 100` already bounds how much PII a
/// single day can ever expose this way (see `bookings_day_notifier.dart`),
/// and a lazily-built list cannot lay out lanes against a shared hour ruler —
/// reintroducing one here would resurrect the R1-adjacent layout bugs this
/// non-lazy grid exists to avoid. Do NOT restructure this widget to "fix"
/// either dimension of the trade-off.
class BookingsTimelineGrid extends StatelessWidget {
  const BookingsTimelineGrid({
    required this.bookings,
    required this.day,
    required this.onBookingTap,
    super.key,
  });

  /// One Kyiv day's bookings, in SERVER order (`startsAt` ASC) — rendered
  /// directly; never mutated or re-sorted here (see [assignLanes]).
  final List<Booking> bookings;

  /// The selected Kyiv calendar day, date-only — the anchor
  /// [_minutesSinceDayStart] measures every card position against.
  final DateTime day;

  /// Fires with the tapped booking. No `Navigator`/`context.push` in this
  /// leaf widget — the caller (Phase 7.11) owns navigation.
  final ValueChanged<Booking> onBookingTap;

  /// One hour of vertical space — MUST match
  /// `TimelineHourRuler._kHourH` so the ruler and the lane hairlines line up.
  ///
  /// See this file's "ADDENDUM 2" for the derivation: raised from `72` to
  /// `112` so a 30-minute slot (`_kSlotH`, `56dp`) clears
  /// `MasterBookingCard`'s real measured height (`54dp`).
  static const double _kHourH = 112;

  /// One 30-minute slot — the grid's minimum unit (ADDENDUM 2). Half of
  /// [_kHourH] by construction; both the gridline spacing and every card's
  /// duration-floor read off this constant, never a re-derived literal.
  static const double _kSlotH = _kHourH / 2;

  /// One lane's card width CEILING — the design's fixed value, but never
  /// used directly as a rendered width. See this file's "ADDENDUM 3": [build]
  /// clamps it down to `constraints.maxWidth` (per render, for every lane)
  /// before it reaches [contentWidth] or any [_LaneColumn.cardWidth], so a
  /// narrow device never clips a card at the viewport's right edge.
  static const double _kCardW = 272;

  /// The minimum breathing room between two same-lane cards even when their
  /// scheduled starts are back-to-back (zero wall-clock gap) — purely
  /// cosmetic (a `Column` already guarantees no overlap with zero spacing);
  /// this just keeps stacked cards from visually touching.
  static const double _kMinInterCardGap = VelvetSpacing.sm;

  /// The half-hour gridline's colour — the same hue as the hour gridline
  /// ([BrandColors.faint]) at a lighter alpha, so the half-hour rhythm reads
  /// as secondary structure rather than competing with the hour lines (see
  /// "ADDENDUM 2"). Hoisted per the file's colour-allocation convention.
  static final Color _halfHourLineColor = BrandColors.faint.withValues(
    alpha: 0.4,
  );

  @override
  Widget build(BuildContext context) {
    final List<int> lanes = assignLanes(bookings);
    final int lanesCount = laneCount(lanes);

    // ------------------------------------------------------------------
    // R1 FIX — minutes-since-[day]'s-Kyiv-midnight, never scalar hours.
    //
    // [_minutesSinceDayStart] anchors every instant to the SAME Kyiv
    // midnight, so a booking ending after midnight yields a value > 1440
    // rather than wrapping to a small number — monotonicity holds by
    // construction and `lastMinute - firstMinute` cannot go negative. The
    // `math.max(..., firstMinute + 60)` floor is belt-and-braces on top of
    // that: even a single, zero-duration-adjacent booking still renders at
    // least one hour of ruler. See the file header's R1 section.
    // ------------------------------------------------------------------
    final int firstMinute = bookings.isEmpty
        ? 0
        : bookings
              .map((Booking b) => _minutesSinceDayStart(b.startAt, day))
              .reduce(math.min);
    final int lastMinuteCandidate = bookings.isEmpty
        ? firstMinute + 60
        : bookings
              .map(
                (Booking b) =>
                    _minutesSinceDayStart(b.startAt, day) + b.durationMinutes,
              )
              .reduce(math.max);
    // Floor: the grid is never shorter than one hour, whatever the data says.
    final int lastMinute = math.max(lastMinuteCandidate, firstMinute + 60);

    final int firstHour = firstMinute ~/ 60;
    final int lastHour = (lastMinute / 60.0).ceil();

    // R3 FIX — group each booking's ORIGINAL index by its assigned lane.
    // [bookings] is already ascending by `startAt` (the class doc's
    // invariant), and this grouping preserves relative order, so each
    // `indices` list below is ascending by `startAt` too without a second
    // sort — exactly the order [_LaneColumn] needs to lay its cards out
    // top-to-bottom. See the file header's "R3" section.
    final List<List<int>> indicesByLane = List<List<int>>.generate(
      lanesCount,
      (_) => <int>[],
    );
    for (int i = 0; i < bookings.length; i++) {
      indicesByLane[lanes[i]].add(i);
    }

    return SingleChildScrollView(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TimelineHourRuler(firstHour: firstHour, lastHour: lastHour),
          // Finding #7 — the grid sat too far right of the ruler versus the
          // design; `VelvetSpacing.xs` (was `.sm`) nudges the whole card area
          // (and its gridlines) slightly left, combined with
          // `TimelineHourRuler`'s own narrower column (see that file).
          const SizedBox(width: VelvetSpacing.xs),
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                // ADDENDUM 3 fix — clamp the card width to whatever lane
                // area is actually available BEFORE it's used to compute
                // [contentWidth] or handed to any lane's cards, so a card
                // never renders wider than the viewport can show. Applied
                // for every [lanesCount] unconditionally — see the file
                // header's "ADDENDUM 3" for why 2+ lanes still needs this on
                // the LEADING lane even though multi-lane days already
                // scroll horizontally by design.
                final double effectiveCardW = math.min(
                  _kCardW,
                  constraints.maxWidth,
                );
                final double contentWidth = lanesCount == 0
                    ? effectiveCardW
                    : lanesCount * effectiveCardW +
                          (lanesCount - 1) * VelvetSpacing.sm;
                final double contentW = math.max(
                  contentWidth,
                  constraints.maxWidth,
                );
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: contentW,
                    // Deliberately NO `height:` — R3 fix. The `Stack` below
                    // sizes itself to its non-`Positioned` child (the `Row`
                    // of lane `Column`s), i.e. to the REAL summed height of
                    // the tallest lane's spacers + actual card sizes, not a
                    // guessed constant. See the file header's "R3" section.
                    //
                    // The leading `Padding` is the label-clipping fix (see
                    // `TimelineHourRuler.labelCenteringNudge`'s doc): rather
                    // than nudging each ruler label UP (which sent the first
                    // label's `top` negative and let the outer vertical
                    // `SingleChildScrollView`'s default `Clip.hardEdge`
                    // permanently crop it), this whole gridline/card `Stack`
                    // is nudged DOWN by the same constant instead. The ruler
                    // and this stack are separate `Stack`s that must stay
                    // registered against each other — shifting only this
                    // one, uniformly, preserves the exact 7dp label↔line
                    // relationship for every hour, `i == 0` included, while
                    // guaranteeing no `top` in either stack is ever negative.
                    child: Padding(
                      padding: const EdgeInsets.only(
                        top: TimelineHourRuler.labelCenteringNudge,
                      ),
                      child: Stack(
                        key: const ValueKey<String>('timeline-lane-stack'),
                        clipBehavior: Clip.none,
                        children: <Widget>[
                          // Finding #8 fix — the hour gridlines are listed
                          // FIRST so they PAINT first (bottom), and the card
                          // `Row` below paints second (on top of them). A
                          // `Stack` paints its children in list order — later
                          // entries paint over earlier ones — so this
                          // ordering alone is what stops the gridlines from
                          // drawing across the booking cards. `Stack`'s SIZE
                          // is unaffected by this: it is computed from every
                          // non-`Positioned` child regardless of that
                          // child's position in the list (the `Positioned`
                          // gridlines never contribute to sizing either
                          // way), so moving the sizing `Row` to the end
                          // changes paint order only, not layout. See the
                          // file header's "R3" section for why the `Row`
                          // must still be the ONE non-`Positioned` child
                          // driving the `Stack`'s size.
                          // ADDENDUM 2 — half-hour gridlines: the stated
                          // minimum grid unit is 30 minutes, so this loops
                          // over HALF-hour indices, not hour indices. Even
                          // indices land exactly on the hour (full-opacity
                          // [BrandColors.faint], matching the pre-existing
                          // hour rhythm the R4 regression test pins); odd
                          // indices are the new half-hour hairlines, drawn at
                          // [_halfHourLineColor] so they read as secondary
                          // structure.
                          for (
                            int half = firstHour * 2;
                            half <= lastHour * 2;
                            half++
                          )
                            Positioned(
                              top: (half - firstHour * 2) * _kSlotH,
                              left: 0,
                              right: 0,
                              height: 1,
                              child: ColoredBox(
                                color: half.isEven
                                    ? BrandColors.faint
                                    : _halfHourLineColor,
                              ),
                            ),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              for (int lane = 0; lane < lanesCount; lane++) ...[
                                if (lane > 0)
                                  const SizedBox(width: VelvetSpacing.sm),
                                _LaneColumn(
                                  key: ValueKey<String>('timeline-lane-$lane'),
                                  bookings: bookings,
                                  indices: indicesByLane[lane],
                                  day: day,
                                  firstMinute: firstMinute,
                                  hourHeight: _kHourH,
                                  cardWidth: effectiveCardW,
                                  onBookingTap: onBookingTap,
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// One overlap lane's cards, stacked top-to-bottom as a plain flex `Column`
/// instead of `Positioned` siblings of a shared `Stack` — the core of the R3
/// fix (see this file's header). A `Column` cannot lay out card N+1 starting
/// above card N's real bottom edge, so same-lane cards can never intersect
/// regardless of how [build]'s per-card `spacer` estimates the gap between
/// them.
class _LaneColumn extends StatelessWidget {
  const _LaneColumn({
    required this.bookings,
    required this.indices,
    required this.day,
    required this.firstMinute,
    required this.hourHeight,
    required this.cardWidth,
    required this.onBookingTap,
    super.key,
  });

  /// The FULL day's bookings — [indices] selects this lane's subset.
  final List<Booking> bookings;

  /// This lane's booking indices into [bookings], ascending by `startAt`
  /// (guaranteed by the caller — see `BookingsTimelineGrid.build`'s grouping
  /// comment).
  final List<int> indices;

  final DateTime day;
  final int firstMinute;
  final double hourHeight;
  final double cardWidth;
  final ValueChanged<Booking> onBookingTap;

  @override
  Widget build(BuildContext context) {
    final List<Widget> children = <Widget>[];
    // The PLANNED bottom edge of the previous card, in the same "minutes
    // since firstMinute, scaled to px" space as every `top` in this file.
    //
    // PROPORTIONAL-DURATION-HEIGHT PASS (this file's "ADDENDUM 2"): advances
    // by each card's actual computed `minHeight` (`_cardMinHeightFor`), not
    // the fixed `MasterBookingCard.estimatedNaturalHeight` the R3-era code
    // used — a real, duration-derived commitment now exists, so it is the
    // better planning number. This remains a PLANNING number only, exactly
    // as before: it decides how generous the blank space between cards
    // looks, never whether two cards can overlap — that guarantee comes from
    // the `Column` below physically laying out child N+1 after child N's
    // REAL rendered size, regardless of this estimate (see the file header's
    // "R3" section, unchanged by this pass).
    double plannedBottom = 0;

    for (int k = 0; k < indices.length; k++) {
      final Booking booking = bookings[indices[k]];
      final int startMinute = _minutesSinceDayStart(booking.startAt, day);
      final double desiredTop = (startMinute - firstMinute) / 60.0 * hourHeight;
      final double cardMinHeight = _cardMinHeightFor(
        booking.durationMinutes,
        hourHeight,
      );

      final double spacer = k == 0
          ? desiredTop
          : math.max(
              BookingsTimelineGrid._kMinInterCardGap,
              desiredTop - plannedBottom,
            );

      children.add(SizedBox(height: spacer));
      children.add(
        // MEDIUM-1 (perf): `MasterBookingCard` is a `StatefulWidget` whose
        // press state drives an `AnimatedScale` (110ms) + `AnimatedContainer`
        // (150ms) — without a boundary, one card's press animation dirties
        // the whole shared layer, so at the ~100-card ceiling a single tap
        // could repaint the entire grid. Same pattern as
        // `calendar_button.dart` and `booking_status_medallion.dart`.
        RepaintBoundary(
          child: SizedBox(
            width: cardWidth,
            child: MasterBookingCard(
              key: ValueKey<String>('timeline-card-${booking.id}'),
              booking: booking,
              onTap: () => onBookingTap(booking),
              minHeight: cardMinHeight,
            ),
          ),
        ),
      );

      plannedBottom += spacer + cardMinHeight;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}

/// A booking's proportional-duration card floor — see this file's
/// "ADDENDUM 2" for the full derivation. Proportional to [durationMinutes]
/// against [hourHeight], floored at one 30-minute slot (`hourHeight / 2`) so
/// nothing under 30 minutes renders shorter than the grid's stated minimum
/// unit. This is a MINIMUM, not an exact size — [MasterBookingCard] applies
/// it as a `BoxConstraints.minHeight`, so real content taller than this
/// value always wins (see that widget's class doc).
double _cardMinHeightFor(int durationMinutes, double hourHeight) {
  final double proportional = durationMinutes / 60.0 * hourHeight;
  return math.max(proportional, hourHeight / 2);
}

/// Minutes between [day]'s Kyiv midnight and [instant]'s Kyiv wall-clock —
/// the R1 fix's anchor. A booking ending after midnight yields a value
/// **greater than 1440** rather than wrapping to a small number, so
/// monotonicity holds by construction.
int _minutesSinceDayStart(DateTime instant, DateTime day) {
  final tz.TZDateTime local = toBeauticaTime(instant);
  final tz.TZDateTime midnight = tz.TZDateTime(
    beauticaZone,
    day.year,
    day.month,
    day.day,
  );
  return local.difference(midnight).inMinutes;
}
