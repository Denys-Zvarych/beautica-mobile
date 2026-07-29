// MO-3 — AppointmentSubmit: the confirm screen's single-visit submit notifier.
//
// A single `@riverpod` notifier (autoDispose by default — the confirm screen is
// popped/replaced at the end of the flow, so the provider disposes cleanly and
// a later booking attempt always starts from a fresh `build()`). It drives the
// CTA's in-button spinner via `state.isLoading` and owns the two write paths of
// the independent-master booking flow's final step:
//
//   • [submitVisit] — the CREATE path: wraps ONE `POST /appointments`
//     (`AppointmentRepository.createAppointment`) for the whole multi-service
//     visit. This REPLACES the pre-MO-3 "N `POST /bookings`, one per service"
//     fan-out (with its per-appointment partial-failure state) — there is now a
//     single call, so a single typed [Failure] maps to one clear error state.
//   • [reschedule] — the RESCHEDULE path: wraps `PATCH /bookings/{id}/reschedule`
//     (`BookingRepository.rescheduleBooking`) for a single existing booking
//     moved to a new time. There is no idempotency key / comment on this path.
//   • [rescheduleAppointment] — track 27.x/MO-6's whole-VISIT counterpart:
//     wraps `PATCH /appointments/{id}/reschedule`
//     (`AppointmentRepository.rescheduleAppointment`), moving every service of
//     a multi-service visit in lockstep to a new time. Dual-actor on the
//     backend (the visit's own CLIENT or an assigned PROVIDER); today only
//     the PROVIDER/master footer invokes it in-app. Same idle/rethrow
//     contract as [reschedule].
//
// IDEMPOTENCY: [submitVisit] does NOT generate the key itself. The visit's
// single `CreateAppointmentRequest.idempotencyKey` is minted ONCE per submit
// attempt by the flow (in `SlotTimeScreen._confirm`, carried on
// `BookingConfirmArgs`) and reused unchanged on every retry of the same submit,
// so an ambiguously-failed create de-duplicates server-side rather than
// double-booking. This notifier only threads it through.
//
// ERROR HANDLING: both methods reset `state` back to `AsyncData(null)` on
// failure (never a persisted `AsyncError`, so the CTA never sticks on a
// spinner/error) and rethrow the original typed [Failure] to the caller. The
// confirm screen's `_submit` catches it and renders one localized error state —
// a 409 `CLIENT_BOOKING_CONFLICT` / `BOOKING_ALREADY_ELAPSED` /
// `DUPLICATE_SERVICE`, a rate-limit 429, or a generic failure — via
// `Failure.userMessage`.

import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:beautica_mobile/core/errors/failures.dart';

import '../data/booking_providers.dart';
import '../domain/appointment.dart';
import '../domain/create_appointment_request.dart';

part 'booking_notifier.g.dart';

const String _tag = 'feature.booking.appointment_submit';

/// Drives the booking-confirmation submit flow. `state.isLoading` is `true` for
/// exactly the duration of one in-flight write — the confirm screen watches it
/// (via `.select`) to drive the CTA's in-button spinner.
///
/// Generated provider name: `appointmentSubmitProvider`.
@riverpod
class AppointmentSubmit extends _$AppointmentSubmit {
  @override
  FutureOr<void> build() {}

  /// Creates the multi-service visit via ONE `POST /appointments`.
  ///
  /// Returns the created (enriched) [Appointment] on success. On failure,
  /// resets `state` to `AsyncData(null)` (never a persisted `AsyncError` — see
  /// the file header) and rethrows the original typed [Failure] so the caller
  /// can map it to one localized error state (a duplicate/conflict/rate-limit,
  /// or a generic one).
  Future<Appointment> submitVisit(CreateAppointmentRequest request) async {
    state = const AsyncLoading<void>();
    try {
      final Appointment appointment = await ref
          .read(appointmentRepositoryProvider)
          .createAppointment(request);
      state = const AsyncData<void>(null);
      return appointment;
    } catch (e, st) {
      _logFailure(e, st);
      state = const AsyncData<void>(null);
      Error.throwWithStackTrace(e, st);
    }
  }

  /// Moves an existing CONFIRMED booking to [startAt] via
  /// `PATCH /bookings/{id}/reschedule`. Same idle/rethrow contract as
  /// [submitVisit] (no idempotency key or comment on this path).
  Future<void> reschedule(String bookingId, DateTime startAt) async {
    state = const AsyncLoading<void>();
    try {
      await ref
          .read(bookingRepositoryProvider)
          .rescheduleBooking(bookingId, startAt);
      state = const AsyncData<void>(null);
    } catch (e, st) {
      _logFailure(e, st);
      state = const AsyncData<void>(null);
      Error.throwWithStackTrace(e, st);
    }
  }

  /// Moves the WHOLE visit [appointmentId] to [startAt] via
  /// `PATCH /appointments/{id}/reschedule` (track 27.x/MO-6). Dual-actor on
  /// the backend (the visit's own CLIENT or an assigned PROVIDER); today only
  /// the PROVIDER/master footer invokes this method in-app. Same idle/rethrow
  /// contract as [reschedule] — every service in the visit moves in lockstep,
  /// so there is no per-service partial state to reconcile.
  Future<void> rescheduleAppointment(
    String appointmentId,
    DateTime startAt,
  ) async {
    state = const AsyncLoading<void>();
    try {
      await ref
          .read(appointmentRepositoryProvider)
          .rescheduleAppointment(appointmentId, startAt);
      state = const AsyncData<void>(null);
    } catch (e, st) {
      _logFailure(e, st);
      state = const AsyncData<void>(null);
      Error.throwWithStackTrace(e, st);
    }
  }

  /// Logs the MAPPED failure type (+ status) only — never `$e`, whose `cause`
  /// is a DioException that could expand the raw error body into debug logs.
  void _logFailure(Object e, StackTrace st) {
    if (!kDebugMode) return;
    final Failure failure = e is Failure ? e : UnknownFailure(cause: e);
    final int? statusCode = failure is ServerFailure
        ? failure.statusCode
        : null;
    log(
      'appointment submit failed: ${failure.runtimeType} status=$statusCode',
      name: _tag,
      level: 900,
      stackTrace: st,
    );
  }
}
