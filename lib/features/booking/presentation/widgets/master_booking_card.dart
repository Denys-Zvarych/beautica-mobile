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
// The two-line grid below (time/service/price, then client/status) is the
// user-approved shape:
//
// ```
// ┌──────────────────────────────┐
// │ 09:00–09:45 Стрижка жін. 450₴│
// │ Марія Іванюк     ● Підтв.    │
// └──────────────────────────────┘
// ```
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

  /// A documented ESTIMATE of this card's natural rendered height. Predates
  /// the proportional-duration-height pass and is no longer read by
  /// `BookingsTimelineGrid`'s lane layout (which now computes a real,
  /// duration-derived floor per booking — see that file's `_cardMinHeightFor`
  /// and "ADDENDUM 2") — kept as a documented, tested reference point for the
  /// card's true natural size, and because a `null`-`minHeight` call site
  /// (any caller outside the timeline grid) still renders at roughly this
  /// height with nothing forced. Deliberately NOT a safety floor in itself:
  /// the timeline's per-lane `Column` layout can never let two cards overlap
  /// regardless of how far this estimate drifts from a card's true height (a
  /// `Column` always starts a child exactly after its predecessor's REAL
  /// rendered size, not this planning number) — so getting this value
  /// slightly wrong only ever costs a little visual density, never
  /// correctness.
  ///
  /// Derivation, post compact-timeline pass (this file's class doc): vertical
  /// padding ×2 (12) + row 1 (the price tag's `NeumorphicInset`, its tallest
  /// child, ~20) + the inter-row gap (4) + row 2 (the client name /
  /// `TimelineStatusBadge` line, ~17) ≈ 53dp. Rounded to 56 to absorb
  /// font-metric overhead (a Nunito/Comfortaa glyph's real ascent+descent
  /// commonly exceeds its nominal `fontSize * height`) and larger system
  /// font scales. Measured against the real widget in
  /// `master_booking_card_test.dart`'s "compact card height" group.
  ///
  /// Row 1's ~20dp term is the price pill, and that pill's height is pinned
  /// independently of its horizontal `BoxFit.scaleDown` — see [_PriceTag]'s
  /// zero-width height anchor. Without that anchor a band wide enough to hit
  /// the pill's width cap would have scaled the pill's HEIGHT down with it
  /// (uniform fit), silently dragging the compact card below this estimate.
  static const double estimatedNaturalHeight = 56;

  @override
  State<MasterBookingCard> createState() => _MasterBookingCardState();
}

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
  /// compact two-row grid to the fuller divided layout — see this file's
  /// "Adaptive full/compact layout" header section for the full mechanism.
  /// Equal to `bookings_timeline_grid.dart`'s `_kHourH` (one hour of ruled
  /// space): a booking whose duration-derived floor reaches 60 minutes
  /// (112dp) or more gets the fuller layout; the 30-/45-minute floors
  /// (56dp/84dp) stay on the compact grid, the only shape proven to fit a
  /// 56dp box without clipping.
  static const double _kFullLayoutMinHeight = 112;

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

  /// Width the compact row 1 keeps for its NON-price content before the price
  /// pill may claim any of it — see [_compactPriceCap] and row 1's own
  /// comment in [_buildCompactBody].
  ///
  /// Derivation, all measured against the real widget, at the WORST case
  /// (`main.dart`'s 1.3 MediaQuery textScaler ceiling — the label scales, the
  /// lane does not):
  ///
  ///   * the start–end range label in [VelvetText.masterCardTime] —
  ///     «09:00–09:20» is 66.65dp at scale 1.0 and 86.6dp at 1.3;
  ///   * the row's two gaps — `VelvetSpacing.xs + 2` then `VelvetSpacing.xs`,
  ///     10dp, fixed;
  ///   * ~15dp so the `Expanded` service name never collapses to literally
  ///     nothing on the narrowest lane.
  ///
  /// 86.6 + 10 + 15 ≈ 112. Deliberately a FIXED reserve rather than a
  /// fraction of the lane: a fraction would shave the pill on wide lanes that
  /// have room to spare, whereas this only ever binds where the arithmetic
  /// says it must. The narrowest lane the timeline can build is 226dp
  /// (`bookings_timeline_grid.dart`'s "ADDENDUM 3" clamps its 272dp card to
  /// `constraints.maxWidth`, and the lane area is `deviceWidth − 94`: 24 + 24
  /// screen padding, 42 ruler, 4 gap — so a 320dp device, which this app
  /// supports throughout, yields `320 − 94 = 226`). 226dp of lane is 203dp of
  /// inner width after this card's own padding and border, leaving the pill
  /// 91dp — under its own 112dp ceiling, so the cap engages there and only
  /// there. A 360dp device's 266dp lane leaves 131dp, i.e. no change at all.
  static const double _kCompactPriceReserve = 112;

  /// The smallest cap [_compactPriceCap] will hand the pill. Below the pill's
  /// own horizontal padding (2 × `VelvetSpacing.sm`) a `ConstrainedBox` would
  /// force a `maxWidth` the pill physically cannot meet; this floor keeps the
  /// constraint satisfiable on a lane narrower than anything production can
  /// produce (the band simply scales down further there).
  static const double _kCompactPriceMinWidth = VelvetSpacing.xxl;

  /// The compact price pill's `maxWidth` for a row [rowWidth] dp wide.
  ///
  /// An unbounded row (no real call site, but [LayoutBuilder] contracts allow
  /// it) leaves the pill on its own [_PriceTag] cap, exactly as before.
  static double _compactPriceCap(double rowWidth) => rowWidth.isFinite
      ? math.max(rowWidth - _kCompactPriceReserve, _kCompactPriceMinWidth)
      : double.infinity;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Booking b = widget.booking;
    final String clientName = b.clientName ?? l10n.bookingDetailGuestClient;

    return Semantics(
      button: true,
      label: l10n.masterBookingCardSemantics(clientName, b.serviceName),
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
            padding: _useFullLayout ? _fullPadding : _compactPadding,
            child: _useFullLayout
                ? _buildFullBody(b, clientName)
                : _buildCompactBody(b, clientName),
          ),
        ),
      ),
    );
  }

  /// Whether [build] renders the design's fuller divided layout instead of
  /// the compact two-row grid — see this file's "Adaptive full/compact
  /// layout" header section for the full rationale.
  bool get _useFullLayout => (widget.minHeight ?? 0) >= _kFullLayoutMinHeight;

  /// The dense two-row grid (time/service/price, then client/status) — the
  /// only shape proven to fit a 30-minute (56dp) slot without clipping. See
  /// this file's "Adaptive full/compact layout" header section.
  Widget _buildCompactBody(Booking b, String clientName) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // Row 1 — start–end time range · service name (flexes) · price.
        //
        // The range roughly DOUBLES this leading label's width versus the
        // bare start time it replaced, and the `Expanded` service name
        // between them absorbs that loss by ellipsising. What the service
        // name CANNOT absorb is the row's two non-flex children out-measuring
        // the row on their own — which is exactly what happened on the real
        // narrowest lane once a frozen band was in play: at 226dp
        // (see [_kCompactPriceReserve]) and the app's 1.3 textScaler ceiling
        // the range label measures 86.6dp and the capped price pill 112dp,
        // which with the two gaps is 208.6dp against 203dp of inner width —
        // a 5.6px overflow with the service name already squeezed to zero.
        // (An earlier version of this comment claimed the non-flex children
        // "stay well inside even the narrowest clamped lane (266dp on a
        // 360dp device)". 266dp is `360 − 94`, not the floor: 320dp is a
        // supported width throughout this app, so `320 − 94 = 226` is, and at
        // 226dp the claim was false. `bookings_timeline_grid.dart`'s
        // "ADDENDUM 3" arithmetic was always right — only this restatement of
        // which device it bottoms out on was wrong.)
        //
        // What guarantees the fit now is [_kCompactPriceReserve]: the pill is
        // still non-flex, but it is capped at the row's REAL width minus a
        // reserve big enough for the range label at the textScaler ceiling,
        // both gaps, and a service-name sliver — so the three children can
        // never sum past the row. On any lane from 266dp up the reserve
        // leaves more than the pill's own 112dp ceiling, so nothing changes
        // there. Pinned by `master_booking_card_test.dart`'s "narrow-lane"
        // group, which sweeps 226/266/272 × textScaler 1.0/1.3 × single/band.
        // THIS CARD MUST NOT BE PLACED UNDER `IntrinsicHeight`,
        // `IntrinsicWidth` OR AN `IntrinsicColumnWidth` TABLE COLUMN
        // -----------------------------------------------------------------
        // The `LayoutBuilder` below is what costs us that: it cannot report
        // intrinsic dimensions, because doing so would mean running its
        // builder speculatively at a size it was never laid out at. The
        // failure is asymmetric between build modes, and the QUIET half is the
        // dangerous one:
        //
        //   * DEBUG/JIT — loud. `_RenderLayoutBuilder.computeMaxIntrinsicHeight`
        //     asserts "LayoutBuilder does not support returning intrinsic
        //     dimensions" and the frame throws. Verified directly: wrapping
        //     this card in an `IntrinsicHeight` under a LOOSE incoming height
        //     (a tight one short-circuits before the intrinsic pass is ever
        //     requested, so the hazard hides) throws through
        //     `RenderFlex.computeMaxIntrinsicHeight`.
        //   * RELEASE/AOT — silent and WRONG. That assert is compiled out, so
        //     all four of `computeMinIntrinsicWidth`, `computeMaxIntrinsicWidth`,
        //     `computeMinIntrinsicHeight` and `computeMaxIntrinsicHeight`
        //     simply return `0.0`. The ancestor then equalises against a
        //     zero-height measurement and lays the row out to a bogus size — a
        //     mangled card in the shipped app with nothing thrown, nothing
        //     logged and no test failure to catch it, because the widget tests
        //     that would have exploded only ever run in debug.
        //
        // Not a theoretical constraint: the `IntrinsicHeight` +
        // `CrossAxisAlignment.stretch` pattern is live and common in this repo
        // — `master_profile_screen.dart:439` and
        // `public_master_profile_screen.dart:410` both use it to equalise a
        // row of cards to the tallest one, and `home_hub_screen.dart`,
        // `quick_links_card.dart`, `next_appointment_card.dart` and
        // `passport_table.dart` do the same. Dropping this card into any such
        // row is a one-line change that looks harmless and reviews clean. If a
        // caller genuinely needs an equal-height row of these cards, give the
        // row a real height (a `SizedBox`/`ConstrainedBox` the caller computes)
        // rather than asking this subtree to measure itself.
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints rowConstraints) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Text(
                  formatSlotTimeRange(b.startAt, b.endAt),
                  style: VelvetText.masterCardTime,
                ),
                const SizedBox(width: VelvetSpacing.xs + 2),
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
                // would assert a debt that does not exist.
                if (b.showsPrice) ...<Widget>[
                  const SizedBox(width: VelvetSpacing.xs),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: _compactPriceCap(rowConstraints.maxWidth),
                    ),
                    child: _PriceTag(price: b.priceLabel),
                  ),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: VelvetSpacing.xs),
        // Row 2 — client name (flexes) · status badge.
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
            const SizedBox(width: VelvetSpacing.xs),
            TimelineStatusBadge(booking: b),
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
        // in a sibling. No reserve is needed here (unlike the compact row's
        // [_kCompactPriceReserve]) because nothing else on this row competes
        // for that space.
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
/// narrowest lane (226dp: a 320dp device minus 94 of ruler/padding/gap, see
/// [MasterBookingCard._kCompactPriceReserve]) that overflowed BOTH layouts
/// once a frozen band was present.
///
/// The fix is on the CALLER side, in both rows, and this widget's job is to
/// honour it: the pill's inner band is a [Flexible], so whenever the pill is
/// handed a bounded `maxWidth` the [FittedBox] scales into THAT instead of
/// into a flat 96. The two callers bound it differently, each matching its
/// row's own priority order:
///
///   * compact row 1 — a `ConstrainedBox` whose `maxWidth` is the row's real
///     width minus a documented reserve for the time label, the gaps and a
///     service-name sliver. The pill stays NON-flex there on purpose: the
///     service name must keep absorbing the slack in the common case (a
///     `Flexible` pill would split the row's free space evenly with the
///     `Expanded` name and cost that name ~17dp on every device, for nothing).
///   * full row 3 — an `Expanded` + `Align`, which hands the pill the row's
///     entire remaining width after the status badge. No reserve is needed
///     because nothing else in that row competes for it.
///
/// Both keep [_maxTextWidth] as the ceiling: on any lane wide enough (266dp
/// and up) neither bound binds and the pill renders exactly as it always did.
class _PriceTag extends StatelessWidget {
  const _PriceTag({required this.price});

  /// Already-formatted — «450 ₴» or «300–500 ₴». See
  /// `BookingDisplayX.priceLabel`; this widget never formats money itself.
  final String price;

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

  @override
  Widget build(BuildContext context) {
    return NeumorphicInset(
      radius: VelvetRadii.pill,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: VelvetSpacing.sm,
          vertical: 3,
        ),
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
/// This widget resolves colour + label through the exact same
/// [BookingStatusVisual.of] factory `BookingStatusBadge` uses — the
/// status→(colour, label) mapping lives in ONE place
/// (`booking_status_badge.dart`), so the two badges can never drift apart on
/// what a given [BookingStatus] means, only on how tightly it is drawn. Only
/// the dot-shaped glyph (no icon cap, matching the approved design) and the
/// sizing are specific to this widget.
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
    final BookingStatusVisual v = BookingStatusVisual.of(booking, l10n);

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
