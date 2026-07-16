// Phase 14.6 — leave-review submit notifier.
//
// A tiny `@riverpod` `AsyncNotifier<void>` that drives the «ВІДГУК ПРО
// МАЙСТРА» screen's submit CTA: [submit] calls
// `BookingRepository.createReview` (`POST /reviews`) and, on success,
// invalidates `bookingDetailProvider(bookingId)` so the detail screen's
// server-computed `canReview` flips false (the entry CTA disappears; a stale
// deep link now lands on the not-reviewable info state).
//
// The screen reads the resulting [AsyncValue] after awaiting [submit]: an
// [AsyncError] carries the mapped [Failure] (shown in a snackbar without
// leaving the screen), an [AsyncData] means success (snackbar + pop). The
// in-flight [AsyncLoading] drives the CTA spinner via `ref.watch`.
//
// The «Мої відгуки» / «Мій рейтинг» read-side (Phase 14.11) has no Riverpod
// provider yet — `MyRatingScreen` always renders the empty state until the
// backend's `GET /clients/me/rating` ships — so there is nothing to invalidate
// there. Wire that invalidation in when the provider lands.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/booking_providers.dart';
import 'booking_detail_notifier.dart';

part 'leave_review_notifier.g.dart';

/// Submits a client → master review and refreshes the affected detail state.
@riverpod
class LeaveReview extends _$LeaveReview {
  @override
  Future<void> build() async {
    // Idle until [submit] is invoked — no work on first read.
  }

  /// Posts the review for [bookingId] with [rating] (1–5) and optional
  /// [comment]. Sets [AsyncLoading] while in flight, then [AsyncData] on
  /// success or [AsyncError] (carrying the mapped [Failure]) on failure. On
  /// success, invalidates `bookingDetailProvider(bookingId)` so `canReview`
  /// re-resolves to false.
  Future<void> submit({
    required String bookingId,
    required int rating,
    String? comment,
  }) async {
    state = const AsyncLoading<void>();
    state = await AsyncValue.guard(() async {
      await ref
          .read(bookingRepositoryProvider)
          .createReview(bookingId: bookingId, rating: rating, comment: comment);
      // Flip the detail screen's `canReview` to false (server-computed) so the
      // entry CTA disappears and any stale review deep link lands on the
      // not-reviewable info state. bookingDetailProvider fetches GET
      // /bookings/{id} and never watches leaveReviewProvider (this notifier is
      // invoked imperatively from the screen), so there is no back-edge.
      // cycle-safe: bookingDetailProvider never watches leaveReviewProvider — no back-edge.
      ref.invalidate(bookingDetailProvider(bookingId));
    });
  }
}
