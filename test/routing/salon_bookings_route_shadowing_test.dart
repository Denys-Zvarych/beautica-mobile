// Phase 250 — pins the RESOLVED screen TYPE for `/salon/bookings/new`, not
// merely that SOME `GoRoute` in the tree happens to carry a matching `path`
// string. Mirrors `test/routing/master_bookings_route_shadowing_test.dart`'s
// own rationale exactly — see that file's header for the full falsification
// story (commenting out the literal route left the OLD suite green because
// `:bookingId` silently absorbed the path).
//
// ## THE DYNAMIC SIBLING ARRIVED — Phase 21.12 (QA)
//
// This header used to say `/salon/bookings/new` had no dynamic sibling to be
// shadowed BY, and that the pair-case would be needed "the moment a future
// phase adds a dynamic `/salon/bookings/:bookingId`". That phase is this one:
// the salon «Записи» board's drill-in needed an OWNER-gated detail route,
// because `RouteNames.bookingDetail` (`/bookings/:id`) is CLIENT-gated in
// `auth_redirect.dart` and bounces a SALON_OWNER to their role home.
//
// So the second case promised above is now written, exactly as promised: the
// `:bookingId` route matches `/salon/bookings/new` perfectly happily with
// `bookingId == 'new'`, and NOTHING BUT DECLARATION ORDER stops it. Both
// cases assert the resolved page TYPE, never the location string — a path
// assertion passes while the wrong screen renders.
//
// MUTATION-VERIFIED (Phase 21.12, QA) — SWAPPING the declaration order of
// the two `GoRoute`s in `app_router.dart` (registering `:bookingId` BEFORE
// `new`) turns the `new` case RED: `/salon/bookings/new` then resolves to
// `BookingDetailScreen` with `bookingId == 'new'` and
// `find.byType(SalonCreateBookingScreen)` reports zero matches, while the
// detail case stays green. Restoring the order turns it back GREEN. This is
// the falsification the old header said could not be performed yet.
//
// MUTATION-VERIFIED (see phase-250 report) — commenting out the
// `/salon/bookings/new` `GoRoute` in `app_router.dart` turns this test RED:
// `router.go(RouteNames.salonStaffBookingNew, extra: ...)` then resolves
// nothing under that path (go_router has no other route claiming that exact
// three-segment literal), and `find.byType(SalonCreateBookingScreen)`
// reports zero matches. Restoring the route turns it back GREEN.

import 'package:beautica_mobile/core/app_start_time.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/application/salon_master_coverage_notifier.dart';
import 'package:beautica_mobile/features/booking/application/salon_masters_roster_notifier.dart';
import 'dart:async';

import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_create_booking_screen.dart';
import 'package:beautica_mobile/features/salon/application/my_salons_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_service_catalog_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:beautica_mobile/routing/auth_redirect.dart';
import 'package:beautica_mobile/routing/role_home.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/fakes/fake_auth_repository.dart';
import '../helpers/fakes/fake_secure_storage.dart';

// ---------------------------------------------------------------------------
// Fixtures — mirrors master_bookings_route_shadowing_test.dart's own.
// ---------------------------------------------------------------------------

const _fakeSalonOwner = User(
  id: 'owner-1',
  email: 'owner@example.com',
  role: UserRole.salonOwner,
  firstName: 'Настя',
  lastName: 'Салон',
);

const _authenticatedSalonOwnerSession = AsyncData<AuthSession>(
  AuthSession.authenticated(user: _fakeSalonOwner, accessToken: 'token'),
);

class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier(this._fixed);

  final AsyncValue<AuthSession> _fixed;

  @override
  Future<AuthSession> build() async {
    state = _fixed;
    return _fixed.value ?? const AuthSession.unauthenticated();
  }
}

/// [MySalons] stub that resolves immediately to an empty list. `mySalonsProvider`
/// is now `@Riverpod(keepAlive: true)` (mobile-perf HIGH follow-up,
/// 2026-08-28), so the plain `mySalonsProvider.overrideWith((ref) async =>
/// ...)` function override this file previously used no longer type-checks —
/// a keepAlive-class provider's `overrideWith` takes a notifier FACTORY, not
/// a build function.
class _SettledMySalons extends MySalons {
  @override
  Future<List<Salon>> build() async => const <Salon>[];
}

/// `getBookingById` never completes; every other member is unreachable from
/// this route. A PENDING read keeps `BookingDetailScreen` in its loading
/// branch, which is all this test needs: it asserts WHICH SCREEN RESOLVED,
/// never what that screen renders. A failing stub was tried first and is
/// wrong — the detail provider surfaces the error during element mounting,
/// which fails the test for a reason that has nothing to do with routing.
class _PendingBookingRepository implements BookingRepository {
  @override
  Future<Booking> getBookingById(String bookingId) =>
      Completer<Booking>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('unreachable from /salon/bookings/:bookingId');
}

class _RouterApp extends StatelessWidget {
  const _RouterApp({required this.router});

  final GoRouter router;

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    routerConfig: router,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('uk', 'UA'),
  );
}

void main() {
  group('app_router — /salon/bookings/new resolves its OWN screen', () {
    setUp(
      () => AppStartTime.setStartForTest(
        DateTime.now().subtract(const Duration(seconds: 5)),
      ),
    );
    tearDown(AppStartTime.resetForTest);

    ProviderContainer makeContainer({
      Duration? Function(int, Object)? retry = beauticaProviderRetry,
      List<Object> extra = const <Object>[],
    }) {
      final container = ProviderContainer(
        retry: retry,
        overrides: <Object>[
          ...extra,
          authProvider.overrideWith(
            () => _FixedAuthNotifier(_authenticatedSalonOwnerSession),
          ),
          authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
          secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
          // The screen's own data — never needs to SETTLE for this test
          // (which only asserts the resolved WIDGET TYPE), but must not
          // throw synchronously while building the provider graph.
          salonMastersRosterProvider.overrideWith((ref, salonId) async => []),
          salonMasterServiceCoverageProvider.overrideWith(
            (ref, args) async => {},
          ),
          salonServiceCatalogProvider.overrideWith((ref, salonId) async => []),
          // Phase 21.1 follow-up — the authenticated SALON_OWNER session's
          // global redirect (isAuthenticated + isAtSplash -> roleHomePath)
          // resolves to RouteNames.mySalons before this test's own
          // router.go() navigates away, momentarily mounting MySalonsScreen.
          // Settling mySalonsProvider keeps that transient mount off the
          // real Dio-backed salonRepositoryProvider (leaked-timer
          // regression — same shape every other override in this file
          // guards against).
          mySalonsProvider.overrideWith(_SettledMySalons.new),
        ].cast(),
      );
      addTearDown(container.dispose);
      return container;
    }

    testWidgets('/salon/bookings/new resolves SalonCreateBookingScreen', (
      tester,
    ) async {
      final container = makeContainer();
      final router = container.read(appRouterProvider);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _RouterApp(router: router),
        ),
      );
      await tester.pump();

      router.go(RouteNames.salonStaffBookingNew, extra: 'salon-1');
      await tester.pump();
      await tester.pump();

      expect(
        find.byType(SalonCreateBookingScreen),
        findsOneWidget,
        reason:
            'the route must resolve to the SALON wizard, not the home '
            'shell fallback (a missing/misrouted `new` segment) or any '
            'other screen, and NOT BookingDetailScreen with '
            "bookingId == 'new' — which is exactly what the dynamic sibling "
            'resolves to if it is ever declared first',
      );
      // The other half of the same claim: the wizard won, so the DETAIL
      // screen must not be anywhere in the tree.
      expect(find.byType(BookingDetailScreen), findsNothing);
    });

    // Phase 21.12 (QA) — the dynamic sibling's own pin. Without a registered
    // `/salon/bookings/:bookingId`, the salon board's drill-in had nowhere
    // OWNER-gated to land: `RouteNames.bookingDetail` resolves to
    // `/bookings/:id`, which `auth_redirect.dart` reserves for CLIENT.
    testWidgets('/salon/bookings/:bookingId resolves BookingDetailScreen', (
      tester,
    ) async {
      // `BookingDetailScreen` mounts its OWN provider graph, which reaches
      // the real Dio-backed `bookingRepositoryProvider` and leaves a pending
      // retry timer after the tree is disposed. Stubbed to a settled failure
      // with the retry policy OFF: this test asserts WHICH SCREEN RESOLVES,
      // not what that screen then renders, and the error branch is a page
      // like any other.
      final container = makeContainer(
        retry: (_, _) => null,
        extra: <Object>[
          bookingRepositoryProvider.overrideWithValue(
            _PendingBookingRepository(),
          ),
        ],
      );
      final router = container.read(appRouterProvider);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _RouterApp(router: router),
        ),
      );
      await tester.pump();

      router.go(RouteNames.salonStaffBookingDetail('bk-1'));
      await tester.pump();
      await tester.pump();

      expect(
        find.byType(BookingDetailScreen),
        findsOneWidget,
        reason:
            'an owner drilling in from the salon «Записи» board must reach '
            'the detail screen under the /salon/* prefix, which the '
            'SALON_OWNER/SALON_ADMIN gate admits',
      );
      expect(find.byType(SalonCreateBookingScreen), findsNothing);
    });

    // ── The salonId HANDOFF over `extra` (2026-09-19, mobile-qa re-audit) ──
    //
    // `salon_bookings_screen.dart:548` pushes this route with
    // `extra: widget.salonId`, and `app_router.dart` folds `state.extra` into
    // `BookingDetailScreen.salonId`; the screen then threads it into
    // `invalidateBookingViewsAfterProviderClose` / ...ItemReschedule so the
    // board's rail dot drops with the list.
    //
    // NOTHING pinned that seam. `booking_calendar_invalidation_test.dart`
    // proves the helpers drop the right member WHEN HANDED a salonId, but a
    // push that dropped `extra:`, or a router that stopped reading it, would
    // leave every one of those tests green while the dot went stale again —
    // the identical hole PASS A was written to close on the wizard side.
    //
    // The assertion reads the resolved screen's `salonId`, which is the only
    // observable this seam HAS: the router's whole job here is argument
    // construction, and a null vs non-null salonId renders identically.
    Future<BookingDetailScreen> pushDetail(
      WidgetTester tester, {
      required Object? extraArg,
    }) async {
      final container = makeContainer(
        retry: (_, _) => null,
        extra: <Object>[
          bookingRepositoryProvider.overrideWithValue(
            _PendingBookingRepository(),
          ),
        ],
      );
      final router = container.read(appRouterProvider);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _RouterApp(router: router),
        ),
      );
      await tester.pump();

      // `push`, not `go` — the production call site is a push, and the two
      // do not populate the same `GoRouterState` fields.
      unawaited(
        router.push(
          RouteNames.salonStaffBookingDetail('bk-1'),
          extra: extraArg,
        ),
      );
      await tester.pump();
      await tester.pump();

      return tester.widget<BookingDetailScreen>(
        find.byType(BookingDetailScreen),
      );
    }

    testWidgets('/salon/bookings/:bookingId carries the board\'s salonId '
        'through `extra` onto the resolved BookingDetailScreen', (
      tester,
    ) async {
      final BookingDetailScreen screen = await pushDetail(
        tester,
        extraArg: 'salon-1',
      );

      expect(
        screen.salonId,
        'salon-1',
        reason:
            'without this the close/reschedule fan-out runs with a null '
            'salonId and salonBookedDaysProvider is never dropped — the '
            'board\'s rail dot then stays lit for the full 30-minute '
            'keepAlive TTL, which is the bug this track fixed',
      );
    });

    testWidgets('the SAME route reached with no `extra` resolves a NULL '
        'salonId rather than throwing — the /master/* and deep-link mounts', (
      tester,
    ) async {
      final BookingDetailScreen screen = await pushDetail(
        tester,
        extraArg: null,
      );

      expect(screen.salonId, isNull);
    });

    testWidgets('a NON-String `extra` is ignored, not cast-thrown — the '
        'switch must degrade to null', (tester) async {
      final BookingDetailScreen screen = await pushDetail(
        tester,
        extraArg: const <String, String>{'salonId': 'salon-1'},
      );

      expect(
        screen.salonId,
        isNull,
        reason:
            '`extra` is untyped; a future caller passing an args object down '
            'this route must not crash the detail screen',
      );
    });

    // The gate itself, as a pure decision — this is WHY the route above had
    // to exist, and it is the assertion that fails if anyone ever "simplifies"
    // the board back onto `RouteNames.bookingDetail`.
    test('the CLIENT-gated /bookings/:id BOUNCES a SALON_OWNER, while '
        '/salon/bookings/:id admits them', () {
      expect(
        authRedirectForLocation(
          _authenticatedSalonOwnerSession,
          RouteNames.bookingDetail('bk-1'),
        ),
        equals(roleHomePath(UserRole.salonOwner)),
        reason:
            '/bookings is a clientBranchPrefix — a non-CLIENT role that '
            'reaches it is redirected to its own role home, i.e. bounced '
            'clean out of the salon shell',
      );
      expect(
        authRedirectForLocation(
          _authenticatedSalonOwnerSession,
          RouteNames.salonStaffBookingDetail('bk-1'),
        ),
        isNull,
        reason: 'the /salon/* gate admits SALON_OWNER and SALON_ADMIN',
      );
      expect(
        authRedirectForLocation(
          _authenticatedSalonOwnerSession,
          RouteNames.masterBookingDetail('bk-1'),
        ),
        equals(roleHomePath(UserRole.salonOwner)),
        reason:
            '/master/* is INDEPENDENT_MASTER-only, so it was never an option '
            'for this board either',
      );
    });
  });
}

// Role-gate coverage (SALON_OWNER/SALON_ADMIN-only for `/salon/*`) lives as
// pure `authRedirectForLocation` cases in `test/routing/auth_redirect_test
// .dart`, mirroring that file's own `/master/working-hours` role-gate group
// — a widget-pumped variant here would additionally need to settle the
// CLIENT home shell's own unrelated provider graph (bottom-nav tiles, etc.)
// just to prove a redirect this file has no other reason to touch.
