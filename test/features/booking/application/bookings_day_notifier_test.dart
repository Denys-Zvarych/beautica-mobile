// Phase 7.9 — bookingsDayProvider: the day-scoped, single-fetch replacement
// for the retired paged `masterBookingsProvider`.
//
// The headline tests here are:
//   1. ONE request per query — no multi-page loop, ever (locked decision,
//      2026-07-18).
//   2. SERVER ORDER IS PRESERVED — a response is fed back in an order that is
//      deliberately NOT `startsAt` order, so any client-side re-sort creeping
//      into the notifier shows up as a failure rather than as a
//      plausible-looking wrong list. Ascending order is load-bearing for
//      Phase 7.10's lane assignment.
//   3. The FAMILY-LEAK guards on `BookingsDayQuery`: structural equality,
//      `day` truncation, and filter-order independence, each observed at the
//      network layer (one fetch, not two) rather than merely at the freezed
//      `==` layer.

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/application/bookings_day_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/bookings_day_query.dart';
import 'package:beautica_mobile/features/booking/domain/bookings_day_state.dart';

class _MockBookingRepository extends Mock implements BookingRepository {}

// ---------------------------------------------------------------------------
// Auth stub (mirrors favorite_toggle_notifier_test.dart /
// pending_service_preselection_provider_test.dart's `_MutableAuthNotifier`) —
// lets the session-boundary-PII tests below flip the settled session AFTER
// build(), so `BookingsDayNotifier.build`'s `authProvider.select(...)` watch
// re-runs deterministically instead of depending on the real `AuthNotifier`
// (which needs a live SecureStorage/AuthRepository and always cold-starts to
// Unauthenticated in a test binding).
// ---------------------------------------------------------------------------

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

  /// Flips the settled session — simulates a logout (→ `unauthenticated`), a
  /// different account logging in (→ a different user id), or a silent token
  /// refresh (→ same user, new `accessToken`), exactly like
  /// `AuthNotifier.setAccessToken`/`logout` do in production.
  void setSession(AuthSession session) =>
      state = AsyncData<AuthSession>(session);
}

/// Builds a container with the auth graph stubbed, with [authProvider]
/// already SETTLED to `AsyncData` before returning.
///
/// Settling first is load-bearing (mirrors
/// `favorite_toggle_notifier_test.dart`'s `_makeContainer`): `build()` now
/// `ref.watch`es `authProvider.select(...)`, so reading `bookingsDayProvider`
/// while `authProvider` is still `AsyncLoading` would observe a `null`
/// selected id, then rebuild a SECOND time the instant `_initial` resolves —
/// an extra, logout-unrelated fetch that has nothing to do with what these
/// tests are asserting.
Future<({ProviderContainer container, _MutableAuthNotifier auth})>
_containerWithAuth(BookingRepository repo, AuthSession initialAuth) async {
  final auth = _MutableAuthNotifier(initialAuth);
  final container = ProviderContainer(
    overrides: <Object>[
      bookingRepositoryProvider.overrideWithValue(repo),
      authProvider.overrideWith(() => auth),
    ].cast(),
  );
  addTearDown(container.dispose);
  await container.read(authProvider.future);
  return (container: container, auth: auth);
}

Booking _booking({
  required String id,
  required double price,
  required DateTime startAt,
}) => Booking(
  id: id,
  masterId: 'master-1',
  masterFirstName: 'Оля',
  masterLastName: 'Коваль',
  masterType: 'INDEPENDENT_MASTER',
  serviceId: 'service-1',
  serviceName: 'Манікюр',
  durationMinutes: 60,
  price: price,
  startAt: startAt,
  endAt: startAt.add(const Duration(hours: 1)),
  status: BookingStatus.confirmed,
  canReview: false,
);

PageResponse<Booking> _page(
  List<Booking> items, {
  int page = 0,
  int totalPages = 1,
  int? totalElements,
}) => PageResponse<Booking>(
  items: items,
  page: page,
  totalPages: totalPages,
  totalElements: totalElements ?? items.length,
);

ProviderContainer _containerWith(BookingRepository repo) {
  final container = ProviderContainer(
    overrides: [bookingRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  setUpAll(() {
    registerFallbackValue(<BookingStatus>{});
    registerFallbackValue(BookingSort.oldest);
  });

  late _MockBookingRepository repo;

  setUp(() {
    repo = _MockBookingRepository();
  });

  void stubBookings(PageResponse<Booking> response) {
    when(
      () => repo.getMyBookings(
        statuses: any(named: 'statuses'),
        serviceIds: any(named: 'serviceIds'),
        from: any(named: 'from'),
        to: any(named: 'to'),
        sort: any(named: 'sort'),
        page: any(named: 'page'),
        size: any(named: 'size'),
      ),
    ).thenAnswer((_) async => response);
  }

  group('bookingsDayProvider — one request, exact shape', () {
    test('from == to == day, size == 100, page == 0, sort == startsAt,asc — '
        'plus every filter from the query', () async {
      stubBookings(_page(const <Booking>[]));

      final query = BookingsDayQuery.of(
        day: DateTime(2026, 7, 20),
        statuses: <BookingStatus>{
          BookingStatus.confirmed,
          BookingStatus.completed,
        },
        serviceIds: <String>{'svc-a', 'svc-b'},
      );

      await _containerWith(repo).read(bookingsDayProvider(query).future);

      verify(
        () => repo.getMyBookings(
          statuses: <BookingStatus>[
            BookingStatus.confirmed,
            BookingStatus.completed,
          ],
          serviceIds: <String>['svc-a', 'svc-b'],
          from: DateTime(2026, 7, 20),
          to: DateTime(2026, 7, 20),
          sort: BookingSort.oldest,
          page: 0,
          size: 100,
        ),
      ).called(1);
    });

    test('a day carrying a time component reaches the repository ALREADY '
        'truncated to date-only — the day is not shifted', () async {
      stubBookings(_page(const <Booking>[]));

      // A near-midnight instant, exactly the shape a rail tap / date picker
      // hands back — the day-shift regression this class exists to
      // prevent. `toApiDate`'s own `yyyy-MM-dd` formatting is pinned
      // separately, at the repository layer
      // (`booking_repository_master_query_test.dart`), which this test
      // does not duplicate — it pins that the DATETIME reaching the
      // repository has already lost its time component.
      final query = BookingsDayQuery.of(day: DateTime(2026, 7, 18, 23, 59, 59));

      await _containerWith(repo).read(bookingsDayProvider(query).future);

      final captured = verify(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          serviceIds: any(named: 'serviceIds'),
          from: captureAny(named: 'from'),
          to: captureAny(named: 'to'),
          sort: any(named: 'sort'),
          page: any(named: 'page'),
          size: any(named: 'size'),
        ),
      ).captured;

      expect(captured, <DateTime>[
        DateTime(2026, 7, 18),
        DateTime(2026, 7, 18),
      ]);
    });

    test('exposes the server\'s totalElements, not items.length', () async {
      // Deliberately totalElements != items.length — a fixture where the two
      // agree could pass even if the notifier read `items.length` instead of
      // the server's own field, which is exactly the regression this test
      // must catch.
      stubBookings(
        _page(<Booking>[
          _booking(id: 'b1', price: 100, startAt: DateTime(2026, 7, 20, 10)),
        ], totalElements: 3),
      );

      final BookingsDayState state = await _containerWith(repo).read(
        bookingsDayProvider(
          BookingsDayQuery.of(day: DateTime(2026, 7, 20)),
        ).future,
      );

      expect(state.items, hasLength(1));
      expect(state.totalElements, 3);
    });

    test('a failing fetch surfaces as an AsyncError', () async {
      when(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          serviceIds: any(named: 'serviceIds'),
          from: any(named: 'from'),
          to: any(named: 'to'),
          sort: any(named: 'sort'),
          page: any(named: 'page'),
          size: any(named: 'size'),
        ),
      ).thenAnswer((_) async => throw const NetworkFailure());

      final container = _containerWith(repo);
      final query = BookingsDayQuery.of(day: DateTime(2026, 7, 20));

      container.listen(bookingsDayProvider(query), (_, _) {});
      container.read(bookingsDayProvider(query));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final AsyncValue<BookingsDayState> state = container.read(
        bookingsDayProvider(query),
      );
      expect(state.hasError, isTrue);
      expect(state.error, isA<NetworkFailure>());
    });

    test('an empty day resolves to isEmpty — not an error', () async {
      stubBookings(_page(const <Booking>[]));

      final BookingsDayState state = await _containerWith(repo).read(
        bookingsDayProvider(
          BookingsDayQuery.of(day: DateTime(2026, 7, 20)),
        ).future,
      );

      expect(state.isEmpty, isTrue);
      expect(state.items, isEmpty);
    });
  });

  group('bookingsDayProvider — SERVER ORDER IS PRESERVED (ascending)', () {
    test('a page reaches the consumer in the server\'s order, NOT re-sorted by '
        'startsAt', () async {
      // Deliberately scrambled relative to startsAt: if anything re-sorts,
      // the ids come back in a different order. Ascending order is
      // load-bearing for Phase 7.10's lane assignment.
      final List<Booking> serverOrder = <Booking>[
        _booking(id: 'noon', price: 900, startAt: DateTime(2026, 7, 20, 12)),
        _booking(id: 'morning', price: 500, startAt: DateTime(2026, 7, 20, 9)),
        _booking(id: 'evening', price: 100, startAt: DateTime(2026, 7, 20, 18)),
      ];
      stubBookings(_page(serverOrder));

      final BookingsDayState state = await _containerWith(repo).read(
        bookingsDayProvider(
          BookingsDayQuery.of(day: DateTime(2026, 7, 20)),
        ).future,
      );

      expect(state.items.map((Booking b) => b.id), <String>[
        'noon',
        'morning',
        'evening',
      ]);
    });
  });

  group('bookingsDayProvider — single fetch, never a loop', () {
    test('a response reporting more results than returned sets isTruncated and '
        'issues NO second request', () async {
      stubBookings(
        _page(
          <Booking>[
            _booking(id: 'a', price: 100, startAt: DateTime(2026, 7, 20, 9)),
          ],
          totalPages: 2,
          totalElements: 101,
        ),
      );

      final container = _containerWith(repo);
      final BookingsDayState state = await container.read(
        bookingsDayProvider(
          BookingsDayQuery.of(day: DateTime(2026, 7, 20)),
        ).future,
      );

      expect(state.isTruncated, isTrue);
      expect(state.items, hasLength(1));
      expect(state.totalElements, 101);
      verify(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          serviceIds: any(named: 'serviceIds'),
          from: any(named: 'from'),
          to: any(named: 'to'),
          sort: any(named: 'sort'),
          page: any(named: 'page'),
          size: any(named: 'size'),
        ),
      ).called(1);
    });

    test('a fully-materialised day (totalElements == items.length) is NOT '
        'truncated', () async {
      stubBookings(
        _page(<Booking>[
          _booking(id: 'a', price: 100, startAt: DateTime(2026, 7, 20, 9)),
        ], totalElements: 1),
      );

      final BookingsDayState state = await _containerWith(repo).read(
        bookingsDayProvider(
          BookingsDayQuery.of(day: DateTime(2026, 7, 20)),
        ).future,
      );

      expect(state.isTruncated, isFalse);
    });
  });

  group('bookingsDayProvider — the provider-leak guard (family reuse)', () {
    test('two independently-built identical queries resolve to ONE family '
        'member — one fetch, not two', () async {
      stubBookings(_page(const <Booking>[]));
      final container = _containerWith(repo);

      final a = BookingsDayQuery.of(
        day: DateTime(2026, 7, 20),
        statuses: <BookingStatus>{BookingStatus.confirmed},
      );
      final b = BookingsDayQuery.of(
        day: DateTime(2026, 7, 20),
        statuses: <BookingStatus>{BookingStatus.confirmed},
      );

      await container.read(bookingsDayProvider(a).future);
      await container.read(bookingsDayProvider(b).future);

      verify(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          serviceIds: any(named: 'serviceIds'),
          from: any(named: 'from'),
          to: any(named: 'to'),
          sort: any(named: 'sort'),
          page: any(named: 'page'),
          size: any(named: 'size'),
        ),
      ).called(1);
    });

    test('the SAME calendar day at different clock times — a stray time '
        'component, exactly what a date picker hands back — collapses to ONE '
        'family member', () async {
      stubBookings(_page(const <Booking>[]));
      final container = _containerWith(repo);

      final a = BookingsDayQuery.of(day: DateTime(2026, 7, 18, 9, 14));
      final b = BookingsDayQuery.of(day: DateTime(2026, 7, 18, 17, 2));

      await container.read(bookingsDayProvider(a).future);
      await container.read(bookingsDayProvider(b).future);

      verify(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          serviceIds: any(named: 'serviceIds'),
          from: any(named: 'from'),
          to: any(named: 'to'),
          sort: any(named: 'sort'),
          page: any(named: 'page'),
          size: any(named: 'size'),
        ),
      ).called(1);
    });

    test('statuses/serviceIds supplied in different iteration orders reuse the '
        'SAME family member', () async {
      stubBookings(_page(const <Booking>[]));
      final container = _containerWith(repo);

      final a = BookingsDayQuery.of(
        day: DateTime(2026, 7, 20),
        statuses: <BookingStatus>{
          BookingStatus.notCompleted,
          BookingStatus.confirmed,
        },
        serviceIds: <String>{'svc-b', 'svc-a'},
      );
      final b = BookingsDayQuery.of(
        day: DateTime(2026, 7, 20),
        statuses: <BookingStatus>{
          BookingStatus.confirmed,
          BookingStatus.notCompleted,
        },
        serviceIds: <String>{'svc-a', 'svc-b'},
      );

      await container.read(bookingsDayProvider(a).future);
      await container.read(bookingsDayProvider(b).future);

      verify(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          serviceIds: any(named: 'serviceIds'),
          from: any(named: 'from'),
          to: any(named: 'to'),
          sort: any(named: 'sort'),
          page: any(named: 'page'),
          size: any(named: 'size'),
        ),
      ).called(1);
    });

    test(
      'a DIFFERENT day is a DIFFERENT family member — two fetches',
      () async {
        stubBookings(_page(const <Booking>[]));
        final container = _containerWith(repo);

        final a = BookingsDayQuery.of(day: DateTime(2026, 7, 20));
        final b = BookingsDayQuery.of(day: DateTime(2026, 7, 21));

        await container.read(bookingsDayProvider(a).future);
        await container.read(bookingsDayProvider(b).future);

        verify(
          () => repo.getMyBookings(
            statuses: any(named: 'statuses'),
            serviceIds: any(named: 'serviceIds'),
            from: any(named: 'from'),
            to: any(named: 'to'),
            sort: any(named: 'sort'),
            page: any(named: 'page'),
            size: any(named: 'size'),
          ),
        ).called(2);
      },
    );
  });

  group('bookingsDayProvider — bounded keepAlive cache (MEDIUM-2)', () {
    // Riverpod's autoDispose eviction check runs on a REAL `Timer(
    // Duration.zero, ...)` (`package:riverpod/src/core/scheduler.dart`), not
    // a microtask — so a bare `await` on an already-resolved Future is not
    // enough to observe it. `visit` gives the scheduler a genuine chance to
    // dispose: subscribe, resolve, unsubscribe, then yield past a zero-
    // duration Timer (registered strictly after the unsubscribe's own
    // dispose-check timer, so it always runs second).
    Future<void> visit(
      ProviderContainer container,
      BookingsDayQuery query,
    ) async {
      final ProviderSubscription<AsyncValue<BookingsDayState>> sub = container
          .listen(bookingsDayProvider(query), (_, _) {});
      await container.read(bookingsDayProvider(query).future);
      sub.close();
      await Future<void>.delayed(Duration.zero);
    }

    test('an immediate re-visit to a recently-viewed day (after its watcher '
        'unsubscribes) issues NO second request — bounded keepAlive, not plain '
        'autoDispose', () async {
      stubBookings(_page(const <Booking>[]));
      final container = _containerWith(repo);
      final query = BookingsDayQuery.of(day: DateTime(2026, 7, 20));

      await visit(container, query);
      await visit(container, query);

      verify(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          serviceIds: any(named: 'serviceIds'),
          from: any(named: 'from'),
          to: any(named: 'to'),
          sort: any(named: 'sort'),
          page: any(named: 'page'),
          size: any(named: 'size'),
        ),
      ).called(1);
    });

    test('the cache is genuinely BOUNDED: a 4th distinct day evicts the '
        'oldest of the 3 kept alive, which then refetches on revisit — a day '
        'still inside the window does NOT', () async {
      stubBookings(_page(const <Booking>[]));
      final container = _containerWith(repo);

      final day1 = BookingsDayQuery.of(day: DateTime(2026, 7, 17));
      final day2 = BookingsDayQuery.of(day: DateTime(2026, 7, 18));
      final day3 = BookingsDayQuery.of(day: DateTime(2026, 7, 19));
      final day4 = BookingsDayQuery.of(day: DateTime(2026, 7, 20));

      // Recency is tracked at the granularity of genuine FETCHES (`touch`
      // is called from `build()`), not of every `visit` — a cache hit
      // serves the existing element without rebuilding, so it does not
      // bump that day's position. Fills the capacity-3 window with
      // {day1, day2, day3}.
      await visit(container, day1);
      await visit(container, day2);
      await visit(container, day3);
      // A 4th DISTINCT day exceeds the cap — day1 (the oldest) is evicted.
      // Window is now {day2, day3, day4}.
      await visit(container, day4);
      // day1 was evicted — this is a genuine second fetch for it. Window
      // becomes {day3, day4, day1} (day2, now the oldest, is evicted).
      await visit(container, day1);
      // day4 was never evicted — still resident — so this revisit is
      // served from cache with NO further fetch.
      await visit(container, day4);

      // day1, day2, day3, day4, day1-again = 5. NOT 6 (day4's final
      // revisit would also have refetched — no cache at all, or one too
      // small) and NOT 4 (day1's revisit would never have needed to
      // refetch — an unbounded keepAlive that never evicts anything).
      verify(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          serviceIds: any(named: 'serviceIds'),
          from: any(named: 'from'),
          to: any(named: 'to'),
          sort: any(named: 'sort'),
          page: any(named: 'page'),
          size: any(named: 'size'),
        ),
      ).called(5);
    });
  });

  group('bookingsDayProvider — session-boundary PII (mobile-security HIGH, '
      '2026-07-19)', () {
    // Mirrors the bounded-keepAlive group's `visit` helper above (same
    // Timer(Duration.zero) reasoning — this class's own doc comment
    // explains why a bare `await` on an already-resolved Future is not
    // enough to observe an autoDispose eviction check).
    Future<void> visit(
      ProviderContainer container,
      BookingsDayQuery query,
    ) async {
      final ProviderSubscription<AsyncValue<BookingsDayState>> sub = container
          .listen(bookingsDayProvider(query), (_, _) {});
      await container.read(bookingsDayProvider(query).future);
      sub.close();
      await Future<void>.delayed(Duration.zero);
    }

    test('a logout followed by a different account logging in forces a '
        'FRESH fetch for the SAME query — the cached member is never served '
        'to the next account (HIGH regression guard)', () async {
      stubBookings(_page(const <Booking>[]));
      final result = await _containerWithAuth(
        repo,
        const AuthSession.authenticated(user: _master1, accessToken: 'token-1'),
      );
      final query = BookingsDayQuery.of(day: DateTime(2026, 7, 20));

      // master-1 views "today" — one fetch, pinned by the bounded LRU.
      await visit(result.container, query);

      // Logout: the session settles to Unauthenticated, exactly like
      // `AuthNotifier.logout` sets `state = AsyncData(unauthenticated())`.
      result.auth.setSession(const AuthSession.unauthenticated());
      // A different account logs in.
      result.auth.setSession(
        const AuthSession.authenticated(user: _master2, accessToken: 'token-2'),
      );

      // master-2 watches the exact SAME query. If the cached member
      // (fix (a) missing/broken) were still being served, this would
      // issue NO second request and master-2 would see master-1's
      // AsyncData with no loading state — the HIGH this test guards.
      await visit(result.container, query);

      verify(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          serviceIds: any(named: 'serviceIds'),
          from: any(named: 'from'),
          to: any(named: 'to'),
          sort: any(named: 'sort'),
          page: any(named: 'page'),
          size: any(named: 'size'),
        ),
      ).called(2);
    });

    test('a silent token refresh for the SAME account does NOT evict the '
        'cache — proves the authProvider watch is narrowed to the user id, '
        'not the whole session', () async {
      stubBookings(_page(const <Booking>[]));
      final result = await _containerWithAuth(
        repo,
        const AuthSession.authenticated(user: _master1, accessToken: 'token-1'),
      );
      final query = BookingsDayQuery.of(day: DateTime(2026, 7, 20));

      await visit(result.container, query);

      // A silent refresh (`AuthNotifier.setAccessToken`'s production
      // behaviour): SAME user, a NEW accessToken.
      result.auth.setSession(
        const AuthSession.authenticated(
          user: _master1,
          accessToken: 'token-1-refreshed',
        ),
      );

      // Same query, same account — must be served from the bounded
      // keepAlive cache, exactly as if nothing had happened.
      await visit(result.container, query);

      verify(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          serviceIds: any(named: 'serviceIds'),
          from: any(named: 'from'),
          to: any(named: 'to'),
          sort: any(named: 'sort'),
          page: any(named: 'page'),
          size: any(named: 'size'),
        ),
      ).called(1);
    });

    test('DayKeepAliveLru.clear closes every held link — a bounded-keepAlive '
        'member with no active listener is reclaimed by ordinary autoDispose '
        'once its link is closed (defence-in-depth half of the HIGH fix, '
        'exercised the way AuthNotifier.logout calls it)', () async {
      stubBookings(_page(const <Booking>[]));
      final result = await _containerWithAuth(
        repo,
        const AuthSession.authenticated(user: _master1, accessToken: 'token-1'),
      );
      final query = BookingsDayQuery.of(day: DateTime(2026, 7, 20));

      // Cached, pinned by the LRU, nobody currently watching it.
      await visit(result.container, query);

      // The exact call `AuthNotifier.logout` makes.
      result.container.read(dayKeepAliveLruProvider).clear();
      // Let the scheduler's disposal check run now that the artificial
      // pin is gone (same reasoning as `visit`'s trailing delay).
      await Future<void>.delayed(Duration.zero);

      // Revisiting the SAME query — same account, nothing else changed —
      // must now issue a genuine second fetch: the member was actually
      // disposed, not merely marked dirty.
      await visit(result.container, query);

      verify(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          serviceIds: any(named: 'serviceIds'),
          from: any(named: 'from'),
          to: any(named: 'to'),
          sort: any(named: 'sort'),
          page: any(named: 'page'),
          size: any(named: 'size'),
        ),
      ).called(2);
    });

    test('an ACTIVELY WATCHED member — a live listener on screen, never closed '
        'across the session flip — is force-refetched by the SAME '
        'id-watching cascade and does NOT keep serving the previous '
        "account's BookingsDayState (mobile-qa LOW-2, 2026-07-19: the "
        'realistic "master is looking at the screen when the session ends" '
        'scenario neither the HIGH regression guard nor the clear()-reclaim '
        'test above can exercise, since both always close their listener '
        'before touching auth)', () async {
      final Booking staleBooking = _booking(
        id: 'master1-stale-booking',
        price: 100,
        startAt: DateTime(2026, 7, 20, 9),
      );
      final Booking freshBooking = _booking(
        id: 'post-logout-booking',
        price: 200,
        startAt: DateTime(2026, 7, 20, 11),
      );
      when(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          serviceIds: any(named: 'serviceIds'),
          from: any(named: 'from'),
          to: any(named: 'to'),
          sort: any(named: 'sort'),
          page: any(named: 'page'),
          size: any(named: 'size'),
        ),
      ).thenAnswer((_) async => _page(<Booking>[staleBooking]));

      final result = await _containerWithAuth(
        repo,
        const AuthSession.authenticated(user: _master1, accessToken: 'token-1'),
      );
      final query = BookingsDayQuery.of(day: DateTime(2026, 7, 20));

      // A live Consumer watching the screen right now — deliberately kept
      // open through the whole session flip below via `addTearDown`
      // rather than an explicit `sub.close()` mid-test. This is the one
      // thing `visit` (used by every other test in this group) never
      // does: it always closes its subscription before touching auth,
      // which is exactly why none of those tests can distinguish "the
      // member was disposed and later re-created" from "the member never
      // noticed the logout at all."
      final ProviderSubscription<AsyncValue<BookingsDayState>> sub = result
          .container
          .listen(bookingsDayProvider(query), (_, _) {});
      addTearDown(sub.close);

      final BookingsDayState beforeLogout = await result.container.read(
        bookingsDayProvider(query).future,
      );
      expect(beforeLogout.items.map((Booking b) => b.id), <String>[
        'master1-stale-booking',
      ]);

      // From here on, the repository would serve the NEXT account's
      // data — proving the eventual read is a genuine refetch, not a
      // re-emission of whatever the first call already cached.
      when(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          serviceIds: any(named: 'serviceIds'),
          from: any(named: 'from'),
          to: any(named: 'to'),
          sort: any(named: 'sort'),
          page: any(named: 'page'),
          size: any(named: 'size'),
        ),
      ).thenAnswer((_) async => _page(<Booking>[freshBooking]));

      // Logout — the exact state transition `AuthNotifier.logout` makes.
      // Nothing re-subscribes or otherwise disturbs `sub` from here.
      result.auth.setSession(const AuthSession.unauthenticated());

      // No `visit`, no extra pump: reading `.future` on a member Riverpod
      // has just marked dirty flushes it before returning — the same
      // mechanism every other `.future` read in this file already relies
      // on, just now observed on a member that was NEVER unsubscribed
      // rather than one freshly re-subscribed.
      final BookingsDayState afterLogout = await result.container.read(
        bookingsDayProvider(query).future,
      );

      expect(
        afterLogout.items.map((Booking b) => b.id),
        <String>['post-logout-booking'],
        reason:
            'an actively-watched member must not keep serving the '
            "previous account's BookingsDayState after logout — it must "
            'rebuild through the same authProvider-id cascade the '
            'unwatched case relies on',
      );

      // The raw provider state (not just the future) must agree — nobody
      // reading `bookingsDayProvider(query)` directly sees stale PII
      // either.
      final AsyncValue<BookingsDayState> rawState = result.container.read(
        bookingsDayProvider(query),
      );
      expect(rawState.asData?.value.items.map((Booking b) => b.id), <String>[
        'post-logout-booking',
      ]);

      verify(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          serviceIds: any(named: 'serviceIds'),
          from: any(named: 'from'),
          to: any(named: 'to'),
          sort: any(named: 'sort'),
          page: any(named: 'page'),
          size: any(named: 'size'),
        ),
      ).called(2);
    });
  });
}
