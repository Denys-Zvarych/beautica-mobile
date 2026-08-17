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

  @override
  Future<MasterArchiveState> build(MasterArchiveQuery query) =>
      _fetchFirstPage(query);

  Future<MasterArchiveState> _fetchFirstPage(MasterArchiveQuery query) async {
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
  Future<void> loadMore() async {
    final MasterArchiveState? current = state.value;
    if (current == null) return;
    if (current.isLoadingMore) return; // double-fetch guard
    if (!current.hasMore) return; // last raw page no-op

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
        page: current.page + 1,
      );

      state = AsyncData(
        current.copyWith(
          items: <Booking>[
            ...current.items,
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
      state = AsyncData(current.copyWith(isLoadingMore: false));
    }
  }
}
