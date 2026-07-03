// Phase 14.2 — BookingConfirm: the confirmation screen's submit notifier.
//
// A single `@riverpod AsyncNotifier<Booking?>` (autoDispose by default —
// mirrors `slot_picker_notifier.dart`'s reasoning: the confirm screen is
// popped/replaced at the end of the flow, so the provider disposes cleanly
// and a later booking attempt always starts from a fresh `build()`).
//
// [confirm] wraps `BookingRepository.createBooking` and OWNS the "one
// idempotency key per submit" state transition contract: it does not
// generate the key itself (the screen does, once per tap, per the
// CreateBookingRequest.idempotencyKey file-header contract) — it only drives
// `state` through loading → data (success) or back to idle (failure) so the
// CTA's in-button spinner reflects exactly one in-flight submit at a time.
//
// ERROR HANDLING: [confirm] rethrows the original [Failure] (or raw error)
// to the caller after resetting `state` back to `AsyncData(null)` — NOT
// `AsyncError`, so a failed submit never gets stuck showing a persistent
// error UI; the confirm screen stays fully interactive (the doc's "slot
// picker re-opens" acceptance criterion — interpreted as "the user can
// navigate back and re-pick a slot", not an automatic re-open) and the
// caller (the screen's `_submit`) maps the rethrown error to a transient
// SnackBar via `try`/`catch` around the `await`, exactly like the
// `service_create_screen.dart` precedent.

import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/booking_providers.dart';
import '../domain/booking.dart';
import '../domain/create_booking_request.dart';

part 'booking_notifier.g.dart';

/// Drives the booking-confirmation submit flow. `state.isLoading` is `true`
/// for exactly the duration of one in-flight [confirm] call — the confirm
/// screen watches it (via `.select`) to drive the CTA's in-button spinner.
@riverpod
class BookingConfirm extends _$BookingConfirm {
  @override
  FutureOr<Booking?> build() => null;

  /// Submits [request] via `POST /bookings`.
  ///
  /// Returns the created (enriched) [Booking] on success. On failure, resets
  /// `state` to `AsyncData(null)` (never a persisted `AsyncError` — see the
  /// file header) and rethrows the original error so the caller can map it
  /// to UI (a `ConflictFailure` snackbar, or a generic one).
  Future<Booking> confirm(CreateBookingRequest request) async {
    state = const AsyncLoading<Booking?>();
    try {
      final Booking booking = await ref
          .read(bookingRepositoryProvider)
          .createBooking(request);
      state = AsyncData<Booking?>(booking);
      return booking;
    } catch (e, st) {
      state = const AsyncData<Booking?>(null);
      Error.throwWithStackTrace(e, st);
    }
  }
}
