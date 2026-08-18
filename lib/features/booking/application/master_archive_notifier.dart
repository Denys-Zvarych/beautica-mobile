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
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:beautica_mobile/core/network/page_response.dart';

import '../data/booking_providers.dart';
import '../data/booking_repository.dart';
import '../domain/booking.dart';
import '../domain/booking_partition.dart';
import '../domain/booking_sort.dart';
import '../domain/booking_status.dart';
import '../domain/master_archive_query.dart';

part 'master_archive_notifier.g.dart';

/// Immutable snapshot of the archive's accumulated, already-filtered
/// bookings + paging cursor. Mirrors `MyBookingsState`.
@immutable
class MasterArchiveState {
  const MasterArchiveState({
    required this.items,
    required this.page,
    required this.hasMore,
    this.isLoadingMore = false,
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

  MasterArchiveState copyWith({
    List<Booking>? items,
    int? page,
    bool? hasMore,
    bool? isLoadingMore,
  }) {
    return MasterArchiveState(
      items: items ?? this.items,
      page: page ?? this.page,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

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
  Future<MasterArchiveState> build(MasterArchiveQuery query) =>
      _fetchFirstPage(query);

  Future<MasterArchiveState> _fetchFirstPage(MasterArchiveQuery query) async {
    _generation++;
    final Set<BookingStatus> predicate = _archiveStatusPredicate(
      query.statuses.toSet(),
    );
    final BookingRepository repo = ref.read(bookingRepositoryProvider);
    final PageResponse<Booking> page = await repo.getMyBookings(
      statuses: _legacyStatusesFor(predicate),
      // ALWAYS sent, unconditionally — see file header's first section. This
      // is the hard requirement asserted on the CAPTURED request, not just
      // the repository call args. Requires a HISTORY-capable backend
      // (`81e8166`+) — see [BookingPartition.history]'s doc.
      partition: BookingPartition.history,
      serviceIds: query.serviceIds,
      sort: BookingSort.newest,
      page: 0,
    );

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

    // The pagination generation this call belongs to — see [_mergeTargetFor].
    final int generation = _generation;
    final int fromPage = current.page;
    state = AsyncData(current.copyWith(isLoadingMore: true));

    final Set<BookingStatus> predicate = _archiveStatusPredicate(
      query.statuses.toSet(),
    );
    final BookingRepository repo = ref.read(bookingRepositoryProvider);

    try {
      final PageResponse<Booking> page = await repo.getMyBookings(
        statuses: _legacyStatusesFor(predicate),
        partition: BookingPartition.history,
        serviceIds: query.serviceIds,
        sort: BookingSort.newest,
        page: fromPage + 1,
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
        ),
      );
    } catch (_) {
      // A failed load-more must not blow away the already-rendered list —
      // mirrors `MyBookingsNotifier.loadMore`'s identical catch.
      final MasterArchiveState? target = _mergeTargetFor(generation);
      if (target == null) return;
      state = AsyncData(target.copyWith(isLoadingMore: false));
    }
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
