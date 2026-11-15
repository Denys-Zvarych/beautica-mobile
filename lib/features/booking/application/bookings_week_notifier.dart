// Phase 480 — BookingsWeekNotifier: ONE range read for a Mon–Sun Kyiv week of
// the master's own bookings (`GET /api/v1/bookings/me?from=Mon&to=Sun`).
//
// ## One range read + page loop (D1)
//
// The week view needs 7 days at once. Seven parallel `bookingsDayProvider`
// reads would be 7 requests (14 with the schedule); `/bookings/me` already
// takes a `from`/`to` range (span ≤ 366 days, page ≤ 100), so the week is one
// request for a normal week. A busy week (> 100 bookings) is paged — page 0,
// 1, … — until every booking the server reported is collected, with a HARD
// STOP at [kWeekMaxPages] pages. Hitting the stop surfaces
// [BookingsWeekState.isTruncated], the same flag and meaning as
// `BookingsDayState.isTruncated`, rather than looping without bound.
//
// The schedule half (D2) needs no new notifier: the week view reads the
// existing `effectiveScheduleProvider(scope, ScheduleRange(mon, sun))`.
//
// ## Auth, keepAlive, cancellation — the day notifier's seams, reused
//
//   * Auth: the SAME `authProvider.select(user.id)` watch
//     `BookingsDayNotifier.build` uses (never a bare `authProvider` watch,
//     which would rebuild on every unrelated auth-state change).
//   * keepAlive: [weekKeepAliveLruProvider] — the generic [KeepAliveLru]
//     the day notifier's `DayKeepAliveLru` was promoted to — pins the last
//     [_kMaxKeptWeeks] (prev / current / next week). `AuthNotifier.logout`
//     clears it alongside the day LRU.
//   * Cancellation: one [CancelToken] per build, cancelled on dispose, shared
//     by every page of the loop.
//
// ## Day walking
//
// Days are stepped with `kyivAddDays` only — never a `Duration` — so a DST
// week (last Sunday of March / October) still yields 7 distinct day keys.

import 'dart:developer';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart'
    show EqualUnmodifiableListView, EqualUnmodifiableMapView;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';

import '../../auth/domain/auth_session.dart';
import '../../auth/domain/user.dart';
import '../../auth/presentation/auth_notifier.dart';
import '../data/booking_providers.dart';
import '../data/booking_repository.dart';
import '../domain/booking.dart';
import '../domain/booking_sort.dart';
import '../domain/bookings_week_query.dart';
import '../domain/bookings_week_state.dart';
import 'keep_alive_lru.dart';

part 'bookings_week_notifier.g.dart';

const String _tag = 'feature.booking.bookings_week';

/// Page size of each range read — the backend's own
/// `spring.data.web.pageable.max-page-size`, same as the day notifier.
const int kWeekPageSize = 100;

/// Hard stop on the page loop: at most this many pages (1 000 bookings) per
/// week. Reaching it with bookings still unread sets
/// [BookingsWeekState.isTruncated].
const int kWeekMaxPages = 10;

/// Distinct week queries pinned at once — previous / current / next week.
const int _kMaxKeptWeeks = 3;

/// Container-scoped LRU pinning the last [_kMaxKeptWeeks] week queries. Same
/// class, same bookkeeping as `dayKeepAliveLruProvider` (see
/// [KeepAliveLru]); public so `AuthNotifier.logout` and
/// `booking_calendar_invalidation.dart` can reach it.
@Riverpod(keepAlive: true)
KeepAliveLru<BookingsWeekQuery> weekKeepAliveLru(Ref ref) =>
    KeepAliveLru<BookingsWeekQuery>(capacity: _kMaxKeptWeeks);

/// One Kyiv week's bookings for one [BookingsWeekQuery], grouped by day.
///
/// Generated provider name: `bookingsWeekProvider` (a family — call
/// `bookingsWeekProvider(query)`).
@riverpod
class BookingsWeekNotifier extends _$BookingsWeekNotifier {
  @override
  Future<BookingsWeekState> build(BookingsWeekQuery query) async {
    // Identity-only auth watch — byte-for-byte the day notifier's selector.
    ref.watch(
      authProvider.select(
        (AsyncValue<AuthSession> session) => switch (session.value) {
          Authenticated(:final User user) => user.id,
          Unauthenticated() || null => null,
        },
      ),
    );

    final KeepAliveLru<BookingsWeekQuery> lru = ref.read(
      weekKeepAliveLruProvider,
    );
    lru.touch(query, ref.keepAlive());
    ref.onAddListener(() => lru.markWatched(query));
    ref.onRemoveListener(() => lru.markUnwatched(query));

    final CancelToken cancelToken = CancelToken();
    ref.onDispose(() => cancelToken.cancel());

    return _fetchWeek(query, cancelToken);
  }

  Future<BookingsWeekState> _fetchWeek(
    BookingsWeekQuery query,
    CancelToken cancelToken,
  ) async {
    final BookingRepository repo = ref.read(bookingRepositoryProvider);
    // Keyed by booking id, KEEP-FIRST: an offset shift between pages (a
    // booking inserted or cancelled mid-loop) can re-serve a row already read
    // on an earlier page; the first copy wins and the duplicate is dropped so
    // `byDay` never shows one booking twice. `LinkedHashMap` (the `{}`
    // default) keeps server order. Loop termination and [isTruncated] still
    // count RAW rows read (`rowsRead`) — the page arithmetic the server's
    // `totalElements` describes — so a duplicate cannot push the loop onto an
    // extra page.
    final Map<String, Booking> collected = <String, Booking>{};
    int rowsRead = 0;
    int totalElements = 0;
    int pagesRead = 0;
    while (pagesRead < kWeekMaxPages) {
      final PageResponse<Booking> page = await repo.getMyBookings(
        statuses: query.statuses,
        serviceIds: query.serviceIds,
        from: query.weekStart,
        to: query.weekEnd,
        sort: BookingSort.oldest,
        page: pagesRead,
        size: kWeekPageSize,
        cancelToken: cancelToken,
        asMaster: query.asOwnerMaster,
      );
      pagesRead++;
      totalElements = page.totalElements;
      rowsRead += page.items.length;
      for (final Booking booking in page.items) {
        collected.putIfAbsent(booking.id, () => booking);
      }
      // An empty page ends the loop too: a server whose `totalElements`
      // over-reports must not spin us through all ten pages.
      if (rowsRead >= totalElements || page.items.isEmpty) break;
    }

    final bool isTruncated = rowsRead < totalElements;
    if (isTruncated && kDebugMode) {
      log(
        'Week ${query.weekStart} reports $totalElements bookings but only '
        '$rowsRead were read in $pagesRead pages — surfacing '
        'isTruncated (hard stop $kWeekMaxPages pages).',
        name: _tag,
        level: 900,
      );
    }

    return BookingsWeekState(
      weekStart: query.weekStart,
      byDay: groupWeekByKyivDay(
        query.weekStart,
        collected.values.toList(growable: false),
      ),
      isTruncated: isTruncated,
    );
  }
}

/// Groups [bookings] (server order) into the seven Kyiv day tokens of the
/// week starting [weekStart]. Every day is present (empty list when free); a
/// booking whose Kyiv day falls outside the week is dropped. Map and lists
/// are `EqualUnmodifiable*View`s — identity-stable through freezed's getters.
@visibleForTesting
Map<DateTime, List<Booking>> groupWeekByKyivDay(
  DateTime weekStart,
  List<Booking> bookings,
) {
  final Map<DateTime, List<Booking>> buckets = <DateTime, List<Booking>>{
    for (int i = 0; i < 7; i++) kyivAddDays(weekStart, i): <Booking>[],
  };
  for (final Booking booking in bookings) {
    final List<Booking>? bucket = buckets[kyivDayOf(booking.startAt)];
    if (bucket == null) {
      if (kDebugMode) {
        log(
          'Booking ${booking.id} starts outside week $weekStart — dropped.',
          name: _tag,
          level: 900,
        );
      }
      continue;
    }
    bucket.add(booking);
  }
  return EqualUnmodifiableMapView<DateTime, List<Booking>>(
    <DateTime, List<Booking>>{
      for (final MapEntry<DateTime, List<Booking>> e in buckets.entries)
        e.key: EqualUnmodifiableListView<Booking>(e.value),
    },
  );
}
