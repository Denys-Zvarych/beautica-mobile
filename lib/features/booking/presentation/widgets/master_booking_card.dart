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
// │ Марія Іванюк       09:00–09:30    ●  │  ← who · when · status DOT
// │ ──────────────────────────────────── │  ← hairline (BrandColors.faint)
// │ Стрижка жіноча              450 ₴    │  ← what · how much
// └──────────────────────────────────────┘
//                 54dp
// ```
// (54dp as of the 2026-08-15 font-size pass — was 56dp; see
// [MasterBookingCard.estimatedNaturalHeight]'s doc.)
//
// Row 1 is IDENTITY (who, then when), row 2 is the TRANSACTION (what + how
// much), and the hairline is the same cut [_buildFullBody] makes between
// its client-name row and its service row. That is what earns the word
// "miniature" instead of "shrunk copy".
//
// ROW 1's INTERNAL ORDER WAS SWAPPED 2026-07-24 — client name FIRST, range
// second. Only the COMPACT body changed; [_buildFullBody] and
// [_buildMicroBody] are untouched. The swap moves compact row 1's LEADING
// element onto the same field [_buildFullBody]'s own row 1 opens with (the
// client name), which is the axis the word "miniature" is about; it does
// diverge on where the range lives (full puts it on the service row, below
// the hairline, beside a `schedule_outlined` glyph — compact has no room
// for a second metadata slot and trails it on row 1 instead). See
// [_buildCompactBody]'s row-1 comment for the reading-order rationale.
//
// The text [TimelineStatusBadge] compresses to [TimelineStatusDot] in this
// layout ONLY — the label is what does not fit, so the colour carries the
// signal and the label moves to the `Semantics`/`Tooltip` channel (see that
// widget's doc: colour alone across six statuses is not a signal). The
// >=1h card keeps the labelled pill, unchanged.
//
// OPEN TENSION — the ROW-1 GLYPH pass (2026-07-24) is FULL-ONLY.
// [_buildFullBody]'s client name now opens with a 16dp [_ClientAvatarMark]
// — the client's own photo when the booking carries one, falling back to the
// `person_outlined` glyph the pass originally introduced (see its row-1
// comment); compact row 1's client name has NEITHER, so on this
// one axis the "miniature" claim is currently weaker than it was. That is
// scope, not oversight: the brief was the >=1h card, and compact's own 39dp
// budget (41dp before the 2026-08-15 font-size pass, see "THE 39dp BUDGET"
// below) is at ZERO slack at textScaler 1.0 (the table above), so a 16dp
// glyph against its now-14dp name line box would cost 2dp the layout does
// not have — [MasterBookingCard.estimatedNaturalHeight] would go 54 -> 56 and
// drag the timeline's compact/micro boundary with it. Giving compact the
// glyph is therefore a real density decision (something else on the row
// would have to pay for it), NOT a consistency fix to apply by reflex.
// Pinned meanwhile by `master_booking_card_test.dart`'s "does NOT render on
// the COMPACT body" case so the divergence stays deliberate and visible.
//
// THE 39dp BUDGET, AND WHAT IT COST TO ADD A DIVIDER
// -----------------------------------------------------------------------
// At textScaler 1.0 a 54dp box leaves `54 − 3 (border 1.5 × 2) − 12
// ([_compactPadding] vertical 6 × 2) = 39dp` of content. The stack:
//
//   | row 1     | 14 | [VelvetText.masterCardClientName] 11.5 × 1.2 — the
//   |           |    | tallest child (the range is 12, the dot 8)
//   | gap       |  4 | `VelvetSpacing.xs`
//   | hairline  |  1 |
//   | gap       |  4 | `VelvetSpacing.xs`
//   | row 2     | 16 | the price pill: 14dp line + [_kCompactPriceVPad] × 2
//   | TOTAL     | 39 | = the budget exactly, zero slack at scale 1.0
//
// WAS the 41dp BUDGET until the 2026-08-15 font-size pass (user request:
// "make all fonts of all existed elements in bookings cards a little bit
// lower" — see `velvet_text.dart`'s `masterCardClientName` doc). Row 1 lost
// 1dp (12.5 -> 11.5 sp) and row 2's pill lost 1dp (a new card-scoped
// `VelvetText.masterCardPricePill`, 10.2 sp, vs the shared `pill()`'s 11 sp —
// `pill()` itself is unchanged, since it is also rendered by the wish-list
// and passport screens, which were out of scope; see that token's doc). The
// TABLE and the DIVIDER/HAIRLINE story below it are otherwise unchanged —
// this pass was size-only, no reflow, no reorder, no recolour.
//
// The divider and its two gaps are 9dp of NET-NEW vertical cost the
// outgoing two-row layout did not carry (it measured 55dp natural, back when
// the budget itself was 41dp — see above). The status dot buys WIDTH, not
// height. That 9dp was paid for out of the PRICE PILL's own vertical
// padding — 3dp -> 1dp via [PriceTag]'s new `verticalPadding` knob (default
// 3, so [_buildFullBody] renders byte-identically) — and NOT out of any type
// size: in a card whose whole job is legibility at a glance in a scrolling
// timeline, the type scale is the last thing to cut. 6dp of a 21dp pill was
// air; a recessed well that generously padded is over-articulated at this
// size anyway. (The 2026-08-15 pass above is a SEPARATE, later decision to
// also step the type down — "a little bit" — once the user asked for it
// explicitly; it does not retract this paragraph's original reasoning about
// where the DIVIDER's 9dp came from.)
//
// Zero slack at 1.0 is deliberate and is ASSERTED (`master_booking_card_
// test.dart`'s "the 39dp vertical budget" group) rather than left as a
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
// ## ONE TIME STYLE ACROSS ALL THREE DENSITIES (2026-07-24)
//
// The range is now typeset identically on every body. It was not: the FULL
// card drew it in [VelvetText.masterCardDateFull] (Nunito 11, muted) while
// COMPACT and MICRO drew it in a [VelvetText.masterCardTime] that was an
// independently-declared `bodyStrong` recipe at 11.5 sp in `BrandColors.text`
// — a different base style, a different size AND a different colour, all at
// once. A single lane mixes densities freely (a 30-minute booking sits
// directly under a 90-minute one), so the two recipes were visible side by
// side and read as two unrelated time treatments on one timeline.
//
// The FULL card's recipe won, and the fix is in the TOKEN, not at the call
// sites: [VelvetText.masterCardTime] is now literally
// `masterCardDateFull.copyWith(height: 1.2)`, so there is one source recipe
// and the two can no longer drift apart. Both call sites below still read
// `VelvetText.masterCardTime` and are otherwise untouched — the child ORDER
// of compact row 1 and of the micro row is unchanged, and the full card,
// its `schedule_outlined` glyph included, is byte-identical.
//
// The `height` step-down is the one delta, and it is a LAYOUT knob rather
// than a type choice — see that token's own doc. It exists because this
// card's MICRO body is exactly one text row, so the tallest child's line box
// IS the card's height: `_feedbackBase`'s 1.4 leading would have pushed
// [MasterBookingCard.microLayoutNaturalHeight] to 30dp and left a 15-minute
// booking (a 30dp band) with zero clearance over its own gridline.
//
// TWO GEOMETRY CONSEQUENCES, both MEASURED and both in the safe direction:
// the micro natural fell 29dp -> 28dp (so the timeline's card floor and the
// sub-break-even overrun both shrink, and the break-even duration moves from
// 14.5 to 14.0 minutes), and the range label got NARROWER — 82.9dp rather
// than 86.6dp at the 1.3 textScaler ceiling — which HANDS BACK ~4dp to the
// compact identity row's `Expanded` client name. The compact (56dp) and full
// (117dp at the time; 118 since the ROW-1 GLYPH pass below) naturals did not
// move at all in THIS (2026-07-24) pass: compact row 1's height is set by the
// client name's taller 15dp line box either way. HISTORICAL as of
// 2026-08-15: the font-size pass below (this file's `estimatedNaturalHeight`
// / `fullLayoutNaturalHeight` docs) moved BOTH of these — compact is now
// 54dp, full 115dp. Do not read 56 / 117-118 as current.
//
// Dropping the avatar ROW is the main height saving, not a smaller font pass.
// (The client's PHOTO did later return — but inline, inside row 1's existing
// 16dp glyph footprint, as [_ClientAvatarMark]; that costs zero height by
// construction and is a different thing from the 42dp row discussed here.)
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
//   * The MASTER card's dominant element is the CLIENT's name, which opens
//     the first line with the booking's start–end time range trailing it. It
//     answers "who is coming to me, for what, and for how long".
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
// WHAT DID NOT COME BACK — the design's avatar + master-name ROWS
// -----------------------------------------------------------------------
// The design's `BookingCard` (this file's source of truth,
// `docs/signup-designs/SalonManagementDesign/lib/widgets/
// booking_widgets.dart`) opens with a 42dp client avatar on its own row + a
// master-name row under it. Neither ROW returns here, full layout or not:
// this card renders the INDEPENDENT master's own bookings, so naming which
// teammate served the client (the master-name row's whole purpose) is
// meaningless, and the original compact pass's rationale for dropping the
// avatar row (pure height saving) is orthogonal to whether that height then
// goes to a fuller layout or stays blank — a locked product decision, not a
// pass that ran out of room.
//
// THE PHOTO ITSELF DID COME BACK, AT 16dp (2026-07-24). The backend now
// ships `clientAvatarUrl` on `BookingDetailResponse`, and [_buildFullBody]'s
// row 1 renders it INSIDE the `person_outlined` glyph's existing 16dp box
// via [_ClientAvatarMark] — the glyph demoted to that widget's fallback.
// This is not the design's avatar row returning by the back door and does
// not reopen the decision above: the mark occupies a slot that already
// existed, at a size already paid for, so the body's natural height was
// unchanged BY THIS PASS (measured, not argued — see
// [MasterBookingCard.fullLayoutNaturalHeight], now 115dp after the
// UNRELATED 2026-08-15 font-size pass — that later pass, not this one, is
// what moved the number). The 42dp row, the second identity line and the
// master name all remain out.
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
// Both layouts render whichever form applies via the same [PriceTag], fed
// by the shared `BookingDisplayX.priceLabel` (→ `formatBookingPrice`) so the
// separator (en-dash), rounding and «₴» suffix can never drift from the
// client card or «Деталі запису». The `showsPrice` gate is unchanged and
// applies identically to a band.
//
// [PriceTag] caps its own width and scales down rather than clipping — see
// its doc — because a two-number band is materially wider than the single
// figure this card's compact 54dp layout (56dp before the 2026-08-15
// font-size pass) was originally sized around.
//
// ## THE MICRO LAYOUT (2026-07-24) — A THIRD DENSITY, FOR SLOTS UNDER 54dp
// (56dp before the 2026-08-15 font-size pass)
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
//                  ~28dp
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
// THE 27dp BUDGET: border (1.5 × 2 = 3) + [_MasterBookingCardState.
// _compactPadding]'s vertical 6 × 2 (12) + ONE text row, whose height is the
// tallest of the three children — [VelvetText.masterCardTime] and
// [VelvetText.masterCardService], BOTH Nunito 10 sp (down from 11, 2026-08-15
// font-size pass — see `velvet_text.dart`'s `masterCardClientName` doc) at
// `height: 1.2` and both measuring a 12dp line box, plus the 8dp dot. =
// **27dp** at textScaler 1.0, pinned as
// [MasterBookingCard.microLayoutNaturalHeight]. It is MEASURED, matching
// (not merely close to) the raw token arithmetic this time (10 × 1.2 = 12.0
// exactly — unlike the pre-pass 11 × 1.2 = 13.2 vs measured 13, the smaller
// size happens to land on a whole number). The grid floors its cards at this
// number, so a 15-minute band (`15/60 × 120 = 30dp`) clears it with 3dp to
// spare (was 2dp before the pass).
//
// WAS 28dp (29dp before THAT) UNTIL 2026-08-15, when the font-size pass
// dropped both tied tokens 11 -> 10 sp uniformly, so the row lost another 1dp
// without breaking the tie the 2026-07-24 pass (below) established. WAS 29dp
// UNTIL 2026-07-24, when the range's own style moved onto the FULL card's
// recipe (Nunito 11 muted — see [VelvetText.masterCardTime]'s doc) so all
// three densities read as one time style. The outgoing 11.5 sp recipe
// measured a 14dp line box and made the RANGE the row's tallest child; at 11
// it tied [VelvetText.masterCardService] instead, and the row lost the odd
// dp. Re-measure this number rather than deriving it if either token moves.
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

import 'package:beautica_mobile/core/media/beautica_image.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/core/widgets/price_tag.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';

import '../../domain/booking.dart';
import '../../domain/booking_display_x.dart';
import '../../domain/booking_status.dart';
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
///  * When [minHeight] is omitted (`null`, the default), the card behaves
///    exactly as before: sizes itself to its own natural content height with
///    nothing forced.
///
/// A SECOND non-null-[minHeight] caller, besides `BookingsTimelineGrid`
/// (2026-08 declared-times swap): `DeclaredTimeCards`
/// (`declared_time_cards.dart`) renders a booked EXPLICIT_TIMES entry as this
/// card, unmodified, at a fixed `minHeight: 120` — the FULL body, deliberately
/// (120 clears [fullLayoutMinHeight]), rather than the timeline's own
/// duration-derived floor. That file's free «Вільно» card is floored at the
/// SAME 120 at textScaler 1.0; above 1.0 it tracks THIS card's own growth via
/// that file's `_freeCardMinHeightFor`, so every entry in its list — booked
/// or free — renders the same box at any text scale, not just at 1.0; see
/// that file's `_kEntryMinHeight` doc for the full reasoning.
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
    this.onComplete,
    this.completing = false,
    this.onReview,
  });

  final Booking booking;
  final VoidCallback onTap;

  /// A `BoxConstraints.minHeight` floor on the card's box — see the class
  /// doc. `null` (the default) applies no constraint at all, so the card
  /// sizes to its own natural content height exactly as it did before the
  /// proportional-duration-height pass.
  final double? minHeight;

  /// Phase 231 (master «Архів» page) — an ADDITIVE, optional trailing
  /// «Виконано» action appended below the price/status row, rendered ONLY
  /// on the FULL layout AND ONLY when [Booking.awaitingClosure] is `true`.
  ///
  /// `null` (the default — every call site before this phase, and every
  /// OTHER call site today: `BookingsTimelineGrid`, `DeclaredTimeCards`)
  /// renders NOTHING here — byte-identical to this widget before this field
  /// existed. Only `master_archive_screen.dart` passes a non-null callback.
  ///
  /// Deliberately additive rather than a fork of this widget or a wrapper
  /// composed around it (user-locked decision, 2026-08-16 — "reuse widgets
  /// that already exist... if one widget should be fixed, all other pages
  /// that used this widget will have the fix as well"): the archive needed
  /// this card's client-name-forward full layout, and a second near-
  /// duplicate widget would drift from it the moment either one changed.
  ///
  /// [fullLayoutNaturalHeight]/[occupiedHeightFor] are UNCHANGED by this
  /// field and remain exact for every caller that leaves it `null` — no
  /// current `BookingsTimelineGrid`/`DeclaredTimeCards` row ever sets it, so
  /// their layout math is untouched. A caller that DOES set it renders
  /// taller than [fullLayoutNaturalHeight] by the button's own height; that
  /// is fine for a plain scrolling list (the archive) and would only need
  /// re-deriving if a future TIMELINE consumer ever wanted this action too.
  final VoidCallback? onComplete;

  /// Whether [onComplete]'s write is currently in flight — disables the
  /// button and swaps its label for a spinner. Ignored when [onComplete] is
  /// `null`. Mirrors `NeumorphicButton.loading`'s own contract (the button
  /// this renders internally).
  final bool completing;

  /// Master «Архів» page (2026-08-16) — an ADDITIVE, optional trailing
  /// «Відгук» action appended below the price/status row, rendered ONLY on
  /// the FULL layout AND ONLY when [Booking.status] is
  /// [BookingStatus.completed]. Mirrors [onComplete]'s own additive contract
  /// exactly — see that field's doc for the general shape (`null`, the
  /// default at every OTHER call site, renders nothing here, byte-identical
  /// to this widget before this field existed).
  ///
  /// ## Deliberately NOT gated on [Booking.providerCanReviewClient]
  ///
  /// [Booking.providerCanReviewClient] is the correct, server-computed
  /// "has this client already been reviewed for this booking" flag — but the
  /// backend hardcodes it `false` on every LISTING path
  /// (`BookingService.java`'s `GET /bookings/me`, both the client and
  /// provider rows — see that field's own doc), and only ever computes a real
  /// value on `GET /bookings/{id}`. `master_archive_screen.dart` reads
  /// `GET /bookings/me`, so gating this button on that flag would make it
  /// PERMANENTLY INVISIBLE on this screen, not merely conservative.
  ///
  /// User-locked decision (2026-08-16), made after being shown that
  /// trade-off: show the button on every COMPLETED row regardless of real
  /// reviewability, accepting that a master may tap a booking they already
  /// reviewed and land on `LeaveClientFeedbackScreen`'s "already reviewed"
  /// state. That screen fetches the real per-booking value on open and
  /// pre-gates immediately (no form flash); a submit-time 409 remains as a
  /// backstop for a race — see that screen's file header. Do NOT re-derive
  /// reviewability client-side either
  /// — the real predicate needs "no `ClientReview` exists yet for this
  /// booking", which list data cannot know, and [Booking] itself documents
  /// [providerCanReviewClient] as server-computed, not to be re-derived.
  ///
  /// The proper fix is backend-side: populate a real value on the provider
  /// rows of `GET /bookings/me` too (tracked in
  /// `docs/backend-phases/backlog.md`). **A future reader who "fixes" this by
  /// adding a `booking.providerCanReviewClient` gate here will silently make
  /// this button vanish from the archive — that is this comment's whole
  /// reason for existing.**
  final VoidCallback? onReview;

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
  /// Derivation, post MINIATURE-OF-THE-FULL-CARD pass (this file's "THE 39dp
  /// BUDGET" header section, which carries the same arithmetic in full):
  /// border (1.5 × 2 = 3) + [_MasterBookingCardState._compactPadding]'s
  /// vertical 6 × 2 (12) + row 1 (14, the client name — the tallest of the
  /// range label / name / dot) + a `VelvetSpacing.xs` gap (4) + the hairline
  /// (1) + a second `VelvetSpacing.xs` gap (4) + row 2 (16, the price pill:
  /// a 14dp line box plus [_MasterBookingCardState._kCompactPriceVPad] × 2)
  /// = **54dp exactly**.
  ///
  /// FONT-SIZE PASS (2026-08-15) — was 56dp. User request: "make all fonts of
  /// all existed elements in bookings cards a little bit lower" — see
  /// `velvet_text.dart`'s `masterCardClientName` doc. Re-MEASURED, not
  /// computed from the token arithmetic alone (this file's own long-standing
  /// warning that the two can disagree): a widget test rendered the real card
  /// at textScaler 1.0 and read `tester.getSize(...)`. Row 1 dropped 15 -> 14
  /// (`masterCardClientName` 12.5 -> 11.5 sp), row 2's pill dropped 17 -> 16
  /// (`masterCardPricePill` — a new, card-scoped 10.2 sp token, since the
  /// price pill's own `pill()` recipe is shared with the wish-list/passport
  /// screens and stayed put — see that token's doc). NOT a rounded-up
  /// estimate: the layout still spends its ENTIRE budget with zero slack —
  /// 39dp of content in a 54dp box, same invariant as before the pass, just a
  /// smaller box. Pinned by `master_booking_card_test.dart`'s "the 39dp
  /// vertical budget" group. Above textScaler 1.0 the real card is TALLER
  /// than this (measured 58dp at 1.15, 62dp at 1.3) and the box grows to meet
  /// it — [minHeight] is a floor, never a ceiling.
  ///
  /// Row 2's 16dp term is the price pill, and that pill's height is pinned
  /// independently of its horizontal `BoxFit.scaleDown` — see [PriceTag]'s
  /// zero-width height anchor. Without that anchor a band wide enough to hit
  /// the pill's width cap would have scaled the pill's HEIGHT down with it
  /// (uniform fit), silently dragging the compact card below this figure.
  static const double estimatedNaturalHeight = 54;

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
  /// `VelvetSpacing.xs + 2` + the price/badge row = **115dp**.
  ///
  /// FONT-SIZE PASS (2026-08-15) — was 118dp; re-MEASURED (widget test,
  /// `tester.getSize` at textScaler 1.0), not computed from the token
  /// arithmetic — see `velvet_text.dart`'s `masterCardClientName` doc for the
  /// pass and [estimatedNaturalHeight] for the same caveat on the compact
  /// body. The three rows: client-name row 16dp (the 16dp
  /// [_ClientAvatarMark] STILL beats [VelvetText.masterCardClientNameFull]'s
  /// now-14dp line box — was 15dp before the pass, so the glyph's margin over
  /// the text widened, not narrowed), service/time row 17dp
  /// ([VelvetText.masterCardServiceFull]'s 17dp line box, down from a
  /// previously-larger box but still the row's tallest child over the 14dp
  /// range and the 12dp `schedule_outlined` glyph), price/badge row 20dp
  /// ([PriceTag] rendered in [VelvetText.masterCardPricePill] at
  /// [PriceTag.defaultVerticalPadding] — still taller than
  /// [TimelineStatusBadge]'s 15dp). Full sum: 3 + 32 + 16 + 10 + 1 + 10 + 17 +
  /// 6 + 20 = 115.
  ///
  /// WAS 117 UNTIL 2026-07-24, when row 1 gained its leading
  /// `person_outlined` glyph (see [_buildFullBody]'s row-1 comment for the
  /// design rationale). The glyph is 16dp against
  /// [VelvetText.masterCardClientNameFull]'s then-15dp line box, so it became
  /// the client-name row's tallest child and took that row 15 -> 16dp. THEN
  /// 118 until the 2026-08-15 font-size pass above dropped the OTHER two rows
  /// (service/time, price/badge) by 3dp combined while row 1 stayed
  /// glyph-pinned at 16 — net **118 -> 115**.
  ///
  /// STILL GLYPH-PINNED at 16dp for row 1 after the CLIENT-PHOTO pass and the
  /// 2026-08-15 font-size pass alike. Row 1's leading slot is
  /// [_ClientAvatarMark] (photo when the booking has one, the glyph when it
  /// does not), and that widget renders an exactly 16 x 16dp box in ALL FOUR
  /// of its states — loaded, loading, errored and null — precisely so this
  /// constant's row-1 term could not move on its own. See that widget's
  /// "SIZE INVARIANT" section: it exists because of the clearance arithmetic
  /// below.
  ///
  /// ONLY AT 1.0. `Icon` does not scale with `textScaler`, and the
  /// 2026-08-15 pass narrowed [VelvetText.masterCardClientNameFull]'s margin
  /// under the glyph, not widened it, so row 1's own tallest-child winner now
  /// changes ACROSS the scale sweep where it never used to: 16dp (glyph wins)
  /// at 1.0, a 16dp TIE at 1.15 (glyph == text, both 16), then 18dp (text
  /// wins) at 1.3. Re-measured (not assumed) full-body naturals: **115 / 120
  /// / 126dp** at 1.0 / 1.15 / 1.3 (was 118 / 124 / 132).
  ///
  /// THE TIMELINE CONSEQUENCE, and why this did not need `_kHourH` to move:
  /// this constant IS [_MasterBookingCardState._kFullLayoutMinHeight], the
  /// full/compact switch, so the threshold FELL with it. A 60-minute booking
  /// is floored at `BookingsTimelineGrid._kHourH` (120dp), which clears 115 —
  /// the margin is now **5dp, up from 2** — and the exact boundary duration
  /// moved `59.0` -> `57.5` minutes (`115 / 120 × 60`). A 58-minute booking
  /// (floor 116dp) now selects the full body with 1dp clearance; a 57-minute
  /// one (floor 114dp) stays on the compact grid. Re-measure before adding a
  /// sixth term to [_buildFullBody].
  ///
  /// Pinned by `master_booking_card_test.dart`'s "the FULL body still
  /// measures exactly 115dp at textScaler 1.0" case, and — as the input to
  /// [occupiedHeightFor] — by `master_booking_card_layout_height_test.dart`,
  /// which renders the real card at every floor the timeline can produce and
  /// asserts the prediction matches to the pixel.
  ///
  /// TEXT SCALE 1.0 ONLY. The same measurement is 120dp at 1.15 and 126dp at
  /// 1.3, so any caller predicting a box from this constant MUST gate itself
  /// on `MediaQuery.textScalerOf(context).scale(1) <= 1.0` — see
  /// `bookings_timeline_grid.dart`'s "ADDENDUM 5". NOTE (2026-08-15): the
  /// 120dp @1.15 value happens to equal `declared_time_cards.dart`'s
  /// `_kEntryMinHeight` (also 120) — see that file's `_freeCardMinHeightFor`
  /// doc for the consequence (the booked/free floor now ties at 1.15 instead
  /// of the booked card leading).
  static const double fullLayoutNaturalHeight = 115;

  /// [_buildMicroBody]'s natural rendered height at textScaler 1.0 — the third
  /// layout's counterpart to [estimatedNaturalHeight] /
  /// [fullLayoutNaturalHeight], and exact for the same reason (one row of
  /// single-line children, so lane width moves the ellipsis, never the height).
  ///
  /// Derivation, in full on the class doc's "THE MICRO LAYOUT" section:
  /// border (1.5 × 2 = 3) + [_MasterBookingCardState._compactPadding]'s
  /// vertical 6 × 2 (12) + the row's tallest child — since the ONE-TIME-STYLE
  /// pass (2026-07-24) the time range ([VelvetText.masterCardTime]) and the
  /// service name ([VelvetText.masterCardService]) are both Nunito at
  /// `height: 1.2` and TIE at a 12dp line box (10 sp as of the 2026-08-15
  /// font-size pass, down from 11 — see `velvet_text.dart`'s
  /// `masterCardClientName` doc), comfortably over the 8dp status dot =
  /// **27dp**.
  ///
  /// FONT-SIZE PASS (2026-08-15) — was 28dp. Re-MEASURED, not computed: a
  /// 13dp line box at 11 sp became a 12dp line box at 10 sp (both round
  /// numbers here, unlike the pre-2026-07-24 11.5 sp recipe, which is why the
  /// unrounded arithmetic and the measured figure now agree exactly — 3 + 12
  /// + 12 = 27 with nothing left over).
  ///
  /// 27, not 28.2 nor any other unrounded-arithmetic figure, and was 29 until
  /// the 2026-07-24 pass moved the range off its old 11.5 sp recipe. It is a
  /// MEASURED number: `bookings_timeline_grid.dart`'s `_cardMinHeightFor`
  /// floors every card at it and [occupiedHeightFor] predicts real boxes from
  /// it, so it has to be what the card actually renders rather than what the
  /// type tokens multiply out to — measured identical (27.0) at 226 / 266 /
  /// 272dp of lane. Pinned by `master_booking_card_test.dart`'s "the MICRO
  /// body measures exactly 27dp" case and, as an [occupiedHeightFor] input,
  /// by `master_booking_card_layout_height_test.dart`.
  ///
  /// TEXT SCALE 1.0 ONLY, exactly as [fullLayoutNaturalHeight]. Re-measured
  /// (this pass) at 29dp @1.15 and 31dp @1.3 — no prior doc published these
  /// two figures to compare against.
  static const double microLayoutNaturalHeight = 27;

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
  /// at `120dp/hour` has a `20dp` wall-clock band, a `27dp` floor (was `28dp`
  /// before the 2026-08-15 font-size pass), and a `27dp` real box.
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

  /// Phase 231 mobile-perf LOW fix — memoized cache of [_buildFullBody]'s
  /// "static" content (identity row / hairline / service row / price+badge
  /// row), keyed by the [Booking] (freezed, value-`==`) it was built from.
  ///
  /// [widget.completing] toggling is a constructor-field change, so Flutter
  /// ALWAYS reruns this `State`'s `build()` when it flips (a `StatefulElement`
  /// calls `didUpdateWidget` then unconditionally rebuilds — there is no
  /// field-level short-circuit). That is unavoidable and fine; what this
  /// cache avoids is the DESCENDANT rebuild it would otherwise cascade into:
  /// [_buildFullBody] hands back the exact same content `Widget` INSTANCE
  /// when only [widget.completing] changed (the booking is unchanged), and
  /// Flutter's own `updateChild` skips rebuilding an element entirely when
  /// `identical(oldWidget, newWidget)` — the same trick `AnimatedBuilder`'s
  /// `child` parameter relies on. Only the trailing «Виконано» button slot
  /// (built fresh every call — cheap, one `NeumorphicButton`) actually reads
  /// [widget.completing].
  Widget? _fullBodyContentCache;
  Booking? _fullBodyContentCacheBooking;

  /// The `clientName` [_fullBodyContent] was built from, alongside
  /// [_fullBodyContentCacheBooking] — see that field's doc for the caching
  /// mechanism.
  ///
  /// `clientName` is computed one level up, in [build] (`b.clientName ??
  /// l10n.bookingDetailGuestClient`), so it is baked into the cached
  /// [Column] as a plain `String` on a guest booking rather than re-read
  /// from context by a leaf widget. [Booking] value-equality alone therefore
  /// under-keys the cache: an unchanged guest [Booking] with a locale change
  /// (`bookingDetailGuestClient` resolving to a different string) would
  /// return the stale cached widget, and Flutter's `identical()`
  /// short-circuit in `updateChild` would skip reconciling that subtree
  /// entirely, leaving the old locale's fallback on screen. This field
  /// closes that gap.
  String? _fullBodyContentCacheClientName;

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
  /// Equal to [MasterBookingCard.fullLayoutNaturalHeight] (`115dp`, the full
  /// body's own natural floor at textScaler 1.0 — was `118dp` before the
  /// 2026-08-15 font-size pass, see that constant's doc): a booking whose
  /// duration-derived floor reaches `115dp` or more gets the fuller layout;
  /// anything shorter stays on the compact grid.
  ///
  /// ## WHICH DURATIONS REACH IT — RE-DERIVE THIS, NEVER QUOTE IT
  ///
  /// The threshold itself is stable (the full body's own natural floor, so a
  /// card takes the fuller shape exactly when its ruled band can contain it
  /// without overhang), but WHICH durations clear it is a function of
  /// `BookingsTimelineGrid._kHourH`, which has now moved three times, AND of
  /// the threshold's own value, which the 2026-08-15 font-size pass moved for
  /// the first time (118 -> 115). At the current `120dp/hour` (that file's
  /// "ADDENDUM 8") against the current `115dp` threshold:
  ///
  ///   * `>= 58` min — floor `>= 116dp`, clears `115`: FULL layout. The exact
  ///     boundary duration is now `57.5` min (`115 / 120 × 60`), so a
  ///     58-minute booking sits at `1dp` clearance and an hour-long one `5dp`
  ///     clear (both up from the pre-pass `0dp` / `2dp` — the threshold fell,
  ///     the floor did not) — which is why `_kHourH` cannot drop below `120`
  ///     without moving this threshold too.
  ///   * `27`-`57` min — floor `54`-`114dp`: COMPACT grid.
  ///   * `< 27` min — floor below the compact body's own `54dp` natural
  ///     (`54 / 120 × 60 = 27` exactly): MICRO, the single row (see this
  ///     file's "THE MICRO LAYOUT" section).
  ///
  /// Two earlier revisions of this doc asserted a 45-minute answer, in
  /// opposite directions (`112` → compact, `168` → full). At `120` it is
  /// compact again (`45/60 × 120 = 90dp`), and the 2026-08-15 threshold drop
  /// does not change that (`90dp` is still well under `115`). The lesson
  /// recorded here rather than the answer: this list is DERIVED, and any
  /// `_kHourH` OR `fullLayoutNaturalHeight` change invalidates it wholesale.
  ///
  /// [_buildFullBody]'s NATURAL height (the same fixture the compact sweeps
  /// use — a long service name, a frozen RANGE band, a full client name)
  /// measures 115dp at textScaler 1.0 (120dp at 1.15, 126dp at 1.3 — was 118 /
  /// 124 / 132 before the 2026-08-15 pass); it is identical at 226 / 266 /
  /// 272dp of lane because every row is flex-driven, so lane width moves the
  /// ellipsis, never the height.
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
  /// against [PriceTag]'s own 3dp default which [_buildFullBody] keeps.
  ///
  /// This 4dp (2 × 2) is exactly what paid for the hairline divider and its
  /// two `VelvetSpacing.xs` gaps — see this file's "THE 39dp BUDGET" (was
  /// "THE 41dp BUDGET" before the 2026-08-15 font-size pass) header section.
  /// At the time this padding split was chosen (2026-07-21), it was spent on
  /// the pill rather than on a type step-down on purpose: 6dp of the pill's
  /// 21dp was air, and a recessed well padded for a 112dp card is
  /// over-articulated inside a 56dp one, whereas shrinking the type would
  /// have cost the card legibility-at-a-glance.
  ///
  /// THAT REASONING NO LONGER APPLIES AS STATED — the 2026-08-15 pass DID
  /// step every token on this card down (user request, "a little bit lower");
  /// this padding split is simply unrelated to that later, separate decision
  /// and was not reverted by it. Both economies coexist: the padding still
  /// pays for the divider, and the type is now also a step smaller. See
  /// `velvet_text.dart`'s `masterCardClientName` doc for the font-size pass.
  static const double _kCompactPriceVPad = PriceTag.compactVerticalPadding;

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
  // safety on that row is structural, not arithmetic — see [PriceTag]'s
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
  /// `null` — the default at every call site — is COMPACT, not micro: it
  /// means "no constraint", not "a very tight one". `DeclaredTimeCards`
  /// (`declared_time_cards.dart`) is a second non-null-[minHeight] caller
  /// besides `BookingsTimelineGrid` — see [minHeight]'s own doc — and passes
  /// a fixed `120`, which resolves to FULL here, deliberately.
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

  /// The MINIATURE of [_buildFullBody] — identity row (client name ·
  /// start–end range · status dot), a hairline, then the transaction row
  /// (service name · price). The only shape proven to fit a 30-minute (54dp,
  /// was 56dp before the 2026-08-15 font-size pass) slot without clipping.
  /// See this file's "The compact layout is a
  /// MINIATURE OF THE FULL CARD" and "THE 41dp BUDGET" header sections.
  Widget _buildCompactBody(Booking b, String clientName) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // ROW 1 — IDENTITY: who, then when, then the status dot hard right.
        //
        // SWAPPED 2026-07-24 (compact ONLY — [_buildFullBody] and
        // [_buildMicroBody] are untouched). The row previously LED with the
        // range and trailed the name; the current order is the reverse.
        //
        // Reading order is deliberate: the heavier client name
        // ([VelvetText.masterCardClientName], Comfortaa 12.5 in
        // `BrandColors.text`) LEADS the lighter range label
        // ([VelvetText.masterCardTime] — since 2026-07-24 the FULL card's own
        // range recipe, Nunito 11 in `BrandColors.muted`), so the row reads
        // headline-then-metadata — "this person, at this hour" — rather than
        // as two cells of a table. The muted range widens that weight
        // gradient rather than flattening it. Two things make that the right
        // way round HERE rather than a coin flip:
        //
        //   * a compact card already sits on its own start gridline, so the
        //     timeline's geometry answers "when" before the label does — the
        //     range is CONFIRMING metadata, and metadata trails. That is the
        //     same argument [_buildMicroBody] makes for putting its own
        //     range on the right, so the two densities now share one
        //     trailing cluster: flexing text · 6 · range · 4 · dot.
        //   * the name is the field a master actually scans a day timeline
        //     for, and it is the one thing the card's POSITION cannot encode.
        //     Leading with it also puts compact row 1's first element on the
        //     same field [_buildFullBody]'s row 1 opens with, so a lane of
        //     mixed-density cards reads as one left column of client names.
        //
        // The weight gradient still runs (heavy -> light now, not light ->
        // heavy) and is still one of the three things keeping this card off
        // the squashed-grid failure mode; the other two are unchanged — the
        // hairline's semantic cut (identity above, transaction below, the
        // same cut [_buildFullBody] makes) and the diagonal formed by the dot
        // at top-right against the price pill at bottom-right, with the
        // flexing text running between them.
        //
        // BOTH GAPS KEEP THE VALUES THE PRE-SWAP ROW USED, so the width
        // arithmetic below is unchanged term for term: `VelvetSpacing.xs + 2`
        // (6dp) separates the identity headline from the metadata cluster,
        // and the tighter `VelvetSpacing.xs` (4dp) holds the dot against it.
        //
        // NO `LayoutBuilder` AND NO PRICE RESERVE ON THIS ROW — it cannot
        // overflow on its own, and the swap does not change that: a `Row`
        // allots its flex child the space its non-flex siblings do not take
        // REGARDLESS of their order. The non-flex content is still the range
        // label (82.9dp at the 1.3 textScaler ceiling — RE-MEASURED after the
        // 2026-07-24 one-time-style pass moved it from 11.5 sp to the full
        // card's 11 sp recipe, down from 86.6dp), two fixed gaps (6 + 4) and
        // an 8dp dot = 100.9dp against the narrowest lane's 203dp of inner
        // width (`320 − 94` lane, less 2 × 1.5 border and [_compactPadding]'s
        // 2 × 10 horizontal), leaving the `Expanded` client name ~102dp —
        // ~4dp MORE than the outgoing recipe left it, so that pass could only
        // relieve this budget, never tighten it. The `Expanded` stays on the
        // NAME — it is the
        // variable-length field and already carries `maxLines: 1` + ellipsis,
        // whereas the range is fixed-width and must never truncate. The
        // outgoing layout needed a capped pill here precisely because the
        // PRICE shared this row; moving it to row 2 is what removed the
        // constraint.
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: Text(
                clientName,
                style: VelvetText.masterCardClientName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: VelvetSpacing.xs + 2),
            Text(
              formatSlotTimeRange(b.startAt, b.endAt),
              style: VelvetText.masterCardTime,
            ),
            // Tight gap on purpose: the dot must read as ATTACHED to this
            // booking's own metadata — a status about this appointment —
            // rather than floating in a third column on the right margin.
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
        // ABOVE [PriceTag.maxTextWidth]'s own 112dp ceiling, so it never
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
        // OVERFLOW SAFETY IS STRUCTURAL, NOT ARITHMETIC: [PriceTag] caps its
        // own text at [PriceTag.maxTextWidth] and wraps it in a `Flexible` +
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
              // which [PriceTag]'s own `Flexible` + [PriceTag.maxTextWidth]
              // resolve to the identical 112dp ceiling the inert 135dp cap
              // used to sit above. Making it `Flexible` here would NOT be
              // equivalent — it would split the free space with the service
              // name's `Expanded` instead of leaving the remainder to it.
              PriceTag(
                price: b.priceLabel,
                verticalPadding: _kCompactPriceVPad,
                style: VelvetText.masterCardPricePill,
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// The design's fuller layout — the client name (led by a 16dp
  /// [_ClientAvatarMark]: the client's photo when the booking carries one,
  /// else the accent `person_outlined` glyph), a hairline divider, the service
  /// name (below the divider, with the design's accent
  /// `spa_outlined` glyph) paired with the booking's start–end time range
  /// (date-free — see this file's "The time is a RANGE" header section), then
  /// price + status. Only ever built once [build] has already confirmed the
  /// box is >= [_kFullLayoutMinHeight] — see this file's "Adaptive
  /// full/compact layout" header section. Still has NO 42dp avatar ROW and NO
  /// master-name row — see that same section's "WHAT DID NOT COME BACK", which
  /// the 16dp inline mark does not reopen.
  Widget _buildFullBody(Booking b, String clientName) {
    final Widget content = _fullBodyContent(b, clientName);
    // See [MasterBookingCard.onComplete] / [MasterBookingCard.onReview]'s
    // docs — both additive, independently-gated slots. Structurally these
    // two conditions can never both be true on the same [Booking]:
    // [Booking.awaitingClosure] requires `status == BookingStatus.confirmed`
    // (see that field's own doc), while [showReview] requires
    // `status == BookingStatus.completed` — one [Booking.status] value
    // cannot satisfy both at the same time. Both branches are still
    // independent `if`s below (not an if/else) so a future relaxation of
    // either gate degrades to "both render, stacked" rather than "one
    // silently wins and the other vanishes".
    final bool showComplete = widget.onComplete != null && b.awaitingClosure;
    final bool showReview =
        widget.onReview != null && b.status == BookingStatus.completed;
    if (!showComplete && !showReview) return content;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        content,
        // Phase 231 — the ADDITIVE «Виконано» slot. See
        // [MasterBookingCard.onComplete]'s doc for why this lives here
        // rather than in a composed-around wrapper. Deliberately built
        // OUTSIDE [_fullBodyContent]'s cache — it is the one part of this
        // body that genuinely depends on [widget.completing], so it is the
        // only part that must rebuild when that flag flips (see
        // [_fullBodyContentCache]'s doc).
        if (showComplete)
          Padding(
            padding: const EdgeInsets.only(top: VelvetSpacing.xs),
            child: NeumorphicButton(
              key: Key('master-booking-card-complete-${b.id}'),
              label: AppLocalizations.of(context).bookingDetailCompleteCta,
              icon: Icons.check_circle_rounded,
              loading: widget.completing,
              onPressed: widget.completing ? null : widget.onComplete,
            ),
          ),
        // Master «Архів» page — the ADDITIVE «Відгук» slot. See
        // [MasterBookingCard.onReview]'s doc for the gating rationale.
        // Deliberately OUTSIDE [_fullBodyContent]'s cache for the same
        // reason as the «Виконано» slot above: it is built fresh every call
        // rather than baked into the memoized, `identical()`-shortcut
        // subtree, so a caller that flips [onReview] (null <-> non-null)
        // between rebuilds of an otherwise-unchanged [Booking] is never
        // silently skipped by Flutter's `updateChild` identity check.
        if (showReview)
          Padding(
            padding: const EdgeInsets.only(top: VelvetSpacing.xs),
            child: NeumorphicButton(
              key: Key('master-booking-card-review-${b.id}'),
              label: AppLocalizations.of(context).masterArchiveReviewCta,
              icon: Icons.rate_review_outlined,
              onPressed: widget.onReview,
            ),
          ),
      ],
    );
  }

  /// The identity/hairline/service/price content shared by every
  /// [_buildFullBody] call — see [_fullBodyContentCache]'s doc for why this
  /// is split out and memoized rather than inlined.
  Widget _fullBodyContent(Booking b, String clientName) {
    final Widget? cached = _fullBodyContentCache;
    if (cached != null &&
        _fullBodyContentCacheBooking == b &&
        _fullBodyContentCacheClientName == clientName) {
      return cached;
    }
    final Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // Row 1 — client identity: a `person_outlined` glyph leading the
        // client's name.
        //
        // THE GLYPH TAKES THE 16dp/ACCENT REGISTER, NOT THE 12dp/MUTED ONE
        // (2026-07-24)
        // ---------------------------------------------------------------
        // This body runs a TWO-TIER glyph system, and the tiers are about
        // a field's RANK, not its row: 16dp in [BrandColors.accent] marks the
        // field that OPENS a row and owns it (row 2's `spa_outlined` + the
        // service name), 12dp in [BrandColors.muted] marks a trailing
        // metadata cluster (row 2's `schedule_outlined` + the time range).
        // The client name is this card's PRIMARY identity field — the whole
        // reason the master is reading the row — so the muted register would
        // have inverted the hierarchy outright, printing a fainter mark on
        // the name than on the service below it. A third size (14dp, which
        // would have fitted inside the name's 15dp line box and dodged the
        // 1dp growth below) was rejected for the same reason it is tempting:
        // three sizes across three fields stop reading as a system at all,
        // and "it saves a constant bump" is not a design argument.
        //
        // IT ALSO BUYS A LEFT RAIL — the real gain, and not decoration.
        // Rows 1 and 2 now open with a 16dp glyph at the same x, so their
        // TEXT starts on one column (`16 + VelvetSpacing.sm` in from the
        // padding edge) instead of the ragged left this body had, where the
        // client name began hard against the padding and the service name
        // 24dp inside it. The hairline now cuts across a two-column grid
        // rather than a full-bleed block.
        //
        // COST, MEASURED: the glyph is 1dp taller than
        // [VelvetText.masterCardClientNameFull]'s 15dp line box at textScaler
        // 1.0, so it becomes this row's tallest child and moved
        // [MasterBookingCard.fullLayoutNaturalHeight] 117 -> 118. `Icon` does
        // NOT scale with `textScaler`, so at 1.15 (17dp line box) and 1.3
        // (20dp) the text still wins and those two naturals are UNCHANGED at
        // 124 / 132. See that constant's doc for the timeline consequence.
        //
        // The glyph is DECORATIVE: the client name is already announced by
        // the card's `Semantics(label:)` (`masterBookingCardSemantics`), so
        // `semanticLabel` is deliberately left null — naming it here would
        // announce the same person twice.
        //
        // THE GLYPH IS NOW THE FALLBACK, NOT THE ONLY STATE (2026-07-24)
        // ---------------------------------------------------------------
        // The backend ships `clientAvatarUrl` on `BookingDetailResponse`, so
        // when the booking's client has a photo it renders HERE, inside the
        // very same 16dp box, and the `person_outlined` glyph above becomes
        // the fallback for the four cases that have no usable photo. See
        // [_ClientAvatarMark] for the size invariant, the https guard and the
        // four states — the one thing that must never change is that this
        // slot measures 16 × 16dp in EVERY state, because
        // [MasterBookingCard.fullLayoutNaturalHeight] (118) has zero
        // clearance at 59 minutes and only 2dp at 60.
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            _ClientAvatarMark(avatarUrl: b.clientAvatarUrl),
            const SizedBox(width: VelvetSpacing.sm),
            // `Expanded`, because this is a `Row` now: an unbounded child
            // would make `maxLines: 1` + `ellipsis` inert and let a long
            // client name overflow instead of truncating.
            Expanded(
              child: Text(
                clientName,
                style: VelvetText.masterCardClientNameFull,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
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
        // This row used to be `PriceTag` + `Spacer` + badge, i.e. TWO
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
        // real bounded constraint, and [PriceTag]'s inner `Flexible` scales
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
                  child: PriceTag(
                    price: b.priceLabel,
                    style: VelvetText.masterCardPricePill,
                  ),
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
    _fullBodyContentCache = content;
    _fullBodyContentCacheBooking = b;
    _fullBodyContentCacheClientName = clientName;
    return content;
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
    // ~226x54dp card (was 56dp before the 2026-08-15 font-size pass): a
    // deliberate long-press on the status dot asks "what is
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

/// The 16dp mark that OPENS [_MasterBookingCardState._buildFullBody]'s row 1 —
/// the booking client's own photo when there is one, and the
/// `person_outlined` glyph that used to be the only thing here when there is
/// not.
///
/// ## THE SIZE INVARIANT — read this before touching anything below
///
/// This widget renders a box of EXACTLY [_kSize] × [_kSize] dp in all four
/// states. Not "about", not "at most": exactly, and in the error and loading
/// states too. The full body has effectively no vertical headroom —
/// [MasterBookingCard.fullLayoutNaturalHeight] is 115dp (was 118dp before the
/// 2026-08-15 font-size pass — see that constant's own doc) against
/// `BookingsTimelineGrid._kHourH`'s 120dp/hour, so a 58-minute booking's floor
/// is 116 (1dp clearance) and an hour-long one's is 120 (5dp). Row 1's height
/// IS this mark's height (16dp beats the client name's now-14dp line box at
/// textScaler 1.0 — that margin WIDENED in the 2026-08-15 pass, from a 15dp
/// line box, so the glyph's grip on this row got firmer, not weaker), so one
/// stray dp here would still silently demote hour-long bookings to the
/// compact layout if it ever pushed row 1 taller than the icon. The size is
/// pinned from the OUTSIDE by `master_booking_card_test.dart`'s
/// interior-headroom assertion, which a `minHeight` floor cannot pad away
/// (re-measured for the new 115dp natural — see that test's own value).
///
/// That is why the photo goes INSIDE the glyph's footprint rather than beside
/// it or scaled up to a conventional avatar size, and why every state below
/// resolves to the same [SizedBox].
///
/// ## THE FOUR STATES
///
///   * **loaded** — the photo, `BoxFit.cover`-clipped to a 16dp disc with a
///     hairline camel ring (see [_kRingAlpha]).
///   * **loading** — the FALLBACK GLYPH, swapped for the photo on the first
///     decoded frame. Deliberately not a spinner, not a shimmer and not a
///     blank hole: at 16dp a progress affordance is illegible chrome, and a
///     hole would break the left rail that rows 1 and 2 form by opening on the
///     same x (see row 1's "IT ALSO BUYS A LEFT RAIL" note). Showing the
///     already-correct fallback means the row is never in a state a master
///     cannot read, and the swap is a repaint of one 16dp disc — no relayout,
///     because the box is fixed either way. No cross-fade: it would cost an
///     animation ticker per card across up to ~100 cards in a scrolling
///     timeline, to soften a transition the size of a fingernail.
///   * **error** (dead URL, 404, offline, malformed image) — the glyph, via
///     `errorBuilder`. A booking row must never degrade into a broken-image
///     box.
///   * **null / non-https** — the glyph, without ever touching the network.
///
/// ## THE https GUARD — mirrored, not invented
///
/// `Image.network` builds its own `HttpClient`; it does NOT go through the
/// app's pinned Dio or any of its interceptors. So the scheme is checked here,
/// exactly as `ResultThumbnail` (`features/discovery`) and `_MasterPhoto`
/// (`booking_card.dart`, the closest sibling — a booking card rendering a
/// remote avatar) already do: anything that is not `https` falls to the glyph
/// rather than being requested, so a compromised or downgraded `http://` URL
/// cannot leak the master's IP in cleartext if ATS/NSC is ever relaxed.
/// `clientAvatarUrl` is a public R2 object URL and carries no credential of
/// its own — see `Booking.clientAvatarUrl`.
///
/// ## SEMANTICS — deliberately silent
///
/// `excludeFromSemantics: true`. The client's name is already announced by the
/// card's own `Semantics(label:)` (`masterBookingCardSemantics`), and the
/// glyph this replaces was decorative for that same reason. Left at the
/// default, `Image` emits an `image`-flagged node into the card's subtree —
/// a second, empty announcement inside a button that already reads its
/// person's name, and a place a URL could later leak into the a11y tree.
///
/// ## CACHING
///
/// Nothing is added here on purpose. Flutter's own `ImageCache` keys on the
/// `ResizeImage(NetworkImage(url), …)` this builds, so the same client on
/// three bookings in one day resolves to ONE key: one fetch, one decode,
/// shared by all three — and cards re-entering the timeline's culling window
/// hit the cache rather than the network. It is memory-only (no disk tier),
/// so the cost is one GET per distinct client per app session.
///
/// ## MEMORY — why BOTH axes are bound, and why the policy is `fit`
///
/// The decode is sized to the physical pixels this 16dp disc occupies, not to
/// the R2 object's native resolution. That much is obvious; the two non-obvious
/// parts are below, and both were mobile-perf findings.
///
/// **Both axes, not just width.** `ResizeImagePolicy` constrains only the axes
/// you give it: with `width` alone the other dimension is whatever the source's
/// aspect ratio implies, so the footprint is unbounded in height. A 1:10 source
/// decodes to `side × 10·side` — an order of magnitude over budget — and
/// `BoxFit.cover` then throws almost all of it away. Binding both axes makes
/// the ceiling `(16 · devicePixelRatio)² × 4` bytes REGARDLESS of source shape:
/// ~7KB at DPR 2.625, ~9KB at DPR 3, ~16KB at DPR 4. (The pre-2026-07-24 doc
/// claimed a flat "~9KB"; that was only ever true for a square source at DPR 3.)
///
/// **`fit`, not `exact`.** With both axes set, `ResizeImagePolicy.exact` is
/// `BoxFit.fill` at decode time — it would squash a 3:4 phone photo into a
/// square before `BoxFit.cover` ever sees it. Avatars are uploaded through
/// `file_picker` with no crop step and are stored byte-for-byte, so non-square
/// sources are the NORM here, not the edge case. `fit` scales the source down
/// until it fits inside `side × side` with its aspect ratio intact; `cover`
/// then crops as it always did. The cost is that `cover` resamples the short
/// axis up a little (≈1.3× for 3:4, ≈1.75× for 9:16) — invisible on a 16dp
/// disc under a ring, and strictly cheaper than the old width-only decode in
/// the common case (32×42 rather than 42×56).
///
/// ## ANIMATED SOURCES — pinned to frame 0
///
/// The backend's `MediaService.MIME_TO_EXT` accepts `image/webp`, sniffs MIME
/// from magic bytes, and neither transcodes nor re-encodes on upload — and
/// animated WebP shares the RIFF/WEBP signature with still WebP. So a client
/// CAN upload an animated avatar today, and it would land here.
///
/// `ResizeImage` does not flatten animation: a multi-frame codec still yields a
/// `MultiFrameImageStreamCompleter`, which re-arms a `Timer` after every frame
/// for as long as `repetitionCount == -1` (the usual "loop forever"). Neither
/// the 16dp box nor the decode bounds above suppress it. One shared completer
/// per URL, but a `setState` and a repaint in EVERY card listening to it, all
/// day, for a decorative fingernail-sized disc.
///
/// `TickerMode(enabled: false)` is Flutter's own documented answer (see
/// `Image`'s class doc: "If the animation is paused when the image first loads,
/// the first frame will be displayed and then animation will stop"). `_ImageState`
/// reads it in `didChangeDependencies`, and on the first delivered frame calls
/// `_stopListeningToStream(keepStreamAlive: true)`. Dropping that listener takes
/// the completer to `hasListeners == false`, which cancels its timer — the
/// `keepAlive` handle it leaves behind is a separate counter and does NOT re-arm
/// the loop. Net: frame 0 renders, the decode loop never starts, the cache entry
/// stays warm.
///
/// This is public API and one widget deep — deliberately NOT a custom
/// `ImageProvider`/`instantiateImageCodec` path, which for a 16dp glyph would
/// trade a battery problem for `ui.Image` refcount crashes. Rejecting or
/// flattening animated WebP at upload is still the better long-term fix (it is
/// one choke point and covers every consumer, not just this card); this guard
/// is what protects the app from objects already in the bucket.
class _ClientAvatarMark extends StatelessWidget {
  const _ClientAvatarMark({required this.avatarUrl});

  /// The client's public photo URL, or null — see `Booking.clientAvatarUrl`.
  /// Null covers BOTH a guest/LINK booking and a registered client who never
  /// uploaded one, and this widget deliberately renders them identically.
  final String? avatarUrl;

  /// The glyph's own size, and therefore row 1's height and 1dp of
  /// [MasterBookingCard.fullLayoutNaturalHeight]. See the size invariant
  /// above before changing it.
  static const double _kSize = 16;

  /// The photo's hairline ring, at the same alpha as the card's own border
  /// ([_MasterBookingCardState._kBorderAlpha]) and in the same camel — no new
  /// colour, the same edge treatment one level down.
  ///
  /// It exists because row 1 and row 2 open with a 16dp `BrandColors.accent`
  /// glyph at the same x, which is what makes them read as one left rail. A
  /// bare photograph in that slot leaves the accent register entirely and the
  /// rail stops resolving as a column; the ring puts the accent mark back
  /// around the photo while the photo carries the identity.
  ///
  /// Painted as a FOREGROUND decoration, so it overlays the image's edge
  /// rather than deflating it — a `Container` border would inset the child to
  /// 14dp and leave an antialiased seam. NO shadow of any kind: a circle
  /// paired with a `boxShadow` rasterizes as a hard square under Impeller-GLES
  /// (pinned for this file by `impeller_circle_shadow_guard_test.dart`).
  static const double _kRingAlpha = _MasterBookingCardState._kBorderAlpha;

  static final BoxDecoration _ring = BoxDecoration(
    shape: BoxShape.circle,
    border: Border.all(
      color: BrandColors.accent.withValues(alpha: _kRingAlpha),
    ),
  );

  /// The fallback — byte-identical to the glyph this slot carried before the
  /// photo landed, so the no-photo card is unchanged.
  static const Widget _glyph = Icon(
    Icons.person_outlined,
    size: _kSize,
    color: BrandColors.accent,
  );

  @override
  Widget build(BuildContext context) {
    final String? url = avatarUrl;
    // Shared media guard (core/media/beautica_image.dart): https-only + host
    // allowlist, replacing this site's old inline scheme check. The explicit
    // `url == null` keeps flow-promotion so `beauticaMediaProvider(url)` below
    // sees a non-null String — isAllowedMediaUrl already rejects null itself.
    if (url == null || !isAllowedMediaUrl(url)) return _glyph;

    // Decode at the physical pixel size this 16dp disc actually occupies
    // rather than at the R2 object's native resolution — see MEMORY above for
    // why BOTH axes are bound and why the policy is `fit` and not `exact`.
    final int side = (_kSize * MediaQuery.devicePixelRatioOf(context)).round();

    return SizedBox(
      height: _kSize,
      width: _kSize,
      child: DecoratedBox(
        decoration: _ring,
        position: DecorationPosition.foreground,
        child: ClipOval(
          // See ANIMATED SOURCES above: this pins the mark to frame 0 and
          // detaches it from the stream, so an animated WebP cannot drive a
          // decode/repaint loop for the life of the timeline.
          child: TickerMode(
            enabled: false,
            // Deliberately NOT `Image.network`: its `cacheWidth`/`cacheHeight`
            // sugar hard-codes `ResizeImagePolicy.exact`, which with both axes
            // set is `BoxFit.fill` at DECODE time and would squash every
            // non-square avatar. Spelling the provider out is the only way to
            // reach `fit`.
            child: Image(
              image: ResizeImage(
                // Disk-cached, TLS-controlled shared provider — the ONLY change
                // from the hand-built NetworkImage: same ResizeImage wrapper,
                // same policy/bounds, so the decode shape and the full body's
                // natural height (115dp as of the 2026-08-15 font-size pass,
                // 118dp when this comment was written — see
                // [MasterBookingCard.fullLayoutNaturalHeight]) are
                // mathematically unchanged BY THIS media-provider swap; the
                // later, unrelated font-size pass is what moved the number.
                beauticaMediaProvider(url),
                width: side,
                height: side,
                policy: ResizeImagePolicy.fit,
              ),
              fit: BoxFit.cover,
              excludeFromSemantics: true,
              // Rebuilt on every press (`_pressed` toggles `setState`), but
              // `NetworkImage`/`ResizeImage` are value-equal (and
              // `ResizeImageKey` folds in the policy), so each rebuild
              // resolves to the SAME `ImageCache` entry — never a refetch.
              frameBuilder: (_, Widget child, int? frame, bool wasSync) =>
                  wasSync || frame != null ? child : _glyph,
              errorBuilder: (_, _, _) => _glyph,
            ),
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
