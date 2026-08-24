// Phase 267 — SalonBookingDraft: the flow-scoped list owner for the salon
// multi-service booking flow (D3). Holds `List<SalonServiceBooking>` plus
// the `salonId` for the duration of ONE booking action.
//
// PURE MODEL/STATE — no Dio, no repository, no screen wired to it in this
// phase (see the phase doc's "Out of scope": assigning masters is Phases
// 268-269, scheduling is Phases 273-275).
//
// D3 — keepAlive, not route `extra`
// -----------------------------------
// Threading the list through `GoRoute.extra` at every step (what the salon
// flow does today, elsewhere) breaks down once the schedule hub (Phase 275)
// opens the slot picker and comes BACK, mutating one entry: with `extra` the
// hub would have to rebuild and re-push its own route to record each pick,
// growing the back stack by one entry per scheduled service. A keepAlive
// notifier makes "hub -> pick -> hub" a pop, not a push.
//
// D4 — explicit disposal on exit, tested here via container.invalidate
// -----------------------------------------------------------------------
// A keepAlive notifier that survives a completed booking would repopulate
// the next booking with the previous action's picks. The flow (a later
// phase) calls `ref.invalidate(salonBookingDraftProvider)` on exit
// (success, or popping past step 1) — from the screen that is VISIBLY ON
// TOP, never a covered one: Riverpod 3 pauses covered consumers, so an
// invalidate issued while the hub is covered can dispose-and-refetch at the
// wrong moment (see `project_riverpod_offstage_pause_invalidate.md`). This
// file only provides the primitive `build()` reset; no screen calls
// `invalidate` yet.
//
// D6 — N capped at 10 selected services
// -----------------------------------------
// The cap lives with the draft list because the draft list is what enforces
// it (re-homed here 2026-08-22 from the deleted Phase 272). The
// service-selection step (a later phase) refuses an 11th selection and says
// why — it must not silently truncate, so [selectServices] throws rather
// than clamping.
//
// D5 — no appointment, no [SalonMasterSchedule], no grouping. This file
// never imports either type.
//
// H-1 (mobile-security HIGH, 2026-08-22) — session boundary
// -----------------------------------------------------------
// [SalonBookingDraft] is `keepAlive: true` and, before this fix, nothing
// tied its lifetime to the auth session. A second client logging in on the
// same process (or a master force-logged-out mid-flow by
// `RefreshInterceptor`) would find the FIRST session's `masterId`,
// `masterServiceId`, retained [SalonMasterSummary] (name/avatar/rating),
// `startAt`, and selected services still sitting in memory — exactly what
// the flow reads on next entry.
//
// [build] therefore watches the AUTHENTICATED IDENTITY (the user id alone,
// via `authProvider.select(...)`) — mirroring
// `client_review_signal_provider.dart`'s identical shape: `keepAlive: true`
// and no external bookkeeping of its own. A logout (id -> null) or a
// different account logging in (id -> a different id) rebuilds this
// provider through the ordinary Riverpod cascade and returns a fresh empty
// draft, the same reset [SalonBookingDraft.build] already performs on the
// explicit-invalidate path (D4) above. Selecting ONLY the id — never the
// whole `AsyncValue<AuthSession>` — is deliberate: `RefreshInterceptor`
// calls `AuthNotifier.setAccessToken` on every silent token refresh, which
// emits a NEW `AuthSession.authenticated` with the SAME user but a
// different `accessToken`; watching the full session would wipe an
// in-progress draft on every silent refresh.
//
// No `AuthNotifier.logout()` sweep is added for this provider. Unlike
// `DayKeepAliveLru` (`bookings_day_notifier.dart`), this notifier holds no
// external bookkeeping — no LRU, no `ref.keepAlive()` links — for the
// identity watch's rebuild to miss, so an explicit sweep would be redundant
// work on every logout. See `client_review_signal_provider.dart`'s
// identical reasoning and the NOTE inside `AuthNotifier.logout` explaining
// why that sibling provider is deliberately absent from its own sweep list.

// `ProviderListenable.select` (used below to narrow the `authProvider` watch
// to the identity-bearing slice — H-1) is not part of `riverpod_annotation`'s
// show-list; every other caller of `authProvider.select(...)` in this
// codebase (`bookings_day_notifier.dart`, `client_review_signal_provider.dart`,
// `search_filters_controller.dart`, `verification_screen.dart`) reaches it
// through the full `flutter_riverpod` package for the same reason.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../auth/domain/auth_session.dart';
import '../../auth/domain/user.dart';
import '../../auth/presentation/auth_notifier.dart';
import '../../salon/domain/salon_master_summary.dart';
import '../../salon/domain/salon_service_catalog.dart';
import '../domain/salon_service_booking.dart';

part 'salon_booking_draft_notifier.g.dart';

/// D6 — hard cap on how many services one booking action's draft may carry.
/// 10 is not arbitrary: it is the largest N for which Phase 277's paced
/// submit finishes inside a tolerable progress bar once backend Phase 264's
/// burst lands. If this cap moves, Phase 277 D3 (which cites it by number)
/// moves with it.
const int kMaxSalonDraftServices = 10;

/// Immutable state: the salon this draft targets (null before
/// [SalonBookingDraft.selectServices] is called) plus the ordered list of
/// per-service drafts. Order is insertion order — [SalonBookingDraft]'s
/// per-entry mutators update in place and never reorder.
class SalonBookingDraftState {
  const SalonBookingDraftState({
    this.salonId,
    this.entries = const <SalonServiceBooking>[],
  });

  final String? salonId;
  final List<SalonServiceBooking> entries;

  /// The entry for [serviceDefId], or `null` if no such entry is in the
  /// draft.
  SalonServiceBooking? entryFor(String serviceDefId) {
    for (final SalonServiceBooking entry in entries) {
      if (entry.serviceDefId == serviceDefId) return entry;
    }
    return null;
  }

  /// Returns a copy with the entry matching [serviceDefId] replaced by
  /// `update(entry)` — every other entry, and the list's order, is left
  /// untouched. A TRUE no-op — returns `this`, the exact same instance, with
  /// no new `List` and no new state allocated — if no entry matches
  /// [serviceDefId] (P-2: a defensive/stale caller must not fire a full
  /// notify for nothing).
  SalonBookingDraftState withUpdatedEntry(
    String serviceDefId,
    SalonServiceBooking Function(SalonServiceBooking entry) update,
  ) {
    if (entryFor(serviceDefId) == null) return this;
    final List<SalonServiceBooking> next = <SalonServiceBooking>[
      for (final SalonServiceBooking entry in entries)
        entry.serviceDefId == serviceDefId ? update(entry) : entry,
    ];
    return SalonBookingDraftState(salonId: salonId, entries: next);
  }

  /// P-1 — value equality over [salonId] and [entries] (element-wise, not
  /// identity and not a deep/recursive compare — [SalonServiceBooking] is
  /// freezed with flat field equality, so a deep traversal buys nothing and
  /// only costs more). Without this, every mutator's fresh instance made
  /// Riverpod's `updateShouldNotify` see a change unconditionally, even when
  /// the new state was equal in every field to the old one.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SalonBookingDraftState) return false;
    if (other.salonId != salonId) return false;
    if (other.entries.length != entries.length) return false;
    for (int i = 0; i < entries.length; i++) {
      if (other.entries[i] != entries[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(salonId, Object.hashAll(entries));
}

/// Owns the draft list for one salon multi-service booking action.
///
/// Generated provider name: `salonBookingDraftProvider`.
@Riverpod(keepAlive: true)
class SalonBookingDraft extends _$SalonBookingDraft {
  @override
  SalonBookingDraftState build() {
    // H-1 — session boundary. See the file header. Selecting ONLY the
    // authenticated user id (never the whole `AsyncValue<AuthSession>`) so a
    // silent token refresh does not wipe an in-progress draft.
    ref.watch(
      authProvider.select(
        (AsyncValue<AuthSession> session) => switch (session.value) {
          Authenticated(:final User user) => user.id,
          Unauthenticated() || null => null,
        },
      ),
    );
    return const SalonBookingDraftState();
  }

  /// Step 1 — seeds the draft with [services] (the client's catalogue
  /// selection) for [salonId], each starting fully unassigned/unscheduled.
  /// Replaces any prior draft outright (a fresh selection replaces the
  /// previous one, it does not merge with it).
  ///
  /// D6: throws [ArgumentError] rather than truncating when [services] has
  /// more than [kMaxSalonDraftServices] entries — the selection step is
  /// responsible for refusing the 11th pick before it ever reaches here.
  void selectServices({
    required String salonId,
    required List<SalonCatalogService> services,
  }) {
    if (services.length > kMaxSalonDraftServices) {
      throw ArgumentError.value(
        services.length,
        'services.length',
        'D6: at most $kMaxSalonDraftServices services per booking action',
      );
    }
    state = SalonBookingDraftState(
      salonId: salonId,
      entries: <SalonServiceBooking>[
        for (final SalonCatalogService s in services)
          SalonServiceBooking(service: s, serviceDefId: s.id),
      ],
    );
  }

  /// Step 2 — assigns [masterId] to the entry keyed by [serviceDefId]. D2:
  /// [masterId] and [masterServiceId] are ALWAYS set together — there is no
  /// mutator that sets one without the other, so an entry's pair is either
  /// both null (unassigned) or both non-null (assigned). [durationMinutes],
  /// when given, comes from the same `MasterServiceAssignment` — it fixes
  /// the entry's appointment window length once scheduled.
  ///
  /// A no-op if no entry matches [serviceDefId] (defensive — every
  /// [serviceDefId] this is called with is expected to have been seeded by
  /// [selectServices] first).
  void assignMaster({
    required String serviceDefId,
    required String masterId,
    required String masterServiceId,
    required SalonMasterSummary master,
    int? durationMinutes,
  }) {
    state = state.withUpdatedEntry(
      serviceDefId,
      (SalonServiceBooking entry) => entry.copyWith(
        masterId: masterId,
        masterServiceId: masterServiceId,
        master: master,
        durationMinutes: durationMinutes ?? entry.durationMinutes,
      ),
    );
  }
}
