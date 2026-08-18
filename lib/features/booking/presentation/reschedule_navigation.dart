// Shared entry point for the booking-reschedule flow (track 14.8 / 24.x
// auto-confirm; widened to visit ITEMS by track 30.x).
//
// Reschedule REUSES the existing create-booking slot picker end to end
// (`RouteNames.bookingSlots` → `BookingTimeScreen`/`SlotTimeScreen` → the
// confirm step) — the key difference is a non-null
// [BookingSlotPickerArgs.rescheduleBookingId], which the confirm-step submit
// reads to swap `POST /bookings` for `PATCH /bookings/{id}/reschedule` (see
// `booking_notifier.dart`). This helper is the one place that seeds those args
// from an existing booking. «Деталі запису» (`booking_detail_screen.dart`) is
// its only caller today — the Home Hub's own «Перенести» trigger was retired
// when the Home Hub's populated card switched over to the SAME read-only
// `BookingCard` widget «Мої записи» uses (a USER-LOCKED decision; see
// `booking_card.dart`'s library doc). This stays a standalone, `bookingId`-
// keyed function (not inlined into the detail screen) so any future surface
// can reuse the identical seed-and-push behavior.
//
// SEEDING: the slot picker needs the target [Master] (for its identity strip +
// address context) and the booked [MasterService] (its id + duration drive
// slot fetching and the working-days calendar gate). A [Booking] carries
// neither as a full object — only `masterId`/`serviceId` — so this helper
// loads them from `publicMasterProfileProvider(masterId)` (the SAME warmed
// family the create flow already uses) and resolves the one service by id. The
// booking itself is read from `bookingDetailProvider(id)` (already cached on
// the detail screen — its sole caller today, so this is instant there) so a
// single `bookingId` is the only input this helper needs; a future bare-id
// caller would pay a genuine fresh GET here instead.
//
// Reschedule is CONFIRMED-only on the backend, so a defensive status guard
// short-circuits a non-confirmed booking with a calm message rather than
// letting the flow reach a 409 at submit. This is checked against the ONE
// booked SERVICE's own status (never a visit header's), which is exactly
// right for a per-item move too — a visit's other services being non-CONFIRMED
// is irrelevant to whether THIS one can still be rescheduled.
//
// VISIT ITEMS (track 30.x): when the freshly-fetched [Booking.appointmentId]
// is non-null — the booking is one service of a multi-service visit — this
// same helper seeds [BookingSlotPickerArgs.rescheduleAppointmentId] alongside
// [BookingSlotPickerArgs.rescheduleBookingId], reading BOTH off that one
// fetch so the pair can never disagree with each other (mobile-security LOW
// fix — this used to take `appointmentId` as a separate caller-supplied
// parameter instead of deriving it from the same read as `rescheduleBookingId`;
// harmless while `Booking.appointmentId` is immutable once set, but the wrong
// shape to keep once appointment membership can change). `services` is STILL
// exactly one element (the ONE service being moved) — this flow moves only
// that item, never its siblings (no re-layout, no cascade, no gap-closing;
// the visit may legally become non-contiguous afterwards). This is a
// deliberate DROP of the earlier whole-VISIT reschedule flow (which used to
// live here as a separate `startAppointmentReschedule` function, seeding
// every item in the visit and calling `PATCH /appointments/{id}/reschedule`)
// — the backend's whole-visit endpoint is untouched, but the mobile entry
// point to it was removed once the backend gained the per-item
// `PATCH /appointments/{id}/services/{bookingId}/reschedule` (locked product
// decision). `BookingConfirmScreen._submit` is what checks
// [BookingSlotPickerArgs.rescheduleAppointmentId] (forwarded onto
// [BookingConfirmArgs.rescheduleAppointmentId]) to swap the endpoint to
// `AppointmentSubmit.rescheduleAppointmentItem` instead of the per-booking
// [AppointmentSubmit.reschedule].

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/show_velvet_snack.dart';

import '../../master/application/public_master_profile_notifier.dart';
import '../../master/domain/master.dart';
import '../../services/domain/master_service.dart';
import '../application/booking_detail_notifier.dart';
import '../application/booking_reschedule_in_flight_notifier.dart';
import '../domain/booking.dart';
import '../domain/booking_slot_picker_args.dart';
import '../domain/booking_status.dart';

/// Seeds the booking slot picker for a RESCHEDULE of [bookingId] and pushes
/// into it. Safe to call from any surface (CLIENT or PROVIDER) that has a
/// booking id.
///
/// [Booking.appointmentId] — read from the SAME freshly-fetched [Booking]
/// this function loads below, never from a caller-supplied value — is
/// forwarded onto [BookingSlotPickerArgs.rescheduleAppointmentId] whenever
/// [bookingId] identifies one service of a multi-service visit; see the file
/// header's VISIT ITEMS section. Non-null there routes the confirm-step
/// submit to the per-item endpoint instead of the plain per-booking one;
/// `services` still carries exactly the one booked service either way.
/// Deriving both halves of the `(appointmentId, bookingId)` pair from the
/// ONE fresh read keeps them atomically consistent — mobile-security LOW: an
/// earlier version took `appointmentId` as a separate parameter supplied by
/// the caller (captured from whatever `Booking` the calling screen already
/// had in hand), which could in principle disagree with the appointment
/// membership this same function's own fresh fetch just observed.
///
/// Loads the enriched booking + the master's public profile to recover the
/// booked [MasterService] the picker requires, then pushes
/// [RouteNames.bookingSlots] with [BookingSlotPickerArgs.rescheduleBookingId]
/// set. On any failure (load error, non-confirmed booking, or a service no
/// longer in the master's catalogue) it surfaces a transient VelvetSnack and
/// does NOT navigate.
Future<void> startBookingReschedule({
  required BuildContext context,
  required WidgetRef ref,
  required String bookingId,
}) async {
  // Re-entrancy guard: a reschedule navigation is already loading its seeding
  // GETs — ignore this extra tap so a double-tap can't spawn two overlapping
  // chains (duplicate GETs + two stacked slot pickers).
  if (ref.read(bookingRescheduleInFlightProvider)) return;
  final BookingRescheduleInFlight inFlight = ref.read(
    bookingRescheduleInFlightProvider.notifier,
  );

  // `l10n` is read BEFORE the first await so it is never read across an
  // async gap. `showUnavailable`/the catch below re-check `context.mounted`
  // at their own call sites instead — VelvetSnack needs a LIVE context (it
  // looks up the root `Overlay` at show time), unlike the old captured
  // `ScaffoldMessengerState` handle this replaces.
  final AppLocalizations l10n = AppLocalizations.of(context);

  // A defensive, pre-emptive guard (not a caught failure) — the booking is
  // no longer in a state reschedule can act on. Matches the design register's
  // own "soft block" example.
  void showUnavailable() =>
      showWarningSnack(context, l10n.bookingRescheduleUnavailable);

  // Reflect the loading window so both reschedule triggers can show a
  // spinner/disabled state while the up-to-two seeding GETs run. Cleared in
  // `finally` so it clears on success, error, AND every early short-circuit.
  inFlight.begin();
  try {
    final Booking booking = await ref.read(
      bookingDetailProvider(bookingId).future,
    );

    // Reschedule is CONFIRMED-only server-side — a defensive guard (the CTAs
    // that call this are already confirmed-gated).
    if (booking.status != BookingStatus.confirmed) {
      if (!context.mounted) return;
      showUnavailable();
      return;
    }

    final (Master master, List<MasterService> services) = await ref.read(
      publicMasterProfileProvider(booking.masterId).future,
    );
    final MasterService? service = services
        .where((MasterService s) => s.id == booking.serviceId)
        .firstOrNull;
    if (service == null) {
      // The booked service was removed from the master's catalogue — there is
      // no duration to fetch slots against, so reschedule cannot proceed.
      if (!context.mounted) return;
      showUnavailable();
      return;
    }

    if (!context.mounted) return;
    unawaited(
      context.push(
        RouteNames.bookingSlots,
        extra: BookingSlotPickerArgs(
          masterId: booking.masterId,
          master: master,
          services: <MasterService>[service],
          rescheduleBookingId: booking.id,
          rescheduleAppointmentId: booking.appointmentId,
        ),
      ),
    );
  } catch (_) {
    if (!context.mounted) return;
    showErrorSnack(context, l10n.errUnknown);
  } finally {
    inFlight.end();
  }
}
