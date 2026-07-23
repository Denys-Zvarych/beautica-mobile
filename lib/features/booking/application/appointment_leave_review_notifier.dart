// MO-6 — visit leave-review submit notifier (the visit analogue of
// `leave_review_notifier.dart`).
//
// A tiny `@riverpod` `AsyncNotifier<void>` driving the visit «ВІДГУК ПРО
// МАЙСТРА» screen's submit CTA: [submit] calls
// `AppointmentRepository.createAppointmentReview`
// (`POST /appointments/{id}/review`) and, on success, invalidates
// `appointmentDetailProvider(appointmentId)` so the visit detail's
// server-computed `canReview` flips false (the entry CTA disappears; a stale
// deep link now lands on the not-reviewable info state).
//
// It ALSO invalidates on a [ReviewAlreadyExistsFailure] (a stale form submitted
// after the visit was already reviewed — the 409 anti-oracle collapse). Backlog
// row 60 fix for the visit path: rather than only snackbar-ing the stale 409,
// the detail is refetched so the watching screen flips to its OWN not-reviewable
// state. The error is still surfaced as the resulting [AsyncError] so the screen
// can also show the message.
//
// The screen reads the resulting [AsyncValue] after awaiting [submit]: an
// [AsyncError] carries the mapped [Failure] (shown in a snackbar without
// leaving the screen), an [AsyncData] means success (snackbar + pop). The
// in-flight [AsyncLoading] drives the CTA spinner via `ref.watch`.
//
// cycle-safe: appointmentDetailProvider fetches GET /appointments/{id} and never
// watches this notifier (it is invoked imperatively from the screen) — no
// back-edge.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/booking_providers.dart';
import 'appointment_detail_notifier.dart';

part 'appointment_leave_review_notifier.g.dart';

/// Submits a client → master review for a whole VISIT and refreshes the affected
/// detail state.
@riverpod
class AppointmentLeaveReview extends _$AppointmentLeaveReview {
  @override
  Future<void> build() async {
    // Idle until [submit] is invoked — no work on first read.
  }

  /// Posts the review for [appointmentId] with [rating] (1–5) and optional
  /// [comment]. Sets [AsyncLoading] while in flight, then [AsyncData] on success
  /// or [AsyncError] (carrying the mapped [Failure]) on failure.
  ///
  /// On success — AND on a [ReviewAlreadyExistsFailure] (the visit was already
  /// reviewed server-side between opening this form and submitting) — invalidates
  /// `appointmentDetailProvider(appointmentId)` so `canReview` re-resolves to
  /// false and the watching screen flips to its not-reviewable state.
  Future<void> submit({
    required String appointmentId,
    required int rating,
    String? comment,
  }) async {
    state = const AsyncLoading<void>();
    state = await AsyncValue.guard(() async {
      try {
        await ref
            .read(appointmentRepositoryProvider)
            .createAppointmentReview(
              appointmentId,
              rating: rating,
              comment: comment,
            );
      } on ReviewAlreadyExistsFailure {
        // Stale form: the visit is already reviewed. Refetch so the screen flips
        // to its own not-reviewable state (backlog row 60 fix), then rethrow so
        // the mapped failure still reaches the screen for its message.
        // cycle-safe: appointmentDetailProvider fetches GET /appointments/{id} and never watches appointmentLeaveReviewProvider — no back-edge, no cycle.
        ref.invalidate(appointmentDetailProvider(appointmentId));
        rethrow;
      }
      // Flip the detail screen's `canReview` to false (server-computed) so the
      // entry CTA disappears and any stale review deep link lands on the
      // not-reviewable info state.
      // cycle-safe: appointmentDetailProvider fetches GET /appointments/{id} and never watches appointmentLeaveReviewProvider — no back-edge, no cycle.
      ref.invalidate(appointmentDetailProvider(appointmentId));
    });
  }
}
