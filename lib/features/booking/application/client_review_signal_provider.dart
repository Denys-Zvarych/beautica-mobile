// Session-scoped "this provider has just left feedback about this booking's
// client" signal — the ONE mechanism that reaches a `MasterArchiveScreen`
// which is NOT the screen that pushed `LeaveClientFeedbackScreen`.
//
// ## Why this exists (mobile-perf MEDIUM, 2026-08-17, cycle 2)
//
// `LeaveClientFeedbackScreen` used to fire a bare
// `ref.invalidate(masterArchiveProvider)` on a successful submit. That was
// removed because it discarded every cached filter combination's accumulated
// pages and scroll position — and, worse, because the archive is COVERED at
// that moment, so its consumers are PAUSED and an autoDispose family member
// invalidated with only paused listeners is DISPOSED outright, making the
// archive rebuild from a bare `AsyncLoading` skeleton on pop-back (QA mutation
// M4 reproduces the user's original bug report verbatim from exactly that
// mechanism).
//
// Its REPLACEMENT — `LeaveClientFeedbackScreen` popping `true`, awaited by
// `MasterArchiveScreen._openReview`, applied via
// `MasterArchiveNotifier.markClientReviewed` — only covers the ADJACENT entry
// path, where the archive itself is the pusher. It does NOT cover:
//
//   archive → row tap → `BookingDetailScreen` → footer «Залишити відгук про
//   клієнта» → review → submit → pop → pop back to the archive
//
// There, the archive is two routes down; nothing it pushed ever pops back to
// it with a result. A pop-result CHAIN through `BookingDetailScreen` is not an
// acceptable fix either: a system/predictive back gesture pops with `null`, so
// the signal would be silently lost on the most common way out of a detail
// screen.
//
// So the signal is decoupled from navigation entirely: the review screen
// DEPOSITS a booking id here on a successful submit, and any
// `MasterArchiveScreen` alive now OR built later reads it and patches its own
// matching row. Delivery to a covered archive happens on RESUME (Riverpod 3
// pauses covered consumers and flushes the change when they resume) — which is
// exactly when the master can see the archive again, so that is on time, not
// late. Pinned by `client_review_signal_provider_test.dart` and by
// `master_archive_screen_test.dart`'s "signal from a NON-adjacent path"
// group, which drives a real paused/covered consumer rather than reasoning
// about it.
//
// ## FAIL-CLOSED — the direction of trust is one-way and must stay that way
//
// This signal can only ever cause `Booking.providerCanReviewClient` to go
// `true → false` (the CTA disappears). Nothing here can set it back to `true`:
// ids are only ever ADDED to the set, and the only consumer,
// `MasterArchiveNotifier.markClientReviewed`, writes a hardcoded `false` (it
// is the single `copyWith(providerCanReviewClient:)` call site in `lib/` —
// mobile-security verified, 2026-08-17; keep it that way). The worst case a
// wrong id can produce is a hidden «Відгук» CTA that the server would have
// allowed — recoverable by reopening the archive (a fresh
// `GET /bookings/me` is authoritative and the set only hides rows it still
// matches), never a review form offered on a booking the server will reject.
//
// ## SEC — keepAlive means this must be tied to the SESSION, not to listeners
//
// Booking ids are user-scoped data, and a `keepAlive` provider outlives every
// screen that reads it. `build()` therefore watches the AUTHENTICATED IDENTITY
// (the user id alone), mirroring `bookings_day_notifier.dart`'s identical
// session-boundary watch: a logout (id → null) or a different account logging
// in (id → another id) rebuilds this provider through the ordinary Riverpod
// cascade and returns a fresh EMPTY set, so one master's reviewed-booking ids
// can never suppress CTAs in another master's archive. Selecting ONLY the id —
// never the whole `AsyncValue<AuthSession>` — is deliberate for the same
// reason it is there: a silent token refresh (`AuthNotifier.setAccessToken`)
// emits a new session with the SAME id and must NOT wipe the set mid-session.

// `ProviderListenable.select` (used below to narrow the `authProvider` watch to
// the identity-bearing slice) is not part of `riverpod_annotation`'s show-list
// — same reason `bookings_day_notifier.dart` reaches for the full package.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../auth/domain/auth_session.dart';
import '../../auth/domain/user.dart';
import '../../auth/presentation/auth_notifier.dart';

part 'client_review_signal_provider.g.dart';

/// Booking ids this provider has left client feedback about during the CURRENT
/// session. Empty on every fresh session — see the file header's SEC section.
///
/// Generated provider name: `clientReviewSignalProvider`.
@Riverpod(keepAlive: true)
class ClientReviewSignal extends _$ClientReviewSignal {
  @override
  Set<String> build() {
    // Session boundary — see the file header. Same `.select` on the user id
    // that `BookingsDayNotifier.build` uses, for the same two reasons (clear
    // on logout / account switch; do NOT clear on a silent token refresh).
    ref.watch(
      authProvider.select(
        (AsyncValue<AuthSession> session) => switch (session.value) {
          Authenticated(:final User user) => user.id,
          Unauthenticated() || null => null,
        },
      ),
    );
    return const <String>{};
  }

  /// Records that feedback about [bookingId]'s client was just submitted.
  ///
  /// ADD-ONLY, by design (see the file header's fail-closed section) — there is
  /// deliberately no `remove`/`clear` counterpart that could hand a row its
  /// «Відгук» CTA back. Idempotent: re-signalling an id already in the set
  /// keeps the SAME set instance, so it publishes no state change and cannot
  /// spin a consumer that rebuilds off this provider.
  ///
  /// ACCEPTED, not overlooked: with no in-session eviction the set grows
  /// monotonically for as long as the session lasts (mobile-security /
  /// mobile-perf INFO, 2026-08-17 cycle 3). The bound is one short id string
  /// (~36 bytes) per review a single provider actually submits between two
  /// logins — a rate capped by human data entry, not by list length or
  /// pagination — and the whole set is dropped on logout, on an account switch
  /// (the identity watch in [build]) and on process death. An eviction policy
  /// would cost more than it saves AND would weaken the fail-closed guarantee:
  /// every removal is a chance to hand a «Відгук» CTA back for a booking the
  /// server will reject. Deliberately not built.
  void markReviewed(String bookingId) {
    final Set<String> current = state;
    if (current.contains(bookingId)) return;
    state = Set<String>.unmodifiable(<String>{...current, bookingId});
  }
}
