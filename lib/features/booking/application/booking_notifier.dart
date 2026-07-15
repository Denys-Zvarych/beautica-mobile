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
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:beautica_mobile/core/errors/failures.dart';

import '../data/booking_providers.dart';
import '../data/booking_repository.dart';
import '../domain/booking.dart';
import '../domain/booking_appointment.dart';
import '../domain/booking_tab.dart';
import '../domain/create_booking_request.dart';
import 'booking_detail_notifier.dart';
import 'my_bookings_notifier.dart';

part 'booking_notifier.g.dart';

const String _tag = 'feature.booking.independent_submit';

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

// ---------------------------------------------------------------------------
// IndependentBookingSubmit — the multi-service confirm screen's submit
// notifier (the independent analogue of `SalonBookingSubmit`).
// ---------------------------------------------------------------------------
//
// The independent-master flow now books N services with a SEPARATE time each
// → N SEPARATE `POST /bookings` calls (the backend has no multi-service
// booking endpoint — see `create_booking_request.dart`). This notifier drives
// those N calls with EXPLICIT partial-failure handling, mirroring
// `salon_booking_submit_notifier.dart` keyed by SERVICE instead of MASTER:
//
//   • Every not-yet-succeeded appointment is attempted, sequentially.
//   • Each appointment's outcome is tracked independently (succeeded / failed
//     + its `Failure`), surfaced per-appointment on the confirm screen.
//   • A booking that already SUCCEEDED is never re-submitted — a retry only
//     re-attempts the still-failed ones, reusing each appointment's STABLE
//     idempotency key so an ambiguously-failed booking is de-duplicated.
//
// A 409 (`ConflictFailure` / `ClientBookingConflictFailure`) on one
// appointment fails only THAT appointment; the rest still go through. Nothing
// is ever silently dropped and success is never claimed while any appointment
// failed.

/// Per-appointment submit lifecycle.
enum IndependentAppointmentSubmitStatus {
  pending,
  submitting,
  succeeded,
  failed,
}

/// Immutable state: each appointment's status + last [Failure], keyed by
/// serviceId, plus the aggregate in-flight flag.
class IndependentBookingSubmitState {
  const IndependentBookingSubmitState({
    this.statusByService = const <String, IndependentAppointmentSubmitStatus>{},
    this.failureByService = const <String, Failure>{},
    this.inFlight = false,
    this.attempted = false,
  });

  /// serviceId → its current submit status. Absent = [pending].
  final Map<String, IndependentAppointmentSubmitStatus> statusByService;

  /// serviceId → its last submit failure (only for currently-failed ones).
  final Map<String, Failure> failureByService;

  /// `true` for exactly the duration of one in-flight [IndependentBookingSubmit.submit]
  /// pass — the confirm screen watches it to drive the CTA spinner.
  final bool inFlight;

  /// `true` once at least one full submit pass has run — distinguishes the
  /// initial «Записатись» state from the post-attempt «Повторити» state.
  final bool attempted;

  IndependentAppointmentSubmitStatus statusFor(String serviceId) =>
      statusByService[serviceId] ?? IndependentAppointmentSubmitStatus.pending;

  Failure? failureFor(String serviceId) => failureByService[serviceId];

  bool get hasFailures => statusByService.values.any(
    (IndependentAppointmentSubmitStatus s) =>
        s == IndependentAppointmentSubmitStatus.failed,
  );

  /// `true` once at least one appointment's `POST /bookings` has SUCCEEDED.
  /// Drives the confirm screen's back-navigation guard.
  bool get hasSucceeded => statusByService.values.any(
    (IndependentAppointmentSubmitStatus s) =>
        s == IndependentAppointmentSubmitStatus.succeeded,
  );

  /// Whether EVERY appointment in [appointments] succeeded.
  bool allSucceeded(List<BookingAppointment> appointments) =>
      appointments.isNotEmpty &&
      appointments.every(
        (BookingAppointment a) =>
            statusFor(a.serviceId) ==
            IndependentAppointmentSubmitStatus.succeeded,
      );

  IndependentBookingSubmitState copyWith({
    Map<String, IndependentAppointmentSubmitStatus>? statusByService,
    Map<String, Failure>? failureByService,
    bool? inFlight,
    bool? attempted,
  }) {
    return IndependentBookingSubmitState(
      statusByService: statusByService ?? this.statusByService,
      failureByService: failureByService ?? this.failureByService,
      inFlight: inFlight ?? this.inFlight,
      attempted: attempted ?? this.attempted,
    );
  }
}

/// Drives the independent-master confirm screen's N-booking submit.
/// autoDispose (the default `@riverpod` class shape) so leaving the confirm
/// screen starts the next attempt from a clean `build()`.
///
/// Generated provider name: `independentBookingSubmitProvider`.
@riverpod
class IndependentBookingSubmit extends _$IndependentBookingSubmit {
  @override
  IndependentBookingSubmitState build() =>
      const IndependentBookingSubmitState();

  /// Submits every appointment in [appointments] (all against [masterId]) that
  /// has not already succeeded, sequentially, and returns the resulting state
  /// so the caller can decide whether to navigate onward
  /// ([IndependentBookingSubmitState.allSucceeded]).
  ///
  /// Reuses each appointment's stable [BookingAppointment.idempotencyKey] so a
  /// retry de-duplicates rather than duplicates. Never throws — every
  /// per-appointment error is captured into state.
  /// When [rescheduleBookingId] is non-null the flow is a RESCHEDULE, not a
  /// create: there is exactly one appointment, and it is submitted via
  /// `PATCH /bookings/{id}/reschedule` (never a new `POST /bookings`). The
  /// [comment] and each appointment's idempotency key are create-only concerns
  /// and are unused on that path. On a successful reschedule the moved
  /// booking's detail and the upcoming My Bookings list are invalidated so both
  /// reflect the new time (mirrors the cancel flow's refetch).
  Future<IndependentBookingSubmitState> submit(
    String masterId,
    List<BookingAppointment> appointments, {
    String? comment,
    String? rescheduleBookingId,
  }) async {
    if (state.inFlight) return state;

    final BookingRepository repo = ref.read(bookingRepositoryProvider);
    final String? trimmedComment =
        (comment != null && comment.trim().isNotEmpty) ? comment.trim() : null;

    // Mark every not-yet-succeeded appointment as submitting and drop its
    // stale failure, so the UI shows in-flight state for exactly the ones this
    // pass will attempt.
    final Map<String, IndependentAppointmentSubmitStatus> statuses =
        <String, IndependentAppointmentSubmitStatus>{...state.statusByService};
    final Map<String, Failure> failures = <String, Failure>{
      ...state.failureByService,
    };
    for (final BookingAppointment a in appointments) {
      if (statuses[a.serviceId] ==
          IndependentAppointmentSubmitStatus.succeeded) {
        continue;
      }
      statuses[a.serviceId] = IndependentAppointmentSubmitStatus.submitting;
      failures.remove(a.serviceId);
    }
    state = state.copyWith(
      statusByService: statuses,
      failureByService: failures,
      inFlight: true,
      attempted: true,
    );

    for (final BookingAppointment a in appointments) {
      if (state.statusFor(a.serviceId) ==
          IndependentAppointmentSubmitStatus.succeeded) {
        continue;
      }
      try {
        if (rescheduleBookingId != null) {
          await repo.rescheduleBooking(rescheduleBookingId, a.startAt);
        } else {
          await repo.createBooking(
            CreateBookingRequest(
              masterId: masterId,
              serviceId: a.serviceId,
              startAt: a.startAt,
              idempotencyKey: a.idempotencyKey,
              clientComment: trimmedComment,
            ),
          );
        }
        _mark(a.serviceId, IndependentAppointmentSubmitStatus.succeeded, null);
      } catch (e, st) {
        final Failure failure = e is Failure ? e : UnknownFailure(cause: e);
        if (kDebugMode) {
          // Log the MAPPED failure type (+ status) — never `$e`, whose `cause`
          // is a DioException that could expand the raw `/bookings` error body
          // into debug logs. Mirrors the salon submit notifier.
          final int? statusCode = failure is ServerFailure
              ? failure.statusCode
              : null;
          log(
            'independent booking submit failed for service=${a.serviceId}: '
            '${failure.runtimeType} status=$statusCode',
            name: _tag,
            level: 900,
            stackTrace: st,
          );
        }
        _mark(a.serviceId, IndependentAppointmentSubmitStatus.failed, failure);
      }
    }

    state = state.copyWith(inFlight: false);

    // A successful reschedule moved an EXISTING booking — its detail page and
    // the upcoming My Bookings list must re-fetch to show the new time. Mirrors
    // the cancel flow's post-write invalidation in `booking_detail_screen`.
    if (rescheduleBookingId != null &&
        !state.hasFailures &&
        state.hasSucceeded) {
      ref.invalidate(bookingDetailProvider(rescheduleBookingId));
      ref.invalidate(myBookingsProvider(BookingTab.upcoming));
    }

    return state;
  }

  void _mark(
    String serviceId,
    IndependentAppointmentSubmitStatus status,
    Failure? failure,
  ) {
    final Map<String, IndependentAppointmentSubmitStatus> statuses =
        <String, IndependentAppointmentSubmitStatus>{
          ...state.statusByService,
          serviceId: status,
        };
    final Map<String, Failure> failures = <String, Failure>{
      ...state.failureByService,
    };
    if (failure == null) {
      failures.remove(serviceId);
    } else {
      failures[serviceId] = failure;
    }
    state = state.copyWith(
      statusByService: statuses,
      failureByService: failures,
    );
  }
}
