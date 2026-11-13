// Phase 480 — BookingsWeekNotifier: one `/bookings/me?from=Mon&to=Sun` range
// read per Kyiv week, page loop with a 10-page hard stop, Kyiv-day grouping,
// identity-only auth watch.
//
// DST cases are host-zone sensitive: run this file under BOTH `TZ=UTC` and
// `TZ=Europe/Kyiv` (phase 480 Test Cases).

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/application/bookings_week_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/bookings_week_query.dart';
import 'package:beautica_mobile/features/booking/domain/bookings_week_state.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';

const User _master1 = User(
  id: 'master-1',
  email: 'master1@beautica.ua',
  role: UserRole.independentMaster,
  firstName: 'Оля',
  lastName: 'Коваль',
);

const User _master2 = User(
  id: 'master-2',
  email: 'master2@beautica.ua',
  role: UserRole.independentMaster,
  firstName: 'Ірина',
  lastName: 'Бондар',
);

class _MutableAuthNotifier extends AuthNotifier {
  _MutableAuthNotifier(this._initial);

  final AuthSession _initial;

  @override
  Future<AuthSession> build() async => _initial;

  void setSession(AuthSession session) =>
      state = AsyncData<AuthSession>(session);
}

typedef _Call = ({
  DateTime? from,
  DateTime? to,
  int page,
  int size,
  BookingSort? sort,
  bool asMaster,
  List<BookingStatus> statuses,
});

/// Serves [server] in `size`-sized pages and records every call.
class _PagedRepository implements BookingRepository {
  _PagedRepository(this.server);

  List<Booking> server;
  final List<_Call> calls = <_Call>[];

  @override
  Future<PageResponse<Booking>> getMyBookings({
    required Iterable<BookingStatus> statuses,
    required int page,
    int size = 100,
    BookingSort? sort,
    Iterable<String>? serviceIds,
    DateTime? from,
    DateTime? to,
    Object? partition,
    Object? cancelToken,
    bool asMaster = false,
  }) async {
    calls.add((
      from: from,
      to: to,
      page: page,
      size: size,
      sort: sort,
      asMaster: asMaster,
      statuses: statuses.toList(),
    ));
    final List<Booking> items = server
        .skip(page * size)
        .take(size)
        .toList(growable: false);
    return PageResponse<Booking>(
      items: items,
      page: page,
      totalPages: (server.length / size).ceil(),
      totalElements: server.length,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

/// Phase 480 (mobile-security LOW) — page 0 answers at once; page 1 is held
/// on [gate] so the test can dispose the provider mid-loop. Mirrors Dio: a
/// call made with an already-cancelled [CancelToken] never reaches the
/// network (recorded in [cancelledCalls], throws `requestCancelled`); only
/// calls on a live token count as [networkPages].
class _GatedRepository implements BookingRepository {
  final Completer<void> gate = Completer<void>();
  final List<int> networkPages = <int>[];
  final List<int> cancelledCalls = <int>[];
  final List<CancelToken?> tokens = <CancelToken?>[];

  @override
  Future<PageResponse<Booking>> getMyBookings({
    required Iterable<BookingStatus> statuses,
    required int page,
    int size = 100,
    BookingSort? sort,
    Iterable<String>? serviceIds,
    DateTime? from,
    DateTime? to,
    Object? partition,
    Object? cancelToken,
    bool asMaster = false,
  }) async {
    final CancelToken? token = cancelToken as CancelToken?;
    tokens.add(token);
    if (token?.isCancelled ?? false) {
      cancelledCalls.add(page);
      throw DioException.requestCancelled(
        requestOptions: RequestOptions(path: '/api/v1/bookings/me'),
        reason: 'cancelled',
      );
    }
    networkPages.add(page);
    if (page == 1) await gate.future;
    return PageResponse<Booking>(
      items: <Booking>[
        for (int i = 0; i < size; i++)
          // future-date-ok: pinned to the queried 2026-07-20 week, never read via isPast
          _booking('p$page-$i', DateTime.utc(2026, 7, 21, 9)),
      ],
      page: page,
      totalPages: 5,
      totalElements: 5 * size,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

/// Page 0 succeeds (partial week); page 1 fails asynchronously like a real
/// Dio call with a deterministic (non-retried) [UnauthorizedFailure].
class _FailingPage1Repository extends _PagedRepository {
  _FailingPage1Repository(super.server);

  @override
  Future<PageResponse<Booking>> getMyBookings({
    required Iterable<BookingStatus> statuses,
    required int page,
    int size = 100,
    BookingSort? sort,
    Iterable<String>? serviceIds,
    DateTime? from,
    DateTime? to,
    Object? partition,
    Object? cancelToken,
    bool asMaster = false,
  }) async {
    if (page == 1) {
      calls.add((
        from: from,
        to: to,
        page: page,
        size: size,
        sort: sort,
        asMaster: asMaster,
        statuses: statuses.toList(),
      ));
      throw const UnauthorizedFailure();
    }
    return super.getMyBookings(
      statuses: statuses,
      page: page,
      size: size,
      sort: sort,
      from: from,
      to: to,
      asMaster: asMaster,
    );
  }
}

/// Phase 480 perf fix (expected behaviour) — after page 0 is served, a new
/// booking lands AHEAD of it in `oldest` order, so the offset window of
/// page 1 shifts by one and re-serves page 0's last booking.
class _ShiftingRepository extends _PagedRepository {
  _ShiftingRepository(super.server);

  @override
  Future<PageResponse<Booking>> getMyBookings({
    required Iterable<BookingStatus> statuses,
    required int page,
    int size = 100,
    BookingSort? sort,
    Iterable<String>? serviceIds,
    DateTime? from,
    DateTime? to,
    Object? partition,
    Object? cancelToken,
    bool asMaster = false,
  }) async {
    final PageResponse<Booking> result = await super.getMyBookings(
      statuses: statuses,
      page: page,
      size: size,
      sort: sort,
      from: from,
      to: to,
      asMaster: asMaster,
    );
    if (page == 0) {
      server = <Booking>[
        // future-date-ok: pinned to the queried 2026-07-20 week, never read via isPast
        _booking('inserted', DateTime.utc(2026, 7, 20, 6)),
        ...server,
      ];
    }
    return result;
  }
}

Booking _booking(String id, DateTime startAt) => Booking(
  id: id,
  masterId: 'master-1',
  masterFirstName: 'Оля',
  masterLastName: 'Коваль',
  masterType: 'INDEPENDENT_MASTER',
  serviceId: 'service-1',
  serviceName: 'Манікюр',
  durationMinutes: 60,
  price: 500,
  startAt: startAt,
  endAt: startAt.add(const Duration(hours: 1)),
  status: BookingStatus.confirmed,
  canReview: false,
);

Future<({ProviderContainer container, _MutableAuthNotifier auth})> _container(
  BookingRepository repo, {
  AuthSession session = const AuthSession.authenticated(
    user: _master1,
    accessToken: 'token-1',
  ),
}) async {
  final _MutableAuthNotifier auth = _MutableAuthNotifier(session);
  final ProviderContainer container = ProviderContainer(
    retry: beauticaProviderRetry,
    overrides: <Object>[
      bookingRepositoryProvider.overrideWithValue(repo),
      authProvider.overrideWith(() => auth),
    ].cast(),
  );
  addTearDown(container.dispose);
  await container.read(authProvider.future);
  return (container: container, auth: auth);
}

Future<BookingsWeekState> _visit(
  ProviderContainer container,
  BookingsWeekQuery query,
) async {
  final ProviderSubscription<AsyncValue<BookingsWeekState>> sub = container
      .listen(bookingsWeekProvider(query), (_, _) {});
  final BookingsWeekState state = await container.read(
    bookingsWeekProvider(query).future,
  );
  sub.close();
  await Future<void>.delayed(Duration.zero);
  return state;
}

void main() {
  initBeauticaTimeZones();

  group('one range read, grouped by Kyiv day', () {
    test('ONE call with from=Mon, to=Sun; a 23:30-Kyiv start stays on its '
        'Kyiv day and a 00:30-Kyiv start (previous UTC day) moves to the next '
        'Kyiv day', () async {
      final _PagedRepository repo = _PagedRepository(<Booking>[
        // Wed 2026-07-22 23:30 Kyiv (UTC+3) = 20:30Z — Kyiv Wednesday.
        // future-date-ok: past grouping fixture, never read via isPast
        _booking('late-wed', DateTime.utc(2026, 7, 22, 20, 30)),
        // Thu 2026-07-23 00:30 Kyiv = Wed 21:30Z — UTC says Wednesday, Kyiv
        // says Thursday.
        // future-date-ok: past grouping fixture, never read via isPast
        _booking('early-thu', DateTime.utc(2026, 7, 22, 21, 30)),
        // Sun 2026-07-26 23:30 Kyiv — last minute of the week.
        // future-date-ok: past grouping fixture, never read via isPast
        _booking('late-sun', DateTime.utc(2026, 7, 26, 20, 30)),
      ]);
      final result = await _container(repo);

      final BookingsWeekState state = await _visit(
        result.container,
        BookingsWeekQuery.of(day: DateTime(2026, 7, 22)),
      );

      expect(repo.calls, hasLength(1));
      final _Call call = repo.calls.single;
      expect(call.from, DateTime(2026, 7, 20));
      expect(call.to, DateTime(2026, 7, 26));
      expect(call.page, 0);
      expect(call.size, 100);
      expect(call.sort, BookingSort.oldest);
      expect(call.asMaster, isFalse);

      expect(state.weekStart, DateTime(2026, 7, 20));
      expect(state.byDay.keys, <DateTime>[
        for (int d = 20; d <= 26; d++) DateTime(2026, 7, d),
      ]);
      expect(
        state.bookingsOn(DateTime(2026, 7, 22)).map((Booking b) => b.id),
        <String>['late-wed'],
      );
      expect(
        state.bookingsOn(DateTime(2026, 7, 23)).map((Booking b) => b.id),
        <String>['early-thu'],
      );
      expect(
        state.bookingsOn(DateTime(2026, 7, 26)).map((Booking b) => b.id),
        <String>['late-sun'],
      );
      expect(state.bookingsOn(DateTime(2026, 7, 20)), isEmpty);
      expect(state.isTruncated, isFalse);
    });

    test('asOwnerMaster + filters travel on the wire', () async {
      final _PagedRepository repo = _PagedRepository(const <Booking>[]);
      final result = await _container(repo);

      await _visit(
        result.container,
        BookingsWeekQuery.of(
          day: DateTime(2026, 7, 26),
          statuses: <BookingStatus>{
            BookingStatus.completed,
            BookingStatus.confirmed,
          },
          asOwnerMaster: true,
        ),
      );

      expect(repo.calls.single.asMaster, isTrue);
      expect(repo.calls.single.statuses, <BookingStatus>[
        BookingStatus.confirmed,
        BookingStatus.completed,
      ]);
    });

    test('byDay map and lists are identity-stable across reads', () async {
      final result = await _container(
        _PagedRepository(<Booking>[
          // future-date-ok: past grouping fixture, never read via isPast
          _booking('a', DateTime.utc(2026, 7, 21, 9)),
        ]),
      );
      final BookingsWeekState state = await _visit(
        result.container,
        BookingsWeekQuery.of(day: DateTime(2026, 7, 21)),
      );

      expect(identical(state.byDay, state.byDay), isTrue);
      expect(
        identical(
          state.byDay[DateTime(2026, 7, 21)],
          state.byDay[DateTime(2026, 7, 21)],
        ),
        isTrue,
      );
    });
  });

  group('page loop', () {
    List<Booking> many(int n) => <Booking>[
      // future-date-ok: past grouping fixture, never read via isPast
      for (int i = 0; i < n; i++) _booking('b$i', DateTime.utc(2026, 7, 21, 9)),
    ];

    test('150 bookings → exactly 2 pages, all collected', () async {
      final _PagedRepository repo = _PagedRepository(many(150));
      final result = await _container(repo);

      final BookingsWeekState state = await _visit(
        result.container,
        BookingsWeekQuery.of(day: DateTime(2026, 7, 21)),
      );

      expect(repo.calls.map((_Call c) => c.page), <int>[0, 1]);
      expect(state.bookingsOn(DateTime(2026, 7, 21)), hasLength(150));
      expect(state.isTruncated, isFalse);
    });

    test(
      '1 005 bookings → stops at 10 pages and reports isTruncated',
      () async {
        final _PagedRepository repo = _PagedRepository(many(1005));
        final result = await _container(repo);

        final BookingsWeekState state = await _visit(
          result.container,
          BookingsWeekQuery.of(day: DateTime(2026, 7, 21)),
        );

        expect(repo.calls, hasLength(kWeekMaxPages));
        expect(repo.calls.last.page, 9);
        expect(state.bookingsOn(DateTime(2026, 7, 21)), hasLength(1000));
        expect(state.isTruncated, isTrue);
      },
    );

    test('exactly 100 bookings → ONE page (no empty second request)', () async {
      final _PagedRepository repo = _PagedRepository(many(100));
      final result = await _container(repo);

      await _visit(
        result.container,
        BookingsWeekQuery.of(day: DateTime(2026, 7, 21)),
      );

      expect(repo.calls, hasLength(1));
    });
  });

  group('failure path', () {
    test('a page failing mid-loop → terminal AsyncError with the mapped '
        'Failure, never a partial week', () async {
      final _FailingPage1Repository repo = _FailingPage1Repository(<Booking>[
        for (int i = 0; i < 150; i++)
          // future-date-ok: pinned to the queried 2026-07-20 week, never read via isPast
          _booking('b$i', DateTime.utc(2026, 7, 21, 9)),
      ]);
      final result = await _container(repo);
      final BookingsWeekQuery query = BookingsWeekQuery.of(
        day: DateTime(2026, 7, 21),
      );
      final ProviderSubscription<AsyncValue<BookingsWeekState>> sub = result
          .container
          .listen(bookingsWeekProvider(query), (_, _) {});
      addTearDown(sub.close);

      await expectLater(
        result.container.read(bookingsWeekProvider(query).future),
        throwsA(isA<UnauthorizedFailure>()),
      );

      final AsyncValue<BookingsWeekState> state = result.container.read(
        bookingsWeekProvider(query),
      );
      expect(state, isA<AsyncError<BookingsWeekState>>());
      expect(state.error, isA<UnauthorizedFailure>());
      expect(state.hasValue, isFalse, reason: 'no partial page-0 week');
      expect(repo.calls.map((_Call c) => c.page), <int>[0, 1]);
    });
  });

  group('dispose mid page-loop (phase 480, mobile-security LOW)', () {
    test('disposing while page 1 is in flight cancels the shared CancelToken '
        'and no further page reaches the network', () async {
      final _GatedRepository repo = _GatedRepository();
      final result = await _container(repo);
      final BookingsWeekQuery query = BookingsWeekQuery.of(
        day: DateTime(2026, 7, 21),
      );
      final ProviderSubscription<AsyncValue<BookingsWeekState>> sub = result
          .container
          .listen(bookingsWeekProvider(query), (_, _) {}, onError: (_, _) {});
      // Let page 0 resolve and page 1 start (held on the gate).
      for (int i = 0; i < 5 && repo.networkPages.length < 2; i++) {
        await Future<void>.value();
      }
      expect(repo.networkPages, <int>[0, 1]);
      expect(
        identical(repo.tokens[0], repo.tokens[1]),
        isTrue,
        reason: 'one CancelToken shared by every page of the loop',
      );

      sub.close();
      result.container.dispose();

      expect(repo.tokens.first, isNotNull);
      expect(repo.tokens.first!.isCancelled, isTrue);

      // Page 1's response lands after the dispose.
      repo.gate.complete();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(
        repo.networkPages,
        <int>[0, 1],
        reason: 'pages 2..4 must never reach the network after dispose',
      );
    });
  });

  group('page-loop dedupe', () {
    test('a booking re-served on page 1 by an offset shift appears ONCE in '
        'byDay', () async {
      final _ShiftingRepository repo = _ShiftingRepository(<Booking>[
        for (int i = 0; i < 150; i++)
          // future-date-ok: pinned to the queried 2026-07-20 week, never read via isPast
          _booking('b$i', DateTime.utc(2026, 7, 21, 9)),
      ]);
      final result = await _container(repo);

      final BookingsWeekState state = await _visit(
        result.container,
        BookingsWeekQuery.of(day: DateTime(2026, 7, 21)),
      );

      expect(repo.calls.map((_Call c) => c.page), <int>[0, 1]);
      final List<String> ids = <String>[
        for (final List<Booking> day in state.byDay.values)
          for (final Booking b in day) b.id,
      ];
      expect(
        ids.where((String id) => id == 'b99'),
        hasLength(1),
        reason: 'b99 was served on page 0 AND page 1',
      );
      expect(ids.toSet(), hasLength(ids.length), reason: 'ids unique');
      expect(
        ids.toSet(),
        containsAll(<String>[for (int i = 0; i < 150; i++) 'b$i']),
      );
    });
  });

  group('DST weeks keep 7 distinct day keys (run under TZ=UTC and '
      'TZ=Europe/Kyiv)', () {
    for (final ({DateTime anyDay, DateTime monday, DateTime sunday}) week
        in <({DateTime anyDay, DateTime monday, DateTime sunday})>[
          // Spring forward — Sunday 2026-03-29.
          (
            anyDay: DateTime(2026, 3, 29),
            monday: DateTime(2026, 3, 23),
            sunday: DateTime(2026, 3, 29),
          ),
          // Fall back — Sunday 2026-10-25.
          (
            anyDay: DateTime(2026, 10, 25),
            monday: DateTime(2026, 10, 19),
            sunday: DateTime(2026, 10, 25),
          ),
          // The week right after fall-back (named in the phase doc).
          (
            anyDay: DateTime(2026, 11, 1),
            monday: DateTime(2026, 10, 26),
            sunday: DateTime(2026, 11, 1),
          ),
        ]) {
      test('week of ${week.monday}', () async {
        final _PagedRepository repo = _PagedRepository(const <Booking>[]);
        final result = await _container(repo);

        final BookingsWeekState state = await _visit(
          result.container,
          BookingsWeekQuery.of(day: week.anyDay),
        );

        expect(repo.calls.single.from, week.monday);
        expect(repo.calls.single.to, week.sunday);
        final List<DateTime> keys = state.byDay.keys.toList();
        expect(keys.toSet(), hasLength(7));
        for (final DateTime key in keys) {
          expect(key.hour, 0, reason: '$key must be a midnight date token');
        }
        expect(keys.first, week.monday);
        expect(keys.last, week.sunday);
      });
    }
  });

  group('auth — identity-only watch', () {
    test('a user-id change rebuilds the SAME query (fresh fetch)', () async {
      final _PagedRepository repo = _PagedRepository(const <Booking>[]);
      final result = await _container(repo);
      final BookingsWeekQuery query = BookingsWeekQuery.of(
        day: DateTime(2026, 7, 21),
      );

      await _visit(result.container, query);
      result.auth.setSession(
        const AuthSession.authenticated(user: _master2, accessToken: 'token-2'),
      );
      await _visit(result.container, query);

      expect(repo.calls, hasLength(2));
    });

    test('an unrelated auth change (token refresh, same user) does NOT '
        'rebuild', () async {
      final _PagedRepository repo = _PagedRepository(const <Booking>[]);
      final result = await _container(repo);
      final BookingsWeekQuery query = BookingsWeekQuery.of(
        day: DateTime(2026, 7, 21),
      );

      await _visit(result.container, query);
      result.auth.setSession(
        const AuthSession.authenticated(
          user: _master1,
          accessToken: 'token-1-refreshed',
        ),
      );
      await _visit(result.container, query);

      expect(repo.calls, hasLength(1));
    });
  });

  group('BookingsWeekQuery.of normalisation', () {
    test('any day / time of one week keys ONE family member', () {
      expect(
        BookingsWeekQuery.of(day: DateTime(2026, 7, 20)),
        BookingsWeekQuery.of(day: DateTime(2026, 7, 26, 18, 45)),
      );
    });

    test('status order collapses to one key', () {
      expect(
        BookingsWeekQuery.of(
          day: DateTime(2026, 7, 21),
          statuses: <BookingStatus>{
            BookingStatus.completed,
            BookingStatus.confirmed,
          },
        ),
        BookingsWeekQuery.of(
          day: DateTime(2026, 7, 21),
          statuses: <BookingStatus>{
            BookingStatus.confirmed,
            BookingStatus.completed,
          },
        ),
      );
    });

    test('covers is true for exactly Mon..Sun', () {
      final BookingsWeekQuery q = BookingsWeekQuery.of(
        day: DateTime(2026, 7, 22),
      );
      expect(q.covers(DateTime(2026, 7, 19)), isFalse);
      expect(q.covers(DateTime(2026, 7, 20)), isTrue);
      expect(q.covers(DateTime(2026, 7, 26)), isTrue);
      expect(q.covers(DateTime(2026, 7, 27)), isFalse);
    });
  });
}
