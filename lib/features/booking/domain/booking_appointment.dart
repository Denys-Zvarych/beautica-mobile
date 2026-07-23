// Multi-service booking (independent-master flow) — one fully-resolved
// appointment: a single service the client picked, the [startAt] they chose
// for it on that service's slide of the per-service time PageView
// (`BookingTimeScreen`), and the stable [idempotencyKey] that keys its single
// `POST /bookings` call.
//
// The independent analogue of the salon flow's [SalonBookingAppointment]
// (`salon_booking_confirm_args.dart`): the salon flow schedules ONE appointment
// per assigned MASTER (each covering that master's assigned services against a
// primary-service assignment id); the independent-master flow schedules ONE
// appointment per selected SERVICE, all against the SAME master. Both map each
// appointment to exactly one `POST /bookings` (the backend has no
// multi-service booking endpoint — N services = N calls, see
// `create_booking_request.dart`).
//
// IDEMPOTENCY: [idempotencyKey] is a STABLE UUID v4 generated ONCE per
// appointment when the confirm args are built (in `BookingTimeScreen._confirm`,
// never regenerated on retry) so a retry of an ambiguously-failed booking
// (a network error where the server may actually have created it) is
// de-duplicated server-side rather than producing a duplicate — per
// `create_booking_request.dart`'s "reuse the same key for retries of the SAME
// submit" contract.
//
// Pure Dart: no Flutter imports anywhere in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

part 'booking_appointment.freezed.dart';

/// One resolved appointment in the independent-master multi-service flow: a
/// selected service, its chosen start, and its stable idempotency key.
@freezed
abstract class BookingAppointment with _$BookingAppointment {
  const factory BookingAppointment({
    /// The selected service's id (`MasterService.id`) — becomes the
    /// `masterServiceId` of this appointment's single `POST /bookings` call.
    required String serviceId,

    /// The client's chosen appointment start (date + clock time) for this
    /// service.
    required DateTime startAt,

    /// Stable UUID v4, one per appointment — reused across retries so an
    /// ambiguously-failed submit is de-duplicated. See the file header.
    required String idempotencyKey,
  }) = _BookingAppointment;
}
