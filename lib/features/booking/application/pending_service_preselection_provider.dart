// Holds the one-shot [PendingServicePreselection] handed from the discovery
// search results screen to the booking flow.
//
// Lifecycle:
//   • [set] — called at result-card navigation time (master / salon card) when
//     a service filter is active, recording which provider + which service-type
//     slugs to pre-check.
//   • [consumeFor] — called on the booking Step 1 screen's FIRST build (via its
//     `initState`). Returns the payload IFF its [targetId] matches the provider
//     being booked, and NULLS the state in the same call — a strict one-shot
//     consume. Backing out of the booking flow and re-entering therefore does
//     NOT re-preselect (the agreed behaviour).
//   • [clear] — belt-and-suspenders reset, called when the user clears the
//     search filters so a stale payload can never leak into a later booking.
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
    ref.watch(authProvider);
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

  /// Returns the pending payload IFF it targets [targetId], then clears it
  /// (one-shot consume). Returns null when nothing is pending or the pending
  /// payload targets a different provider — in which case the booking flow
  /// pre-checks nothing and the other target's payload is left intact.
  PendingServicePreselection? consumeFor(String targetId) {
    final PendingServicePreselection? current = state;
    if (current == null || current.targetId != targetId) return null;
    state = null;
    return current;
  }

  /// Clears any pending pre-selection. Paired with the search filter reset.
  void clear() => state = null;
}
