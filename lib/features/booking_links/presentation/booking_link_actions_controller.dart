// Phase 415 — regenerate a booking link (D6 / D7).
//
// State: the [BookingLink.keyId] of the card whose regenerate is in flight,
// or `null`. One call at a time across the screen: a second tap while one is
// in flight is ignored (returns `null`), and backend 378's optimistic
// `currentSlug` check (409) covers everything the UI cannot see.
//
// Outcomes ([BookingLinkMutationOutcome]):
//   done        → the card is replaced in place via [BookingLinksPatches]
//                 (no reload, no flicker).
//   stale (409) → the per-account cache is invalidated: the screen re-reads
//                 the current link.
//   unavailable (404, kill-switch) → invalidated too, so the settings row
//                 hides; the screen pops back (414 D7).
//   rateLimited (429) → nothing to refresh.
// Any other failure is rethrown to the screen.
//
// Kept alive: a screen closed mid-flight must still record the replacement,
// or reopening it within the cache TTL would show the retired URL.
//
// The app never revokes (user decision 2026-10-23): there is no revoke here.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../auth/domain/user_role.dart';
import '../../auth/presentation/auth_notifier.dart';
import '../data/booking_links_repository.dart';
import '../domain/booking_link.dart';
import 'booking_links_provider.dart';

part 'booking_link_actions_controller.g.dart';

@Riverpod(keepAlive: true)
class BookingLinkActions extends _$BookingLinkActions {
  @override
  String? build() => null;

  /// Regenerates [link] (the card as the screen shows it). `null` when the
  /// call was not made (another one in flight, or nothing loaded / signed
  /// out), or its result was dropped because the signed-in user changed
  /// while it was in flight.
  Future<BookingLinkMutationOutcome?> regenerate(BookingLink link) async {
    if (state != null) return null;
    final String? userId = ref.read(authProvider.select(authUserIdOrNull));
    final UserRole? role = ref.read(authProvider.select(authUserRoleOrNull));
    if (userId == null || role == null) return null;
    final BookingLinks? base = ref
        .read(bookingLinksForAccountProvider(userId, role))
        .value;
    if (base == null) return null;

    state = link.keyId;
    try {
      final BookingLinkMutationOutcome outcome = await ref
          .read(bookingLinksRepositoryProvider)
          .regenerate(link);
      if (!ref.mounted) return outcome;
      // Signed out / switched account mid-flight: the result belongs to the
      // previous account — never write its link into the (kept-alive) patch
      // overlay or poke the new account's cache. Dropped like a no-op call.
      if (ref.read(authProvider.select(authUserIdOrNull)) != userId) {
        return null;
      }
      switch (outcome) {
        case BookingLinkMutationDone(link: final BookingLink next):
          ref
              .read(bookingLinksPatchesProvider.notifier)
              .replace(base, link.keyId, next);
        case BookingLinkMutationStale() || BookingLinkMutationUnavailable():
          ref.invalidate(bookingLinksForAccountProvider);
        case BookingLinkMutationRateLimited():
          break;
      }
      return outcome;
    } finally {
      if (ref.mounted) state = null;
    }
  }
}
