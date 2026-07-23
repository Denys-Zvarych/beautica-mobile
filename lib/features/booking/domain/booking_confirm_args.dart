// Navigation payload for the `/booking/confirm` route (independent-master
// booking flow's final review-and-submit step).
//
// MULTI-SERVICE (the multi-service booking rework): the client may select
// several services in Step 1 and pick a SEPARATE time for each on the
// per-service time PageView (`BookingTimeScreen`). Each becomes ONE
// appointment — carried here as [appointments] (one [BookingAppointment] per
// selected service, each with its own chosen `startAt` and a STABLE
// idempotency key generated once when these args were built). All N
// appointments are for the SAME [masterId]; the confirm screen submits one
// `POST /bookings` per appointment (auto-confirmed to CONFIRMED). This mirrors
// the salon flow's `SalonBookingConfirmArgs.appointments` shape, keyed by
// SERVICE instead of MASTER — see `booking_appointment.dart`'s header.
//
// [master] is carried forward from `BookingSlotPickerArgs` so the confirm/
// success screens can render the master-identity card without depending on a
// fresh network read (they still re-watch `publicMasterProfileProvider` to
// resolve each appointment's service display object out of the warmed cache).
// Optional so the retained single-service / reschedule entry
// (`SlotTimeScreen._confirm`) — which does not always thread it — stays valid.
//
// [rescheduleBookingId], threaded through from [BookingSlotPickerArgs], is the
// Phase 14.8 extension point: a future phase branches on it (POST create vs.
// PATCH reschedule) through the retained `BookingConfirm` notifier. Dormant
// today (never non-null on the live create flow).
//
// Pure Dart: no Flutter imports anywhere in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../master/domain/master.dart';
import 'booking_appointment.dart';

part 'booking_confirm_args.freezed.dart';

/// Navigation extra for `RouteNames.bookingConfirm`.
@freezed
abstract class BookingConfirmArgs with _$BookingConfirmArgs {
  const factory BookingConfirmArgs({
    required String masterId,

    /// Every selected service's fully-resolved appointment (service id +
    /// chosen start + stable idempotency key), in slide order. Never empty on
    /// a well-formed push — the «Підтвердити» CTA only enables once every
    /// service has a date AND a time.
    required List<BookingAppointment> appointments,

    /// The target master, carried forward for the confirm/success recap.
    /// Optional so the retained single-service picker (`SlotTimeScreen`) can
    /// push without it.
    Master? master,

    /// Non-null only when this flow was entered from the Phase 14.8 reschedule
    /// surface. See the file header — dormant today.
    String? rescheduleBookingId,
  }) = _BookingConfirmArgs;
}
