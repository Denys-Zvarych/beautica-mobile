// Phase 231 (HISTORY cutover, 2026-08-16) — «Архів» page: paginated,
// filterable HISTORY-partition notifier.
//
// A `@riverpod` AsyncNotifier family keyed by [MasterArchiveQuery], mirroring
// `MyBookingsNotifier`'s pagination shape (`my_bookings_notifier.dart`) —
// `_fetchFirstPage`/`refresh`/`loadMore`, same in-flight/last-page guards.
// What is genuinely new here is REQUEST SHAPING, documented below.
//
// ## The request is ALWAYS `partition: BookingPartition.history` PLUS a
// legacy `status` set — never conditional on the filter selection
//
// Originally shipped against `BookingPartition.past`; switched to
// `BookingPartition.history` (backend `beautica-backend` `81e8166`,
// `feat/booking-partition-history`) because the archive's whole point is to
// show a master's completed visit history, and `PAST` structurally excludes
// CANCELLED/DECLINED rows — the reported bug this cutover fixes (a declined
// visit never appeared here, and ticking «Скасовано» always came back
// empty). `HISTORY` is a union view, `PAST ∪ CANCELLED` =
// `COMPLETED ∪ NOT_COMPLETED ∪ (CONFIRMED AND ends_at < now) ∪ CANCELLED ∪
// DECLINED` ≡ everything except UPCOMING — see [BookingPartition.history]'s
// doc for the full definition and, critically, the HARD SEQUENCING HAZARD it
// carries that `past`/`cancelled`/etc. do not: `HISTORY` is an unrecognised
// VALUE on any backend older than `81e8166`, which is a 400
// (`MethodArgumentTypeMismatchException`), not a silent degrade. **This
// notifier now hard-requires a HISTORY-capable backend.**
//
// `status` is still sent alongside `partition` — mirrors
// `MyBookingsNotifier._fetchFirstPage`'s Phase 227 rollout-valve pattern:
// `partition` wins outright and `status` is IGNORED server-side whenever
// `partition` is present (`BookingService#getMyBookings`'s javadoc,
// beautica-backend), so against ANY backend that recognises `partition` at
// all (HISTORY-capable or not), `status` is dead weight either way. It is
// kept purely for the one case it can still help: a backend so old it has
// no `partition` param declared AT ALL (a genuinely pre-28.2 backend, where
// an unrecognised param NAME — not value — is silently dropped by Spring;
// see `booking_repository.dart`'s `getMyBookings` doc for that distinct
// failure mode). Against a backend that HAS `partition` but predates
// `81e8166` specifically (28.2-but-pre-HISTORY), the legacy `status` set
// does NOT help — that request still 400s on the unrecognised `HISTORY`
// value regardless of what `status` carries. So the fallback below is
// deliberately widened to `{COMPLETED, NOT_COMPLETED, CANCELLED, DECLINED}`
// — the closest a `status`-only, partition-blind backend can approximate
// HISTORY (see [_legacyStatusesFor]'s own doc for why `CONFIRMED`/elapsed
// still cannot be expressed this way, and why that's stated rather than
// papered over).
//
// ## The SCOPE is a field on the family key, not on the notifier (phase 342)
//
// [MasterArchiveQuery.salonId] selects WHICH history is read: `null` means
// "mine" (`GET /bookings/me`, byte-identical to every pre-342 caller) and a
// non-null id means "this salon's whole history, across every master"
// (`GET /bookings/salon/{salonId}`, backend phase 322's `partition=HISTORY`).
// Everything else in this file is scope-agnostic and stayed untouched by that
// change: [_archiveStatusPredicate], [_applyPredicate], the
// [_generation]/[_mergeTargetFor] re-entrancy guard, the raw-page `hasMore`
// walk, the failed-`loadMore` recovery, and
// [markClientReviewed]/[markClientsReviewed] (which patch a SERVER-supplied
// flag and therefore need no client-side role gate — `bookings_capability.
// dart`'s "there is no third boolean for may-leave-client-feedback").
//
// The scope lives on the QUERY because this is an autoDispose family keyed by
// it — see [MasterArchiveQuery.of]'s doc for why two scopes sharing one cache
// entry would serve the wrong list. The branch itself lives in exactly one
// place, [_fetchPage], which both [_fetchFirstPage] and [loadMore] call.
//
// ## Outcome filtering («Підтверджено»/«Виконано»/«Скасовано») is applied
// CLIENT-SIDE, on top of the fixed `partition: HISTORY` fetch
//
// The backend has no way to combine `partition=HISTORY` with a `status`
// sub-filter in one request (status is ignored the instant partition is
// non-null — see above), so narrowing "HISTORY, but only COMPLETED rows" is
// not expressible server-side without giving up partition's correctness (the
// elapsed-CONFIRMED computation `status` alone cannot do). Filtering the
// already-fetched HISTORY page in Dart instead is what makes
// [BookingStatusFilterGroup.confirmed] ("Підтверджено") work as the
// «Потребують закриття» filter with NO new UI (the amendment this phase
// shipped under, 2026-08-16): within `BookingPartition.history`, a booking
// is (still-open) CONFIRMED if and only if `awaitingClosure` is `true` — no
// non-elapsed CONFIRMED row can ever appear in this partition either.
// Filtering by `status == confirmed` and filtering by `awaitingClosure ==
// true` are therefore the SAME predicate here, not merely correlated.
//
// ## Ticking «Скасовано» ([BookingStatusFilterGroup.cancelled],
// CANCELLED/DECLINED) — FIXED by this cutover, no longer a scope limit
//
// Under the old `BookingPartition.past` fetch this always resolved to an
// EMPTY visible list — `PAST` structurally never contained a CANCELLED/
// DECLINED row (that was `BookingPartition.cancelled`'s own, disjoint
// domain). `HISTORY` includes both statuses, so
// [_archiveStatusPredicate]/[_applyPredicate] now surface exactly the
// cancelled-or-declined rows the fetched HISTORY page contains — no change
// needed to the predicate/filtering logic itself, only to which partition is
// requested. Pinned by `master_archive_notifier_test.dart`'s inverted
// «Скасовано» test (was previously an "empty list" assertion; a former
// regression guard for the bug this cutover fixes).
//
// ## Pagination interacts with client-side filtering
//
// A FILTERED view can render fewer visible rows per fetched page than the
// server's page size (e.g. ticking «Виконано» against a raw page that is
// mostly `awaitingClosure` rows) — `hasMore` still reflects the SERVER's
// pagination, so `loadMore` keeps advancing through raw pages until the
// server is exhausted, appending each page's filtered subset. This can mean
// several `loadMore` calls before the visible list visibly grows on a
// heavily-filtered view; it never mis-reports "no more" while raw pages
// remain, and the UNFILTERED (default, most-used) view pays none of this
// cost — every fetched row is shown, so pagination there is exactly
// server-driven, same as `MyBookingsNotifier`.
//
// ## "Select all 3 rows" collapses to "no filter" — NOT
// `BookingStatus.dayListWireStatuses` reused verbatim
//
// [_archiveStatusPredicate] deliberately does NOT call
// `BookingStatus.dayListWireStatuses`, even though its "select-all collapses
// to omit-status" shape is the right ONE of its two behaviours to reuse. The
// other — hiding CANCELLED/DECLINED on an EMPTY (untouched) selection — is a
// day-list product decision this screen never adopted (the amendment: "the
// archive's default is the whole PAST partition, which is NOT the day
// list's default"). Under the original `BookingPartition.past` fetch,
// applying it here would have been a harmless no-op (`PAST` never contained
// CANCELLED/DECLINED either way); under the `HISTORY` cutover it would NOT
// be harmless — HISTORY genuinely returns CANCELLED/DECLINED rows now, so
// adopting the day-list's default would actively hide them from the
// archive's unfiltered landing view, defeating this whole cutover. So this
// file writes its own small resolver instead, sharing only the part that is
// genuinely load-bearing here too: naming every status a filter UI can
// select must NOT be allowed to silently exclude
// [BookingStatus.notCompleted], which none of `BookingStatusFilterGroup`'s
// three rows can express (mobile-security LOW-1's reasoning, restated for
// this screen's own maximal set).

import 'package:flutter/foundation.dart';
// `ProviderListenable.select` (used below to narrow the `authProvider` watch
// to the identity-bearing slice — phase 342 D6) is not part of
// `riverpod_annotation`'s show-list; every other caller of
// `authProvider.select(authUserIdOrNull)` in this codebase reaches it through
// the full `flutter_riverpod` package for the same reason.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';

import '../../auth/presentation/auth_notifier.dart';
import '../data/booking_providers.dart';
import '../data/booking_repository.dart';
import '../domain/booking.dart';
import '../domain/booking_partition.dart';
import '../domain/booking_sort.dart';
import '../domain/booking_status.dart';
import '../domain/master_archive_query.dart';

part 'master_archive_notifier.g.dart';

/// Sentinel for [MasterArchiveState.copyWith]'s nullable [retryNotBefore]:
/// `copyWith(retryNotBefore: null)` has to mean "CLEAR the cooldown", which a
/// plain `?? this.x` idiom cannot express. Compare-by-identity, so no real
/// value can ever collide with it.
const Object _kUnset = Object();

/// Immutable snapshot of the archive's accumulated, already-filtered
/// bookings + paging cursor. Mirrors `MyBookingsState`, plus the one field
/// that shape does not carry — [retryNotBefore].
@immutable
class MasterArchiveState {
  const MasterArchiveState({
    required this.items,
    required this.page,
    required this.hasMore,
    this.isLoadingMore = false,
    this.retryNotBefore,
  });

  /// The VISIBLE bookings accumulated so far — already narrowed by the
  /// master's status selection (see file header). Server-ordered
  /// (newest-first), no client-side re-sort.
  final List<Booking> items;

  /// Zero-based index of the last fetched RAW server page (not the count of
  /// visible items, which can be fewer after client-side filtering).
  final int page;

  /// Whether a subsequent RAW server page exists.
  final bool hasMore;

  /// Whether a [MasterArchiveNotifier.loadMore] fetch is currently in
  /// flight.
  final bool isLoadingMore;

  /// THE FAILURE MEMORY (mobile-security HIGH, 2026-09-20). The instant before
  /// which no further [MasterArchiveNotifier.loadMore] may be issued, or
  /// `null` when the tail is free to fetch.
  ///
  /// ## The storm this closes
  ///
  /// `loadMore` swallows its own failure and restores `isLoadingMore: false`
  /// while `hasMore` stays `true` — so BOTH of the screen's scroll-listener
  /// guards re-satisfy immediately and the same failing request re-fires on
  /// every subsequent scroll notification. Under `ClampingScrollPhysics`
  /// (Android/Linux/Windows) the position comes to rest exactly at
  /// `maxScrollExtent`, the controller stops notifying, and the cost is one
  /// fetch per gesture. Under `BouncingScrollPhysics` (iOS — `ios/` exists in
  /// this repo, and the archive list passes a parentless
  /// `AlwaysScrollableScrollPhysics()` that inherits ambient physics) the
  /// overscroll settle keeps the position CHANGING for its whole duration.
  /// Measured on flutter-tester 800×600 with page 1 failing: 12 fetches for a
  /// single drag, 109 for one fling, 556 for four — ~687 across ten gestures,
  /// against the backend's 60/min per-user budget.
  ///
  /// ## Why a DEADLINE and not `hasMore = false`
  ///
  /// Clearing `hasMore` would stop the storm and also delete the
  /// «Завантажити ще» affordance, the `ListView`'s tail spinner slot, and the
  /// screen's auto-continue branch — a paging list permanently convinced it
  /// had reached the end because one request failed once. The deadline stops
  /// the re-arm while leaving every one of those intact.
  ///
  /// An ABSOLUTE instant, never a Kyiv day token — see `kyiv_day.dart`'s
  /// header for why the two must not be confused. Set from the server's own
  /// `Retry-After` when the failure is a [SalonBoardRateLimitedFailure] and
  /// from [kLoadMoreFailureBackoff] otherwise, and CLEARED (to `null`) by
  /// every page-0 fetch, so a pull-to-refresh or a filter change always starts
  /// the tail unblocked.
  final DateTime? retryNotBefore;

  /// Whether [retryNotBefore] is still in the future at [now] — the single
  /// predicate both [MasterArchiveNotifier.loadMore] and the screen's scroll
  /// listener consult, so the gate cannot be spelled two subtly different ways.
  ///
  /// instant-ok: a cooldown deadline is a genuine absolute-instant comparison
  /// (`kyiv_day.dart` exemption) — nothing here resolves a calendar DAY, so
  /// `kyivToday` would be the wrong tool and `.toUtc()`/`.toLocal()` on either
  /// side would be meaningless.
  bool isRetryBlockedAt(DateTime now) {
    final DateTime? until = retryNotBefore;
    return until != null && now.isBefore(until);
  }

  /// Seconds still to wait at [now], rounded UP so a partially-elapsed second
  /// never renders as «0 с». `0` when nothing is blocked.
  ///
  /// instant-ok: see [isRetryBlockedAt].
  int retrySecondsRemainingAt(DateTime now) {
    final DateTime? until = retryNotBefore;
    if (until == null || !now.isBefore(until)) return 0;
    final int ms = until.difference(now).inMilliseconds;
    return (ms + 999) ~/ 1000;
  }

  MasterArchiveState copyWith({
    List<Booking>? items,
    int? page,
    bool? hasMore,
    bool? isLoadingMore,
    Object? retryNotBefore = _kUnset,
  }) {
    return MasterArchiveState(
      items: items ?? this.items,
      page: page ?? this.page,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      // Sentinel, not `??` — passing `null` explicitly must CLEAR the
      // cooldown, which is how an explicit retry re-arms the tail.
      retryNotBefore: identical(retryNotBefore, _kUnset)
          ? this.retryNotBefore
          : retryNotBefore as DateTime?,
    );
  }
}

/// How long the archive tail parks itself after a load-more failure that
/// carries no server-supplied `Retry-After`.
///
/// Five seconds, sized against the thing it has to outlast rather than picked
/// round: an iOS overscroll bounce settles in well under two seconds, and a
/// fling's whole ballistic simulation in well under four. Anything shorter
/// re-opens the gate mid-settle and the storm resumes at a lower rate; much
/// longer starts punishing a master who genuinely wants to re-tap
/// «Завантажити ще» after a transient blip.
const Duration kLoadMoreFailureBackoff = Duration(seconds: 5);

/// The full status coverage `BookingsFilterSheet`'s three rows
/// (`widgets/bookings_filter_sheet.dart`'s `BookingStatusFilterGroup`) can
/// express — the "maximal" set for [_archiveStatusPredicate]'s select-all
/// collapse.
///
/// HAND-LISTED, not derived from `BookingStatusFilterGroup.values` — this is
/// `application/`, and that enum lives in `presentation/widgets/`
/// (cross-feature-layer imports go through `domain/`/`shared/` only; see
/// `ARCHITECTURE-mobile.md`'s layer table). KEEP IN LOCKSTEP: a future fourth
/// filter row added there must add its status here on the same commit, or
/// the select-all collapse quietly stops covering it. Pinned by
/// `master_archive_notifier_test.dart`'s lockstep test, which imports the
/// widget file (tests may cross layers to assert an invariant; production
/// code here does not) and asserts this set equals
/// `BookingStatusFilterGroup.values.expand((g) => g.statuses).toSet()` —
/// mirrors `bookings_day_query.dart`'s own "KEEP IN LOCKSTEP WITH TWO SETS"
/// discipline.
const Set<BookingStatus> kArchiveFilterCoverage = <BookingStatus>{
  BookingStatus.confirmed,
  BookingStatus.completed,
  BookingStatus.cancelled,
  BookingStatus.declined,
};

/// Resolves the master's raw filter-sheet selection into the CLIENT-SIDE
/// status predicate applied to an already-fetched `HISTORY`-partition page.
/// An EMPTY set return means "no predicate — show every fetched row
/// verbatim".
///
/// See file header for the full reasoning. Two cases collapse to "no
/// predicate": an untouched (empty) selection, and every row the sheet
/// offers ticked at once — both must still surface a legacy
/// [BookingStatus.notCompleted] row, which none of the three rows can
/// individually select.
Set<BookingStatus> _archiveStatusPredicate(Set<BookingStatus> selected) {
  if (selected.isEmpty || selected.containsAll(kArchiveFilterCoverage)) {
    return const <BookingStatus>{};
  }
  return selected;
}

/// The legacy `status` query set sent alongside `partition: HISTORY` — the
/// Phase 227 rollout-valve value, honoured only by a backend old enough to
/// have no `partition` PARAM at all (see file header for why a backend that
/// has `partition` but predates `81e8166` gets NO benefit from this — that
/// request 400s on the unrecognised `HISTORY` value regardless). See file
/// header for the full reasoning.
Set<BookingStatus> _legacyStatusesFor(Set<BookingStatus> predicate) {
  if (predicate.isNotEmpty) return predicate;
  // Best-effort legacy default approximating HISTORY (`PAST ∪ CANCELLED`)
  // via `status` alone: COMPLETED/NOT_COMPLETED (PAST's terminal statuses)
  // plus CANCELLED/DECLINED (HISTORY's whole reason for existing over PAST).
  // This can NEVER be a full HISTORY equivalent — a partition-blind backend
  // has no way to compute "elapsed", so an unclosed CONFIRMED row that has
  // already ended is structurally unreachable via `status` alone (the same
  // limitation `BookingTab.past.statuses` accepts for its own legacy
  // fallback). Stated here rather than silently accepted: this fallback is
  // a best-effort approximation, not parity.
  return const <BookingStatus>{
    BookingStatus.completed,
    BookingStatus.notCompleted,
    BookingStatus.cancelled,
    BookingStatus.declined,
  };
}

List<Booking> _applyPredicate(
  List<Booking> items,
  Set<BookingStatus> predicate,
) {
  if (predicate.isEmpty) return items;
  return items.where((Booking b) => predicate.contains(b.status)).toList();
}

/// Paged, filtered bookings for the master «Архів» page.
///
/// autoDispose (the `@riverpod class` default) — each filter combination's
/// cache drops when nothing watches it (the archive screen is popped), so
/// re-opening it always starts from a fresh page 0.
@riverpod
class MasterArchiveNotifier extends _$MasterArchiveNotifier {
  /// In-flight guard for [refresh] — mirrors `MyBookingsNotifier._refreshing`.
  bool _refreshing = false;

  /// Bumped by every page-0 fetch (an initial [build] or a [refresh]), i.e.
  /// every time the accumulated list is thrown away and started over. An
  /// in-flight [loadMore] captures it and refuses to merge its page into a
  /// LATER generation — see [_mergeTargetFor].
  ///
  /// Deliberately not derived from [MasterArchiveState.page]: a refresh landing
  /// during the FIRST `loadMore` resets the cursor to 0, which is exactly the
  /// value that call captured, so a cursor comparison would read as "unchanged"
  /// in the single most common case.
  int _generation = 0;

  @override
  Future<MasterArchiveState> build(MasterArchiveQuery query) {
    // Session-boundary PII (phase 342 D6; `mobile-backlog.md:120`, filed
    // 2026-08-16 by mobile-security precisely against the moment this family
    // gained a second host). Ties every member's lifetime to the
    // AUTHENTICATED IDENTITY, not merely to its listeners: a logout (id →
    // null) or a different account signing in (id → a different id) rebuilds
    // through the ordinary Riverpod cascade instead of leaving a cached page
    // of a previous account's booking PII behind an autoDispose element a
    // fast re-login could re-read. This matters strictly more for the
    // salon-scoped member than it ever did for "mine": salon history carries
    // CLIENT NAMES ACROSS THE WHOLE ROSTER, not one master's own bookings.
    //
    // NARROWED through the shared [authUserIdOrNull] selector — never a bare
    // `ref.watch(authProvider)`. `RefreshInterceptor` calls
    // `AuthNotifier.setAccessToken` on EVERY silent token refresh, emitting a
    // new `Authenticated` with the same user and a different `accessToken`; a
    // bare watch cannot tell that apart from a logout and would throw away
    // every accumulated page and the master's scroll position mid-session.
    // Selecting just the id makes a refresh a no-op (same id, same `==`, no
    // rebuild) while a real identity change still rebuilds. Same discipline
    // `bookings_day_notifier.dart`'s `build` uses, and the reason
    // [authUserIdOrNull] was promoted in the first place — see its doc.
    //
    // ACCEPTED LIMIT, documented rather than fixed (audit-fix LOW-4,
    // 2026-09-19): this scopes the cache to IDENTITY, not to ENTITLEMENT. An
    // entitlement revocation that leaves the id unchanged — an admin removed
    // from salon B while still signed in as themselves — emits no new id, so
    // an already-cached salon-scoped page is NOT evicted and its rows keep
    // rendering until something else disposes the member. The exposure is
    // bounded on three sides: the server re-authorises EVERY fetch (the route
    // is gated by `@authz.canManageSalon`, so the next page, refresh or
    // re-open 403s rather than serving more), this family is autoDispose (the
    // member dies the moment the archive screen is popped), and nothing here
    // is persisted to disk, so the window closes at the latest on app
    // restart. Widening to a bare `ref.watch(authProvider)` would NOT fix it
    // either — a revocation emits no auth state at all — and would reintroduce
    // exactly the failure mode the `.select` above exists to avoid: every
    // silent token refresh discarding every accumulated page and the master's
    // scroll position. Closing this properly needs a server-pushed
    // entitlement signal, not a wider watch.
    ref.watch(authProvider.select(authUserIdOrNull));
    return _fetchFirstPage(query);
  }

  /// The ONE place this notifier talks to the repository — both
  /// [_fetchFirstPage] and [loadMore] route through it, so the scope branch
  /// exists exactly once (phase 342 D5). They differ only in [page].
  ///
  /// `query.salonId == null` is the pre-342 "mine" arm and is BYTE-IDENTICAL
  /// to what this notifier has always sent: the same [getMyBookings]
  /// argument set, in the same order, with the same values.
  ///
  /// ## The status narrowing on BOTH arms is unavoidably CLIENT-SIDE, and
  /// that costs round trips (mobile-perf LOW, audit-fix 2026-09-19)
  ///
  /// `partition` and `status` cannot co-exist as predicates: the backend
  /// ignores `status` outright whenever `partition` is present
  /// (`BookingService#getMyBookings`'s javadoc; backend phase 322 D2 for the
  /// salon route — see `booking_repository.dart`'s `getSalonBookings` doc).
  /// Since this notifier hard-requires `partition: HISTORY` for correctness
  /// (only the server can compute "elapsed CONFIRMED", which `status` alone
  /// cannot express), the outcome filter is applied by [_applyPredicate]
  /// AFTER the page lands — so a filtered page can render far fewer rows than
  /// it fetched, and `_MasterArchiveScreenState._kMaxAutoContinueAttempts`
  /// lets the screen burn up to THREE extra `loadMore` round trips filling
  /// the first screenful. The salon arm pays this over roster-wide pages.
  ///
  /// This is NOT fixable mobile-side — it is the backend's precedence rule,
  /// not a client choice, and the only alternatives (drop `partition`, or
  /// stop filtering) each give up correctness. Closing it needs a BACKEND
  /// change letting `partition` and `status` narrow together; until then this
  /// cost is accepted, not worked around. Do not "optimise" it by dropping
  /// `partition` — that reintroduces the phase-231 bug where declined and
  /// cancelled visits never appeared here at all.
  ///
  /// DECIDED, NOT PENDING (phase 342 § D10 — recorded here because the two
  /// paragraphs above otherwise read as an open TODO and have been re-raised
  /// as one). The ruling is: **no backend change**, and none is planned. The
  /// accepted cost above is the final answer at today's scale. It is
  /// reopened under ONE named condition and no other — a FILTERED archive at
  /// real roster scale that exhausts all three
  /// `_kMaxAutoContinueAttempts` and STILL renders short while
  /// `hasMore == true`. That is a measurement against the phase-345 fixture,
  /// not a judgement call: if the walk terminates inside its budget, the
  /// finding is recorded and nothing moves. Do not raise the constant
  /// defensively — an unbounded walk is a spin (see
  /// `_MasterArchiveScreenState._autoContinueAttempts`'s anti-spin doc).
  Future<PageResponse<Booking>> _fetchPage(
    MasterArchiveQuery query,
    Set<BookingStatus> predicate,
    int page,
  ) {
    final BookingRepository repo = ref.read(bookingRepositoryProvider);
    final String? salonId = query.salonId;
    if (salonId == null) {
      return repo.getMyBookings(
        statuses: _legacyStatusesFor(predicate),
        // ALWAYS sent, unconditionally — see file header's first section.
        // This is the hard requirement asserted on the CAPTURED request, not
        // just the repository call args. Requires a HISTORY-capable backend
        // (`81e8166`+) — see [BookingPartition.history]'s doc.
        partition: BookingPartition.history,
        serviceIds: query.serviceIds,
        sort: BookingSort.newest,
        page: page,
        asMaster: query.asOwnerMaster,
      );
    }

    // `serviceIds` is deliberately NOT forwarded on the salon arm, and cannot
    // be non-empty here: [MasterArchiveQuery.of] REJECTS
    // `salonId != null && serviceIds.isNotEmpty` at construction with an
    // `ArgumentError`. This used to be an `assert` on this very line; it was
    // moved to the family key in audit-fix MEDIUM-2 (2026-09-19) because an
    // `assert` is stripped in profile/release, so a shipped build would drop
    // the ids here while `MasterArchiveQuery.hasFilters` still reported
    // `true` — «Скинути» offered for a filter that narrowed nothing. Do NOT
    // re-add a local assert: the invalid state is now unrepresentable, and a
    // second copy of the rule is a second thing to drift.
    //
    // No `from`/`to`: the archive wants the salon's WHOLE history, and this
    // route has always accepted open-ended bounds.
    return repo.getSalonBookings(
      salonId: salonId,
      statuses: _legacyStatusesFor(predicate),
      partition: BookingPartition.history,
      sort: BookingSort.newest,
      page: page,
    );
  }

  Future<MasterArchiveState> _fetchFirstPage(MasterArchiveQuery query) async {
    _generation++;
    final Set<BookingStatus> predicate = _archiveStatusPredicate(
      query.statuses.toSet(),
    );
    final PageResponse<Booking> page = await _fetchPage(query, predicate, 0);

    return MasterArchiveState(
      items: _applyPredicate(page.items, predicate),
      page: page.page,
      hasMore: page.hasMore,
    );
  }

  /// Re-fetches page 0 — the pull-to-refresh entry point. Coalesces
  /// concurrent calls, mirroring `MyBookingsNotifier.refresh`.
  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      state = const AsyncLoading<MasterArchiveState>();
      state = await AsyncValue.guard(() => _fetchFirstPage(query));
    } finally {
      _refreshing = false;
    }
  }

  /// Appends the next RAW server page (filtered before being appended). See
  /// file header's pagination-vs-filtering section for why a filtered view
  /// may need several calls before the visible list visibly grows.
  ///
  /// No-op when: the notifier has no data yet, a load-more is already in
  /// flight, or the server-side stream is exhausted.
  ///
  /// ## The fetched page is merged into the state as it is AFTER the await,
  /// never into the snapshot captured before it (mobile-perf LOW, 2026-08-17
  /// cycle 3)
  ///
  /// [markClientReviewed] can land at any point during the round trip below,
  /// and rebuilding state from the pre-await `current` would silently DROP that
  /// row patch — the «Відгук» CTA would flick back on the moment the page
  /// landed. The signal-set path ([clientReviewSignalProvider], read by
  /// `master_archive_screen.dart`'s `_scheduleClientReviewSignalPatch`) would
  /// re-arm itself on the next build and heal it, but the pop-result-only path
  /// would NOT: a master who backs out of an already-reviewed booking's
  /// pre-gate pops `true` WITHOUT submitting, so nothing is ever deposited in
  /// the signal set and the lost patch is simply gone. Hence [_mergeTargetFor].
  Future<void> loadMore() async {
    final MasterArchiveState? current = state.value;
    if (current == null) return;
    if (current.isLoadingMore) return; // double-fetch guard
    if (!current.hasMore) return; // last raw page no-op
    // FAILURE-MEMORY guard (mobile-security HIGH, 2026-09-20). Gated HERE as
    // well as in `_MasterArchiveScreenState._onScroll`, deliberately: the
    // screen has three other entry points into this method (the
    // auto-continue post-frame callback, the `_ArchiveContinueState` tap, and
    // the tail affordance), and a gate that lived only in the scroll listener
    // would leave each of them free to re-fire the same failing request. See
    // [MasterArchiveState.retryNotBefore].
    //
    // instant-ok: a cooldown deadline compared against the injected clock —
    // an absolute-instant question, not a calendar-day one.
    if (current.isRetryBlockedAt(ref.read(clockProvider)())) return;

    // The pagination generation this call belongs to — see [_mergeTargetFor].
    final int generation = _generation;
    final int fromPage = current.page;
    state = AsyncData(current.copyWith(isLoadingMore: true));

    final Set<BookingStatus> predicate = _archiveStatusPredicate(
      query.statuses.toSet(),
    );

    try {
      final PageResponse<Booking> page = await _fetchPage(
        query,
        predicate,
        fromPage + 1,
      );

      final MasterArchiveState? target = _mergeTargetFor(generation);
      if (target == null) return;
      state = AsyncData(
        target.copyWith(
          items: <Booking>[
            ...target.items,
            ..._applyPredicate(page.items, predicate),
          ],
          page: page.page,
          hasMore: page.hasMore,
          isLoadingMore: false,
          // A page that LANDED clears any cooldown a previous failure left —
          // explicitly, because `copyWith` preserves the field otherwise.
          retryNotBefore: null,
        ),
      );
    } catch (e) {
      // A failed load-more must not blow away the already-rendered list —
      // mirrors `MyBookingsNotifier.loadMore`'s identical catch.
      //
      // What is NEW (mobile-security HIGH, 2026-09-20) is that the failure is
      // now REMEMBERED. Restoring `isLoadingMore: false` with `hasMore` still
      // `true` re-satisfies every caller's guard instantly, which under iOS
      // bouncing physics re-fired this exact request once per frame for the
      // whole overscroll settle. `retryNotBefore` is what the callers now
      // consult instead — see that field's doc for the measurement.
      //
      // instant-ok: a deadline built from the injected clock.
      final MasterArchiveState? target = _mergeTargetFor(generation);
      if (target == null) return;
      state = AsyncData(
        target.copyWith(
          isLoadingMore: false,
          retryNotBefore: ref.read(clockProvider)().add(_backoffFor(e)),
        ),
      );
    }
  }

  /// How long the tail parks after [error].
  ///
  /// The SERVER's own number wins when it sent one: backend PR #130 answers a
  /// board 429 with `Retry-After`, which `ErrorMapperInterceptor` now surfaces
  /// as [SalonBoardRateLimitedFailure.retryAfterSeconds] (it used to reach the
  /// app as an `UnknownFailure` with the header discarded). Re-fetching before
  /// that window closes cannot succeed and spends the budget the master's next
  /// deliberate tap needs.
  ///
  /// Everything else — a dropped connection, a 5xx, a deserialization
  /// breakdown — takes the flat [kLoadMoreFailureBackoff], which exists to
  /// outlast the SCROLL GESTURE rather than to model the server.
  Duration _backoffFor(Object error) {
    if (error is SalonBoardRateLimitedFailure) {
      final int? seconds = error.retryAfterSeconds;
      // `null` means absent / unparsable / above the 10-minute UX ceiling —
      // there is no honest server number, so the gesture-scale backoff is
      // still strictly better than none.
      if (seconds != null && seconds > 0) {
        return Duration(seconds: seconds);
      }
    }
    return kLoadMoreFailureBackoff;
  }

  /// The state a completed [loadMore] round trip may write into, re-read AFTER
  /// its await — or `null` when this call's result must be DISCARDED instead.
  ///
  /// Returns `null` in exactly two cases, both meaning "a newer, authoritative
  /// answer already replaced the list this page was fetched for":
  ///
  ///  * the notifier no longer holds data ([refresh] assigns a bare
  ///    `AsyncLoading` that drops the value, and a failed refresh leaves an
  ///    `AsyncError`) — writing here would launder that state away, exactly as
  ///    [markClientReviewed] refuses to;
  ///  * a page-0 fetch started or landed underneath ([_generation] moved) —
  ///    appending page `fromPage + 1` onto a list rebuilt from page 0 would
  ///    leave a hole in the middle AND push the cursor past it, so the NEXT
  ///    load-more would skip a page entirely. The refresh's own `items`/`page`/
  ///    `hasMore` are the authoritative bookkeeping, so the in-flight page is
  ///    dropped rather than merged.
  ///
  /// Otherwise the returned state is the SAME pagination generation the fetch
  /// started in, so its `items` can only differ from the pre-await snapshot by
  /// in-place row rewrites: [markClientsReviewed] is the only other writer that
  /// touches state within a generation, and it maps `items` 1:1 (never adds,
  /// drops or reorders). Appending the fetched page to it therefore cannot
  /// duplicate a row — the two id sets come from disjoint server pages.
  MasterArchiveState? _mergeTargetFor(int generation) {
    if (_generation != generation) return null;
    final AsyncValue<MasterArchiveState> snapshot = state;
    if (snapshot is! AsyncData<MasterArchiveState>) return null;
    return snapshot.value;
  }

  /// Rewrites the ONE already-loaded row identified by [bookingId] so its
  /// [Booking.providerCanReviewClient] reads `false` — dropping the «Відгук»
  /// CTA (`MasterBookingCard.onReview`) from that row alone, with NO network
  /// call, NO lost pages and NO lost scroll position.
  ///
  /// Called by `master_archive_screen.dart`'s `_openReview` when
  /// `LeaveClientFeedbackScreen` pops `true` — i.e. the provider just left
  /// feedback about that booking's client, or the destination's own
  /// `GET /bookings/{id}` pre-gate revealed the row was already reviewed.
  ///
  /// ## Why this exists instead of `ref.invalidate(masterArchiveProvider)`
  ///
  /// (mobile-perf MEDIUM, 2026-08-17.) Invalidating this family would discard
  /// every accumulated page and the master's scroll position, and — on a
  /// FILTERED archive — burn up to
  /// `_MasterArchiveScreenState._kMaxAutoContinueAttempts` extra `loadMore`
  /// round trips re-walking raw pages the master had already paged past. It
  /// would also show the master the full-list SKELETON on pop-back, which is
  /// worth spelling out because the mechanism is NOT the ordinary "reload shows
  /// loading" one (`AsyncValue.when` skips that for a refresh — see
  /// `master_archive_screen.dart`'s own note): the invalidate arrives while the
  /// archive is COVERED by the review route, so its consumers are PAUSED, and
  /// an autoDispose provider invalidated with only paused listeners is
  /// DISPOSED outright — there is no previous value left to retain, and the
  /// rebuild on resume starts from a bare `AsyncLoading`. All of that to learn
  /// ONE boolean on ONE row. Leaving a client review changes
  /// nothing else: [Booking.status] is untouched, so the row cannot move
  /// between filter partitions or day groups, and the server's own answer for
  /// this field after a successful write is exactly the `false` written here.
  ///
  /// Contrast `_confirmComplete`, which DOES change status (a row can leave
  /// the «Підтверджено» filter for «Виконано») and therefore legitimately
  /// reloads through `_reloadArchive` rather than patching locally.
  ///
  /// A NO-OP when the notifier holds no data yet (loading/error — nothing to
  /// patch, and writing `AsyncData` there would launder an error away) and
  /// when no loaded row is still REVIEWABLE under [bookingId] (a filter changed
  /// underneath, the row was never in this member's page set, or it is already
  /// patched). Never throws, never fabricates a row, and never allocates a new
  /// `items` list on a miss — that list's IDENTITY is
  /// `_MasterArchiveScreenState._groupedEntries`'s cache key, so a no-op that
  /// replaced it would silently cost an O(n) regroup.
  ///
  /// Deliberately does NOT self-invalidate — see
  /// `scripts/forbid_provider_self_invalidation.sh`.
  void markClientReviewed(String bookingId) =>
      markClientsReviewed(<String>{bookingId});

  /// The BATCH form of [markClientReviewed] — patches every row in
  /// [bookingIds] in ONE pass over `items`, emitting ONE new state.
  ///
  /// Exists for `master_archive_screen.dart`'s
  /// `_scheduleClientReviewSignalPatch`, which can hold several signalled ids
  /// at once when a `loadMore` page lands carrying rows the provider already
  /// reviewed on another screen. Calling the single-id form per id would copy
  /// the whole `items` list `k` times (O(k·n)) and emit `k` states; this copies
  /// it once (mobile-perf INFO, 2026-08-17 cycle 3).
  ///
  /// [markClientReviewed] DELEGATES here rather than the other way round, so
  /// there is still exactly ONE `copyWith(providerCanReviewClient:)` call site
  /// in `lib/` writing exactly one hardcoded `false` — the fail-closed
  /// invariant `client_review_signal_provider.dart`'s header locks and
  /// `master_archive_notifier_test.dart`'s FAIL-CLOSED test pins. Keep it that
  /// way.
  ///
  /// The guard tests the FLAG, not merely id presence: a repeat call on a row
  /// already at `false` must keep the SAME `items` instance, or it would bust
  /// `_groupedEntries`' identity memo and force a full `ListView` rebuild for
  /// no visible change (mobile-perf LOW, 2026-08-17 cycle 3). That is also what
  /// makes the two patch paths — the pop result and the signal set — genuinely
  /// idempotent rather than idempotent-by-frame-ordering.
  void markClientsReviewed(Set<String> bookingIds) {
    final AsyncValue<MasterArchiveState> snapshot = state;
    if (snapshot is! AsyncData<MasterArchiveState>) return;
    final MasterArchiveState current = snapshot.value;
    bool patchable(Booking b) =>
        b.providerCanReviewClient && bookingIds.contains(b.id);
    if (!current.items.any(patchable)) return;
    state = AsyncData<MasterArchiveState>(
      current.copyWith(
        items: <Booking>[
          for (final Booking b in current.items)
            if (patchable(b)) b.copyWith(providerCanReviewClient: false) else b,
        ],
      ),
    );
  }
}
