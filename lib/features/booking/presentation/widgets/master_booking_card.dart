// Phase 7.6 — one booking in the MASTER's «Мої записи» list, rendered inside
// the day timeline (`BookingsTimelineGrid`, Phase 7.10).
//
// ## Compact-timeline pass (2026-07-20) — WHY THIS CARD LOST ITS AVATAR ROW
//
// The card previously carried a 3-row grid (avatar + client name, a divider,
// service + date chip, price + status) whose natural height never dropped
// below ~135-150dp even after two earlier density passes. `_kHourH` (the
// timeline's one-hour vertical unit, `bookings_timeline_grid.dart`) is 72dp,
// so a 30-minute slot is 36dp and a 60-minute slot is 72dp — nothing shorter
// than ~2 hours could ever fit that card at its own true time position.
// `_LaneColumn`'s collision-nudge (see that file's "R3" section) then pushed
// every subsequent same-lane card progressively further below its real hour
// line to avoid a genuine overlap — cards visually detached from the ruler,
// which is what the "cards are going outside the time lines" report was
// actually describing (NOT the design's own card overhang, which is
// expected and fine).
//
// The fix is density, not a layout rewrite: a card that fits inside a
// 45-60 minute slot reaches its true `desiredTop` in the common case, so the
// drift disappears on its own. `_LaneColumn` is UNCHANGED and still the
// correctness backstop for the genuinely-tight case (two 15-minute bookings
// back-to-back) — see that file's R3 header.
//
// The compact layout is a MINIATURE OF THE FULL CARD (2026-07-21)
// -----------------------------------------------------------------------
// The compact body previously ran a divider-less two-line grid
// (time/service/price, then client/status). It has been re-composed so a
// 30-minute card reads as a scaled-down version of the >=1h card rather
// than a differently-shaped one — same semantic split, same hairline, same
// reading order:
//
// ```
// ┌──────────────────────────────────────┐
// │ 09:00–09:30   Марія Іванюк        ●  │  ← when · who · status DOT
// │ ──────────────────────────────────── │  ← hairline (BrandColors.faint)
// │ Стрижка жіноча              450 ₴    │  ← what · how much
// └──────────────────────────────────────┘
//                 56dp
// ```
//
// Row 1 is IDENTITY (when + who), row 2 is the TRANSACTION (what + how
// much), and the hairline is the same cut [_buildFullBody] makes between
// its client-name row and its service row. That is what earns the word
// "miniature" instead of "shrunk copy".
//
// The text [TimelineStatusBadge] compresses to [TimelineStatusDot] in this
// layout ONLY — the label is what does not fit, so the colour carries the
// signal and the label moves to the `Semantics`/`Tooltip` channel (see that
// widget's doc: colour alone across six statuses is not a signal). The
// >=1h card keeps the labelled pill, unchanged.
//
// THE 41dp BUDGET, AND WHAT IT COST TO ADD A DIVIDER
// -----------------------------------------------------------------------
// At textScaler 1.0 a 56dp box leaves `56 − 3 (border 1.5 × 2) − 12
// ([_compactPadding] vertical 6 × 2) = 41dp` of content. The stack:
//
//   | row 1     | 15 | [VelvetText.masterCardClientName] 12.5 × 1.2 — the
//   |           |    | tallest child (time is 13.8, the dot 8)
//   | gap       |  4 | `VelvetSpacing.xs`
//   | hairline  |  1 |
//   | gap       |  4 | `VelvetSpacing.xs`
//   | row 2     | 17 | the price pill: 15dp line + [_kCompactPriceVPad] × 2
//   | TOTAL     | 41 | = the budget exactly, zero slack at scale 1.0
//
// The divider and its two gaps are 9dp of NET-NEW vertical cost the
// outgoing two-row layout did not carry (it measured 55dp natural). The
// status dot buys WIDTH, not height. That 9dp was paid for out of the
// PRICE PILL's own vertical padding — 3dp -> 1dp via [_PriceTag]'s new
// `verticalPadding` knob (default 3, so [_buildFullBody] renders
// byte-identically) — and NOT out of any type size: in a card whose whole
// job is legibility at a glance in a scrolling timeline, the type scale is
// the last thing to cut. 6dp of a 21dp pill was air; a recessed well that
// generously padded is over-articulated at this size anyway.
//
// Zero slack at 1.0 is deliberate and is ASSERTED (`master_booking_card_
// test.dart`'s "the 41dp vertical budget" group) rather than left as a
// claim — any regression overflows rather than quietly eating the gaps.
// Above 1.0 the box simply grows: [minHeight] is a floor, never a ceiling
// (see the class doc), so a 1.3-scaled card renders taller than its slot
// exactly as the outgoing layout did.
//
// ## The time is a RANGE, and carries no date (2026-07-21)
//
// Both layouts print `start–end` («10:00–11:30») via the shared
// [formatSlotTimeRange], fed by `Booking.endAt` — the real persisted end
// instant, never re-derived from `durationMinutes` (see that formatter's doc
// for why the two cases are deliberately separate functions).
//
// The full layout previously paired its `schedule_outlined` glyph with a
// date+time caption («12 лип, 14:30»). The DATE is gone from both layouts:
// «Мої записи» is day-scoped — `bookingsDayProvider` returns exactly one Kyiv
// day per fetch and `BookingsDayRail` above the timeline already names that
// day — so repeating it on every card was redundant chrome. The glyph and the
// [VelvetText.masterCardDateFull] style are unchanged; only the string is.
// A master reading a timeline wants to know how long each appointment RUNS,
// which the start alone never told them.
//
// Dropping the avatar is the main height saving, not a smaller font pass —
// [ClientAvatarGradients] (`core/theme/brand_colors.dart`, shared/public) and
// this file's own [_ClientAvatar] widget are deliberately NOT deleted: they
// remain available for any future non-timeline card that wants the gradient
// avatar treatment. [_ClientAvatar] is simply unreferenced from this file's
// build now (see its own doc for the `unused_element` justification) — the
// per-card gradient-resolution plumbing that used to feed it
// (`_avatarGradientColors`/`initState`/`didUpdateWidget`) was removed as dead
// weight rather than kept computing a value nothing reads.
//
// ## Why this is NOT an extension of the shipped `booking_card.dart`
//
// Phase 7.6's brief asks that the client-side `BookingCard` be extended if it
// generalises. It does not, and the reason is structural rather than
// cosmetic — the two cards disagree about what a booking IS.
//
//   * The CLIENT card's dominant element is a date STUB in its own exclusive
//     left column, pinned to a fixed y-offset, beside a master photo. Its
//     whole grid exists to answer "when am I going somewhere, and to whom".
//     Its identity slot renders the master (avatar, professional title, salon
//     name) — three fields this card must not show.
//   * The MASTER card's dominant element is the CLIENT's name, with the
//     booking's start–end time range leading the first line. It answers "who
//     is coming to me, for what, and for how long".
//
// The genuinely shared pieces ARE shared: `BookingDisplayX.showsPrice` and
// the date formatters. `BookingStatusBadge` (Phase 14.7) is DELIBERATELY NOT
// shared with this card any more — see [TimelineStatusBadge]'s doc for why
// the timeline needed its own compact variant instead of restyling the
// widget `booking_card.dart` (client list), «Деталі запису» and the salon
// screens all still consume verbatim.
//
// The one design element deliberately dropped: the preview's SECOND identity
// row (`b.masterName` under the client) is salon-scope only — it names which
// teammate serves the booking. A single master's own list never needs it,
// the same reason `showMasterFilter: false`.
//
// SEC: renders a client name (PII). The hosting screen holds the
// `ScreenProtectionManager`; this widget logs nothing.
//
// ## Adaptive full/compact layout (2026-07-20, later the same day as the
// compact-timeline pass above) — design-parity pass on top of proportional
// height
//
// The compact-timeline pass above fixed CORRECTNESS (nothing under a
// 45-60 minute slot could ever fit the old 3-row card). The very next
// commit (`0da31fe`, this file's `minHeight` doc) made the card's floor
// PROPORTIONAL to `booking.durationMinutes` instead of a flat one-slot
// estimate — so a 60-minute booking now gets a genuine ~112dp box, and a
// 90-minute one ~168dp. That reopened room the compact pass never had: a
// 60-minute-and-up card can now afford the approved design's fuller shape
// (client name → hairline divider → service+time → price+status) without
// reintroducing the "cards drift off their hour line" bug — the divider
// layout only ever renders on a box already tall enough for it.
//
// THE SWITCH — read from the resolved constraint, never re-derived from
// `durationMinutes`
// -----------------------------------------------------------------------
// [build] compares [minHeight] itself (`widget.minHeight ?? 0`) against
// [_kFullLayoutMinHeight], NOT `widget.booking.durationMinutes`. That
// constructor field IS the card's real constraint, not a guess: it flows
// straight into the `BoxConstraints(minHeight: widget.minHeight!)` a few
// lines below, so comparing against it is comparing against the exact
// value the box's `ConstrainedBox` will enforce — a few lines apart from
// where it is actually applied, not re-derived independently. Reading
// `widget.booking.durationMinutes` directly instead would be a SECOND,
// independently-driftable source of truth for the same decision the
// timeline already made when it computed [minHeight]
// (`bookings_timeline_grid.dart`'s `_cardMinHeightFor`) — two places
// deciding "is this booking long enough" that could silently disagree
// after a future edit to either one's threshold.
//
// WHY NOT A `LayoutBuilder` READING `constraints.minHeight` INSTEAD — a
// real trap, not a style preference
// -----------------------------------------------------------------------
// A first pass tried exactly that: a `LayoutBuilder` as the
// `AnimatedContainer`'s child, comparing `constraints.minHeight` (the
// value the `ConstrainedBox` actually resolved) against the threshold.
// `constraints.maxHeight` was never viable — see the "no clipping" note
// below, `maxHeight` is `double.infinity` at every real call site — but
// `minHeight` looked like the more precise read, since it is the box's
// FINAL enforced constraint rather than the pre-enforcement field. It
// measured 3dp SHORT of the true 112dp floor in the widget test harness,
// intermittently flipping a genuinely->=112dp card back to the compact
// layout. Root cause: `Container`/`AnimatedContainer` treats a
// `BoxDecoration`'s border as IMPLICIT padding (`BoxDecoration.padding =>
// border?.dimensions`) reserved so content never paints under the stroke,
// and that padding is applied INSIDE the `ConstrainedBox` — so a
// `LayoutBuilder` sitting below it sees the constraint AFTER the border's
// own width has already been deflated out (`Border.all(width: 1.5)` here
// deflates height by 2 x 1.5 = 3dp, both edges). That silently coupled the
// full/compact SWITCH to this same pass's unrelated border-width bump (see
// [_decorationUnpressed]'s doc) — a future border-width tweak would have
// silently shifted the layout threshold along with it. Comparing
// [minHeight] directly has no such coupling: it is read before any
// decoration is ever built.
//
// NO CLIPPING, either branch — the invariant carries over unchanged from
// the R2 fix above: [minHeight] is a floor, never a ceiling, so whichever
// layout [build] picks, the box grows to fit that layout's real content
// (`AnimatedContainer.constraints` sets `minHeight` only, never
// `maxHeight`) — there is still no mechanism anywhere in this widget that
// could crop a layout's paint to a box smaller than its natural size.
//
// WHAT DID NOT COME BACK — the design's avatar + master-name rows
// -----------------------------------------------------------------------
// The design's `BookingCard` (this file's source of truth,
// `docs/signup-designs/SalonManagementDesign/lib/widgets/
// booking_widgets.dart`) opens with a client avatar + a master-name row
// under it. Neither returns here, full layout or not: this card renders
// the INDEPENDENT master's own bookings, so naming which teammate served
// the client (the master-name row's whole purpose) is meaningless, and the
// original compact pass's rationale for dropping the avatar (pure height
// saving) is orthogonal to whether that height then goes to a fuller
// layout or stays blank — a locked product decision, not a pass that ran
// out of room.
//
// PRICE MAY BE A FROZEN BAND — «450 ₴» OR «300–500 ₴»
// -----------------------------------------------------------------------
// This section previously claimed, as a locked decision, that "a booked,
// settled appointment has one price, never a min-max range". That is FALSE
// and has been corrected: the backend now sends `priceMaxAtBooking`
// alongside `priceAtBooking`, and a booking made against a service the
// master had left as a genuine `RANGE` (no `priceOverride`) carries both.
//
// The contract, in full:
//   * `Booking.priceMax == null` means SINGLE price — render `price` alone.
//     Null is not a missing value and not an error state.
//   * Non-null means the range was real at booking time; `price` is the
//     floor and `priceMax` the ceiling. Both were FROZEN server-side, once,
//     at booking time — this card must never re-derive a band from
//     `priceType`/`priceOverride`/the service's current catalogue state,
//     which describe the service today rather than what was agreed then.
//
// Both layouts render whichever form applies via the same [_PriceTag], fed
// by the shared `BookingDisplayX.priceLabel` (→ `formatBookingPrice`) so the
// separator (en-dash), rounding and «₴» suffix can never drift from the
// client card or «Деталі запису». The `showsPrice` gate is unchanged and
// applies identically to a band.
//
// [_PriceTag] caps its own width and scales down rather than clipping — see
// its doc — because a two-number band is materially wider than the single
// figure this card's compact 56dp layout was originally sized around.
//
// ## THE MICRO LAYOUT (2026-07-24) — A THIRD DENSITY, FOR SLOTS UNDER 56dp
//
// `bookings_timeline_grid.dart`'s VERTICAL-SCALE-DOWN pass (its "ADDENDUM 8")
// dropped `_kHourH` to `120`, which puts a 30-minute booking at `60dp` and a
// 15-minute one at `30dp`. The compact grid above needs `56dp`, so every
// booking under ~28 minutes would have been INFLATED to a 56dp box — a card
// visibly taller than its own wall-clock band, i.e. exactly the overrun the
// scale pass exists to remove.
//
// The MICRO layout is the shape that fits a 15-minute band:
//
// ```
// ┌────────────────────────────────────────┐
// │ Стрижка жіноча        10:00–10:15   ●  │  ← what · when · status DOT
// └────────────────────────────────────────┘
//                  ~29dp
// ```
//
// ONE row, no hairline, no price pill, no client name. The service name
// LEADS and takes the `Expanded` slot because it is the only thing the card's
// vertical POSITION does not already encode — a micro card sits on its own
// start gridline, so "when" is legible from the geometry and needs only a
// trailing confirmation. [TimelineStatusDot] stays hard right, in the same
// place both other layouts put their status indicator, so the right edge of a
// mixed-density lane reads as one column of statuses.
//
// WHAT IS DROPPED, AND WHERE IT WENT: the client name is already carried by
// the card's own `Semantics(label:)` (`masterBookingCardSemantics`, unchanged
// for all three layouts). The PRICE has no visual slot left, so [build]
// attaches it as `Semantics(value:)` on the micro branch only — a standard
// a11y property, no new ARB key, and no per-card `Tooltip` (a card-wide
// tooltip would win the gesture arena on long-press and suppress the card's
// own `onTap`; see [TimelineStatusDot]'s "GESTURE PROPERTY" note). Everything
// dropped from the visual stays one tap away on «Деталі запису» — the whole
// card is still the same single tap target it is in the other two layouts.
//
// THE 29dp BUDGET: border (1.5 × 2 = 3) + [_MasterBookingCardState.
// _compactPadding]'s vertical 6 × 2 (12) + ONE text row, whose height is the
// tallest of the three children — [VelvetText.masterCardTime] (11.5 × 1.2 =
// 13.8), [VelvetText.masterCardService] (11 × 1.2 = 13.2) and the 8dp dot.
// = **29dp** at textScaler 1.0 (13.8 rounds up to a whole 14 in text
// layout), pinned as [MasterBookingCard.microLayoutNaturalHeight]. It is
// MEASURED, not the round 30 an early sketch assumed nor the 28.8 the raw
// token arithmetic gives. The grid floors its cards at this number, so a
// 15-minute band (`15/60 × 120 = 30dp`) clears it and lands exactly on its
// end line.
//
// THE SELECTION IS THREE-WAY BUT `null` STILL MEANS COMPACT. [_layout] reads
// [minHeight] itself (same reason as the full/compact switch below), but a
// `null` [minHeight] — every call site outside the timeline grid — resolves
// to COMPACT, not micro. `null` means "no constraint at all", which is the
// opposite of "a very tight constraint"; treating it as `0` and selecting
// micro would silently re-shape every non-timeline caller.
//
// THE BORDER, NOT THE SHADOW, CARRIES "MORE VISIBLE"
// -----------------------------------------------------------------------
// The design's own card reads sharper mostly because of an OFFSET dual
// shadow (`booking_widgets.dart`'s `_kCardShadow`) — BANNED here, see
// `_decorationUnpressed`'s doc below for why (the Impeller corner-artifact
// history, shipped twice). The border alpha/width bump documented on
// [_decorationUnpressed] is the safe substitute: more contrast from the
// stroke itself, the safe non-offset [VelvetShadows.borderedCard] shadow
// unchanged.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';

import '../../domain/booking.dart';
import '../../domain/booking_display_x.dart';
import 'booking_status_badge.dart';

/// A provider-perspective booking row. The whole card is one tap target that
/// opens «Деталі запису» — it carries no per-action buttons (those live on the
/// detail screen, Phase 7.3).
///
/// `BookingsTimelineGrid` (Phase 7.10) constrains this card's `width` (via a
/// `SizedBox` in its per-lane `_LaneColumn`) and, since the
/// PROPORTIONAL-DURATION-HEIGHT pass (2026-07-20, see that file's
/// "ADDENDUM 2"), a [minHeight] floor derived from the booking's
/// `durationMinutes` — never an exact `height:`. The distinction is the whole
/// point:
///
///  * [minHeight] is a [BoxConstraints.minHeight] on the card's own
///    `AnimatedContainer`, so the box can grow PAST it to fit real content
///    but can never force that content to render smaller than its natural
///    size. When the booking's duration-derived floor exceeds the card's
///    natural ~54dp content, the extra space renders as blank room BELOW the
///    two content rows, inside the same decorated box — the card visually
///    fills the slot its duration occupies, per-pixel, while the content
///    itself never resizes.
///  * When [minHeight] is omitted (`null`, the default — every call site
///    outside `BookingsTimelineGrid`), the card behaves exactly as before:
///    sizes itself to its own natural content height with nothing forced.
///
/// An earlier version of this widget accepted optional `width`/`height`
/// constructor params and, whenever `height` came in smaller than the card's
/// natural size, wrapped itself in an [OverflowBox] + [ClipRect] pair that
/// laid the card out at its natural height and then visually CROPPED the
/// paint — and the hit-test region — to the forced box. That was the exact
/// mechanism behind the "I can see only half of the card" report against the
/// real device. [minHeight] cannot reintroduce that bug because it is a
/// floor, never a ceiling: do not add a `maxHeight`/exact `height:` knob to
/// this widget, and do not wrap it in `OverflowBox`/`ClipRect` — a future
/// caller that genuinely needs a fixed-size card must crop the CONTENT
/// (fewer rows), never the render of the full card.
class MasterBookingCard extends StatefulWidget {
  const MasterBookingCard({
    super.key,
    required this.booking,
    required this.onTap,
    this.minHeight,
  });

  final Booking booking;
  final VoidCallback onTap;

  /// A `BoxConstraints.minHeight` floor on the card's box — see the class
  /// doc. `null` (the default) applies no constraint at all, so the card
  /// sizes to its own natural content height exactly as it did before the
  /// proportional-duration-height pass.
  final double? minHeight;

  /// The COMPACT body's EXACT natural rendered height at textScaler 1.0 (see
  /// the derivation below) — the middle of this card's three naturals,
  /// alongside [microLayoutNaturalHeight] and [fullLayoutNaturalHeight].
  ///
  /// CORRECTION — an earlier revision of this doc said it was "no longer read
  /// by `BookingsTimelineGrid`'s lane layout". That was false when written and
  /// is false now. It is read twice: [occupiedHeightFor] returns it for every
  /// floor in the compact band, and it IS [microLayoutMaxHeight], the
  /// compact/micro boundary — a floor that cannot contain this height is
  /// exactly what selects the micro row. (What it stopped being, in the
  /// PROPORTIONAL-DURATION-HEIGHT pass, is the grid's card FLOOR; that is now
  /// [microLayoutNaturalHeight] — see `bookings_timeline_grid.dart`'s
  /// `_cardMinHeightFor`.)
  ///
  /// Still deliberately NOT a safety floor: the timeline's per-lane `Column`
  /// layout can never let two cards overlap regardless of how far any of these
  /// naturals drift from a card's true height (a `Column` always starts a
  /// child exactly after its predecessor's REAL rendered size, not a planning
  /// number) — so getting this value wrong costs visual density and scroll
  /// extent, never correctness.
  ///
  /// Derivation, post MINIATURE-OF-THE-FULL-CARD pass (this file's "THE 41dp
  /// BUDGET" header section, which carries the same arithmetic in full):
  /// border (1.5 × 2 = 3) + [_MasterBookingCardState._compactPadding]'s
  /// vertical 6 × 2 (12) + row 1 (15, the client name — the tallest of the
  /// range label / name / dot) + a `VelvetSpacing.xs` gap (4) + the hairline
  /// (1) + a second `VelvetSpacing.xs` gap (4) + row 2 (17, the price pill:
  /// a 15dp line box plus [_MasterBookingCardState._kCompactPriceVPad] × 2)
  /// = **56dp exactly**.
  ///
  /// NO LONGER A ROUNDED-UP ESTIMATE. The outgoing divider-less grid
  /// measured 55dp natural against this same 56 and the constant carried
  /// ~1dp of slop "to absorb font-metric overhead". The re-composed layout
  /// lands on 56 on the nose at textScaler 1.0 — the budget and the constant
  /// are now the same number, which is the point: the layout was sized TO
  /// this box rather than measured after the fact, so a regression that
  /// eats a gap or re-inflates the pill shows up as a real overflow instead
  /// of quietly consuming slack. Pinned by `master_booking_card_test.dart`'s
  /// "the 41dp vertical budget" group. Above textScaler 1.0 the real card is
  /// TALLER than this (measured 60dp at 1.15, 65dp at 1.3) and the box grows
  /// to meet it — [minHeight] is a floor, never a ceiling.
  ///
  /// Row 2's 17dp term is the price pill, and that pill's height is pinned
  /// independently of its horizontal `BoxFit.scaleDown` — see [_PriceTag]'s
  /// zero-width height anchor. Without that anchor a band wide enough to hit
  /// the pill's width cap would have scaled the pill's HEIGHT down with it
  /// (uniform fit), silently dragging the compact card below this figure.
  static const double estimatedNaturalHeight = 56;

  /// The [minHeight] at or above which this card renders its fuller divided
  /// layout instead of the compact grid — the public face of
  /// [_MasterBookingCardState._kFullLayoutMinHeight], which carries the full
  /// derivation. Exposed so a CALLER that must predict this card's rendered
  /// box (see [occupiedHeightFor]) reads the very constant [build] switches
  /// on, rather than re-deriving the threshold and drifting from it.
  static const double fullLayoutMinHeight =
      _MasterBookingCardState._kFullLayoutMinHeight;

  /// [_buildFullBody]'s natural rendered height at textScaler 1.0 — the
  /// [estimatedNaturalHeight] of the OTHER layout, and EXACT rather than an
  /// estimate for the same reason: the full body is a fixed stack of
  /// single-line rows, so its height is independent of the booking's text
  /// (lane width moves the ellipsis, never the height — measured identical at
  /// 226 / 266 / 272dp of lane).
  ///
  /// Derivation: border (1.5 × 2 = 3) + [_MasterBookingCardState._fullPadding]
  /// (16 × 2 = 32) + the client-name row + `VelvetSpacing.sm + 2` + the 1dp
  /// hairline + `VelvetSpacing.sm + 2` + the service/time row +
  /// `VelvetSpacing.xs + 2` + the price/badge row = **117dp**.
  ///
  /// Pinned by `master_booking_card_test.dart`'s "the FULL body still
  /// measures exactly 117dp at textScaler 1.0" case, and — as the input to
  /// [occupiedHeightFor] — by `master_booking_card_layout_height_test.dart`,
  /// which renders the real card at every floor the timeline can produce and
  /// asserts the prediction matches to the pixel.
  ///
  /// TEXT SCALE 1.0 ONLY. The same measurement is 124dp at 1.15 and 132dp at
  /// 1.3, so any caller predicting a box from this constant MUST gate itself
  /// on `MediaQuery.textScalerOf(context).scale(1) <= 1.0` — see
  /// `bookings_timeline_grid.dart`'s "ADDENDUM 5".
  static const double fullLayoutNaturalHeight = 117;

  /// [_buildMicroBody]'s natural rendered height at textScaler 1.0 — the third
  /// layout's counterpart to [estimatedNaturalHeight] /
  /// [fullLayoutNaturalHeight], and exact for the same reason (one row of
  /// single-line children, so lane width moves the ellipsis, never the height).
  ///
  /// Derivation, in full on the class doc's "THE MICRO LAYOUT" section:
  /// border (1.5 × 2 = 3) + [_MasterBookingCardState._compactPadding]'s
  /// vertical 6 × 2 (12) + the row's tallest child, the time range in
  /// [VelvetText.masterCardTime] (Nunito 11.5 at `height: 1.2` = 13.8, which
  /// Flutter's text layout rounds UP to a whole 14 — taller than the service
  /// name's 13.2 and the 8dp status dot) = **29dp**.
  ///
  /// 29, NOT the round 30 an early sketch of this pass assumed, and not the
  /// 28.8 the unrounded arithmetic gives. It is a MEASURED number:
  /// `bookings_timeline_grid.dart`'s `_cardMinHeightFor` floors every card at
  /// it and [occupiedHeightFor] predicts real boxes from it, so it has to be
  /// what the card actually renders rather than what the type tokens multiply
  /// out to. Pinned by `master_booking_card_test.dart`'s "the MICRO body
  /// measures exactly 29dp" case and, as an [occupiedHeightFor] input, by
  /// `master_booking_card_layout_height_test.dart`.
  ///
  /// TEXT SCALE 1.0 ONLY, exactly as [fullLayoutNaturalHeight].
  static const double microLayoutNaturalHeight = 29;

  /// The [minHeight] BELOW which this card renders its single-row micro
  /// layout — equal to [estimatedNaturalHeight] because that IS the compact
  /// grid's natural height: a floor that cannot contain the compact body is
  /// precisely the case micro exists for. Exclusive, so a floor of exactly
  /// [estimatedNaturalHeight] still gets the compact grid.
  ///
  /// A `null` [minHeight] never selects micro — see the class doc.
  static const double microLayoutMaxHeight = estimatedNaturalHeight;

  /// The EXACT height this card's decorated box occupies when built with
  /// [minHeight], at textScaler 1.0 — computable without building the card.
  ///
  /// [minHeight] is a floor, never a ceiling (see the class doc), so the box
  /// resolves to `max(floor, the selected layout's natural content height)`,
  /// and which layout is selected is itself a pure function of [minHeight]
  /// ([fullLayoutMinHeight] / [microLayoutMaxHeight]). All three branches'
  /// naturals are content-independent exact numbers
  /// ([microLayoutNaturalHeight] / [estimatedNaturalHeight] /
  /// [fullLayoutNaturalHeight]), so this is a real prediction rather than an
  /// estimate.
  ///
  /// NO LONGER A MATHEMATICAL NO-OP. While the grid floored every card at
  /// [estimatedNaturalHeight] this function could only ever return its own
  /// argument, and the doc comments claiming otherwise were stale. The micro
  /// layout moved the grid's floor down to [microLayoutNaturalHeight], so the
  /// `max` genuinely binds again in the sub-compact band: a 10-minute booking
  /// at `120dp/hour` has a `20dp` wall-clock band, a `29dp` floor, and a
  /// `29dp` real box.
  ///
  /// Exists for `bookings_timeline_grid.dart`'s viewport culling, whose
  /// placeholder must reserve precisely the room the real card would take or
  /// every card below it reflows off its hour line. Do NOT use it to SIZE a
  /// card (that would reintroduce the exact-height clipping bug the class doc
  /// forbids) — it predicts, it never constrains.
  ///
  /// Valid at textScaler 1.0 only — see [fullLayoutNaturalHeight].
  static double occupiedHeightFor(double minHeight) {
    final double natural;
    if (minHeight >= fullLayoutMinHeight) {
      natural = fullLayoutNaturalHeight;
    } else if (minHeight < microLayoutMaxHeight) {
      natural = microLayoutNaturalHeight;
    } else {
      natural = estimatedNaturalHeight;
    }
    return math.max(minHeight, natural);
  }

  @override
  State<MasterBookingCard> createState() => _MasterBookingCardState();
}

/// Which body [_MasterBookingCardState.build] renders, resolved once from
/// [MasterBookingCard.minHeight] — see [_MasterBookingCardState._layout].
///
/// An enum rather than the two booleans this started as: with three densities,
/// a pair of independent `_useFullLayout`/`_useMicroLayout` getters can express
/// the impossible "both" state, and every call site would have to re-derive the
/// precedence between them. `switch` over this is exhaustive by construction,
/// so a fourth density cannot be added without the compiler naming every place
/// that must handle it.
enum _MasterCardLayout { full, compact, micro }

class _MasterBookingCardState extends State<MasterBookingCard> {
  bool _pressed = false;

  /// The card's two decoration states, hoisted out of [build] (mobile-perf
  /// MEDIUM-4): `build()` reruns on every press
  /// (`onTapDown`/`onTapCancel`/`onTapUp` each call `setState`) and on every
  /// ancestor rebuild across up to ~100 cards on the busiest day, so
  /// reallocating a fresh `BoxDecoration` + `Border.all` on every one of
  /// those was pure waste — the decoration is a pure function of [_pressed],
  /// which only ever takes two values.
  ///
  /// `VelvetShadows.borderedCard`, NOT `extrudedCard` and NOT an offset
  /// single-dark-shadow recipe.
  ///
  /// `extrudedCard` is out because its offset near-white light shadow pokes
  /// past the rounded corner under Impeller and paints a white wedge there
  /// (resolved 34db74f). This card previously used a since-deleted
  /// `cardDropShadow` recipe (an offset, fully-opaque `shadowDarkCard`
  /// shadow) on the theory that only NEAR-WHITE offset shadows were unsafe —
  /// that theory was wrong. The Impeller-GLES corner-square artifact is
  /// triggered by an OPAQUE shadow at a non-zero `Offset` on a rounded
  /// `BoxDecoration`, full stop; hue is irrelevant, and `shadowDarkCard` is
  /// opaque (`alpha 0xFF`). It shipped a black rectangle in this card's
  /// corners for the same structural reason the earlier fix shipped a white
  /// one. `borderedCard` is proven safe (already shipped on
  /// `master_strip_shell.dart` / `calendar_button.dart` / `bookings_day_rail.dart`
  /// for this exact bug class) because it is BOTH alpha-attenuated
  /// (`.withValues(alpha: 0.45)`, not opaque) AND non-offset. Do NOT assume
  /// either property alone is sufficient — an attenuated-but-OFFSET shadow
  /// has not been empirically verified safe on this hardware and must not be
  /// introduced as a "closer to the design" compromise; a flatter, fully-safe
  /// card beats a second unverified corner-artifact risk. See
  /// `impeller_circle_shadow_guard_test.dart`'s (corrected, hue-independent)
  /// "offset-opaque-shadow recipe guard".
  ///
  /// ## "Much more visible" border (2026-07-20 design-parity pass)
  ///
  /// The design's card reads sharper mostly from its offset dual shadow —
  /// banned here (see above). Bumped the stroke itself instead: alpha
  /// 0.18 -> 0.38 (a bit over double) and width 1 -> 1.5dp. Chosen by eye
  /// against the `#E6DDD0` base: 0.38 is the point where the camel edge
  /// reads as a clear, deliberate outline at rest without turning heavy or
  /// competing with the accent-colour content inside the card (the price
  /// pill's `accentDeep` text, the service icon). [_kBorderAlpha]/
  /// [_kBorderWidth] are named so a future revert back toward 0.18 trips
  /// the border-visibility test in `master_booking_card_test.dart`.
  static const double _kBorderAlpha = 0.38;
  static const double _kBorderWidth = 1.5;

  static final BoxDecoration _decorationUnpressed = BoxDecoration(
    color: BrandColors.base,
    borderRadius: BorderRadius.circular(VelvetRadii.card),
    border: Border.all(
      color: BrandColors.accent.withValues(alpha: _kBorderAlpha),
      width: _kBorderWidth,
    ),
    boxShadow: VelvetShadows.borderedCard,
  );
  static final BoxDecoration _decorationPressed = BoxDecoration(
    color: BrandColors.base,
    borderRadius: BorderRadius.circular(VelvetRadii.card),
    border: Border.all(
      color: BrandColors.accent.withValues(alpha: _kBorderAlpha),
      width: _kBorderWidth,
    ),
  );

  /// The height, in dp, at or above which [build] switches from the
  /// compact grid to the fuller divided layout — see this file's
  /// "Adaptive full/compact layout" header section for the full mechanism.
  /// Equal to [MasterBookingCard.fullLayoutNaturalHeight] (`117dp`, the full
  /// body's own natural floor at textScaler 1.0): a booking whose
  /// duration-derived floor reaches `117dp` or more gets the fuller layout;
  /// anything shorter stays on the compact grid.
  ///
  /// ## WHICH DURATIONS REACH IT — RE-DERIVE THIS, NEVER QUOTE IT
  ///
  /// The threshold itself is stable (the full body's own natural floor, so a
  /// card takes the fuller shape exactly when its ruled band can contain it
  /// without overhang), but WHICH durations clear it is a function of
  /// `BookingsTimelineGrid._kHourH`, which has now moved three times. At the
  /// current `120dp/hour` (that file's "ADDENDUM 8"):
  ///
  ///   * `>= 59` min — floor `>= 118dp`, clears `117`: FULL layout. The exact
  ///     boundary duration is `58.5` min (`117 / 120 × 60`); an hour-long
  ///     booking sits only `3dp` clear of it, which is why `_kHourH` cannot
  ///     drop below `120` without moving this threshold too.
  ///   * `28`-`58` min — floor `56`-`116dp`: COMPACT grid.
  ///   * `< 28` min — floor below the compact body's own `56dp` natural
  ///     (`56 / 120 × 60 = 28` exactly): MICRO, the single row (see this
  ///     file's "THE MICRO LAYOUT" section).
  ///
  /// Two earlier revisions of this doc asserted a 45-minute answer, in
  /// opposite directions (`112` → compact, `168` → full). At `120` it is
  /// compact again (`45/60 × 120 = 90dp`). The lesson recorded here rather
  /// than the answer: this list is DERIVED, and any `_kHourH` change
  /// invalidates it wholesale.
  ///
  /// [_buildFullBody]'s NATURAL height (the same fixture the compact sweeps
  /// use — a long service name, a frozen RANGE band, a full client name)
  /// measures 117dp at textScaler 1.0 (124dp at 1.15, 132dp at 1.3); it is
  /// identical at 226 / 266 / 272dp of lane because every row is flex-driven,
  /// so lane width moves the ellipsis, never the height.
  ///
  /// Nothing clips in either branch (the box grows — see "NO CLIPPING, either
  /// branch" above); this threshold only chooses which layout renders.
  static const double _kFullLayoutMinHeight =
      MasterBookingCard.fullLayoutNaturalHeight;

  /// Full layout padding — 16dp, matching the approved design's own
  /// `BookingCard` padding (`EdgeInsets.all(VelvetSpacing.md)` in the
  /// design's token file, where `md` is also 16). Distinct from
  /// `ARCHITECTURE-mobile.md` §9's generic "neumorphic card" padding token
  /// (`VelvetSpacing.lg`, 24dp) — that table entry is for a general raised
  /// card, not this specific design's own booking-card spec, which this
  /// file transcribes literally per the design-source-of-truth rule.
  static const EdgeInsets _fullPadding = EdgeInsets.all(VelvetSpacing.md);

  /// Compact layout padding — unchanged from the pre-adaptive-pass card.
  static const EdgeInsets _compactPadding = EdgeInsets.symmetric(
    horizontal: VelvetSpacing.sm + 2,
    vertical: VelvetSpacing.xs + 2,
  );

  /// The price pill's vertical padding inside the COMPACT layout — 1dp,
  /// against [_PriceTag]'s own 3dp default which [_buildFullBody] keeps.
  ///
  /// This 4dp (2 × 2) is exactly what paid for the hairline divider and its
  /// two `VelvetSpacing.xs` gaps — see this file's "THE 41dp BUDGET" header
  /// section. It is spent on the pill rather than on a type step-down on
  /// purpose: 6dp of the pill's 21dp was air, and a recessed well padded for
  /// a 112dp card is over-articulated inside a 56dp one, whereas shrinking
  /// the type would cost the card the legibility-at-a-glance that is its
  /// entire job in a scrolling timeline.
  static const double _kCompactPriceVPad = 1;

  // THE COMPACT PRICE CAP IS GONE — REMOVED 2026-07-22 (mobile-perf MEDIUM)
  // ----------------------------------------------------------------------
  // `_kCompactPriceReserve` (68), `_kCompactPriceMinWidth` and
  // `_compactPriceCap(rowWidth)` used to compute a `maxWidth` for the compact
  // row's price pill from the row's own measured width, which is what forced
  // the per-card `LayoutBuilder` this file's row 2 comment now documents the
  // removal of. The cap was inert on every device the app supports (it
  // resolved to 135dp against the pill's own 112dp ceiling), and the
  // measurement it required cost a relayout boundary per card up to 100 times
  // per day AND made the whole card illegal under `IntrinsicHeight`. Overflow
  // safety on that row is structural, not arithmetic — see [_PriceTag]'s
  // `Flexible` + `FittedBox(fit: BoxFit.scaleDown)` and row 2's comment in
  // [_buildCompactBody]. Do not reintroduce a width-measuring cap here.

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Booking b = widget.booking;
    final String clientName = b.clientName ?? l10n.bookingDetailGuestClient;

    final _MasterCardLayout layout = _layout;

    return Semantics(
      button: true,
      label: l10n.masterBookingCardSemantics(clientName, b.serviceName),
      // The MICRO layout has no room for the price pill, so the price moves to
      // the a11y channel rather than disappearing — see the class doc's "WHAT
      // IS DROPPED, AND WHERE IT WENT". `null` on the other two layouts, whose
      // semantics are unchanged.
      value: layout == _MasterCardLayout.micro && b.showsPrice
          ? b.priceLabel
          : null,
      child: GestureDetector(
        key: Key('master-booking-card-${b.id}'),
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _pressed ? 0.99 : 1,
          duration: const Duration(milliseconds: 110),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: _pressed ? _decorationPressed : _decorationUnpressed,
            // A FLOOR, not an exact size — see the class doc's [minHeight]
            // section. `constraints` sits OUTSIDE the padding below, in
            // `Container`'s own build order, so the decorated box (not just
            // the content inside it) really spans at least [minHeight];
            // each branch's `Column` stays top-aligned
            // (`mainAxisAlignment.start`, its default) so any leftover room
            // renders as blank space under the content rather than
            // stretching it.
            constraints: widget.minHeight == null
                ? null
                : BoxConstraints(minHeight: widget.minHeight!),
            // The full/compact switch — see this file's "Adaptive
            // full/compact layout" header section, in particular "WHY NOT A
            // `LayoutBuilder`", for why this reads [minHeight] itself
            // rather than the box's resolved `BoxConstraints` at build
            // time.
            padding: layout == _MasterCardLayout.full
                ? _fullPadding
                : _compactPadding,
            child: switch (layout) {
              _MasterCardLayout.full => _buildFullBody(b, clientName),
              _MasterCardLayout.compact => _buildCompactBody(b, clientName),
              _MasterCardLayout.micro => _buildMicroBody(b),
            },
          ),
        ),
      ),
    );
  }

  /// Which of the three bodies [build] renders — see this file's "Adaptive
  /// full/compact layout" and "THE MICRO LAYOUT" header sections.
  ///
  /// Reads [MasterBookingCard.minHeight] itself rather than the box's resolved
  /// `BoxConstraints` (see "WHY NOT A `LayoutBuilder`") or the booking's
  /// `durationMinutes` (which would be a second, independently-driftable
  /// source of truth for a decision the timeline already made).
  ///
  /// `null` — every call site outside `BookingsTimelineGrid` — is COMPACT, not
  /// micro: it means "no constraint", not "a very tight one".
  _MasterCardLayout get _layout {
    final double? minHeight = widget.minHeight;
    if (minHeight == null) return _MasterCardLayout.compact;
    if (minHeight >= _kFullLayoutMinHeight) return _MasterCardLayout.full;
    if (minHeight < MasterBookingCard.microLayoutMaxHeight) {
      return _MasterCardLayout.micro;
    }
    return _MasterCardLayout.compact;
  }

  /// The SINGLE-ROW body for a slot too short for the compact grid — service
  /// name (flexes), the start–end range, the status dot. See this file's "THE
  /// MICRO LAYOUT" header section for what is dropped and where it went.
  ///
  /// No `clientName` parameter on purpose: the client is not rendered here at
  /// all, and taking the argument would invite a future edit to squeeze it in.
  Widget _buildMicroBody(Booking b) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        // The service name LEADS and takes the flex: a micro card sits on its
        // own start gridline, so the ruler already answers "when" — the
        // service is the only thing the card's position cannot encode.
        Expanded(
          child: Text(
            b.serviceName,
            style: VelvetText.masterCardService,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // The same two gaps the compact row 1 uses, in the same order
        // (`VelvetSpacing.xs + 2` before the trailing metadata, the tighter
        // `VelvetSpacing.xs` before the dot so the dot reads as ATTACHED to
        // this booking rather than floating on the right margin).
        const SizedBox(width: VelvetSpacing.xs + 2),
        Text(
          formatSlotTimeRange(b.startAt, b.endAt),
          style: VelvetText.masterCardTime,
        ),
        const SizedBox(width: VelvetSpacing.xs),
        TimelineStatusDot(booking: b),
      ],
    );
  }

  /// The MINIATURE of [_buildFullBody] — identity row (start–end range ·
  /// client name · status dot), a hairline, then the transaction row
  /// (service name · price). The only shape proven to fit a 30-minute (56dp)
  /// slot without clipping. See this file's "The compact layout is a
  /// MINIATURE OF THE FULL CARD" and "THE 41dp BUDGET" header sections.
  Widget _buildCompactBody(Booking b, String clientName) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // ROW 1 — IDENTITY: when, then who, then the status dot hard right.
        //
        // Reading order is deliberate: the lighter range label
        // ([VelvetText.masterCardTime], Nunito 11.5) LEADS the heavier client
        // name ([VelvetText.masterCardClientName], Comfortaa 12.5), so the row
        // reads as a sentence — "at this hour, this person" — rather than as
        // two cells of a table. That weight gradient is one of the three
        // things keeping this card off the squashed-grid failure mode; the
        // other two are the hairline's semantic cut (identity above,
        // transaction below — the same cut [_buildFullBody] makes) and the
        // diagonal formed by the dot at top-right against the price pill at
        // bottom-right, with the flexing text running between them.
        //
        // NO `LayoutBuilder` AND NO PRICE RESERVE ON THIS ROW — it cannot
        // overflow on its own. Its non-flex content is the range label
        // (86.6dp at the 1.3 textScaler ceiling), two fixed gaps (6 + 4) and
        // an 8dp dot = 104.6dp against the narrowest lane's 203dp of inner
        // width, leaving the `Expanded` client name ~98dp. The outgoing
        // layout needed a capped pill here precisely because the PRICE shared
        // this row; moving it to row 2 is what removed the constraint.
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Text(
              formatSlotTimeRange(b.startAt, b.endAt),
              style: VelvetText.masterCardTime,
            ),
            const SizedBox(width: VelvetSpacing.xs + 2),
            Expanded(
              child: Text(
                clientName,
                style: VelvetText.masterCardClientName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Tight gap on purpose: the dot must read as ATTACHED to the
            // client name — a status about this appointment — rather than
            // floating in a third column on the right margin.
            const SizedBox(width: VelvetSpacing.xs),
            TimelineStatusDot(booking: b),
          ],
        ),
        const SizedBox(height: VelvetSpacing.xs),
        // The hairline — the same 1dp `BrandColors.faint` rule
        // [_buildFullBody] draws, and the same role: it separates the
        // client-identity row above from the booking detail below. Run
        // full-width inside the padding rather than inset; an inset rule at
        // 226dp reads as decoration, edge-to-edge reads as structure.
        //
        // Its own key, distinct from the full layout's
        // `master-booking-card-divider-<id>`, so a test can tell the two
        // layouts apart by which divider rendered rather than by the mere
        // presence of one (the compact/full switch is otherwise invisible
        // now that BOTH bodies carry a hairline and the SAME range string).
        Container(
          key: Key('master-booking-card-compact-divider-${b.id}'),
          height: 1,
          color: BrandColors.faint,
        ),
        const SizedBox(height: VelvetSpacing.xs),
        // ROW 2 — THE TRANSACTION: service name (flexes) · price.
        //
        // NO `LayoutBuilder` HERE — REMOVED 2026-07-22 (mobile-perf MEDIUM)
        // -----------------------------------------------------------------
        // This row used to be wrapped in one, purely to compute a
        // `maxWidth` cap for the price pill from the row's own width. That
        // cap was provably INERT on every device the app supports: the
        // narrowest lane the timeline can build is 226dp
        // (`bookings_timeline_grid.dart`'s "ADDENDUM 3" clamps its 272dp card
        // to `constraints.maxWidth`, and the lane area is `deviceWidth − 94`
        // — 24 + 24 screen padding, 42 ruler, 4 gap — so a 320dp device
        // yields `320 − 94 = 226`), which is 203dp of inner width after this
        // card's padding and border. The cap resolved to `203 − 68 = 135dp`,
        // ABOVE [_PriceTag._maxTextWidth]'s own 112dp ceiling, so it never
        // bound anything.
        //
        // What it DID cost, up to 100 times per day: a relayout boundary per
        // card, plus this subtree being built during LAYOUT rather than
        // build — and, worse, it made the whole card illegal under
        // `IntrinsicHeight`/`IntrinsicWidth`/an `IntrinsicColumnWidth` table
        // column, because a `LayoutBuilder` cannot report intrinsic
        // dimensions. That failure was asymmetric and the quiet half was the
        // dangerous one: DEBUG/JIT asserts "LayoutBuilder does not support
        // returning intrinsic dimensions" and throws, while RELEASE/AOT
        // compiles the assert out and silently returns `0.0` from all four
        // intrinsic queries — a mangled card in the shipped app with nothing
        // thrown, nothing logged and no test failure, because the widget
        // tests that would have exploded only ever run in debug. The
        // `IntrinsicHeight` + `CrossAxisAlignment.stretch` pattern is live
        // and common in this repo (`master_profile_screen.dart`,
        // `public_master_profile_screen.dart`, `home_hub_screen.dart`,
        // `quick_links_card.dart`, `next_appointment_card.dart`,
        // `passport_table.dart`), so that was a one-line landmine for any
        // future caller.
        //
        // OVERFLOW SAFETY IS STRUCTURAL, NOT ARITHMETIC: [_PriceTag] caps its
        // own text at [_PriceTag._maxTextWidth] and wraps it in a `Flexible` +
        // `FittedBox(fit: BoxFit.scaleDown)`, so it scales into whatever
        // bounded width this `Row` hands it however narrow that gets — no
        // reserve, and no row-width measurement, required.
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: Text(
                b.serviceName,
                style: VelvetText.masterCardService,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // See `BookingDisplayX.showsPrice`: a cancelled, declined or
            // missed appointment owes nothing, so printing a sum on it
            // would assert a debt that does not exist. On those cards
            // this row is the service name alone.
            if (b.showsPrice) ...<Widget>[
              const SizedBox(width: VelvetSpacing.xs),
              // NON-flex, exactly as the retired `ConstrainedBox` was: a
              // `Row` hands its non-flex children unbounded width, under
              // which [_PriceTag]'s own `Flexible` + [_PriceTag._maxTextWidth]
              // resolve to the identical 112dp ceiling the inert 135dp cap
              // used to sit above. Making it `Flexible` here would NOT be
              // equivalent — it would split the free space with the service
              // name's `Expanded` instead of leaving the remainder to it.
              _PriceTag(
                price: b.priceLabel,
                verticalPadding: _kCompactPriceVPad,
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// The design's fuller layout — client name, a hairline divider, the
  /// service name (below the divider, with the design's accent
  /// `spa_outlined` glyph) paired with the booking's start–end time range
  /// (date-free — see this file's "The time is a RANGE" header section), then
  /// price + status. Only ever built once [build] has already confirmed the
  /// box is >= [_kFullLayoutMinHeight] — see this file's "Adaptive
  /// full/compact layout" header section. Deliberately has NO avatar and NO
  /// master-name row — see that same section's "WHAT DID NOT COME BACK".
  Widget _buildFullBody(Booking b, String clientName) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // Row 1 — client identity only.
        Text(
          clientName,
          style: VelvetText.masterCardClientNameFull,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: VelvetSpacing.sm + 2),
        // The hairline divider — its canonical role in the design is
        // separating the client-identity row above from the service/booking
        // detail below.
        Container(
          key: Key('master-booking-card-divider-${b.id}'),
          height: 1,
          color: BrandColors.faint,
        ),
        const SizedBox(height: VelvetSpacing.sm + 2),
        // Row 2 — service name (below the divider, per design) + the booking's
        // start–end time range (via the shared `formatSlotTimeRange`
        // formatter — never hand-rolled, see
        // `shared/formatters/booking_date_labels.dart`). NO DATE: this screen
        // is day-scoped (`bookingsDayProvider` fetches exactly one Kyiv day)
        // and the day rail above the timeline already names the day, so a
        // per-card date was redundant chrome. The range reads NARROWER than
        // the "12 лип, 14:30" caption it replaced, so this row gained margin.
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.spa_outlined, size: 16, color: BrandColors.accent),
            const SizedBox(width: VelvetSpacing.sm),
            Expanded(
              child: Text(
                b.serviceName,
                style: VelvetText.masterCardServiceFull,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: VelvetSpacing.sm),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.schedule_outlined,
                  size: 12,
                  color: BrandColors.muted,
                ),
                const SizedBox(width: 3),
                Text(
                  formatSlotTimeRange(b.startAt, b.endAt),
                  style: VelvetText.masterCardDateFull,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: VelvetSpacing.xs + 2),
        // Row 3 — price (left) + status badge (right). See
        // `BookingDisplayX.showsPrice`: a cancelled, declined or missed
        // appointment owes nothing, so printing a sum on it would assert a
        // debt that does not exist — the badge alone still renders, pushed
        // right by the `Spacer` in that branch.
        //
        // THE PRICE IS `Expanded` + LEFT-ALIGNED, NOT A NON-FLEX PILL BESIDE
        // A `Spacer` (226dp narrow-lane pass, 2026-07-21)
        // ---------------------------------------------------------------
        // This row used to be `_PriceTag` + `Spacer` + badge, i.e. TWO
        // non-flex children either side of the flex. A `Row` lays non-flex
        // children out unbounded, so neither could ever see how little room
        // the row had: on the narrowest real lane (226dp → 191dp of inner
        // width here, this layout's padding being 16 not 10) a capped 112dp
        // band plus the badge overflowed by 6.6px at textScaler 1.0, 16px at
        // 1.15 and 26px at 1.3. Hiding the pill cleared it; shrinking the
        // service name above did not — so it is the pill's non-flex contract
        // that had to give, NOT the type scale.
        //
        // `Expanded` + `Align` is what gives it: the badge (short, and the
        // one thing on this row that must stay fully legible) keeps its
        // intrinsic width, the price then gets ALL the remaining width as a
        // real bounded constraint, and [_PriceTag]'s inner `Flexible` scales
        // the band into it. `Align(centerLeft)` reproduces the retired
        // `Spacer`'s visual result exactly — pill hard left, badge hard
        // right — with the leftover living inside the `Expanded` instead of
        // in a sibling. No reserve is needed here — nothing else on this row
        // competes for that space (and the compact row's own reserve is gone
        // too; see the note where it used to be declared).
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            if (b.showsPrice)
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _PriceTag(price: b.priceLabel),
                ),
              )
            else
              const Spacer(),
            // v-pad 3dp per the design's own `BookingStatusBadge` — the
            // compact timeline row keeps the tighter 2dp default (its own
            // budget is far smaller); see [TimelineStatusBadge.verticalPadding].
            TimelineStatusBadge(booking: b, verticalPadding: 3),
          ],
        ),
      ],
    );
  }
}

/// A price pill — «450 ₴», or the frozen band «300–500 ₴».
///
/// Design-parity pass (finding #9): the approved design draws this as a
/// `NeumorphicInset` recessed well (`booking_widgets.dart`'s `PriceTag`);
/// transcribed verbatim via the shared `core/widgets/neumorphic.dart`
/// `NeumorphicInset` — the same widget the design's own token file's
/// `NeumorphicInset` maps to, so this is a like-for-like port, not a
/// reinterpretation.
///
/// ## Why the width cap exists (frozen-band pass)
///
/// This pill sits beside an `Expanded` service name (compact) or a status
/// badge (full). A long band («12500–25000 ₴») is materially wider than the
/// single figure this card was sized around, so left unbounded it could
/// out-measure the room the row has left and trip a `RenderFlex` overflow.
/// Capping the TEXT at [_maxTextWidth] and letting [FittedBox] scale it down
/// keeps the pill hugging its content (so it stays hard against its row's
/// edge, and the service name still ellipsises into whatever it leaves) while
/// making an overflow structurally impossible. `scaleDown` shrinks rather than
/// clips, so a pathological band stays legible instead of losing its ceiling
/// to an ellipsis.
///
/// ## The cap is a CEILING; the incoming constraint is the real limit
/// (226dp narrow-lane pass, 2026-07-21)
///
/// [_maxTextWidth] alone was NOT enough, and the reason is a `RenderFlex`
/// detail rather than a mis-measured constant: a `Row` lays its NON-flex
/// children out with an UNBOUNDED `maxWidth`, so a pill parked as a plain
/// non-flex child never saw how much room its row actually had. It always
/// took the full capped 112dp (96 text + 2×8 padding) — and on the real
/// narrowest lane (226dp: a 320dp device minus 94 of ruler/padding/gap — see
/// `bookings_timeline_grid.dart`'s "ADDENDUM 3") that overflowed BOTH layouts
/// once a frozen band was present.
///
/// The fix is on the CALLER side, in both rows, and this widget's job is to
/// honour it: the pill's inner band is a [Flexible], so whenever the pill is
/// handed a bounded `maxWidth` the [FittedBox] scales into THAT instead of
/// into a flat 96. The two callers bound it differently, each matching its
/// row's own priority order:
///
///   * compact row 2 — a plain NON-flex child, so [_maxTextWidth] alone is
///     the ceiling. It stays non-flex on purpose: the service name must keep
///     absorbing the slack (a `Flexible` pill would split the row's free
///     space evenly with the `Expanded` name and cost that name ~17dp on
///     every device, for nothing). The row-width-derived `ConstrainedBox`
///     that used to sit here was removed 2026-07-22 — it never bound, and
///     buying it cost a `LayoutBuilder` per card; see [MasterBookingCard]'s
///     row 2 comment.
///   * full row 3 — an `Expanded` + `Align`, which hands the pill the row's
///     entire remaining width after the status badge. No reserve is needed
///     because nothing else in that row competes for it.
///
/// Both keep [_maxTextWidth] as the ceiling: on any lane wide enough (266dp
/// and up) neither bound binds and the pill renders exactly as it always did.
class _PriceTag extends StatelessWidget {
  const _PriceTag({required this.price, this.verticalPadding = _kDefaultVPad});

  /// The pill's default vertical padding — the approved design's own
  /// `PriceTag` value, which [MasterBookingCard]'s FULL layout keeps
  /// verbatim. Named (was a bare `3` literal on the constructor default) so
  /// [_paddingDefault] below can be a compile-time constant without
  /// re-stating the number.
  static const double _kDefaultVPad = 3;

  /// Already-formatted — «450 ₴» or «300–500 ₴». See
  /// `BookingDisplayX.priceLabel`; this widget never formats money itself.
  final String price;

  /// Vertical padding inside the pill. Defaults to 3dp — the approved
  /// design's own `PriceTag` value, which [MasterBookingCard]'s FULL layout
  /// keeps verbatim. The COMPACT layout passes 1dp
  /// ([MasterBookingCard]'s `_kCompactPriceVPad`): those 4dp are exactly
  /// what paid for the compact card's hairline divider and its two gaps —
  /// see `master_booking_card.dart`'s "THE 41dp BUDGET" header section.
  ///
  /// A PARAMETER rather than a second widget, and defaulted so the >=1h card
  /// renders byte-identically — the same shape [TimelineStatusBadge.
  /// verticalPadding] already established for the same reason. The HEIGHT
  /// ANCHOR below is unaffected: it pins the pill's LINE box, and this knob
  /// only moves the padding around it.
  final double verticalPadding;

  /// The widest the pill's TEXT may grow before it scales down. A CAP, not a
  /// column width — a short «450 ₴» still sizes to its own content.
  ///
  /// Sized to the longest band this card can realistically be asked to draw,
  /// «12500–25000 ₴» (5 + 5 digits), in [VelvetText.pill] (Nunito 11/w800):
  /// 83.8dp measured, so ~12dp of headroom under this 96
  /// (`VelvetSpacing.xxl * 2`).
  ///
  /// ## The 96 it shares with `booking_card.dart` is a COINCIDENCE — do not
  /// treat the two as one knob
  ///
  /// `booking_card.dart`'s `_priceMaxWidth` is also 96, and an earlier version
  /// of this doc claimed that made "the two booking cards scale their price at
  /// the same threshold". That is FALSE and has been corrected: the two caps
  /// are equal in dp but NOT in glyphs, because the two cards render the price
  /// at different type scales.
  ///
  ///   * this card — [VelvetText.pill] (Nunito 11/w800): «12500–25000 ₴»
  ///     measures 83.77dp, leaving ~12dp of headroom.
  ///   * `booking_card.dart` — `VelvetText.bookingCardPrice` (Nunito 10/w800):
  ///     the same band measures 76.96dp, leaving ~19dp. (Re-measured when that
  ///     card's band finally got test coverage of its own — it had been
  ///     carrying an estimated «~74dp / ~22dp» that nothing checked.)
  ///
  /// So a future type-scale bump trips THIS card roughly 7dp of band-width
  /// earlier than the other one. Deliberately left as two independent
  /// constants rather than one shared token: unifying them would encode a
  /// coupling that does not exist and would invite the exact wrong edit
  /// (bumping one token and assuming both cards are still clear). If either
  /// card's price type scale changes, RE-MEASURE THAT CARD ONLY — and update
  /// the headroom figures on both docs so this comparison stays honest.
  static const double _maxTextWidth = VelvetSpacing.xxl * 2; // 96

  /// The two padding values this widget is ACTUALLY built with, pre-resolved
  /// as compile-time constants (mobile-perf INFO-2, 2026-07-21).
  ///
  /// Turning the vertical inset into a FIELD cost the `EdgeInsets` its
  /// constness — one allocation per card per build where HEAD had a `const`.
  /// Only two values exist in the whole app ([_kDefaultVPad] for the >=1h
  /// card, [_MasterBookingCardState._kCompactPriceVPad] for the compact one),
  /// so [_resolvePadding] selects between these two instead of building a
  /// third. The knob itself stays a `double` field — see [verticalPadding]'s
  /// doc for why it is a parameter and not a second widget — so the
  /// non-const branch below remains as the correct fallback for any other
  /// value rather than an assert that would turn a cosmetic tweak into a
  /// crash.
  static const EdgeInsets _paddingDefault = EdgeInsets.symmetric(
    horizontal: VelvetSpacing.sm,
    vertical: _kDefaultVPad,
  );
  static const EdgeInsets _paddingCompact = EdgeInsets.symmetric(
    horizontal: VelvetSpacing.sm,
    vertical: _MasterBookingCardState._kCompactPriceVPad,
  );

  EdgeInsets _resolvePadding() {
    if (verticalPadding == _kDefaultVPad) return _paddingDefault;
    if (verticalPadding == _MasterBookingCardState._kCompactPriceVPad) {
      return _paddingCompact;
    }
    return EdgeInsets.symmetric(
      horizontal: VelvetSpacing.sm,
      vertical: verticalPadding,
    );
  }

  @override
  Widget build(BuildContext context) {
    return NeumorphicInset(
      radius: VelvetRadii.pill,
      child: Padding(
        padding: _resolvePadding(),
        // HEIGHT IS PINNED INDEPENDENTLY OF THE HORIZONTAL SCALE
        // ---------------------------------------------------------------
        // `BoxFit.scaleDown` scales UNIFORMLY, so the moment
        // [_maxTextWidth] binds it shrinks the band's HEIGHT by the same
        // factor, not just its width — measured: an over-cap band renders
        // its text at 13.0dp instead of the style's natural 15.0dp. Left
        // alone that silently drags the whole compact card under
        // [MasterBookingCard.estimatedNaturalHeight], whose derivation names
        // this pill's ~20dp row as the card's tallest.
        //
        // The zero-width [Text] below is a HEIGHT ANCHOR: an empty string in
        // the same [VelvetText.pill] style lays out at Size(0.0, 15.0) — no
        // width contributed to the [Row], full natural line height held. The
        // [Row] then takes the taller of (anchor, scaled band), which is the
        // anchor for every scale <= 1, so the pill keeps its natural height
        // no matter how far the band scales horizontally.
        //
        // IT MUST STAY A [Text], NOT A `SizedBox(height: 15)`. 15.0 is the
        // line height at textScaler 1.0 ONLY; a box cannot see the ambient
        // scaler, so under the app's own MediaQuery clamp (see `main.dart`'s
        // 1.3 ceiling) it would under-anchor and hand the height back to the
        // scaled band — measured with the constant swapped in: at 1.1 the pill
        // goes 23.0 (in-cap) vs 21.0 (over-cap), at 1.3 23.76 vs 21.0, i.e.
        // exactly the defect this anchor removes. The [Text] re-derives its
        // height from the inherited scaler on every build; the constant
        // freezes one scale. A scale-1.3 case in
        // `master_booking_card_test.dart` fails on the swap.
        //
        // Structural, not documentary, on purpose: the alternative (just
        // documenting the coupling on `estimatedNaturalHeight`) leaves a live
        // mechanism that quietly shrinks a real card, and the over-cap case
        // is now exercised by `master_booking_card_test.dart`'s
        // "the width cap actually engages" group.
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('', style: VelvetText.pill()),
            // [Flexible], not a bare [ConstrainedBox] — see this class's
            // "the cap is a CEILING, the incoming constraint is the floor"
            // section. A [Row] hands its NON-flex children unbounded width,
            // so without this the [ConstrainedBox] below would resolve to a
            // flat [_maxTextWidth] even when the pill's own incoming
            // `maxWidth` is narrower than that — and the overflow would
            // simply move INSIDE the pill. Under an unbounded incoming
            // width (the pill's original non-flex call shape) `Flexible`
            // lays the child out unbounded exactly as before, so this is a
            // no-op there.
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _maxTextWidth),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(price, style: VelvetText.pill(), maxLines: 1),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The (status colour, localized status label) pair the timeline's TWO status
/// indicators — [TimelineStatusBadge] (labelled pill, >=1h cards) and
/// [TimelineStatusDot] (bare circle, compact cards) — both render.
///
/// ## Why this exists rather than each widget calling the factory itself
///
/// [BookingStatusVisual.of] (`booking_status_badge.dart`) is already the ONE
/// place the status→(colour, glyph, label) mapping lives, shared with the
/// client card, «Деталі запису» and the salon screens. This helper does not
/// re-implement any of it — it is a single named resolution point INSIDE this
/// file so the badge and the dot cannot drift from each other either.
///
/// That second level matters here specifically because the dot DROPS the
/// label from the visual channel. Two independent `BookingStatusVisual.of`
/// call sites would each look correct in review while a future edit that
/// touched only one of them (say, mapping `unknown` to a different accent in
/// the pill) would silently ship a card whose dot and whose tooltip disagreed
/// about the status — the one failure a colour-only indicator cannot survive.
/// One call, destructured at the two use sites, makes that impossible.
({Color accent, String label}) _timelineStatusVisual(
  Booking booking,
  AppLocalizations l10n,
) {
  final BookingStatusVisual v = BookingStatusVisual.of(booking, l10n);
  return (accent: v.accent, label: v.label);
}

/// The COMPACT card's status indicator — a bare status-coloured circle, no
/// label, no wash, no border.
///
/// ## Why the label goes away here and only here
///
/// [TimelineStatusBadge]'s pill needs ~55-70dp of the row for its label. The
/// compact card's row 1 has already committed that width to the client's full
/// name, which is the thing a master actually scans a day timeline for. The
/// label is therefore the element that yields — but it is COMPRESSED, never
/// DROPPED: it moves wholesale to the non-visual channel below.
///
/// ## Colour alone is not a signal — the label is mandatory, not a nicety
///
/// There are SIX statuses (confirmed, completed, cancelled, declined,
/// not_completed, unknown) and three of their accents are warm browns a step
/// apart (`accentLatte`, `accentDeep`, `text`). Sighted users cannot reliably
/// tell those three apart at 8dp, and a screen-reader user gets nothing at all
/// from a coloured box. So this widget carries:
///
///   * `Semantics(label:)` with the SAME `l10n.bookingStatusSemantics(...)`
///     string [TimelineStatusBadge] announces, so the two indicators are
///     indistinguishable to assistive tech;
///   * a `Tooltip` with the plain status label, for the sighted long-press /
///     hover path.
///
/// Both strings come from [_timelineStatusVisual] → [BookingStatusVisual.of] →
/// the existing ARB keys the badge already uses. No new l10n key was needed
/// and none was added.
///
/// ## The 8dp
///
/// [TimelineStatusBadge] draws a 6dp dot BESIDE its label. Strip the label and
/// the dot inherits the whole signal, so it steps up one token to
/// `VelvetSpacing.sm`. Named ([diameter]), not inlined, so the sizing is one
/// edit rather than two.
///
/// Deliberately shadow-FREE, like every other circle in this app: on
/// Impeller-GLES `shape: BoxShape.circle` + `boxShadow` rasterizes as a hard
/// white square (`impeller_circle_shadow_guard_test.dart`). A wash halo would
/// be no better at this size — it would only muddy the hue the dot exists to
/// communicate.
class TimelineStatusDot extends StatelessWidget {
  const TimelineStatusDot({super.key, required this.booking});

  final Booking booking;

  /// `VelvetSpacing.sm` (8dp) — see the class doc. Fixed, so a status change
  /// can never reflow row 1.
  static const double diameter = VelvetSpacing.sm;

  /// The number of distinct accents [BookingStatusVisual.of] can resolve to —
  /// one per status (confirmed, completed, cancelled, declined,
  /// not_completed, unknown). The bound on [_decorationsByAccent].
  static const int _kAccentCount = 6;

  /// Per-accent [BoxDecoration] memo (mobile-perf INFO-1, 2026-07-21).
  ///
  /// The dot's decoration was previously allocated on EVERY build, against
  /// this file's own hoisting rule — see
  /// [_MasterBookingCardState._decorationUnpressed], which landed as a
  /// mobile-perf MEDIUM for exactly this.
  ///
  /// ## Why a memo rather than a hard-coded 6-entry literal
  ///
  /// A literal map keyed off the accents `booking_status_badge.dart` happens
  /// to use today would silently MISS — i.e. quietly regress to the per-build
  /// allocation this exists to remove, with nothing failing — the moment a
  /// status is remapped to a different accent or a seventh status ships. This
  /// memo is keyed by the accent actually resolved, so it cannot drift from
  /// the factory. It also keeps the dot on [_timelineStatusVisual] as its ONE
  /// resolution point (no status enum re-derived here), which the dot↔badge
  /// no-fork guarantee depends on.
  ///
  /// Bounded by construction: the status set is closed, so this reaches
  /// [_kAccentCount] entries and stops. [_decorationFor]'s assert is the
  /// tripwire if that ever stops being true.
  static final Map<Color, BoxDecoration> _decorationsByAccent =
      <Color, BoxDecoration>{};

  static BoxDecoration _decorationFor(Color accent) {
    assert(
      _decorationsByAccent.containsKey(accent) ||
          _decorationsByAccent.length < _kAccentCount,
      'TimelineStatusDot._decorationsByAccent grew past $_kAccentCount '
      'entries. It is keyed by status accent and BookingStatusVisual.of maps '
      'a closed set of $_kAccentCount statuses, so this means either a new '
      'status shipped (raise _kAccentCount) or an accent is being rebuilt '
      'per-instance — which would make this map an unbounded leak instead of '
      'the fixed table it is meant to be.',
    );
    return _decorationsByAccent.putIfAbsent(
      accent,
      () => BoxDecoration(shape: BoxShape.circle, color: accent),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ({Color accent, String label}) v = _timelineStatusVisual(
      booking,
      l10n,
    );

    // THE TOOLTIP IS THIS WIDGET'S DOMINANT COST, AND IT STAYS — A RECORDED
    // DECISION, NOT AN ACCIDENT (mobile-perf LOW-2, 2026-07-21)
    // -------------------------------------------------------------------
    // Measured: [TimelineStatusDot] costs 359.6us per instance to mount, of
    // which the `Tooltip` is 281.6us (78%); +107us on rebuild. Each MOUNTED
    // tooltip also installs a `PointerRouter` GLOBAL route
    // (`RawTooltipState.initState`, `raw_tooltip.dart:781`) — measured
    // +5.93us per pointer event at 100 mounted tooltips — holds a
    // `GlobalKey`, and allocates a `TextStyle.copyWith` + `Color.withOpacity`
    // + `BoxDecoration` + `EdgeInsets` + `_TooltipBox` on EVERY build whether
    // or not it is ever shown.
    //
    // It is NOT a regression. The `TimelineStatusBadge` this dot replaced on
    // the compact card cost 659us, so dot+tooltip is a net -299us per card,
    // and the rework as a whole moved a 100-card day switch 220.2ms ->
    // 212.1ms. The tooltip buys an affordance INSIDE a measured improvement;
    // it is not paying down one.
    //
    // KEPT because it is the only IN-PLACE disclosure a SIGHTED user has for
    // an 8dp colour. The `Semantics` label below serves screen-reader users
    // and does nothing for a sighted one, and three of the six accents are
    // warm browns one step apart (`accentLatte`, `accentDeep`, `text`) — see
    // this class's "Colour alone is not a signal" section. Cheaper
    // alternatives were evaluated and each lost:
    //
    //   * Hoist the styling into a `TooltipTheme`. The per-build allocations
    //     are computed unconditionally in `Tooltip.build`
    //     (`tooltip.dart:518+`), so a theme does not remove them — and the
    //     dominant 281.6us is the RawTooltip state machine + `OverlayPortal`
    //     + gesture wiring, not the styling. Saves ~nothing of the 78%.
    //   * ONE grid-level tooltip host instead of one per card. No Flutter API
    //     does this; it means a bespoke `OverlayPortal` + a grid-level
    //     `LongPressGestureRecognizer` + hit-testing back to the pressed dot,
    //     re-implementing dismiss-on-global-pointer, the show delay and the
    //     platform semantics contract. A new bespoke overlay and its bug
    //     surface to reclaim ~28ms of a 212ms DAY SWITCH (not a scroll
    //     frame). Rejected on KISS/YAGNI and risk.
    //   * Drop it and lean on the >=1h card's labelled `TimelineStatusBadge`
    //     plus «Деталі запису». A day of 30-minute bookings renders NO
    //     labelled badge at all, and the detail screen is a navigation away —
    //     so this is deleting the affordance and calling it an optimisation.
    //   * A colour legend in the timeline header. A design change (needs
    //     `frontend-design` + approval, out of scope for an audit pass) and
    //     it still cannot answer "what is THIS dot" in place.
    //
    // If this ever does land on a real frame budget, the honest fix is a
    // cheaper DISCLOSURE (a header legend, or restoring the label at >=45min),
    // never a silent deletion.
    //
    // TEST-HARNESS HAZARD (mobile-perf INFO-3) — `Tooltip` asserts
    // `debugCheckHasOverlay(context)` (`raw_tooltip.dart:844`). Every
    // production call site is under a `Navigator` (`_LaneColumn` ->
    // `BookingsTimelineGrid` -> `BookingsDiscoveryView`) and the suite is
    // green, but a future golden or unit test that pumps a bare
    // [MasterBookingCard] WITHOUT a `MaterialApp`/`Overlay` will now THROW
    // where it previously would not. Wrap the pump (`pumpApp` already does);
    // do not "fix" it by deleting the tooltip.
    //
    // GESTURE PROPERTY (mobile-perf INFO-4 — measured, intended) — a TAP on
    // the dot still opens the card: the tooltip's `Listener` is not a
    // gesture-arena member, so the card's `onTap` is unopposed. A LONG-PRESS
    // on the dot shows the tooltip and SUPPRESSES the card's `onTap` — the
    // tooltip's `LongPressGestureRecognizer` wins the arena at its 500ms
    // deadline, and `onTapCancel` fires so the card's `_pressed` does not
    // stick. That is correct tooltip behaviour over an 8dp target on a
    // ~226x56dp card: a deliberate long-press on the status dot asks "what is
    // this?", not "open this". Documented expectation, not a defect.
    return Tooltip(
      message: v.label,
      // THE STATUS WAS BEING ANNOUNCED TWICE (mobile-security LOW-1)
      // -----------------------------------------------------------------
      // Left at its default (`false`), `Tooltip` ALSO annotates the node with
      // `Semantics(tooltip:)` (`raw_tooltip.dart:850-851`) and fires
      // `SemanticsService.tooltip(...)` on show (`:562`) — while the
      // `Semantics(label:)` below already carries the same word. On Android
      // the `tooltip` property maps to `AccessibilityNodeInfo
      // .setTooltipText`, which TalkBack reads, so the node announced
      // «Статус: Підтверджено, Підтверджено».
      //
      // The `Semantics(label:)` below is the CANONICAL screen-reader channel
      // and is deliberately untouched — it is the string that makes this dot
      // indistinguishable from [TimelineStatusBadge] to assistive tech. This
      // flag silences only the tooltip's duplicate copy of it, which also
      // drops one `Semantics` node per card from the semantics tree.
      excludeFromSemantics: true,
      child: Semantics(
        label: l10n.bookingStatusSemantics(v.label),
        child: SizedBox(
          height: diameter,
          width: diameter,
          child: DecoratedBox(decoration: _decorationFor(v.accent)),
        ),
      ),
    );
  }
}

/// The timeline-only compact status pill — a `NeumorphicInset` recessed
/// well carrying a small status-coloured dot + label, transcribed from the
/// approved design's own `BookingStatusBadge`
/// (`docs/signup-designs/SalonManagementDesign/lib/widgets/
/// booking_widgets.dart:36-90`).
///
/// ## Why this is a SEPARATE widget from the shared `BookingStatusBadge`
///
/// The shared `booking_status_badge.dart` widget (Phase 14.3) is consumed
/// verbatim by `booking_card.dart` (the client list), «Деталі запису» and
/// the salon screens, and its file header documents deliberate,
/// measured-contrast choices (an actor-cap glyph, a soft wash, a fixed
/// 24dp height) that those surfaces rely on. The compact timeline row has no
/// room for a 24dp badge with an 18dp glyph cap next to a full client name —
/// but shrinking the SHARED widget to fit would touch every other screen
/// that already renders it, none of which asked for a smaller badge. A
/// second, timeline-scoped variant (this class) is the one the user
/// explicitly chose over restyling the shared widget.
///
/// ## Never a second source of truth for what each status MEANS
///
/// This widget resolves colour + label through [_timelineStatusVisual], which
/// wraps the exact same [BookingStatusVisual.of] factory `BookingStatusBadge`
/// uses — the status→(colour, label) mapping lives in ONE place
/// (`booking_status_badge.dart`), so the badges can never drift apart on what
/// a given [BookingStatus] means, only on how tightly they are drawn. Only the
/// dot-shaped glyph (no icon cap, matching the approved design) and the sizing
/// are specific to this widget. [TimelineStatusDot] — the compact card's
/// label-less variant — reads the same helper, for the reasons set out on it.
class TimelineStatusBadge extends StatelessWidget {
  const TimelineStatusBadge({
    super.key,
    required this.booking,
    this.verticalPadding = 2,
  });

  final Booking booking;

  /// Vertical padding inside the pill. Defaults to 2dp — the compact
  /// timeline row's original budget (see `master_booking_card.dart`'s
  /// class doc; a 30-minute card has no room to spare). [MasterBookingCard]
  /// passes 3dp when this badge sits inside its FULL layout (>=112dp
  /// cards), matching the approved design's own `BookingStatusBadge`
  /// (`booking_widgets.dart`'s `vertical: 3`).
  final double verticalPadding;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ({Color accent, String label}) v = _timelineStatusVisual(
      booking,
      l10n,
    );

    return Semantics(
      label: l10n.bookingStatusSemantics(v.label),
      child: NeumorphicInset(
        radius: VelvetRadii.pill,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: VelvetSpacing.xs + 2,
            vertical: verticalPadding,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                height: 6,
                width: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: v.accent,
                ),
              ),
              const SizedBox(width: VelvetSpacing.xs),
              Flexible(
                child: Text(
                  v.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: VelvetText.masterCardBadgeLabel.copyWith(
                    color: v.accent,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A raised circular gradient avatar with a person glyph — the client's
/// placeholder photo. Transcribed from the design's `_ClientAvatar`
/// (`booking_widgets.dart:295-331`): a two-colour top-left→bottom-right
/// gradient picked deterministically per client via
/// [ClientAvatarGradients.forKey], so the same client always renders the same
/// gradient across rebuilds, screens, and app restarts.
///
/// Compact-timeline pass (2026-07-20): no longer instantiated by
/// [MasterBookingCard] — dropping the avatar row is the main height saving
/// that lets a card fit inside a 45-60 minute timeline slot (see this file's
/// class doc). Deliberately NOT deleted, only unreferenced: kept available
/// for any future non-timeline card that wants the gradient-avatar
/// treatment, per the same design source this was originally transcribed
/// from. `// ignore: unused_element` documents that the dangling reference
/// is intentional, not an oversight — a future caller that wires this back
/// up should drop the ignore.
// ignore: unused_element
class _ClientAvatar extends StatelessWidget {
  const _ClientAvatar({required this.colors});

  /// The client's avatar gradient stops, already resolved via
  /// [ClientAvatarGradients.forKey].
  final List<Color> colors;

  /// Compact-card pass (findings #1/#2/#8): 42dp, down from the design's own
  /// 46dp.
  static const double _diameter = 42;

  /// Hoisted out of [build] (mobile-perf MEDIUM-2): `Color.withValues` is not
  /// a const constructor, so this can't be a `static const`, but computing it
  /// once at class-load time — instead of once per `build()` call — is
  /// exactly the same fix `VelvetText`'s cached statics apply to `TextStyle`s.
  static final Border _border = Border.all(
    color: BrandColors.white.withValues(alpha: 0.35),
    width: 2,
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _diameter,
      width: _diameter,
      // Deliberately shadow-FREE — `impeller_circle_shadow_guard_test.dart`
      // pins this widget (alongside `booking_counterparty_header.dart`'s
      // `_ClientAvatar`) as one of the two circular client-monogram avatars
      // that must never pair `shape: BoxShape.circle` with a `boxShadow`: on
      // Impeller-GLES that combination rasterizes as a hard white square
      // instead of a soft circle. [_border]'s hairline accent stands in for
      // the depth a shadow would otherwise buy.
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        border: _border,
      ),
      child: Center(
        child: Icon(
          Icons.person_rounded,
          color: BrandColors.white.withValues(alpha: 0.82),
          size: 20,
        ),
      ),
    );
  }
}
