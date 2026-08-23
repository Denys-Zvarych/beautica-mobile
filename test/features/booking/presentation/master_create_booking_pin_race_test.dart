// ITEM (this track, mobile-debugger) — the MISSED site. This class of
// `ProviderSubscription`-closed crash was fixed at FIVE sibling sites
// (`booking_calendar_invalidation.dart`'s FIX A/B/C/D + the reschedule FIX A)
// but `invalidateBookingViewsAfterBookingCreated` — the CREATE-path fan-out,
// the ONLY caller of which is `MasterCreateBookingNotifier.submit` — was
// allow-listed instead of fixed (`scripts/.keepalive_family_invalidation_allow`
// used to carry an entry for `booking_calendar_invalidation.dart:350`).
//
// WHY THE ALLOW-LIST ENTRY WAS WRONG
// -----------------------------------
// The stated reason was "the caller always fires while the day-calendar
// screen is COVERED by the full-screen booking wizard, and Riverpod 3 PAUSES
// a covered consumer rather than dropping its listener to zero". That is
// TRUE only for the ONE day the rail happens to be showing at submit time —
// its `Consumer` is paused, listener count stays > 0, no disposal race. It is
// FALSE for every OTHER day still pinned in `DayKeepAliveLru` (bounded to 3):
// a day the master glanced at earlier in the session, then scrubbed the rail
// away from, sits in the LRU with a keepAlive link and ZERO listeners — the
// exact precondition every sibling fix in this file protects against. This
// function's OLD body (`ref.invalidate(bookingsDayProvider);`, no query
// argument) is a BARE FAMILY invalidate: it calls `invalidateSelf()` on every
// currently-built member, including those pinned-but-unwatched ones, and
// races their queued disposal against the next rail-tap that re-subscribes.
//
// USER SYMPTOM THIS REPRODUCES
// -----------------------------
// Master adds a walk-in booking on a WORKING day D with no other bookings
// (empty result set — the shape this test drives). Opening D again after
// bouncing to another day (E) and back throws "Bad state: called
// ProviderSubscription.read on a subscription that was closed", or —
// silently absorbed by Flutter's per-`Element` error boundary — leaves D's
// skeleton stuck forever (one mechanism, two symptoms, per this file header's
// siblings).
//
// THE RECIPE (mirrors `booking_provider_close_pin_race_test.dart` /
// `bookings_discovery_view_reschedule_pin_race_test.dart` exactly, swapping
// in the CREATE-path invalidation as the trigger)
// -----------------------------------------------------------------------
//   1-2. Pin day D via the real `BookingsDiscoveryView` (visit D, tap over to
//        E) — D becomes pinned-but-unwatched.
//   3.   Cover with an opaque route (mirrors the full-screen wizard).
//   4.   Run the REAL `invalidateBookingViewsAfterBookingCreated(ref)` — the
//        EXACT function `MasterCreateBookingNotifier.submit` calls on
//        success — through a real `Ref` reached from the covering route.
//        Same extracted-function precedent both sibling test files already
//        use, for the same reason: `booking_provider_close_pin_race_test
//        .dart` drives `invalidateBookingViewsAfterProviderClose` directly
//        rather than the full decline-dialog flow, "to duplicate that
//        screen's own (already covered elsewhere) test surface for no
//        additional proof of THIS mechanism".
//
//        Getting a real `Ref` (not `WidgetRef` — this function's signature
//        deliberately differs from its two `WidgetRef`-taking siblings; see
//        its own doc, "Takes a provider-side `Ref`, not a `WidgetRef`,
//        because its caller is a Notifier") needs one extra step: a tiny
//        `Provider<void Function()>` captures its own `Ref` and closes over
//        the SAME function reference, so the button below still calls the
//        literal production function, just reached via `ref.read(...)`
//        instead of `ref` itself.
//
//        TRIED AND REJECTED: driving the actual `MasterCreateBookingNotifier
//        .submit(...)` end-to-end (via `ref.read(masterCreateBookingProvider
//        .notifier).submit(...)`), even with a `SynchronousFuture`-returning
//        mock (so the mocked network call introduces no real microtask
//        delay). That still did NOT reproduce the crash in this harness —
//        `AsyncValue.guard`'s own try/catch plumbing and the `AsyncNotifier`
//        `state = ...` machinery add enough extra pump/microtask cycles
//        that, in the FAKE-clock test binding, the queued zero-duration
//        disposal `Timer` for D consistently finishes firing (a clean,
//        non-racy disposal-then-fresh-rebuild) before this test's
//        `reestablishWatch()` ever runs — verified empirically: a throwaway
//        diagnostic copy of this file, differing ONLY in going through
//        `submit()` instead of the direct call, passed green against the
//        UNFIXED (bare-invalidate) production code on this same day. That is
//        a property of how many pump ticks intervene before the race check,
//        not evidence the CREATE path is actually safe — the direct call
//        below reproduces the exact same underlying defect deterministically
//        against the unfixed code (confirmed: RED with the real "Bad state:
//        called ProviderSubscription.read on a subscription that was
//        closed" before the fix below existed), and the fix targets the
//        function itself, not any one caller's timing.
//   5.   Pop back.
//   6.   Re-tap D's rail chip.
//   7.   Assert NO `FlutterError`, and D resolves to a data/empty state
//        within a bounded pump budget — never `pumpAndSettle`.
//
// Day D is stubbed to return ZERO bookings throughout (the user's exact
// shape: "a WORKING date that has NO other bookings") — the empty-result
// path is asserted explicitly via `master-bookings-empty`, not merely "some
// non-error state", since an empty result set can take a different code path
// than a non-empty one inside `BookingsDiscoveryView`/`BookingsDayState`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/application/booked_days_notifier.dart';
import 'package:beautica_mobile/features/booking/application/booking_calendar_invalidation.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/bookings_day_query.dart';
import 'package:beautica_mobile/features/booking/presentation/bookings_discovery_view.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_day_rail.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';

import '../../../helpers/keepalive_pin_race_harness.dart';
import '../../../helpers/pump_app.dart';

class _MockBookingRepository extends Mock implements BookingRepository {}

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
}

class _StubAuth extends AuthNotifier {
  @override
  Future<AuthSession> build() async => const AuthSession.authenticated(
    user: User(
      id: 'master-1',
      email: 'master1@beautica.ua',
      role: UserRole.independentMaster,
    ),
    accessToken: 't',
  );
}

// Same pinned-clock convention as both siblings — mixing a bare
// `DateTime.now()` fixture with a pinned `clockProvider` is the recurring
// timezone defect in this repo (invisible on a Kyiv-zoned dev host).
//
// FIXED, not `futureBookingStart()` (mobile-debugger, this track,
// 2026-08-24). `futureBookingStart()` is `DateTime.now().toUtc().add(30
// days)`, so `_dayD` — and therefore `dayChipKey(_dayD)`'s render geometry —
// silently changed every calendar day the suite happened to run on. That
// went CI-red on 2026-08-23 for a date-shaped reason having nothing to do
// with this file's own code: `reselectD`'s tap landed on a chip whose
// GestureDetector had not yet repainted to its settled post-pop position
// (see `reselectD`'s own doc for the mechanism) — `getCenter` derived an
// off-screen offset purely because that day's rail geometry happened to
// place D's chip near enough the viewport's left edge. A fixed PAST literal
// (unlike a future one) never needs `// future-date-ok:` — this file's own
// bookings are never read through `BookingDisplayX.isPast` (day D is stubbed
// with ZERO bookings throughout), so there is no "elapses and flips a
// real assertion" hazard `scripts/forbid_stale_future_date_fixture.sh`
// exists to catch; only [_dayD]'s CALENDAR identity matters here, not its
// distance from the real clock.
final DateTime _fixedNow = DateTime.utc(2024, 3, 12, 9);
final DateTime _dayD = kyivToday(() => _fixedNow);
final DateTime _dayE = () {
  final DateTime monday = mondayOf(_dayD);
  return monday.isAtSameMomentAs(_dayD)
      ? monday.add(const Duration(days: 1))
      : monday;
}();

/// Captures a real `Ref` (not `WidgetRef`) purely so the covering route's
/// button can invoke the literal production
/// [invalidateBookingViewsAfterBookingCreated] — see the file header's
/// "Getting a real `Ref`" note.
final Provider<void Function()> _runInvalidationProvider =
    Provider<void Function()>(
      (Ref ref) =>
          () => invalidateBookingViewsAfterBookingCreated(ref),
    );

GoRouter _router() => GoRouter(
  initialLocation: '/day',
  routes: <RouteBase>[
    GoRoute(
      path: '/day',
      builder: (BuildContext context, GoRouterState state) => Scaffold(
        body: BookingsDiscoveryView(
          query: BookingsDayQuery.of(day: _dayD),
          title: 'Мої записи',
          onBookingTap: (Booking _) {},
        ),
      ),
    ),
    // Opaque and full-screen — mirrors the master «Новий запис» wizard
    // covering the day list for the whole submit, and where this test
    // performs the EXACT create-path invalidation via a real `Ref`.
    GoRoute(
      path: '/create',
      builder: (BuildContext context, GoRouterState state) => Scaffold(
        body: Consumer(
          builder: (BuildContext context, WidgetRef ref, _) => Center(
            child: TextButton(
              key: const Key('run-booking-created-invalidation'),
              onPressed: () => ref.read(_runInvalidationProvider)(),
              child: const Text('submit'),
            ),
          ),
        ),
      ),
    ),
  ],
);

void main() {
  setUpAll(() {
    initBeauticaTimeZones();
    registerFallbackValue(<BookingStatus>{});
    registerFallbackValue(BookingSort.oldest);
  });

  late _MockBookingRepository repo;

  setUp(() {
    repo = _MockBookingRepository();
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
      // The user's exact shape: day D has ZERO other bookings. An empty
      // result set can take a different code path than a non-empty one, so
      // this is asserted explicitly (`master-bookings-empty`), not just "not
      // an error".
    ).thenAnswer(
      (_) async => const PageResponse<Booking>(
        items: <Booking>[],
        page: 0,
        totalPages: 1,
        totalElements: 0,
      ),
    );
  });

  /// Steps 1-2: pump the day list on D, tap over to E (D becomes
  /// pinned-but-unwatched via `DayKeepAliveLru`).
  Future<GoRouter> pinD(WidgetTester tester) async {
    final GoRouter router = _router();
    await tester.pumpRoutedApp(
      router,
      overrides: <Object>[
        screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
        bookingRepositoryProvider.overrideWithValue(repo),
        bookedDaysProvider.overrideWith((ref) async => <DateTime>{}),
        clockProvider.overrideWithValue(() => _fixedNow),
        authProvider.overrideWith(_StubAuth.new),
      ],
    );
    await tester.pumpUntilGone(
      find.byKey(const Key('master-bookings-skeleton')),
    );
    expect(
      find.byKey(const Key('master-bookings-empty')),
      findsOneWidget,
      reason: 'sanity: D loaded to an empty (not error/skeleton) state',
    );

    await tester.tap(find.byKey(dayChipKey(_dayE)));
    // fixed-wait-ok: waits out the REAL 220ms rail-tap debounce timer.
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pumpUntilGone(
      find.byKey(const Key('master-bookings-skeleton')),
    );
    expect(
      find.byKey(const Key('master-bookings-empty')),
      findsOneWidget,
      reason: 'sanity: E loaded — D is now unwatched, not merely paused',
    );

    return router;
  }

  /// Step 6: re-tap D's rail chip and wait out the real debounce.
  ///
  /// The leading `pump(300ms)` (mobile-debugger, this track, 2026-08-24) is
  /// NOT a debounce wait — it settles the POP itself before touching
  /// anything. `expectKeepAlivePinRaceClosed`'s step 5 pops with exactly ONE
  /// zero-duration `pump()` (deliberately, to avoid ever pumping while the
  /// day list's skeleton might be up), which is not enough real time for the
  /// revealed route's own transition (go_router's default `MaterialPage`,
  /// platform default 300ms) to finish — the day rail's `PageView` was still
  /// mid-transition, painted at a stale scroll offset, when `tap()` computed
  /// the chip's hit-test centre from that stale geometry. Confirmed
  /// empirically: with this pump absent, `dayChipKey(_dayD)` resolved to an
  /// off-screen `Offset` for a chip sitting on the LEFT edge of its rail week
  /// (Monday/Tuesday) — a small, otherwise-easy-to-miss geometry error, since
  /// every chip further right just landed a few dozen px off centre and
  /// still hit-tested fine. Safe to pump here specifically (unlike almost
  /// everywhere else in this recipe): the day list is showing E's already-
  /// resolved EMPTY state at this point, not a skeleton, so there is no
  /// repeating shimmer animation for a longer pump to get stuck behind.
  Future<void> reselectD(WidgetTester tester) async {
    // fixed-wait-ok: waits out go_router's default MaterialPage pop
    // transition (platform default 300ms) so the day rail settles to its
    // real post-pop geometry before this tap computes a hit-test centre.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(dayChipKey(_dayD)));
    // fixed-wait-ok: waits out the same real 220ms rail-tap debounce.
    await tester.pump(const Duration(milliseconds: 260));
  }

  testWidgets(
    'the CREATE-path fan-out (invalidateBookingViewsAfterBookingCreated), '
    'run from a DIFFERENT (wizard-shaped) route while D is '
    'pinned-but-unwatched, then re-selecting D on the rail after popping '
    'back, throws NO FlutterError and reaches a data/empty state within a '
    'bounded pump budget',
    (tester) async {
      final GoRouter router = await pinD(tester);

      await expectKeepAlivePinRaceClosed(
        tester,
        router,
        coverRouteKey: '/create',
        invalidate: () => tester.tap(
          find.byKey(const Key('run-booking-created-invalidation')),
        ),
        reestablishWatch: () => reselectD(tester),
        loadingFinder: find.byKey(const Key('master-bookings-skeleton')),
        resolvedFinder: find.byKey(const Key('master-bookings-empty')),
      );

      expect(find.byKey(const Key('my_bookings_error')), findsNothing);
    },
  );
}
