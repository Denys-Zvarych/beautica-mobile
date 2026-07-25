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
// The table above is the CLIENT footer. A PROVIDER viewer (track 27.x Wave
// A) gets an entirely different set — «Перенести» + «Скасувати»
// (CONFIRMED, not yet started) or «Завершити» + «Скасувати» (CONFIRMED,
// [BookingDisplayX.hasStarted] — the backend now allows a provider decline
// at any time, elapsed or not), nothing on any terminal status — built by
// `_DetailBody._providerActions`, never this switch. See
// `booking_viewer_role.dart` for the role derivation and
// `_DetailBody._actions`'s doc for the dispatch.
//
// Add-to-calendar is CONFIRMED-only (see `Booking.canAddToCalendar`) and
// lives as a calendar icon in the header row opposite the back button (via the
// scaffold's `headerTrailing` slot), NOT the pinned footer — it copies the
// appointment somewhere else, it does not act ON the booking, so it does not
// belong in the primary/destructive action hierarchy. (Before, it sat in the
// scroll body as a full-width `CalendarButton` pill in a page-level slot below
// the recap; that slot is gone — the success screens now hang a compact
// `CalendarButton` off each appointment card instead.) NOT_COMPLETED gets no
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

import '../application/booking_detail_notifier.dart';
import '../application/booking_reschedule_in_flight_notifier.dart';
import '../application/booking_viewer_role.dart';
import '../application/bookings_day_notifier.dart';
import '../application/my_bookings_notifier.dart';
import '../data/booking_providers.dart';
import '../domain/booking.dart';
import '../domain/booking_display_x.dart';
import '../domain/booking_status.dart';
import '../domain/booking_tab.dart';
import 'widgets/booking_counterparty_header.dart';
import 'widgets/booking_notes.dart';
import 'widgets/booking_recap.dart';
import 'widgets/booking_status_badge.dart';
import 'widgets/booking_status_medallion.dart';
import 'widgets/booking_summary_cards.dart';
import 'widgets/booking_success_scaffold.dart';
import 'widgets/cancel_booking_dialog.dart';
import 'widgets/complete_booking_dialog.dart';
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

  /// Track 27.x Wave A — the PROVIDER's «Скасувати» opens the decline
  /// confirmation; mirrors [_confirmCancel]'s shape exactly (dialog →
  /// repository call → 409-specific handling → refetch), swapped to the
  /// provider's own dialog/repository method/failure type.
  ///
  /// Track 27.x/MO-6: when [Booking.appointmentId] is non-null this booking
  /// is one service of a multi-service VISIT — the backend's
  /// `assertNotAppointmentChild` guard 409s a per-booking decline on an
  /// appointment child (`"…use /appointments/{id} to change it"`), so the
  /// write routes to `AppointmentRepository.declineAppointment` instead,
  /// transitioning every service in the visit in lockstep. The dialog itself
  /// is told via `isAppointment` so its copy reads "the whole visit", not
  /// just this one service. A booking with a `null` `appointmentId` (a plain
  /// single-service booking) is UNCHANGED — same dialog, same
  /// `BookingRepository.declineBooking` call, same failure handling.
  Future<void> _confirmDecline(BuildContext context, Booking booking) async {
    final bool isAppointment = booking.appointmentId != null;
    final String? comment = await showDeclineBookingDialog(
      context,
      booking,
      isAppointment: isAppointment,
    );
    if (comment == null || !mounted) return; // backed out — nothing happened.

    try {
      final String? appointmentId = booking.appointmentId;
      if (appointmentId != null) {
        await ref
            .read(appointmentRepositoryProvider)
            .declineAppointment(
              appointmentId,
              comment: comment.isEmpty ? null : comment,
            );
      } else {
        await ref
            .read(bookingRepositoryProvider)
            .declineBooking(
              booking.id,
              comment: comment.isEmpty ? null : comment,
            );
      }
    } on ProviderDeclineWindowClosedFailure catch (failure) {
      // Defense-in-depth only — the backend now allows a provider decline at
      // any time (elapsed or not), so this 409 is not expected in normal
      // operation. If some OTHER server-side rejection still lands here,
      // surface the clean localized message AND refetch so the footer
      // re-renders from the server's authoritative state, never a raw 409.
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
    ref.invalidate(bookingDetailProvider(booking.id));
    // The booking just left CONFIRMED for DECLINED — the master's own
    // «Мої записи» day timeline (`master_bookings_screen.dart` /
    // `bookings_discovery_view.dart`, both reading `bookingsDayProvider`)
    // would otherwise keep showing it as CONFIRMED until its bounded
    // keepAlive cache (≤3 days, `DayKeepAliveLru`) happens to evict and
    // refetch on its own. Passing the bare FAMILY (no query argument) drops
    // every cached day's value at once; Riverpod only EAGERLY recomputes the
    // family members that still have an active listener right now (at most
    // the ≤3-entry LRU's worth), so the actual refetch cost is bounded — any
    // other cached day refetches lazily the next time it's watched. Cheaper
    // than guessing which single `BookingsDayQuery` (day + filters) the
    // master was last viewing, which this screen has no way to know. Mirrors
    // `_confirmCancel`'s `myBookingsProvider` invalidation above, one family
    // reference standing in for that enumerable tab set.
    ref.invalidate(bookingsDayProvider);
  }

  /// Track 27.x Wave A — the PROVIDER's «Завершити» opens a plain confirm
  /// dialog (no note to collect — see `CompleteBookingDialog`'s doc), then
  /// calls `completeBooking`. Same 409-handling shape as [_confirmDecline]/
  /// [_confirmCancel].
  ///
  /// Track 27.x/MO-6: same appointment-child routing as [_confirmDecline] —
  /// a non-null [Booking.appointmentId] routes the write to
  /// `AppointmentRepository.completeAppointment` (whole-visit lockstep) and
  /// tells the dialog `isAppointment: true` for the whole-visit copy; a plain
  /// single-service booking (`appointmentId == null`) is UNCHANGED.
  Future<void> _confirmComplete(BuildContext context, Booking booking) async {
    final bool isAppointment = booking.appointmentId != null;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => CompleteBookingDialog(isAppointment: isAppointment),
    );
    if (confirmed != true || !mounted) return;

    try {
      final String? appointmentId = booking.appointmentId;
      if (appointmentId != null) {
        await ref
            .read(appointmentRepositoryProvider)
            .completeAppointment(appointmentId);
      } else {
        await ref.read(bookingRepositoryProvider).completeBooking(booking.id);
      }
    } on ProviderCompleteNotStartedFailure catch (failure) {
      // The booking's start slipped back into the future relative to this
      // (possibly stale) screen — or the device clock was rolled back and the
      // server refused to honour it. Same resolution as the decline 409:
      // localized message + refetch so the footer re-renders correctly.
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
    ref.invalidate(bookingDetailProvider(booking.id));
    // Same day-list staleness fix as `_confirmDecline` — the booking just
    // left CONFIRMED for COMPLETED.
    ref.invalidate(bookingsDayProvider);
  }

  /// Track 27.x/MO-6: when [Booking.appointmentId] is non-null this booking is
  /// one service of a multi-service VISIT — the reschedule routes to
  /// [startAppointmentReschedule] instead, moving every service in lockstep via
  /// `PATCH /appointments/{id}/reschedule`. A plain single-service booking
  /// (`appointmentId == null`) is UNCHANGED — same [startBookingReschedule]
  /// call as before. Confirmed-only either way — the CTA below is gated to
  /// match.
  void _onReschedule(BuildContext context, Booking booking) {
    final String? appointmentId = booking.appointmentId;
    if (appointmentId != null) {
      unawaited(
        startAppointmentReschedule(
          context: context,
          ref: ref,
          appointmentId: appointmentId,
          bookingId: booking.id,
        ),
      );
      return;
    }
    // Reuse the create-booking slot picker, seeded to reschedule THIS booking
    // (the confirm-step submit swaps POST → PATCH /reschedule on the non-null
    // rescheduleBookingId).
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
      // Exactly the string the recap card renders on-screen — both go through
      // `BookingDisplayX.priceLabel`, so a RANGE booking exports «300–500 ₴»
      // rather than a floor the client never agreed to on its own.
      price: booking.showsPrice ? booking.priceLabel : null,
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

  /// «Залишити відгук про майстра» — pushes the Phase 14.6 leave-review screen
  /// onto the Записи branch (swipe-back returns here). Gated on
  /// `booking.canReview` at the call site (the CTA is only built then).
  void _onLeaveReview(Booking booking) {
    context.push(RouteNames.bookingReview(booking.id));
  }

  /// «Залишити відгук про клієнта» (track 7.x Wave B) — pushes the leave-
  /// client-feedback screen onto the master's own stack (swipe-back returns
  /// here). Offered on a COMPLETED provider booking only when
  /// `booking.providerCanReviewClient` is `true` — see
  /// `_DetailBody._providerActions`'s doc.
  void _onLeaveClientFeedback(Booking booking) {
    context.push(RouteNames.clientReview(booking.id));
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<Booking> async = ref.watch(
      bookingDetailProvider(widget.bookingId),
    );
    // Drives the «Перенести» button's spinner while the shared reschedule
    // navigation loads its seeding GETs (before it pushes the slot picker).
    final bool rescheduleLoading = ref.watch(bookingRescheduleInFlightProvider);

    // Phase 7.2 — which side of this booking is looking. Derived from the
    // session, never from a constructor flag (locked decision D5); see
    // `booking_viewer_role.dart` for why a widget parameter would be unsafe.
    final BookingViewerRole viewer = ref.watch(bookingViewerRoleProvider);

    return async.when(
      loading: () => const _DetailLoading(),
      error: (Object e, StackTrace _) => _DetailError(
        error: e,
        onRetry: () => ref.invalidate(bookingDetailProvider(widget.bookingId)),
      ),
      data: (Booking booking) => _DetailBody(
        booking: booking,
        viewer: viewer,
        rescheduleLoading: rescheduleLoading,
        onReschedule: () => _onReschedule(context, booking),
        onCancel: () => _confirmCancel(context, booking),
        onDecline: () => _confirmDecline(context, booking),
        onComplete: () => _confirmComplete(context, booking),
        onRebook: () => _onRebook(booking),
        onLeaveReview: () => _onLeaveReview(booking),
        onLeaveClientFeedback: () => _onLeaveClientFeedback(booking),
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
    required this.viewer,
    required this.rescheduleLoading,
    required this.onReschedule,
    required this.onCancel,
    required this.onDecline,
    required this.onComplete,
    required this.onRebook,
    required this.onLeaveReview,
    required this.onLeaveClientFeedback,
    required this.onAddToCalendar,
  });

  final Booking booking;
  final BookingViewerRole viewer;
  final bool rescheduleLoading;
  final VoidCallback onReschedule;
  final VoidCallback onCancel;

  /// Track 27.x Wave A — the PROVIDER'S «Скасувати» (decline).
  final VoidCallback onDecline;

  /// Track 27.x Wave A — the PROVIDER'S «Завершити» (complete).
  final VoidCallback onComplete;
  final VoidCallback onRebook;
  final VoidCallback onLeaveReview;

  /// Track 7.x Wave B — the PROVIDER'S «Залишити відгук про клієнта».
  final VoidCallback onLeaveClientFeedback;
  final VoidCallback onAddToCalendar;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final BookingStatusVisual v = BookingStatusVisual.of(booking, l10n);
    final (String? addressValue, String? addressDetail) = booking.addressBlock;

    // The big status TITLE still shows for COMPLETED and NOT_COMPLETED — the
    // finished outcome deserves a header label. CONFIRMED drops it (a confirmed
    // booking needs no ceremony — the subline suffices); CANCELLED and DECLINED
    // drop it too (product decision 2026-07-15: no big «Скасовано» title — the
    // neutral state reads through the subline alone).
    final bool showStatusTitle =
        booking.status == BookingStatus.completed ||
        booking.status == BookingStatus.notCompleted;

    // The top status MEDALLION (hero icon) is now dropped for COMPLETED too
    // (product decision 2026-07-16) — a finished booking needs no ceremonial
    // icon, mirroring how CONFIRMED and CANCELLED/DECLINED already omit it. Only
    // NOT_COMPLETED still carries the medallion. The COMPLETED header keeps its
    // title/subline unchanged; only the top icon goes away.
    final bool showStatusHero = booking.status == BookingStatus.notCompleted;

    return BookingSuccessScaffold(
      title: showStatusTitle ? v.label : null,
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
      //
      // SEC — CLIENT-SIDE ONLY, deliberately (`!viewer.isProvider`).
      // `canAddToCalendar` is a STATUS predicate; it says nothing about who is
      // looking. Without this role gate the provider view offered the export
      // too, and `_onAddToCalendar` composed the event from
      // `salonName ?? masterName` + `addressLine` — i.e. the master's OWN name
      // and OWN address, which is semantically wrong for a provider. The real
      // hazard is the trajectory, not today's payload: the natural repair is to
      // substitute the CLIENT's name into the title/description, and that would
      // be a new write of client PII into the device calendar — a store that
      // syncs to Google/iCloud outside this app's protection boundary, beyond
      // the `ScreenProtectionManager` and the no-free-text rule below.
      // A provider-side calendar export, if ever wanted, needs its OWN explicit
      // allowlist decision about what may leave the app — it must not be
      // inherited from the client-side one.
      headerTrailing:
          !viewer.isProvider && booking.canAddToCalendar && !booking.isPast
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
          // Branch point 1 of 2 (locked decision D5) — the counterparty. A
          // client sees the master; a provider sees the client. Everything
          // else on this screen is shared verbatim.
          masterCard: BookingCounterpartyHeader(
            booking: booking,
            viewer: viewer,
          ),
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
            // «300 ₴», or «300–500 ₴» when the master left this service as a
            // genuine RANGE at booking time — see `BookingDisplayX.priceLabel`.
            price: booking.priceLabel,
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
        // `viewer` is threaded through (mobile-security LOW, 2026-07-22) —
        // without it the master read the CLIENT's brief under «Ваші
        // побажання» and their OWN comment inside the recessed inbound well.
        // See `booking_notes.dart`'s "The headings are VIEWER-relative"
        // section; this is a framing fix, NOT a visibility one.
        if (BookingNotes.has(booking, l10n, viewer: viewer))
          BookingNotes(booking: booking, viewer: viewer),
      ],
    );
  }

  /// One calm sentence per status, in the app's own neutral voice. The
  /// no-show line is agent-less on purpose — the app records that the visit
  /// did not happen and points at the provider's own words; it never itself
  /// tells the client they failed to show up.
  String? _subline(Booking b, AppLocalizations l10n) {
    switch (b.status) {
      case BookingStatus.confirmed:
        // The reminder ("Нагадаємо про запис напередодні.") is an
        // upcoming-only affordance. An ELAPSED CONFIRMED booking is already
        // read-only (Reschedule/Cancel/Add-to-calendar all hidden, «Записатись
        // знову» shown), so drop the reminder too — reminding about a visit
        // whose time has passed is meaningless.
        if (b.isPast) {
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
      // No subline. Every other branch here is the app narrating what the
      // status MEANS; for a status this build does not recognise there is
      // nothing truthful to narrate, and the badge already says so.
      case BookingStatus.unknown:
        return null;
    }
  }

  /// The pinned footer. An empty list renders no footer at all.
  ///
  /// Branch point 2 of 2 (locked decision D5). Dispatches to
  /// [_providerActions] for a provider viewer (track 27.x Wave A — filled;
  /// previously always empty, Phase 7.2/7.3's placeholder) or the CLIENT
  /// switch below, unchanged since Phase 14.4.
  ///
  /// The client action set below is NOT merely hidden from a provider — every
  /// one of its entries is a CLIENT capability (reschedule and cancel are the
  /// client's own; «Записатись знову» would have the master book themselves;
  /// «Залишити відгук» is the client reviewing the master, and `canReview` is
  /// server-computed for the booking's client, not its provider). Falling
  /// through to it would offer the master four actions that are wrong for
  /// them and two the backend would reject.
  List<Widget> _actions(AppLocalizations l10n) {
    if (viewer.isProvider) {
      return _providerActions(l10n);
    }
    switch (booking.status) {
      case BookingStatus.confirmed:
        // An ELAPSED CONFIRMED booking is READ-ONLY: its slot is already in the
        // past, so Reschedule + Cancel no longer apply (the backend 409s both
        // with BOOKING_ALREADY_ELAPSED — the server clock is authoritative).
        // Route it into the SAME «Записатись знову» affordance the terminal
        // states use, rather than showing actions that can only fail.
        if (booking.isPast) {
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
            buttonKey: const Key('booking-detail-cancel'),
            label: l10n.bookingDetailCancelCta,
            icon: Icons.close_rounded,
            onTap: onCancel,
          ),
        ];

      // A just-completed booking's most relevant next action is leaving a
      // review — the primary CTA while the server still says it's reviewable
      // (COMPLETED + owner + not already reviewed, via `canReview`). Rebooking
      // stays available below it. Once reviewed (`canReview` false) only the
      // rebook CTA remains — matching the CANCELLED / DECLINED states.
      case BookingStatus.completed:
        if (booking.canReview) {
          return <Widget>[
            NeumorphicButton(
              key: const Key('booking-detail-leave-review'),
              label: l10n.bookingDetailReviewCta,
              icon: Icons.rate_review_rounded,
              onPressed: onLeaveReview,
            ),
            const SizedBox(height: VelvetSpacing.xs),
            NeumorphicButton(
              label: l10n.bookingDetailRebookCta,
              icon: Icons.refresh_rounded,
              onPressed: onRebook,
            ),
          ];
        }
        return _rebookActions(l10n);

      // A kept appointment is the strongest rebook signal there is; a
      // cancelled one leaves an unmet need whoever ended it — same label in
      // both, because an action keeps its name.
      case BookingStatus.cancelled:
      case BookingStatus.declined:
        return _rebookActions(l10n);

      // Deliberately nothing — see the file header.
      case BookingStatus.notCompleted:
        return const <Widget>[];

      // An unrecognised status grants NOTHING that acts on this booking — no
      // reschedule, no cancel (security S1). «Записатись знову» is the one
      // safe offer: it starts a brand-new booking flow and touches this record
      // not at all. Add-to-calendar is already excluded upstream via
      // `canAddToCalendar`.
      case BookingStatus.unknown:
        return _rebookActions(l10n);
    }
  }

  /// The PROVIDER footer (track 27.x Wave A). Status- AND time-driven,
  /// mirroring the backend's Phase 27.1 `BookingTemporalGuard` predicates as
  /// UX — the server remains authoritative; a stale screen or a rolled-back
  /// device clock can still hit a 409, handled by `onDecline`/`onComplete`'s
  /// callers (see `_confirmDecline`/`_confirmComplete` in the screen state).
  ///
  ///   * CONFIRMED, not yet started — «Перенести» (a plain single-service
  ///     booking reuses the SAME `startBookingReschedule` flow the client uses
  ///     — Phase 27.2 widened `PATCH …/reschedule` to providers on the
  ///     identical endpoint/shape; an appointment-child booking instead routes
  ///     to `startAppointmentReschedule`, moving the whole visit via
  ///     `PATCH /appointments/{id}/reschedule` — track 27.x/MO-6) + «Скасувати»
  ///     (decline).
  ///   * CONFIRMED, [Booking.hasStarted] — «Завершити» AND «Скасувати»
  ///     (decline). Reschedule alone is hidden — it would 409 server-side
  ///     once the appointment has begun (see `hasStarted`'s doc for why this
  ///     is a DIFFERENT gate than the client-side [Booking.isPast]). Decline
  ///     itself is NOT time-gated — the backend allows a provider to decline
  ///     a CONFIRMED booking at any time, elapsed or not; a client who never
  ///     showed up is recorded as a decline with a free-text reason, same as
  ///     any other cancellation, rather than a separate no-show status.
  ///   * COMPLETED, `booking.providerCanReviewClient` — «Залишити відгук про
  ///     клієнта» (track 7.x Wave B). PRIVATE feedback about the booking's
  ///     client; the client only ever sees their aggregate rating number
  ///     move, never this screen's words.
  ///   * COMPLETED, but `!booking.providerCanReviewClient` (client already
  ///     reviewed, or not eligible) — no CTA, footer is empty.
  ///   * Every other terminal status (CANCELLED / DECLINED / NOT_COMPLETED /
  ///     unknown) — read-only, no actions.
  ///
  /// Track 27.x/MO-6 — a booking that is part of a multi-service VISIT
  /// (`Booking.appointmentId != null`) now ALSO offers «Перенести»: the
  /// backend exposes `PATCH /appointments/{id}/reschedule`, so `_onReschedule`
  /// routes it to [startAppointmentReschedule] (whole-visit lockstep) instead
  /// of the per-booking flow the visit-child 409 guard would otherwise block.
  /// «Скасувати» (decline) is unchanged — it routes to
  /// `AppointmentRepository.declineAppointment` instead of the per-booking
  /// endpoint (see [_confirmDecline]).
  ///
  /// GATING NOTE (track 7.x Wave B, superseded): the CTA used to be offered
  /// on every COMPLETED provider booking regardless of prior feedback,
  /// because `BookingDetailResponse` carried no provider-side
  /// canReview-equivalent flag. It now does —
  /// `booking.providerCanReviewClient` — so the CTA is pre-gated here exactly
  /// like the CLIENT footer's «Залишити відгук про майстра»/`canReview`
  /// above. The 409 the backend returns for a duplicate submit
  /// (`ClientReviewAlreadyExistsFailure`) is STILL handled on the destination
  /// screen (`LeaveClientFeedbackScreen` swaps its form for a not-reviewable
  /// info state) as defense-in-depth against a race between this screen's
  /// load and the submit (e.g. reviewed from another device in between).
  List<Widget> _providerActions(AppLocalizations l10n) {
    if (booking.status == BookingStatus.completed) {
      if (!booking.providerCanReviewClient) {
        return const <Widget>[];
      }
      return <Widget>[
        NeumorphicButton(
          key: const Key('booking-detail-leave-client-feedback'),
          label: l10n.bookingDetailClientReviewCta,
          icon: Icons.rate_review_rounded,
          onPressed: onLeaveClientFeedback,
        ),
      ];
    }
    if (booking.status != BookingStatus.confirmed) {
      return const <Widget>[];
    }
    if (booking.hasStarted) {
      return <Widget>[
        NeumorphicButton(
          key: const Key('booking-detail-complete'),
          label: l10n.bookingDetailCompleteCta,
          icon: Icons.check_circle_rounded,
          onPressed: onComplete,
        ),
        const SizedBox(height: VelvetSpacing.xs),
        _DestructiveSecondaryButton(
          buttonKey: const Key('booking-detail-decline'),
          label: l10n.bookingDetailDeclineCta,
          icon: Icons.close_rounded,
          onTap: onDecline,
        ),
      ];
    }
    // Track 27.x/MO-6 — «Перенести» is now offered on EVERY not-yet-started
    // CONFIRMED provider booking, appointment-child or not; `_onReschedule`
    // (the screen state's handler bound to `onReschedule`) is what branches on
    // `booking.appointmentId` to pick the right endpoint.
    return <Widget>[
      NeumorphicButton(
        key: const Key('booking-detail-provider-reschedule'),
        label: l10n.bookingDetailRescheduleCta,
        icon: Icons.event_repeat_rounded,
        loading: rescheduleLoading,
        onPressed: onReschedule,
      ),
      const SizedBox(height: VelvetSpacing.xs),
      _DestructiveSecondaryButton(
        buttonKey: const Key('booking-detail-decline'),
        label: l10n.bookingDetailDeclineCta,
        icon: Icons.close_rounded,
        onTap: onDecline,
      ),
    ];
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
    required this.buttonKey,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  // Deliberately NOT routed through `super.key`: this shell's `State.build`
  // needs the tap-target identity on the inner `GestureDetector` (the actual
  // hit-testable node) — not on this StatefulWidget too. Giving the same
  // `Key` to both the outer widget AND the inner GestureDetector makes
  // `find.byKey` ambiguous (two matching elements in the tree for one key),
  // which is exactly the regression this field exists to prevent (track
  // 27.x Wave A: `booking-detail-cancel` duplicated across the client and
  // provider footers — see `booking_detail_provider_view_test.dart`).
  final Key buttonKey;
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
        // `widget.buttonKey`, NOT `widget.key`/`super.key`: this shell is
        // shared by the CLIENT «Скасувати запис»
        // (`Key('booking-detail-cancel')`) and the PROVIDER «Скасувати»
        // (`Key('booking-detail-decline')`) call sites. Routing the caller's
        // key through `super.key` would apply it to this StatefulWidget's
        // own element AND (if also copied here) to the GestureDetector,
        // producing two elements answering to the same `Key` — `find.byKey`
        // then throws "ambiguously found multiple matching widgets" (mobile-qa
        // regression, track 27.x Wave A). `buttonKey` is a plain data field,
        // so exactly one element in the tree — this GestureDetector, the
        // actual hit-testable node — carries the key.
        key: widget.buttonKey,
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
