// Phase 4.5 — Master received-reviews list loader ("Мої відгуки").
//
// A `@riverpod` family keyed on BOTH [masterId] and the active
// [MasterReviewSort] — changing the sort re-keys the family, so the screen
// re-fetches a freshly server-sorted first page rather than re-sorting the
// previous page client-side. Exact mirror of `salon_reviews_notifier.dart`.
//
// Scope note: loads only the FIRST page ([kMasterReviewsPageSize] items) — no
// infinite scroll (parity with the salon reviews list).
//
// Cache: autoDispose by default, but [ref.keepAlive] holds the result for a
// 5-minute TTL. Because the family is keyed on BOTH [masterId] and [sort], each
// `(masterId, sort)` combination gets its OWN window: switching sort is an
// intentional new fetch; leaving and returning with the SAME sort within the
// window hits the cache. The timer is cancelled on dispose so it can never fire
// after the provider is gone.

import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/master_repository.dart';
import '../domain/master_review.dart';

part 'master_reviews_notifier.g.dart';

/// Loads the first page of [masterId]'s received reviews, server-sorted by
/// [sort].
///
/// Generated provider name: `masterReviewsProvider` — a family, call it with
/// the master id and the active sort, e.g.
/// `masterReviewsProvider(masterId, MasterReviewSort.newest)`.
@riverpod
Future<List<MasterReviewItem>> masterReviews(
  Ref ref,
  String masterId,
  MasterReviewSort sort,
) async {
  final link = ref.keepAlive();
  final Timer timer = Timer(const Duration(minutes: 5), link.close);
  ref.onDispose(timer.cancel);

  return ref
      .watch(masterRepositoryProvider)
      .getMasterReviews(masterId: masterId, sort: sort);
}
