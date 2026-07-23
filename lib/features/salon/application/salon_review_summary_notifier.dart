// Phase 13.6 — Salon review-summary loader ("Відгуки" tab header).
//
// A `@riverpod` family keyed on [salonId], independent of the paginated
// review list ([salonReviewsProvider]) so the rating-summary card can
// load/retry/error on its own and never needs to re-fetch when the user
// changes the sort order (the summary's aggregate numbers do not depend on
// the active sort).
//
// Cache: autoDispose by default, but [ref.keepAlive] holds the result for a
// 5-minute TTL so switching tabs away and back within the window serves the
// cached summary instead of re-fetching (mobile-perf MEDIUM fix, Phase 13.6
// audit — mirrors [publicSalonProfileProvider]'s TTL pattern exactly).

import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/salon_repository.dart';
import '../domain/salon_review.dart';

part 'salon_review_summary_notifier.g.dart';

/// Loads the salon's aggregate review summary (average + 5★→1★ distribution).
///
/// Generated provider name: `salonReviewSummaryProvider` — a family, call it
/// with the target salon id.
@riverpod
Future<SalonReviewSummary> salonReviewSummary(Ref ref, String salonId) async {
  // 5-minute cache window. Keep the link alive across an away-and-back tab
  // switch, then close it so a stale summary eventually refetches. The timer
  // is cancelled on dispose so it can never fire after the provider is gone.
  final link = ref.keepAlive();
  final Timer timer = Timer(const Duration(minutes: 5), link.close);
  ref.onDispose(timer.cancel);

  return ref.watch(salonRepositoryProvider).getSalonReviewSummary(salonId);
}
