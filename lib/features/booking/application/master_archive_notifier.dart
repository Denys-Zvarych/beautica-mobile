// Phase 231 — «Архів» page: paginated, filterable PAST-partition notifier.
//
// A `@riverpod` AsyncNotifier family keyed by [MasterArchiveQuery], mirroring
// `MyBookingsNotifier`'s pagination shape (`my_bookings_notifier.dart`) —
// `_fetchFirstPage`/`refresh`/`loadMore`, same in-flight/last-page guards.
// What is genuinely new here is REQUEST SHAPING, documented below.
//
// ## The request is ALWAYS `partition: BookingPartition.past` PLUS a legacy
// `status` set — never conditional on the filter selection
//
// This mirrors `MyBookingsNotifier._fetchFirstPage`'s Phase 227 rollout-valve
// pattern exactly: `partition` wins on a Phase-28.2-capable backend and
// `status` is IGNORED server-side whenever `partition` is present
// (`BookingService#getMyBookings`'s javadoc, beautica-backend) — `status` is
// sent purely so a backend that has not yet deployed 28.2 still degrades to
// SOME filtering instead of the master's entire unfiltered history. Backend
// `origin/dev` already carries both `BookingController:150` and
// `/me/unclosed-count`, so this is a genuine (if now mostly dormant) safety
// valve, not a TODO.
//
// ## Outcome filtering («Підтверджено»/«Виконано»/«Скасовано») is applied
// CLIENT-SIDE, on top of the fixed `partition: PAST` fetch
//
// The backend has no way to combine `partition=PAST` with a `status`
// sub-filter in one request (status is ignored the instant partition is
// non-null — see above), so narrowing "PAST, but only COMPLETED rows" is not
// expressible server-side without giving up partition's correctness (the
// elapsed-CONFIRMED-is-past computation `status` alone cannot do). Filtering
// the already-fetched PAST page in Dart instead is what makes
// [BookingStatusFilterGroup.confirmed] ("Підтверджено") work as the
// «Потребують закриття» filter with NO new UI (the amendment this phase
// shipped under, 2026-08-16): within `BookingPartition.past`, a booking is
// CONFIRMED if and only if `awaitingClosure` is `true` — `PAST`'s own
// definition is `COMPLETED ∪ NOT_COMPLETED ∪ (CONFIRMED AND elapsed)`, so
// there is no non-elapsed CONFIRMED row this partition could ever return.
// Filtering by `status == confirmed` and filtering by `awaitingClosure ==
// true` are therefore the SAME predicate here, not merely correlated.
//
// KNOWN, DELIBERATE SCOPE LIMIT: ticking «Скасовано»
// ([BookingStatusFilterGroup.cancelled], CANCELLED/DECLINED) always resolves
// to an EMPTY visible list. `BookingPartition.past` structurally never
// contains a CANCELLED/DECLINED row (that is `BookingPartition.cancelled`'s
// own, disjoint domain — see that enum's backend javadoc: "CANCELLED
// CANCELLED OR DECLINED (regardless of ends_at)"), so no client-side filter
// can ever surface one here. This is consistent with the phase's own stated
// goal ("close the visits they never marked as done or not-done" — nothing
// about cancellations), not a bug: the archive's domain is `PAST`, full
// stop. The row stays in the reused sheet (the amendment mandates verbatim
// reuse, no bespoke chip row) but is inert for this screen — a future reader
// wondering why is pointed here.
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
// list's default"). Applying it here would currently be a harmless no-op
// (`BookingPartition.past` never contains CANCELLED/DECLINED either way),
// but stating the WRONG intent in code is worse than a harmless no-op — a
// future reader copying this call site would carry the day-list's default
// into a screen that never wanted it. So this file writes its own small
// resolver instead, sharing only the part that is genuinely load-bearing
// here too: naming every status a filter UI can select must NOT be allowed
// to silently exclude [BookingStatus.notCompleted], which none of
// `BookingStatusFilterGroup`'s three rows can express (mobile-security
// LOW-1's reasoning, restated for this screen's own maximal set).

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
/// status predicate applied to an already-fetched `PAST`-partition page. An
/// EMPTY set return means "no predicate — show every fetched row verbatim".
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

/// The legacy `status` query set sent alongside `partition: PAST` — the
/// Phase 227 rollout-valve value, honoured only by a backend that does not
/// yet understand `partition`. See file header.
Set<BookingStatus> _legacyStatusesFor(Set<BookingStatus> predicate) {
  if (predicate.isNotEmpty) return predicate;
  // Best-effort legacy default — mirrors `BookingTab.past.statuses` exactly
  // (deliberately excludes CONFIRMED: a legacy, partition-blind backend
  // cannot compute "elapsed", so including it would resurrect every FUTURE
  // confirmed booking too — the same limitation that tab's own doc accepts).
  return const <BookingStatus>{
    BookingStatus.completed,
    BookingStatus.notCompleted,
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
      // the repository call args.
      partition: BookingPartition.past,
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
        partition: BookingPartition.past,
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
