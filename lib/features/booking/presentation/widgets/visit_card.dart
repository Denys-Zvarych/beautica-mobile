// MO-5 — one multi-service VISIT in the «МОЇ ЗАПИСИ» list.
//
// A `part of booking_card.dart` (see that file's `part` directive for why): it
// reuses the single-service card's private ticket chrome — the painted status
// rail + dashed tear line ([_CardChrome]), the exclusive date-stub column
// ([_DateStub]), the master photo ([_MasterPhoto]), the price-anchored service
// line ([_ServiceLine]) and every grid constant — so the two cards can never
// drift, while the single-service card's own render stays byte-for-byte
// unchanged.
//
// ## What differs from `BookingCard`
//
// Only the middle "what" region. A single booking shows one [_ServiceLine]
// (glyph + service name + price); a visit shows:
//   1. a SUMMARY line — reusing the same [_ServiceLine] mechanics — a stacked-
//      services glyph + «N послуг · 1 год 30 хв», with the visit TOTAL price
//      («650 ₴» or the summed band «300–500 ₴») pinned hard-right at the same x
//      as the time above it;
//   2. an ordered [_VisitServiceList] beneath — up to three service names, each
//      a small camel dot + ellipsised name, with a «+ N послуг» overflow row.
//
// Everything else — the rail's status accent, the tear line, the date stub, the
// master identity block, the time top-right, the status badge + chevron, the
// depth-as-time-axis shadows, the press-scale — is identical to `BookingCard`,
// derived from the visit's shared lead row (all rows of a visit share the same
// master and the same status — all-or-nothing on the wire).

part of 'booking_card.dart';

/// One multi-service visit in the «МОЇ ЗАПИСИ» list. See the part-file doc.
class VisitCard extends StatefulWidget {
  const VisitCard({
    super.key,
    required this.entry,
    required this.onOpenDetails,
  });

  final VisitBookingEntry entry;

  /// The card's ONLY callback — opens the visit detail (`GET /appointments/{id}`).
  final VoidCallback onOpenDetails;

  @override
  State<VisitCard> createState() => _VisitCardState();
}

class _VisitCardState extends State<VisitCard> {
  bool _pressed = false;

  /// The visit's rows ordered by start instant + the derived lead row, computed
  /// ONCE per entry (not per build, and not on every `_pressed` rebuild). This
  /// mirrors `VisitBookingEntryX.orderedBookings` / `.lead` byte-for-byte — same
  /// sort, same lead — but the card reads these getters ~12× per build, so
  /// caching keeps the single sort a single sort. Recomputed in [didUpdateWidget]
  /// whenever the parent hands us a different entry object.
  late List<Booking> _ordered;
  late Booking _lead;

  @override
  void initState() {
    super.initState();
    _recomputeOrder();
  }

  @override
  void didUpdateWidget(covariant VisitCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.entry, widget.entry)) _recomputeOrder();
  }

  void _recomputeOrder() {
    final List<Booking> sorted = List<Booking>.of(widget.entry.bookings)
      ..sort((Booking a, Booking b) => a.startAt.compareTo(b.startAt));
    _ordered = sorted;
    _lead = sorted.first;
  }

  VisitBookingEntry get _e => widget.entry;

  bool get _isNoShow => _lead.status == BookingStatus.notCompleted;

  bool get _isDead =>
      _lead.status == BookingStatus.cancelled ||
      _lead.status == BookingStatus.declined;

  /// Mirrors `_BookingCardState._deadShadows` — a single soft ground shadow, no
  /// lift, for a cancelled / declined visit.
  static final List<BoxShadow> _deadShadows = <BoxShadow>[
    BoxShadow(
      color: BrandColors.shadowDarkCard.withValues(alpha: 0.40),
      offset: const Offset(0, 4),
      blurRadius: 12,
    ),
  ];

  /// Depth-as-time-axis, identical to `_BookingCardState._shadows`.
  List<BoxShadow>? get _shadows {
    if (_pressed) return null;
    return switch (_lead.status) {
      BookingStatus.confirmed => VelvetShadows.extrudedCard,
      BookingStatus.completed ||
      BookingStatus.notCompleted ||
      BookingStatus.unknown => VelvetShadows.extrudedSmall,
      BookingStatus.cancelled || BookingStatus.declined => _deadShadows,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final BookingStatusVisual v = BookingStatusVisual.of(_lead, l10n);

    return Semantics(
      button: true,
      label: l10n.bookingCardSemantics(
        formatServiceCountUk(_e.serviceCount),
        _lead.masterName,
        formatFullDate(_lead.startAt),
        formatSlotTime(_lead.startAt),
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
              border: _isDead
                  ? Border.all(color: BrandColors.faint.withValues(alpha: 0.55))
                  : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(VelvetRadii.card),
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.only(top: _stubTopOffset),
                        child: _DateStub(
                          key: ValueKey<String>(
                            'stub-visit-${_e.appointmentId}',
                          ),
                          start: _lead.startAt,
                          dimmed: _isDead,
                          struck: _isNoShow,
                        ),
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
        // ── The single visit start time, top-right — diagonally opposite the
        //    day number, exactly as the single card.
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            formatSlotTime(_lead.startAt),
            key: ValueKey<String>('visit-time-${_e.appointmentId}'),
            style: VelvetText.bookingTime.copyWith(
              color: _isDead ? BrandColors.muted : BrandColors.accentDeep,
              decoration: _isNoShow
                  ? TextDecoration.lineThrough
                  : TextDecoration.none,
              decorationColor: BrandColors.textSecondary.withValues(alpha: 0.8),
              decorationThickness: 1.5,
            ),
          ),
        ),
        const SizedBox(height: VelvetSpacing.xs),

        _identity(),
        const SizedBox(height: VelvetSpacing.xs),

        // ── WHAT — the visit summary. Reuses `_ServiceLine`'s exact glyph +
        //    text + right-anchored price mechanics; the text is the
        //    «N послуг · <summed duration>» count instead of one service name,
        //    and the price is the visit TOTAL (band-aware), gated by the shared
        //    `showsPrice` rule.
        _ServiceLine(
          bookingId: 'visit-${_e.appointmentId}',
          icon: Icons.auto_awesome_motion_rounded,
          text:
              '${formatServiceCountUk(_e.serviceCount)} · '
              '${DurationMinutes.format(_e.summedDurationMinutes)}',
          price: _lead.showsPrice ? _e.priceLabel : null,
          dimmed: _isDead,
        ),
        const SizedBox(height: VelvetSpacing.xs),

        // ── The ordered service names, the visit's own signature — the one
        //    thing a single card never shows.
        _VisitServiceList(
          appointmentId: _e.appointmentId,
          names: <String>[for (final Booking b in _ordered) b.serviceName],
          dimmed: _isDead,
        ),
        const SizedBox(height: VelvetSpacing.xs),

        // ── Status, and the chevron that says the row opens.
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Flexible(child: BookingStatusBadge(booking: _lead)),
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

  /// WHO — identical composition to `_BookingCardState._identity`, reading the
  /// shared lead row. Kept as its own method (rather than a shared widget) so
  /// the single-service card's method stays untouched; the delicate parts
  /// ([_MasterPhoto]) are the shared pieces.
  Widget _identity() {
    final String? title = _lead.masterProfessionalTitle;
    final String? salon = _lead.salonName;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        _MasterPhoto(
          avatarUrl: _lead.masterAvatarUrl,
          initials: _lead.masterInitials,
          dimmed: _isDead,
        ),
        const SizedBox(width: VelvetSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                _lead.masterName,
                key: ValueKey<String>('master-name-visit-${_e.appointmentId}'),
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

/// The ordered service names of a visit — the middle region's second row. Up to
/// [_maxRows] names are shown, each a small camel dot + ellipsised name; a visit
/// with more collapses the tail into a «+ N послуг» overflow row so the card's
/// height stays bounded no matter how many services the visit bundles.
class _VisitServiceList extends StatelessWidget {
  const _VisitServiceList({
    required this.appointmentId,
    required this.names,
    required this.dimmed,
  });

  final String appointmentId;
  final List<String> names;
  final bool dimmed;

  /// The most name rows drawn — including the overflow row when it applies.
  static const int _maxRows = 3;

  @override
  Widget build(BuildContext context) {
    // When the list fits, show every name; otherwise show the first
    // `_maxRows - 1` and fold the rest into one overflow row (always ≤ _maxRows
    // rows total).
    final bool overflowing = names.length > _maxRows;
    final int shown = overflowing ? _maxRows - 1 : names.length;
    final int remaining = names.length - shown;

    final Color dotColor = dimmed ? BrandColors.faint : BrandColors.accent;
    final Color nameColor = dimmed
        ? BrandColors.textSecondary
        : BrandColors.text;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < shown; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: 3),
          _VisitServiceRow(
            key: ValueKey<String>('visit-service-$appointmentId-$i'),
            name: names[i],
            dotColor: dotColor,
            nameColor: nameColor,
          ),
        ],
        if (remaining > 0) ...<Widget>[
          const SizedBox(height: 3),
          Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Text(
              '+ ${formatServiceCountUk(remaining)}',
              key: ValueKey<String>('visit-services-more-$appointmentId'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: VelvetText.bookingCardCaption.copyWith(
                color: dimmed ? BrandColors.faint : BrandColors.muted,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// One name row of [_VisitServiceList] — a 4 dp camel dot + the ellipsised
/// service name.
class _VisitServiceRow extends StatelessWidget {
  const _VisitServiceRow({
    super.key,
    required this.name,
    required this.dotColor,
    required this.nameColor,
  });

  final String name;
  final Color dotColor;
  final Color nameColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: VelvetSpacing.xs + 2),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: VelvetText.bookingCardSubtle.copyWith(color: nameColor),
          ),
        ),
      ],
    );
  }
}
