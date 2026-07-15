// Phase 14.3/14.4 — «Деталі запису», one booking opened from its
// `BookingCard`.
//
// Ported from `docs/signup-designs/MyBookings/lib/screens/booking_detail_screen.dart`.
//
// ## It is the SHIPPED booking-success screen, later
//
// Composes the SAME [BookingSuccessScaffold] both success screens do — the
// hero, staggered title/subline reveal, scrolling recap, pinned footer are
// all identical machinery. Four things differ, each forced (see the
// scaffold's own GENERALIZATION note for how each maps onto a new param):
//   1. `canPop: true` — this screen is PUSHED from a list, not
//      `pushReplacement`d over a submitted form; it must pop, and it gets a
//      `leading` back button the success screens have never needed.
//   2. `heroBuilder` — a static [BookingStatusMedallion], never a Lottie, on
//      ANY status. A celebration animation is a MOMENT (it fired when the
//      booking was made); replaying it every time this reference page opens
//      would cheapen the original — see that widget's doc.
//   3. `actions` — up to TWO pinned buttons for `CONFIRMED`
//      («Перенести»+«Скасувати запис»), not the success screens' one.
//   4. The title IS the status label, not a celebration headline.
//
// ## The action set, by status
//
// | status | `belowRecap` | pinned `actions` |
// |---|---|---|
// | CONFIRMED | «Додати в календар» | «Перенести» + «Скасувати запис» |
// | COMPLETED / CANCELLED / DECLINED | — | «Записатись знову» |
// | NOT_COMPLETED | — | (none) |
//
// Add-to-calendar is CONFIRMED-only (see `Booking.canAddToCalendar`) and
// lives in `belowRecap`, NOT the pinned footer — it copies the appointment
// somewhere else, it does not act ON the booking, so it does not belong in
// the primary/secondary action hierarchy. NOT_COMPLETED gets no rebook
// shortcut: offering one under the provider's own account of a no-show would
// read as the app brokering a reconciliation the client never asked for.
//
// go_router only: pushed at `/bookings/:bookingId` (nested under the
// Записи branch so it pops back onto that branch's own navigator stack).
//
// SEC: renders the master's/salon's address + free-text notes (PII) —
// acquires the app-wide [ScreenProtectionManager] for its lifetime, mirroring
// every other PII screen's acquire-in-`initState`/release-in-`dispose`
// pattern.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';

import '../application/booking_detail_notifier.dart';
import '../application/my_bookings_notifier.dart';
import '../data/booking_providers.dart';
import '../domain/booking.dart';
import '../domain/booking_display_x.dart';
import '../domain/booking_status.dart';
import '../domain/booking_tab.dart';
import 'widgets/booking_notes.dart';
import 'widgets/booking_recap.dart';
import 'widgets/booking_status_badge.dart';
import 'widgets/booking_status_medallion.dart';
import 'widgets/booking_summary_cards.dart';
import 'widgets/booking_success_scaffold.dart';
import 'widgets/calendar_button.dart';
import 'widgets/cancel_booking_dialog.dart';
import 'widgets/master_strip.dart';

/// «Деталі запису» for the booking identified by [bookingId].
class BookingDetailScreen extends ConsumerStatefulWidget {
  const BookingDetailScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  ConsumerState<BookingDetailScreen> createState() =>
      _BookingDetailScreenState();
}

class _BookingDetailScreenState extends ConsumerState<BookingDetailScreen> {
  // Captured in initState so dispose() never touches `ref` (Riverpod 3.x
  // throws on a post-dispose `ref` read).
  late final ScreenProtectionManager _screenProtection;

  @override
  void initState() {
    super.initState();
    _screenProtection = ref.read(screenProtectionProvider)..acquire();
  }

  @override
  void dispose() {
    _screenProtection.release();
    super.dispose();
  }

  /// «Скасувати запис» opens the confirmation — it never cancels anything
  /// itself. The dialog resolves to the client's note (possibly empty) on
  /// confirm, and to `null` on every way of backing out.
  Future<void> _confirmCancel(BuildContext context, Booking booking) async {
    final String? note = await showCancelBookingDialog(context, booking);
    if (note == null || !mounted) return; // backed out — nothing happened.

    try {
      await ref
          .read(bookingRepositoryProvider)
          .cancelBooking(booking.id, reason: note.isEmpty ? null : note);
    } catch (_) {
      if (!context.mounted) return;
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(l10n.errUnknown)));
      return;
    }
    if (!mounted) return;

    // Refetch this booking's fresh status and re-partition the two affected
    // tabs (it just left Майбутні and entered Скасовані) — the merged
    // per-status pagination in `MyBookingsNotifier` means a plain invalidate
    // of each tab cleanly re-fetches page 0 for every status it covers.
    ref.invalidate(bookingDetailProvider(booking.id));
    ref.invalidate(myBookingsProvider(BookingTab.upcoming));
    ref.invalidate(myBookingsProvider(BookingTab.cancelled));
  }

  void _onReschedule(BuildContext context) {
    // Phase 14.8 (reschedule) is not built yet — a calm, honest "not yet"
    // rather than a silent no-op.
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(l10n.bookingRescheduleComingSoon)));
  }

  void _onAddToCalendar() {
    // TODO(phase-14.x): wire a real OS calendar event once `add_2_calendar`
    // (or an ICS export) is reviewed and added to pubspec.yaml — see
    // `calendar_button.dart`'s file header. Intentionally a no-op for now.
  }

  void _onRebook(Booking booking) {
    // `BookingDetailResponse` carries `masterId` but no `salonId` — a salon
    // booking's own venue is not independently addressable from a booking
    // record. The master's own public profile is reachable either way and
    // is the only rebook target the data supports.
    context.push(RouteNames.masterPublicProfile(booking.masterId));
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<Booking> async = ref.watch(
      bookingDetailProvider(widget.bookingId),
    );

    return async.when(
      loading: () => const _DetailLoading(),
      error: (Object e, StackTrace _) => _DetailError(
        error: e,
        onRetry: () => ref.invalidate(bookingDetailProvider(widget.bookingId)),
      ),
      data: (Booking booking) => _DetailBody(
        booking: booking,
        onReschedule: () => _onReschedule(context),
        onCancel: () => _confirmCancel(context, booking),
        onRebook: () => _onRebook(booking),
        onAddToCalendar: _onAddToCalendar,
      ),
    );
  }
}

/// The populated screen — a thin declarative call site over
/// [BookingSuccessScaffold].
class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.booking,
    required this.onReschedule,
    required this.onCancel,
    required this.onRebook,
    required this.onAddToCalendar,
  });

  final Booking booking;
  final VoidCallback onReschedule;
  final VoidCallback onCancel;
  final VoidCallback onRebook;
  final VoidCallback onAddToCalendar;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final BookingStatusVisual v = BookingStatusVisual.of(booking, l10n);
    final (String? addressValue, String? addressDetail) = booking.addressBlock;

    return BookingSuccessScaffold(
      title: v.label,
      subline: _subline(booking, l10n),
      canPop: true,
      leading: _BackButton(semanticLabel: l10n.bookingDetailBackSemantics),
      heroBuilder: (AnimationController controller) =>
          BookingStatusMedallion(visual: v, controller: controller),
      belowRecap: booking.canAddToCalendar
          ? CalendarButton(onTap: onAddToCalendar)
          : null,
      actions: _actions(l10n),
      recapCards: <Widget>[
        BookingSummaryCards(
          masterCard: MasterStripFromBooking(booking: booking),
          salonName: booking.salonName,
          addressLine: addressValue,
          addressDetail: addressDetail,
          // Omitted entirely when the provider has no location on file at
          // all — no «Адресу не вказано» placeholder on this page, mirroring
          // every other optional field.
          hideAddressWhenEmpty: true,
          // The arrival hint — a property of the PLACE, not a note anyone
          // sent. Renders inside the address block, with neither note
          // container.
          locationNote: booking.locationNote,
          dateLabel: formatFullDate(booking.startAt),
          timeLabel: formatTimeRange(booking.startAt, booking.durationMinutes),
          // ONE service — a booking is not a selection. See
          // `BookingRecap.single`'s doc.
          singleSelection: BookingSelection(
            name: booking.serviceName,
            price: '${booking.price.toStringAsFixed(0)} ₴',
            duration: booking.durationLabel,
          ),
          dense: true,
          showBorder: true,
          compactText: true,
          // See `Booking.showsPrice`: a cancelled, declined or missed
          // appointment owes nothing — printing a sum on it would assert a
          // debt that does not exist.
          showPrice: booking.showsPrice,
        ),

        // ── Every note this booking carries, in the order they were
        //    written. The ONLY surface that renders note text — the card
        //    shows none.
        if (BookingNotes.has(booking, l10n)) BookingNotes(booking: booking),
      ],
    );
  }

  /// One calm sentence per status, in the app's own neutral voice. The
  /// no-show line is agent-less on purpose — the app records that the visit
  /// did not happen and points at the provider's own words; it never itself
  /// tells the client they failed to show up.
  String _subline(Booking b, AppLocalizations l10n) {
    switch (b.status) {
      case BookingStatus.pending:
      case BookingStatus.confirmed:
        return l10n.bookingDetailSublineConfirmed;
      case BookingStatus.completed:
        return l10n.bookingDetailSublineCompleted;
      case BookingStatus.notCompleted:
        return l10n.bookingDetailSublineNotCompleted(b.providerGenitive);
      case BookingStatus.cancelled:
        return l10n.bookingDetailSublineCancelled;
      case BookingStatus.declined:
        return b.atSalon
            ? l10n.bookingDetailSublineDeclinedSalon
            : l10n.bookingDetailSublineDeclinedMaster;
    }
  }

  /// The pinned footer. An empty list renders no footer at all.
  List<Widget> _actions(AppLocalizations l10n) {
    switch (booking.status) {
      case BookingStatus.pending:
      case BookingStatus.confirmed:
        return <Widget>[
          NeumorphicButton(
            label: l10n.bookingDetailRescheduleCta,
            icon: Icons.event_repeat_rounded,
            onPressed: onReschedule,
          ),
          const SizedBox(height: VelvetSpacing.xs),
          _DestructiveSecondaryButton(
            label: l10n.bookingDetailCancelCta,
            icon: Icons.close_rounded,
            onTap: onCancel,
          ),
        ];

      // A kept appointment is the strongest rebook signal there is; a
      // cancelled one leaves an unmet need whoever ended it — same label in
      // all three, because an action keeps its name.
      case BookingStatus.completed:
      case BookingStatus.cancelled:
      case BookingStatus.declined:
        return <Widget>[
          NeumorphicButton(
            label: l10n.bookingDetailRebookCta,
            icon: Icons.refresh_rounded,
            onPressed: onRebook,
          ),
        ];

      // Deliberately nothing — see the file header.
      case BookingStatus.notCompleted:
        return const <Widget>[];
    }
  }
}

/// Adapts [MasterStrip] to the enriched [Booking] fields — mirrors
/// `MasterStrip.fromMaster`/`.fromSchedule`'s pattern, but a `Booking` has
/// no [MasterType] on the wire the strip's constructor set expects, so this
/// composes the base [MasterStrip] constructor directly instead of adding a
/// fourth factory to a widget three other flows already share.
class MasterStripFromBooking extends StatelessWidget {
  const MasterStripFromBooking({super.key, required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final bool isDead =
        booking.status == BookingStatus.cancelled ||
        booking.status == BookingStatus.declined;
    return Opacity(
      opacity: isDead ? 0.7 : 1,
      child: MasterStrip(
        name: booking.masterName,
        // A booking record carries no live `MasterType` — the strip's
        // fallback role label is resolved directly from `atSalon` instead
        // (mirrors `masterRoleLabel`'s two salon-vs-independent strings).
        type: booking.atSalon
            ? MasterType.salonMaster
            : MasterType.independentMaster,
        professionalTitle: booking.masterProfessionalTitle,
        showRole: true,
        showRating: false,
      ),
    );
  }
}

/// The un-animated back affordance — see `BookingSuccessScaffold.leading`'s
/// doc for why the shared scaffold needed this extra slot.
class _BackButton extends StatelessWidget {
  const _BackButton({required this.semanticLabel});

  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return NeumorphicIconButton(
      key: const Key('booking-detail-back'),
      icon: Icons.arrow_back_ios_new_rounded,
      semanticLabel: semanticLabel,
      onTap: () => context.pop(),
    );
  }
}

/// The **destructive** secondary — «Скасувати запис». Still the shipped
/// `_SecondaryButton`'s raised base-tone pill shape (so the two-tier
/// hierarchy under «Перенести» is intact), recoloured to read as destructive
/// at a glance: an `error` hairline edge, an `error` glyph, the label in
/// `error`.
///
/// Deliberately NOT a red slab — a booking you are merely LOOKING AT should
/// not have a red brick sitting on it (that would make every upcoming
/// appointment feel like a hazard, and it would outshout «Перенести», the
/// action most people actually want). The saturated fill is spent exactly
/// once, on `CancelBookingDialog`'s confirm button, where the act is already
/// decided.
class _DestructiveSecondaryButton extends StatefulWidget {
  const _DestructiveSecondaryButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_DestructiveSecondaryButton> createState() =>
      _DestructiveSecondaryButtonState();
}

class _DestructiveSecondaryButtonState
    extends State<_DestructiveSecondaryButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        key: const Key('booking-detail-cancel'),
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: VelvetSizes.cta,
          decoration: BoxDecoration(
            color: BrandColors.base,
            borderRadius: BorderRadius.circular(VelvetRadii.button),
            boxShadow: _pressed ? null : VelvetShadows.extrudedButton,
            border: Border.all(
              color: BrandColors.error.withValues(alpha: 0.55),
              width: 1.2,
            ),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(widget.icon, size: 18, color: BrandColors.error),
              const SizedBox(width: VelvetSpacing.xs),
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: VelvetText.cta().copyWith(color: BrandColors.error),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Loading skeleton for the detail fetch — a bare centred spinner behind the
/// SAME un-animated back affordance the populated screen uses, so a slow
/// fetch never traps the client without a way out.
class _DetailLoading extends StatelessWidget {
  const _DetailLoading();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: BrandColors.base,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            VelvetSpacing.lg,
            VelvetSpacing.xs,
            VelvetSpacing.lg,
            VelvetSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _BackButton(semanticLabel: l10n.bookingDetailBackSemantics),
              const Expanded(
                child: Center(
                  child: CircularProgressIndicator(color: BrandColors.accent),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The error state — the failure message + a retry button, behind the same
/// back affordance.
class _DetailError extends StatelessWidget {
  const _DetailError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: BrandColors.base,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            VelvetSpacing.lg,
            VelvetSpacing.xs,
            VelvetSpacing.lg,
            VelvetSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _BackButton(semanticLabel: l10n.bookingDetailBackSemantics),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(
                          Icons.cloud_off_rounded,
                          size: 48,
                          color: BrandColors.muted,
                        ),
                        const SizedBox(height: VelvetSpacing.md),
                        Text(
                          l10n.errUnknown,
                          textAlign: TextAlign.center,
                          style: VelvetText.body(),
                        ),
                        const SizedBox(height: VelvetSpacing.lg),
                        SizedBox(
                          width: double.infinity,
                          child: NeumorphicButton(
                            key: const Key('booking-detail-error-retry'),
                            label: l10n.retryLabel,
                            icon: Icons.refresh_rounded,
                            onPressed: onRetry,
                          ),
                        ),
                      ],
                    ),
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
