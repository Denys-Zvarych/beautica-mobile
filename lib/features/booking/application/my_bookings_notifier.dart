// Phase 14.3 — «МОЇ ЗАПИСИ» per-tab notifier (network + pagination).
//
// A `@riverpod` AsyncNotifier family keyed by [BookingTab]. `GET /bookings/me`
// now accepts a REPEATABLE `status` param (backend Phase 26.1 — unioned via
// `EnumSet` and paginated server-side) and an honoured `sort` param (backend
// Phase 26.3), so each tab issues exactly ONE paginated request carrying its
// whole [BookingTabX.statuses] set — no client-side fan-out, merge, or
// re-sort. This replaces an earlier per-status fan-out (one paginated fetch
// PER status, merged + re-sorted client-side) that was unsound: merging two
// independently-paginated streams is only correct as a prefix, so a tab with
// >20 items in more than one status could show a booking landing mid-list on
// a later page and reshuffle already-viewed rows on load-more. The server
// now returns a single correctly-ordered, correctly-paginated stream, so the
// client only has to page through it.
//
// Sort order: Майбутні reads soonest-first (`ascending: true` — "what's
// next"); Минулі/Скасовані read most-recent-first (`ascending: false` —
// "what just happened"), matching `BookingSampleData.forTab` in the approved
// preview. Threaded straight into [BookingRepository.getMyBookings]'s
// `ascending` param, which renders it as `sort=startsAt,<asc|desc>`.
//
// Pagination: [loadMore] advances the tab's single page cursor, guards
// against a double-fetch (an in-flight [loadMore] is a no-op), and is a
// no-op once the stream is exhausted. A failed load-more does not blow away
// the already-rendered list — see `search_results_notifier.dart`'s identical
// `catch` comment.

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:beautica_mobile/core/network/page_response.dart';

import '../data/booking_providers.dart';
import '../data/booking_repository.dart';
import '../domain/booking.dart';
import '../domain/booking_tab.dart';

part 'my_bookings_notifier.g.dart';

/// Immutable snapshot of one [BookingTab]'s accumulated bookings + paging
/// cursor.
@immutable
class MyBookingsState {
  const MyBookingsState({
    required this.items,
    required this.page,
    required this.hasMore,
    this.isLoadingMore = false,
  });

  /// The bookings accumulated so far, server-ordered — what the screen
  /// renders directly, with no client-side re-sort.
  final List<Booking> items;

  /// Zero-based index of the last fetched page.
  final int page;

  /// Whether a subsequent page exists.
  final bool hasMore;

  /// Whether a [MyBookingsNotifier.loadMore] fetch is currently in flight.
  final bool isLoadingMore;

  MyBookingsState copyWith({
    List<Booking>? items,
    int? page,
    bool? hasMore,
    bool? isLoadingMore,
  }) {
    return MyBookingsState(
      items: items ?? this.items,
      page: page ?? this.page,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

/// Paged bookings for one [BookingTab].
///
/// autoDispose (the default for a `@riverpod class`) — each tab's cache drops
/// when nothing watches it (e.g. the My Bookings screen is popped), so
/// re-opening it always starts from a fresh page 0.
@riverpod
class MyBookingsNotifier extends _$MyBookingsNotifier {
  @override
  Future<MyBookingsState> build(BookingTab tab) => _fetchFirstPage(tab);

  /// Fetches page 0 of [tab]'s whole status set in ONE request — the server
  /// unions + globally paginates + sorts, so the response is used as-is.
  Future<MyBookingsState> _fetchFirstPage(BookingTab tab) async {
    final BookingRepository repo = ref.read(bookingRepositoryProvider);
    final PageResponse<Booking> page = await repo.getMyBookings(
      statuses: tab.statuses,
      ascending: tab == BookingTab.upcoming,
      page: 0,
    );

    return MyBookingsState(
      items: page.items,
      page: page.page,
      hasMore: page.hasMore,
    );
  }

  /// Re-fetches page 0 — the pull-to-refresh entry point.
  Future<void> refresh() async {
    state = const AsyncLoading<MyBookingsState>();
    state = await AsyncValue.guard(() => _fetchFirstPage(tab));
  }

  /// Appends the next page.
  ///
  /// No-op when: the notifier has no data yet (still loading / errored), a
  /// load-more is already in flight, or the stream is exhausted.
  Future<void> loadMore() async {
    final MyBookingsState? current = state.value;
    if (current == null) return;
    if (current.isLoadingMore) return; // double-fetch guard
    if (!current.hasMore) return; // last page no-op

    // Flag the in-flight load WITHOUT flipping the whole provider to
    // AsyncLoading — the current list stays on screen, the screen shows a
    // bottom spinner off [isLoadingMore].
    state = AsyncData(current.copyWith(isLoadingMore: true));

    final BookingRepository repo = ref.read(bookingRepositoryProvider);

    try {
      final PageResponse<Booking> page = await repo.getMyBookings(
        statuses: tab.statuses,
        ascending: tab == BookingTab.upcoming,
        page: current.page + 1,
      );

      state = AsyncData(
        current.copyWith(
          items: <Booking>[...current.items, ...page.items],
          page: page.page,
          hasMore: page.hasMore,
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
