// Phase 225 — shared entry point for the CLIENT single-booking cancel flow.
//
// Originally extracted from `BookingDetailScreen._confirmCancel` so the Home
// Hub's «Найближчий запис» card could offer the exact same «Скасувати запис»
// flow (dialog → `BookingRepository.cancelBooking` → 409-specific handling →
// cache refresh) without duplicating it. A later, USER-LOCKED decision
// switched the Home Hub's populated card over to the SAME read-only
// `BookingCard` widget «Мої записи» uses — "the card has ONE affordance: open
// me" (see `booking_card.dart`'s library doc) — so the Home Hub no longer has
// its own «Скасувати» trigger; `booking_detail_screen.dart`'s `_confirmCancel`
// is this helper's only caller today. It stays a standalone function (not
// inlined back into the screen) so any future CLIENT surface with just a
// `bookingId` can still reuse the dialog → write → cache-refresh flow.
//
// Takes a bare `bookingId` (not a `Booking`), exactly like
// `startBookingReschedule`: it loads the enriched booking itself via
// `bookingDetailProvider(bookingId).future` before showing the confirmation
// dialog (`CancelBookingDialog` needs the service/master/when recap) — on
// «Деталі запису» that provider is already watched and cached, so this costs
// no extra round trip there.
//
// RE-ENTRANCY (mobile-security LOW, Phase 225 audit-fix cycle 2 — supersedes
// the mobile-perf MEDIUM fix pass note this replaces): the same shape as
// `startBookingReschedule`'s `bookingRescheduleInFlightProvider` guard —
// `bookingCancelInFlightProvider` is read first to skip a re-entrant call
// outright. The window now spans the ENTIRE flow: `begin()` fires before the
// booking-detail load and `end()` fires in a single outer `finally` covering
// load, confirm dialog, AND the `cancelBooking` write — cleared on every exit
// path (load failure, the client backing out of the dialog, write failure,
// and success alike).
//
// The previous cut held the flag ONLY across the booking-detail load,
// reasoning that the confirmation dialog's own modal barrier already blocks a
// second real tap. That reasoning covers the DIALOG step but not the step
// after it: once the user confirms, the card's button was un-guarded and
// re-tappable for the whole `cancelBooking` write, so a second tap there
// re-entered this function, opened a second dialog, and could fire a second
// write concurrent with the first — the write phase was the one part of the
// flow the reschedule sibling's guard already covered end-to-end, and cancel
// did not. Widening the guard was the correct call and stays as-is.
//
// SPINNER ANIMATION (mobile-perf LOW, Phase 225 audit-fix cycle 3): widening
// the GUARD to span the dialog-open window also widened a spinner-bearing
// cancel CTA's indeterminate `CircularProgressIndicator` to animate for that
// same, user-paced duration — fully hidden behind the dialog's modal barrier
// the whole time. That is a distinct concern from the guard (tappability) and
// is fixed separately, without narrowing the guard back: a second flag,
// `bookingCancelDialogVisibleProvider`
// (`booking_cancel_dialog_visible_notifier.dart`), brackets ONLY the
// `showCancelBookingDialog` await below, so a spinner-bearing consumer can
// mute its `TickerMode` for exactly that window and keep animating for the
// pre-dialog load and the post-confirm write, where the spin is genuinely
// informative. The original consumer was the Home Hub's inline «Скасувати»
// button (`HubOutlineButton`'s `spinnerPaused` param); the Home Hub now
// renders the shared, cancel-button-less `BookingCard` instead, and
// `booking_detail_screen.dart`'s cancel CTA (`_DestructiveSecondaryButton`,
// the sole remaining `startBookingCancel` caller — see
// `booking_detail_screen_test.dart`) renders no spinner of its own, so this
// flag currently has no live UI reader — it stays wired for whichever caller
// next needs the mute. See `booking_cancel_dialog_visible_notifier.dart` for
// the full `TickerMode`/root-navigator reasoning, including why muting the
// ticker incidentally makes `tester.pumpAndSettle()` safe again while the
// dialog is open (no frame keeps rescheduling) — that mechanism is
// unchanged, only its consumer moved (and is currently absent).
//
// NOT for a multi-service VISIT (`Booking.appointmentId != null`) — that flow
// lives in `visit_detail_screen.dart`'s own `_confirmCancel`, which cancels
// the WHOLE visit via `AppointmentRepository.cancelAppointment`, a different
// endpoint entirely. `BookingDetailScreen`'s CLIENT footer has never special-
// cased that distinction for cancel (see its `_actions` doc), so neither does
// this helper — it is a straight extraction, not a behavior change.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/home/application/home_hub_notifier.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/feedback/show_velvet_snack.dart';

import '../application/booking_cancel_dialog_visible_notifier.dart';
import '../application/booking_cancel_in_flight_notifier.dart';
import '../application/booking_detail_notifier.dart';
import '../application/my_bookings_notifier.dart';
import '../data/booking_providers.dart';
import '../domain/booking.dart';
import '../domain/booking_tab.dart';
import 'widgets/cancel_booking_dialog.dart';

/// Cancels the booking identified by [bookingId] on behalf of the
/// authenticated CLIENT: loads it, shows the cancellation-note confirmation,
/// calls [BookingRepository.cancelBooking], and on success invalidates every
/// cache a cancel affects.
///
/// Safe to call from any CLIENT surface that only has a booking id.
/// `booking_detail_screen.dart`'s «Скасувати запис» CTA is the only caller
/// today (see the file header) — kept a standalone, bookingId-keyed helper
/// so a future surface with just an id can reuse it without duplicating the
/// dialog → write → cache-refresh flow. Does nothing (no dialog, no write)
/// when the load fails or the client backs out of the confirmation.
Future<void> startBookingCancel({
  required BuildContext context,
  required WidgetRef ref,
  required String bookingId,
}) async {
  // Re-entrancy guard: mirrors `startBookingReschedule`'s guard — a cancel
  // flow (load → confirm dialog → write) is already in flight; ignore this
  // extra tap so a double-tap can't stack two confirmation dialogs or fire
  // two `cancelBooking` writes for the same booking. Only one «Скасувати
  // запис» CTA is ever visible at a time (`booking_detail_screen.dart` is
  // the sole caller today), so a single shared flag (not keyed by
  // bookingId) is sufficient — exactly like the reschedule flag.
  if (ref.read(bookingCancelInFlightProvider)) return;
  final BookingCancelInFlight inFlight = ref.read(
    bookingCancelInFlightProvider.notifier,
  );

  final AppLocalizations l10n = AppLocalizations.of(context);

  void showUnknownError() => showErrorSnack(context, l10n.errUnknown);

  // Reflect the loading window across the WHOLE flow — load, confirm dialog,
  // AND the cancelBooking write — not just the load. Cleared in the outer
  // `finally` below so it clears on every exit path alike: load failure, the
  // dialog dismissed/backed out, write failure, and success. See the
  // file-header RE-ENTRANCY note.
  inFlight.begin();
  try {
    final Booking booking;
    try {
      booking = await ref.read(bookingDetailProvider(bookingId).future);
    } catch (_) {
      if (!context.mounted) return;
      showUnknownError();
      return;
    }
    if (!context.mounted) return;

    // Brackets ONLY the dialog-open window so a spinner-bearing cancel CTA
    // can mute its ticker while it's obscured — see the file-header SPINNER
    // ANIMATION note (the original consumer, the Home Hub's inline cancel
    // button, is gone; `startBookingCancel`'s sole caller today is
    // `booking_detail_screen.dart`, whose cancel CTA has no spinner of its
    // own). `end()` in `finally` clears it whether the user confirms or
    // backs out.
    final BookingCancelDialogVisible dialogVisible = ref.read(
      bookingCancelDialogVisibleProvider.notifier,
    );
    final String? note;
    dialogVisible.begin();
    try {
      note = await showCancelBookingDialog(context, booking);
    } finally {
      dialogVisible.end();
    }
    // backed out — nothing happened.
    if (note == null || !context.mounted) return;

    try {
      await ref
          .read(bookingRepositoryProvider)
          .cancelBooking(booking.id, reason: note.isEmpty ? null : note);
    } on BookingAlreadyElapsedFailure catch (failure) {
      // The slot elapsed against the SERVER clock between the confirmation
      // opening and the confirm tap — or the device clock was rolled back
      // and the server refused to honour it. Surface the clean localized
      // message AND refetch so the caller re-renders read-only, never a raw
      // 409.
      if (!context.mounted) return;
      showErrorSnack(context, failure.userMessage(context));
      ref.invalidate(bookingDetailProvider(booking.id));
      return;
    } catch (_) {
      if (!context.mounted) return;
      showUnknownError();
      return;
    }

    // Refetch this booking's fresh status and re-partition the two affected
    // tabs (it just left Майбутні and entered Скасовані) — the merged
    // per-status pagination in `MyBookingsNotifier` means a plain invalidate
    // of each tab cleanly re-fetches page 0 for every status it covers. Also
    // refreshes the Home Hub's own «Найближчий запис» card — invalidated
    // here (not left to the caller) so it stays correct regardless of which
    // CLIENT surface this helper is called from, today or in the future.
    ref.invalidate(bookingDetailProvider(booking.id));
    ref.invalidate(myBookingsProvider(BookingTab.upcoming));
    ref.invalidate(myBookingsProvider(BookingTab.cancelled));
    ref.invalidate(nextAppointmentProvider);
  } finally {
    inFlight.end();
  }
}
