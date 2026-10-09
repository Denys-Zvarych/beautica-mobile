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
// ## THE THIRD SIBLING — Phase 344
//
// `/salon/bookings/archive` joins `new` as a second literal above the same
// dynamic `:bookingId`. The equivalent mutation is recorded beside its own
// group below rather than as a second convention here: MOVING the `archive`
// `GoRoute` below `:bookingId` turns that case RED, and DELETING its `extra`
// redirect turns the missing-`extra` case RED. Both were run.
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
import 'package:beautica_mobile/features/salon/application/salon_staff_masters_roster.dart';
import 'dart:async';

import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_partition.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/master_archive_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_create_booking_screen.dart';
import 'package:dio/dio.dart';
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

import '../helpers/fake_salon_master_coverage.dart';
import '../helpers/fake_salon_staff_masters_roster.dart';
import '../helpers/fakes/fake_auth_repository.dart';
import '../helpers/fakes/fake_secure_storage.dart';
import '../helpers/test_container.dart';

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

  /// Phase 344 — the SAME never-completing discipline for the `archive`
  /// sibling: [MasterArchiveScreen] mounted on the salon scope reads
  /// `masterArchiveProvider`, whose one salon arm is this call. A pending read
  /// parks the screen in its skeleton branch, which is all these tests need —
  /// they assert WHICH SCREEN RESOLVED, never what it renders.
  @override
  Future<PageResponse<Booking>> getSalonBookings({
    required String salonId,
    DateTime? from,
    DateTime? to,
    String? masterId,
    Iterable<BookingStatus>? statuses,
    BookingPartition? partition,
    required int page,
    int size = kBookingsPageSize,
    BookingSort? sort,
    CancelToken? cancelToken,
  }) => Completer<PageResponse<Booking>>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'unreachable from /salon/bookings/{archive,:bookingId}',
  );
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
      final container = makeTestContainer(
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
          salonStaffMastersRosterProvider.overrideWith(
            () => FakeSalonStaffMastersRoster(() => []),
          ),
          salonMasterServiceCoverageProvider.overrideWith(
            () => FakeSalonMasterServiceCoverage(
              () => salonCoverageOf(<String, Map<String, String>>{}),
            ),
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
        ],
      );
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

    // ══════════════════════════════════════════════════════════════════════
    // Phase 344 — the THIRD sibling under `/salon/bookings`.
    //
    // `archive` is a second literal joining `new` above the dynamic
    // `:bookingId`. `/salon/bookings/:bookingId` matches
    // `/salon/bookings/archive` perfectly happily with
    // `bookingId == 'archive'`, and nothing but declaration order stops it —
    // shadowed, the owner's «Архів» tap would land on a `BookingDetailScreen`
    // fetching a booking literally called "archive" and failing like a
    // backend problem.
    //
    // MUTATION RECIPE (extend the header's own two, do not write a second
    // convention):
    //   * MOVE the `archive` `GoRoute` in `app_router.dart` BELOW the
    //     `:bookingId` route  ⇒  the case below goes RED
    //     (`find.byType(MasterArchiveScreen)` reports zero matches and
    //     `BookingDetailScreen` is found instead). This is the load-bearing
    //     one: if it stays green the test is asserting a location string.
    //   * DELETE the route's `extra` redirect  ⇒  the missing-`extra` case
    //     goes RED (the route renders instead of bouncing — in fact it throws
    //     on `state.extra! as String`).
    // ══════════════════════════════════════════════════════════════════════
    testWidgets('/salon/bookings/archive resolves MasterArchiveScreen, NOT '
        'BookingDetailScreen with bookingId == "archive"', (tester) async {
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

      router.go(RouteNames.salonStaffBookingsArchive, extra: 'salon-1');
      await tester.pump();
      await tester.pump();

      expect(
        find.byType(MasterArchiveScreen),
        findsOneWidget,
        reason:
            'the literal `archive` must win over the dynamic `:bookingId` '
            'sibling — and only its DECLARATION ORDER in app_router.dart '
            'makes that true',
      );
      // The other half of the same claim, stated as a TYPE (a location
      // assertion passes while the wrong screen renders).
      expect(find.byType(BookingDetailScreen), findsNothing);
      expect(find.byType(SalonCreateBookingScreen), findsNothing);
    });

    testWidgets('the salon archive mount is SALON-SCOPED and drops the '
        '«Послуга» facet — the flags the route must pass', (tester) async {
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

      router.go(RouteNames.salonStaffBookingsArchive, extra: 'salon-1');
      await tester.pump();
      await tester.pump();

      final MasterArchiveScreen screen = tester.widget<MasterArchiveScreen>(
        find.byType(MasterArchiveScreen),
      );

      expect(
        screen.salonId,
        'salon-1',
        reason:
            'the board pushes its own salon id on `extra`; dropped, this '
            'mount would silently read the OWNER\'S OWN "mine" archive '
            '(GET /bookings/me) while claiming to be the salon\'s',
      );
      expect(
        screen.showServiceFilter,
        isFalse,
        reason:
            'phase 343 D1 keeps this flag INDEPENDENT of `salonId`, and it '
            'defaults to TRUE. Omitted at the route, a ticked service would '
            'build a salon-scoped MasterArchiveQuery.of with non-empty '
            'serviceIds, which that factory rejects with an ArgumentError '
            'thrown from build. An owner\'s catalogue happening to resolve '
            'empty today is a coincidence, not the contract',
      );
      expect(
        screen.showMasterAttribution,
        isTrue,
        reason:
            'every row here belongs to a DIFFERENT master, so "who performed '
            'it" is the row\'s first unanswered question',
      );

      // ── THE TWO ROUTE BUILDERS (mobile-qa, phase 344) ──────────────────
      //
      // Added because nothing observed them: the route passes FIVE
      // arguments and this test checked three. Both default to `null`, and
      // `null` is not inert — `MasterArchiveScreen._openDetail` /
      // `_openReview` fall back to `RouteNames.masterBookingDetail` and
      // `RouteNames.masterClientReview`, both under the
      // INDEPENDENT_MASTER-only `/master/*` gate, which ejects an owner from
      // the salon shell to `/salons/mine`. That is the same shape as the
      // phase-21.12 board bug.
      //
      // The DETAIL half is additionally driven end to end (a real row tap,
      // through the real `auth_redirect.dart` gate) in
      // `integration_test/salon_owner_bookings_board_flow_test.dart`'s
      // phase-344 arm. The REVIEW half cannot be: the salon board's fixture
      // rows hardcode `providerCanReviewClient: false` — the only value the
      // real server returns for a viewer who is not the performing master —
      // so the «Відгук» CTA is correctly never offered to an owner there.
      // A function identity check is therefore the strongest honest pin
      // available for it.
      expect(
        screen.detailRouteBuilder,
        same(RouteNames.salonStaffBookingDetail),
      );
      expect(
        screen.reviewRouteBuilder,
        same(RouteNames.salonStaffClientReview),
      );
      // …and NOT the `/master/*` fallbacks the null default resolves to.
      expect(
        screen.detailRouteBuilder,
        isNot(same(RouteNames.masterBookingDetail)),
      );
      expect(screen.detailRouteBuilder, isNotNull);
      expect(screen.reviewRouteBuilder, isNotNull);
      // Phase 383 — the salon id is forwarded to `/salon/bookings/:id` as
      // `extra`; that path holds no salon id, so null here means an
      // archive-opened detail never drops this salon's board dots. The row
      // tap itself is driven end to end in
      // `integration_test/salon_owner_bookings_board_flow_test.dart`.
      expect(
        screen.detailExtra,
        'salon-1',
        reason: 'the archive must forward its salon id to the detail push',
      );
    });

    testWidgets('the salon archive AppBar reuses masterArchiveTitle («Архів») '
        '— phase 344 D6 adds ZERO new ARB keys', (tester) async {
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

      router.go(RouteNames.salonStaffBookingsArchive, extra: 'salon-1');
      await tester.pump();
      await tester.pump();

      final BuildContext context = tester.element(
        find.byType(MasterArchiveScreen),
      );
      final String expected = AppLocalizations.of(context).masterArchiveTitle;

      // The REUSE claim, positively stated — not merely "no failure". If a
      // future phase introduces a distinct «Архів салону» string, this goes
      // RED and `page_title_consistency_test.dart`'s ledger must be updated
      // with it.
      expect(expected, 'Архів');
      expect(find.text(expected), findsWidgets);
    });

    testWidgets('/salon/bookings/archive reached with NO `extra` REDIRECTS to '
        'the role home instead of rendering an unscoped archive', (
      tester,
    ) async {
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

      // A cold deep link: `extra` does not survive one, which is the accepted
      // consequence of D2's `extra`-carries-the-salon-id contract. It must
      // BOUNCE, never crash on `state.extra! as String`.
      router.go(RouteNames.salonStaffBookingsArchive);
      await tester.pump();
      await tester.pump();

      expect(find.byType(MasterArchiveScreen), findsNothing);
      expect(find.byType(BookingDetailScreen), findsNothing);
      expect(
        router.state.matchedLocation,
        equals(roleHomePath(UserRole.salonOwner)),
      );
    });

    // The three arms above drive the redirect with `router.go`. Production
    // reaches this route with `context.push` ONLY
    // (`salon_bookings_screen.dart:810`), and `push` takes a materially
    // different path through go_router: `RouteMatchList.push` grafts a nested
    // `ImperativeRouteMatch` onto the EXISTING match list instead of
    // replacing it, and a redirect returned during that graft has to unwind a
    // push rather than a go. Pinning only the `go` shape would leave the one
    // call shape that actually ships unproven — and the user-visible question
    // («does a cold link-in bounce the owner somewhere sane, or does
    // `state.extra! as String` throw?») is a question about `push`.
    testWidgets('the PUSH shape production actually uses bounces too — a cold '
        '`context.push` with no `extra` lands the owner on their role home '
        'and throws nothing', (tester) async {
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

      // The router's OWN navigator context — the same one
      // `SalonBookingsScreen`'s `context.push` resolves against. A context
      // taken from above `MaterialApp.router` would reach a different
      // (root) `GoRouter` inherited widget and prove nothing about this one.
      final BuildContext navContext =
          router.routerDelegate.navigatorKey.currentContext!;
      // `unawaited`: the push future completes only when the pushed route
      // is POPPED, which never happens here — the redirect resolves it away.
      unawaited(navContext.push(RouteNames.salonStaffBookingsArchive));
      await tester.pump();
      await tester.pump();

      // NOT A CRASH is half the assertion: without the redirect,
      // `state.extra! as String` is a null-check on `null` thrown from
      // `builder`, which surfaces as a red screen, not as a bounce.
      expect(tester.takeException(), isNull);
      expect(find.byType(MasterArchiveScreen), findsNothing);
      // And not the SHADOWED alternative either — a `:bookingId` match on
      // the literal `archive` would render a detail screen fetching booking
      // `'archive'`, which reads to a user as a backend fault.
      expect(find.byType(BookingDetailScreen), findsNothing);
      // ⚠ THE RESOLVED LOCATION DIFFERS FROM THE `go` ARM, and that is a
      // real observation about `push`, not a weaker assertion. `go` replaces
      // the match list, so `matchedLocation` reports the redirect's own
      // target (`roleHomePath` = `/salons/home`). `push` grafts onto the
      // EXISTING list, so what surfaces is the owner's already-resolved home
      // leaf — `/salons/home` redirects onward into the salon shell, whose
      // branch root is `/salons/mine`. Either way the owner is on their own
      // home surface and NOT on the archive; the path string is asserted
      // exactly rather than by prefix so a future redirect change cannot
      // slide past this.
      expect(router.state.matchedLocation, equals(RouteNames.mySalons));
      expect(
        router.state.matchedLocation,
        isNot(equals(RouteNames.salonStaffBookingsArchive)),
      );
    });

    testWidgets('an EMPTY-string `extra` redirects too — `isEmpty` is half of '
        'the copied guard, not decoration', (tester) async {
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

      router.go(RouteNames.salonStaffBookingsArchive, extra: '');
      await tester.pump();
      await tester.pump();

      expect(find.byType(MasterArchiveScreen), findsNothing);
      expect(
        router.state.matchedLocation,
        equals(roleHomePath(UserRole.salonOwner)),
      );
    });

    testWidgets('a NON-String `extra` redirects rather than cast-throwing', (
      tester,
    ) async {
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

      router.go(
        RouteNames.salonStaffBookingsArchive,
        extra: const <String, String>{'salonId': 'salon-1'},
      );
      await tester.pump();
      await tester.pump();

      expect(find.byType(MasterArchiveScreen), findsNothing);
      expect(
        router.state.matchedLocation,
        equals(roleHomePath(UserRole.salonOwner)),
      );
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

    // Phase 344 D4 — the archive route's role gate, as a pure decision.
    //
    // `mobile-backlog.md:118` (2026-08-16) warned that the salon-archive
    // phase must not widen `/master/*` to admit SALON_MASTER, because the
    // archive offers a «Виконано» button that would 403 on tap for that role.
    // The hazard is avoided BY CONSTRUCTION, not mitigated: the new route
    // lives under `/salon/*`, whose EXISTING prefix gate (added by phase 250
    // for `/salon/bookings/new`) already admits exactly SALON_OWNER and
    // SALON_ADMIN. These arms verify that the gate is a PREFIX match and not
    // an exact-path list — an exact-path list would let the new literal
    // through ungated, which is the failure this group exists to catch.
    test('the /salon/* gate covers /salon/bookings/archive by PREFIX: it '
        'admits SALON_OWNER + SALON_ADMIN and bounces everyone else', () {
      AsyncData<AuthSession> sessionFor(UserRole role) =>
          AsyncData<AuthSession>(
            AuthSession.authenticated(
              user: User(
                id: 'u-1',
                email: 'u@example.com',
                role: role,
                firstName: 'Тест',
                lastName: 'Тестенко',
              ),
              accessToken: 'token',
            ),
          );

      for (final UserRole admitted in <UserRole>[
        UserRole.salonOwner,
        UserRole.salonAdmin,
      ]) {
        expect(
          authRedirectForLocation(
            sessionFor(admitted),
            RouteNames.salonStaffBookingsArchive,
          ),
          isNull,
          reason: '$admitted is the audience of the board this is pushed from',
        );
      }

      for (final UserRole bounced in <UserRole>[
        UserRole.salonMaster,
        UserRole.client,
        UserRole.independentMaster,
      ]) {
        expect(
          authRedirectForLocation(
            sessionFor(bounced),
            RouteNames.salonStaffBookingsArchive,
          ),
          equals(roleHomePath(bounced)),
          reason:
              '$bounced must be bounced to its own landing. For SALON_MASTER '
              'specifically this is mobile-backlog.md:118 — its own archive '
              'is the UNCHANGED /staff/bookings/archive',
        );
      }

      expect(
        authRedirectForLocation(
          const AsyncData<AuthSession>(AuthSession.unauthenticated()),
          RouteNames.salonStaffBookingsArchive,
        ),
        equals(RouteNames.login),
        reason: 'an unauthenticated visitor lands on login, not the archive',
      );
    });

    test('/master/* is NOT widened by this phase — SALON_MASTER is still '
        'bounced from the INDEPENDENT_MASTER archive, and keeps its own', () {
      const AsyncData<AuthSession> salonMasterSession = AsyncData<AuthSession>(
        AuthSession.authenticated(
          user: User(
            id: 'sm-1',
            email: 'sm@example.com',
            role: UserRole.salonMaster,
            firstName: 'Ольга',
            lastName: 'Майстер',
          ),
          accessToken: 'token',
        ),
      );

      expect(
        authRedirectForLocation(
          salonMasterSession,
          RouteNames.masterBookingsArchive,
        ),
        equals(roleHomePath(UserRole.salonMaster)),
      );
      expect(
        authRedirectForLocation(
          salonMasterSession,
          RouteNames.salonMasterBookingsArchive,
        ),
        isNull,
        reason: '/staff/bookings/archive is untouched by this phase',
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
