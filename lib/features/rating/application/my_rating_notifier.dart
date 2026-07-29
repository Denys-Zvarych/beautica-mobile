// Track 7.x Wave B — «Мій рейтинг» loader.
//
// A `@riverpod` loader for the CLIENT's own aggregate rating — mirrors
// `masterReviewSummary` (`features/master/application/
// master_review_summary_notifier.dart`) in shape: autoDispose by default, but
// [ref.keepAlive] holds the result for a 5-minute TTL so leaving and
// returning to «Мій рейтинг» within the window serves the cached value
// instead of re-fetching. The timer is cancelled on dispose so it can never
// fire after the provider is gone.

import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/rating_repository.dart';
import '../domain/client_rating.dart';

part 'my_rating_notifier.g.dart';

/// Loads the authenticated CLIENT's own aggregate rating.
///
/// Generated provider name: `myRatingProvider`.
@riverpod
Future<ClientRating> myRating(Ref ref) async {
  final link = ref.keepAlive();
  final Timer timer = Timer(const Duration(minutes: 5), link.close);
  ref.onDispose(timer.cancel);

  return ref.watch(ratingRepositoryProvider).getMyRating();
}
