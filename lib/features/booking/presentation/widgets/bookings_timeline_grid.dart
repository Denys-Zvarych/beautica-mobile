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
//   NOTE (superseded by ADDENDUM 7): the original pass CONFLATED two floors —
//   it chose a 56dp slot to clear the 54dp card and then let that same 56dp
//   double as both the gridline unit AND the card's minimum. ADDENDUM 7
//   splits them: the gridline slot (`_kSlotH`, now 84dp) and the card's
//   legibility minimum (`MasterBookingCard.estimatedNaturalHeight`, 56dp) are
//   now independent numbers. The card floor is `56dp`, NOT `hourHeight / 2`.
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
// THE ARITHMETIC (as of 2026-08-15 — the left inset halved, see below):
//   deviceWidth − 12 (screen padding L) − 24 (screen padding R)
//              − 42 (`TimelineHourRuler._kRulerWidth`)
//              − 4  (`VelvetSpacing.xs`, the ruler↔grid gap above)
//   = deviceWidth − 82.
// [_kCardW] (272) fits once `deviceWidth − 82 >= 272`, i.e.
// `deviceWidth >= 354` — so the common 360dp Android baseline now HAS 278dp
// of lane area and renders the card at its full natural 272dp. The clamp is
// inert there; it still bites below 354dp (e.g. 320dp small phones, and any
// device once a 2+-lane overlap narrows the per-lane budget).
//
// THE ORIGINAL NUMBERS (kept so the fix's motivation stays legible): the
// screen padding was symmetric `VelvetSpacing.lg` on both sides, making the
// chrome `24 + 24 + 42 + 4` = 94dp, so the lane area was `deviceWidth − 94`
// and [_kCardW] needed `deviceWidth >= 366`. The 360dp baseline cleared every
// term EXCEPT that one — 266dp of lane area, 6dp short of the fixed 272dp
// card — so the card's right edge was permanently clipped on first paint.
// `bookings_discovery_view.dart`'s `_kTimelineLeftInset` (12) is what closed
// that 6dp gap; it is applied to THIS branch only (`DeclaredTimeCards` has no
// ruler gutter and keeps the 24dp inset). Do NOT shrink [_kRulerWidth] to buy
// width — "23:00" stops fitting at 11sp and worse at large text scales.
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
// ADDENDUM 4 (2026-07-22) — VIEWPORT CULLING, AND THE MEMOISED LAYOUT MODEL
// ============================================================================
// mobile-perf HIGH: a `SingleChildScrollView` paints its WHOLE child — there
// is no `RenderViewport` culling — so at the server's `size: 100` ceiling the
// grid mounted ~200 layers and issued ~200 `MaskFilter.blur` RRect draws per
// day (every `MasterBookingCard` carries a `RepaintBoundary`, and its
// `PriceTag` → `NeumorphicInset` a second one plus a blurred `CustomPaint`),
// whether or not the card was anywhere near the viewport.
//
// THE FIX, AND WHY IT IS NOT A `ListView`: a lazy list cannot lay lanes out
// against a shared hour ruler (see the class doc's "do NOT generalise" note
// and R1/R3 above) — swapping one in would resurrect exactly the layout bugs
// this non-lazy grid exists to avoid. Instead [_LaneColumn] keeps emitting a
// child for EVERY booking, in the same order, at the same size — it just
// emits a bare `SizedBox(width: cardWidth, height: cardMinHeight)` in place of
// the `MasterBookingCard` when that card's planned box falls outside the
// culling window. The `Column`'s child count, child order and per-child
// geometry are all unchanged, so R3's "a Column physically cannot lay child
// N+1 above child N's bottom" guarantee and [assignLanes] are both untouched.
//
// WHY THE SUBSTITUTION IS SIZE-EXACT, AND THE TEXT-SCALE GATE: [SUPERSEDED BY
// ADDENDUM 6 — read that first.] This addendum culled on BOTH sides of the
// viewport, which made size fidelity load-bearing (a card culled ABOVE the
// visible band shifts everything below it, visible cards included). Since
// every height in this file is a textScaler-1.0 measurement (see ADDENDUM 2),
// that forced a gate: culling ran only when
// `MediaQuery.textScalerOf(context).scale(1) <= 1.0`. ADDENDUM 6 removed both
// the above-window culling and the gate.
//
// THE WINDOW, AND WHY IT DOES NOT REBUILD PER SCROLL PIXEL: the window ends at
// `offset + 1.5V` (V = viewport height) — half a viewport of slack below the
// visible band — recomputed only once the scroll offset has drifted `V / 4`
// from where the current window was anchored. That hysteresis is what keeps
// the scroll listener from calling `setState` every frame. See "ADDENDUM 9"
// for the arithmetic and for why the original `2V` / `V / 2` pair had to be
// tightened when the vertical scale came down. (ADDENDUM 6 stopped acting on
// the window's TOP edge; only the bottom edge exists.)
// Before the controller has any metrics the window falls back to the SCREEN
// height, which over-estimates the viewport and therefore only ever culls
// LESS — and ADDENDUM 6 replaces that seed with the real
// `viewportDimension` on the first post-frame callback.
//
// THE MEMOISED LAYOUT MODEL (mobile-perf MEDIUM): [assignLanes] (N `MapEntry`
// allocations + a sort) and the per-card Kyiv-midnight anchor used to be
// recomputed on every `build()` — including every one of the culling
// rebuilds above. Both are pure functions of `bookings` + `day`, so
// [_BookingsTimelineGridState] computes them once in `initState` and again
// only when `!identical(widget.bookings, old.bookings) || widget.day !=
// old.day`. The Kyiv midnight in particular was being reconstructed on EVERY
// [_minutesSinceDayStart] call (~3N per build, i.e. 300 timezone-table
// lookups at N=100) — it is now built once and passed in.
//
// ============================================================================
// ADDENDUM 5 (2026-07-22) — THE CULLING PLACEHOLDER'S SIZE INVARIANT, STATED
// PROPERLY (mobile-qa HIGH; ADDENDUM 4's own argument was wrong)
// ============================================================================
// ADDENDUM 4 justified its placeholder by claiming the real card "would have
// rendered at exactly `cardMinHeight`", because [_cardMinHeightFor]'s 56dp
// floor clears the card's 54dp natural height. That reasoning covers
// `MasterBookingCard`'s COMPACT layout ONLY.
//
// EVERY FIGURE IN THE NEXT PARAGRAPH IS AS-OF-2026-07-22 AND IS NOW STALE. It
// is preserved verbatim because the bug it describes IS the difference between
// two of those figures; substituting today's numbers would destroy the
// arithmetic without making the account any truer. For the geometry in force
// now see ADDENDUM 8's table and [MasterBookingCard.fullLayoutNaturalHeight] —
// the full body measures 118dp (117 until the card's ROW-1 GLYPH pass,
// 2026-07-24), and the threshold IS that same measured 118, no longer a tuned
// 112.
//
// AS IT STOOD THEN: the card switched to its FULL layout at
// `minHeight >= MasterBookingCard.fullLayoutMinHeight`, then a tuned 112dp,
// and the full layout's own natural content measured 117dp — while a
// 60-minute booking's floor was exactly 112dp. So the single most common
// booking length rendered a 117dp card behind a 112dp placeholder, and because
// [_LaneColumn]
// is a flex `Column`, every card below a culled one moved UP 5dp per culled
// card. Measured by mobile-qa: with two hour-long cards culled off the top,
// the next card's content offset went 250 -> 240. The hour gridlines are
// `Positioned` and never culled, so the cards slid out of registration with
// their own hour lines as the day scrolled — a visible correctness bug, worse
// than the paint cost culling exists to remove.
//
// THE INVARIANT, STATED AS AN INVARIANT (not as an argument about one
// layout) — AMENDED BY ADDENDUM 6, WHICH DEMOTED IT FROM LOAD-BEARING TO
// NICE-TO-HAVE. As ADDENDUM 5 originally shipped it read:
//
//   For every booking, at textScaler 1.0, the height of the widget
//   [_LaneColumn] emits is the SAME whether that booking is culled or not.
//   Substitution is a layout no-op; only paint work is removed.
//
// ADDENDUM 6 replaces it with a weaker claim that holds at EVERY text scale
// — "no VISIBLE content moves" — and keeps everything below purely as the
// mechanism that makes the scroll extent stable at scale 1.0. Read ADDENDUM 6
// for the invariant now in force.
//
// THE MECHANISM — direction (a): make the placeholder genuinely size-exact.
// [_LaneColumn] no longer sizes the placeholder from the FLOOR it hands the
// card ([_cardMinHeightFor]); it sizes it from
// `MasterBookingCard.occupiedHeightFor(floor)` — the box the card really
// occupies, `max(floor, the selected layout's natural content height)`. That
// is computable WITHOUT building the card because both inputs are pure
// functions of the floor: which layout is selected is `floor >=
// fullLayoutMinHeight`, and each layout's natural height is a
// content-independent exact number (`estimatedNaturalHeight` 56 /
// `fullLayoutNaturalHeight` 118 — every row in both bodies is a single
// ellipsised line, so lane width and string length move the ellipsis, never
// the height).
//
// Direction (b) — "only cull cards whose floor keeps them in the compact
// layout" — was rejected: it would surrender culling for exactly the
// bookings a real working day is made of (>=60 minutes), i.e. most of the
// paint cost, to avoid publishing a number the card already knows about
// itself and that `master_booking_card_test.dart` already pins.
//
// THE SAME NUMBER NOW DRIVES `plannedBottom`. It used to advance by the bare
// floor, so on a day of hour-long bookings the PLANNED position drifted 5dp
// per card from the RENDERED one — harmless for R3 (the `Column` guarantees
// no overlap however wrong the planning is) but not for culling, which tests
// `plannedTop` against a window in real screen coordinates. Planned and
// rendered positions now coincide.
//
// ENFORCED BY TESTS, NOT BY THIS COMMENT — the previous comment argued the
// invariant and was wrong, so:
//   * `bookings_timeline_grid_test.dart`'s "ADDENDUM 4 — viewport culling"
//     group asserts the placeholder is the exact box (width AND height) of
//     the card it replaced, and that no card's offset within the timeline
//     content changes as the view scrolls.
//   * `widgets/master_booking_card_layout_height_test.dart` closes the
//     derivation itself: it renders the REAL card at every floor this grid
//     can produce (15/30/45/60/61/90/120-minute durations, plus the exact
//     `fullLayoutMinHeight` boundary and one step either side of it) and
//     asserts `occupiedHeightFor` predicted the rendered height to the pixel.
//     A future density pass that moves either layout's natural height fails
//     there, with the measurement attached, instead of shipping the reflow.
//
// STILL TEXT-SCALE-1.0 ONLY. `fullLayoutNaturalHeight` is 124dp at 1.15 and
// 132dp at 1.3, so ADDENDUM 4's `_cullEnabled` gate is unchanged and remains
// load-bearing: above 1.0 nothing is culled at all.
// ^^^ TRUE WHEN WRITTEN, NO LONGER TRUE — see ADDENDUM 6. The gate is gone;
// `occupiedHeightFor` survives it, and is still exact at 1.0.
//
// ============================================================================
// ADDENDUM 6 (2026-07-22) — CULL BELOW ONLY, AT EVERY TEXT SCALE
// (mobile-perf MEDIUM: the gate disabled culling for a large share of real
// users)
// ============================================================================
// ADDENDUM 5 closed its reflow bug by making the placeholder size-exact, and
// bought that exactness with `_cullEnabled` — culling ran only at textScaler
// 1.0. `main.dart` clamps the ambient scale's CEILING to 1.3 but does not
// clamp it down, so Android's ordinary "Large" font setting (1.15) and the
// clamped maximum (1.3) both reach this widget intact. Every such user got
// `_cullEnabled == false` for the whole session, i.e. the original
// ~200-layer / ~100-blur grid that ADDENDUM 4 exists to remove. The HIGH was
// simply unfixed for them.
//
// THE FIX: STOP MAKING SIZE-EXACTNESS LOAD-BEARING. Culling now happens only
// BELOW the visible window, never above it. A card that is culled sits a
// quarter of a viewport BELOW the visible band at worst (the window's `+1.5V`
// edge minus the `V/4` re-anchor drift leaves >= V/4 of margin — see
// ADDENDUM 9 for the re-derivation at the tightened window), so if its
// placeholder height is imperfect, the only content it displaces is content
// that is ITSELF off-screen and further down.
// Nothing on screen moves, and the hour-ruler registration ADDENDUM 5 was
// about is preserved BY CONSTRUCTION rather than by a measurement table: the
// cards from the top of the day down to the visible band are never
// substituted at all, so their positions cannot drift however wrong a
// placeholder below them is.
//
// THE INVARIANT NOW IN FORCE (replacing ADDENDUM 5's):
//
//   At EVERY text scale, no card at or above the visible band is ever
//   replaced by a placeholder. Therefore the content offset of every card
//   from the day's start through the bottom of the viewport is independent of
//   the scroll offset, and no visible card can move because of culling.
//   Placeholder height fidelity affects only the SCROLL EXTENT and the
//   positions of other off-screen cards below the window.
//
// WHAT THIS COSTS: the tail of the day above the current scroll position is
// no longer culled, so scrolling to the bottom of a 100-card day does
// eventually materialise all 100. The win that remains is the one that
// matters most — first paint, every day switch, and every short scroll of a
// long day materialise only the head of the list plus three viewports of
// slack, instead of the whole day.
//
// WHY NOT THE OTHER DIRECTION (make `occupiedHeightFor` a function of the
// ambient `TextScaler` against a measured table — 124dp @1.15, 132dp @1.3 —
// and gate only above the largest measured entry): correct but brittle. It
// hard-codes per-scale measurements that any typography change silently
// invalidates, and the test that enforces it would have to sweep every scale
// the platform can hand us. This direction needs no measurement at all to be
// CORRECT.
//
// `occupiedHeightFor` IS KEPT, DELIBERATELY, THOUGH IT IS NO LONGER
// LOAD-BEARING: it is already written and already pinned to the pixel by
// `master_booking_card_layout_height_test.dart`, and it is what keeps
// `maxScrollExtent` exactly stable at textScaler 1.0 (planned == rendered, so
// the extent does not change at all as below-window placeholders resolve).
// Above 1.0 the extent does wobble slightly as the tail materialises — up to
// ~15dp per culled card at 1.3 — which is invisible on the target platform:
// the scroll OFFSET never changes, only the distance still available below
// it, and `MaterialScrollBehavior` builds no `Scrollbar` on Android/iOS, so
// there is no thumb to jump. Do not delete `occupiedHeightFor` to "simplify";
// deleting it would trade an exact extent at the dominant text scale for
// nothing.
//
// TWO SMALLER FIXES LANDED IN THE SAME PASS:
//
//  * THE VIEWPORT SEED (mobile-perf LOW). `ScrollPosition` does not notify
//    its listeners on `applyViewportDimension`, so the SCREEN-height seed
//    used to persist for an un-scrolled day's entire lifetime —
//    over-materialising ~3.6 viewports instead of 3, on exactly the frames
//    that matter. [_syncViewportFromMetrics] now reads the real
//    `position.viewportDimension` in a post-frame callback scheduled from
//    [didChangeDependencies], so first paint and every dependency change
//    (rotation included) converge on the true viewport.
//
//  * THE PER-CARD GEOMETRY (mobile-perf LOW). `startMinute` (a
//    [toBeauticaTime] timezone-table lookup plus a `difference`),
//    [_cardMinHeightFor], `occupiedHeightFor` and the running `plannedTop`
//    used to be recomputed inside `_LaneColumn.build`. Before culling, lane
//    columns rebuilt only on a data change; culling made them rebuild on
//    every window re-anchor (~every half viewport of scroll), so at N=100
//    that was ~100 timezone lookups per re-anchor ON A SCROLLING FRAME. All
//    of it is a pure function of `bookings + day`, so it now lives in
//    [_CardGeometry], computed once in [_recomputeLayoutModel] beside
//    [_laneGeometry]. The scroll path does one `>` comparison per card.
//
// ============================================================================
// ADDENDUM 7 (2026-07-24) — VERTICAL-SCALE PASS: CARDS LAND ON THEIR END LINE
// ============================================================================
// THE REPORT: a booking ending at 14:00 rendered its card bottom down to
// ~14:10 — the card overran its end-time line. ADDENDUM 2's proportional
// scale was correct in spirit but two numbers fought each other.
//
// THE ROOT CAUSE — A CONFLATED FLOOR:
//   `_cardMinHeightFor` floored the card at `hourHeight / 2` (one 30-minute
//   slot). At `_kHourH = 112` that slot was 56dp, which happened to equal the
//   card's real legible height (54dp + headroom), so the single number 56 was
//   doing DOUBLE DUTY: the gridline unit AND the card's minimum. The two only
//   coincidentally agreed. As long as the card floor tracked `hourHeight / 2`,
//   raising the scale to make cards land on their line would raise the floor
//   in lockstep and re-open the same overrun — the fix would silently fail.
//
// THE TWO-PART FIX:
//   1. Raise `_kHourH` 112 -> 168 (and the ruler's, in lockstep). At 168 a
//      booking's proportional height `duration/60 * 168` lands its bottom
//      exactly on its end-time line.
//   2. DECOUPLE the card floor from the slot: `_cardMinHeightFor` now floors
//      at `MasterBookingCard.estimatedNaturalHeight` (56dp, the compact card's
//      own natural legible height), NOT `hourHeight / 2` (now 84dp). This is
//      the load-bearing change — without it the floor would jump 56 -> 84 and
//      short cards would overrun to a 30-minute footprint again.
//
// THE RESULTING BEHAVIOUR — STATED HONESTLY:
//   * Bookings >= 20 minutes: card bottom lands EXACTLY on the end-time line.
//     A 20-minute band is `20/60 * 168 = 56dp`, precisely the legibility
//     floor — the break-even. 60-min = 168dp, 45-min = 126dp, all exact.
//   * Bookings < 20 minutes: floored at 56dp (a 20-minute band's worth). The
//     card is a hair TALLER than its wall-clock footprint — a residual
//     overrun that remains BY DESIGN. It is irreducible: a card cannot render
//     legibly below 56dp, and services can be as short as 1 minute, so no
//     finite vertical scale zeroes it. Fully UN-CLIPPED — the box grows, it
//     never crops (the R2 OverflowBox/ClipRect ban still holds).
//   * 45-minute cards cleared the full-layout threshold AT THIS SCALE
//     (126dp >= the then-117dp threshold), so they took the fuller divided
//     layout, inverting `MasterBookingCard`'s `_kFullLayoutMinHeight` doc's
//     older "45-min stays compact" reasoning. RE-INVERTED BY ADDENDUM 8, which
//     took `_kHourH` back down to 120: a 45-minute band is 90dp there, under
//     the threshold (118dp since the ROW-1 GLYPH pass), so 45-min is COMPACT
//     again today — ADDENDUM 8's geometry table is the live statement. Both
//     figures on this line are 168dp/hour-era and do not describe the grid as
//     it ships.
//   * A working day scrolls 1.5x longer than at 112 — accepted.
//
// ============================================================================
// ADDENDUM 8 (2026-07-24) — THE COSMETIC GAP WAS THE DRIFT BUG; SCALE DOWN TO
// 120; A THIRD CARD DENSITY
// ============================================================================
// THE REPORT: "the 12:00–14:00 card in the time grid looks like it starts
// about 12:10 and ends 14:10". Note the shape — the card keeps its correct
// 2-hour LENGTH and slides bodily DOWN. An offset, not a stretch, and the
// offset grows with each consecutive booking in the day. ADDENDUM 7 read the
// same class of report as an overrun and fixed a real conflated-floor bug, but
// it left the actual accumulator in place.
//
// THE ROOT CAUSE — AN ADDITIVE FLOOR ON A RELATIVE SPACER:
//   [_geometryForLane] computed
//     `spacer = max(_kMinInterCardGap, desiredTop - plannedBottom)`
//   where `_kMinInterCardGap` was `VelvetSpacing.sm` (8dp), documented as a
//   "purely cosmetic" minimum so stacked cards would not touch. But the
//   spacer is measured from `plannedBottom` — the PREVIOUS CARD'S bottom —
//   while `desiredTop` is absolute against the ruler origin. For a
//   back-to-back pair `desiredTop - plannedBottom == 0`, so the `max` returned
//   8 and added it to a running position that was never re-registered against
//   the ruler. Six consecutive hour-long bookings drifted 0, +8, +16, +24,
//   +32, +40dp; at 168dp/hour the last card read ~14 minutes late. A "cosmetic
//   minimum" measured in the wrong coordinate space is a clock error.
//
// THE FIX (part 1): the floor is 0 and the constant is deleted. Cards tile
// exactly, so card N's top lands on its own start gridline for every N in a
// back-to-back run, and the ONLY way a card can now sit below its line is if
// the card ABOVE it genuinely could not render inside its own band — a
// bounded, visible condition rather than an unconditional per-card tax.
// Separation between adjacent cards is carried by `MasterBookingCard`'s own
// 1.5dp / 0.38-alpha camel border (two adjacent borders read as a 3dp seam),
// which is where it belonged: a border is drawn INSIDE the card's box and
// therefore costs the ruler nothing.
//
// THE FIX (part 2) — `_kHourH` 168 -> 120. ADDENDUM 7 raised the scale to 168
// to buy exact end-line landing, and paid for it with a day that scrolls 1.5×
// longer. The thing forcing that scale up was the card's `56dp` legibility
// floor: at any lower scale a short booking's band fell under 56 and the card
// overran. 120 is the smallest ROUND scale that keeps a 60-minute band
// (`120dp`) at or above `MasterBookingCard.fullLayoutMinHeight` (`117dp` when
// this addendum was written; `118dp` since the card's ROW-1 GLYPH pass,
// 2026-07-24), so hour-long bookings — most of a real working day — keep the
// full layout. Do not go below 120 without moving that threshold.
// `_kFullLayoutMinHeight` is not tuned to `_kHourH` — it is a MEASURED natural
// height, so it moves whenever the full body's content does, and it has: the
// hour-long booking's clearance over it is now `2dp`, not `3`.
//
// THE FIX (part 3) — A MICRO CARD, so the floor can follow the scale down.
// Dropping to 120 puts a 15-minute band at `30dp`, well under the compact
// body's `56dp`, which would have re-inflated every short booking to a box
// nearly twice its band. `MasterBookingCard` gained a THIRD, single-row layout
// (service name · time range · status dot) whose natural height is `28dp`,
// selected when the floor cannot contain the compact body — see that widget's
// "THE MICRO LAYOUT" section. [_cardMinHeightFor]'s floor moved to it.
//
// (That natural was `29dp` until the ONE-TIME-STYLE pass, 2026-07-24, put the
// range on the full card's own type recipe — see `master_booking_card.dart`'s
// section of that name. It is a MEASURED number and moves whenever either of
// the micro row's two text tokens does; re-measure, never re-derive.)
//
// THE RESULTING GEOMETRY, at `_kHourH = 120`, spacer floor 0, card floor 28:
//
//   | duration | band  | card box | layout  | residual |
//   |----------|-------|----------|---------|----------|
//   |  60 min  | 120   | 120      | full    | 0 exact  |
//   |  45 min  |  90   |  90      | compact | 0 exact  |
//   |  30 min  |  60   |  60      | compact | 0 exact  |
//   |  15 min  |  30   |  30      | micro   | 0 exact  |
//   |  10 min  |  20   |  28      | micro   | +8       |
//
// The break-even is now 14.0 minutes (`28 / 120 * 60`), down from 20. Below
// it the residual is genuinely irreducible — a card cannot render below its
// own natural height and services can be one minute long — but it no longer
// touches any ordinary appointment length, and it never CLIPS (the R2
// OverflowBox/ClipRect ban still holds; the box grows).
//
// THE NO-DRIFT PROPERTY, STATED AS AN INVARIANT: for any run of consecutive
// bookings each of whose `occupiedHeight` equals its band (every row above
// except the last), `plannedBottom` after card N equals card N+1's
// `desiredTop`, so `spacer == 0` and `plannedTop == desiredTop` — by
// induction, card N's top is on its own start gridline for every N,
// independent of run length. Where a residual does occur, the NEXT card with
// any real idle time before it re-anchors exactly (`spacer` takes the positive
// branch, `plannedTop == desiredTop` again), so a residual cannot propagate
// past the first genuine gap in the lane.
//
// ============================================================================
// ADDENDUM 9 (2026-07-24) — THE CULLING WINDOW IS RE-TUNED FOR THE NEW SCALE,
// AND ZERO-HEIGHT SPACERS ARE NO LONGER EMITTED (mobile-perf MEDIUM + LOW)
// ============================================================================
// PART 1 — THE WINDOW DID NOT TRACK THE SCALE. ADDENDUM 4 sized the culling
// band in PIXELS (`offset + 2V`), which is scale-INVARIANT, but ADDENDUM 8 cut
// `_kHourH` 168 -> 120. The same 2V of pixels therefore packs 1.4x more of the
// day: at 168 a ~550dp viewport's window spanned ~6.5 wall-clock hours, at 120
// it spans ~9.1. For an ordinary 09:00–19:00 day that took first-paint culling
// from ~35% of the day down to ~10% — ADDENDUM 4's optimisation was very nearly
// inert on exactly the day shape it was written for. Whenever `_kHourH` moves,
// re-read this paragraph: a pixel window and a dp-per-hour scale are coupled.
//
// THE FIX: the band is now `offset + 1.5V` and the re-anchor threshold is
// `V / 4` (was `2V` / `V / 2`).
//
// THE SAFETY ARITHMETIC, RE-DERIVED AT THE NEW NUMBERS (there is only ONE edge
// to defend — ADDENDUM 6 deleted the top edge, so nothing at or above the
// visible band is ever culled and the top needs no margin at all):
//
//   Let `p` be the live scroll offset and `A = _windowOffset` the offset the
//   current window is anchored at. [_onScroll] re-anchors as soon as
//   `|p - A| >= V / 4`, so between re-anchors `p < A + V / 4`.
//   The visible band's BOTTOM edge is `p + V`, i.e. at worst
//   `A + V/4 + V = A + 1.25V`.
//   The culling band's bottom edge is `A + 1.5V`.
//   Margin = `1.5V - 1.25V` = **`0.25V`** — a quarter viewport of on-screen
//   content is still guaranteed real at the moment the window is most stale.
//   (Both quantities are shifted by the same
//   `TimelineHourRuler.labelCenteringNudge` when expressed in a lane's local
//   coordinates, so the nudge cancels out of the margin.)
//
// Scrolling UP is slack by construction: `p >= A - V/4` puts the visible bottom
// at `A + 0.75V`, further still from the band's edge.
//
// WHY THE MARGIN DOES NOT NEED TO ABSORB A FRAME OF FLING: [_onScroll] is a
// `ScrollPosition` listener, so a ballistic scroll fires it during the frame's
// transient-callback phase — the `setState` it schedules is flushed in the SAME
// frame's build phase, not the next one. The margin only has to cover the
// hysteresis threshold itself, which is exactly what the derivation above does.
//
// AND WHY A SHORTER PLACEHOLDER STILL CANNOT PULL AN OFF-SCREEN CARD INTO VIEW:
// `occupiedHeightFor` is exact at textScaler 1.0 and an UNDER-estimate above it
// (`max(floor, natural)` and natural only grows with scale), so the rendered
// box is always `>=` the planned one. Culled content can only drift DOWN, away
// from the visible band — never up into it. This is ADDENDUM 6's argument,
// unchanged by the tightening; only the size of the cushion moved.
//
// PART 2 — NO MORE GUARANTEED NO-OP SPACERS. [_LaneColumn] used to emit
// `SizedBox(height: geo.spacer)` unconditionally. With ADDENDUM 8's spacer
// floor at 0, `spacer == 0` for EVERY card after the first in a back-to-back
// run — which is the normal shape of a working day — so a 100-booking day
// mounted ~100 `Element`s + `RenderBox`es that build, lay out and paint
// nothing. It is now emitted only when positive.
//
// THIS DOES NOT WEAKEN R3, AND IT DOES NOT WEAKEN CULLING'S "SAME SHAPE EITHER
// WAY" ARGUMENT. R3's guarantee is that a `Column` cannot lay child N+1 above
// child N's rendered bottom — dropping a zero-height box changes neither the
// relative ORDER of the cards nor any rendered height (a zero-height child
// contributes nothing to a `Column`'s main axis). And [_CardGeometry] is
// memoised from `bookings + day` alone, so which spacers are positive is
// identical whether a card is culled or not: the culled and un-culled trees
// still have the same child count, the same child order and the same per-child
// geometry as EACH OTHER, which is all ADDENDUM 4 ever relied on.
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
import 'schedule_timeline_window.dart';
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
/// every card's client-name-bearing `Semantics` node (`master_booking_card
/// .dart`) exists in the accessibility tree at once for the whole materialised
/// part of the day, not just the on-screen part. (ADDENDUM 6 narrowed this
/// from the literal "EVERY card, always" it said when written: a card culled
/// below the window emits a bare `SizedBox` with no `Semantics` node at all,
/// so a day's tail is not exposed until it is scrolled towards. That is an
/// incidental narrowing, NOT a mitigation — culling is a paint optimisation
/// with no security contract, everything from the day's start down to the
/// window is still exposed simultaneously, and a hostile app that scrolls the
/// view still sweeps the lot. The trade-off below is accepted on exactly the
/// same terms as before.) The retired `ListView.builder` virtualized, so
/// only visible cards were ever exposed. The hosting screen's
/// `ScreenProtectionManager` acquire is no defence here: since the 2026-08-20
/// product decision it only blanks the app-switcher snapshot and never blocked
/// the Android Accessibility API in any case (it no longer blocks screenshots
/// or screen recording either — see the header of
/// `lib/core/security/screen_protection.dart`). So a hostile
/// accessibility-service app can enumerate a full day's client names in one
/// sweep instead of only what is visible on screen. This is an ACCEPTED
/// trade-off, not an oversight: `size: 100` already bounds how much PII a
/// single day can ever expose this way (see `bookings_day_notifier.dart`),
/// and a lazily-built list cannot lay out lanes against a shared hour ruler —
/// reintroducing one here would resurrect the R1-adjacent layout bugs this
/// non-lazy grid exists to avoid. Do NOT restructure this widget to "fix"
/// either dimension of the trade-off.
class BookingsTimelineGrid extends StatefulWidget {
  const BookingsTimelineGrid({
    required this.bookings,
    required this.day,
    required this.onBookingTap,
    this.scheduleFirstMinute,
    this.scheduleWindowEndMinute,
    super.key,
  }) : assert(
         (scheduleFirstMinute == null) == (scheduleWindowEndMinute == null),
         'scheduleFirstMinute and scheduleWindowEndMinute must be set '
         'together, or not at all.',
       );

  /// One Kyiv day's bookings, in SERVER order (`startsAt` ASC) — rendered
  /// directly; never mutated or re-sorted here (see [assignLanes]).
  ///
  /// mobile-security HIGH fix (this session): when [scheduleFirstMinute]/
  /// [scheduleWindowEndMinute] are set, this list MUST ALREADY be filtered to
  /// [ScheduleTimelineWindow.includesStart] — this widget no longer filters
  /// it itself. The caller (`BookingsDiscoveryView`'s `_Loaded`) calls the
  /// public [bookingsInsideScheduleWindow] once and uses its result for BOTH
  /// the header count AND this widget's [bookings], so the two can never
  /// disagree — see that function's doc. This grid trusts what it is handed;
  /// it does not re-decide "is this booking in the window" a second time.
  final List<Booking> bookings;

  /// The selected Kyiv calendar day, date-only — the anchor
  /// [_minutesSinceDayStart] measures every card position against.
  final DateTime day;

  /// Fires with the tapped booking. No `Navigator`/`context.push` in this
  /// leaf widget — the caller (Phase 7.11) owns navigation.
  final ValueChanged<Booking> onBookingTap;

  /// ═══════════════════════════════════════════════════════════════════════
  /// SCHEDULE-DERIVED WINDOW (master «Мої записи» working-hours bounds)
  /// ═══════════════════════════════════════════════════════════════════════
  /// Both `null` (the default, and every pre-existing call site) keeps the
  /// ORIGINAL booking-derived window: grid top/bottom come from
  /// [bookings] alone, exactly as before this feature. Set BOTH together (see
  /// the constructor assert) to bound the grid by the master's WORKING HOURS
  /// for [day] instead — `BookingsDiscoveryView`'s `useScheduleWindow: true`
  /// path (the master's own screen only) computes them from
  /// `ScheduleTimelineWindow` (`schedule_timeline_window.dart`).
  ///
  /// When set:
  ///   * [_firstMinute] (grid top) becomes [scheduleFirstMinute] directly —
  ///     never lowered for an early booking (see the next bullet).
  ///   * [bookings] is assumed ALREADY filtered to this window (see that
  ///     field's doc) — this widget performs no filtering of its own.
  ///   * The grid's BOTTOM is `max(scheduleWindowEndMinute, the real end of
  ///     the latest booking in [bookings])` — the R1 arithmetic already
  ///     computes that second term (`lastMinuteCandidate`), so a booking that
  ///     starts inside the window but runs past [scheduleWindowEndMinute]
  ///     (e.g. 18:30 + 60min against hours ending 19:00) still renders in
  ///     full, never clipped. This is the ONE widening this feature performs;
  ///     nothing else about an out-of-window booking widens the grid — and
  ///     nothing here can even SEE an out-of-window booking any more, since
  ///     the caller never hands one in.
  ///
  /// Minutes since [day]'s Kyiv midnight — the earliest working-hours start.
  final int? scheduleFirstMinute;

  /// INTERVAL day: the latest interval END. EXPLICIT_TIMES day: the latest
  /// DECLARED START time itself — there is no "end" in that mode. See
  /// `ScheduleTimelineWindow.windowEndMinute`'s doc, which this mirrors. Used
  /// here ONLY to widen the grid's bottom (see [scheduleFirstMinute]'s doc);
  /// the inclusive-vs-exclusive boundary distinction that number's doc also
  /// describes matters for FILTERING only, which is entirely the caller's
  /// job now (see [bookings]'s doc) — this widget has no boundary rule of its
  /// own left to apply.
  final int? scheduleWindowEndMinute;

  /// One hour of vertical space — MUST match
  /// `TimelineHourRuler._kHourH` so the ruler and the lane hairlines line up.
  ///
  /// See this file's "ADDENDUM 2" for the original derivation and "ADDENDUM 8"
  /// for the current value. History: `72` → `112` → `168` → **`120`**. The
  /// `168` step bought exact end-line landing by making the whole day 1.5×
  /// longer to scroll; `120` keeps the exact landing and gives the scroll
  /// length back, because the MICRO card layout
  /// ([MasterBookingCard.microLayoutNaturalHeight], `28dp`) removed the
  /// `56dp` legibility floor that was forcing the scale up.
  ///
  /// `120` is the SMALLEST round scale that still works: a 60-minute band is
  /// `120dp`, which must stay `>= MasterBookingCard.fullLayoutMinHeight`
  /// (`118dp` since that card's ROW-1 GLYPH pass, 2026-07-24 — `117` before
  /// it) or hour-long bookings — the bulk of a real working day — would drop
  /// out of the full layout. The margin is now `2dp`. Do NOT lower this
  /// further, and re-check it whenever the full body's content grows, since
  /// that threshold is a measured height rather than a number tuned to fit
  /// here.
  static const double _kHourH = 120;

  /// One 30-minute slot — the grid's minimum unit (ADDENDUM 2). Half of
  /// [_kHourH] by construction (now `60dp`). Drives the half-hour GRIDLINE
  /// spacing only. Since the vertical-scale pass it does NOT govern the card
  /// floor — that is [MasterBookingCard.microLayoutNaturalHeight] (see
  /// `_cardMinHeightFor`), and keeping the two decoupled is what lets short
  /// bookings land on their end-time line. Read off this constant for
  /// gridlines, never a re-derived literal.
  static const double _kSlotH = _kHourH / 2;

  /// One lane's card width CEILING — the design's fixed value, but never
  /// used directly as a rendered width. See this file's "ADDENDUM 3": [build]
  /// clamps it down to `constraints.maxWidth` (per render, for every lane)
  /// before it reaches [contentWidth] or any [_LaneColumn.cardWidth], so a
  /// narrow device never clips a card at the viewport's right edge.
  static const double _kCardW = 272;

  /// Minutes in one calendar day — the ceiling on where this grid's TOP may
  /// sit. See [_kMaxEndMinute].
  static const int _kDayMinutes = 24 * 60;

  /// The hard ceiling on this grid's BOTTOM, in minutes since [day]'s Kyiv
  /// midnight: two full days. Generous — a real day's latest booking end is
  /// `< 1440 + its own duration` — but FINITE, which is the entire point.
  ///
  /// WHY A CLAMP EXISTS AT ALL (2026-08-17, unbounded-hang fix)
  /// ----------------------------------------------------------
  /// [_recomputeLayoutModel] derives the grid's extent from [bookings] with no
  /// bound of its own, and `build` turns that extent into one
  /// `TimelineHourRuler` row per hour — a SYNCHRONOUS, allocating loop. So a
  /// single booking outside [day] does not merely render in the wrong place:
  /// it sets `totalHours` to the distance between it and the rest of the day.
  /// A row six years off the selected day produced ~56 500 rows, which starves
  /// the Dart event loop outright — and once the loop is starved NOTHING
  /// timer-based can rescue it (`Future.timeout`, `pumpAndSettle`'s deadline,
  /// a test `Timeout`, a watchdog: all timers, none of which tick). The build
  /// never returns.
  ///
  /// [bookingsInsideScheduleWindow] is NOT that bound. It is real, and it does
  /// drop such a row — but only on `BookingsDiscoveryView`'s `data:` branch,
  /// for an INTERVAL day, once a working-hours window has actually resolved.
  /// The `loading:` and `error:` branches (`bookings_discovery_view.dart`) both
  /// fall back to `window: null`, which hands this widget `state.items`
  /// UNFILTERED with `scheduleFirstMinute == null` — the legacy
  /// booking-derived path. "Schedule still loading" is the state of every cold
  /// open of the master's «Мої записи», and "schedule errored" is permanent.
  /// So the filter runs strictly AFTER, and sometimes never; it cannot be what
  /// makes the extent safe.
  ///
  /// Hence this clamp, applied to the extent itself rather than to the card
  /// set: `totalHours` is bounded BY CONSTRUCTION, whatever the server, a
  /// timezone edge, or a stale cache hands in. It deliberately does NOT filter
  /// [bookings] — that would re-introduce the second, independently-maintained
  /// filtering computation this widget's class doc forbids (the header count
  /// and the rendered cards must keep coming from one list). An out-of-window
  /// card simply lands outside the clamped `Stack` and is not painted.
  static const int _kMaxEndMinute = 2 * _kDayMinutes;

  // `_kMinInterCardGap` IS GONE — IT WAS THE DRIFT BUG (2026-07-24)
  // ----------------------------------------------------------------------
  // It was an 8dp (`VelvetSpacing.sm`) FLOOR on `_geometryForLane`'s spacer,
  // documented as a "purely cosmetic" minimum so stacked cards would not
  // visually touch. It was not cosmetic. The spacer is measured from the
  // PREVIOUS CARD'S PLANNED BOTTOM, not from the ruler origin, so for
  // back-to-back bookings (`desiredTop - plannedBottom == 0`) the floor
  // returned 8 and ADDED it to a running absolute position that never
  // re-registered against the ruler. A day of six consecutive hour-long
  // bookings drifted 0, +8, +16, +24, +32, +40dp — at the then-`168dp/hour`
  // scale, the last card read ~14 minutes late. That is exactly the reported
  // symptom: "12:00–14:00 looks like it starts about 12:10 and ends 14:10",
  // an OFFSET (correct length, wrong position) that grows down the day.
  //
  // The spacer is now `max(0, desiredTop - plannedBottom)` — cards tile
  // exactly and EVERY card re-registers on its true wall-clock position, so
  // the drift cannot accumulate. Visual separation is carried by the card's
  // own 1.5dp / 0.38-alpha camel border (`MasterBookingCard`'s
  // `_kBorderWidth`/`_kBorderAlpha`), so two adjacent cards still read as a
  // 3dp seam rather than one merged block. Do NOT reintroduce a non-zero
  // floor here: any positive constant is unconditionally additive against an
  // absolute ruler.

  /// The half-hour gridline's colour — the same hue as the hour gridline
  /// ([BrandColors.faint]) at a lighter alpha, so the half-hour rhythm reads
  /// as secondary structure rather than competing with the hour lines (see
  /// "ADDENDUM 2"). Hoisted per the file's colour-allocation convention.
  static final Color _halfHourLineColor = BrandColors.faint.withValues(
    alpha: 0.4,
  );

  @override
  State<BookingsTimelineGrid> createState() => _BookingsTimelineGridState();
}

/// How much slack, as a fraction of the viewport height, the culling band
/// keeps BELOW the visible band — so the band ends at
/// `scrollOffset + (1 + this) * viewport`.
///
/// ADDENDUM 9 cut it from `1.0` to `0.5`: the window is a PIXEL quantity, so
/// when [BookingsTimelineGrid._kHourH] dropped 168 -> 120 the same slack
/// started buying 1.4x more of the DAY and culling all but stopped engaging on
/// an ordinary 09:00–19:00 shift. Read ADDENDUM 9 before changing either this
/// or `_kHourH` — they are coupled.
const double _kWindowSlack = 0.5;

/// How far, as a fraction of the viewport height, the scroll offset may drift
/// from the window's anchor before the window is re-anchored.
///
/// MUST stay comfortably below [_kWindowSlack]: the guaranteed on-screen margin
/// is exactly `(_kWindowSlack - this) * viewport`, and it must be positive or a
/// card that is genuinely visible gets replaced by a blank box. At `0.5 / 0.25`
/// the margin is a quarter viewport (ADDENDUM 9).
const double _kWindowReanchorFraction = 0.25;

class _BookingsTimelineGridState extends State<BookingsTimelineGrid> {
  /// The grid's OWN vertical scroll controller — the culling window's only
  /// source of truth (see the file header's "ADDENDUM 4"). Owned here rather
  /// than injected: nothing outside this widget drives or reads this scroll.
  final ScrollController _scrollController = ScrollController();

  // ── The memoised layout model (ADDENDUM 4, extended by ADDENDUM 6) ────
  // Pure functions of `widget.bookings` + `widget.day` (+ the schedule-window
  // params, see the class doc); recomputed ONLY in [_recomputeLayoutModel],
  // never in [build].
  late List<List<_CardGeometry>> _laneGeometry;
  late int _lanesCount;
  late int _firstMinute;
  late int _lastMinute;

  /// Always `widget.bookings` (this widget no longer filters — see that
  /// field's doc) — held here, alongside [_laneGeometry] and friends, purely
  /// so [build] reads the exact list [_CardGeometry.bookingIndex] indexes
  /// into without reaching back through `widget` for it.
  late List<Booking> _visibleBookings;

  // ── The culling window (ADDENDUM 4) ───────────────────────────────────

  /// The scroll offset the current window is anchored at. Starts at 0, which
  /// is exact: [_scrollController] is created here, so the grid always mounts
  /// unscrolled.
  double _windowOffset = 0;

  /// The viewport height the current window was sized from. Seeded from the
  /// SCREEN height in [didChangeDependencies] — an over-estimate, which can
  /// only ever cull less — and replaced with the scroll position's real
  /// `viewportDimension` by [_syncViewportFromMetrics] on the first
  /// post-frame callback (mobile-perf LOW; see the file header's
  /// "ADDENDUM 6").
  double _windowViewport = 0;

  /// Guards [_syncViewportFromMetrics] against queueing more than one
  /// post-frame callback at a time.
  bool _viewportSyncScheduled = false;

  /// The culling band's BOTTOM edge, in the lane `Column`s' own local
  /// coordinates — the ONLY scroll-derived value the tree consumes, and it
  /// flows to exactly one place: each [_LaneColumn]'s `visibleBottom`.
  ///
  /// `_windowOffset` is measured against the scroll view's child, whose origin
  /// sits [TimelineHourRuler.labelCenteringNudge] above each lane's own origin
  /// (the `Padding` in [build]), hence the shift in [_cullingWindowBottom].
  ///
  /// Holding this in a [ValueNotifier] rather than mutating it via `setState`
  /// confines a scroll re-anchor's rebuild to the lane `Row` (wrapped in the
  /// [ValueListenableBuilder] in [build]). The ruler and the gridlines depend
  /// only on the day's hour extent — never on scroll — so they no longer
  /// rebuild when the window moves (mobile-perf LOW). Recomputed via
  /// [_cullingWindowBottom] wherever [_windowOffset] / [_windowViewport]
  /// change.
  final ValueNotifier<double> _visibleBottom = ValueNotifier<double>(0);

  /// The current culling-band bottom edge from the window anchor + viewport.
  ///
  /// ADDENDUM 6 — there is deliberately no matching `visibleTop`: cards above
  /// the window are never culled, which is what lets culling run at every text
  /// scale without the placeholder having to be size-exact. Do not reintroduce
  /// a top edge without re-reading ADDENDUM 5 and 6.
  ///
  /// ADDENDUM 9 — the slack is `0.5V` (the band ends at `offset + 1.5V`), not
  /// ADDENDUM 4's `1V`. See that addendum for the re-derived margin.
  double get _cullingWindowBottom =>
      _windowOffset +
      (1 + _kWindowSlack) * _windowViewport -
      TimelineHourRuler.labelCenteringNudge;

  @override
  void initState() {
    super.initState();
    _recomputeLayoutModel();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_windowViewport <= 0) {
      _windowViewport = MediaQuery.sizeOf(context).height;
      _visibleBottom.value = _cullingWindowBottom;
    }
    // `ScrollPosition` never notifies on `applyViewportDimension`, so the
    // seed above would otherwise persist for an un-scrolled day's whole
    // lifetime. Re-read it after the frame that just laid the viewport out —
    // and again after any dependency change (a rotation, a
    // `MediaQuery` insets change), since those resize it silently too.
    _scheduleViewportSync();
  }

  @override
  void didUpdateWidget(covariant BookingsTimelineGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    // `identical`, not `==`: `List` has reference equality anyway, and the
    // notifier hands out a fresh list on every fetch — so this is exactly
    // "did the data actually change", with no O(N) comparison. The schedule
    // window params are also compared: a master editing today's working
    // hours while this screen is open changes them WITHOUT necessarily
    // changing `widget.bookings`'s identity, and missing that would leave
    // the grid showing yesterday's window.
    if (!identical(widget.bookings, oldWidget.bookings) ||
        widget.day != oldWidget.day ||
        widget.scheduleFirstMinute != oldWidget.scheduleFirstMinute ||
        widget.scheduleWindowEndMinute != oldWidget.scheduleWindowEndMinute) {
      _recomputeLayoutModel();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _visibleBottom.dispose();
    super.dispose();
  }

  /// Reads the scroll view's REAL viewport height once the frame that laid it
  /// out has completed, replacing [didChangeDependencies]'s screen-height
  /// seed. See the file header's "ADDENDUM 6".
  void _scheduleViewportSync() {
    if (_viewportSyncScheduled) return;
    _viewportSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewportSyncScheduled = false;
      if (!mounted) return;
      _syncViewportFromMetrics();
    });
  }

  void _syncViewportFromMetrics() {
    if (!_scrollController.hasClients) return;
    final ScrollPosition position = _scrollController.position;
    if (!position.hasViewportDimension) return;
    final double viewport = position.viewportDimension;
    if (viewport <= 0 || viewport == _windowViewport) return;
    // Only the culling band moves — publish it to the lane `Row` alone via the
    // notifier rather than a `setState` that would also rebuild the ruler and
    // the gridlines (mobile-perf LOW).
    _windowViewport = viewport;
    if (position.hasPixels) _windowOffset = position.pixels;
    _visibleBottom.value = _cullingWindowBottom;
  }

  /// Rebuilds everything derived from `bookings` + `day` — lane assignment,
  /// the Kyiv-midnight anchor, the grid's minute extent, and (ADDENDUM 6)
  /// every card's per-lane geometry.
  void _recomputeLayoutModel() {
    final DateTime day = widget.day;

    // Hoisted out of [_minutesSinceDayStart] (mobile-perf MEDIUM): that
    // function used to construct this `TZDateTime` on every call, ~3N times
    // per build. It cannot change unless [BookingsTimelineGrid.day] does.
    final tz.TZDateTime midnight = tz.TZDateTime(
      beauticaZone,
      day.year,
      day.month,
      day.day,
    );

    // mobile-security HIGH fix (this session): `widget.bookings` is no
    // longer filtered here. When a schedule window is set, the caller
    // (`BookingsDiscoveryView`'s `_Loaded`) has ALREADY filtered it via
    // [bookingsInsideScheduleWindow] — see [BookingsTimelineGrid.bookings]'s
    // doc for why re-filtering the same list a second time, even with an
    // identical predicate, is exactly the duplicated-computation shape that
    // let the header count and the rendered cards read different numbers.
    // `bookings`/`startMinutes` below are simply `widget.bookings` and its
    // per-card Kyiv-minute offsets — unfiltered, always — which is also
    // byte-for-byte the legacy (`scheduleFirstMinute == null`) behaviour.
    final List<Booking> bookings = widget.bookings;
    final List<int> startMinutes = <int>[
      for (final Booking b in bookings)
        _minutesSinceDayStart(b.startAt, midnight),
    ];
    _visibleBookings = bookings;

    final List<int> lanes = assignLanes(bookings);
    _lanesCount = laneCount(lanes);

    final int? schedFirst = widget.scheduleFirstMinute;
    final int? schedWindowEnd = widget.scheduleWindowEndMinute;

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
    // Grid top: the schedule's working-hours start when set, else (legacy)
    // the earliest booking's start. `bookings` is already the caller's
    // in-window set whenever `schedFirst` is set (see [bookings]'s doc), so
    // there is no separate "surviving" subset to derive here any more.
    // `.clamp` to `[0, _kDayMinutes]` — the grid's top can never precede
    // [day]'s Kyiv midnight nor start after the day is over, however far off
    // the day an incoming booking sits. See [_kMaxEndMinute]'s doc for why
    // this bound lives here and not in the (later, conditional) caller-side
    // filter.
    _firstMinute =
        (schedFirst ??
                (startMinutes.isEmpty ? 0 : startMinutes.reduce(math.min)))
            .clamp(0, BookingsTimelineGrid._kDayMinutes);
    final int lastMinuteCandidate = bookings.isEmpty
        ? _firstMinute + 60
        : <int>[
            for (int i = 0; i < bookings.length; i++)
              startMinutes[i] + bookings[i].durationMinutes,
          ].reduce(math.max);
    // Grid bottom base: the schedule's working-hours end, WIDENED (never
    // narrowed) to cover any booking that runs past it — see the class doc's
    // "the ONE widening this feature performs". Legacy path (schedWindowEnd
    // null) is unaffected: `lastMinuteCandidate` alone, same as before this
    // feature.
    final int lastMinuteBase = schedWindowEnd == null
        ? lastMinuteCandidate
        : math.max(schedWindowEnd, lastMinuteCandidate);
    // Floor: the grid is never shorter than one hour, whatever the data says.
    // CEILING: nor longer than [_kMaxEndMinute] — so `lastHour - firstHour`
    // (and therefore the ruler's per-hour row count, `build`'s
    // `gridStackHeight`, and every gridline `Positioned`) is finite BY
    // CONSTRUCTION rather than by the incoming data being well-behaved. The
    // floor is applied last so it always wins: a `_firstMinute` sitting at the
    // very top of its own clamp still gets its one hour of ruler.
    _lastMinute = math.max(
      math.min(lastMinuteBase, BookingsTimelineGrid._kMaxEndMinute),
      _firstMinute + 60,
    );

    // R3 FIX — group each booking's ORIGINAL index by its assigned lane.
    // [bookings] is already ascending by `startAt` (the class doc's
    // invariant), and this grouping preserves relative order, so each lane's
    // list below is ascending by `startAt` too without a second sort —
    // exactly the order [_LaneColumn] needs to lay its cards out
    // top-to-bottom. See the file header's "R3" section.
    final List<List<int>> indicesByLane = List<List<int>>.generate(
      _lanesCount,
      (_) => <int>[],
    );
    for (int i = 0; i < bookings.length; i++) {
      indicesByLane[lanes[i]].add(i);
    }

    // ADDENDUM 6 — the per-card geometry, memoised alongside the lanes. Every
    // term below is a pure function of `bookings` + `day`, so none of it
    // belongs on the culling rebuild path.
    const double hourHeight = BookingsTimelineGrid._kHourH;
    // ADDENDUM 7 (part 2) — the card layer's vertical ORIGIN is the FLOORED
    // hour (`firstHour * 60`), NOT the raw `_firstMinute`. The gridlines and
    // the ruler both anchor to `firstHour = _firstMinute ~/ 60` (see [build]
    // and `TimelineHourRuler`), so anchoring cards to `_firstMinute` instead
    // slid the whole card layer up by `(_firstMinute mod 60)` minutes whenever
    // the day's first booking started off-hour (e.g. 13:40 → a 40-minute,
    // 112dp shift), and cards no longer landed on their end-time gridlines.
    // Sharing this ONE floored origin makes a card's top/bottom offsets
    // coincide with the gridline offsets for its start/end times.
    final int originMinute = (_firstMinute ~/ 60) * 60;
    // The clamped extent in px, in the SAME whole-hour space `build` derives
    // `gridStackHeight` from, so a card can never be planned outside the ruler
    // the clamp just bounded. For every in-window card this is inert: its
    // `desiredTop` is `>= 0` (the origin is the floored earliest start) and
    // `<= maxTopPx` (`lastHour` already covers the latest END). It bites only
    // on a booking that does not belong to [day] at all — see
    // [_kMaxEndMinute]'s doc, and [_geometryForLane]'s `maxTopPx` parameter for
    // why such a card is repositioned rather than dropped.
    final double maxTopPx =
        ((_lastMinute / 60.0).ceil() - _firstMinute ~/ 60) * hourHeight;
    _laneGeometry = <List<_CardGeometry>>[
      for (final List<int> indices in indicesByLane)
        _geometryForLane(
          bookings: bookings,
          indices: indices,
          startMinutes: startMinutes,
          originMinute: originMinute,
          hourHeight: hourHeight,
          maxTopPx: maxTopPx,
        ),
    ];
  }

  /// Re-anchors the culling window when the scroll offset has drifted a
  /// QUARTER of a viewport from where it was last anchored — see the file
  /// header's "ADDENDUM 9" for why a `V / 4` drift against `0.5V` of slack
  /// leaves `0.25V` of margin, and why this must NOT re-anchor per frame.
  ///
  /// This threshold and [_kWindowSlack] are one pair: tightening the window
  /// without tightening this too would eat the margin. Change both or neither.
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final ScrollPosition position = _scrollController.position;
    if (!position.hasPixels || !position.hasViewportDimension) return;
    final double viewport = position.viewportDimension;
    if (viewport <= 0) return;
    if (viewport == _windowViewport &&
        (position.pixels - _windowOffset).abs() <
            viewport * _kWindowReanchorFraction) {
      return;
    }
    // Re-anchor the window. The offset/viewport this depends on feed ONLY the
    // culling band, so the re-anchor publishes the new [_cullingWindowBottom]
    // to the lane `Row` through the notifier — NOT via `setState`, which would
    // needlessly rebuild the ruler + every gridline `Positioned` too. The
    // re-anchor QUANTIZATION (the `_kWindowReanchorFraction` threshold above +
    // the `_kWindowSlack` band) is unchanged; only the delivery mechanism is.
    _windowOffset = position.pixels;
    _windowViewport = viewport;
    _visibleBottom.value = _cullingWindowBottom;
  }

  @override
  Widget build(BuildContext context) {
    // [_visibleBookings], NOT `widget.bookings` — [_laneGeometry]'s
    // [_CardGeometry.bookingIndex] indexes into the FILTERED list whenever a
    // schedule window is set (see that field's doc); reading `widget.bookings`
    // here directly would index a booking dropped by the filter.
    final List<Booking> bookings = _visibleBookings;
    final int lanesCount = _lanesCount;
    final int firstMinute = _firstMinute;
    final int firstHour = firstMinute ~/ 60;
    final int lastHour = (_lastMinute / 60.0).ceil();

    // BUG FIX — the gridline/card `Stack`'s own height, explicit and derived
    // from `firstHour`/`lastHour` exactly like `TimelineHourRuler` computes
    // its total extent, so the two stay pixel-registered regardless of
    // `lanesCount`. Previously the `Stack` sized itself from its one
    // non-`Positioned` child (the lane `Row`, see below), which collapses to
    // `Size.zero` whenever `lanesCount == 0` — a working day with genuinely
    // no (visible) bookings. The `Positioned` gridlines were laid out
    // correctly in that case but had no `Stack` extent to paint inside, so
    // the whole grid (ruler numbers survived — see `TimelineHourRuler`,
    // which never depended on lane content — but the gridlines and card area
    // vanished). This formula is always an upper bound on the tallest card's
    // real bottom: `_lastMinute` already widens to cover every booking AND
    // the schedule window (R1 fix above), and `lastHour = ceil(_lastMinute /
    // 60)` rounds that up to the same hour granularity `_kHourH` uses — so
    // switching from "guessed from content" to "derived from the same clock
    // math the ruler uses" never clips an existing card, it only makes the
    // empty-lane case render. The trailing `+ 1` covers the last gridline's
    // own 1dp height, which sits exactly at `totalHours * _kHourH`.
    final double gridStackHeight =
        (lastHour - firstHour) * BookingsTimelineGrid._kHourH + 1;

    // The scroll-derived culling band ([_visibleBottom]) is consumed ONLY
    // inside the [ValueListenableBuilder] wrapping the lane `Row` below, so a
    // scroll re-anchor rebuilds that `Row` alone — never this `build`, the
    // ruler, or the gridlines. See [_visibleBottom] / [_cullingWindowBottom].

    return SingleChildScrollView(
      controller: _scrollController,
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
                  BookingsTimelineGrid._kCardW,
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
                  child: ConstrainedBox(
                    // `minHeight:` — see [gridStackHeight]'s doc above (BUG
                    // FIX): a FLOOR, not a fixed size. `width` stays tight
                    // (min == max == `contentW`, same as the `SizedBox` this
                    // replaced); `height` stays LOOSE above the floor
                    // (`maxHeight` defaults to infinity), so the `Stack`
                    // below can still grow taller than [gridStackHeight] when
                    // real card content needs more room (ADDENDUM 4's
                    // textScaler-inflated cards do exactly this — a TIGHT
                    // height here clipped them, "RenderFlex overflowed").
                    // What the floor fixes is the OTHER end: on a zero-lane
                    // day the `Row` of lane `Column`s (the `Stack`'s only
                    // non-`Positioned` child) sizes to `Size.zero`, and
                    // without a floor the `Stack` collapsed to zero height
                    // right along with it — the `Positioned` gridlines were
                    // laid out correctly but had no `Stack` extent to paint
                    // inside, so the whole grid vanished. The floor is
                    // derived from the same firstHour/lastHour clock math
                    // `TimelineHourRuler` already uses for its own extent, so
                    // the two stay in lockstep. The R3 fix's original goal (a
                    // real, non-guessed extent, not a magic constant) still
                    // holds either way — content-driven when there is
                    // content, clock-derived when there is none.
                    constraints: BoxConstraints(
                      minWidth: contentW,
                      maxWidth: contentW,
                      minHeight:
                          gridStackHeight +
                          TimelineHourRuler.labelCenteringNudge,
                    ),
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
                              top:
                                  (half - firstHour * 2) *
                                  BookingsTimelineGrid._kSlotH,
                              left: 0,
                              right: 0,
                              height: 1,
                              child: ColoredBox(
                                color: half.isEven
                                    ? BrandColors.faint
                                    : BookingsTimelineGrid._halfHourLineColor,
                              ),
                            ),
                          // The lane `Row` is the sole non-`Positioned` child
                          // of the `Stack` (it drives the `Stack`'s size — see
                          // the R3 note above). Wrapping it in a
                          // [ValueListenableBuilder] on [_visibleBottom] keeps
                          // that role (the builder is layout-transparent,
                          // sizing to its `Row`) while confining every scroll
                          // re-anchor's rebuild to this subtree alone.
                          ValueListenableBuilder<double>(
                            valueListenable: _visibleBottom,
                            builder:
                                (
                                  BuildContext context,
                                  double visibleBottom,
                                  Widget? child,
                                ) {
                                  return Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      for (
                                        int lane = 0;
                                        lane < lanesCount;
                                        lane++
                                      ) ...[
                                        if (lane > 0)
                                          const SizedBox(
                                            width: VelvetSpacing.sm,
                                          ),
                                        _LaneColumn(
                                          key: ValueKey<String>(
                                            'timeline-lane-$lane',
                                          ),
                                          bookings: bookings,
                                          geometry: _laneGeometry[lane],
                                          cardWidth: effectiveCardW,
                                          visibleBottom: visibleBottom,
                                          onBookingTap: widget.onBookingTap,
                                        ),
                                      ],
                                    ],
                                  );
                                },
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
    required this.geometry,
    required this.cardWidth,
    required this.visibleBottom,
    required this.onBookingTap,
    super.key,
  });

  /// The FULL day's bookings — [geometry] selects this lane's subset by
  /// [_CardGeometry.bookingIndex].
  final List<Booking> bookings;

  /// This lane's precomputed per-card geometry, ascending by `startAt` —
  /// memoised by the grid's state (see the file header's "ADDENDUM 6"), so
  /// this build does no timezone lookups and no layout arithmetic at all.
  final List<_CardGeometry> geometry;

  final double cardWidth;

  /// The culling band's BOTTOM edge in this column's own coordinates — a card
  /// planned entirely below it is replaced by an identically-sized `SizedBox`.
  ///
  /// ADDENDUM 6: there is no top edge. Cards at or above the visible band are
  /// NEVER culled, so no visible card can move if a placeholder's height is
  /// imperfect — which is what allows culling at every text scale.
  final double visibleBottom;

  final ValueChanged<Booking> onBookingTap;

  @override
  Widget build(BuildContext context) {
    final List<Widget> children = <Widget>[];

    for (final _CardGeometry geo in geometry) {
      final Booking booking = bookings[geo.bookingIndex];

      // ADDENDUM 4/5/6 — viewport culling. The placeholder is the box the
      // card is EXPECTED to occupy (`cardWidth` × [_CardGeometry.
      // occupiedHeight]), emitted in the SAME position in the `Column`, so
      // nothing about the lane's geometry — or R3's no-overlap guarantee —
      // changes. The width matters as much as the height: a lane whose cards
      // were all replaced by height-only boxes would collapse to zero width
      // and drag every lane to its right sideways.
      final bool culled = geo.plannedTop > visibleBottom;

      // ADDENDUM 9 part 2 — only a POSITIVE spacer is worth an element. Since
      // ADDENDUM 8 floored the spacer at 0, `spacer == 0` for every card after
      // the first in a back-to-back run (the normal shape of a working day),
      // and a zero-height `SizedBox` in a `Column` contributes nothing to
      // layout or paint — it was ~100 no-op `Element`s + `RenderBox`es on a
      // full day. Dropping it is layout-identical and leaves R3 (and culling's
      // "same tree shape either way" argument) intact; see ADDENDUM 9.
      if (geo.spacer > 0) {
        children.add(SizedBox(height: geo.spacer));
      }
      children.add(
        culled
            ? SizedBox(
                key: ValueKey<String>('timeline-card-culled-${booking.id}'),
                width: cardWidth,
                height: geo.occupiedHeight,
              )
            // MEDIUM-1 (perf): `MasterBookingCard` is a `StatefulWidget` whose
            // press state drives an `AnimatedScale` (110ms) +
            // `AnimatedContainer` (150ms) — without a boundary, one card's
            // press animation dirties the whole shared layer, so at the
            // ~100-card ceiling a single tap could repaint the entire grid.
            // Same pattern as `calendar_button.dart` and
            // `booking_status_medallion.dart`.
            : RepaintBoundary(
                child: SizedBox(
                  width: cardWidth,
                  child: MasterBookingCard(
                    key: ValueKey<String>('timeline-card-${booking.id}'),
                    booking: booking,
                    onTap: () => onBookingTap(booking),
                    minHeight: geo.minHeight,
                  ),
                ),
              ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}

/// One card's fully-resolved position and size within its lane `Column` —
/// memoised by [_BookingsTimelineGridState._recomputeLayoutModel] (see the
/// file header's "ADDENDUM 6") so that a culling rebuild costs one `>`
/// comparison per card instead of a timezone-table lookup plus the whole
/// layout arithmetic.
class _CardGeometry {
  const _CardGeometry({
    required this.bookingIndex,
    required this.spacer,
    required this.plannedTop,
    required this.minHeight,
    required this.occupiedHeight,
  });

  /// Index into the grid's FULL day list, not into this lane.
  final int bookingIndex;

  /// The blank vertical space before this card — idle time in the lane, or
  /// (for the lane's first card) its distance from the ruler origin. Floored
  /// at 0 since ADDENDUM 8, and since ADDENDUM 9 a zero value emits NO
  /// `SizedBox` at all rather than a no-op one.
  final double spacer;

  /// This card's planned top edge in the lane's own coordinates — `spacer`
  /// added to the previous card's planned bottom. Compared against the
  /// culling window's bottom edge.
  final double plannedTop;

  /// The duration-derived FLOOR handed to `MasterBookingCard.minHeight`.
  final double minHeight;

  /// The box the card is expected to really occupy — [minHeight] raised to
  /// the selected layout's natural content height when that is taller. Exact
  /// at textScaler 1.0 (pinned by `master_booking_card_layout_height_test
  /// .dart`); an under-estimate above it, which ADDENDUM 6 made non-load-
  /// bearing.
  final double occupiedHeight;
}

/// Resolves one lane's [_CardGeometry] list — the arithmetic that used to
/// live inline in `_LaneColumn.build`.
///
/// `plannedBottom` is the PLANNED bottom edge of the previous card, in the
/// same "minutes since [originMinute], scaled to px" space as every `top` in
/// this file. [originMinute] is the FLOORED-hour origin (`firstHour * 60`)
/// that the gridlines and ruler also anchor to (see the file header's
/// "ADDENDUM 7" part 2), so a card's top/bottom land on the gridlines for its
/// start/end times even when the day's first booking starts off-hour. Per the
/// PROPORTIONAL-DURATION-HEIGHT PASS (this file's
/// "ADDENDUM 2") it advances by each card's real occupied box, not the fixed
/// `MasterBookingCard.estimatedNaturalHeight` the R3-era code used;
/// ADDENDUM 5 sharpened it further to `MasterBookingCard.occupiedHeightFor
/// (...)` rather than the bare [_cardMinHeightFor] FLOOR, so for a card whose
/// layout overshoots its floor (the >=60-minute full layout) the planned
/// position equals the rendered one exactly. This remains a PLANNING number
/// only: it decides how generous the blank space between cards looks, never
/// whether two cards can overlap — that guarantee comes from the `Column`
/// physically laying out child N+1 after child N's REAL rendered size,
/// regardless of this estimate (see the file header's "R3" section).
/// [maxTopPx] is the clamped extent's bottom, in the same px space as every
/// `top` here (see [BookingsTimelineGrid._kMaxEndMinute]). Every in-window
/// card's `desiredTop` already sits inside `[0, maxTopPx]`, so this bound is
/// INERT for real data; it exists so a booking that does not belong to the
/// selected day cannot plan a card 85 000dp down and hand the lane `Column`
/// — the one non-`Positioned` child driving the grid `Stack`'s size — an
/// extent the clamped ruler does not cover.
///
/// Such a card is REPOSITIONED to the nearest edge, never dropped. Dropping it
/// would make the rendered card set disagree with the header count the caller
/// computes from the same list — the exact divergence
/// `bookingsInsideScheduleWindow` was extracted to prevent (see
/// [BookingsTimelineGrid.bookings]). Deciding an out-of-window booking should
/// not be SHOWN is the caller's call; all this widget owes is a finite grid.
List<_CardGeometry> _geometryForLane({
  required List<Booking> bookings,
  required List<int> indices,
  required List<int> startMinutes,
  required int originMinute,
  required double hourHeight,
  required double maxTopPx,
}) {
  final List<_CardGeometry> geometry = <_CardGeometry>[];
  double plannedBottom = 0;

  for (int k = 0; k < indices.length; k++) {
    final int index = indices[k];
    final double desiredTop =
        ((startMinutes[index] - originMinute) / 60.0 * hourHeight).clamp(
          0.0,
          maxTopPx,
        );
    final double minHeight = _cardMinHeightFor(
      bookings[index].durationMinutes,
      hourHeight,
    );
    final double occupiedHeight = MasterBookingCard.occupiedHeightFor(
      minHeight,
    );

    // `max(0, ...)`, NOT `max(<some cosmetic gap>, ...)` — see the note where
    // `_kMinInterCardGap` used to be declared. The zero branch is the
    // no-collision case (the card's own band is at or past the previous card's
    // real bottom, so it lands on its true `desiredTop`); the positive branch
    // is genuine idle time in the lane. A spacer can never be negative because
    // a `Column` cannot lay a child above its predecessor's bottom anyway —
    // clamping at 0 makes the planned position agree with what the `Column`
    // will really do.
    final double spacer = k == 0
        ? desiredTop
        : math.max(0, desiredTop - plannedBottom);
    final double plannedTop = plannedBottom + spacer;

    geometry.add(
      _CardGeometry(
        bookingIndex: index,
        spacer: spacer,
        plannedTop: plannedTop,
        minHeight: minHeight,
        occupiedHeight: occupiedHeight,
      ),
    );

    plannedBottom = plannedTop + occupiedHeight;
  }

  return geometry;
}

/// A booking's proportional-duration card floor — see this file's
/// "ADDENDUM 2" for the original derivation and "ADDENDUM 8" for the current
/// floor. Proportional to [durationMinutes] against [hourHeight], floored at
/// the MICRO card's natural height
/// ([MasterBookingCard.microLayoutNaturalHeight], `28dp`) — the shortest box
/// `MasterBookingCard` can render anything legible in.
///
/// THE FLOOR IS THE SMALLEST OF THE CARD'S THREE NATURALS, ON PURPOSE. It used
/// to be [MasterBookingCard.estimatedNaturalHeight] (`56dp`, the COMPACT
/// body's), which meant every booking whose band was shorter than `56dp` got a
/// box taller than its own wall-clock footprint — the residual overrun the
/// previous pass documented as "irreducible". It was not irreducible; it was a
/// consequence of the card having no shape below the compact grid. Now that it
/// has one, the floor drops with it and the overrun only survives below ~14.0
/// minutes.
///
/// STILL INDEPENDENT OF THE 30-MINUTE SLOT (`hourHeight / 2`, now `60dp`): the
/// slot governs the gridlines, the card's own natural governs the card. Tying
/// the floor back to the slot would re-inflate every short card off its
/// end-time line, which is the bug the decoupling exists to prevent.
///
/// A MINIMUM, not an exact size — [MasterBookingCard] applies it as a
/// `BoxConstraints.minHeight`, so real content taller than this value always
/// wins (see that widget's class doc).
double _cardMinHeightFor(int durationMinutes, double hourHeight) {
  final double proportional = durationMinutes / 60.0 * hourHeight;
  return math.max(proportional, MasterBookingCard.microLayoutNaturalHeight);
}

/// Minutes between the selected day's Kyiv [midnight] and [instant]'s Kyiv
/// wall-clock — the R1 fix's anchor. A booking ending after midnight yields a
/// value **greater than 1440** rather than wrapping to a small number, so
/// monotonicity holds by construction.
///
/// [midnight] is passed IN rather than derived here (mobile-perf MEDIUM): it
/// is a pure function of the selected day, and constructing a `TZDateTime` per
/// call cost ~3N timezone-table lookups per build. See the file header's
/// "ADDENDUM 4".
int _minutesSinceDayStart(DateTime instant, tz.TZDateTime midnight) {
  final tz.TZDateTime local = toBeauticaTime(instant);
  return local.difference(midnight).inMinutes;
}

/// Filters [bookings] to those whose Kyiv-day start on [day] falls inside
/// [window] (per [ScheduleTimelineWindow.includesStart]) — the ONE filtering
/// computation behind the master's own «Мої записи» working-hours window.
///
/// mobile-security HIGH fix (this session): before this function existed,
/// [BookingsTimelineGrid] filtered its own card set internally while
/// `BookingsDiscoveryView`'s header count read the server's unfiltered
/// `totalElements` — two independently-maintained numbers that could (and
/// did) disagree. `_Loaded` now calls this once per day and uses its result
/// for BOTH the header count and [BookingsTimelineGrid.bookings], so the
/// count is always exactly `visible.length`, i.e. exactly what renders.
/// Public (not `_`-prefixed) specifically so a caller outside this file can
/// reach it — the same Kyiv-minute conversion ([_minutesSinceDayStart]) this
/// grid's own layout model uses internally, exposed once rather than
/// re-implemented at the call site.
///
/// mobile-perf MEDIUM fix (this session): returns [bookings] itself —
/// same instance, not an equal copy — whenever every booking passes the
/// window (the common case: a working master's own day rarely has a
/// booking outside its own working hours). A fresh `<Booking>[for … if …]`
/// here on EVERY call, even when nothing was actually filtered out, handed
/// [BookingsTimelineGrid] a new list identity on every rebuild and defeated
/// its `identical(widget.bookings, oldWidget.bookings)` memoisation gate
/// (`didUpdateWidget`, below) — reopening the exact O(N log N)
/// `assignLanes` + per-card layout cost ADDENDUM 4/6 fixed. Safe only
/// because this function's result is read-only everywhere downstream (grid
/// layout + card render, never mutated) — do not hand this out to a caller
/// that appends/removes from it.
List<Booking> bookingsInsideScheduleWindow(
  List<Booking> bookings,
  DateTime day,
  ScheduleTimelineWindow window,
) {
  final tz.TZDateTime midnight = tz.TZDateTime(
    beauticaZone,
    day.year,
    day.month,
    day.day,
  );
  List<Booking>? filtered;
  for (int i = 0; i < bookings.length; i++) {
    final Booking b = bookings[i];
    final bool inside = window.includesStart(
      _minutesSinceDayStart(b.startAt, midnight),
    );
    if (filtered == null) {
      // Nothing excluded yet — defer allocating a copy until we actually
      // know one is needed.
      if (!inside) {
        filtered = bookings.sublist(0, i);
      }
    } else if (inside) {
      filtered.add(b);
    }
  }
  return filtered ?? bookings;
}
