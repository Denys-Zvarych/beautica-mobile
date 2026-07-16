// Phase 14.3 — «МОЇ ЗАПИСИ» per-tab notifier (network + pagination).
//
// A `@riverpod` AsyncNotifier family keyed by [BookingTab]. Mirrors
// `discovery/application/search_results_notifier.dart`'s merge-two-paginated-
// -endpoints idiom, generalised to N statuses: `GET /bookings/me` only
// accepts a SINGLE `status` filter (see `BookingController.listMyBookings`),
// but Минулі (COMPLETED + NOT_COMPLETED) and Скасовані (CANCELLED +
// DECLINED) are each TWO statuses sharing one tab. So each tab fans out one
// independently-paginated fetch per status in [BookingTabX.statuses], keeps a
// running per-status page cursor + hasMore flag, and re-merges + re-sorts the
// accumulated set on every fetch.
//
// Sort order: Майбутні reads soonest-first (ascending `startAt` — "what's
// next"); Минулі/Скасовані read most-recent-first (descending — "what just
// happened"), matching `BookingSampleData.forTab` in the approved preview.
//
// Pagination: [loadMore] advances only the statuses that still have a page,
// guards against a double-fetch (an in-flight [loadMore] is a no-op), and is
// a no-op once every status is exhausted. A failed load-more does not blow
// away the already-rendered list — see `search_results_notifier.dart`'s
// identical `catch` comment.

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:beautica_mobile/core/network/page_response.dart';

import '../data/booking_providers.dart';
import '../data/booking_repository.dart';
import '../domain/booking.dart';
import '../domain/booking_status.dart';
import '../domain/booking_tab.dart';

part 'my_bookings_notifier.g.dart';

/// Immutable snapshot of the merged bookings list + per-status paging
/// cursors for one [BookingTab].
@immutable
class MyBookingsState {
  const MyBookingsState({
    required this.items,
    required this.byStatus,
    required this.pages,
    required this.hasMoreByStatus,
    this.isLoadingMore = false,
  });

  /// The merged, sorted bookings accumulated so far — what the screen renders.
  final List<Booking> items;

  /// Accumulated raw pages per status, kept separately so [items] can be
  /// re-merged/re-sorted without re-fetching every status on each loadMore.
  final Map<BookingStatus, List<Booking>> byStatus;

  /// Zero-based index of the last fetched page, per status.
  final Map<BookingStatus, int> pages;

  /// Whether a status still has another page beyond [pages]`[status]`.
  final Map<BookingStatus, bool> hasMoreByStatus;

  /// Whether a [MyBookingsNotifier.loadMore] fetch is currently in flight.
  final bool isLoadingMore;

  /// Whether ANY status backing this tab still has a page to fetch.
  bool get hasMore => hasMoreByStatus.values.any((bool v) => v);

  MyBookingsState copyWith({
    List<Booking>? items,
    Map<BookingStatus, List<Booking>>? byStatus,
    Map<BookingStatus, int>? pages,
    Map<BookingStatus, bool>? hasMoreByStatus,
    bool? isLoadingMore,
  }) {
    return MyBookingsState(
      items: items ?? this.items,
      byStatus: byStatus ?? this.byStatus,
      pages: pages ?? this.pages,
      hasMoreByStatus: hasMoreByStatus ?? this.hasMoreByStatus,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

/// Paged, merged bookings for one [BookingTab].
///
/// autoDispose (the default for a `@riverpod class`) — each tab's cache drops
/// when nothing watches it (e.g. the My Bookings screen is popped), so
/// re-opening it always starts from a fresh page 0.
@riverpod
class MyBookingsNotifier extends _$MyBookingsNotifier {
  @override
  Future<MyBookingsState> build(BookingTab tab) => _fetchFirstPage(tab);

  /// Fetches page 0 of every status in [tab]'s partition, in parallel, and
  /// merges them.
  Future<MyBookingsState> _fetchFirstPage(BookingTab tab) async {
    final BookingRepository repo = ref.read(bookingRepositoryProvider);
    final List<BookingStatus> statuses = tab.statuses.toList(growable: false);
    final List<PageResponse<Booking>> results = await Future.wait(
      statuses.map((BookingStatus s) => repo.getMyBookings(status: s, page: 0)),
    );

    final Map<BookingStatus, List<Booking>> byStatus =
        <BookingStatus, List<Booking>>{};
    final Map<BookingStatus, int> pages = <BookingStatus, int>{};
    final Map<BookingStatus, bool> hasMore = <BookingStatus, bool>{};
    for (int i = 0; i < statuses.length; i++) {
      final BookingStatus status = statuses[i];
      final PageResponse<Booking> page = results[i];
      byStatus[status] = page.items;
      pages[status] = page.page;
      hasMore[status] = page.hasMore;
    }

    return MyBookingsState(
      items: _merge(tab, byStatus),
      byStatus: byStatus,
      pages: pages,
      hasMoreByStatus: hasMore,
    );
  }

  /// Re-fetches page 0 of every status — the pull-to-refresh entry point.
  Future<void> refresh() async {
    state = const AsyncLoading<MyBookingsState>();
    state = await AsyncValue.guard(() => _fetchFirstPage(tab));
  }

  /// Appends the next page from whichever status(es) still have one.
  ///
  /// No-op when: the notifier has no data yet (still loading / errored), a
  /// load-more is already in flight, or every status is exhausted.
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
    final List<BookingStatus> toFetch = current.hasMoreByStatus.entries
        .where((MapEntry<BookingStatus, bool> e) => e.value)
        .map((MapEntry<BookingStatus, bool> e) => e.key)
        .toList(growable: false);

    try {
      final List<PageResponse<Booking>> results = await Future.wait(
        toFetch.map(
          (BookingStatus s) =>
              repo.getMyBookings(status: s, page: current.pages[s]! + 1),
        ),
      );

      final Map<BookingStatus, List<Booking>> byStatus =
          Map<BookingStatus, List<Booking>>.of(current.byStatus);
      final Map<BookingStatus, int> pages = Map<BookingStatus, int>.of(
        current.pages,
      );
      final Map<BookingStatus, bool> hasMore = Map<BookingStatus, bool>.of(
        current.hasMoreByStatus,
      );
      for (int i = 0; i < toFetch.length; i++) {
        final BookingStatus status = toFetch[i];
        final PageResponse<Booking> page = results[i];
        byStatus[status] = <Booking>[...?byStatus[status], ...page.items];
        pages[status] = page.page;
        hasMore[status] = page.hasMore;
      }

      state = AsyncData(
        current.copyWith(
          items: _merge(tab, byStatus),
          byStatus: byStatus,
          pages: pages,
          hasMoreByStatus: hasMore,
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

  /// Flattens every status's accumulated bookings into one sorted list.
  /// Майбутні reads soonest-first; Минулі/Скасовані read most-recent-first.
  List<Booking> _merge(
    BookingTab tab,
    Map<BookingStatus, List<Booking>> byStatus,
  ) {
    final List<Booking> all = <Booking>[
      for (final List<Booking> list in byStatus.values) ...list,
    ];
    all.sort(
      (Booking a, Booking b) => tab == BookingTab.upcoming
          ? a.startAt.compareTo(b.startAt)
          : b.startAt.compareTo(a.startAt),
    );
    return all;
  }
}
