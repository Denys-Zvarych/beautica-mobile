// Phase 13.6 — Salon reviews list loader ("Відгуки" tab body).
//
// A `@riverpod` family keyed on BOTH [salonId] and the active [SalonReviewSort]
// — changing the sort re-keys the family, so the widget tree re-fetches a
// freshly server-sorted first page rather than re-sorting the previous page
// client-side (per the phase brief: "the port re-fetches server-sorted pages
// rather than sorting locally").
//
// Scope note: this loads only the FIRST page (`kSalonReviewsPageSize` items).
// Infinite-scroll pagination for the reviews list is out of scope for this
// pass (the approved preview's mock data was a static, unpaginated list too);
// a later phase can extend this to a paginated notifier if the list needs to
// grow past one page in practice.
//
// Cache: autoDispose by default, but [ref.keepAlive] holds the result for a
// 5-minute TTL, mirroring [publicSalonProfileProvider]'s TTL pattern exactly
// (mobile-perf MEDIUM fix, Phase 13.6 audit). Because the family is keyed on
// BOTH [salonId] and [sort], each distinct `(salonId, sort)` combination gets
// its OWN 5-minute window: switching sort is an intentional new fetch (a new
// family key, so a fresh keepAlive timer), while switching tabs away and back
// with the SAME sort within the window hits the cache.

import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/salon_repository.dart';
import '../domain/salon_review.dart';

part 'salon_reviews_notifier.g.dart';

/// Loads the first page of the salon's reviews, server-sorted by [sort].
///
/// Generated provider name: `salonReviewsProvider` — a family, call it with
/// the target salon id and the active sort, e.g.
/// `salonReviewsProvider(salonId, SalonReviewSort.newest)`.
@riverpod
Future<List<SalonReviewItem>> salonReviews(
  Ref ref,
  String salonId,
  SalonReviewSort sort,
) async {
  // 5-minute cache window, keyed on THIS (salonId, sort) family instance. The
  // timer is cancelled on dispose so it can never fire after the provider is
  // gone.
  final link = ref.keepAlive();
  final Timer timer = Timer(const Duration(minutes: 5), link.close);
  ref.onDispose(timer.cancel);

  return ref
      .watch(salonRepositoryProvider)
      .getSalonReviews(salonId: salonId, sort: sort);
}
