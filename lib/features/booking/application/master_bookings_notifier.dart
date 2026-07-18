// Phase 7.1 — the independent master's «Мої записи» list: paged, server-
// filtered, server-sorted.
//
// A `@riverpod` AsyncNotifier family keyed by [MasterBookingsQuery]. Changing
// any filter or the sort builds a new query → a new family member → a fresh
// page 0, with the previous member disposed once the screen stops watching it.
//
// ## The server owns the order — the client must never re-sort
//
// This is the single most important invariant here, and the reason this
// notifier exists rather than reusing the client's. `MyBookingsNotifier`'s
// ancestor once merged + re-sorted pages client-side; that is actively WRONG
// for this screen, twice over:
//
//   1. It silently defeats the sort the user picked. A client-side
//      `items.sort((a,b) => b.startAt.compareTo(a.startAt))` would quietly
//      undo «Дорожчі спершу» — the list would look plausible and be wrong,
//      with no error anywhere.
//   2. It breaks pagination even for the sort it implements. Page N+1 is the
//      server's next slice of a GLOBAL ordering; re-sorting only the rows
//      paged in SO FAR reshuffles already-viewed rows on every load-more and
//      lets a later-arriving booking land mid-list above rows the user has
//      already scrolled past.
//
// So [loadMore] appends verbatim. There is no comparator in this file, and
// adding one is a bug — `master_bookings_notifier_test.dart` pins this with a
// `priceDesc` response whose order is deliberately NOT the `startsAt` order.
//
// ## autoDispose + a bounded TTL — not `keepAlive: true`
//
// An unconditional `keepAlive` is wrong here: a filter sheet can mint many
// short-lived query objects, and caching a page per filter combination the
// user ever tried grows the family without bound.
//
// But plain autoDispose was wrong in the other direction (perf P2). Filter
// churn is not the only thing that stops watching this provider — NAVIGATION
// is. Scrolling to page 4 (five requests) and tapping a booking disposes the
// member; coming back re-fetches page 0 and throws away four pages plus the
// scroll position, for a round trip the user experiences as "the list forgot
// where I was".
//
// So: autoDispose with a 5-minute `keepAlive` link (see [build]). The family
// is bounded by what the user actually touched in the last five minutes rather
// than by the session, which keeps navigation cheap without letting abandoned
// filter permutations accumulate.

import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:beautica_mobile/core/network/page_response.dart';

import '../data/booking_providers.dart';
import '../data/booking_repository.dart';
import '../domain/booking.dart';
import '../domain/master_bookings_query.dart';
import '../domain/master_bookings_state.dart';

part 'master_bookings_notifier.g.dart';

/// Paged bookings for one [MasterBookingsQuery].
///
/// Generated provider name: `masterBookingsProvider` (a family — call
/// `masterBookingsProvider(query)`).
@riverpod
class MasterBookingsNotifier extends _$MasterBookingsNotifier {
  /// In-flight guard for [refresh] (perf P1) — mirrors `ServicesList.refresh`.
  bool _refreshing = false;

  @override
  Future<MasterBookingsState> build(MasterBookingsQuery query) async {
    // Survive navigation for 5 minutes, then let this member go (perf P2 —
    // see the file header for why neither plain autoDispose nor an
    // unconditional keepAlive is right). The timer is cancelled on dispose so
    // a member that IS dropped early does not leave one pending.
    final link = ref.keepAlive();
    final Timer timer = Timer(const Duration(minutes: 5), link.close);
    ref.onDispose(timer.cancel);

    // `async` + `await` is deliberate, not a redundant wrapper around a
    // passthrough return. It guarantees that a SYNCHRONOUS throw from the
    // repository call is captured as a rejected Future instead of escaping
    // `build()` itself — an escaped sync throw leaves the provider stuck in
    // its loading state and surfaces as a StateError on disposal rather than
    // as the repository's own typed Failure. Same reasoning as
    // `WorkingDaysNotifier.build`.
    return await _fetchFirstPage(query);
  }

  /// Fetches page 0 for [query]'s whole filter set in ONE request — the
  /// server filters, sorts and paginates, so the response is used as-is.
  Future<MasterBookingsState> _fetchFirstPage(MasterBookingsQuery query) async {
    final BookingRepository repo = ref.read(bookingRepositoryProvider);
    final PageResponse<Booking> page = await repo.getMyBookings(
      statuses: query.statuses,
      serviceIds: query.serviceIds,
      from: query.from,
      to: query.to,
      sort: query.sort,
      page: 0,
    );

    return MasterBookingsState(
      items: page.items,
      page: page.page,
      hasMore: page.hasMore,
      totalElements: page.totalElements,
    );
  }

  /// Re-fetches page 0 — the pull-to-refresh entry point.
  ///
  /// Coalesces concurrent calls (perf P1). Without this guard three rapid
  /// pull-to-refresh gestures fired three concurrent `GET /bookings/me?page=0`
  /// requests and the LAST to RESOLVE won — which is not the last to be sent,
  /// so a stale response could overwrite a fresher one. [loadMore] has always
  /// had the equivalent guard via `isLoadingMore`.
  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      state = const AsyncLoading<MasterBookingsState>();
      state = await AsyncValue.guard(() => _fetchFirstPage(query));
    } finally {
      _refreshing = false;
    }
  }

  /// Appends the next page, **preserving server order** (see the file header).
  ///
  /// No-op when: the notifier has no data yet (still loading / errored), a
  /// load-more is already in flight, or the stream is exhausted.
  Future<void> loadMore() async {
    final MasterBookingsState? current = state.value;
    if (current == null) return;
    if (current.isLoadingMore) return; // double-fetch guard
    if (!current.hasMore) return; // last page no-op

    // Flag the in-flight load WITHOUT flipping the provider to AsyncLoading —
    // the current list stays on screen behind a footer spinner.
    state = AsyncData(current.copyWith(isLoadingMore: true));

    final BookingRepository repo = ref.read(bookingRepositoryProvider);

    try {
      final PageResponse<Booking> page = await repo.getMyBookings(
        statuses: query.statuses,
        serviceIds: query.serviceIds,
        from: query.from,
        to: query.to,
        sort: query.sort,
        page: current.page + 1,
      );

      state = AsyncData(
        current.copyWith(
          // Straight concatenation — NO re-sort. See the file header.
          items: <Booking>[...current.items, ...page.items],
          page: page.page,
          hasMore: page.hasMore,
          totalElements: page.totalElements,
          isLoadingMore: false,
        ),
      );
    } catch (_) {
      // A failed load-more must not blow away the already-rendered list (that
      // is the first-page error state's job) — clear the spinner and keep the
      // current page so the user can scroll to retry.
      state = AsyncData(current.copyWith(isLoadingMore: false));
    }
  }
}
