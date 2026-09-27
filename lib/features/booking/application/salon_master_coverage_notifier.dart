// Phase 14.13 — per-service bookable-master coverage for the salon booking
// flow's master-assignment step. Rewired (Phase 23.x) onto the dedicated
// `GET /salons/{salonId}/services/{serviceDefId}/masters` endpoint. Phase 266
// split the per-service failure signal out of the silent-empty-list
// degradation (see "GRACEFUL DEGRADATION" below) and added a per-service
// retry entry point.
//
// WHY THIS PROVIDER EXISTS
// -------------------------
// `SalonMasterSelectionScreen` must show only the masters who perform at
// least one of the client's selected services (Phase 14.12 output), and for
// each selected service resolve which of the picked masters can do it. Neither
// existing salon read carries that information:
//   • [publicSalonProfileProvider]'s masters rail ([SalonMasterSummary]) has
//     no service list at all.
//   • [salonServiceCatalogProvider]'s catalogue ([SalonCatalogService]) has no
//     master list either — a salon service can be assigned to several
//     masters (`master_services` join table, backend `MasterServiceAssignment`),
//     and the public catalogue DTO deliberately omits that ownership mapping
//     (it is a display-only read).
//
// REWIRE (Phase 23.x, bookable-masters endpoint) — this provider used to
// fan `GET /masters/{masterId}/services` out over the salon's FULL roster
// (up to `kSalonMastersPageSize`, 50, bounded-chunked at 8-concurrent) and
// derive coverage by intersecting each master's own service list against the
// client's selection. That had two problems the backend's new endpoint fixes
// at the source:
//   1. A master with an active assignment but NO usable weekly schedule
//      still showed up as "covers this service", so picking them opened a
//      calendar with every date disabled (the bug this rewire fixes).
//   2. The fan-out scaled with roster size (up to 50 calls), not with what
//      the client actually selected.
// `SalonRepository.getBookableMasters(salonId, serviceDefId)` is called
// ONCE PER SELECTED SERVICE instead: the backend already filters to masters
// who are active, actively assigned, AND schedule-usable, so a scheduleless
// master is simply absent from the response — it can never reach this map,
// and therefore can never be picked on this screen. No roster read is needed
// here anymore; `publicSalonProfileProvider` is still watched by the SCREEN
// (not this provider) purely for master display data (name/avatar/rating) —
// see `salon_master_selection_screen.dart`'s file header, "DATA — per-master
// service coverage gap".
//
// FAMILY KEY — composite (salonId, selectedServiceIds), reusing
// [SalonBookingMasterSelectionArgs] (the screen's own nav payload) as the key
// type rather than inventing a parallel query class: freezed already gives it
// value equality with `DeepCollectionEquality` on [selectedServiceIds]
// (verified against the generated `.freezed.dart`), so re-watching with the
// SAME args instance — the normal case, since the screen holds `widget.args`
// as a stable field — resolves to the same cached family member instead of
// re-fetching. Keying on [selectedServiceIds] (not just [salonId], as
// before) is required now: the coverage map itself depends on which services
// were selected, since each selected service is its own network call.
//
// GRACEFUL DEGRADATION (backlog line 122) — the old `Future.wait` over the
// roster fan-out was all-or-nothing: one master's failed request blanked the
// ENTIRE grid. Each selected service's call is now caught independently, so
// one failing service degrades to "no bookable masters for that service"
// (surfaces as an uncovered service on screen) rather than failing the whole
// provider.
//
// PHASE 266 — the empty-list degradation above is silent BY DESIGN (any one
// service failing must never blank the others), but silence has a cost: an
// empty coverage row for a service reads IDENTICALLY on screen whether the
// call actually failed or the service genuinely has no bookable master right
// now, and the backend's bookable-service gate (see the phase doc) makes the
// genuine case rare. [SalonCoverage.degradedServiceIds] carries exactly the
// set of selected service ids whose OWN call failed — nothing else about the
// catch block below changed: same chunking, same concurrency, same per-
// service try/catch, same keepAlive + TTL. [SalonMasterServiceCoverage.
// retryService] is the paired per-service retry entry point: it re-issues
// ONE service's call and merges the result in place, touching no other
// service's cached row and never re-running [build] (so a healthy service's
// entry, and this family member's keepAlive TTL, are both left untouched).
//
// PHASE 266, AUDIT CYCLE 1 — the first cut of [retryService] captured
// [state.value] once, before its own `await`, and wrote its merge from that
// stale snapshot; two concurrent retries for DIFFERENT services could then
// have the later write silently discard the earlier one's result. Fixed by
// moving the merge into [SalonMasterServiceCoverage._settle], which re-reads
// [state] AFTER the network call — mirrors `SalonInvites.cancelInvite`'s
// identical `_settle`-after-await shape in `salon_invites_notifier.dart`.
// [SalonCoverage.retryingServiceIds] (the in-flight guard) and
// [SalonCoverage.retryCooldownUntil] (the post-failure cooldown, see
// [_kRetryCooldown]) live in the SAME resolved record for the same reason
// `SalonInvitesState.cancelling` does: one `ref.watch`, one source of truth,
// for both the guard and whatever reflects it on screen.
//
// PHASE 266, AUDIT CYCLE 2 — two MEDIUM fixes to the cycle-1 [retryService]:
//  1. Its `try`/`on Failure catch` only ever caught a [Failure]. A non-
//     [Failure] throw (the same "mapper `TypeError` on a malformed 200 body"
//     case [build]'s own "degradation ceiling" test documents for the
//     initial fetch) escaped BEFORE [_settle] ran, so the id stayed in
//     [SalonCoverage.retryingServiceIds] forever — a permanently spinning,
//     permanently disabled row. [_settle] now runs from a `finally` block,
//     so it ALWAYS runs, on every exit path. A non-[Failure] throw is
//     additionally still RE-thrown after that `finally` completes — mirrors
//     [build]'s own policy of never silently folding a non-network bug into
//     an ordinary "no bookable masters" result (see [build]'s catch and the
//     "degradation ceiling" test) — [build] cannot "degrade one service and
//     move on" (a thrown error there fails the entire assembling
//     `Future.wait` chunk), so the closest [retryService] equivalent is:
//     still settle THIS one service into degraded + cooldown (so the row
//     never gets stuck), but don't swallow the error either — let it
//     surface, same as [build] does. `salon_master_selection_screen.dart`'s
//     `_retryService` (a fire-and-forget call, by design — see [retryService]
//     doc) is the thing that actually stops that rethrow from reaching the
//     zone as an unhandled async error.
//  2. [SalonCoverage.retryCooldownUntil] had no expiry trigger: once
//     [_kRetryCooldown] elapsed, the id stayed disabled until some UNRELATED
//     rebuild happened to re-derive the screen's cooldown set against a
//     newer [ref.watch(clockProvider)] read. [_settle] now arms a one-shot
//     [Timer] per failed retry ([_armCooldownExpiry]) that removes the id
//     from [SalonCoverage.retryCooldownUntil] — a genuine `state` WRITE, so
//     every watcher rebuilds — the instant the cooldown window closes, with
//     no dependency on an unrelated rebuild happening to notice. One timer
//     per service id: a fresh failed retry for the SAME id cancels and
//     replaces whatever timer was already pending for it, and every timer is
//     cancelled in [build]'s `ref.onDispose` so none can fire past this
//     family member's own lifetime.
//
// BOUNDED FAN-OUT (mobile-perf LOW fix, Phase 23.x audit) — selections are
// normally 1-3 services, but the catalogue multi-select doesn't cap how many
// a client can pick, so the per-service `Future.wait` is issued in bounded
// chunks of [_kFetchChunkSize] rather than firing every call at once — the
// same cap the pre-rewire roster fan-out used (see the REWIRE note above).
//
// Cache: [ref.keepAlive] + a 5-minute TTL (mobile-perf MEDIUM fix, Phase
// 14.13 audit) — mirrors [salonReviewSummaryProvider]'s identical pattern. A
// plain `autoDispose` refired the full fetch on every intermediate pop (e.g.
// client tweaks the service selection, then re-enters this step) within the
// same booking session; the TTL keeps that round trip cached without keeping
// it alive indefinitely.

import 'dart:async';
import 'dart:developer';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../salon/data/salon_repository.dart';
import '../../salon/domain/bookable_master_assignment.dart';
import '../domain/salon_booking_args.dart';

part 'salon_master_coverage_notifier.g.dart';

/// Max concurrent `GET /salons/{salonId}/services/{serviceDefId}/masters`
/// calls in flight at once — mirrors the pre-rewire roster fan-out's cap
/// (mobile-perf LOW fix, Phase 23.x audit).
const int _kFetchChunkSize = 8;

/// Client-side cooldown after a FAILED [SalonMasterServiceCoverage.
/// retryService] call (mobile-security MEDIUM, Phase 266 audit cycle 1) —
/// `GET /salons/{salonId}/services/{serviceDefId}/masters` carries no
/// per-endpoint rate limit, and this retry is, by design, user-repeatable
/// for as long as D5 keeps the degraded row on screen. 3s is short enough
/// that a genuine "let me try again" tap is never punished, long enough
/// that an impatient tap-loop can't turn into a request per animation
/// frame. Read through [clockProvider] (never the host wall clock, never a
/// real [Timer]) so a test can pin/advance "now" deterministically instead
/// of sleeping a real 3 seconds — see that provider's file header.
const Duration _kRetryCooldown = Duration(seconds: 3);

/// [SalonMasterServiceCoverage]'s resolved value — the coverage map plus
/// (Phase 266) the subset of the request's selected services whose OWN
/// `getBookableMasters` call failed.
///
/// [degradedServiceIds] exists so a caller can tell "nobody performs this
/// service" (the id is simply absent from [byMaster], AND absent here) apart
/// from "we couldn't check" (absent from [byMaster], but present here) — the
/// two demand opposite UI: the first is terminal, the second is a retryable
/// error. A degraded service is always absent from every master's row in
/// [byMaster] — the failing fetch never contributed any master for it — so
/// checking coverage alone can never distinguish the two cases; this field is
/// the only source of truth for which one applies.
///
/// [retryingServiceIds] and [retryCooldownUntil] (Phase 266 audit cycle 1)
/// carry [SalonMasterServiceCoverage.retryService]'s own guard state IN the
/// resolved value — mirrors `SalonInvitesState.cancelling`
/// (`salon_invites_notifier.dart`) rather than a private field on the
/// notifier — so the screen reflects "retrying" (spinner) and "cooling down"
/// (disabled) through the SAME `ref.watch` every other consumer already
/// uses, instead of a second, easy-to-desync source of truth:
///  * [retryingServiceIds] — service ids with a `retryService` call
///    currently awaiting its network response. Also the double-tap guard:
///    a call for an id already in this set is refused.
///  * [retryCooldownUntil] — serviceDefId → the [clockProvider] instant a
///    FAILED retry's cooldown ends. A present, still-future entry refuses a
///    further `retryService` call for that id.
typedef SalonCoverage = ({
  Map<String, Map<String, String>> byMaster,
  Set<String> degradedServiceIds,
  Set<String> retryingServiceIds,
  Map<String, DateTime> retryCooldownUntil,
});

/// Shared empty instances — a fresh [SalonMasterServiceCoverage.build] reuses
/// these rather than allocating a new empty [Set]/[Map] no `retryService`
/// call has touched yet (mirrors `salon_invites_notifier.dart`'s `_kNoIds`).
const Set<String> _kNoRetryingIds = <String>{};
const Map<String, DateTime> _kNoRetryCooldown = <String, DateTime>{};

/// Maps each master id bookable for ≥1 of [args.selectedServiceIds] to a
/// `serviceDefId -> assignmentId` map of the services (from that selection)
/// they are bookable for: the key is the catalog id (comparable against
/// [SalonCatalogService.id]), the value is that master's OWN
/// `MasterServiceAssignment` id for the same service — the id the slot-
/// availability endpoint actually requires (see `salon_master_schedule.dart`'s
/// `orderedMasterServiceIds`). "Does master X cover service Y" is still a
/// simple `coverage[x]?.containsKey(y) ?? false` check, now spelled
/// `result.byMaster[x]?.containsKey(y) ?? false` — see [SalonCoverage].
///
/// Generated provider name: `salonMasterServiceCoverageProvider` — a family,
/// call it with the screen's [SalonBookingMasterSelectionArgs].
///
/// Converted from a plain `@riverpod` function to a class-based
/// [AsyncNotifier] (Phase 266) purely so [retryService] has somewhere to
/// live: D4 requires refetching exactly ONE service and merging the result
/// in place, which is a mutation on the cached [state] — not expressible
/// from a bare function provider, which only ever reruns its whole body via
/// `ref.invalidate`/`ref.refresh` (D3 forbids that: it would re-issue every
/// already-succeeded service's request too). The generated provider keeps
/// the exact same name and family-key shape, so every existing `ref.watch` /
/// `ref.invalidate` call site is unaffected by the conversion itself — only
/// the resolved value's TYPE changed, from the bare coverage map to
/// [SalonCoverage].
@riverpod
class SalonMasterServiceCoverage extends _$SalonMasterServiceCoverage {
  /// One-shot cooldown-expiry [Timer] per service id currently in
  /// [SalonCoverage.retryCooldownUntil] — armed by [_armCooldownExpiry],
  /// cancelled wholesale in [build]'s `ref.onDispose` (audit cycle 2, finding
  /// #2). Never touched directly outside those two places.
  final Map<String, Timer> _cooldownTimers = <String, Timer>{};

  @override
  Future<SalonCoverage> build(SalonBookingMasterSelectionArgs args) async {
    // 5-minute cache window — see the file header's "Cache" note. The timer is
    // cancelled on dispose so it can never fire after the provider is gone.
    final link = ref.keepAlive();
    final Timer timer = Timer(const Duration(minutes: 5), link.close);
    ref.onDispose(timer.cancel);
    // Audit cycle 2, finding #2 — every pending cooldown-expiry Timer
    // ([_armCooldownExpiry]) must die with this family member too, so none
    // can fire (and write to a torn-down notifier) past its own lifetime.
    // Audit cycle 3, finding #2 — pulled into [cancelCooldownTimers] (a
    // named, `@visibleForTesting` method) rather than staying an inline
    // closure: `FakeSalonMasterServiceCoverage.build` (test-only) OVERRIDES
    // this [build] wholesale — Dart never chains an overridden method to its
    // superclass's body automatically — so a widget test that exercises the
    // REAL (inherited) [retryService] against the fake arms a REAL
    // [_cooldownTimers] entry via [_armCooldownExpiry] with nothing left to
    // cancel it on dispose, and `flutter_test` fails any test that tears down
    // with a pending [Timer]. Naming this lets the fake's own [build] call the
    // exact same cleanup instead of re-deriving (and risking drifting from)
    // this closure.
    ref.onDispose(cancelCooldownTimers);

    final SalonRepository repo = ref.watch(salonRepositoryProvider);

    // One `getBookableMasters` call per selected service, issued in bounded-
    // size chunks of at most [_kFetchChunkSize] concurrent requests (mobile-
    // perf LOW fix — mirrors the pre-rewire roster fan-out's cap, see the file
    // header's REWIRE note). Selections are normally 1-3 services, but the
    // catalogue multi-select doesn't cap how many a client can pick, so an
    // unbounded `Future.wait` over the full selection would still be an
    // unbounded parallel fan-out in the worst case. Each call is wrapped in
    // its own try/catch so a single failing service degrades to "no bookable
    // masters for that service" instead of failing every other
    // already-resolved (or still in-flight) service's coverage too, and
    // results are assembled chunk-by-chunk so `perService[i]` stays aligned
    // with `args.selectedServiceIds[i]` regardless of chunking.
    final List<List<BookableMasterAssignment>> perService =
        <List<BookableMasterAssignment>>[];
    // Phase 266 — the ids this build() pass could not resolve; the catch
    // block below is the ONLY thing this phase adds to the fetch itself (see
    // the file header's "PHASE 266" note).
    final Set<String> degraded = <String>{};
    for (
      int start = 0;
      start < args.selectedServiceIds.length;
      start += _kFetchChunkSize
    ) {
      final int end = start + _kFetchChunkSize < args.selectedServiceIds.length
          ? start + _kFetchChunkSize
          : args.selectedServiceIds.length;
      final List<String> batch = args.selectedServiceIds.sublist(start, end);
      final List<List<BookableMasterAssignment>>
      batchResults = await Future.wait(
        batch.map((String serviceDefId) async {
          try {
            return await repo.getBookableMasters(
              salonId: args.salonId,
              serviceDefId: serviceDefId,
            );
          } on Failure catch (e, st) {
            // Debug-only, matching the rest of the feature (`booking_mapper`,
            // `appointment_repository`). Today's payload is a `Failure` plus a
            // catalogue `serviceDefId` — no PII — but the gate is what keeps it
            // that way once a release-mode crash reporter (Phase 8.1) starts
            // ingesting `log()` output.
            if (kDebugMode) {
              log(
                'getBookableMasters($serviceDefId) failed — treating as no '
                'bookable masters for this service, and flagging it '
                'degraded so the UI can offer a retry instead of reading '
                'this as a genuine "nobody performs it"',
                name: 'booking.salonMasterCoverage',
                level: 900,
                error: e,
                stackTrace: st,
              );
            }
            degraded.add(serviceDefId);
            return const <BookableMasterAssignment>[];
          }
        }),
      );
      perService.addAll(batchResults);
    }

    final Map<String, Map<String, String>> coverage =
        <String, Map<String, String>>{};
    for (int i = 0; i < args.selectedServiceIds.length; i++) {
      final String serviceDefId = args.selectedServiceIds[i];
      for (final BookableMasterAssignment row in perService[i]) {
        coverage.putIfAbsent(
          row.masterId,
          () => <String, String>{},
        )[serviceDefId] = row.masterServiceId;
      }
    }
    return (
      byMaster: coverage,
      degradedServiceIds: degraded,
      retryingServiceIds: _kNoRetryingIds,
      retryCooldownUntil: _kNoRetryCooldown,
    );
  }

  /// D4 — refetches exactly ONE [serviceDefId] (never the whole family) and
  /// merges the result into the cached [state] in place.
  ///
  /// Deliberately does NOT call [ref.invalidate]/[ref.refresh] or re-run
  /// [build]: either would re-issue every OTHER selected service's request
  /// too (D3/D4 forbid that — a healthy service must never be refetched just
  /// because a sibling failed) and would reset this family member's 5-minute
  /// keepAlive TTL, set once in [build] and otherwise left alone for the
  /// life of the cached entry.
  ///
  /// Guards, in order (Phase 266 audit cycle 1 — verifier MEDIUM #1/#2/#3,
  /// LOW #4, security MEDIUM #5/LOW #6):
  ///  1. [serviceDefId] must be one of [SalonBookingMasterSelectionArgs.
  ///     selectedServiceIds] — never trust a caller's id blindly (#6).
  ///  2. [state] must be a settled [AsyncData] — mirrors
  ///     `SalonInvites.cancelInvite`'s identical guard (`salon_invites_
  ///     notifier.dart`): `state.value` alone survives an `AsyncLoading`/
  ///     `AsyncError` via `copyWithPrevious`, so a bare non-null check would
  ///     still act mid an in-flight [build] rebuild (#4).
  ///  3. [SalonCoverage.retryingServiceIds] must not already contain
  ///     [serviceDefId] — a double-tap is a no-op, not a second request
  ///     (#3).
  ///  4. [SalonCoverage.retryCooldownUntil] must not hold a still-future
  ///     entry for [serviceDefId] — see [_kRetryCooldown] (#5).
  ///
  /// The merge itself finishes in [_settle], which re-reads [state] AFTER
  /// the network await instead of reusing whatever was captured before it —
  /// a SIBLING service's retry can complete its own merge while this one is
  /// still in flight, and writing from a pre-await snapshot would silently
  /// discard that write (#1). [_settle] also re-checks [ref.mounted] before
  /// touching [state] at all: this family member's only lifeline past its
  /// first watcher popping is the 5-minute keepAlive TTL in [build], and a
  /// retry that outlives it must never write to a torn-down notifier (#2).
  Future<void> retryService(String serviceDefId) async {
    if (!args.selectedServiceIds.contains(serviceDefId)) return;

    final SalonCoverage? current = state.value;
    if (current == null || state is! AsyncData<SalonCoverage>) return;
    if (current.retryingServiceIds.contains(serviceDefId)) return;

    final DateTime? cooldownUntil = current.retryCooldownUntil[serviceDefId];
    if (cooldownUntil != null &&
        !ref.read(clockProvider)().isAfter(cooldownUntil)) {
      return;
    }

    // Tag this id in-flight immediately — before the network call even
    // starts — so the row can show its spinner on the very next frame.
    // `byMaster`/`degradedServiceIds` are reused BY REFERENCE (untouched);
    // only the two retry-tracking fields change. Any stale cooldown entry
    // for this id is dropped here too: the guard above already let this
    // attempt through, so nothing should read it as still cooling down
    // while it is actively retrying.
    state = AsyncData<SalonCoverage>((
      byMaster: current.byMaster,
      degradedServiceIds: current.degradedServiceIds,
      retryingServiceIds: <String>{...current.retryingServiceIds, serviceDefId},
      retryCooldownUntil: current.retryCooldownUntil.containsKey(serviceDefId)
          ? (Map<String, DateTime>.of(current.retryCooldownUntil)
              ..remove(serviceDefId))
          : current.retryCooldownUntil,
    ));

    final SalonRepository repo = ref.read(salonRepositoryProvider);
    List<BookableMasterAssignment> rows = const <BookableMasterAssignment>[];
    bool failed = false;
    try {
      rows = await repo.getBookableMasters(
        salonId: args.salonId,
        serviceDefId: serviceDefId,
      );
    } on Failure catch (e, st) {
      failed = true;
      if (kDebugMode) {
        log(
          'retryService($serviceDefId) failed again — leaving it degraded '
          'for another manual retry after a ${_kRetryCooldown.inSeconds}s '
          'cooldown',
          name: 'booking.salonMasterCoverage',
          level: 900,
          error: e,
          stackTrace: st,
        );
      }
    } catch (e, st) {
      // Audit cycle 2, finding #1 — anything that is NOT a [Failure] (a
      // mapper `TypeError` on a malformed 200 body is the realistic case;
      // see [build]'s "degradation ceiling" test for the identical gap on
      // the initial fetch). This is a genuine bug, not a transient network
      // condition, so it is NOT swallowed the way a [Failure] is above:
      // still mark this ONE service failed (so `finally`, below, settles it
      // into degraded + cooldown instead of leaving it stuck mid-retry), but
      // rethrow afterwards — mirrors [build]'s own policy of never quietly
      // folding a non-network bug into an ordinary empty result. The caller
      // (`salon_master_selection_screen.dart`'s `_retryService`) is a
      // fire-and-forget call by design and is responsible for catching this
      // rethrow so it never reaches the zone as an unhandled async error.
      failed = true;
      if (kDebugMode) {
        log(
          'retryService($serviceDefId) threw a non-Failure error — settling '
          'it as failed (degraded + cooldown) and rethrowing, mirroring '
          "build()'s policy of never silently swallowing a non-network bug",
          name: 'booking.salonMasterCoverage',
          level: 1000,
          error: e,
          stackTrace: st,
        );
      }
      rethrow;
    } finally {
      // Runs on EVERY exit path — including the `rethrow` above — so the id
      // can never be left stranded in `retryingServiceIds` (audit cycle 2,
      // finding #1).
      _settle(serviceDefId, rows: rows, failed: failed);
    }
  }

  /// Applies a finished [retryService] call to whatever [state] is NOW —
  /// see that method's doc for why this is never the pre-await snapshot.
  void _settle(
    String serviceDefId, {
    required List<BookableMasterAssignment> rows,
    required bool failed,
  }) {
    if (!ref.mounted) return;
    final SalonCoverage? now = state.value;
    if (now == null) return;

    // Only THIS service's rows are touched — see `_mergeRetriedService`'s
    // doc for why a healthy, unrelated master's inner `Map` instance
    // survives this call unchanged (verifier LOW #7).
    final Map<String, Map<String, String>> nextByMaster = _mergeRetriedService(
      base: now.byMaster,
      serviceDefId: serviceDefId,
      rows: rows,
    );
    final Set<String> nextDegraded = Set<String>.of(now.degradedServiceIds);
    if (failed) {
      nextDegraded.add(serviceDefId);
    } else {
      nextDegraded.remove(serviceDefId);
    }

    state = AsyncData<SalonCoverage>((
      byMaster: nextByMaster,
      degradedServiceIds: nextDegraded,
      retryingServiceIds: <String>{...now.retryingServiceIds}
        ..remove(serviceDefId),
      retryCooldownUntil: failed
          ? <String, DateTime>{
              ...now.retryCooldownUntil,
              serviceDefId: ref.read(clockProvider)().add(_kRetryCooldown),
            }
          : now.retryCooldownUntil,
    ));

    // Audit cycle 2, finding #2 — a failed retry needs something to clear
    // its OWN cooldown entry once [_kRetryCooldown] elapses; nothing else in
    // the app reads a clock on a timer for this row. A successful retry
    // never reaches here (see [_armCooldownExpiry]'s own membership guard on
    // the off chance a stale timer for an EARLIER failed attempt is still
    // pending — cancelling it here would be redundant, not wrong, but the
    // membership check makes that unnecessary).
    if (failed) {
      _armCooldownExpiry(serviceDefId);
    }
  }

  /// Arms a one-shot [Timer] that removes [serviceDefId] from
  /// [SalonCoverage.retryCooldownUntil] once [_kRetryCooldown] elapses —
  /// audit cycle 2, finding #2. That removal is a genuine `state` write, so
  /// every `ref.watch` consumer (the screen's disabled/enabled row) rebuilds
  /// the instant the cooldown closes, instead of waiting on an unrelated
  /// rebuild to notice a newer [clockProvider] read.
  ///
  /// One timer per [serviceDefId]: cancels whatever timer was already
  /// pending for this id before scheduling the new one, so a fresh failed
  /// retry always replaces (never stacks with) an earlier still-pending
  /// timer for the SAME id.
  /// Cancels and clears every pending [_cooldownTimers] entry — the body
  /// [build] registers via `ref.onDispose` on every real family member.
  /// `@visibleForTesting` so [FakeSalonMasterServiceCoverage.build] (the one
  /// fake that overrides [build] instead of calling through to it, per that
  /// class's file header) can register the SAME cleanup itself, keeping the
  /// production dispose contract intact for a fake that only ever exercises
  /// the inherited (real) [retryService]/[_armCooldownExpiry] path. Never
  /// called directly by production code outside [build]'s own
  /// `ref.onDispose`.
  @visibleForTesting
  void cancelCooldownTimers() {
    for (final Timer t in _cooldownTimers.values) {
      t.cancel();
    }
    _cooldownTimers.clear();
  }

  void _armCooldownExpiry(String serviceDefId) {
    _cooldownTimers.remove(serviceDefId)?.cancel();
    _cooldownTimers[serviceDefId] = Timer(_kRetryCooldown, () {
      _cooldownTimers.remove(serviceDefId);
      if (!ref.mounted) return;
      final SalonCoverage? now = state.value;
      // Nothing to clear — either a later retry already resolved (success
      // removed the entry, or another failure re-armed its OWN timer, which
      // cancelled this one before it could ever fire).
      if (now == null || !now.retryCooldownUntil.containsKey(serviceDefId)) {
        return;
      }
      state = AsyncData<SalonCoverage>((
        // `byMaster`/`degradedServiceIds`/`retryingServiceIds` are reused BY
        // REFERENCE, untouched — only `retryCooldownUntil` changes, so the
        // screen's `identical()` memoization and the wizard-step memo both
        // still hit (this write must not force either recompute).
        byMaster: now.byMaster,
        degradedServiceIds: now.degradedServiceIds,
        retryingServiceIds: now.retryingServiceIds,
        retryCooldownUntil: Map<String, DateTime>.of(now.retryCooldownUntil)
          ..remove(serviceDefId),
      ));
    });
  }
}

/// Rebuilds [base] with ONLY [serviceDefId]'s rows touched (verifier LOW #7,
/// Phase 266 audit cycle 1) — the pre-fix merge rebuilt a fresh inner `Map`
/// for EVERY master on every retry, no matter how unrelated to the retried
/// service. A master whose row does not mention [serviceDefId] and is not
/// among [rows]' master ids keeps its EXACT `Map` instance, so a consumer
/// comparing by identity (this file's own tests today; the screen's memoized
/// derivation in `salon_master_selection_screen.dart` tomorrow) can tell
/// "untouched by this retry" from "changed". A master left with an empty row
/// after the removal is dropped entirely, so `byMaster.containsKey` stays
/// accurate for `_MasterSelectionStatic.eligible`.
Map<String, Map<String, String>> _mergeRetriedService({
  required Map<String, Map<String, String>> base,
  required String serviceDefId,
  required List<BookableMasterAssignment> rows,
}) {
  final Set<String> newMasterIds = <String>{
    for (final BookableMasterAssignment r in rows) r.masterId,
  };
  final Map<String, Map<String, String>> next = <String, Map<String, String>>{};
  for (final MapEntry<String, Map<String, String>> entry in base.entries) {
    final Map<String, String> row = entry.value;
    final bool hadService = row.containsKey(serviceDefId);
    if (!hadService && !newMasterIds.contains(entry.key)) {
      next[entry.key] = row; // untouched — same Map instance, never rebuilt
      continue;
    }
    next[entry.key] = hadService
        ? <String, String>{
            for (final MapEntry<String, String> r in row.entries)
              if (r.key != serviceDefId) r.key: r.value,
          }
        : Map<String, String>.of(row);
  }
  for (final BookableMasterAssignment row in rows) {
    next[row.masterId] = <String, String>{
      ...?next[row.masterId],
      serviceDefId: row.masterServiceId,
    };
  }
  next.removeWhere((_, Map<String, String> row) => row.isEmpty);
  return next;
}
