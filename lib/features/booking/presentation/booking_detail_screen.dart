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
// | status | `headerTrailing` | pinned `actions` |
// |---|---|---|
// | CONFIRMED | 📅 icon | «Перенести» + «Скасувати запис» |
// | COMPLETED / CANCELLED / DECLINED | — | «Записатись знову» |
// | NOT_COMPLETED | — | (none) |
//
// Add-to-calendar is CONFIRMED-only (see `Booking.canAddToCalendar`) and
// lives as a calendar icon in the header row opposite the back button (via the
// scaffold's `headerTrailing` slot), NOT the pinned footer — it copies the
// appointment somewhere else, it does not act ON the booking, so it does not
// belong in the primary/destructive action hierarchy. (Before, it sat in the
// scroll body as a full-width `CalendarButton` pill in `belowRecap`; that pill
// still serves both success screens + the home hub.) NOT_COMPLETED gets no
// rebook shortcut: offering one under the provider's own account of a no-show
// would read as the app brokering a reconciliation the client never asked for.
//
// go_router only: pushed at `/bookings/:bookingId` (nested under the
// Записи branch so it pops back onto that branch's own navigator stack).
//
// SEC: renders the master's/salon's address + free-text notes (PII) —
// acquires the app-wide [ScreenProtectionManager] for its lifetime, mirroring
// every other PII screen's acquire-in-`initState`/release-in-`dispose`
// pattern.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/calendar/add_to_calendar.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';
import 'package:beautica_mobile/shared/formatters/service_price_display.dart';

import '../application/booking_detail_notifier.dart';
import '../application/booking_reschedule_in_flight_notifier.dart';
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
import 'widgets/cancel_booking_dialog.dart';
import 'widgets/master_strip.dart';
import 'reschedule_navigation.dart';

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
    } on BookingAlreadyElapsedFailure catch (failure) {
      // The slot elapsed against the SERVER clock between this (possibly stale)
      // screen opening and the confirm tap — or the device clock was rolled
      // back and the server refused to honour it. Surface the clean localized
      // message AND refetch the booking so it re-renders read-only (Reschedule
      // + Cancel drop away, «Записатись знову» takes their place) — never a
      // raw 409.
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(failure.userMessage(context))));
      ref.invalidate(bookingDetailProvider(booking.id));
      return;
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

  void _onReschedule(BuildContext context, Booking booking) {
    // Reuse the create-booking slot picker, seeded to reschedule THIS booking
    // (the confirm-step submit swaps POST → PATCH /reschedule on the non-null
    // rescheduleBookingId). Confirmed-only — the CTA below is gated to match.
    unawaited(
      startBookingReschedule(context: context, ref: ref, bookingId: booking.id),
    );
  }

  /// Opens the OS calendar's "new event" sheet for this CONFIRMED booking.
  /// [Booking.startAt]/[Booking.endAt] are non-nullable, so the CONFIRMED-only
  /// [Booking.canAddToCalendar] gate is the sole precondition — no null guard
  /// is reachable here.
  Future<void> _onAddToCalendar(BuildContext context, Booking booking) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    // A salon booking names the SALON; an independent-master booking names the
    // MASTER (mirrors the recap card + notes heading's atSalon split).
    final String provider = booking.salonName ?? booking.masterName;
    // Structured facts only — NO free-text note fields (clientComment /
    // providerComment / clientCancellationNote) are passed. The date+time and
    // price reuse the exact strings the recap card renders on-screen. Price is
    // gated by `showsPrice` (a cancelled/declined/no-show booking owes
    // nothing) — but this path is CONFIRMED-only, so it is always present.
    final String? description = buildCalendarDescription(
      l10n: l10n,
      service: booking.serviceName,
      provider: provider,
      providerRole: booking.atSalon
          ? CalendarProviderRole.salon
          : CalendarProviderRole.master,
      dateTime:
          '${formatFullDate(booking.startAt)}, '
          '${formatTimeRange(booking.startAt, booking.durationMinutes)}',
      address: booking.addressLine,
      price: booking.showsPrice
          ? '${booking.price.toStringAsFixed(0)} ${ServicePriceDisplay.suffix}'
          : null,
      status: BookingStatusVisual.of(booking, l10n).label,
    );
    return addBookingToCalendar(
      context: context,
      title: l10n.bookingCalendarEventTitle(booking.serviceName, provider),
      // The composed street/district/city line — reuses the same
      // `composeAddressLine` derivation the recap card shows.
      location: booking.addressLine,
      start: booking.startAt,
      end: booking.endAt,
      description: description,
    );
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
    // Drives the «Перенести» button's spinner while the shared reschedule
    // navigation loads its seeding GETs (before it pushes the slot picker).
    final bool rescheduleLoading = ref.watch(bookingRescheduleInFlightProvider);

    return async.when(
      loading: () => const _DetailLoading(),
      error: (Object e, StackTrace _) => _DetailError(
        error: e,
        onRetry: () => ref.invalidate(bookingDetailProvider(widget.bookingId)),
      ),
      data: (Booking booking) => _DetailBody(
        booking: booking,
        rescheduleLoading: rescheduleLoading,
        onReschedule: () => _onReschedule(context, booking),
        onCancel: () => _confirmCancel(context, booking),
        onRebook: () => _onRebook(booking),
        onAddToCalendar: () => _onAddToCalendar(context, booking),
      ),
    );
  }
}

/// The populated screen — a thin declarative call site over
/// [BookingSuccessScaffold].
class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.booking,
    required this.rescheduleLoading,
    required this.onReschedule,
    required this.onCancel,
    required this.onRebook,
    required this.onAddToCalendar,
  });

  final Booking booking;
  final bool rescheduleLoading;
  final VoidCallback onReschedule;
  final VoidCallback onCancel;
  final VoidCallback onRebook;
  final VoidCallback onAddToCalendar;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final BookingStatusVisual v = BookingStatusVisual.of(booking, l10n);
    final (String? addressValue, String? addressDetail) = booking.addressBlock;

    // Only COMPLETED and NOT_COMPLETED still carry the big status hero (the
    // medallion + status title). CONFIRMED drops it (a confirmed booking needs
    // no ceremony — the subline suffices); CANCELLED and DECLINED drop it too
    // (product decision 2026-07-15: no medallion, no big «Скасовано» title —
    // the neutral state reads through the subline alone).
    final bool showStatusHero =
        booking.status == BookingStatus.completed ||
        booking.status == BookingStatus.notCompleted;

    return BookingSuccessScaffold(
      title: showStatusHero ? v.label : null,
      subline: _subline(booking, l10n),
      canPop: true,
      leading: _BackButton(semanticLabel: l10n.bookingDetailBackSemantics),
      // «Додати в календар» now lives as a header icon opposite the back
      // button (CONFIRMED-only via `canAddToCalendar`), freeing the pinned
      // footer to a clean two-button stack. It copies the appointment
      // elsewhere — it does not act ON the booking — so it belongs at the top,
      // not in the primary/destructive action hierarchy below. Also dropped
      // once the slot has ELAPSED (`isPast`): adding a past event to a calendar
      // is pointless, and an elapsed CONFIRMED booking is read-only anyway.
      headerTrailing: booking.canAddToCalendar && !booking.isPast
          ? _CalendarIconButton(onTap: onAddToCalendar)
          : null,
      showHero: showStatusHero,
      heroBuilder: showStatusHero
          ? (AnimationController controller) =>
                BookingStatusMedallion(visual: v, controller: controller)
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
  String? _subline(Booking b, AppLocalizations l10n) {
    switch (b.status) {
      case BookingStatus.pending:
      case BookingStatus.confirmed:
        // The reminder ("Нагадаємо про запис напередодні.") is an
        // upcoming-only affordance. An ELAPSED CONFIRMED booking is already
        // read-only (Reschedule/Cancel/Add-to-calendar all hidden, «Записатись
        // знову» shown), so drop the reminder too — reminding about a visit
        // whose time has passed is meaningless.
        if (b.status == BookingStatus.confirmed && b.isPast) {
          return null;
        }
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
        // An ELAPSED CONFIRMED booking is READ-ONLY: its slot is already in the
        // past, so Reschedule + Cancel no longer apply (the backend 409s both
        // with BOOKING_ALREADY_ELAPSED — the server clock is authoritative).
        // Route it into the SAME «Записатись знову» affordance the terminal
        // states use, rather than showing actions that can only fail.
        if (booking.status == BookingStatus.confirmed && booking.isPast) {
          return _rebookActions(l10n);
        }
        return <Widget>[
          // Reschedule is CONFIRMED-only (backend `PATCH …/reschedule`); a
          // PENDING booking would 409, so the «Перенести» CTA is shown only
          // for CONFIRMED. Cancel stays available on both.
          if (booking.status == BookingStatus.confirmed) ...<Widget>[
            NeumorphicButton(
              key: const Key('booking-detail-reschedule'),
              label: l10n.bookingDetailRescheduleCta,
              icon: Icons.event_repeat_rounded,
              loading: rescheduleLoading,
              onPressed: onReschedule,
            ),
            const SizedBox(height: VelvetSpacing.xs),
          ],
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
        return _rebookActions(l10n);

      // Deliberately nothing — see the file header.
      case BookingStatus.notCompleted:
        return const <Widget>[];
    }
  }

  /// The single «Записатись знову» footer — shared by the terminal states
  /// (COMPLETED / CANCELLED / DECLINED) and by an elapsed CONFIRMED booking,
  /// which is likewise read-only and offers rebooking as its only forward
  /// action.
  List<Widget> _rebookActions(AppLocalizations l10n) => <Widget>[
    NeumorphicButton(
      label: l10n.bookingDetailRebookCta,
      icon: Icons.refresh_rounded,
      onPressed: onRebook,
    ),
  ];
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

/// The trailing header affordance — «Додати в календар», CONFIRMED-only.
/// Relocated out of the scroll body's full-width `CalendarButton` pill (which
/// still serves both success screens + the home hub) into a header icon that
/// reads as a matched pair with `_BackButton`: the SAME [NeumorphicIconButton]
/// shell (48 dp raised base-tone square, `extrudedSmall` shadow), so back and
/// calendar sit symmetric at the two ends of the header row. The one
/// difference carries meaning — the back arrow keeps the neutral
/// `textSecondary` tint, this calendar glyph takes the camel `accentDeep`
/// tint (echoing the old pill's own glyph), quietly marking it as the header's
/// single actionable control. Reuses the existing `bookingAddCalendarSemantics`
/// label (a11y unchanged) and the `bookingSuccessAddCalendarCta` string as its
/// long-press tooltip; its `onTap` is the SAME `_onAddToCalendar` handler, so
/// the structured event description is preserved verbatim.
class _CalendarIconButton extends StatelessWidget {
  const _CalendarIconButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Tooltip(
      message: l10n.bookingSuccessAddCalendarCta,
      child: NeumorphicIconButton(
        key: const Key('booking-detail-add-calendar'),
        iconWidget: const Icon(
          // Material Symbols «calendar_add_on» (rounded cut) — a calendar page
          // with a «+», so the textless header affordance reads as "add to
          // calendar" on its own. The `_rounded` variant is chosen over the
          // package's default (outlined) `Symbols.calendar_add_on` to sit with
          // the app's `*_rounded` glyph family (e.g. `arrow_back_ios_new_rounded`
          // on the paired back button). Default weight 400 / fill 0 keeps it a
          // const IconData → release icon tree-shaking subsets the font.
          Symbols.calendar_add_on_rounded,
          color: BrandColors.accentDeep,
          size: 22,
        ),
        semanticLabel: l10n.bookingAddCalendarSemantics,
        onTap: onTap,
      ),
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
          // Top inset MUST match `BookingSuccessScaffold`'s (`lg`) so the shared
          // back affordance keeps a fixed Y as this skeleton swaps to the loaded
          // body — otherwise the arrow jumps down 20dp mid page-open transition.
          padding: const EdgeInsets.fromLTRB(
            VelvetSpacing.lg,
            VelvetSpacing.lg,
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
          // Top inset MUST match `BookingSuccessScaffold`'s (`lg`) so the shared
          // back affordance keeps a fixed Y as this skeleton swaps to the loaded
          // body — otherwise the arrow jumps down 20dp mid page-open transition.
          padding: const EdgeInsets.fromLTRB(
            VelvetSpacing.lg,
            VelvetSpacing.lg,
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
