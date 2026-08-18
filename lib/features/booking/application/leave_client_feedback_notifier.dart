// Track 7.x Wave B — leave-client-feedback submit notifier.
//
// A tiny `@riverpod` `AsyncNotifier<void>` that drives the «ВІДГУК ПРО
// КЛІЄНТА» screen's submit CTA: [submit] calls
// `ClientReviewRepository.createClientReview` (`POST /client-reviews`).
//
// Like [LeaveReview] (the CLIENT→MASTER mirror), a successful submit DOES
// change something on `BookingDetailScreen`: the backend flips
// `Booking.providerCanReviewClient` to false, which gates that screen's own
// «Залишити відгук про клієнта» CTA (see `_DetailBody._providerActions`).
// This notifier only owns the submit call itself — the resulting
// `bookingDetailProvider` invalidation is the SCREEN's job (done in
// `LeaveClientFeedbackScreen._submit`'s success branch, right before the
// `context.pop()`), since only the screen knows the `bookingId` to invalidate
// and the pop timing that keeps the underlying detail screen's re-fetch
// from racing the navigation.
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
