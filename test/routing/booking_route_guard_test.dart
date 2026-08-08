// Phase 14.1 — Route-guard tests for the booking flow (`/booking/*`).
//
// WHY THIS FILE MOUNTS THE REAL ROUTER (unlike client_menu_route_guard_test.dart)
// -----------------------------------------------------------------------------
// The `/client/*` and `/master/*` guard tests exercise `authRedirectForLocation`
// — a pure, `@visibleForTesting` seam called from the GLOBAL `authRedirect`
// prefix gate. The 4 booking routes are gated differently: `clientOnlyGuard`
// (app_router.dart:154) is a closure defined INSIDE `appRouterProvider` itself
// and wired as each route's OWN `redirect:` callback (app_router.dart:381-473)
// — there is no pure-function seam to call directly. So this file mounts the
// REAL `appRouterProvider` (mirrors `app_router_no_leaked_timer_test.dart`'s
// proven pattern: `ProviderContainer` overrides + `container.read(appRouterProvider)`
// + `UncontrolledProviderScope`) and drives `router.go(...)` directly, then
// asserts the resolved location.
//
// Every data-fetching provider `ServiceSelectorSheet` touches
// (`publicMasterProfileProvider`, `approvedCategoriesProvider` — the
// documented "approvedCategoriesProvider override footgun", see MEMORY) is
// settled synchronously in [_makeContainer] so a CLIENT admitted onto
// `/booking/new` never fires a real Dio request and never leaks a connection
// timeout `Timer` under the fake-async test binding — the exact regression
// `app_router_no_leaked_timer_test.dart` guards for `/master/profile`.
//
// This same rule applies to `slotRepositoryProvider` (overridden with
// [FakeSlotRepository] below): `/booking/slots/time` is a NESTED GoRoute
// under `/booking/slots` (app_router.dart), so a direct `router.go(...)` to
// it mounts BOTH `SlotDateScreen` and `SlotTimeScreen` in the same frame.
// `SlotDateScreen.build()` unconditionally watches `workingDaysProvider`,
// which reads through `slotRepositoryProvider` -> `HttpSlotRepository
// .getWorkingDays` — a real Dio call. Leaving that provider unfaked leaks a
// connection-timeout `Timer` past this test's teardown even though the
// screen under test is `SlotTimeScreen`, not `SlotDateScreen`. ANY future
// route added to this file that (transitively) mounts a booking-flow screen
// MUST get its own data-fetching providers checked against this same trap.
//
// COVERS
// ------
//   1. INDEPENDENT_MASTER is bounced off all 4 booking routes to its own
//      landing (`/master/profile`) — `clientOnlyGuard` → `roleHomePath`.
//   2. CLIENT may reach all 4 routes (no redirect).
//   3. A missing/wrong-typed `extra` on `/booking/new` redirects to `/home`
//      (`RouteNames.clientHome`) instead of rendering `ServiceSelectorSheet`
//      with an empty `masterId` (the guard added in the perf/security fix
//      pass — app_router.dart:409-423).
//   4. A missing `extra` on `/booking/slots` / `/booking/slots/time` never
//      crashes on the `state.extra! as BookingSlotPickerArgs` cast — it
//      redirects to `/booking/new`, whose OWN guard then also sees a missing
//      extra and chain-redirects further to `/home` (clientHome). The FULLY
//      RESOLVED location is `/home`, not the intermediate `/booking/new` hop
//      — see the `malformed extra guard` group for why.
//
// Phase 14.12/14.13 — EXTENDED with the same 3-part guard coverage
// (INDEPENDENT_MASTER bounced / CLIENT admitted / malformed extra) for the
// salon booking flow's three routes: `/booking/salon/services`,
// `/booking/salon/masters`, `/booking/salon/coming-soon`.

import 'package:beautica_mobile/core/app_start_time.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/application/salon_master_coverage_notifier.dart';
import 'package:beautica_mobile/features/booking/application/slot_picker_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/domain/booking_confirm_args.dart';
import 'package:beautica_mobile/features/booking/domain/booking_slot_picker_args.dart';
import 'package:beautica_mobile/features/booking/domain/booking_success_args.dart';
import 'package:beautica_mobile/features/booking/domain/salon_booking_args.dart';
import 'package:beautica_mobile/features/booking/domain/salon_master_schedule.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_confirm_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_success_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_master_selection_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_service_selection_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_time_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/service_selector_sheet.dart';
import 'package:beautica_mobile/features/booking/presentation/slot_picker_screen.dart';
import 'package:beautica_mobile/features/master/application/public_master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/rating/application/my_rating_notifier.dart';
import 'package:beautica_mobile/features/rating/domain/client_rating.dart';
import 'package:beautica_mobile/features/salon/application/public_salon_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_service_catalog_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_master_summary.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/wishlist/application/wishlist_notifier.dart';
import 'package:beautica_mobile/features/wishlist/domain/wishlist_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/fakes/fake_auth_repository.dart';
import '../helpers/fakes/fake_master_repository.dart';
import '../helpers/fakes/fake_secure_storage.dart';
import '../helpers/fakes/fake_service_repository.dart';
import '../helpers/fakes/fake_slot_repository.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const String _kMasterId = 'master-1';

const _kMaster = Master(
  id: _kMasterId,
  firstName: 'Test',
  lastName: 'Master',
  avgRating: 0,
  reviewCount: 0,
  type: MasterType.independentMaster,
);

const _kService = MasterService(
  id: 'svc-1',
  serviceDefId: 'def-1',
  name: 'Манікюр з покриттям',
  durationMinutes: 60,
  priceMin: 500,
  priceDisplay: '500 ₴',
  category: 'NAILS',
);

BookingSlotPickerArgs _validArgs() => const BookingSlotPickerArgs(
  masterId: _kMasterId,
  master: _kMaster,
  services: <MasterService>[_kService],
);

/// A valid `BookingConfirmArgs` extra for `/booking/confirm` — Phase 14.2
/// replaced the placeholder screen with `BookingConfirmScreen`, which reads
/// `publicMasterProfileProvider(masterId)` (overridden below with `_kMaster`
/// + `_kService`) and requires `state.extra` to actually resolve `_kService`
/// by id, or its defensive not-found guard pops the screen.
BookingConfirmArgs _validConfirmArgs() => BookingConfirmArgs(
  masterId: _kMasterId,
  master: _kMaster,
  services: <MasterService>[_kService],
  startAt: DateTime.utc(2026, 7, 20, 10),
  idempotencyKey: 'guard-key-1',
);

/// A valid `BookingSuccessArgs` extra for `/booking/success`.
BookingSuccessArgs _validSuccessArgs() => BookingSuccessArgs(
  master: _kMaster,
  services: <MasterService>[_kService],
  startAt: DateTime.utc(2026, 7, 20, 10),
);

// Phase 14.12/14.13 — salon booking flow fixtures.
const String _kSalonId = 'salon-1';

const _kSalon = Salon(id: _kSalonId, name: 'Test Salon');

const _kSalonCatalog = <SalonServiceCategoryEntry>[
  SalonServiceCategoryEntry(
    category: 'NAILS',
    displayName: 'Манікюр',
    count: 1,
    services: <SalonCatalogService>[
      SalonCatalogService(
        id: 'svc-1',
        name: 'Манікюр з покриттям',
        durationLabel: '1 год',
        priceDisplay: '500 ₴',
      ),
    ],
  ),
];

SalonBookingMasterSelectionArgs _validSalonMasterArgs() =>
    const SalonBookingMasterSelectionArgs(
      salonId: _kSalonId,
      selectedServiceIds: <String>['svc-1'],
    );

// Phase 14.16/14.17 — the salon booking flow's step-3 "Час" route fixture.
const String _kSalonMasterId = 'salon-master-1';

const _kSalonMaster = SalonMasterSummary(
  masterId: _kSalonMasterId,
  firstName: 'Salon',
  lastName: 'Master',
  avgRating: 0,
  reviewCount: 0,
  type: MasterType.salonMaster,
);

SalonBookingTimeArgs _validSalonTimeArgs() => const SalonBookingTimeArgs(
  salonId: _kSalonId,
  visit: SalonMasterSchedule(
    masterId: _kSalonMasterId,
    firstName: 'Salon',
    lastName: 'Master',
    type: MasterType.salonMaster,
    services: <SalonCatalogService>[
      SalonCatalogService(
        id: 'svc-1',
        name: 'Манікюр',
        durationLabel: '1 год',
        priceDisplay: '500 ₴',
        durationMinutes: 60,
        priceType: ServicePriceType.fixed,
        priceMin: 500,
      ),
    ],
    orderedMasterServiceIds: <String>['assign-svc-1'],
  ),
);

const _clientUser = User(
  id: 'c1',
  email: 'client@example.com',
  role: UserRole.client,
  firstName: 'Client',
  lastName: 'User',
);
const _clientSession = AsyncData<AuthSession>(
  AuthSession.authenticated(user: _clientUser, accessToken: 'token'),
);

const _masterUser = User(
  id: 'm1',
  email: 'master@example.com',
  role: UserRole.independentMaster,
  firstName: 'Master',
  lastName: 'User',
);
const _masterSession = AsyncData<AuthSession>(
  AuthSession.authenticated(user: _masterUser, accessToken: 'token'),
);

/// [AuthNotifier] stub that immediately settles to a fixed [AsyncValue] —
/// mirrors `app_router_no_leaked_timer_test.dart`'s `_FixedAuthNotifier`.
class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier(this._fixed);

  final AsyncValue<AuthSession> _fixed;

  @override
  Future<AuthSession> build() async {
    state = _fixed;
    return _fixed.value ?? const AuthSession.unauthenticated();
  }
}

/// [MasterProfile] stub that resolves immediately to a fixed [Master] so the
/// INDEPENDENT_MASTER redirect target (`/master/profile`, `roleHomePath`'s
/// landing for that role) never fires a real Dio request — mirrors
/// `app_router_no_leaked_timer_test.dart`'s `_SettledMasterProfileNotifier`
/// (same regression: an unsettled `MasterProfileScreen` leaks a
/// connection-timeout `Timer` under the fake-async test binding).
class _SettledMasterProfileNotifier extends MasterProfile {
  @override
  Future<Master> build() async => const Master(
    id: 'm1',
    firstName: 'Master',
    lastName: 'User',
    avgRating: 0,
    reviewCount: 0,
    type: MasterType.independentMaster,
  );
}

/// [Wishlist] stub that resolves immediately to an empty list, bypassing the
/// real notifier's `build()` body ENTIRELY — including its unconditional
/// 5-minute keep-alive TTL `Timer` — so ServiceSelectorSheet's Phase 240
/// wish-list watch cannot leak a Timer past this file's manual
/// `ProviderContainer` disposal. Mirrors `myRatingProvider`'s identical fix
/// below for the same ordering gotcha.
class _SettledWishlistNotifier extends Wishlist {
  @override
  Future<List<WishlistService>> build() async => const <WishlistService>[];
}

/// [SlotPicker] stub that starts with a date ALREADY selected.
///
/// `SlotTimeScreen` self-pops (via a post-frame `context.pop()`) when
/// `slotPickerProvider.selectedDate` is null — a defensive guard for the
/// broken-flow case of reaching the time screen without going through the
/// date screen first (see `slot_picker_screen.dart:226-233`). Driving
/// `/booking/slots/time` directly via `router.go(...)` (as these guard tests
/// do, skipping the real "tap a day" interaction) hits exactly that guard, so
/// this override pre-seeds a selected date purely so the SCREEN MOUNTS —
/// this file is testing the ROLE/extra guard, not the date-selection
/// precondition.
class _SettledSlotPickerNotifier extends SlotPicker {
  @override
  // `selectedDate` is a DATE TOKEN (a Kyiv calendar day), not an instant — the
  // real screen seeds it from `kyivToday(ref.read(clockProvider))`. Seeding it
  // with a bare `DateTime.now()` handed the guard a host-local INSTANT whose
  // `.year`/`.month`/`.day` are the DEVICE's calendar day, which is a
  // different day from Kyiv's for part of every 24h window on any non-Kyiv
  // host.
  SlotPickerState build() =>
      SlotPickerState(selectedDate: kyivToday(DateTime.now));
}

/// [MaterialApp.router] wrapper for the real [appRouter] with l10n delegates.
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
  group('/booking/* role gate (Phase 14.1 clientOnlyGuard)', () {
    // Park the splash gate in the past so authRedirect does not pin the
    // router on /splash waiting for AppStartTime.minSplashDuration to elapse.
    setUp(
      () => AppStartTime.setStartForTest(
        DateTime.now().subtract(const Duration(seconds: 5)),
      ),
    );
    tearDown(AppStartTime.resetForTest);

    ProviderContainer makeContainer(AsyncValue<AuthSession> session) {
      final container = ProviderContainer(
        // A CLIENT session resolves through the REAL client shell
        // (`RouteNames.clientHome`) en route to whichever booking location
        // the test navigates to — the shell's `StatefulShellRoute.indexedStack`
        // eagerly builds all 5 branches (Пошук/Улюблені/BEAUTY PASSPORT/etc.),
        // several of which are real, data-fetching screens this test does not
        // (and should not need to) stub. Riverpod's DEFAULT retry policy would
        // otherwise schedule a real exponential-backoff `Timer` for each of
        // those unrelated failed reads and leak it past test teardown —
        // disabling retry (mirrors `pump_app.dart`'s `retry:` knob) keeps this
        // test scoped to the booking-route guard it actually exercises.
        retry: (_, _) => null,
        overrides: [
          authProvider.overrideWith(() => _FixedAuthNotifier(session)),
          authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
          secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
          // Settles ServiceSelectorSheet's data fetch synchronously — a
          // CLIENT admitted onto /booking/new must never fire a real Dio
          // request (leaked-timer regression; see file header).
          publicMasterProfileProvider(
            _kMasterId,
          ).overrideWith((ref) => (_kMaster, const <MasterService>[_kService])),
          // approvedCategoriesProvider footgun (MEMORY): sources from the
          // real Dio-backed categoryRequestApiProvider, independent of any
          // service repository override — MUST be overridden directly.
          approvedCategoriesProvider.overrideWith(
            (ref) async => const <ServiceCategoryOption>[],
          ),
          // Phase 240 — ServiceSelectorSheet now also watches wishlistProvider
          // (to prime each row's favourite heart). Overriding the NESTED
          // wishlistRepositoryProvider is NOT enough: `Wishlist.build()`
          // unconditionally starts its own 5-minute keep-alive TTL Timer
          // BEFORE it ever reads the repository, and `ref.onDispose` only
          // cancels it when the PROVIDER disposes — which for this file's
          // manual `ProviderContainer` happens in `container.dispose()`
          // (`addTearDown`), AFTER flutter_test's `!timersPending` check —
          // same ordering gotcha `myRatingProvider`'s override below
          // documents. Bypassing `Wishlist.build()` entirely — not just its
          // repository dependency — is the fix; see
          // `_SettledWishlistNotifier` below.
          wishlistProvider.overrideWith(_SettledWishlistNotifier.new),
          // Settles the INDEPENDENT_MASTER redirect target (/master/profile)
          // synchronously — same leaked-timer regression, different screen.
          masterProfileProvider.overrideWith(_SettledMasterProfileNotifier.new),
          masterRepositoryProvider.overrideWith((_) => FakeMasterRepository()),
          serviceRepositoryProvider.overrideWith(
            (_) => FakeServiceRepository(),
          ),
          // Settles `workingDaysProvider` (SlotDateScreen's calendar-gate
          // fetch) synchronously — same leaked-timer regression as the
          // profile/category overrides above, tripped by
          // `/booking/slots/time`'s direct router.go() also mounting
          // SlotDateScreen (nested route) in the same frame. See the file
          // header for the full rationale.
          slotRepositoryProvider.overrideWith((_) => FakeSlotRepository()),
          // Pre-seeds a selected date so a direct router.go() to
          // /booking/slots/time (bypassing the real "tap a day" step) does
          // not hit SlotTimeScreen's broken-flow self-pop guard — see
          // _SettledSlotPickerNotifier's doc comment.
          slotPickerProvider.overrideWith(_SettledSlotPickerNotifier.new),
          // Phase 14.12/14.13 — settles the salon booking screens' data
          // fetches synchronously, same leaked-timer rationale as the master
          // flow's overrides above.
          publicSalonProfileProvider(_kSalonId).overrideWith(
            (ref) => (_kSalon, const <SalonMasterSummary>[_kSalonMaster]),
          ),
          salonServiceCatalogProvider(
            _kSalonId,
          ).overrideWith((ref) => _kSalonCatalog),
          // Phase 14.16/14.17 bugfix — coverage values are now
          // `serviceDefId -> assignmentId` maps, not a bare `Set<String>`.
          // MUST resolve `_kSalonMasterId -> 'svc-1'` to a real assignment
          // id here (not an empty map): `SalonTimeScreen._resolveSchedule`
          // now consults this map to build `SalonMasterSchedule
          // .primaryServiceAssignmentId`, and drops any master it can't
          // resolve — an empty map would silently empty out the schedule
          // list and self-pop the `/booking/salon/time` route this file's
          // "CLIENT may reach every booking route" group asserts renders.
          salonMasterServiceCoverageProvider(
            const SalonBookingMasterSelectionArgs(
              salonId: _kSalonId,
              selectedServiceIds: <String>['svc-1'],
            ),
          ).overrideWith(
            (ref) => const <String, Map<String, String>>{
              _kSalonMasterId: <String, String>{'svc-1': 'svc-1'},
            },
          ),
          // Malformed/guard-redirect cases land the CLIENT session on
          // `RouteNames.clientHome` (HomeHubScreen), whose `_StatPillsRow`
          // watches `myRatingProvider`. `myRating`'s build (`my_rating_
          // notifier.dart`) unconditionally starts a 5-minute
          // `ref.keepAlive()` TTL `Timer` — correctly cancelled via
          // `ref.onDispose` on provider disposal, but disposal only happens
          // when `container.dispose()` runs (`addTearDown`, AFTER a test
          // body returns), which is AFTER the `!timersPending` tear-down
          // check. The `retry: null` knob above does not help here — that
          // only suppresses Riverpod's error-retry backoff, not this
          // explicit application Timer. Same leaked-timer shape as the
          // other overrides in this list; settling with an override
          // (bypassing `myRating`'s build body, and the Timer, entirely) is
          // the fix, mirroring `role_landing_chrome_test.dart`'s identical
          // fix for the same screen.
          myRatingProvider.overrideWith((ref) async => const ClientRating()),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    String locationOf(GoRouter router) =>
        router.routerDelegate.currentConfiguration.uri.toString();

    Future<GoRouter> pumpRouterAs(
      WidgetTester tester,
      AsyncValue<AuthSession> session,
    ) async {
      final container = makeContainer(session);
      final router = container.read(appRouterProvider);
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _RouterApp(router: router),
        ),
      );
      // Unlike app_router_no_leaked_timer_test.dart (which only asserts the
      // resolved LOCATION after a single bounded pump), these tests also
      // assert the mounted widget TYPE, which needs the redirect chain +
      // page transition to fully resolve. `pumpAndSettle` is safe here
      // (unlike that file's screens) because every landed screen's data is
      // settled synchronously via the overrides above — no shimmer/loading
      // state is ever entered, so there is no unbounded animation to wait on.
      await tester.pumpAndSettle();
      return router;
    }

    group('INDEPENDENT_MASTER is bounced off every booking route', () {
      testWidgets('/booking/new (extra: masterId) → /master/profile', (
        tester,
      ) async {
        final router = await pumpRouterAs(tester, _masterSession);

        router.go(RouteNames.bookingNew, extra: _kMasterId);
        await tester.pumpAndSettle();

        expect(locationOf(router), equals(RouteNames.masterProfile));
        expect(find.byType(ServiceSelectorSheet), findsNothing);
      });

      testWidgets('/booking/slots (extra: valid args) → /master/profile', (
        tester,
      ) async {
        final router = await pumpRouterAs(tester, _masterSession);

        router.go(RouteNames.bookingSlots, extra: _validArgs());
        await tester.pumpAndSettle();

        expect(locationOf(router), equals(RouteNames.masterProfile));
        expect(find.byType(SlotDateScreen), findsNothing);
      });

      testWidgets('/booking/slots/time (extra: valid args) → /master/profile', (
        tester,
      ) async {
        final router = await pumpRouterAs(tester, _masterSession);

        router.go(RouteNames.bookingSlotsTime, extra: _validArgs());
        await tester.pumpAndSettle();

        expect(locationOf(router), equals(RouteNames.masterProfile));
        expect(find.byType(SlotTimeScreen), findsNothing);
      });

      testWidgets('/booking/confirm → /master/profile', (tester) async {
        final router = await pumpRouterAs(tester, _masterSession);

        router.go(RouteNames.bookingConfirm, extra: _validConfirmArgs());
        await tester.pumpAndSettle();

        expect(locationOf(router), equals(RouteNames.masterProfile));
        expect(find.byType(BookingConfirmScreen), findsNothing);
      });

      testWidgets('/booking/success → /master/profile', (tester) async {
        final router = await pumpRouterAs(tester, _masterSession);

        router.go(RouteNames.bookingSuccess, extra: _validSuccessArgs());
        await tester.pumpAndSettle();

        expect(locationOf(router), equals(RouteNames.masterProfile));
        expect(find.byType(BookingSuccessScreen), findsNothing);
      });

      // Phase 14.12/14.13 — same guard, salon booking flow's 3 routes.
      testWidgets(
        '/booking/salon/services (extra: salonId) → /master/profile',
        (tester) async {
          final router = await pumpRouterAs(tester, _masterSession);

          router.go(RouteNames.salonBookingServices, extra: _kSalonId);
          await tester.pumpAndSettle();

          expect(locationOf(router), equals(RouteNames.masterProfile));
          expect(find.byType(SalonServiceSelectionScreen), findsNothing);
        },
      );

      testWidgets(
        '/booking/salon/masters (extra: valid args) → /master/profile',
        (tester) async {
          final router = await pumpRouterAs(tester, _masterSession);

          router.go(
            RouteNames.salonBookingMasters,
            extra: _validSalonMasterArgs(),
          );
          await tester.pumpAndSettle();

          expect(locationOf(router), equals(RouteNames.masterProfile));
          expect(find.byType(SalonMasterSelectionScreen), findsNothing);
        },
      );

      testWidgets('/booking/salon/time (extra: valid args) → /master/profile', (
        tester,
      ) async {
        final router = await pumpRouterAs(tester, _masterSession);

        router.go(RouteNames.salonBookingTime, extra: _validSalonTimeArgs());
        await tester.pumpAndSettle();

        expect(locationOf(router), equals(RouteNames.masterProfile));
        expect(find.byType(SalonTimeScreen), findsNothing);
      });
    });

    group('CLIENT may reach every booking route (no redirect)', () {
      testWidgets('/booking/new (extra: masterId)', (tester) async {
        final router = await pumpRouterAs(tester, _clientSession);

        router.go(RouteNames.bookingNew, extra: _kMasterId);
        await tester.pumpAndSettle();

        expect(locationOf(router), equals(RouteNames.bookingNew));
        expect(find.byType(ServiceSelectorSheet), findsOneWidget);
      });

      testWidgets('/booking/slots (extra: valid args)', (tester) async {
        final router = await pumpRouterAs(tester, _clientSession);

        router.go(RouteNames.bookingSlots, extra: _validArgs());
        await tester.pumpAndSettle();

        expect(locationOf(router), equals(RouteNames.bookingSlots));
        expect(find.byType(SlotDateScreen), findsOneWidget);
      });

      testWidgets('/booking/slots/time (extra: valid args)', (tester) async {
        final router = await pumpRouterAs(tester, _clientSession);

        router.go(RouteNames.bookingSlotsTime, extra: _validArgs());
        await tester.pumpAndSettle();

        expect(locationOf(router), equals(RouteNames.bookingSlotsTime));
        expect(find.byType(SlotTimeScreen), findsOneWidget);
      });

      testWidgets('/booking/confirm (extra: valid BookingConfirmArgs)', (
        tester,
      ) async {
        final router = await pumpRouterAs(tester, _clientSession);

        router.go(RouteNames.bookingConfirm, extra: _validConfirmArgs());
        await tester.pumpAndSettle();

        expect(locationOf(router), equals(RouteNames.bookingConfirm));
        expect(find.byType(BookingConfirmScreen), findsOneWidget);
      });

      testWidgets('/booking/success (extra: valid BookingSuccessArgs)', (
        tester,
      ) async {
        final router = await pumpRouterAs(tester, _clientSession);

        router.go(RouteNames.bookingSuccess, extra: _validSuccessArgs());
        await tester.pumpAndSettle();

        expect(locationOf(router), equals(RouteNames.bookingSuccess));
        expect(find.byType(BookingSuccessScreen), findsOneWidget);
      });

      // Phase 14.12/14.13 — same coverage, salon booking flow's 3 routes.
      testWidgets('/booking/salon/services (extra: salonId)', (tester) async {
        final router = await pumpRouterAs(tester, _clientSession);

        router.go(RouteNames.salonBookingServices, extra: _kSalonId);
        await tester.pumpAndSettle();

        expect(locationOf(router), equals(RouteNames.salonBookingServices));
        expect(find.byType(SalonServiceSelectionScreen), findsOneWidget);
      });

      testWidgets('/booking/salon/masters (extra: valid args)', (tester) async {
        final router = await pumpRouterAs(tester, _clientSession);

        router.go(
          RouteNames.salonBookingMasters,
          extra: _validSalonMasterArgs(),
        );
        await tester.pumpAndSettle();

        expect(locationOf(router), equals(RouteNames.salonBookingMasters));
        expect(find.byType(SalonMasterSelectionScreen), findsOneWidget);
      });

      testWidgets('/booking/salon/time (extra: valid args)', (tester) async {
        final router = await pumpRouterAs(tester, _clientSession);

        router.go(RouteNames.salonBookingTime, extra: _validSalonTimeArgs());
        await tester.pumpAndSettle();

        expect(locationOf(router), equals(RouteNames.salonBookingTime));
        expect(find.byType(SalonTimeScreen), findsOneWidget);
      });
    });

    group('malformed extra guard', () {
      testWidgets(
        '/booking/new with a missing extra redirects to /home (clientHome), '
        'never rendering ServiceSelectorSheet with an empty masterId',
        (tester) async {
          final router = await pumpRouterAs(tester, _clientSession);

          router.go(RouteNames.bookingNew);
          await tester.pumpAndSettle();

          expect(locationOf(router), equals(RouteNames.clientHome));
          expect(find.byType(ServiceSelectorSheet), findsNothing);
        },
      );

      testWidgets('/booking/new with a wrong-typed extra redirects to /home '
          '(clientHome)', (tester) async {
        final router = await pumpRouterAs(tester, _clientSession);

        router.go(RouteNames.bookingNew, extra: 42);
        await tester.pumpAndSettle();

        expect(locationOf(router), equals(RouteNames.clientHome));
      });

      // A missing extra on /booking/slots redirects to /booking/new — but
      // that route's OWN guard then sees ITS extra is also missing (go_router
      // re-evaluates the target's redirect chain, it does not just "land" on
      // the intermediate hop) and bounces again, so the location this
      // FULLY-RESOLVED chain settles on is /home (clientHome), not
      // /booking/new. Asserting the intermediate hop would be wrong — this
      // pins the REAL end-to-end resolved location.
      testWidgets(
        '/booking/slots with a missing extra chain-redirects through '
        '/booking/new to /home (clientHome) — both guards see a missing extra',
        (tester) async {
          final router = await pumpRouterAs(tester, _clientSession);

          router.go(RouteNames.bookingSlots);
          await tester.pumpAndSettle();

          expect(locationOf(router), equals(RouteNames.clientHome));
          expect(find.byType(SlotDateScreen), findsNothing);
        },
      );

      testWidgets(
        '/booking/slots/time with a missing extra chain-redirects through '
        '/booking/new to /home (clientHome)',
        (tester) async {
          final router = await pumpRouterAs(tester, _clientSession);

          router.go(RouteNames.bookingSlotsTime);
          await tester.pumpAndSettle();

          expect(locationOf(router), equals(RouteNames.clientHome));
          expect(find.byType(SlotTimeScreen), findsNothing);
        },
      );

      // Phase 14.2 — /booking/confirm now renders the real BookingConfirmScreen
      // (requires a BookingConfirmArgs extra), not the old placeholder. A
      // missing/wrong-typed extra redirects to [RouteNames.bookingNew] — that
      // route's OWN guard then sees a missing extra too (no masterId String was
      // ever carried), chain-redirecting further to /home, exactly like the
      // /booking/slots case above.
      testWidgets(
        '/booking/confirm with a missing extra chain-redirects through '
        '/booking/new to /home (clientHome)',
        (tester) async {
          final router = await pumpRouterAs(tester, _clientSession);

          router.go(RouteNames.bookingConfirm);
          await tester.pumpAndSettle();

          expect(locationOf(router), equals(RouteNames.clientHome));
          expect(find.byType(BookingConfirmScreen), findsNothing);
        },
      );

      testWidgets(
        '/booking/confirm with a wrong-typed extra chain-redirects through '
        '/booking/new to /home (clientHome)',
        (tester) async {
          final router = await pumpRouterAs(tester, _clientSession);

          router.go(RouteNames.bookingConfirm, extra: 42);
          await tester.pumpAndSettle();

          expect(locationOf(router), equals(RouteNames.clientHome));
          expect(find.byType(BookingConfirmScreen), findsNothing);
        },
      );

      // /booking/success has no upstream flow step to chain-redirect through
      // (unlike /booking/confirm → /booking/new) — a missing/invalid extra
      // bounces straight to /home (clientHome), matching every other booking
      // route's malformed-extra fallback.
      testWidgets('/booking/success with a missing extra redirects to /home '
          '(clientHome)', (tester) async {
        final router = await pumpRouterAs(tester, _clientSession);

        router.go(RouteNames.bookingSuccess);
        await tester.pumpAndSettle();

        expect(locationOf(router), equals(RouteNames.clientHome));
        expect(find.byType(BookingSuccessScreen), findsNothing);
      });

      testWidgets(
        '/booking/success with a wrong-typed extra redirects to /home '
        '(clientHome)',
        (tester) async {
          final router = await pumpRouterAs(tester, _clientSession);

          router.go(RouteNames.bookingSuccess, extra: 42);
          await tester.pumpAndSettle();

          expect(locationOf(router), equals(RouteNames.clientHome));
          expect(find.byType(BookingSuccessScreen), findsNothing);
        },
      );

      // Phase 14.12 — /booking/salon/services requires a non-empty String
      // (salonId) extra, mirroring /booking/new's guard shape exactly.
      testWidgets(
        '/booking/salon/services with a missing extra redirects to /home '
        '(clientHome), never rendering SalonServiceSelectionScreen with an '
        'empty salonId',
        (tester) async {
          final router = await pumpRouterAs(tester, _clientSession);

          router.go(RouteNames.salonBookingServices);
          await tester.pumpAndSettle();

          expect(locationOf(router), equals(RouteNames.clientHome));
          expect(find.byType(SalonServiceSelectionScreen), findsNothing);
        },
      );

      testWidgets(
        '/booking/salon/services with a wrong-typed extra redirects to '
        '/home (clientHome)',
        (tester) async {
          final router = await pumpRouterAs(tester, _clientSession);

          router.go(RouteNames.salonBookingServices, extra: 42);
          await tester.pumpAndSettle();

          expect(locationOf(router), equals(RouteNames.clientHome));
          expect(find.byType(SalonServiceSelectionScreen), findsNothing);
        },
      );

      // Phase 14.13 — /booking/salon/masters has no natural upstream salon id
      // to chain-redirect through (the preceding step's own route ALSO
      // requires an extra) — a missing/wrong-typed extra bounces straight to
      // /home (clientHome), matching /booking/confirm's "no natural upstream"
      // fallback shape.
      testWidgets(
        '/booking/salon/masters with a missing extra redirects to /home '
        '(clientHome)',
        (tester) async {
          final router = await pumpRouterAs(tester, _clientSession);

          router.go(RouteNames.salonBookingMasters);
          await tester.pumpAndSettle();

          expect(locationOf(router), equals(RouteNames.clientHome));
          expect(find.byType(SalonMasterSelectionScreen), findsNothing);
        },
      );

      testWidgets(
        '/booking/salon/masters with a wrong-typed extra redirects to /home '
        '(clientHome)',
        (tester) async {
          final router = await pumpRouterAs(tester, _clientSession);

          router.go(RouteNames.salonBookingMasters, extra: 42);
          await tester.pumpAndSettle();

          expect(locationOf(router), equals(RouteNames.clientHome));
          expect(find.byType(SalonMasterSelectionScreen), findsNothing);
        },
      );

      // Phase 14.13 — /booking/salon/coming-soon requires a non-empty String
      // (salonId) extra, mirroring /booking/salon/services' guard shape.

      // Phase 14.16 — /booking/salon/time has no natural upstream salon id
      // to chain-redirect through either — same "no natural upstream"
      // fallback shape as /booking/salon/masters above.
      testWidgets('/booking/salon/time with a missing extra redirects to /home '
          '(clientHome)', (tester) async {
        final router = await pumpRouterAs(tester, _clientSession);

        router.go(RouteNames.salonBookingTime);
        await tester.pumpAndSettle();

        expect(locationOf(router), equals(RouteNames.clientHome));
        expect(find.byType(SalonTimeScreen), findsNothing);
      });

      testWidgets(
        '/booking/salon/time with a wrong-typed extra redirects to /home '
        '(clientHome)',
        (tester) async {
          final router = await pumpRouterAs(tester, _clientSession);

          router.go(RouteNames.salonBookingTime, extra: 42);
          await tester.pumpAndSettle();

          expect(locationOf(router), equals(RouteNames.clientHome));
          expect(find.byType(SalonTimeScreen), findsNothing);
        },
      );
    });
  });
}
