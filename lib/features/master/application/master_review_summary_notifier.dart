// Phase 4.5 — Master review-summary loader ("Мої відгуки" header).
//
// A `@riverpod` family keyed on [masterId], independent of the review list
// ([masterReviewsProvider]) so the rating-summary card can load/retry/error on
// its own and never re-fetches when the user changes the sort order (the
// aggregate numbers do not depend on the active sort). Exact mirror of
// `salon_review_summary_notifier.dart`.
//
// Cache: autoDispose by default, but [ref.keepAlive] holds the result for a
// 5-minute TTL so leaving and returning within the window serves the cached
// summary. The timer is cancelled on dispose so it can never fire after the
// provider is gone.

import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/master_repository.dart';
import '../domain/master_review.dart';

part 'master_review_summary_notifier.g.dart';

/// Loads [masterId]'s aggregate review summary (average + 5★→1★ distribution).
///
/// Generated provider name: `masterReviewSummaryProvider` — a family, call it
/// with the master id.
@riverpod
Future<MasterReviewSummary> masterReviewSummary(
  Ref ref,
  String masterId,
) async {
  final link = ref.keepAlive();
  final Timer timer = Timer(const Duration(minutes: 5), link.close);
  ref.onDispose(timer.cancel);

  return ref.watch(masterRepositoryProvider).getMasterReviewSummary(masterId);
}
