// Shared entry point for the CLIENT booking-reschedule flow (track 14.8 /
// 24.x auto-confirm).
//
// Reschedule REUSES the existing create-booking slot picker end to end
// (`RouteNames.bookingSlots` → `BookingTimeScreen`/`SlotTimeScreen` → the
// confirm step) — the ONLY difference is a non-null
// [BookingSlotPickerArgs.rescheduleBookingId], which the confirm-step submit
// reads to swap `POST /bookings` for `PATCH /bookings/{id}/reschedule` (see
// `booking_notifier.dart`). This helper is the one place that seeds those args
// from an existing booking, so both surfaces that offer reschedule — the
// «Деталі запису» screen and the Home Hub «Найближчий запис» card — share
// identical behavior.
//
// SEEDING: the slot picker needs the target [Master] (for its identity strip +
// address context) and the booked [MasterService] (its id + duration drive
// slot fetching and the working-days calendar gate). A [Booking] carries
// neither as a full object — only `masterId`/`serviceId` — so this helper
// loads them from `publicMasterProfileProvider(masterId)` (the SAME warmed
// family the create flow already uses) and resolves the one service by id. The
// booking itself is read from `bookingDetailProvider(id)` (already cached on
// the detail screen; a fresh GET from the Home Hub) so a single `bookingId` is
// the only input either caller needs.
//
// Reschedule is CONFIRMED-only on the backend, so a defensive status guard
// short-circuits a non-confirmed booking with a calm message rather than
// letting the flow reach a 409 at submit.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';

import '../../master/application/public_master_profile_notifier.dart';
import '../../master/domain/master.dart';
import '../../services/domain/master_service.dart';
import '../application/booking_detail_notifier.dart';
import '../application/booking_reschedule_in_flight_notifier.dart';
import '../domain/booking.dart';
import '../domain/booking_slot_picker_args.dart';
import '../domain/booking_status.dart';

/// Seeds the booking slot picker for a RESCHEDULE of [bookingId] and pushes
/// into it. Safe to call from any CLIENT surface that has a booking id.
///
/// Loads the enriched booking + the master's public profile to recover the
/// booked [MasterService] the picker requires, then pushes
/// [RouteNames.bookingSlots] with [BookingSlotPickerArgs.rescheduleBookingId]
/// set. On any failure (load error, non-confirmed booking, or a service no
/// longer in the master's catalogue) it surfaces a transient SnackBar and does
/// NOT navigate.
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

  // Capture context-bound handles BEFORE the first await so they are never
  // read across an async gap.
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final AppLocalizations l10n = AppLocalizations.of(context);

  void showUnavailable() => messenger
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(l10n.bookingRescheduleUnavailable)));

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
        ),
      ),
    );
  } catch (_) {
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(l10n.errUnknown)));
  } finally {
    inFlight.end();
  }
}
