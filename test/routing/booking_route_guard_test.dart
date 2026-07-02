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

import 'package:beautica_mobile/core/app_start_time.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/application/slot_picker_notifier.dart';
import 'package:beautica_mobile/features/booking/domain/booking_slot_picker_args.dart';
import 'package:beautica_mobile/features/booking/presentation/service_selector_sheet.dart';
import 'package:beautica_mobile/features/booking/presentation/slot_picker_screen.dart';
import 'package:beautica_mobile/features/master/application/public_master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/fakes/fake_auth_repository.dart';
import '../helpers/fakes/fake_master_repository.dart';
import '../helpers/fakes/fake_secure_storage.dart';
import '../helpers/fakes/fake_service_repository.dart';

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
  priceDisplay: '500 грн',
  category: 'NAILS',
);

BookingSlotPickerArgs _validArgs() => const BookingSlotPickerArgs(
  masterId: _kMasterId,
  master: _kMaster,
  services: <MasterService>[_kService],
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
  SlotPickerState build() => SlotPickerState(selectedDate: DateTime.now());
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
          // Settles the INDEPENDENT_MASTER redirect target (/master/profile)
          // synchronously — same leaked-timer regression, different screen.
          masterProfileProvider.overrideWith(_SettledMasterProfileNotifier.new),
          masterRepositoryProvider.overrideWith((_) => FakeMasterRepository()),
          serviceRepositoryProvider.overrideWith(
            (_) => FakeServiceRepository(),
          ),
          // Pre-seeds a selected date so a direct router.go() to
          // /booking/slots/time (bypassing the real "tap a day" step) does
          // not hit SlotTimeScreen's broken-flow self-pop guard — see
          // _SettledSlotPickerNotifier's doc comment.
          slotPickerProvider.overrideWith(_SettledSlotPickerNotifier.new),
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

        router.go(RouteNames.bookingConfirm);
        await tester.pumpAndSettle();

        expect(locationOf(router), equals(RouteNames.masterProfile));
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

      testWidgets('/booking/confirm', (tester) async {
        final router = await pumpRouterAs(tester, _clientSession);

        router.go(RouteNames.bookingConfirm);
        await tester.pumpAndSettle();

        expect(locationOf(router), equals(RouteNames.bookingConfirm));
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
    });
  });
}
