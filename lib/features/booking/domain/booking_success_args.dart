// Navigation payload for the `/booking/success` route.
//
// [BookingConfirmScreen]'s «Записатись» CTA `pushReplacement`s here once the
// single `POST /appointments` has succeeded, carrying the SAME [master] + the
// ordered [services] selection + the visit [startAt] the confirm screen already
// had in hand (loaded once via `publicMasterProfileProvider`) — the success
// screen never re-fetches, it re-renders the identical [BookingSummaryCards]
// recap so the two screens can never visually drift.
//
// MO-3 (single-visit rework): the independent-master flow now books the whole
// selection as ONE visit with ONE start time (services run back-to-back), so
// the success recap shows the ordered service list under a SINGLE visit window
// (`startAt` → `startAt + summed duration`) and offers ONE «Додати в календар»
// event for the whole arrival — not one card/event per service.
//
// Pure Dart: no Flutter imports anywhere in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../master/domain/master.dart';
import '../../services/domain/master_service.dart';

part 'booking_success_args.freezed.dart';

/// Navigation extra for `RouteNames.bookingSuccess`.
@freezed
abstract class BookingSuccessArgs with _$BookingSuccessArgs {
  const factory BookingSuccessArgs({
    required Master master,

    /// The confirmed visit's ordered services (1..10). Always non-empty (the
    /// success screen is only reached once the visit was created).
    required List<MasterService> services,

    /// The confirmed visit's single start time.
    required DateTime startAt,

    /// `true` when the flow was a RESCHEDULE (a single existing booking moved
    /// to a new time) rather than a fresh visit — the success screen swaps its
    /// celebration title/subline copy accordingly. Defaults to `false`.
    @Default(false) bool isReschedule,
  }) = _BookingSuccessArgs;
}
