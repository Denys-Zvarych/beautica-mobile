// Navigation link audit — auth/onboarding flows.
//
// Purpose: assert every screen-to-screen transition identified in the QA
// navigation matrix. Each test pumps only the source screen + a thin stub
// destination (Text label) so the assertion is on the router location, not
// on real destination widget rendering. That keeps tests fast, deterministic,
// and isolated from destination-screen complexity.
//
// Tests are structured as: tap the trigger on the source screen → assert the
// router lands on the destination route.
//
// Covered flows (NL = Navigation Link test):
//   NL-01  /login "Register" link → /register/role                  ✅ covered (login_screen_test)
//   NL-02  /login "Forgot password" link → /forgot-password         ✅ covered (login_screen_test)
//   NL-03  /login success → /                                       ✅ covered (login_screen_test)
//   NL-04  /login EMAIL_NOT_VERIFIED banner → /verification          ✅ covered (login_screen_test)
//   NL-05  /register/role Continue → /register                      ✅ covered (role_selection_screen_test)
//   NL-06  /register/role login link → /login                       ✅ covered (role_selection_screen_test)
//   NL-07  /register (step-1) Next → /register/step-2               ✅ covered (register_step_1_screen_test)
//   NL-08  /register (step-1) back link → /register/role            ✅ covered (register_step_1_screen_test)
//   NL-09  /register (step-1) login link → /login                   ✅ covered (register_step_1_screen_test)
//   NL-10  /register/step-2 Next → /register/step-3                 ✅ covered (register_step_2_screen_test)
//   NL-11  /register/step-3 Submit → /verification (VerificationRequired) ✅ covered
//   NL-12  /register/step-3 CLIENT Skip → /verification             ✅ covered (register_step_3_skip_navigation_test)
//   NL-13  /verification OTP success → /done                        ✅ covered (verification_screen_test)
//   NL-14  /verification back link → /register/step-3               ✅ covered (verification_screen_test)
//   NL-15  /done "Go to app" → /                                    ✅ covered (done_screen_test)
//   NL-16  /done "Setup later" → /                                  ✅ covered (done_screen_test)
//   NL-17  /forgot-password "Send" success → /reset-password/otp (Beautica OTP
//          task Phase B3 — replaces the old in-screen "sent" confirmation
//          state)                                                  ✅ covered (forgot_password_request_screen_test)
//   NL-18  (retired — the old sent-state "preview reset" CTA no longer exists)
//   NL-19  /forgot-password back button → /login                   ✅ covered (this file, NL-B03)
//   NL-20  /reset-password success CTA → /login                     ✅ covered (reset_password_screen_test)
//   NL-21  /reset-password invalid CTA → /forgot-password            ✅ covered (reset_password_screen_test)
//   NL-22  /invite/accept success → / (via router redirect)         ❌ GAP — new test NL-22 below
//   NL-23  /settings logout confirmed → /login                      ✅ covered (settings_screen_test)
//
// Auth-guard coverage gaps (authRedirectForLocation — pure seam tests):
//   NL-G01  authenticated user at /register/role → /             ❌ GAP — new test
//   NL-G02  unauthenticated user at /register/role → stays (null) ❌ GAP — new test
//   NL-G03  authenticated user at /register/step-2 → /          ❌ GAP — new test
//   NL-G04  unauthenticated user at /register/step-2 → stays     ❌ GAP — new test
//   NL-G05  loading session at /register/role → stays            ❌ GAP — new test
//   NL-G06  loading session at /register/step-2 → stays          ❌ GAP — new test
//
// app_router.dart route completeness:
//   NL-R01  every RouteNames constant has a matching GoRoute registration       ❌ GAP — new test
//
// /register/step-2 back button:
//   NL-B01  AuthScaffold showBack=true on step-2 → back tapped → /register     ✅ covered (this file)
//
// /register/step-3 back button:
//   NL-B02  AuthScaffold showBack=true on step-3 → back tapped → /register/step-2  ✅ covered (this file)
//
// /forgot-password showBack=true → back tapped → /login:
//   NL-B03  AuthScaffold showBack=true on /forgot-password → back → /login     ❌ GAP — new test
//
// /reset-password showBack=true (form state) → back tapped → /login:
//   NL-B04  AuthScaffold showBack=true on /reset-password (form) → back → /login ❌ GAP — new test

import 'dart:async';
import 'dart:io';

import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/auth_tokens.dart';
import 'package:beautica_mobile/features/auth/domain/invite_details.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/accept_invite_screen.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/auth/presentation/forgot_password_request_screen.dart';
import 'package:beautica_mobile/features/auth/presentation/register_step_2_screen.dart';
import 'package:beautica_mobile/features/auth/presentation/register_step_3_screen.dart';
import 'package:beautica_mobile/features/auth/domain/reset_password_args.dart';
import 'package:beautica_mobile/features/auth/presentation/reset_password_screen.dart';
import 'package:beautica_mobile/features/auth/state/accept_invite_notifier.dart';
import 'package:beautica_mobile/features/auth/state/register_draft_notifier.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:beautica_mobile/routing/auth_redirect.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/fakes/fake_auth_repository.dart';
import '../helpers/fakes/fake_secure_storage.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

// ---------------------------------------------------------------------------
// Shared fixtures
// ---------------------------------------------------------------------------

const _fakeUser = User(
  id: 'u1',
  email: 'test@example.com',
  role: UserRole.independentMaster,
  firstName: 'Test',
  lastName: 'User',
);

const _authenticatedSession = AsyncData<AuthSession>(
  AuthSession.authenticated(user: _fakeUser, accessToken: 'tok'),
);

const _unauthenticatedSession = AsyncData<AuthSession>(
  AuthSession.unauthenticated(),
);

const _loadingSession = AsyncLoading<AuthSession>();

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Stubs `authProvider` to a settled, authenticated session so the PRODUCTION
/// [appRouterProvider] can be read without live network/storage calls. Mirrors
/// `app_router_page_type_test.dart`'s idiom — the established way to drive the
/// real router from a unit test.
class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier(this._fixed);

  final AsyncValue<AuthSession> _fixed;

  @override
  Future<AuthSession> build() async {
    state = _fixed;
    return _fixed.value ?? const AuthSession.unauthenticated();
  }
}

/// Reads the REAL production router with the minimum overrides needed to avoid
/// network / platform-channel I/O.
GoRouter _productionRouter() {
  final container = ProviderContainer(
    retry: beauticaProviderRetry,
    overrides: [
      authProvider.overrideWith(
        () => _FixedAuthNotifier(_authenticatedSession),
      ),
      authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
      secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
    ],
  );
  addTearDown(container.dispose);
  return container.read(appRouterProvider);
}

/// Minimal probe that renders its label as Text.
class _Probe extends StatelessWidget {
  const _Probe(this.label);
  final String label;

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text(label)));
}

// ===========================================================================
// NL-G01 – NL-G06: Auth-guard coverage for wizard routes not yet in
// auth_redirect_test.dart (registerRole, registerStep2).
// ===========================================================================

void main() {
  // -------------------------------------------------------------------------
  // Auth-guard pure-seam tests for wizard routes
  // -------------------------------------------------------------------------
  group('authRedirectForLocation — wizard route guard gaps', () {
    // NL-G01
    test(
      'NL-G01: INDEPENDENT_MASTER at /register/role is redirected to /master/profile',
      () {
        expect(
          authRedirectForLocation(
            _authenticatedSession,
            RouteNames.registerRole,
          ),
          equals(RouteNames.masterProfile),
        );
      },
    );

    // NL-G02
    test('NL-G02: unauthenticated user at /register/role stays (null)', () {
      expect(
        authRedirectForLocation(
          _unauthenticatedSession,
          RouteNames.registerRole,
        ),
        isNull,
      );
    });

    // NL-G03
    test(
      'NL-G03: INDEPENDENT_MASTER at /register/step-2 is redirected to /master/profile',
      () {
        expect(
          authRedirectForLocation(
            _authenticatedSession,
            RouteNames.registerStep2,
          ),
          equals(RouteNames.masterProfile),
        );
      },
    );

    // NL-G04
    test('NL-G04: unauthenticated user at /register/step-2 stays (null)', () {
      expect(
        authRedirectForLocation(
          _unauthenticatedSession,
          RouteNames.registerStep2,
        ),
        isNull,
      );
    });

    // NL-G05
    test('NL-G05: loading session at /register/role stays (null)', () {
      expect(
        authRedirectForLocation(_loadingSession, RouteNames.registerRole),
        isNull,
      );
    });

    // NL-G06
    test('NL-G06: loading session at /register/step-2 stays (null)', () {
      expect(
        authRedirectForLocation(_loadingSession, RouteNames.registerStep2),
        isNull,
      );
    });
  });

  // -------------------------------------------------------------------------
  // NL-R01: Every RouteNames constant maps to a GoRoute in app_router.dart.
  // -------------------------------------------------------------------------
  // WHAT CHANGED (2026-07-22 vacuous-assertion audit)
  // -------------------------------------------------
  // This test used to build its OWN `GoRouter`, commented "Mirror of the
  // production app_router registrations", and never imported app_router.dart
  // at all. It therefore asserted that the routes the TEST had just registered
  // were registered — deleting a real route from app_router.dart could not
  // fail it, which is the exact regression the test's name claims to catch. It
  // also only covered 14 of the RouteNames constants.
  //
  // It now resolves every constant against the PRODUCTION `appRouterProvider`
  // via `RouteConfiguration.findMatch`, which performs pure pattern matching
  // (no redirects, no auth guards, no widget tree) and returns an error match
  // list when nothing is registered for a location.
  //
  // MUTATION-VERIFIED: commenting out the `/settings` GoRoute registration in
  // lib/routing/app_router.dart turns this test red
  // ('RouteNames.settings → /settings ... resolves to NO registered GoRoute').
  // Restored immediately; not committed.
  group('NL-R01: Route registration completeness', () {
    // Every RouteNames member, with the path-building functions instantiated
    // against a sample id. Keyed by member name for a readable failure.
    //
    // This map is hand-maintained (Dart has no reflection), so the drift guard
    // below cross-checks its size against the declaration count in
    // route_names.dart — a new constant that is not added here fails THAT
    // test rather than silently escaping this one.
    const String kSampleId = 'sample-id';
    final Map<String, String> allRoutes = <String, String>{
      'splash': RouteNames.splash,
      'login': RouteNames.login,
      'registerRole': RouteNames.registerRole,
      'register': RouteNames.register,
      'registerStep2': RouteNames.registerStep2,
      'registerStep3': RouteNames.registerStep3,
      'forgotPassword': RouteNames.forgotPassword,
      'resetOtpVerification': RouteNames.resetOtpVerification,
      'resetPassword': RouteNames.resetPassword,
      'changePassword': RouteNames.changePassword,
      'acceptInvite': RouteNames.acceptInvite,
      'verification': RouteNames.verification,
      'done': RouteNames.done,
      'home': RouteNames.home,
      'settings': RouteNames.settings,
      'clientHome': RouteNames.clientHome,
      'clientFavorites': RouteNames.clientFavorites,
      'clientSearch': RouteNames.clientSearch,
      'clientBookings': RouteNames.clientBookings,
      'clientPassport': RouteNames.clientPassport,
      // Phase 239 — «Усі збережені», a pushed leaf nested under the passport
      // branch. Registered, so it belongs in `allRoutes` rather than in
      // `deliberatelyUnregistered`.
      'clientWishlist': RouteNames.clientWishlist,
      'bookingDetail()': RouteNames.bookingDetail(kSampleId),
      'bookingReview()': RouteNames.bookingReview(kSampleId),
      'clientSearchResults': RouteNames.clientSearchResults,
      'masterPublicProfile()': RouteNames.masterPublicProfile(kSampleId),
      'masterPublicReviews()': RouteNames.masterPublicReviews(kSampleId),
      'salonPublicProfile()': RouteNames.salonPublicProfile(kSampleId),
      // Phase 21.2 — owner/admin editable salon profile + its settings page.
      // Registered as STANDALONE top-level routes (see `app_router.dart`'s
      // own comment on why they cannot nest under `/salons/:salonId`).
      'salonManage()': RouteNames.salonManage(kSampleId),
      'salonManageSettings()': RouteNames.salonManageSettings(kSampleId),
      // Phase 21.1 — My Salons Hub, the SALON_OWNER landing. A literal
      // `/salons/mine` registered BEFORE the dynamic `/salons/:salonId`
      // above so it is not shadowed by it (see `RouteNames.mySalons`'s own
      // doc).
      'mySalons': RouteNames.mySalons,
      'bookingNew': RouteNames.bookingNew,
      'bookingSlots': RouteNames.bookingSlots,
      'bookingSlotsTime': RouteNames.bookingSlotsTime,
      'bookingConfirm': RouteNames.bookingConfirm,
      'bookingSuccess': RouteNames.bookingSuccess,
      'salonBookingServices': RouteNames.salonBookingServices,
      'salonBookingMasters': RouteNames.salonBookingMasters,
      'salonBookingTime': RouteNames.salonBookingTime,
      'salonBookingConfirm': RouteNames.salonBookingConfirm,
      'salonBookingSuccess': RouteNames.salonBookingSuccess,
      'clientMenu': RouteNames.clientMenu,
      'clientEditPersonal': RouteNames.clientEditPersonal,
      'clientEditContacts': RouteNames.clientEditContacts,
      'clientEditLocation': RouteNames.clientEditLocation,
      'contactSupport': RouteNames.contactSupport,
      'masterProfile': RouteNames.masterProfile,
      'masterBookings': RouteNames.masterBookings,
      'masterBookingNew': RouteNames.masterBookingNew,
      'masterBookingNewServices': RouteNames.masterBookingNewServices,
      'masterBookingDetail()': RouteNames.masterBookingDetail(kSampleId),
      'masterBookingsArchive': RouteNames.masterBookingsArchive,
      'clientReview()': RouteNames.clientReview(kSampleId),
      'masterMenu': RouteNames.masterMenu,
      'masterEditPersonal': RouteNames.masterEditPersonal,
      'masterEditContacts': RouteNames.masterEditContacts,
      'masterEditLocation': RouteNames.masterEditLocation,
      'masterReceivedReviews': RouteNames.masterReceivedReviews,
      'services': RouteNames.services,
      'serviceEdit()': RouteNames.serviceEdit(kSampleId),
      'serviceSetup': RouteNames.serviceSetup,
      'masterSchedule': RouteNames.masterSchedule,
      'scheduleWeeklyEditor': RouteNames.scheduleWeeklyEditor,
      'scheduleDayOverride': RouteNames.scheduleDayOverride,
      'schedulePropagate': RouteNames.schedulePropagate,
      'myRating': RouteNames.myRating,
      // Phase 250 — registered as a STANDALONE top-level `GoRoute`
      // (`app_router.dart`, near the `/salon/bookings/:bookingId` sibling
      // group) — see [RouteNames.salonStaffBookingNew]'s own doc.
      'salonStaffBookingNew': RouteNames.salonStaffBookingNew,
    };

    // Deliberate exclusions. `/master/working-hours` was retired in Phase 6.2
    // (it wrote the deprecated `working_hours` table and was deep-link-
    // reachable with no production navigation); the constant is kept only
    // because auth_redirect_test.dart uses it as a representative `/master/*`
    // path. `app_router_page_type_test.dart`'s RR-1 asserts the opposite —
    // that it stays UNregistered — so this exclusion is itself covered by a
    // test, not merely asserted here.
    //
    // NOT an exclusion — `/services/create` (2026-08-04): the single-create
    // form (`ServiceCreateScreen`) was deleted and the two "add services"
    // flows collapsed onto the one surface `/services/setup`. Unlike the
    // entries below, the `RouteNames.serviceCreate` CONSTANT was deleted too,
    // so it belongs in neither `allRoutes` nor `deliberatelyUnregistered` —
    // NL-R01c's `covered.difference(declared)` assertion is what forced the
    // `allRoutes` row out. `/services/setup` is still covered above.
    //
    // `salonStaffBookings` (`/salon/bookings`) — Phase 250 — a path-prefix
    // constant only, so the `/salon/bookings/new` child path can be composed
    // and the `/salon/*` role gate has a name to reference. There is no
    // parent SCREEN yet (that is Phase 251's Розклад entry point per
    // `app_router.dart`'s own comment above the `/salon/bookings/new`
    // registration), so no `GoRoute` is registered for the bare path today.
    const Set<String> deliberatelyUnregistered = <String>{
      'workingHours',
      'salonStaffBookings',
    };

    test('NL-R01: every RouteNames constant resolves to a registered GoRoute '
        'in the PRODUCTION app_router', () {
      final GoRouter router = _productionRouter();

      final List<String> unresolved = <String>[];
      allRoutes.forEach((String member, String path) {
        final RouteMatchList match = router.configuration.findMatch(
          Uri.parse(path),
        );
        if (match.isError) unresolved.add('RouteNames.$member → $path');
      });

      expect(
        unresolved,
        isEmpty,
        reason:
            'These RouteNames constants resolve to NO registered GoRoute in '
            'lib/routing/app_router.dart. Either register the route or delete '
            'the constant — a constant with no route is a nav target that '
            'throws at runtime:\n  ${unresolved.join('\n  ')}',
      );
    });

    test('NL-R01b: the retired /master/working-hours constant stays '
        'unregistered', () {
      final GoRouter router = _productionRouter();

      expect(
        router.configuration
            .findMatch(Uri.parse(RouteNames.workingHours))
            .isError,
        isTrue,
        reason:
            'RouteNames.workingHours is the ONE constant NL-R01 excludes. If it '
            'is ever re-registered, remove it from `deliberatelyUnregistered` '
            'and delete this test — do not leave the exclusion silently stale.',
      );
    });

    // DRIFT GUARD for the hand-maintained map above. Without it, a RouteNames
    // constant added tomorrow is simply absent from `allRoutes` and NL-R01
    // keeps passing — the same "the test only checks what the test knows
    // about" failure mode the mirrored router had.
    test(
      'NL-R01c: the NL-R01 route map covers every RouteNames declaration',
      () {
        final List<String> source = File(
          'lib/routing/route_names.dart',
        ).readAsLinesSync();

        // `static const String <name> =` and `static String <name>(` — the two
        // declaration shapes RouteNames uses.
        final RegExp decl = RegExp(
          r'^\s*static\s+(?:const\s+)?String\s+(\w+)\s*[=(]',
        );
        final Set<String> declared = source
            .map(decl.firstMatch)
            .nonNulls
            .map((RegExpMatch m) => m.group(1)!)
            .toSet();

        // Normalise the map's keys (the function entries carry a `()` suffix).
        final Set<String> covered = allRoutes.keys
            .map(
              (String k) => k.endsWith('()') ? k.substring(0, k.length - 2) : k,
            )
            .toSet()
            .union(deliberatelyUnregistered);

        expect(
          declared.difference(covered),
          isEmpty,
          reason:
              'RouteNames declares constants that NL-R01 does not check. Add '
              'them to `allRoutes` (or, if deliberately unregistered, to '
              '`deliberatelyUnregistered` WITH a justifying comment).',
        );
        expect(
          covered.difference(declared),
          isEmpty,
          reason:
              'NL-R01 checks names that no longer exist in RouteNames — stale '
              'entries in `allRoutes`/`deliberatelyUnregistered`.',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // NL-22: /invite/accept success → router navigates to /
  // -------------------------------------------------------------------------
  // The accept invite screen calls authProvider.notifier.acceptInvite(...)
  // which on success transitions authProvider to Authenticated. The screen
  // then relies on the router's redirect (authRedirect: authenticated + on
  // unauthOnlyRoute → /) to forward to home. In the widget test we wire the
  // real authRedirect so this guard fires.
  //
  // Implementation detail: AcceptInviteScreen does NOT call context.go('/') on
  // success — it deliberately leaves navigation to the router's refresh
  // listener. So this test wires authRedirect into the minimal GoRouter and
  // asserts that the router resolves to / after a successful accept.
  group('NL-22: /invite/accept success → / via router redirect', () {
    testWidgets('NL-22: tapping invite_accept CTA with valid form and successful '
        'repository call causes the router to navigate to /', (tester) async {
      const kToken = 'valid-invite-token';

      final validInvite = InviteDetails(
        email: 'masha@salon.ua',
        role: UserRole.salonMaster,
        expiresAt: DateTime.now().add(const Duration(hours: 48)),
      );

      // We need a ProviderScope so we can override acceptInviteProvider,
      // authRepositoryProvider, and secureStorageProvider simultaneously.
      // The router's redirect calls authRedirectForLocation with a captured
      // session — we capture it via authProvider.
      final repo = FakeAuthRepository();
      // Force acceptInvite() to return a salonMaster user so the role-based
      // router redirect lands on /home (salonMaster has no dedicated route yet).
      repo.acceptInviteResult = (
        const User(
          id: 'invited-u1',
          email: 'masha@salon.ua',
          role: UserRole.salonMaster,
          firstName: 'Марія',
          lastName: 'Бондар',
        ),
        const AuthTokens(
          accessToken: 'access-token',
          refreshToken: 'refresh-token',
        ),
      );
      final storage = FakeSecureStorage();

      // A container that starts with an unauthenticated session and
      // transitions to Authenticated after acceptInvite() succeeds.
      final container = ProviderContainer(
        retry: beauticaProviderRetry,
        overrides: [
          authRepositoryProvider.overrideWith((_) => repo),
          secureStorageProvider.overrideWith((_) => storage),
          acceptInviteProvider(
            kToken,
          ).overrideWith(() => _SyncInviteNotifier(validInvite)),
        ],
      );
      addTearDown(container.dispose);

      // Build a minimal router that wires the REAL authRedirect so the
      // authenticated→unauthOnlyRoute guard is exercised.
      final router = GoRouter(
        initialLocation: '${RouteNames.acceptInvite}?token=$kToken',
        // Fire the redirect on every navigation (same pattern as production).
        refreshListenable: _ContainerListenable(container),
        redirect: (context, state) =>
            authRedirect(container.read(authProvider), state),
        routes: <RouteBase>[
          GoRoute(
            path: RouteNames.acceptInvite,
            builder: (context, state) {
              final t = state.uri.queryParameters['token'] ?? '';
              return AcceptInviteScreen(token: t);
            },
          ),
          GoRoute(
            path: RouteNames.home,
            builder: (_, _) => const _Probe('home'),
          ),
          GoRoute(
            path: RouteNames.login,
            builder: (_, _) => const _Probe('login'),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('uk'),
          ),
        ),
      );
      // Wait for acceptInviteProvider Stream to deliver AsyncData.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      // Fill password (12-char minimum for invite path).
      await tester.enterText(
        find.byKey(const ValueKey<String>('invite_password')),
        'StrongPass12',
      );
      await tester.pump();

      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('invite_first_name')),
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('invite_first_name')),
        'Марія',
      );
      await tester.pump();

      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('invite_last_name')),
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('invite_last_name')),
        'Бондар',
      );
      await tester.pump();

      // Tap the accept CTA.
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('invite_accept')),
      );
      await tester.tap(find.byKey(const ValueKey<String>('invite_accept')));

      // Let the async acceptInvite() complete and the session update settle.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // The router's redirect must have forwarded the now-authenticated user
      // from /invite/accept (an unauthOnlyRoute) to /.
      final currentUri = router.routerDelegate.currentConfiguration.uri
          .toString();
      expect(
        currentUri,
        equals(RouteNames.home),
        reason:
            'After a successful acceptInvite() the session transitions to '
            'Authenticated. The router redirect fires because the user is now '
            'authenticated on /invite/accept (an unauthOnlyRoute) and must be '
            'forwarded to /.',
      );
    });
  });

  // -------------------------------------------------------------------------
  // NL-B01: /register/step-2 AuthScaffold back button navigates to /register
  //
  // FIX: AuthScaffold gained an `onBack` callback parameter. RegisterStep2Screen
  // passes `onBack: () => context.go(RouteNames.register)` so the back affordance
  // calls context.go() instead of Navigator.maybePop() (which was a no-op after
  // the wizard's context.go() calls replaced the stack).
  // -------------------------------------------------------------------------
  group('NL-B01: /register/step-2 back button navigates to /register', () {
    testWidgets(
      'NL-B01: tapping the AuthScaffold back button on /register/step-2 '
      'navigates to /register (step-1)',
      (tester) async {
        final container = ProviderContainer(
          retry: beauticaProviderRetry,
          overrides: [
            authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
            secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
          ],
        );
        addTearDown(container.dispose);

        container.read(registerDraftProvider.notifier).start(UserRole.client);

        final router = GoRouter(
          initialLocation: RouteNames.registerStep2,
          redirect: (_, _) => null,
          routes: <RouteBase>[
            GoRoute(
              path: RouteNames.register,
              builder: (_, _) => const _Probe('step-1'),
            ),
            GoRoute(
              path: RouteNames.registerRole,
              builder: (_, _) => const _Probe('role-selection'),
            ),
            ShellRoute(
              builder: (_, _, child) => child,
              routes: <RouteBase>[
                GoRoute(
                  path: RouteNames.registerStep2,
                  builder: (_, _) => const RegisterStep2Screen(),
                ),
                GoRoute(
                  path: RouteNames.registerStep3,
                  builder: (_, _) => const _Probe('step-3'),
                ),
              ],
            ),
          ],
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(
              routerConfig: router,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('uk'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The back button is rendered — the user can see it.
        final backFinder = find.byType(NeumorphicIconButton);
        expect(
          backFinder,
          findsOneWidget,
          reason:
              'AuthScaffold(showBack:true) must render a NeumorphicIconButton; '
              'the back affordance must be visible to the user.',
        );

        await tester.tap(backFinder);
        await tester.pumpAndSettle();

        // After the fix, tapping back on step-2 must navigate to /register.
        expect(
          find.text('step-1'),
          findsOneWidget,
          reason:
              'NL-B01: tapping the NeumorphicIconButton back on step-2 must '
              'navigate to /register via context.go(RouteNames.register). '
              'AuthScaffold.onBack was wired to context.go() to fix the '
              'maybePop no-op bug.',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // NL-B02: /register/step-3 AuthScaffold back button navigates to
  // /register/step-2
  //
  // FIX: RegisterStep3Screen passes `onBack: () => context.go(RouteNames.registerStep2)`
  // to AuthScaffold so the back affordance calls context.go() instead of the
  // no-op maybePop().
  // -------------------------------------------------------------------------
  group('NL-B02: /register/step-3 back button navigates to /register/step-2', () {
    testWidgets('NL-B02: tapping the AuthScaffold back button on /register/step-3 '
        'navigates to /register/step-2', (tester) async {
      final container = ProviderContainer(
        retry: beauticaProviderRetry,
        overrides: [
          authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
          secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
        ],
      );
      addTearDown(container.dispose);

      container
          .read(registerDraftProvider.notifier)
          .start(UserRole.independentMaster);
      container
          .read(registerDraftProvider.notifier)
          .updateStep1(
            email: 'test@example.com',
            password: 'Password1!',
            confirmPassword: 'Password1!',
          );

      final router = GoRouter(
        initialLocation: RouteNames.registerStep3,
        redirect: (_, _) => null,
        routes: <RouteBase>[
          GoRoute(
            path: RouteNames.register,
            builder: (_, _) => const _Probe('step-1'),
          ),
          GoRoute(
            path: RouteNames.registerRole,
            builder: (_, _) => const _Probe('role-selection'),
          ),
          ShellRoute(
            builder: (_, _, child) => child,
            routes: <RouteBase>[
              GoRoute(
                path: RouteNames.registerStep2,
                builder: (_, _) => const _Probe('step-2'),
              ),
              GoRoute(
                path: RouteNames.registerStep3,
                builder: (_, _) => const RegisterStep3Screen(),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('uk'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final backFinder = find.byType(NeumorphicIconButton);
      expect(
        backFinder,
        findsOneWidget,
        reason:
            'AuthScaffold(showBack:true) must render a NeumorphicIconButton; '
            'the back affordance must be visible to the user.',
      );

      await tester.tap(backFinder);
      await tester.pumpAndSettle();

      // After the fix, tapping back on step-3 must navigate to /register/step-2.
      expect(
        find.text('step-2'),
        findsOneWidget,
        reason:
            'NL-B02: tapping the NeumorphicIconButton back on step-3 must '
            'navigate to /register/step-2 via context.go(RouteNames.registerStep2). '
            'AuthScaffold.onBack was wired to context.go() to fix the '
            'maybePop no-op bug.',
      );
    });
  });

  // -------------------------------------------------------------------------
  // NL-B03: /forgot-password AuthScaffold back button → /login
  // -------------------------------------------------------------------------
  group('NL-B03: /forgot-password back button navigates to /login', () {
    testWidgets('NL-B03: tapping the AuthScaffold back button on /forgot-password '
        'navigates to /login', (tester) async {
      final repo = FakeAuthRepository();
      final storage = FakeSecureStorage();

      final router = GoRouter(
        // Navigate directly to /forgot-password from /login so the GoRouter
        // history has /login as the previous entry — context.pop() will land there.
        initialLocation: RouteNames.login,
        redirect: (_, _) => null,
        routes: <RouteBase>[
          GoRoute(
            path: RouteNames.login,
            builder: (_, _) => const _Probe('login'),
          ),
          GoRoute(
            path: RouteNames.forgotPassword,
            builder: (_, _) => const ForgotPasswordRequestScreen(),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          retry: beauticaProviderRetry,
          overrides: [
            authRepositoryProvider.overrideWith((_) => repo),
            secureStorageProvider.overrideWith((_) => storage),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('uk'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to /forgot-password (push from /login).
      unawaited(
        router.push(RouteNames.forgotPassword),
      ); // ignore: unawaited_futures
      await tester.pumpAndSettle();

      // The ForgotPasswordRequestScreen is now on screen — tap back.
      final backFinder = find.byType(NeumorphicIconButton);
      expect(
        backFinder,
        findsOneWidget,
        reason:
            'AuthScaffold(showBack:true) must render a NeumorphicIconButton',
      );
      await tester.tap(backFinder);
      await tester.pumpAndSettle();

      expect(
        find.text('login'),
        findsOneWidget,
        reason:
            'Tapping the AuthScaffold back button on /forgot-password must '
            'pop back to /login — the previous entry in the GoRouter history.',
      );
    });
  });

  // -------------------------------------------------------------------------
  // NL-B04: /reset-password (form state) AuthScaffold back button → /login
  // -------------------------------------------------------------------------
  group('NL-B04: /reset-password form back button navigates to /login', () {
    testWidgets(
      'NL-B04: tapping the AuthScaffold back button on /reset-password (form '
      'state) navigates back to /login',
      (tester) async {
        final repo = FakeAuthRepository();
        final storage = FakeSecureStorage();

        final router = GoRouter(
          initialLocation: RouteNames.login,
          redirect: (_, _) => null,
          routes: <RouteBase>[
            GoRoute(
              path: RouteNames.login,
              builder: (_, _) => const _Probe('login'),
            ),
            GoRoute(
              path: RouteNames.resetPassword,
              builder: (context, state) {
                final args = state.extra as ResetPasswordArgs?;
                return ResetPasswordScreen(
                  resetTicket: args?.resetTicket ?? '',
                  fromChangePassword: args?.fromChangePassword ?? false,
                );
              },
            ),
          ],
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(
          ProviderScope(
            retry: beauticaProviderRetry,
            overrides: [
              authRepositoryProvider.overrideWith((_) => repo),
              secureStorageProvider.overrideWith((_) => storage),
            ],
            child: MaterialApp.router(
              routerConfig: router,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('uk'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Navigate to /reset-password (push from /login), carrying the reset
        // ticket via in-app `extra` — no more `?token=` deep-link query param.
        unawaited(
          router.push(
            RouteNames.resetPassword,
            extra: const ResetPasswordArgs(resetTicket: 'test-ticket'),
          ),
        ); // ignore: unawaited_futures
        await tester.pumpAndSettle();

        // Tap back (AuthScaffold renders the back button in the form state).
        final backFinder = find.byType(NeumorphicIconButton);
        expect(
          backFinder,
          findsOneWidget,
          reason:
              'AuthScaffold(showBack:true) must render a NeumorphicIconButton',
        );
        await tester.tap(backFinder);
        await tester.pumpAndSettle();

        expect(
          find.text('login'),
          findsOneWidget,
          reason:
              'Tapping the AuthScaffold back button on /reset-password (form '
              'state) must pop back to /login — the previous GoRouter entry.',
        );
      },
    );
  });
}

// ---------------------------------------------------------------------------
// _ContainerListenable — bridges a ProviderContainer to a Listenable so the
// GoRouter refreshListenable fires whenever authProvider changes.
// ---------------------------------------------------------------------------

class _ContainerListenable extends ChangeNotifier {
  _ContainerListenable(ProviderContainer container) {
    container.listen<AsyncValue<AuthSession>>(
      authProvider,
      (_, _) => notifyListeners(),
    );
  }
}

// ---------------------------------------------------------------------------
// _SyncInviteNotifier — synchronously returns a fixed InviteDetails so the
// AcceptInviteScreen renders the form state immediately in tests.
// ---------------------------------------------------------------------------

class _SyncInviteNotifier extends AcceptInviteNotifier {
  _SyncInviteNotifier(this._invite);

  final InviteDetails _invite;

  @override
  FutureOr<InviteDetails> build(String token) => _invite;
}
