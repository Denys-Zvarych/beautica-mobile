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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../auth/presentation/auth_notifier.dart';
import '../data/rating_repository.dart';
import '../domain/client_rating.dart';

part 'my_rating_notifier.g.dart';

/// Loads the authenticated CLIENT's own aggregate rating.
///
/// Generated provider name: `myRatingProvider`.
@riverpod
Future<ClientRating> myRating(Ref ref) async {
  // SESSION BOUNDARY (mobile-security MEDIUM, 2026-09-17) — same bug class,
  // same fix, same reasoning as `passportProvider`'s watch (read its comment
  // for the full argument): `keepAlive` + 5-minute TTL, a chain
  // (`ratingRepositoryProvider` → the generated user API → `dioProvider`)
  // with no auth watch at any hop, and — because this provider is KEYLESS —
  // ONE member shared by every account that signs in on the device. The next
  // sign-in within the TTL was served the outgoing client's own aggregate
  // rating from memory, under the incoming client's «Мій рейтинг».
  //
  // Narrowed through [authUserIdOrNull] so a silent token refresh does not
  // discard a live cache entry; nothing here reads the token or the role.
  ref.watch(authProvider.select(authUserIdOrNull));

  final link = ref.keepAlive();
  final Timer timer = Timer(const Duration(minutes: 5), link.close);
  ref.onDispose(timer.cancel);

  return ref.watch(ratingRepositoryProvider).getMyRating();
}
