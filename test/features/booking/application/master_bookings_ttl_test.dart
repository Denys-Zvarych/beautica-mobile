// Phase 7.1 — the bounded-TTL cache guards for `masterBookingsProvider`
// (5 min, perf P2) and `bookedDaysProvider` (30 min, perf P3).
//
// WHY THIS FILE EXISTS
// --------------------
// Both providers are `autoDispose` (a filter sheet can mint many short-lived
// query objects, so an unconditional `keepAlive: true` would grow the family
// without bound), but both open a BOUNDED `ref.keepAlive()` link in `build`
// and close it from a `Timer`:
//
//     final link = ref.keepAlive();
//     final Timer timer = Timer(const Duration(minutes: 5), link.close);
//     ref.onDispose(timer.cancel);
//
// That three-line shape was INVISIBLE to the rest of the suite. Deleting the
// `ref.keepAlive()` line reverts the perf fix — every navigation back into
// «Мої записи» re-fetches page 0 and throws away the paged-in pages and the
// scroll position — with a fully green `flutter test` and a clean
// `flutter analyze`. Nothing else pins it, so the regression would ship
// silently. This file is that pin.
//
// Each provider gets THREE tests, and they fail in three DIFFERENT directions,
// which is the point — one assertion alone would let the opposite mistake
// through:
//
//   1. INSIDE the window, a re-listen must NOT refetch.
//      → fails if `ref.keepAlive()` is deleted (plain autoDispose disposes the
//        member the instant the last listener goes, so re-listening refetches).
//   2. PAST the window, a re-listen MUST refetch exactly once.
//      → fails if the TTL is widened into an unconditional keepAlive, or if
//        `link.close` is never wired to the timer — the member would then live
//        for the whole session and serve arbitrarily stale rows.
//   3. Disposing a member EARLY must leave no pending timer.
//      → fails if `ref.onDispose(timer.cancel)` is deleted. flutter_test's own
//        teardown raises "A Timer is still pending even after the widget tree
//        was disposed", so the assertion is enforced by the framework rather
//        than written out — a leaked 5-/30-minute timer holding a closure over
//        a disposed provider's `KeepAliveLink` is precisely what that check
//        exists for.
//
// ON `tester.pump(Duration)` HERE
// -------------------------------
// The project bans `pump(Duration(...))` as a way of WAITING for async work
// (M6) — it is non-deterministic and hides real timing bugs. This file uses it
// for the opposite purpose: a `testWidgets` body runs inside a `FakeAsync`
// zone, so the `Timer` under test is a FAKE timer and `tester.pump(d)` ELAPSES
// the fake clock deterministically. Nothing is being waited on; five minutes
// pass in microseconds of real time, and the result is exact rather than
// approximate. A real-clock wait could not test a 30-minute TTL at all.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';

import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/features/booking/application/booked_days_notifier.dart';
import 'package:beautica_mobile/features/booking/application/master_bookings_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/master_bookings_query.dart';

class _MockBookingRepository extends Mock implements BookingRepository {}

/// The TTLs the two providers declare. Kept as local constants so a change to
/// either duration in `lib/` shows up here as a FAILING test rather than as a
/// silently-passing one — the numbers are part of the contract.
const Duration _listTtl = Duration(minutes: 5);
const Duration _railTtl = Duration(minutes: 30);

PageResponse<Booking> _emptyPage() => const PageResponse<Booking>(
  items: <Booking>[],
  page: 0,
  totalPages: 1,
  totalElements: 0,
);

void main() {
  setUpAll(() {
    registerFallbackValue(<BookingStatus>{});
    registerFallbackValue(BookingSort.newest);
  });

  late _MockBookingRepository repo;
  late int listCalls;
  late int railCalls;

  setUp(() {
    repo = _MockBookingRepository();
    listCalls = 0;
    railCalls = 0;

    when(
      () => repo.getMyBookings(
        statuses: any(named: 'statuses'),
        serviceIds: any(named: 'serviceIds'),
        from: any(named: 'from'),
        to: any(named: 'to'),
        sort: any(named: 'sort'),
        page: any(named: 'page'),
      ),
    ).thenAnswer((_) async {
      listCalls++;
      return _emptyPage();
    });

    when(
      () => repo.getMyBookedDays(
        from: any(named: 'from'),
        to: any(named: 'to'),
      ),
    ).thenAnswer((_) async {
      railCalls++;
      return const <DateTime>[];
    });
  });

  /// A fresh container per test.
  ///
  /// Deliberately NOT registered via `addTearDown` (the usual M1 idiom).
  /// `addTearDown` callbacks run AFTER `testWidgets`' end-of-body invariant
  /// check, so a still-alive member's TTL timer would be pending at that
  /// moment and every test here would fail on the framework's own
  /// pending-timer assertion — the very assertion the third test in each group
  /// relies on. So each body disposes its container explicitly, in-body, once
  /// it is done. Verified: the check is live — the first draft of this file
  /// tripped it on all four cache tests.
  ProviderContainer buildContainer() => ProviderContainer(
    overrides: [bookingRepositoryProvider.overrideWithValue(repo)],
  );

  // ==========================================================================
  // masterBookingsProvider — 5-minute keepAlive (perf P2).
  //
  // The user journey each test encodes: the master scrolls «Мої записи», taps
  // a booking (the list stops being watched), reads the detail, and comes
  // back.
  // ==========================================================================
  group('masterBookingsProvider — 5-minute keepAlive across navigation', () {
    final MasterBookingsQuery query = MasterBookingsQuery.of(
      statuses: <BookingStatus>{BookingStatus.confirmed},
    );

    testWidgets(
      'returning WITHIN 5 minutes serves the cached page — no refetch '
      '(deleting ref.keepAlive() fails here)',
      (tester) async {
        final container = buildContainer();

        // Enter the screen.
        final sub = container.listen(
          masterBookingsProvider(query),
          (_, _) {},
          fireImmediately: true,
        );
        await container.read(masterBookingsProvider(query).future);
        expect(listCalls, 1, reason: 'entering the screen fetches page 0');

        // Navigate away — the ONLY thing keeping the member alive from here is
        // the keepAlive link.
        sub.close();
        // fixed-wait-ok: advancing a FAKE clock past a known TTL boundary,
        // not waiting on async work — deterministic by construction (see the
        // file header). Stopping 1s short of 5min is the assertion.
        await tester.pump(_listTtl - const Duration(seconds: 1));

        // Come back.
        final sub2 = container.listen(
          masterBookingsProvider(query),
          (_, _) {},
          fireImmediately: true,
        );
        await tester.pump();

        expect(
          listCalls,
          1,
          reason:
              'the member must still be alive 4m59s after the last listener '
              'went, so returning to the list costs no request',
        );
        sub2.close();
        container.dispose();
      },
    );

    testWidgets(
      'the link CLOSES at 5 minutes — a later return refetches exactly once '
      '(an unconditional keepAlive fails here)',
      (tester) async {
        final container = buildContainer();

        final sub = container.listen(
          masterBookingsProvider(query),
          (_, _) {},
          fireImmediately: true,
        );
        await container.read(masterBookingsProvider(query).future);
        expect(listCalls, 1);

        sub.close();
        // Past the TTL: the timer fires, `link.close()` runs, and with no
        // listener the autoDispose member is collected.
        // fixed-wait-ok: fake-clock advance 1s PAST the 5-minute TTL, which
        // is precisely what must fire the timer and close the keepAlive link.
        await tester.pump(_listTtl + const Duration(seconds: 1));

        final sub2 = container.listen(
          masterBookingsProvider(query),
          (_, _) {},
          fireImmediately: true,
        );
        await container.read(masterBookingsProvider(query).future);

        expect(
          listCalls,
          2,
          reason:
              'the cache is BOUNDED — past 5 minutes the member is gone and '
              'the list must re-fetch, exactly once and not more',
        );
        sub2.close();
        container.dispose();
      },
    );

    testWidgets(
      'a member disposed BEFORE its TTL leaves no pending timer — flutter_test '
      'teardown fails if ref.onDispose(timer.cancel) is deleted',
      (tester) async {
        // A deliberately local container so it can be torn down mid-TTL, which
        // is the ordinary case: the user changes a filter one second after the
        // page loads and this member is dropped with ~4m59s left on its timer.
        final container = ProviderContainer(
          overrides: [bookingRepositoryProvider.overrideWithValue(repo)],
        );
        final sub = container.listen(
          masterBookingsProvider(query),
          (_, _) {},
          fireImmediately: true,
        );
        await container.read(masterBookingsProvider(query).future);

        sub.close();
        container.dispose();
        await tester.pump();

        // No explicit expect: the assertion is flutter_test's own end-of-test
        // pending-timer check. If the `onDispose` cancel is removed, the
        // 5-minute timer outlives the container and the test fails with
        // "A Timer is still pending even after the widget tree was disposed".
        expect(listCalls, 1);
      },
    );
  });

  // ==========================================================================
  // bookedDaysProvider — 30-minute keepAlive (perf P3).
  //
  // The heaviest request in the feature (a full ±180-day sweep), and the one
  // plain autoDispose re-issued on EVERY entry to «Мої записи» and every
  // return from a detail screen.
  // ==========================================================================
  group('bookedDaysProvider — 30-minute keepAlive', () {
    testWidgets(
      'returning WITHIN 30 minutes reuses the cached dot set — the ±180-day '
      'sweep is not re-issued',
      (tester) async {
        final container = buildContainer();

        final sub = container.listen(
          bookedDaysProvider,
          (_, _) {},
          fireImmediately: true,
        );
        await container.read(bookedDaysProvider.future);
        expect(railCalls, 1);

        sub.close();
        // fixed-wait-ok: fake-clock advance to 29min — inside the rail's
        // 30-minute TTL. A pump-until-condition cannot express "nothing has
        // happened yet", which is the property under test.
        await tester.pump(_railTtl - const Duration(minutes: 1));

        final sub2 = container.listen(
          bookedDaysProvider,
          (_, _) {},
          fireImmediately: true,
        );
        await tester.pump();

        expect(
          railCalls,
          1,
          reason:
              '29 minutes in, the rail must still be served from cache — this '
              'is the single heaviest request in the feature',
        );
        sub2.close();
        container.dispose();
      },
    );

    testWidgets(
      'the 30-minute link CLOSES — a later return refetches, which is what '
      'bounds the across-midnight window drift',
      (tester) async {
        final container = buildContainer();

        final sub = container.listen(
          bookedDaysProvider,
          (_, _) {},
          fireImmediately: true,
        );
        await container.read(bookedDaysProvider.future);
        expect(railCalls, 1);

        sub.close();
        // fixed-wait-ok: fake-clock advance past the rail's 30-minute TTL.
        await tester.pump(_railTtl + const Duration(minutes: 1));

        final sub2 = container.listen(
          bookedDaysProvider,
          (_, _) {},
          fireImmediately: true,
        );
        await container.read(bookedDaysProvider.future);

        expect(
          railCalls,
          2,
          reason:
              'the window is computed from DateTime.now() at build time, so '
              'an unbounded keepAlive would pin a stale ±180-day window for '
              'the whole session; the TTL is what bounds that drift',
        );
        sub2.close();
        container.dispose();
      },
    );

    testWidgets('disposing the rail early leaves no pending 30-minute timer', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [bookingRepositoryProvider.overrideWithValue(repo)],
      );
      final sub = container.listen(
        bookedDaysProvider,
        (_, _) {},
        fireImmediately: true,
      );
      await container.read(bookedDaysProvider.future);

      sub.close();
      container.dispose();
      await tester.pump();

      // As above: flutter_test's pending-timer teardown IS the assertion. A
      // leaked 30-minute timer is the longer-lived of the two and the more
      // likely to be observed as a "test hangs / timer still pending" flake
      // elsewhere in the suite.
      expect(railCalls, 1);
    });
  });

  // ==========================================================================
  // The two TTLs are deliberately DIFFERENT, and the difference is reasoned:
  // the list is a correctness surface (rows the master acts on), the rail is a
  // navigational hint (nothing is authorised off a dot). Collapsing them to
  // one number would either make the rail needlessly chatty or make the list
  // needlessly stale.
  // ==========================================================================
  test('the rail is cached SIX times longer than the list', () {
    expect(_railTtl.inMinutes, 30);
    expect(_listTtl.inMinutes, 5);
    expect(_railTtl.inMinutes ~/ _listTtl.inMinutes, 6);
  });
}
