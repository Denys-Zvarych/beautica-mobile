// Regression tests for the STUCK-SKELETON defect (user-reported 2026-08-20).
//
// THE DEFECT
// ----------
// A master created a manual walk-in booking, opened THAT date on «Мої записи»,
// and got the loading skeleton indefinitely — no grid, no cards, no error, and
// nothing in the backend log.
//
// Two properties of `bookingsDayProvider` combined to produce it, and NEITHER
// was guarded by a test:
//
//   1. **Why only that date.** The day list keeps a bounded ≤3-day keepAlive
//      LRU (`bookings_day_notifier.dart`'s `_kMaxKeptDays`). Every other day
//      the master had recently visited painted from that cache without a
//      request; the freshly-booked date is BY CONSTRUCTION the one member that
//      must hit the network. Nothing pinned the boundary — a silent bump of
//      `_kMaxKeptDays` to a large number, or its removal, changes which days
//      refetch and no test noticed.
//
//   2. **Why it was silent.** `beauticaProviderRetry` delegated a transient
//      failure to `ProviderContainer.defaultRetry`'s FULL curve — 10 attempts
//      over ~38 s — and `AsyncValue.when` routes `AsyncLoading(retrying: true)`
//      to `loading:`, so every re-attempt rendered the same skeleton as the
//      first. The failure never became an error the UI could show.
//
// `test/core/errors/failure_retry_policy_test.dart` pins the retry PREDICATE
// (which `retryCount` values return a delay). That is necessary and not
// sufficient: it proves what the function returns, never that Riverpod
// actually stops calling the repository. This file pins the OBSERVABLE
// consequence — the number of times the repository is hit, and the state the
// provider lands in.
//
// TWO TRAPS THIS FILE IS WRITTEN AROUND
// -------------------------------------
//   • `AsyncLoading(retrying: true)` satisfies `hasError` and carries the real
//     `error`. A test asserting only `hasError`/`error` therefore CANNOT tell
//     the terminal error apart from the mid-retry loading state, and passes
//     while the screen is still shimmering. Every error assertion below also
//     pins the runtime type with `isA<AsyncError<…>>()`.
//   • A synchronous `thenThrow` throws during `build()` and short-circuits the
//     retry machinery entirely — measured elsewhere in this repo as ONE
//     repository call and an immediate terminal `AsyncError`. That is not what
//     a Dio-backed repository does: it ALWAYS fails asynchronously. Every
//     failing stub here is `thenAnswer((_) async => throw …)`, which is the
//     only shape that exercises the retry curve at all.

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
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

class _StubAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async => const AuthSession.authenticated(
    user: User(
      id: 'master-1',
      email: 'master1@beautica.ua',
      role: UserRole.independentMaster,
      firstName: 'Оля',
      lastName: 'Коваль',
    ),
    accessToken: 'token-1',
  );
}

/// The Kyiv calendar day the master "just booked" — the LRU member that must
/// hit the network. A plain date token, never a booking `startAt`, so it
/// carries no `BookingDisplayX.isPast` time bomb.
final DateTime _kDay0 = DateTime(2026, 7, 20);

BookingsDayQuery _q(int dayOffset) =>
    BookingsDayQuery.dayList(day: _kDay0.add(Duration(days: dayOffset)));

const PageResponse<Booking> _emptyPage = PageResponse<Booking>(
  items: <Booking>[],
  page: 0,
  totalPages: 1,
  totalElements: 0,
);

/// Settles `authProvider` BEFORE anything reads `bookingsDayProvider` — its
/// `build()` watches `authProvider.select(...)`, so reading while auth is
/// still `AsyncLoading` observes a `null` id and then rebuilds a SECOND time,
/// inflating every call count in this file by one.
Future<ProviderContainer> _container(BookingRepository repo) async {
  final ProviderContainer container = ProviderContainer(
    // The PRODUCTION predicate — the whole point of this file is what it does
    // end to end, so it must not be stubbed out here.
    retry: beauticaProviderRetry,
    overrides: <Object>[
      bookingRepositoryProvider.overrideWithValue(repo),
      authProvider.overrideWith(_StubAuthNotifier.new),
    ].cast(),
  );
  addTearDown(container.dispose);
  await container.read(authProvider.future);
  return container;
}

/// Lets Riverpod's own scheduler run.
///
/// Closing a `KeepAliveLink` does not dispose the element inline — it calls
/// `mayNeedDispose()`, which QUEUES the disposal on the scheduler
/// (`scheduler.dart::scheduleProviderDispose` → a zero-duration `Timer`).
/// Until that task runs, an evicted member still holds its cached
/// `AsyncData` and a re-read is served from it, so a test that measures
/// eviction without yielding to the event loop measures nothing. Not a
/// fixed wait: `Duration.zero` yields exactly one event-loop turn.
Future<void> _flushScheduler() => Future<void>.delayed(Duration.zero);

/// Holds a LIVE subscription on [query]'s day-list member for the rest of the
/// test.
///
/// Load-bearing for every retry test below. `container.read(p.future)` does not
/// retain the element: between a failed attempt and its re-attempt there is a
/// genuine async gap, `mayNeedDispose()` runs, and the element is torn down
/// mid-curve — the read then fails with "was disposed during loading state"
/// and the retry never completes. A real screen always has a live consumer
/// while it is waiting, which is precisely the situation this file reproduces,
/// so the subscription is fidelity, not a workaround.
void _keepAlive(ProviderContainer container, BookingsDayQuery query) {
  final ProviderSubscription<AsyncValue<BookingsDayState>> sub = container
      .listen(bookingsDayProvider(query), (_, _) {}, fireImmediately: true);
  addTearDown(sub.close);
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

  /// Records the `from` of every `getMyBookings` call, so a test can tell
  /// WHICH day was fetched, not merely how many fetches happened.
  List<DateTime?> stubDays() {
    final List<DateTime?> days = <DateTime?>[];
    when(
      () => repo.getMyBookings(
        statuses: any(named: 'statuses'),
        serviceIds: any(named: 'serviceIds'),
        from: any(named: 'from'),
        to: any(named: 'to'),
        sort: any(named: 'sort'),
        page: any(named: 'page'),
        size: any(named: 'size'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((Invocation i) async {
      days.add(i.namedArguments[#from] as DateTime?);
      return _emptyPage;
    });
    return days;
  }

  // -------------------------------------------------------------------------
  // (b) THE LRU BOUNDARY — "why only that date"
  // -------------------------------------------------------------------------
  group('bounded keepAlive LRU — the "why only that date" invariant', () {
    test('a day INSIDE the ≤3-day window is served from cache; the day pushed '
        'OUT of it refetches', () async {
      final List<DateTime?> fetched = stubDays();
      final ProviderContainer container = await _container(repo);

      // Visit FOUR distinct days with no live listener anywhere — the bounded
      // `ref.keepAlive()` LRU is the only thing keeping any of them alive.
      for (int i = 0; i < 4; i++) {
        await container.read(bookingsDayProvider(_q(i)).future);
      }
      expect(fetched, hasLength(4), reason: 'sanity: one fetch per new day');
      await _flushScheduler();

      // The three most-recently-touched days (1, 2, 3) are still pinned.
      // Asserted BEFORE re-reading day 0 on purpose: re-reading day 0 first
      // would itself evict day 1, and the assertion would then be measuring
      // the test's own ordering rather than the cache.
      for (int i = 3; i >= 1; i--) {
        await container.read(bookingsDayProvider(_q(i)).future);
      }
      expect(
        fetched,
        hasLength(4),
        reason:
            'days inside the window must paint from cache — no request at '
            'all, which is exactly why the OTHER dates looked fine to the '
            'master',
      );

      // Day 0 was evicted the moment day 3 was touched (budget of 3), so it
      // must go back to the network — the freshly-booked date's position.
      await container.read(bookingsDayProvider(_q(0)).future);
      expect(
        fetched,
        hasLength(5),
        reason:
            'the day outside the ≤3-day LRU is the ONE that must hit the '
            'network; this is the whole "why only that date" mechanism',
      );
      expect(
        fetched.last,
        _kDay0,
        reason: 'and the refetch must be for day 0, not some other member',
      );
    });

    test('the LRU is bounded, not unbounded — visiting many days never pins '
        'more than the budget', () async {
      final List<DateTime?> fetched = stubDays();
      final ProviderContainer container = await _container(repo);

      // Scrub the rail across ten days, then come back to the first one.
      for (int i = 0; i < 10; i++) {
        await container.read(bookingsDayProvider(_q(i)).future);
      }
      expect(fetched, hasLength(10));
      await _flushScheduler();

      await container.read(bookingsDayProvider(_q(0)).future);
      expect(
        fetched,
        hasLength(11),
        reason:
            'an UNBOUNDED keepAlive would have kept day 0 and served it from '
            'cache — the bound is what makes this a fetch, and what stops one '
            'cached day of client PII accumulating per rail cell visited',
      );
    });
  });

  // -------------------------------------------------------------------------
  // (c) THE BOUNDED RETRY — "why it was silent"
  // -------------------------------------------------------------------------
  group('bounded transient retry — the ~38 s silent hang cannot come back', () {
    /// Fails every call ASYNCHRONOUSLY. A synchronous `thenThrow` would throw
    /// inside `build()` and bypass Riverpod's retry entirely — one call, no
    /// curve, and a test that proves nothing about the bound.
    List<DateTime?> stubAsyncTransientFailure() {
      final List<DateTime?> calls = <DateTime?>[];
      when(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          serviceIds: any(named: 'serviceIds'),
          from: any(named: 'from'),
          to: any(named: 'to'),
          sort: any(named: 'sort'),
          page: any(named: 'page'),
          size: any(named: 'size'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((Invocation i) async {
        calls.add(i.namedArguments[#from] as DateTime?);
        throw const NetworkFailure();
      });
      return calls;
    }

    test('a persistently transient failure hits the repository EXACTLY TWICE '
        'and lands on a TERMINAL AsyncError', () async {
      final List<DateTime?> calls = stubAsyncTransientFailure();
      final ProviderContainer container = await _container(repo);
      _keepAlive(container, _q(0));

      await expectLater(
        container.read(bookingsDayProvider(_q(0)).future),
        throwsA(isA<NetworkFailure>()),
      );

      expect(
        calls,
        hasLength(2),
        reason:
            'one attempt plus ONE bounded re-attempt. Before the 2026-08-20 '
            'bound this was 10 attempts over ~38 s, each additionally able to '
            "burn dioProvider's 15 s connect / 30 s receive timeout — the "
            'screen looked hung because the attempt COUNT, not the backoff, '
            'was the wall clock',
      );

      final AsyncValue<BookingsDayState> state = container.read(
        bookingsDayProvider(_q(0)),
      );
      // `isA<AsyncError>` is the load-bearing half. `hasError` alone is ALSO
      // true of `AsyncLoading(retrying: true)`, so an assertion built on it
      // would pass mid-retry — i.e. while the user is still staring at the
      // skeleton this whole file exists to abolish.
      expect(
        state,
        isA<AsyncError<BookingsDayState>>(),
        reason:
            'the provider must reach a TERMINAL error the UI can render a '
            'retry button on — not park in AsyncLoading(retrying: true), '
            'which `AsyncValue.when` routes to the skeleton',
      );
      expect(state.isLoading, isFalse);
      expect(state.error, isA<NetworkFailure>());
    });

    test('a DETERMINISTIC failure is not retried at all — the bound shortens, '
        'it never starts, a retry sequence', () async {
      final List<DateTime?> calls = <DateTime?>[];
      when(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          serviceIds: any(named: 'serviceIds'),
          from: any(named: 'from'),
          to: any(named: 'to'),
          sort: any(named: 'sort'),
          page: any(named: 'page'),
          size: any(named: 'size'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((Invocation i) async {
        calls.add(i.namedArguments[#from] as DateTime?);
        throw const NotFoundFailure();
      });

      final ProviderContainer container = await _container(repo);
      _keepAlive(container, _q(0));
      await expectLater(
        container.read(bookingsDayProvider(_q(0)).future),
        throwsA(isA<NotFoundFailure>()),
      );

      expect(
        calls,
        hasLength(1),
        reason:
            'a 404 will not become a 200 by asking again; the classification '
            'refuses it at attempt 0, ahead of the bound',
      );
      expect(
        container.read(bookingsDayProvider(_q(0))),
        isA<AsyncError<BookingsDayState>>(),
      );
    });

    test('a transient failure that clears on the re-attempt still SUCCEEDS — '
        'the bound must not have removed the retry that matters', () async {
      int calls = 0;
      when(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          serviceIds: any(named: 'serviceIds'),
          from: any(named: 'from'),
          to: any(named: 'to'),
          sort: any(named: 'sort'),
          page: any(named: 'page'),
          size: any(named: 'size'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((_) async {
        calls++;
        if (calls == 1) throw const NetworkFailure();
        return _emptyPage;
      });

      final ProviderContainer container = await _container(repo);
      _keepAlive(container, _q(0));
      final BookingsDayState state = await container.read(
        bookingsDayProvider(_q(0)).future,
      );

      expect(calls, 2);
      expect(state.items, isEmpty);
      expect(
        container.read(bookingsDayProvider(_q(0))),
        isA<AsyncData<BookingsDayState>>(),
        reason:
            'a dropped packet / Wi-Fi→LTE handover / backend mid-restart is '
            'exactly the case the ONE surviving re-attempt exists to serve',
      );
    });
  });
}
