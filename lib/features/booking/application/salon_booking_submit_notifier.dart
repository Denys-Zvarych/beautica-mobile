// Phase 14.18 — SalonBookingSubmit: the salon confirmation screen's submit
// notifier (the FIRST booking-WRITE in the salon flow).
//
// Unlike the independent-master `BookingConfirm` notifier (one `POST
// /bookings` per submit), a salon booking maps to N appointments (one per
// assigned master) → N SEPARATE `POST /bookings` calls (the backend has no
// multi-appointment endpoint, and no `booking_services` join table — see
// `salon_booking_schedule_notifier.dart`'s header). This notifier drives
// those N calls with EXPLICIT partial-failure handling:
//
//   • Every not-yet-succeeded appointment is attempted, sequentially.
//   • Each appointment's outcome is tracked independently (succeeded / failed
//     + its `Failure`), surfaced per-appointment on the confirm screen.
//   • A booking that already SUCCEEDED is never re-submitted — a retry only
//     re-attempts the still-failed ones, reusing each appointment's STABLE
//     idempotency key so an ambiguously-failed booking (network error where
//     the server may have created it) is de-duplicated rather than
//     duplicated.
//
// A 409 `ConflictFailure` on one appointment (its slot was taken between the
// kept-alive step-3 pick and this submit — backlog #68: those slots are never
// refreshed, so a stale pick is realistic) fails only THAT appointment; the
// rest still go through. Nothing is ever silently dropped and success is
// never claimed while any appointment failed.
//
// Re-validation (backlog #48): each call sends the server-authoritative
// `masterId` + `masterServiceId` (the master's OWN assignment id — a
// master-scoped id, so the backend re-checks the master↔service pairing) +
// `startsAt`, never trusting client-only state.

import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:beautica_mobile/core/errors/failures.dart';

import '../data/booking_providers.dart';
import '../data/booking_repository.dart';
import '../domain/create_booking_request.dart';
import '../domain/salon_booking_confirm_args.dart';

part 'salon_booking_submit_notifier.g.dart';

const String _tag = 'feature.booking.salon_submit';

/// Per-appointment submit lifecycle.
enum SalonAppointmentSubmitStatus { pending, submitting, succeeded, failed }

/// Immutable state: each appointment's [SalonAppointmentSubmitStatus] +
/// last [Failure], keyed by masterId, plus the aggregate in-flight flag.
class SalonBookingSubmitState {
  const SalonBookingSubmitState({
    this.statusByMaster = const <String, SalonAppointmentSubmitStatus>{},
    this.failureByMaster = const <String, Failure>{},
    this.inFlight = false,
    this.attempted = false,
  });

  /// masterId → its current submit status. Absent = [pending].
  final Map<String, SalonAppointmentSubmitStatus> statusByMaster;

  /// masterId → its last submit failure (only for currently-failed ones).
  final Map<String, Failure> failureByMaster;

  /// `true` for exactly the duration of one in-flight [SalonBookingSubmit.submit]
  /// pass — the confirm screen watches it to drive the CTA spinner.
  final bool inFlight;

  /// `true` once at least one full submit pass has run — distinguishes the
  /// initial "Записатись" state from the post-attempt "retry the failed ones"
  /// state.
  final bool attempted;

  SalonAppointmentSubmitStatus statusFor(String masterId) =>
      statusByMaster[masterId] ?? SalonAppointmentSubmitStatus.pending;

  Failure? failureFor(String masterId) => failureByMaster[masterId];

  bool get hasFailures => statusByMaster.values.any(
    (SalonAppointmentSubmitStatus s) =>
        s == SalonAppointmentSubmitStatus.failed,
  );

  /// `true` once at least one appointment's `POST /bookings` has SUCCEEDED.
  ///
  /// Drives the confirm screen's back-navigation guard: after a partial
  /// success the only safe way forward is the «Повторити» retry (which reuses
  /// each appointment's stable idempotency key) — leaving and re-entering the
  /// step-3 picker would re-mint fresh keys for the already-created bookings.
  bool get hasSucceeded => statusByMaster.values.any(
    (SalonAppointmentSubmitStatus s) =>
        s == SalonAppointmentSubmitStatus.succeeded,
  );

  /// Whether EVERY appointment in [appointments] succeeded.
  bool allSucceeded(List<SalonBookingAppointment> appointments) =>
      appointments.isNotEmpty &&
      appointments.every(
        (SalonBookingAppointment a) =>
            statusFor(a.schedule.masterId) ==
            SalonAppointmentSubmitStatus.succeeded,
      );

  SalonBookingSubmitState copyWith({
    Map<String, SalonAppointmentSubmitStatus>? statusByMaster,
    Map<String, Failure>? failureByMaster,
    bool? inFlight,
    bool? attempted,
  }) {
    return SalonBookingSubmitState(
      statusByMaster: statusByMaster ?? this.statusByMaster,
      failureByMaster: failureByMaster ?? this.failureByMaster,
      inFlight: inFlight ?? this.inFlight,
      attempted: attempted ?? this.attempted,
    );
  }
}

/// Drives the salon confirmation screen's N-booking submit. autoDispose (the
/// default `@riverpod` class shape) so leaving the confirm screen starts the
/// next attempt from a clean `build()`.
///
/// Generated provider name: `salonBookingSubmitProvider`.
@riverpod
class SalonBookingSubmit extends _$SalonBookingSubmit {
  @override
  SalonBookingSubmitState build() => const SalonBookingSubmitState();

  /// Submits every appointment in [appointments] that has not already
  /// succeeded, sequentially, and returns the resulting state so the caller
  /// can decide whether to navigate onward ([SalonBookingSubmitState.allSucceeded]).
  ///
  /// Reuses each appointment's stable [SalonBookingAppointment.idempotencyKey]
  /// so a retry de-duplicates rather than duplicates. Never throws — every
  /// per-appointment error is captured into [SalonBookingSubmitState].
  Future<SalonBookingSubmitState> submit(
    List<SalonBookingAppointment> appointments, {
    String? comment,
  }) async {
    if (state.inFlight) return state;

    final BookingRepository repo = ref.read(bookingRepositoryProvider);
    final String? trimmedComment =
        (comment != null && comment.trim().isNotEmpty) ? comment.trim() : null;

    // Mark every not-yet-succeeded appointment as submitting and drop its
    // stale failure, so the UI shows in-flight state for exactly the ones
    // this pass will attempt.
    final Map<String, SalonAppointmentSubmitStatus> statuses =
        <String, SalonAppointmentSubmitStatus>{...state.statusByMaster};
    final Map<String, Failure> failures = <String, Failure>{
      ...state.failureByMaster,
    };
    for (final SalonBookingAppointment a in appointments) {
      final String id = a.schedule.masterId;
      if (statuses[id] == SalonAppointmentSubmitStatus.succeeded) continue;
      statuses[id] = SalonAppointmentSubmitStatus.submitting;
      failures.remove(id);
    }
    state = state.copyWith(
      statusByMaster: statuses,
      failureByMaster: failures,
      inFlight: true,
      attempted: true,
    );

    for (final SalonBookingAppointment a in appointments) {
      final String id = a.schedule.masterId;
      if (state.statusFor(id) == SalonAppointmentSubmitStatus.succeeded) {
        continue;
      }
      try {
        await repo.createBooking(
          CreateBookingRequest(
            masterId: a.schedule.masterId,
            serviceId: a.schedule.primaryServiceAssignmentId,
            startAt: a.startAt,
            idempotencyKey: a.idempotencyKey,
            clientComment: trimmedComment,
          ),
        );
        _mark(id, SalonAppointmentSubmitStatus.succeeded, null);
      } catch (e, st) {
        final Failure failure = e is Failure ? e : UnknownFailure(cause: e);
        if (kDebugMode) {
          // Log the MAPPED failure type (+ status for the one variant that
          // carries it) — never `$e`, whose `cause` is a DioException that
          // could expand the raw `/bookings` error body into debug logs.
          // Mirrors the repository's `${e.type} ${e.response?.statusCode}`.
          final int? statusCode = failure is ServerFailure
              ? failure.statusCode
              : null;
          log(
            'salon booking submit failed for master=$id: '
            '${failure.runtimeType} status=$statusCode',
            name: _tag,
            level: 900,
            stackTrace: st,
          );
        }
        _mark(id, SalonAppointmentSubmitStatus.failed, failure);
      }
    }

    state = state.copyWith(inFlight: false);
    return state;
  }

  void _mark(
    String masterId,
    SalonAppointmentSubmitStatus status,
    Failure? failure,
  ) {
    final Map<String, SalonAppointmentSubmitStatus> statuses =
        <String, SalonAppointmentSubmitStatus>{
          ...state.statusByMaster,
          masterId: status,
        };
    final Map<String, Failure> failures = <String, Failure>{
      ...state.failureByMaster,
    };
    if (failure == null) {
      failures.remove(masterId);
    } else {
      failures[masterId] = failure;
    }
    state = state.copyWith(statusByMaster: statuses, failureByMaster: failures);
  }
}
