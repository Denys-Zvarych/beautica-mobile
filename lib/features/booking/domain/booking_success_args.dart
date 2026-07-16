// Navigation payload for the `/booking/success` route.
//
// [BookingConfirmScreen]'s «Записатись» CTA `pushReplacement`s here once every
// appointment's `POST /bookings` has succeeded, carrying the SAME [Master] +
// the per-appointment ([MasterService], start) pairs the confirm screen
// already had in hand (loaded once via `publicMasterProfileProvider`) — the
// success screen never re-fetches, it re-renders the identical
// [BookingSummaryCards] recap so the two screens can never visually drift.
//
// MULTI-SERVICE (the multi-service booking rework): the independent-master
// flow now books N services with a SEPARATE time each, so the success recap
// lists one card per confirmed appointment ([appointments]) rather than a
// single service/start — mirrors the salon success screen's per-appointment
// recap, keyed by SERVICE.
//
// Pure Dart: no Flutter imports anywhere in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../master/domain/master.dart';
import '../../services/domain/master_service.dart';

part 'booking_success_args.freezed.dart';

/// One confirmed appointment for the success recap: the service booked and its
/// chosen start.
@freezed
abstract class BookingSuccessAppointment with _$BookingSuccessAppointment {
  const factory BookingSuccessAppointment({
    required MasterService service,
    required DateTime start,
  }) = _BookingSuccessAppointment;
}

/// Navigation extra for `RouteNames.bookingSuccess`.
@freezed
abstract class BookingSuccessArgs with _$BookingSuccessArgs {
  const factory BookingSuccessArgs({
    required Master master,

    /// Every confirmed appointment, in the order they were booked. Always
    /// non-empty (the success screen is only reached once every appointment
    /// succeeded).
    required List<BookingSuccessAppointment> appointments,

    /// `true` when the flow was a RESCHEDULE (a single existing booking moved
    /// to a new time) rather than a fresh booking — the success screen swaps
    /// its celebration title/subline copy accordingly. Defaults to `false` for
    /// the create flow.
    @Default(false) bool isReschedule,
  }) = _BookingSuccessArgs;
}
