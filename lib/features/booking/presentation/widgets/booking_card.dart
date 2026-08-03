/// Phase 14.3 — one booking in the «МОЇ ЗАПИСИ» list.
///
/// Ported from `docs/signup-designs/MyBookings/lib/widgets/booking_card.dart`.
/// See that file's doc comments (preserved below where load-bearing) for the
/// full design reasoning; this header only summarises the parts a future
/// editor must not casually "fix".
///
/// ## The grid
///
/// ```
/// ┌──┬────────┬┄┬─────────────────────────────────────┐
/// │▐ │        ┊ │                                     │
/// │▐ │        ┊ │  ⟨photo⟩  Марія Іванюк              │
/// │▐ │   18   ┊ │   52 dp   Майстриня манікюру        │
/// │▐ │червня, ┊ │           ▣ Lviv Nails Studio       │
/// │▐ │   ср   ┊ │                                     │
/// │▐ │ 15:00  ┊ │  ✂ Манікюр з покриттям      650 ₴   │
/// │▐ │        ┊ │  ⦿ Підтверджено                  ›  │
/// └──┴────────┴┄┴─────────────────────────────────────┘
///  rail  stub  perf              body
/// ```
///
/// **The date column is exclusive.** Nothing from the body sits inside it,
/// and nothing from it leaks into the body — the stub is its own column,
/// carrying the WHOLE "when" of the booking (day, weekday/month, and the
/// slot time stacked directly under the date it belongs to), and every other
/// element lives to its right. The outer `Row` is
/// `CrossAxisAlignment.center`d, so the stub centres against the card's full
/// content height — the taller `Expanded` body defines that height, the
/// shorter stub rides in the middle of it.
///
/// **This reverses an earlier decision.** An older revision of this file
/// pinned the stub to a fixed offset derived from the photo's optical
/// centre specifically so the date would land on the SAME y on every card,
/// independent of body height — the trade-off being that a genuinely
/// centred stub drifts, because the body's height is not constant: it grows
/// or shrinks with whether the master filled in a professional title and/or
/// salon name, whether their name wraps to a second line, and whether the
/// service name wraps to a second line. That was a deliberate choice at the
/// time. The user has since asked for TRUE vertical centring instead, and
/// this revision honours that: the stub's y position now visibly varies
/// row-to-row in the «Мої записи» list — a card with a one-line identity
/// block sits the date noticeably higher than a card with a two-line master
/// name and both title and salon filled in. That drift is the accepted
/// cost of true centring; a future editor should not "fix" it back to a
/// fixed pin without the user asking for that trade-off again.
///
/// ## The card has ONE affordance: open me
///
/// Every action — «Перенести», «Скасувати», «Записатись знову», add-to-
/// calendar — lives on «Деталі запису». The card carries no buttons; the
/// whole card is the tap target, and the only mark of that is a muted
/// chevron on the status row's trailing edge — deliberately not a button and
/// not its own tap target.
///
/// ## No note text, at any status
///
/// The card renders NO note body at all. Notes run to 1000 characters, and a
/// scanned list row is not where you read someone's paragraph — every note
/// lives on «Деталі запису». What stays is [BookingStatusBadge]: the client
/// still sees at a glance that a booking was cancelled and BY WHOM.
///
/// ## Price shows only where money is a true statement
///
/// See [BookingDisplayX.showsPrice]. `CONFIRMED`/`COMPLETED` carry the price;
/// `CANCELLED`/`DECLINED`/`NOT_COMPLETED` do not — printing a sum on an
/// appointment that never happened (or whose bill is genuinely ambiguous, on
/// a no-show) asserts a debt the app has no standing to assert.
///
/// The figure itself is [BookingDisplayX.priceLabel], which reads «650 ₴» for
/// a single price and «300–500 ₴» when the master left the service as a
/// genuine RANGE at booking time. The band is gated by the SAME `showsPrice`
/// rule — nothing about the two-number form changes when money is shown.
///
/// ## ⚠ The price anchor is a NON-flex child
///
/// The service name is the row's Expanded child; the price is laid out
/// FIRST at its intrinsic width, non-flex, hard against the row's right
/// edge. Making the price `Flexible` (a second flex child) makes the row
/// split its free space 50/50 between the two flex children instead, and
/// the unallocated remainder floats the price off the margin by a variable
/// amount per card — measured drift in the original design pass: ~20 dp.
/// See `_ServiceLine`. (The slot time used to sit top-right of the body,
/// directly above this anchor, sharing its x — it now lives in the date
/// stub, so the price's only remaining reference edge is the body's own
/// right margin.)
library;

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/media/beautica_image.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';

import '../../domain/booking.dart';
import '../../domain/booking_display_x.dart';
import '../../domain/booking_status.dart';
import 'booking_status_badge.dart';

/// One booking in the «МОЇ ЗАПИСИ» list. See the library doc.
class BookingCard extends StatefulWidget {
  const BookingCard({
    super.key,
    required this.booking,
    required this.onOpenDetails,
  });

  final Booking booking;

  /// The card's ONLY callback — every action now lives on «Деталі запису».
  final VoidCallback onOpenDetails;

  @override
  State<BookingCard> createState() => _BookingCardState();
}

// The card's horizontal grid, in one place, because the painted chrome and
// the laid-out content have to agree on it exactly. Every number is a
// VelvetSpacing token.
const double _railWidth = 4;
const double _stubInset = VelvetSpacing.sm; // 8
const double _gutter = VelvetSpacing.lg; // 24
const double _tearLineX =
    _railWidth + _stubInset + _DateStub.width + VelvetSpacing.xs;

/// The widest the price anchor may grow before it scales its text down. A
/// CAP, not a column width — the price sizes to its content and sits flush
/// against the body's right edge whatever its length. (It no longer shares
/// an x with a time line — the slot time moved into the date stub; see the
/// library doc.)
///
/// Re-verified when the frozen RANGE band («300–500 ₴», see
/// [BookingDisplayX.priceLabel]) started reaching this anchor: measured in
/// [VelvetText.bookingCardPrice] (Nunito 10/w800), the longest band this card
/// can realistically draw — «12500–25000 ₴» — is 76.96dp, and a plain «650 ₴»
/// is ~27dp, so 96 still clears the widest case with ~19dp of headroom and no
/// live booking scales down. That band is now PINNED, not merely documented:
/// `booking_surfaces_overflow_test.dart`'s "§ 1d" block renders it across the
/// 9-cell width x scale matrix and re-measures the 1.0x headroom, because
/// every other fixture in that file passes a single `price` with no
/// `priceMax` and so never drew a band at all.
/// It is a cap, not a floor: the `FittedBox` below
/// shrinks rather than clips, so even a pathological figure stays whole and
/// the row can never overflow. Do NOT lower it below ~80 — that would start
/// scaling real bands.
///
/// `master_booking_card.dart`'s `_PriceTag._maxTextWidth` is also 96, but that
/// is a COINCIDENCE of two independent measurements, NOT a shared knob: that
/// card renders the price in `VelvetText.pill` (Nunito 11/w800), where the same
/// «12500–25000 ₴» band measures 83.77dp and leaves only ~12dp of headroom. The
/// caps match in dp; the thresholds in GLYPHS do not, and a future type-scale
/// bump would trip that card ~7dp of band-width before this one. Re-measure
/// each card separately — see that constant's doc for the full comparison.
const double _priceMaxWidth = 96;

class _BookingCardState extends State<BookingCard> {
  bool _pressed = false;

  Booking get _b => widget.booking;

  /// The provider marked the client absent. Lives in «Минулі» beside
  /// «Виконано».
  bool get _isNoShow => _b.status == BookingStatus.notCompleted;

  /// Either cancellation state. Both are "this appointment is gone", both
  /// sink to the flat depth stratum.
  bool get _isDead =>
      _b.status == BookingStatus.cancelled ||
      _b.status == BookingStatus.declined;

  /// Cancelled / declined: no lift at all — a single soft ground shadow so the
  /// card still separates from the base without claiming elevation. Hoisted to
  /// a static field: it never varies, so it need not reallocate on each build.
  static final List<BoxShadow> _deadShadows = <BoxShadow>[
    BoxShadow(
      color: BrandColors.shadowDarkCard.withValues(alpha: 0.40),
      offset: const Offset(0, 4),
      blurRadius: 12,
    ),
  ];

  /// Depth-as-time-axis: proud → shallow → sunk.
  List<BoxShadow>? get _shadows {
    if (_pressed) return null;
    return switch (_b.status) {
      BookingStatus.confirmed => VelvetShadows.extrudedCard,
      BookingStatus.completed ||
      BookingStatus.notCompleted ||
      // An unrecognised status sits in the middle stratum: present and
      // tappable, but not claiming CONFIRMED's proud lift (which is the
      // depth cue for "this is happening").
      BookingStatus.unknown => VelvetShadows.extrudedSmall,
      BookingStatus.cancelled || BookingStatus.declined => _deadShadows,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final BookingStatusVisual v = BookingStatusVisual.of(_b, l10n);

    return Semantics(
      button: true,
      label: l10n.bookingCardSemantics(
        _b.serviceName,
        _b.masterName,
        formatFullDate(_b.startAt),
        formatSlotTime(_b.startAt),
        v.label,
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onOpenDetails();
        },
        child: AnimatedScale(
          scale: _pressed ? 0.985 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            decoration: BoxDecoration(
              color: BrandColors.base,
              borderRadius: BorderRadius.circular(VelvetRadii.card),
              boxShadow: _shadows,
              // A cancelled card has no lift, so it earns a hairline instead
              // — otherwise it would dissolve into the taupe background.
              border: _isDead
                  ? Border.all(color: BrandColors.faint.withValues(alpha: 0.55))
                  : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(VelvetRadii.card),
              // The status rail + tear line are PAINTED behind the content
              // rather than laid out beside it — a Row-based layout would
              // need an IntrinsicHeight around the card, and this subtree's
              // note-clamping LayoutBuilder cannot answer an intrinsic
              // query (it asserts). A CustomPaint gets the card's final
              // size for free and asks the subtree nothing.
              child: CustomPaint(
                painter: _CardChrome(accent: v.accent, muted: _isDead),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    _railWidth + _stubInset,
                    VelvetSpacing.sm,
                    VelvetSpacing.sm,
                    VelvetSpacing.sm,
                  ),
                  child: Row(
                    // Centres the stub against the card's FULL content
                    // height (the taller Expanded body defines that height;
                    // the shorter stub centres within it) — see the library
                    // doc's "date column" section for why this replaced the
                    // old fixed-offset pin.
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      _DateStub(
                        key: ValueKey<String>('stub-${_b.id}'),
                        bookingId: _b.id,
                        start: _b.startAt,
                        dimmed: _isDead,
                        struck: _isNoShow,
                      ),
                      const SizedBox(width: _gutter),
                      Expanded(child: _body(l10n)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // ── The time moved out of the body and into the date stub, directly
        //    under the day it belongs to — see [_DateStub] and the library
        //    doc. The identity row is now the body's first line.
        _identity(),
        const SizedBox(height: VelvetSpacing.xs),

        // ── WHAT — the only line between identity and status, so it
        //    carries the middle of the card on its own.
        _ServiceLine(
          bookingId: _b.id,
          icon: _categoryIconFor(_b.categoryName),
          text: _b.serviceName,
          price: _b.showsPrice ? _b.priceLabel : null,
          dimmed: _isDead,
        ),
        const SizedBox(height: VelvetSpacing.xs),

        // ── Status, and the chevron that says the row opens.
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Flexible(child: BookingStatusBadge(booking: _b)),
            const Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: BrandColors.faint,
            ),
          ],
        ),
      ],
    );
  }

  /// WHO: the photo, and the person beside it. [CrossAxisAlignment.center]
  /// is load-bearing — the text column is 1-3 lines depending on which
  /// optional fields the master filled in, and centring it against the
  /// 52 dp photo means a master with no title/salon gets a name sitting
  /// squarely beside their picture, never a hole where the title would be.
  Widget _identity() {
    final String? title = _b.masterProfessionalTitle;
    final String? salon = _b.salonName;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        _MasterPhoto(
          avatarUrl: _b.masterAvatarUrl,
          initials: _b.masterInitials,
          dimmed: _isDead,
        ),
        const SizedBox(width: VelvetSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                _b.masterName,
                key: ValueKey<String>('master-name-${_b.id}'),
                // A long «Ім'я Прізвище» wraps to a second line rather than
                // being cut mid-name; the ellipsis stays only as a defensive
                // floor for a pathological 3-lines-worth name. The identity
                // column is MainAxisSize.min inside a min-height body Column,
                // so the extra line grows the card instead of clipping.
                maxLines: 2,
                softWrap: true,
                overflow: TextOverflow.ellipsis,
                style: VelvetText.bookingCardName.copyWith(
                  color: _isDead ? BrandColors.textSecondary : BrandColors.text,
                ),
              ),
              if (title != null) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: VelvetText.bookingCardSubtle,
                ),
              ],
              if (salon != null) ...<Widget>[
                const SizedBox(height: 2),
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.storefront_rounded,
                      size: 12,
                      color: _isDead
                          ? BrandColors.faint
                          : BrandColors.accent.withValues(alpha: 0.9),
                    ),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(
                        salon,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: VelvetText.bookingCardCaption.copyWith(
                          color: _isDead
                              ? BrandColors.muted
                              : BrandColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Maps a booking's category name to its glyph. A private, card-local switch
/// (mirrors the approved preview) — there is no shared `categoryIconFor`
/// utility yet (tracked for the discovery feature).
IconData _categoryIconFor(String? category) => switch (category) {
  'Манікюр' || 'Нігті' => Icons.front_hand_rounded,
  'Волосся' => Icons.content_cut_rounded,
  'Брови' || 'Вії' => Icons.remove_red_eye_rounded,
  'Масаж' => Icons.spa_rounded,
  'Косметологія' => Icons.face_retouching_natural_rounded,
  _ => Icons.auto_awesome_rounded,
};

/// The two full-height chrome marks, painted behind the content.
///
/// **The status rail** — a 4 dp stripe of the badge's own accent down the
/// card's leading edge, restating the badge at the periphery.
/// **The tear line** — a dashed rule between the stub and the ticket body,
/// deliberately NEUTRAL (never tinted with the status accent): the rail
/// means *status*, the perforation means *structure*.
class _CardChrome extends CustomPainter {
  const _CardChrome({required this.accent, required this.muted});

  final Color accent;
  final bool muted;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rail = Rect.fromLTWH(0, 0, _railWidth, size.height);
    canvas.drawRect(
      rail,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            accent.withValues(alpha: muted ? 0.85 : 1),
            accent.withValues(alpha: muted ? 0.35 : 0.55),
          ],
        ).createShader(rail),
    );

    final Paint dashes = Paint()
      ..color = BrandColors.faint.withValues(alpha: 0.65)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    const double dash = 3;
    const double gap = 4.5;
    const double inset = 12;
    double y = inset;
    while (y < size.height - inset) {
      final double end = (y + dash).clamp(0.0, size.height - inset);
      canvas.drawLine(
        Offset(_tearLineX + 0.5, y),
        Offset(_tearLineX + 0.5, end),
        dashes,
      );
      y += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_CardChrome old) =>
      old.accent != accent || old.muted != muted;
}

/// The signature element — the ticket's tear-off stub, carrying the date and
/// nothing else, for the card's whole height. [struck] is the no-show
/// treatment: the day number AND the time below it are ruled through — no
/// hue, no words, landing before the client has read anything.
///
/// Carries three stacked lines now: day number, weekday/month, and — moved
/// down from the body's old top-right corner — the slot time, directly under
/// the date it belongs to. See the library doc's ASCII grid and its "date
/// column" section for how the stub is now centred against the body.
class _DateStub extends StatelessWidget {
  const _DateStub({
    super.key,
    required this.bookingId,
    required this.start,
    required this.dimmed,
    this.struck = false,
  });

  /// Only needed so the stub's three stacked `Text`s can carry stable
  /// `ValueKey`s (`stub-day-$bookingId`, `stub-month-$bookingId`,
  /// `time-$bookingId`) — widget tests find them there.
  final String bookingId;
  final DateTime start;
  final bool dimmed;
  final bool struck;

  /// Sized to the widest UNBREAKABLE token the day line can produce — the
  /// genitive month «листопада,» measures 61.7 dp at statCaption's natural
  /// size (the whole «листопада, нд» line is 79 dp, but the weekday breaks
  /// onto a second line). 64 dp (`VelvetSpacing.xxl + VelvetSpacing.md`) clears
  /// that widest token with ~2 dp of margin, so the month never clips and never
  /// has to scale down: the 9 shorter months stay on one line, the three long
  /// ones («березня», «вересня», «листопада») wrap to two centred lines. It is
  /// narrower than the old scale-to-fit width (68), so [_tearLineX] shifts left
  /// and the Expanded body gains the freed space.
  ///
  /// Re-verified for the time line added below the month line: `formatSlotTime`
  /// always renders a fixed 5-glyph «HH:mm», measured (`TextPainter`, real
  /// Comfortaa) at [VelvetText.bookingTime] — 33.2 dp for «15:00», worst case
  /// 36.3 dp for «23:59». Both clear 64 dp with ample headroom (~28 dp), so the
  /// stub is NOT widened for the time; the `maxLines: 1` + ellipsis on the time
  /// `Text` below is a defensive floor only, for extreme accessibility text
  /// scales, mirroring the month line's own ellipsis floor.
  static const double width = VelvetSpacing.xxl + VelvetSpacing.md; // 64

  /// The tight leading between the stub's three stacked lines — one rhythm
  /// for the whole "when" cluster (day, weekday/month, time), not a
  /// `VelvetSpacing` token: even `.xs` (4) would loosen the cluster enough
  /// to read as three separate labels instead of one "when" unit. Also
  /// keeps the stub's total height close to the 52 dp photo's, so the two
  /// columns read as roughly matched blocks even though the stub is now
  /// centred against the whole body rather than pinned to the photo — see
  /// the library doc's "date column" section.
  static const double _lineGap = 2;

  @override
  Widget build(BuildContext context) {
    final Color dayColor = dimmed || struck
        ? BrandColors.textSecondary
        : BrandColors.text;

    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            formatStubDayNumber(start),
            key: ValueKey<String>('stub-day-$bookingId'),
            textAlign: TextAlign.center,
            style: VelvetText.bookingDayNumber.copyWith(
              color: dayColor,
              decoration: struck
                  ? TextDecoration.lineThrough
                  : TextDecoration.none,
              decorationColor: BrandColors.textSecondary.withValues(alpha: 0.8),
              decorationThickness: 1.8,
            ),
          ),
          const SizedBox(height: _lineGap),
          // Centred under the day number. At the stub's natural size no month
          // clips: the short ones sit on one line, «березня»/«вересня»/
          // «листопада» wrap to a second centred line rather than scaling. The
          // ellipsis is a defensive floor for extreme accessibility text scales
          // — it never triggers on real labels at normal scale.
          Text(
            formatStubDayLine(start),
            key: ValueKey<String>('stub-month-$bookingId'),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: VelvetText.bookingCardCaption.copyWith(
              color: dimmed ? BrandColors.faint : BrandColors.muted,
            ),
          ),
          const SizedBox(height: _lineGap),
          // ── WHEN, part two — the slot time, moved down from the body's
          //    old top-right corner so it reads as one unit with the date
          //    above it. Same colour/decoration contract the body copy used
          //    to carry, unchanged: dead bookings mute to BrandColors.muted,
          //    a no-show strikes the figure exactly like the day number does.
          Text(
            formatSlotTime(start),
            key: ValueKey<String>('time-$bookingId'),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: VelvetText.bookingTime.copyWith(
              color: dimmed ? BrandColors.muted : BrandColors.accentDeep,
              decoration: struck
                  ? TextDecoration.lineThrough
                  : TextDecoration.none,
              decorationColor: BrandColors.textSecondary.withValues(alpha: 0.8),
              decorationThickness: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// The master's photo — a network image when [avatarUrl] is a valid https
/// URL, else a camel-gradient disc with initials (mirrors
/// `ResultThumbnail`'s https-only guard: `Image.network` uses its own
/// HttpClient, not the app's pinned Dio, so a non-https URL falls straight
/// to the initials fallback rather than ever being requested).
///
/// 52 dp: sized to the identity text block beside it (name + title + salon
/// ≈ 52), so the photo no longer sets the card's floor height — the text
/// does.
class _MasterPhoto extends StatelessWidget {
  const _MasterPhoto({
    required this.avatarUrl,
    required this.initials,
    required this.dimmed,
  });

  final String? avatarUrl;
  final String initials;
  final bool dimmed;

  static const double size = 52;

  /// The lit (non-`dimmed`) disc's neumorphic pair. Hoisted to a static field
  /// — MO-7 made this widget one instance PER SERVICE CARD (was once per
  /// VISIT under the old grouped `VisitCard`), so a per-build allocation here
  /// is now N× more frequent. Mirrors `_BookingCardState._deadShadows`'s
  /// treatment for the same reason. `static final`, not `static const`:
  /// `Color.withValues` is not a const constructor.
  static final List<BoxShadow> _liftedShadows = <BoxShadow>[
    BoxShadow(
      color: BrandColors.shadowDarkCard.withValues(alpha: 0.75),
      offset: const Offset(3, 3),
      blurRadius: 8,
    ),
    const BoxShadow(
      color: BrandColors.shadowLightStrong,
      offset: Offset(-3, -3),
      blurRadius: 8,
    ),
  ];

  static const List<Color> _gradient = <Color>[
    BrandColors.accentLogo,
    BrandColors.accent,
    BrandColors.accentLatte,
  ];

  Widget _initialsDisc() {
    return Container(
      height: size,
      width: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _gradient,
          stops: <double>[0.0, 0.55, 1.0],
        ),
      ),
      child: Center(
        child: Text(
          initials,
          style: VelvetText.statValue().copyWith(color: BrandColors.white),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget disc = Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: dimmed ? null : _liftedShadows,
      ),
      // Shared media loader: the https-only + host-allowlist guard, the disk
      // cache, the socket-level TLS controls and the animated-WebP pin all
      // live in RemoteImage now (see core/media/beautica_image.dart). The
      // circular clip + gradient-initials fallback are unchanged.
      child: RemoteImage(
        url: avatarUrl,
        width: size,
        height: size,
        shape: RemoteImageShape.circle,
        excludeFromSemantics: true,
        fallback: _initialsDisc(),
      ),
    );
    // A cancelled booking's photo desaturates toward the base tone — the
    // person is no longer in the client's near future.
    return dimmed ? Opacity(opacity: 0.55, child: disc) : disc;
  }
}

/// WHAT is happening — the category glyph + the service name. The strongest
/// text in the card's body.
class _ServiceLine extends StatelessWidget {
  const _ServiceLine({
    required this.bookingId,
    required this.icon,
    required this.text,
    required this.price,
    required this.dimmed,
  });

  final String bookingId;
  final IconData icon;
  final String text;

  /// The already-formatted price locked in at booking — «650 ₴» or the band
  /// «300–500 ₴» (see [BookingDisplayX.priceLabel]) — or `null` when money is
  /// not a true statement (cancelled / declined / no-show). Null builds
  /// nothing.
  final String? price;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            icon,
            size: 14,
            color: dimmed ? BrandColors.faint : BrandColors.accent,
          ),
        ),
        const SizedBox(width: VelvetSpacing.xs),
        // Takes every pixel the price anchor leaves, ellipsising into it —
        // it can never push the price around, and with no price it simply
        // runs to the body's right edge.
        Expanded(
          child: Text(
            text,
            key: ValueKey<String>('service-$bookingId'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: VelvetText.bookingCardService.copyWith(
              color: dimmed ? BrandColors.textSecondary : BrandColors.text,
            ),
          ),
        ),
        if (price != null) ...<Widget>[
          const SizedBox(width: VelvetSpacing.xs),
          // ── THE RIGHT ANCHOR — a NON-flex child. See the library doc's
          // ⚠ note: a `Flexible` here would make this a second flex child
          // competing with the service name's `Expanded`, floating the
          // price off the margin by a variable amount per card.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _priceMaxWidth),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                price!,
                key: ValueKey<String>('price-$bookingId'),
                maxLines: 1,
                style: VelvetText.bookingCardPrice,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
