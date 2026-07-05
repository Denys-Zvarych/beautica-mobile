// Phase 14.1 — navigation payload for the (stubbed) `/booking/confirm` route.
//
// The time screen's "Підтвердити" CTA hands this off once a slot is chosen.
// Phase 14.2 builds the real confirmation/success screen and the
// [BookingRepository.createBooking] wiring; until then `/booking/confirm`
// renders `BookingConfirmPlaceholderScreen` so navigation never crashes.
//
// [rescheduleBookingId], threaded through from [BookingSlotPickerArgs], is the
// Phase 14.8 extension point: Phase 14.2 will branch on it (POST create vs.
// PATCH reschedule) once that screen exists. Not read by anything yet.
//
// Pure Dart: no Flutter imports anywhere in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

part 'booking_confirm_args.freezed.dart';

/// Navigation extra for `RouteNames.bookingConfirm`.
@freezed
abstract class BookingConfirmArgs with _$BookingConfirmArgs {
  const factory BookingConfirmArgs({
    required String masterId,

    /// The PRIMARY selected service (`services.first` from
    /// [BookingSlotPickerArgs]) — see that file's header for why multi-service
    /// selection collapses to one operative service here.
    required String serviceId,
    required DateTime startAt,
    String? rescheduleBookingId,
  }) = _BookingConfirmArgs;
}
