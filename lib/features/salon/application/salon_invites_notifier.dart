// Salon staff-invitation HISTORY for one salon — every invitation ever sent,
// newest first — plus the per-row cancel machine.
//
// A `@riverpod` family keyed on `salonId`, so the settings-hub screen
// (`SalonPendingInvitesScreen`) and the invite form's own inline block
// (`InviteStaffScreen`) share ONE instance per salon: cancelling from either
// surface updates the other with no refetch, and neither screen issues a
// second round trip when the user hops between them. The form's block
// FILTERS this shared list down to pending rows — see `invite_staff_screen
// .dart` — because the two surfaces answer different questions off the same
// data.
//
// ORDERING IS THE SERVER'S. `GET /salons/{salonId}/invites` returns rows
// already sorted `createdAt DESC, id DESC`. There is no client-side sort and
// no `.reversed` here, deliberately: a defensive re-sort would hide a server
// ordering regression behind a green screen, and a millisecond tie would then
// resolve differently on the device than in the payload.
//
// WHY THE STATE IS A RECORD, NOT A BARE `List<SalonInvite>`
// ---------------------------------------------------------
// A cancel is a per-ROW operation with three visible outcomes (in flight /
// settled / failed-and-restored), and the screen must render all three side
// by side while OTHER rows stay idle. Folding that into the top-level
// `AsyncValue` would be wrong twice over: an `AsyncLoading` for one row's
// cancel would blank the whole list, and an `AsyncError` would replace the
// list with a full-screen error for a failure that is scoped to one invite.
// So the list stays `AsyncData` throughout a cancel and the per-row state
// lives beside it in two id sets. Mirrors `SalonStaffMemberProfileData`'s own
// record-typedef precedent rather than introducing a freezed view model.
//
// OPTIMISTIC TRANSITION CONTRACT
//   * tap  → the id enters [SalonInvitesState.cancelling]; the row stays
//            put and swaps its «Скасувати» label for an in-row spinner.
//   * 2xx  → the row STAYS in [SalonInvitesState.invites] and flips to
//            [InviteStatus.cancelled], which drops its cancel action and
//            raises the «Скасовано» chip. It is HISTORY now, not a deletion:
//            removing it locally would contradict the very list the next
//            refetch returns. No refetch either — `DELETE
//            .../invites/{inviteId}` is authoritative and a re-`GET` would
//            only cost a round trip to learn what the 2xx already said.
//   * error → the row is left in place, still pending, and its id enters
//            [SalonInvitesState.failed], which renders the in-row error
//            chip. The next tap on the same row clears the flag and retries.
//
// Every post-`await` `state` write is `ref.mounted`-guarded: this provider is
// autoDispose and a viewer can pop the screen mid-request, disposing the
// element while the DELETE is still in flight (same guard shape as
// `booking_cancel_in_flight_notifier.dart`).

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/salon_repository.dart';
import '../domain/invite_status.dart';
import '../domain/salon_invite.dart';

part 'salon_invites_notifier.g.dart';

/// The invite-history list plus the per-row cancel bookkeeping.
///
/// [cancelling] holds the [SalonInvite.inviteId]s whose `DELETE` is in
/// flight; [failed] holds the ids whose last cancel attempt errored and which
/// therefore render an in-row error chip. Both are always subsets of the ids
/// present in [invites].
///
/// [truncated] is carried through from the server envelope so the screen can
/// say the list is capped — see [SalonInviteHistory].
///
/// [pending] is [invites] filtered to [InviteStatus.pending], DERIVED HERE
/// rather than in a screen's `build`. `InviteStaffScreen` shows the pending
/// subset under its form, and computing it there walked all 200 history rows
/// and allocated a fresh `List` on EVERY build of that screen — a role toggle,
/// a `_submitting` flip, every keystroke that changes the email field's error.
/// Derived once per data change instead, it is also a STABLE INSTANCE across
/// the emissions that do not touch the list (a cancel starting, a cancel
/// failing), so a consumer comparing it by identity sees no change.
typedef SalonInvitesState = ({
  List<SalonInvite> invites,
  List<SalonInvite> pending,
  bool truncated,
  Set<String> cancelling,
  Set<String> failed,
});

/// Empty per-row bookkeeping — hoisted so a fresh `build()` and every
/// list-only rebuild reuse the same immutable empty sets.
const Set<String> _kNoIds = <String>{};

/// The [SalonInvitesState.pending] projection — the ONE place the "waiting for
/// an answer" subset is defined, so the form's block and the notifier's own
/// cancel guard can never disagree about what pending means.
List<SalonInvite> _pendingOf(List<SalonInvite> invites) => <SalonInvite>[
  for (final SalonInvite invite in invites)
    if (invite.status == InviteStatus.pending) invite,
];

/// Loads (and locally mutates) the invitation history of salon [salonId].
///
/// Generated provider name: `salonInvitesProvider` (a family — call it as
/// `salonInvitesProvider(salonId)`).
@riverpod
class SalonInvites extends _$SalonInvites {
  @override
  Future<SalonInvitesState> build(String salonId) async {
    final SalonInviteHistory history = await ref
        .watch(salonRepositoryProvider)
        .listSalonInvites(salonId);
    return (
      invites: history.invites,
      pending: _pendingOf(history.invites),
      truncated: history.truncated,
      cancelling: _kNoIds,
      failed: _kNoIds,
    );
  }

  /// Cancels invitation [inviteId] — see this file's header for the full
  /// optimistic-transition contract.
  ///
  /// A no-op when the target is not [SalonInvite.isCancellable]: the backend
  /// 404s a cancel of any used, revoked or expired invite, and the row does
  /// not render the action in those states anyway. This guard is the
  /// authoritative one — a caller reaching past the widget (a stale closure
  /// held across a status flip, a test, a future surface) must not be able to
  /// fire a request the server will reject.
  ///
  /// Also a no-op while the same id's `DELETE` is already in flight (the
  /// row's own spinner already blocks a second tap visually, but a rapid
  /// double tap can land two calls inside one frame) and while the list has
  /// not resolved yet.
  Future<void> cancelInvite(String inviteId) async {
    final SalonInvitesState? current = state.value;
    // `state.value` survives an `AsyncError`/`AsyncLoading` via
    // `copyWithPrevious`, so a bare non-null check is not "the list is
    // showing". Only act when the CURRENT state is genuinely resolved data —
    // during a reload/error the screen is not rendering a cancellable row.
    if (current == null || state is! AsyncData<SalonInvitesState>) return;
    if (current.cancelling.contains(inviteId)) return;

    final int index = current.invites.indexWhere(
      (SalonInvite i) => i.inviteId == inviteId,
    );
    if (index < 0 || !current.invites[index].isCancellable) return;

    state = AsyncData<SalonInvitesState>((
      invites: current.invites,
      // Same instances — nothing about the ROWS changed, only this id's
      // in-flight flag, so a consumer that compares either list by identity
      // correctly concludes it has no work to do.
      pending: current.pending,
      truncated: current.truncated,
      cancelling: <String>{...current.cancelling, inviteId},
      // Clear any previous failure chip for this row — the retry is starting.
      failed: current.failed.contains(inviteId)
          ? (<String>{...current.failed}..remove(inviteId))
          : current.failed,
    ));

    try {
      await ref
          .read(salonRepositoryProvider)
          .cancelInvite(salonId: salonId, inviteId: inviteId);
    } catch (e, st) {
      if (kDebugMode) {
        log(
          'cancelInvite($inviteId) failed',
          name: 'feature.salon.salonInvites',
          level: 900,
          error: e,
          stackTrace: st,
        );
      }
      _settle(inviteId, cancelled: false);
      return;
    }
    _settle(inviteId, cancelled: true);
  }

  /// Applies a finished cancel to whatever the state is NOW (re-read, never
  /// the pre-`await` snapshot — a sibling row's cancel may have resolved
  /// while this one was in flight).
  ///
  /// [cancelled] true flips the row to [InviteStatus.cancelled] IN PLACE;
  /// false leaves it untouched and raises its error chip.
  void _settle(String inviteId, {required bool cancelled}) {
    if (!ref.mounted) return;
    final SalonInvitesState? now = state.value;
    if (now == null) return;
    final Set<String> cancelling = <String>{...now.cancelling}
      ..remove(inviteId);
    if (cancelled) {
      final List<SalonInvite> invites = <SalonInvite>[
        for (final SalonInvite invite in now.invites)
          if (invite.inviteId == inviteId)
            invite.copyWith(status: InviteStatus.cancelled)
          else
            invite,
      ];
      state = AsyncData<SalonInvitesState>((
        invites: invites,
        // The one transition that genuinely leaves the pending subset — the
        // row is history now — so this is the one place it is recomputed.
        pending: _pendingOf(invites),
        truncated: now.truncated,
        cancelling: cancelling,
        failed: now.failed.contains(inviteId)
            ? (<String>{...now.failed}..remove(inviteId))
            : now.failed,
      ));
      return;
    }
    state = AsyncData<SalonInvitesState>((
      invites: now.invites,
      // The row is untouched — it is still pending and still cancellable —
      // so both list instances carry over unchanged.
      pending: now.pending,
      truncated: now.truncated,
      cancelling: cancelling,
      failed: <String>{...now.failed, inviteId},
    ));
  }
}
