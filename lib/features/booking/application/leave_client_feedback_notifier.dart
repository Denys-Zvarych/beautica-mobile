// Track 7.x Wave B — leave-client-feedback submit notifier.
//
// A tiny `@riverpod` `AsyncNotifier<void>` that drives the «ВІДГУК ПРО
// КЛІЄНТА» screen's submit CTA: [submit] calls
// `ClientReviewRepository.createClientReview` (`POST /client-reviews`).
//
// Unlike [LeaveReview] (the CLIENT→MASTER mirror), there is no
// `bookingDetailProvider` invalidation on success — the backend carries no
// provider-side `canReview`-equivalent flag for `BookingDetailScreen` to
// re-resolve (see `ClientReviewAlreadyExistsFailure`'s doc), so there is
// nothing on the detail screen that a successful submit would change.
//
// The screen reads the resulting [AsyncValue] after awaiting [submit]: an
// [AsyncError] carries the mapped [Failure] — a
// [ClientReviewAlreadyExistsFailure] swaps the form for the not-reviewable
// info state, anything else shows in a SnackBar and the provider stays on the
// form. An [AsyncData] means success (snackbar + pop). The in-flight
// [AsyncLoading] drives the CTA spinner via `ref.watch`.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/booking_providers.dart';

part 'leave_client_feedback_notifier.g.dart';

/// Submits a provider → client feedback entry for a COMPLETED booking.
@riverpod
class LeaveClientFeedback extends _$LeaveClientFeedback {
  @override
  Future<void> build() async {
    // Idle until [submit] is invoked — no work on first read.
  }

  /// Posts the client feedback for [bookingId] with [rating] (1–5) and
  /// optional [comment]. Sets [AsyncLoading] while in flight, then
  /// [AsyncData] on success or [AsyncError] (carrying the mapped [Failure])
  /// on failure.
  Future<void> submit({
    required String bookingId,
    required int rating,
    String? comment,
  }) async {
    state = const AsyncLoading<void>();
    state = await AsyncValue.guard(
      () => ref
          .read(clientReviewRepositoryProvider)
          .createClientReview(
            bookingId: bookingId,
            rating: rating,
            comment: comment,
          ),
    );
  }
}
