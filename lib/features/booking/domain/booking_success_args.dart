// Phase 14.2 — navigation payload for the `/booking/success` route.
//
// [BookingConfirmScreen]'s "Записатись" CTA `pushReplacement`s here once
// `POST /bookings` succeeds, carrying the SAME [Master] / [MasterService] /
// [start] the confirmation screen already had in hand (loaded once via
// `publicMasterProfileProvider`) — the success screen never re-fetches, it
// simply re-renders the identical [BookingSummaryCards] recap (minus the
// master card) so the two screens can never visually drift.
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
    required MasterService service,
    required DateTime start,
  }) = _BookingSuccessArgs;
}
