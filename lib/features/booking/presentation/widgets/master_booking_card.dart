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
// │ 09:00  Стрижка жіноча    450₴│
// │ Марія Іванюк     ● Підтв.    │
// └──────────────────────────────┘
// ```
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
//     booking's start time leading the first line. It answers "who is coming
//     to me, and for what, and when".
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
/// The card always sizes itself to its own natural content height — there is
/// no duration-derived or otherwise externally forced height.
/// `BookingsTimelineGrid` (Phase 7.10) constrains only this card's `width`
/// (via a `SizedBox` in its per-lane `_LaneColumn`), never a `height:`,
/// exactly mirroring the design's own `_TimelineGrid`
/// (`bookings_toolbar.dart:1438-1448`). See that file's "R3" header section
/// for why same-lane cards are laid out as a flex `Column` rather than
/// absolutely `Positioned` siblings of a shared `Stack`.
///
/// An earlier version of this widget accepted optional `width`/`height`
/// constructor params and, whenever `height` came in smaller than the card's
/// natural size, wrapped itself in an [OverflowBox] + [ClipRect] pair that
/// laid the card out at its natural height and then visually CROPPED the
/// paint — and the hit-test region — to the forced box. That was the exact
/// mechanism behind the "I can see only half of the card" report against the
/// real device. Do not reintroduce a forced height here: a future caller
/// that genuinely needs a fixed-size card must crop the CONTENT (fewer
/// rows), never the render of the full card.
class MasterBookingCard extends StatefulWidget {
  const MasterBookingCard({
    super.key,
    required this.booking,
    required this.onTap,
  });

  final Booking booking;
  final VoidCallback onTap;

  /// A documented ESTIMATE of this card's natural rendered height, used ONLY
  /// by `BookingsTimelineGrid`'s collision-avoiding lane layout to decide how
  /// much breathing room to leave between two same-lane cards when their
  /// scheduled times are close together — see that file's "R3" header
  /// section. Deliberately NOT a safety floor: the timeline's per-lane
  /// `Column` layout can never let two cards overlap regardless of how far
  /// this estimate drifts from a card's true height (a `Column` always
  /// starts a child exactly after its predecessor's REAL rendered size, not
  /// this planning number) — so getting this value slightly wrong only ever
  /// costs a little visual density, never correctness.
  ///
  /// Derivation, post compact-timeline pass (this file's class doc): vertical
  /// padding ×2 (12) + row 1 (the price tag's `NeumorphicInset`, its tallest
  /// child, ~20) + the inter-row gap (4) + row 2 (the client name /
  /// `TimelineStatusBadge` line, ~17) ≈ 53dp. Rounded to 56 to absorb
  /// font-metric overhead (a Nunito/Comfortaa glyph's real ascent+descent
  /// commonly exceeds its nominal `fontSize * height`) and larger system
  /// font scales. Measured against the real widget in
  /// `master_booking_card_test.dart`'s "compact card height" group.
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
  static final BoxDecoration _decorationUnpressed = BoxDecoration(
    color: BrandColors.base,
    borderRadius: BorderRadius.circular(VelvetRadii.card),
    border: Border.all(
      color: BrandColors.accent.withValues(alpha: 0.18),
      width: 1,
    ),
    boxShadow: VelvetShadows.borderedCard,
  );
  static final BoxDecoration _decorationPressed = BoxDecoration(
    color: BrandColors.base,
    borderRadius: BorderRadius.circular(VelvetRadii.card),
    border: Border.all(
      color: BrandColors.accent.withValues(alpha: 0.18),
      width: 1,
    ),
  );

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
            padding: const EdgeInsets.symmetric(
              horizontal: VelvetSpacing.sm + 2,
              vertical: VelvetSpacing.xs + 2,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // Row 1 — start time · service name (flexes) · price.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      formatSlotTime(b.startAt),
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
                    // See `BookingDisplayX.showsPrice`: a cancelled, declined
                    // or missed appointment owes nothing, so printing a sum
                    // on it would assert a debt that does not exist.
                    if (b.showsPrice) ...<Widget>[
                      const SizedBox(width: VelvetSpacing.xs),
                      _PriceTag(
                        price:
                            '${b.price.toStringAsFixed(0)} '
                            '${l10n.pricingCurrencySuffix}',
                      ),
                    ],
                  ],
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
            ),
          ),
        ),
      ),
    );
  }
}

/// A price pill — «450 ₴».
///
/// Design-parity pass (finding #9): the approved design draws this as a
/// `NeumorphicInset` recessed well (`booking_widgets.dart`'s `PriceTag`);
/// transcribed verbatim via the shared `core/widgets/neumorphic.dart`
/// `NeumorphicInset` — the same widget the design's own token file's
/// `NeumorphicInset` maps to, so this is a like-for-like port, not a
/// reinterpretation.
class _PriceTag extends StatelessWidget {
  const _PriceTag({required this.price});

  final String price;

  @override
  Widget build(BuildContext context) {
    return NeumorphicInset(
      radius: VelvetRadii.pill,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: VelvetSpacing.sm,
          vertical: 3,
        ),
        child: Text(
          price,
          style: VelvetText.pill(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
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
  const TimelineStatusBadge({super.key, required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final BookingStatusVisual v = BookingStatusVisual.of(booking, l10n);

    return Semantics(
      label: l10n.bookingStatusSemantics(v.label),
      child: NeumorphicInset(
        radius: VelvetRadii.pill,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: VelvetSpacing.xs + 2,
            vertical: 2,
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
