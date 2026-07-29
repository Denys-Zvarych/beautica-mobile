// Router-tier chrome guard — the durable net for the f929caf bug class.
//
// For EACH role in the matrix, this boots the REAL `appRouterProvider` under an
// authenticated session of that role, drives the router through the real
// redirect to the role's landing destination, and asserts that the role's
// EXPECTED navigation chrome actually rendered (`findsOneWidget`) — or, for the
// intentional "coming soon" no-chrome rows, that NO bottom bar rendered.
//
// WHY THIS WOULD HAVE CAUGHT THE ORIGINAL BUG
// -------------------------------------------
// The defect: a CLIENT was delivered to `/` (the bare placeholder) instead of
// `/home` (ClientShell). The CLIENT row asserts, after the real redirect,
// `find.byType(ClientBottomNav)` is findsOneWidget. On the buggy dispatch the
// router would have settled on `/` → the `_Placeholder` scaffold, where
// ClientBottomNav is ABSENT → `findsOneWidget` fails. Unlike the old route-string
// tests, this asserts the CHROME the user actually sees, not just a path. The
// master row is the symmetric guard for INDEPENDENT_MASTER → VelvetBottomNavBar.
//
// This is the natural generalization of app_router_no_leaked_timer_test.dart
// (which only landed the INDEPENDENT_MASTER `/master/profile` case): the same
// production-router harness, now parametrised over every role + asserting chrome.
//
// Note: `test/` is excluded from the no_raw_ui_strings lint. Every assertion
// keys off route constants and widget TYPES — never raw Ukrainian text (mobile-
// qa M2). All pumps are BOUNDED (the real auth/profile screens animate, so
// pumpAndSettle would never quiesce — same constraint as the leaked-timer test).

import 'package:beautica_mobile/core/app_start_time.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/home/application/home_hub_notifier.dart';
import 'package:beautica_mobile/features/home/domain/home_hub_models.dart';
import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/profile_avatar.dart';
import 'package:beautica_mobile/features/rating/application/my_rating_notifier.dart';
import 'package:beautica_mobile/features/rating/domain/client_rating.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/shell/presentation/client_shell.dart';
import 'package:beautica_mobile/features/shell/presentation/widgets/client_bottom_nav.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/fakes/fake_auth_repository.dart';
import '../helpers/fakes/fake_master_repository.dart';
import '../helpers/fakes/fake_secure_storage.dart';
import '../helpers/fakes/fake_service_repository.dart';
import 'role_landing_chrome_matrix.dart';

void main() {
  group('each role lands on a screen that shows its expected nav chrome', () {
    // Park the splash gate in the past so authRedirect does not pin the router
    // on /splash waiting for the minimum splash duration to elapse.
    setUp(
      () => AppStartTime.setStartForTest(
        DateTime.now().subtract(const Duration(seconds: 5)),
      ),
    );
    tearDown(AppStartTime.resetForTest);

    test('matrix covers every UserRole exactly once', () {
      assertMatrixCoversAllRoles();
    });

    // ── One router-tier test per matrix row (data-driven, no copy-paste) ────
    for (final row in roleLandingMatrix) {
      testWidgets(
        row.hasChrome
            ? '${row.role.name} lands on ${row.expectedLandingPath} showing '
                  '${row.chromeDescription}'
            : '${row.role.name} lands on ${row.expectedLandingPath} with no '
                  'bottom bar (intentional coming-soon)',
        (tester) async {
          final container = _authedContainer(row.role);
          final router = container.read(appRouterProvider);
          addTearDown(router.dispose);

          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: _RouterApp(router: router),
            ),
          );
          // Bounded pump — the real auth/profile screens animate; pumpAndSettle
          // would never quiesce. A few frames let the redirect resolve and the
          // landing screen build.
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));

          // The production redirect must deliver the role to the matrix's
          // declared landing path (value finder — not raw text).
          expect(
            _currentLocation(router),
            equals(row.expectedLandingPath),
            reason:
                '${row.role.name} must land on ${row.expectedLandingPath}; the '
                'live redirect sent it to ${_currentLocation(router)}. A wrong '
                'path here is the f929caf dispatch bug.',
          );

          if (row.hasChrome) {
            // THE durable assertion: the role's nav chrome actually rendered.
            // On the original bug a CLIENT would have settled on "/" (the
            // placeholder) where ClientBottomNav is absent → this fails.
            expect(
              row.chromeFinder!,
              findsOneWidget,
              reason:
                  '${row.role.name} landed on ${row.expectedLandingPath} but '
                  '${row.chromeDescription} did not render. The navigation '
                  'never delivered the user to the screen that HOSTS the bar — '
                  'this is exactly the f929caf class of bug (element exists, '
                  'user never reaches it).',
            );
          } else {
            // Intentional no-chrome landing. Assert NEITHER known bottom bar is
            // present. Reason on record: ${row.comingSoonReason}. A future
            // change that gives this role a shell flips the matrix row → this
            // branch stops running and the chrome branch above starts asserting.
            expect(
              find.byType(ClientBottomNav),
              findsNothing,
              reason:
                  '${row.role.name} is coming-soon (no chrome by design) but a '
                  'ClientBottomNav rendered. ${row.comingSoonReason}',
            );
            expect(
              find.byType(VelvetBottomNavBar),
              findsNothing,
              reason:
                  '${row.role.name} is coming-soon (no chrome by design) but a '
                  'VelvetBottomNavBar rendered. ${row.comingSoonReason}',
            );
            // And the chrome-bearing shells must not have mounted at all.
            expect(find.byType(ClientShell), findsNothing);
          }
        },
      );
    }
  });
}

// ---------------------------------------------------------------------------
// Harness (generalised from app_router_no_leaked_timer_test.dart).
// ---------------------------------------------------------------------------

/// Builds a ProviderContainer with an authenticated session for [role] and the
/// settled fakes that keep the landed screen off the real Dio stack (so the
/// master-profile landing resolves synchronously and schedules no wall-clock
/// timer — same overrides the leaked-timer guard relies on).
ProviderContainer _authedContainer(UserRole role) {
  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith(() => _FixedAuthNotifier(_sessionFor(role))),
      authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
      secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
      // Settle the master-profile data path (used only by the master row).
      masterProfileProvider.overrideWith(_SettledMasterProfileNotifier.new),
      masterRepositoryProvider.overrideWith((_) => FakeMasterRepository()),
      serviceRepositoryProvider.overrideWith((_) => FakeServiceRepository()),
      // MasterProfileScreen's categories section watches
      // `approvedCategoriesProvider`, which builds via the REAL authenticated
      // Dio (it bypasses serviceRepositoryProvider). Settle it with an empty
      // list so no 15s connect-timeout Timer outlives the bounded `pump`.
      approvedCategoriesProvider.overrideWith(
        (ref) async => const <ServiceCategoryOption>[],
      ),
      // Settle the CLIENT Home-Hub data path (used only by the client row).
      //
      // HomeHubScreen watches five async providers. clientProfileProvider
      // derives from clientEditProfileProvider, which fires a REAL GET /users/me
      // on the authenticated Dio. Under this harness that request never resolves,
      // so Riverpod 3.x schedules a ~200ms `triggerRetry` Timer that outlives the
      // bounded `pump(100ms)` → `!timersPending`. Override every home-hub data
      // provider with a settled fake so none enters the error→retry path and no
      // wall-clock Timer is scheduled (same settle approach as
      // masterProfileProvider / approvedCategoriesProvider above; NO
      // `pump(Duration)` wait-out hack — mobile-qa M6).
      clientProfileProvider.overrideWith(
        (ref) async => const ClientProfileSummary(
          firstName: 'Test',
          lastName: 'Client',
          city: '',
          phone: '',
          clientRating: null,
          memberSinceYear: 2026,
        ),
      ),
      nextAppointmentProvider.overrideWith((ref) async => null),
      favoriteMastersProvider.overrideWith(
        (ref) async => const <FavoriteMasterItem>[],
      ),
      beautyTimelineProvider.overrideWith(
        (ref) async => const <TimelineEntry>[],
      ),
      // `_StatPillsRow` (home_hub_screen.dart) watches `myRatingProvider` — the
      // fifth home-hub data provider, added after this harness was written.
      // Its REAL build (`my_rating_notifier.dart`) starts a 5-minute
      // `ref.keepAlive()` TTL `Timer` unconditionally at build time — cancelled
      // correctly via `ref.onDispose` on provider disposal, but disposal only
      // happens when `container.dispose()` runs (`addTearDown`, AFTER this
      // test's body returns), which is AFTER `TestWidgetsFlutterBinding`'s
      // `!timersPending` invariant check. So a genuine, unavoidable-by-
      // production-code-changes 5-minute Timer is still pending at that check
      // no matter how fast the underlying future resolves — same shape as the
      // Dio-timeout leaks `app_router_no_leaked_timer_test.dart` documents.
      // Settling with an override (bypassing `myRating`'s build body, and thus
      // the Timer, entirely) is the SAME project-blessed fix that file's header
      // comment prescribes, matching the pattern already applied to the other
      // four home-hub providers above.
      myRatingProvider.overrideWith((ref) async => const ClientRating()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

AsyncData<AuthSession> _sessionFor(UserRole role) => AsyncData<AuthSession>(
  AuthSession.authenticated(user: _userFor(role), accessToken: 'token'),
);

User _userFor(UserRole role) => User(
  id: 'u-${role.name}',
  email: '${role.name}@example.com',
  role: role,
  firstName: 'Test',
  lastName: role.name,
);

String _currentLocation(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.toString();

/// [MasterProfile] stub that resolves immediately so the master landing builds
/// without the real repository firing a Dio request.
class _SettledMasterProfileNotifier extends MasterProfile {
  @override
  Future<Master> build() async => const Master(
    id: 'u-independentMaster',
    firstName: 'Test',
    lastName: 'Master',
    avgRating: 0,
    reviewCount: 0,
    type: MasterType.independentMaster,
  );
}

/// [AuthNotifier] stub that immediately settles to a fixed [AsyncValue].
class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier(this._fixed);

  final AsyncValue<AuthSession> _fixed;

  @override
  Future<AuthSession> build() async {
    state = _fixed;
    return _fixed.value ?? const AuthSession.unauthenticated();
  }
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
