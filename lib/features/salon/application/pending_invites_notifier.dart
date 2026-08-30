// Phase 21.11 — Pending (sent, not-yet-accepted) staff invitations for one
// salon, plus the per-row cancel machine.
//
// A `@riverpod` family keyed on `salonId`, so the settings-hub screen
// (`SalonPendingInvitesScreen`) and the invite form's own inline block
// (`InviteStaffScreen`) share ONE instance per salon: cancelling from either
// surface updates the other with no refetch, and neither screen issues a
// second round trip when the user hops between them.
//
// WHY THE STATE IS A RECORD, NOT A BARE `List<PendingInvite>`
// ----------------------------------------------------------
// A cancel is a per-ROW operation with three visible outcomes (in flight /
// gone / failed-and-restored), and the screen must render all three side by
// side while OTHER rows stay idle. Folding that into the top-level
// `AsyncValue` would be wrong twice over: an `AsyncLoading` for one row's
// cancel would blank the whole list, and an `AsyncError` would replace the
// list with a full-screen error for a failure that is scoped to one invite.
// So the list stays `AsyncData` throughout a cancel and the per-row state
// lives beside it in two id sets. Mirrors `SalonStaffMemberProfileData`'s own
// record-typedef precedent rather than introducing a freezed view model.
//
// OPTIMISTIC REMOVAL CONTRACT
//   * tap  → the id enters [PendingInvitesState.cancelling]; the row stays
//            put and swaps its «Скасувати» label for an in-row spinner.
//   * 2xx  → the row is removed from [PendingInvitesState.invites] locally.
//            No refetch: `DELETE .../invites/{inviteId}` is authoritative and
//            a re-`GET` would only cost a round trip to learn what the 2xx
//            already said.
//   * error → the row is left in place and its id enters
//            [PendingInvitesState.failed], which renders the in-row error
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
import '../domain/pending_invite.dart';

part 'pending_invites_notifier.g.dart';

/// The pending-invite list plus the per-row cancel bookkeeping.
///
/// [cancelling] holds the [PendingInvite.inviteId]s whose `DELETE` is in
/// flight; [failed] holds the ids whose last cancel attempt errored and which
/// therefore render an in-row error chip. Both are always subsets of the ids
/// present in [invites] — an id is dropped from BOTH the moment its row is
/// removed.
typedef PendingInvitesState = ({
  List<PendingInvite> invites,
  Set<String> cancelling,
  Set<String> failed,
});

/// Empty per-row bookkeeping — hoisted so a fresh `build()` and every
/// list-only rebuild reuse the same immutable empty sets.
const Set<String> _kNoIds = <String>{};

/// Loads (and locally mutates) the outstanding invitations of salon
/// [salonId].
///
/// Generated provider name: `pendingInvitesProvider` (a family — call it as
/// `pendingInvitesProvider(salonId)`).
@riverpod
class PendingInvites extends _$PendingInvites {
  @override
  Future<PendingInvitesState> build(String salonId) async {
    final List<PendingInvite> invites = await ref
        .watch(salonRepositoryProvider)
        .listPendingInvites(salonId);
    return (invites: invites, cancelling: _kNoIds, failed: _kNoIds);
  }

  /// Cancels invitation [inviteId] — see this file's header for the full
  /// optimistic-removal contract.
  ///
  /// A no-op while the same id's `DELETE` is already in flight (the row's own
  /// spinner already blocks a second tap visually, but a rapid double tap can
  /// land two calls inside one frame — this is the authoritative guard) and
  /// while the list has not resolved yet.
  Future<void> cancelInvite(String inviteId) async {
    final PendingInvitesState? current = state.value;
    // `state.value` survives an `AsyncError`/`AsyncLoading` via
    // `copyWithPrevious`, so a bare non-null check is not "the list is
    // showing". Only act when the CURRENT state is genuinely resolved data —
    // during a reload/error the screen is not rendering a cancellable row.
    if (current == null || state is! AsyncData<PendingInvitesState>) return;
    if (current.cancelling.contains(inviteId)) return;

    state = AsyncData<PendingInvitesState>((
      invites: current.invites,
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
          name: 'feature.salon.pendingInvites',
          level: 900,
          error: e,
          stackTrace: st,
        );
      }
      _settle(inviteId, removeRow: false);
      return;
    }
    _settle(inviteId, removeRow: true);
  }

  /// Applies a finished cancel to whatever the state is NOW (re-read, never
  /// the pre-`await` snapshot — a sibling row's cancel may have resolved
  /// while this one was in flight).
  ///
  /// [removeRow] true drops the invite from the list; false leaves it in
  /// place and raises its error chip.
  void _settle(String inviteId, {required bool removeRow}) {
    if (!ref.mounted) return;
    final PendingInvitesState? now = state.value;
    if (now == null) return;
    final Set<String> cancelling = <String>{...now.cancelling}
      ..remove(inviteId);
    if (removeRow) {
      state = AsyncData<PendingInvitesState>((
        invites: <PendingInvite>[
          for (final PendingInvite invite in now.invites)
            if (invite.inviteId != inviteId) invite,
        ],
        cancelling: cancelling,
        failed: now.failed.contains(inviteId)
            ? (<String>{...now.failed}..remove(inviteId))
            : now.failed,
      ));
      return;
    }
    state = AsyncData<PendingInvitesState>((
      invites: now.invites,
      cancelling: cancelling,
      failed: <String>{...now.failed, inviteId},
    ));
  }
}
