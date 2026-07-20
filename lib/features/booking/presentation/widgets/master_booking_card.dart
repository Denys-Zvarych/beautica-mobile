// Phase 7.6 — one booking in the MASTER's «Мої записи» list.
//
// Transcribed from `docs/signup-designs/SalonManagementDesign/lib/widgets/
// booking_widgets.dart` (`BookingCard`), which is already drawn from the
// provider's perspective: the client is the headline, because the master
// already knows who the master is.
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
//   * The MASTER card's dominant element is the CLIENT's name on the first
//     line, with the date demoted to an inline caption chip beside the
//     service. It answers "who is coming to me, and for what".
//
// Generalising would mean a widget with two mutually exclusive grids, two
// identity blocks and a mode flag selecting between them — which is two
// widgets wearing one name, with every future edit to either forced to reason
// about the other. The genuinely shared pieces ARE shared: `BookingStatusBadge`
// (Phase 14.7, consumed verbatim — Phase 7.4's replacement badge is retired),
// `BookingDisplayX.showsPrice`, and the date formatters.
//
// The one design element deliberately dropped: the preview's SECOND identity
// row (`b.masterName` under the client) is salon-scope only — it names which
// teammate serves the booking. A single master's own list never needs it, the
// same reason `showMasterFilter: false`.
//
// SEC: renders a client name (PII). The hosting screen holds the
// `ScreenProtectionManager`; this widget logs nothing.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
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
/// natural size (as it always did for anything shorter than ~50 minutes —
/// see `bookings_timeline_grid.dart`'s "R2" section), wrapped itself in an
/// [OverflowBox] + [ClipRect] pair that laid the card out at its natural
/// height and then visually CROPPED the paint — and the hit-test region — to
/// the forced box. That was the exact mechanism behind the "I can see only
/// half of the card" report against the real device. Do not reintroduce a
/// forced height here: a future caller that genuinely needs a fixed-size card
/// must crop the CONTENT (fewer rows), never the render of the full card.
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
  /// Derivation (mirrors the card's own fixed row stack, top to bottom):
  /// `VelvetSpacing.md` padding ×2 (32) + the avatar row (46, the tallest
  /// child) + a `VelvetSpacing.sm + 2` gap (10) + the divider (1) + another
  /// `VelvetSpacing.sm + 2` gap (10) + the service/date row (~20, approximate
  /// — text-metric driven) + a `VelvetSpacing.xs + 2` gap (6) + the
  /// price/status row (24, `BookingStatusBadge`'s fixed height) ≈ 149dp. This
  /// constant rounds up from that to absorb font-metric overhead (a
  /// Nunito/Comfortaa glyph's real ascent+descent commonly exceeds its
  /// nominal `fontSize * height`) and larger system font scales, so the
  /// spacing this buys still looks reasonable at the common accessibility
  /// text-scale steps.
  static const double estimatedNaturalHeight = 190;

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
  /// which only ever takes two values. Exactly the same fix already applied
  /// to `_ClientAvatar._border` below.
  ///
  /// `borderedCard`, NOT `extrudedCard` — the extruded pair's offset
  /// near-white light shadow pokes past the rounded corner under Impeller and
  /// paints a white wedge there (resolved 34db74f). The hairline border
  /// defines the card instead.
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

  /// The client's avatar gradient, resolved ONCE per card lifetime rather
  /// than on every `build()` — mobile-perf MEDIUM-2 (Phase 7.10 timeline
  /// audit). `build()` reruns on every press (`onTapDown`/`onTapCancel`/
  /// `onTapUp` each call `setState`) and on every ancestor rebuild across up
  /// to ~100 cards on the busiest day, so re-walking
  /// `ClientAvatarGradients.forKey`'s rolling hash and re-allocating the
  /// gradient object on every one of those was pure waste: the identity this
  /// is keyed on (`clientId ?? clientName ?? id`) does not change across a
  /// press gesture. [didUpdateWidget] recomputes it only on the rare event
  /// that identity actually changes under the SAME element (a booking's
  /// client fields updated in place without the list also handing this
  /// widget a new `Key`) — the common case (a different booking) already
  /// gets a fresh `State` via `BookingsTimelineGrid`'s per-id `ValueKey`, so
  /// [initState] alone covers it.
  late List<Color> _avatarGradientColors;

  @override
  void initState() {
    super.initState();
    _avatarGradientColors = ClientAvatarGradients.forKey(
      _avatarKey(widget.booking),
    );
  }

  @override
  void didUpdateWidget(covariant MasterBookingCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_avatarKey(widget.booking) != _avatarKey(oldWidget.booking)) {
      _avatarGradientColors = ClientAvatarGradients.forKey(
        _avatarKey(widget.booking),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Booking b = widget.booking;
    final String clientName = b.clientName ?? l10n.bookingDetailGuestClient;

    final Widget card = Semantics(
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
            padding: const EdgeInsets.all(VelvetSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // Row 1 — avatar + client name. No badge on this row, so the
                // name gets the full remaining width (design's note).
                Row(
                  children: <Widget>[
                    _ClientAvatar(colors: _avatarGradientColors),
                    const SizedBox(width: VelvetSpacing.sm + 2),
                    Expanded(
                      child: Text(
                        clientName,
                        style: VelvetText.masterCardClientName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: VelvetSpacing.sm + 2),
                Container(height: 1, color: BrandColors.faint),
                const SizedBox(height: VelvetSpacing.sm + 2),
                // Row 2 — service name + date caption.
                Row(
                  children: <Widget>[
                    const Icon(
                      Icons.spa_outlined,
                      size: 16,
                      color: BrandColors.accent,
                    ),
                    const SizedBox(width: VelvetSpacing.sm),
                    Expanded(
                      child: Text(
                        b.serviceName,
                        style: VelvetText.masterCardService,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: VelvetSpacing.sm),
                    _BookingDateChip(startAt: b.startAt),
                  ],
                ),
                const SizedBox(height: VelvetSpacing.xs + 2),
                // Row 3 — price (left) + status badge (right).
                Row(
                  children: <Widget>[
                    const SizedBox(width: 16 + VelvetSpacing.sm),
                    // See `BookingDisplayX.showsPrice`: a cancelled, declined
                    // or missed appointment owes nothing, so printing a sum on
                    // it would assert a debt that does not exist.
                    if (b.showsPrice)
                      _PriceTag(
                        price:
                            '${b.price.toStringAsFixed(0)} '
                            '${l10n.pricingCurrencySuffix}',
                      ),
                    const Spacer(),
                    BookingStatusBadge(booking: b),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return card;
  }
}

/// The stable identity a booking's client-avatar gradient is keyed on —
/// shared between [_MasterBookingCardState.initState]/[_MasterBookingCardState.didUpdateWidget]
/// so both compute the exact same key [ClientAvatarGradients.forKey] expects.
String _avatarKey(Booking booking) =>
    booking.clientId ?? booking.clientName ?? booking.id;

/// A price pill — «450 ₴».
///
/// The design draws this as a `NeumorphicInset`. Rendered here as a hairline
/// bordered pill instead: the card already sits on `borderedCard`, and nesting
/// a recessed well inside a raised card at this size reads as noise rather
/// than depth. The accent hairline is the same edge language the card and the
/// calendar button use.
class _PriceTag extends StatelessWidget {
  const _PriceTag({required this.price});

  final String price;

  /// Hoisted out of [build] (mobile-perf LOW-5 — same root cause as
  /// MEDIUM-4): the owning `MasterBookingCard` rebuilds on every press
  /// (`onTapDown`/`onTapCancel`/`onTapUp` each call `setState`), which reruns
  /// this `StatelessWidget`'s `build()` too across up to ~100 cards on the
  /// busiest day. `Color.withValues` is not a const constructor, so this
  /// can't be `static const`, but resolving it once at class-load time —
  /// instead of once per press — is the same fix `_ClientAvatar._border` and
  /// `_MasterBookingCardState`'s own card decoration apply.
  static final BoxDecoration _decoration = BoxDecoration(
    color: BrandColors.base,
    borderRadius: BorderRadius.circular(VelvetRadii.pill),
    border: Border.all(
      color: BrandColors.accent.withValues(alpha: 0.22),
      width: 1,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _decoration,
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

/// A muted date+time caption with a clock glyph — «12 лип, 14:30».
class _BookingDateChip extends StatelessWidget {
  const _BookingDateChip({required this.startAt});

  final DateTime startAt;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Icon(Icons.schedule_outlined, size: 12, color: BrandColors.muted),
        const SizedBox(width: 3),
        Text(formatShortDateTime(startAt), style: VelvetText.masterCardDate),
      ],
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
/// mobile-perf MEDIUM-2 (Phase 7.10 timeline audit): takes the already
/// resolved [colors] rather than a `gradientKey` string, so this `build()` —
/// which reruns on every press of the owning `MasterBookingCard` — never
/// re-walks [ClientAvatarGradients.forKey]'s hash loop. The caller
/// (`_MasterBookingCardState`) resolves that once per card lifetime.
class _ClientAvatar extends StatelessWidget {
  const _ClientAvatar({required this.colors});

  /// The client's avatar gradient stops, already resolved via
  /// [ClientAvatarGradients.forKey].
  final List<Color> colors;

  static const double _diameter = 46;

  /// Hoisted out of [build] (mobile-perf MEDIUM-2): `Color.withValues` is not
  /// a const constructor, so this can't be a `static const`, but computing it
  /// once at class-load time — instead of once per `build()` call, i.e. on
  /// every press of the owning card and every ancestor rebuild — is exactly
  /// the same fix `VelvetText`'s cached statics apply to `TextStyle`s.
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
          size: 22,
        ),
      ),
    );
  }
}
