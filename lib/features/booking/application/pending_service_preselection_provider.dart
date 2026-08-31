// Holds the one-shot [PendingServicePreselection] handed from the discovery
// search results screen to the booking flow.
//
// Lifecycle:
//   • [set] — called at result-card navigation time (master / salon card) when
//     a service filter is active, recording which provider + which service-type
//     slugs to pre-check.
//   • [peekFor] — called on the booking Step 1 screen's FIRST build (via its
//     `initState`). Returns the payload IFF its [targetId] matches the provider
//     being booked, WITHOUT mutating state (safe during a build). The screen
//     then defers the one-shot [clear] to a post-frame callback, so the payload
//     is consumed exactly once after the screen mounts — backing out and
//     re-entering does NOT re-preselect (the agreed behaviour).
//   • [consumeFor] — read-and-clear in one call; retained for non-lifecycle
//     callers. Must NOT be called during a build/`initState` (it writes state).
//   • [clear] — belt-and-suspenders reset, called both as the deferred one-shot
//     consume above and when the user clears the search filters so a stale
//     payload can never leak into a later booking.
//
// keepAlive: the payload must survive the `context.push` from the results
// screen into the booking flow (an autoDispose provider would reset the moment
// the results screen unmounts during the push). It `ref.watch(authProvider)`s
// so a fresh session (login after logout) resets it to null — the same
// self-clearing pattern every other keepAlive per-user provider in this repo
// uses; no manual logout eviction is needed.
//
// The [targetId] guard + one-shot consume already prevent cross-target leakage;
// the auth watch closes the cross-session hole.

// `ProviderListenable.select` (used below to narrow the `authProvider` watch to
// the identity-bearing slice via [authUserIdOrNull]) is not part of
// `riverpod_annotation`'s show-list — same reason `bookings_day_notifier.dart`
// reaches for the full package.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../auth/presentation/auth_notifier.dart';
import '../domain/pending_service_preselection.dart';

part 'pending_service_preselection_provider.g.dart';

/// Nullable holder for the pending service pre-selection. Null means "nothing
/// pending" — the booking flow pre-checks nothing.
@Riverpod(keepAlive: true)
class PendingServicePreselectionController
    extends _$PendingServicePreselectionController {
  @override
  PendingServicePreselection? build() {
    // Reset on a session flip (logout → login) so one user's search never
    // pre-checks services in the next user's booking flow.
    //
    // NARROWED to the user id (mobile-perf LOW, 2026-09-01) — and here the
    // narrowing is a CORRECTNESS fix, not only waste. Rebuilding this notifier
    // resets `state` to null, so the bare `ref.watch(authProvider)` meant that
    // a silent token refresh (`AuthNotifier.setAccessToken` re-emits
    // `Authenticated` with a new accessToken) WIPED the pending pre-selection
    // the user was mid-flow with: search with a service filter → tap a result
    // → refresh lands during the push → the booking step opens with nothing
    // pre-checked. Only a different signed-in identity may clear it, which is
    // exactly the cross-session hole this watch was added to close.
    ref.watch(authProvider.select(authUserIdOrNull));
    return null;
  }

  /// Records the service pre-selection for [targetId] (a master or salon id).
  ///
  /// Called only when a service filter is active — an empty [serviceTypeSlugs]
  /// is never passed. The sets are copied into unmodifiable views so a later
  /// mutation of the caller's filter set can never rewrite a stored payload.
  void set({
    required String targetId,
    required Set<String> serviceTypeSlugs,
    required Set<String> serviceTypeLabels,
  }) {
    state = PendingServicePreselection(
      targetId: targetId,
      serviceTypeSlugs: Set<String>.unmodifiable(serviceTypeSlugs),
      serviceTypeLabels: Set<String>.unmodifiable(serviceTypeLabels),
    );
  }

  /// Returns the pending payload IFF it targets [targetId], WITHOUT touching
  /// state. Safe to call from a widget's `initState`/build (it never mutates
  /// the provider). Returns null when nothing is pending or the pending payload
  /// targets a different provider — in which case the booking flow pre-checks
  /// nothing and the other target's payload is left intact.
  ///
  /// Split from [consumeFor] to fix a Riverpod "modified a provider while the
  /// widget tree was building" crash: the booking Step 1 screens read the
  /// payload synchronously in `initState` (so [_seedOnce] can pre-check against
  /// the resolved catalogue), then defer the one-shot [clear] to a post-frame
  /// callback — off the build phase.
  PendingServicePreselection? peekFor(String targetId) {
    final PendingServicePreselection? current = state;
    if (current == null || current.targetId != targetId) return null;
    return current;
  }

  /// Returns the pending payload IFF it targets [targetId], then clears it
  /// (one-shot consume). Returns null when nothing is pending or the pending
  /// payload targets a different provider — in which case the booking flow
  /// pre-checks nothing and the other target's payload is left intact.
  ///
  /// WARNING: mutates state — must NOT be called during a widget build /
  /// `initState`. The booking screens use [peekFor] + a deferred [clear]
  /// instead. Retained for API symmetry / non-lifecycle callers.
  PendingServicePreselection? consumeFor(String targetId) {
    final PendingServicePreselection? current = state;
    if (current == null || current.targetId != targetId) return null;
    state = null;
    return current;
  }

  /// Clears any pending pre-selection. Paired with the search filter reset.
  void clear() => state = null;
}
