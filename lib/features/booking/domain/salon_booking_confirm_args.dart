// Phase 14.18 — navigation payloads for the salon booking flow's step-4
// confirmation + success screens (`/booking/salon/confirm`,
// `/booking/salon/success`).
//
// The salon flow schedules N appointments (one per assigned master) on the
// step-3 "Час" screen (`SalonTimeScreen`), each with its OWN chosen date +
// time, tracked LOCALLY in `salonBookingScheduleProvider`. That provider is
// autoDispose and tied to `SalonTimeScreen`, so its picks must be THREADED
// FORWARD as concrete nav args rather than re-read on the confirm screen —
// hence [SalonBookingAppointment] snapshots each master's fully-resolved
// appointment (who + which services + which primary assignment id + the
// chosen start) at the moment «Підтвердити» is tapped.
//
// BOOKING MAPPING: each appointment becomes exactly ONE
// `POST /appointments` chained-visit call — `masterId` =
// [SalonMasterSchedule.masterId], `masterServiceIds` =
// [SalonMasterSchedule.orderedMasterServiceIds] (every assigned service's
// OWN assignment id, in chained-visit order — never just the first),
// `startAt` = [startAt]. A master with 2+ assigned services yields ONE
// multi-service visit (N bookings under one appointment, backend-side), so
// N masters on this screen → N appointment submissions with no risk of
// overlapping/duplicate appointments.
//
// IDEMPOTENCY: [idempotencyKey] is a STABLE UUID v4 generated once per
// appointment when these args are built (never regenerated on retry), so a
// retry of an ambiguously-failed booking (network error where the server may
// actually have created it) is de-duplicated server-side rather than
// producing a duplicate — per `create_booking_request.dart`'s "reuse the same
// key for retries of the SAME submit" contract.
//
// Pure Dart: no Flutter imports anywhere in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

import 'salon_master_schedule.dart';

part 'salon_booking_confirm_args.freezed.dart';

/// One fully-resolved salon appointment: a master's identity + assigned
/// services (via [schedule]), the client's chosen [startAt], and the stable
/// [idempotencyKey] that keys its single `POST /bookings` call.
@freezed
abstract class SalonBookingAppointment with _$SalonBookingAppointment {
  const factory SalonBookingAppointment({
    /// The master + their assigned services + primary assignment id (the
    /// `SalonTimeScreen` slide's own resolved schedule).
    required SalonMasterSchedule schedule,

    /// The chosen appointment start (date + clock time) for this master.
    required DateTime startAt,

    /// Stable UUID v4, one per appointment — reused across retries so an
    /// ambiguously-failed submit is de-duplicated. See the file header.
    required String idempotencyKey,
  }) = _SalonBookingAppointment;

  const SalonBookingAppointment._();

  /// This appointment's summed length across every assigned service — the
  /// same value the "Час" slide displayed, used for the confirm/success
  /// window label.
  int get durationMinutes => schedule.summedDurationMinutes;
}

/// Navigation extra for `RouteNames.salonBookingConfirm`.
@freezed
abstract class SalonBookingConfirmArgs with _$SalonBookingConfirmArgs {
  const factory SalonBookingConfirmArgs({
    required String salonId,

    /// Every assigned master's fully-resolved appointment, in slider order.
    /// Never empty on a well-formed push — the «Підтвердити» CTA only enables
    /// once every master has a date AND a time.
    required List<SalonBookingAppointment> appointments,
  }) = _SalonBookingConfirmArgs;
}

/// Navigation extra for `RouteNames.salonBookingSuccess`.
@freezed
abstract class SalonBookingSuccessArgs with _$SalonBookingSuccessArgs {
  const factory SalonBookingSuccessArgs({
    required String salonId,

    /// The appointments that were successfully created — rendered as the
    /// post-submit recap. Always non-empty (the success screen is only
    /// reached once every appointment succeeded).
    required List<SalonBookingAppointment> appointments,
  }) = _SalonBookingSuccessArgs;
}
