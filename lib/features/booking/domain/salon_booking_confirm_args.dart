// MO-4 (single-master single-visit rework) — navigation payloads for the salon
// booking flow's confirmation (`/booking/salon/confirm`) and success
// (`/booking/salon/success`) screens.
//
// The salon flow now schedules ONE visit: the client picks the ONE master who
// performs ALL selected services, ONE date + ONE start time, submitted as a
// SINGLE `POST /appointments` — mirroring the independent-master flow
// (`booking_confirm_args.dart`). This REPLACES the pre-MO-4 "N appointments,
// one per master" model (and its `SalonBookingAppointment` per-master snapshot
// / partial-failure machinery, now retired).
//
// The chosen master + ordered services + per-master assignment ids are carried
// forward in [SalonMasterSchedule.visit] (resolved on the master-selection
// step). [startAt] is the client's chosen visit start; [idempotencyKey] is a
// STABLE UUID v4 minted ONCE per submit (in `SalonTimeScreen._confirm`, when
// these args are built) and reused unchanged on every retry so an
// ambiguously-failed create de-duplicates server-side — re-picking a time mints
// a fresh key. Same contract as `BookingConfirmArgs.idempotencyKey`.
//
// Pure Dart: no Flutter imports anywhere in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

import 'salon_master_schedule.dart';

part 'salon_booking_confirm_args.freezed.dart';

/// Navigation extra for `RouteNames.salonBookingConfirm`.
@freezed
abstract class SalonBookingConfirmArgs with _$SalonBookingConfirmArgs {
  const factory SalonBookingConfirmArgs({
    required String salonId,

    /// The chosen master + ordered services + per-master assignment ids.
    required SalonMasterSchedule visit,

    /// The client's chosen start (date + clock time) for the whole visit.
    required DateTime startAt,

    /// Stable UUID v4 for the visit, minted once per submit and reused on
    /// retry (fresh on re-pick). See the file header.
    required String idempotencyKey,
  }) = _SalonBookingConfirmArgs;
}

/// Navigation extra for `RouteNames.salonBookingSuccess`.
@freezed
abstract class SalonBookingSuccessArgs with _$SalonBookingSuccessArgs {
  const factory SalonBookingSuccessArgs({
    required String salonId,

    /// The visit that was successfully created — rendered as the post-submit
    /// recap.
    required SalonMasterSchedule visit,

    /// The confirmed visit start.
    required DateTime startAt,
  }) = _SalonBookingSuccessArgs;
}
