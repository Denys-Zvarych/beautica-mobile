// Phase 7.1 — the independent master's «Мої записи» list: paged, server-
// filtered, server-ordered.
//
// A `@riverpod` AsyncNotifier family keyed by [MasterBookingsQuery]. Changing
// any filter builds a new query → a new family member → a fresh page 0, with
// the previous member disposed once the screen stops watching it.
//
// ## The server owns the order — the client must never re-sort
//
// This is the single most important invariant here, and the reason this
// notifier exists rather than reusing the client's. `MyBookingsNotifier`'s
// ancestor once merged + re-sorted pages client-side; that is actively WRONG
// for this screen:
//
//   Page N+1 is the server's next slice of a GLOBAL ordering. Re-sorting only
//   the rows paged in SO FAR reshuffles already-viewed rows on every load-more
//   and lets a later-arriving booking land mid-list above rows the user has
//   already scrolled past. The list would look plausible and be wrong, with no
//   error anywhere.
//
// So [loadMore] appends verbatim. There is no comparator in this file, and
// adding one is a bug — `master_bookings_notifier_test.dart` pins this with a
// response deliberately NOT in `startsAt` order.
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
import '../domain/booking_sort.dart';
import '../domain/master_bookings_query.dart';
import '../domain/master_bookings_state.dart';

part 'master_bookings_notifier.g.dart';

/// Keep-alive window for the screen's LANDING query — the undated list.
///
/// This is the Phase 7.1 value and the one the TTL audit accepted. It exists
/// for the navigation-return case: tap a booking, read it, come back, and the
/// pages you had scrolled through are still there.
const Duration kMasterBookingsKeepAlive = Duration(minutes: 5);

/// Keep-alive window for a DATE-NARROWED query (`from`/`to` set).
///
/// Shorter than [kMasterBookingsKeepAlive] because these members accumulate
/// differently (perf P6). Every rail day the master settles on mints its own
/// family member holding its own page of [Booking]s, so browsing 20 days
/// retains 20 pages — the 220ms tap debounce bounds the request RATE, not the
/// retained TOTAL. The undated landing query cannot accumulate that way: there
/// is only one of it.
///
/// Two minutes rather than something aggressive: the navigation-return
/// guarantee has to hold here too — narrowing to a day and opening one of that
/// day's bookings is the single most likely path on this screen, and reading a
/// booking detail is a ~30 second act. Two minutes covers that comfortably
/// while cutting worst-case retention from a browsing session by more than
/// half. The audited 5-minute decision for the landing query is untouched.
const Duration kMasterBookingsDatedKeepAlive = Duration(minutes: 2);

/// The ordering this screen requests, fixed in code (Phase 7.8).
///
/// Sorting was retired as a user-facing feature, so [MasterBookingsQuery] no
/// longer carries a `sort` and there is nothing for the master to choose. This
/// constant is deliberately [BookingSort.newest] — the value the screen already
/// defaulted to — so the emitted URL stays byte-identical to what shipped
/// (`sort=startsAt,desc`). Dropping the param entirely would have handed
/// ordering to the server's default, which is a behaviour change this phase did
/// not ask for.
///
/// Phase 7.9 replaces [MasterBookingsQuery] with `BookingsDayQuery` and moves
/// this surface to a hard-coded `startsAt,asc`, because a timeline grid reads
/// top-down through the day. That is a deliberate two-step: this phase removes
/// the feature, 7.9 changes the ordering along with the container that makes
/// the new ordering correct.
const BookingSort _fixedSort = BookingSort.newest;

Duration _keepAliveFor(MasterBookingsQuery query) =>
    (query.from != null || query.to != null)
    ? kMasterBookingsDatedKeepAlive
    : kMasterBookingsKeepAlive;

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
    // Survive navigation, then let this member go (perf P2 — see the file
    // header for why neither plain autoDispose nor an unconditional keepAlive
    // is right). The timer is cancelled on dispose so a member that IS dropped
    // early does not leave one pending.
    final link = ref.keepAlive();
    final Timer timer = Timer(_keepAliveFor(query), link.close);
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
      sort: _fixedSort,
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
      // NO `state = const AsyncLoading()` here (perf P3), deliberately.
      //
      // That value-less loading state made `.when` swap the populated list for
      // `BookingsSkeleton` mid-gesture: a full teardown and rebuild of every
      // visible card plus a fresh layout pass, underneath a `RefreshIndicator`
      // whose entire purpose is keeping the content on screen while it spins.
      // User-visible, and the opposite of what the gesture promises.
      //
      // Leaving `state` on its current `AsyncData` until the new page resolves
      // keeps the list mounted for free. The spinner is not lost with it: a
      // `RefreshIndicator` drives its own animation from the Future this
      // method returns, not from the provider's `isLoading`.
      //
      // The alternative — `AsyncLoading().copyWithPrevious(state)` — expresses
      // "refreshing, previous value retained" more precisely and is what
      // `skipLoadingOnRefresh` is built for, but `copyWithPrevious` is marked
      // internal to `riverpod` (`invalid_use_of_internal_member`) and is not
      // ours to call. Not emitting the intermediate state at all reaches the
      // same rendered outcome through public API.
      //
      // Concurrency is unaffected: re-entry is held off by `_refreshing`
      // above, not by the provider's loading flag.
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
        sort: _fixedSort,
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
