// Phase 21.14 — MINIMAL dev smoke for [OwnerOwnProfileScreen].
//
// SCOPE, HONESTLY: this is the author's own render smoke, not a QA suite. It
// pins the two structurally different bodies the screen renders from the same
// data source — master section PRESENT vs ABSENT — plus the `embedded` back
// affordance and the inert trailing tune. It exists so the screen is not
// shipped having never been rendered once.
//
// EXTENDED by mobile-qa on 2026-09-01 — the gaps listed below are now closed
// (see the "closing the gaps" banner further down for exactly where each one
// landed; two of them are covered outside this file on purpose). The original
// list is kept verbatim as the record of what the seed did and did not do:
//   • loading + error [AsyncValue] states (skeleton shape; ErrorState retry
//     re-invoking only the `/users/me` upstream);
//   • the `hasMasterProfile` TRI-STATE at the provider level
//     (`owner_own_profile_notifier.dart`): false skips the probe entirely,
//     null falls through to it, and a `/masters/me` NotFoundFailure degrades
//     the section to ABSENT instead of erroring — none of that is covered here;
//   • the shell swap (`salon_shell_screen.dart` slot 2: owner gets this
//     screen, admin keeps `SalonShellTabPlaceholder`);
//   • the `/profile/owner` route's `mySalonsGuard` role gate;
//   • the empty-catalogue branch (`owner-own-profile-categories-empty`).
//
// `approvedCategoriesProvider` is overridden DIRECTLY (never via
// `serviceRepositoryProvider` — it bypasses that provider entirely), the same
// footgun `salon_staff_profile_screen_test.dart` documents.
import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/salon/application/owner_own_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/presentation/owner_own_profile_screen.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/home/application/client_edit_profile_notifier.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/application/my_salons_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/app_start_time.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';
import '../../../helpers/pump_app.dart';

const _owner = User(
  id: 'u-1',
  email: 'owner@beautica.test',
  role: UserRole.salonOwner,
  firstName: 'Олена',
  lastName: 'Ковальчук',
  phoneNumber: '+380 97 000 00 00',
  instagram: '@olena',
  professionalTitle: 'Топ-майстер',
  hasMasterProfile: true,
);

const _master = Master(
  id: 'm-1',
  firstName: 'Олена',
  lastName: 'Ковальчук',
  bio: 'Працюю з 2015 року.',
  avgRating: 4.8,
  reviewCount: 12,
  type: MasterType.salonOwner,
);

const _services = <MasterService>[
  MasterService(
    id: 's-1',
    serviceDefId: 'd-1',
    name: 'Манікюр',
    durationMinutes: 60,
    priceMin: 500,
    priceDisplay: '500 ₴',
    category: 'NAILS',
  ),
];

List<Object> _overrides(OwnerOwnProfileData data) => <Object>[
  ownerOwnProfileProvider.overrideWith((ref) async => data),
  approvedCategoriesProvider.overrideWith(
    (ref) async => const <ServiceCategoryOption>[],
  ),
];

// ---------------------------------------------------------------------------
// mobile-qa extension — stubs for the retry-target and route-guard groups.
// ---------------------------------------------------------------------------

class _MockServiceRepository extends Mock implements ServiceRepository {}

/// `/users/me` that FAILS the first time and succeeds afterwards — the exact
/// shape the retry affordance exists for. Records every attempt so the test can
/// count them.
///
/// The failure is thrown from an `async` body, never synchronously: a Dio-backed
/// repository always fails asynchronously, and a sync throw during a provider
/// build bypasses Riverpod's retry machinery entirely.
class _FlakyClientEditProfile extends ClientEditProfile {
  _FlakyClientEditProfile(this.log);

  final List<String> log;
  int _attempts = 0;

  @override
  Future<User> build() async {
    log.add('users/me');
    if (_attempts++ == 0) throw const ServerFailure();
    return _owner;
  }
}

/// `/masters/me` that only RECORDS that it was built — the retry test's
/// negative half (it must NOT be re-invoked).
class _CountingMasterProfile extends MasterProfile {
  _CountingMasterProfile(this.log);

  final List<String> log;

  @override
  Future<Master> build() async {
    log.add('masters/me');
    return _master;
  }
}

/// Router-group personas. Distinct from [_owner] (which is the PROFILE the
/// screen renders) because a guard is about the SESSION's role.
const User _routerOwner = User(
  id: 'u-1',
  email: 'owner@beautica.test',
  role: UserRole.salonOwner,
);
const User _routerMaster = User(
  id: 'u-2',
  email: 'master@beautica.test',
  role: UserRole.independentMaster,
);

/// Pins the session to a fixed [AsyncValue] without touching platform channels
/// — mirrors `register_salon_route_shadowing_test.dart`'s own stub.
class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier(this._fixed);

  final AsyncValue<AuthSession> _fixed;

  @override
  Future<AuthSession> build() async {
    state = _fixed;
    return _fixed.value ?? const AuthSession.unauthenticated();
  }
}

/// [MySalons] stub that resolves IMMEDIATELY, so the owner landing never
/// reaches the real Dio-backed repository and never parks on a never-settling
/// `SkeletonShimmerScope`.
class _SettledMySalons extends MySalons {
  @override
  Future<List<Salon>> build() async => const <Salon>[
    Salon(id: 'salon-owner-1', name: 'Test Salon', isPrimary: true),
  ];
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
  testWidgets('master section present', (tester) async {
    await tester.pumpApp(
      const OwnerOwnProfileScreen(embedded: true),
      overrides: _overrides((owner: _owner, master: (_master, _services))),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('owner-own-profile-name')), findsOneWidget);
    expect(
      find.byKey(const Key('owner-own-profile-role-chip')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('owner-own-profile-professional-title')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('owner-own-profile-stats')), findsOneWidget);
    expect(
      find.byKey(const Key('owner-own-profile-rating-value')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('owner-own-profile-bio')), findsOneWidget);
    expect(
      find.byKey(const Key('owner-own-profile-categories')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('owner-profile-category-NAILS')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('owner-own-profile-contact-phone')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('owner-own-profile-contact-instagram')),
      findsOneWidget,
    );
    // No back chevron when embedded.
    expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsNothing);
  });

  testWidgets('master section absent; tune is inert', (tester) async {
    await tester.pumpApp(
      const OwnerOwnProfileScreen(),
      overrides: _overrides((
        owner: _owner.copyWith(
          hasMasterProfile: false,
          instagram: null,
          professionalTitle: null,
        ),
        master: null,
      )),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('owner-own-profile-stats')), findsNothing);
    expect(find.byKey(const Key('owner-own-profile-bio')), findsNothing);
    expect(find.byKey(const Key('owner-own-profile-categories')), findsNothing);
    expect(
      find.byKey(const Key('owner-own-profile-professional-title')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('owner-own-profile-contact-instagram')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('owner-own-profile-contact-phone')),
      findsOneWidget,
    );

    // Tune renders, is dimmed and absorbs taps.
    final tune = find.byKey(const Key('btn-owner-own-profile-settings'));
    expect(tune, findsOneWidget);
    expect(
      tester
          .widget<Opacity>(
            find.descendant(of: tune, matching: find.byType(Opacity)),
          )
          .opacity,
      0.6,
    );
    expect(
      tester
          .widget<AbsorbPointer>(
            find.descendant(of: tune, matching: find.byType(AbsorbPointer)),
          )
          .absorbing,
      isTrue,
    );

    // Standalone keeps a back affordance.
    expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // `visible` — the two IndexedStack defects (mobile-perf MEDIUM + LOW,
  // 2026-08-31). See `OwnerOwnProfileScreen.visible` for the full statement.
  //
  // These pump the screen inside a HOST that flips `visible` exactly as
  // `SalonShellScreen` does when the bottom nav moves off and back onto
  // «Профіль», with the screen staying MOUNTED throughout — which is the whole
  // point: a raw `IndexedStack` never disposes a visited child, and gives it
  // neither `Offstage` nor `TickerMode`, so "not visible" is a state the
  // screen can only learn from its parent.
  // -------------------------------------------------------------------------

  /// Current opacity of the identity card's entrance fade — the observable
  /// the reveal actually drives.
  ///
  /// `skipOffstage: false` throughout: the default finders SKIP the
  /// non-current child of an `IndexedStack` (Flutter wraps it in a
  /// `Visibility` whose element the finder treats as offstage), and the
  /// off-screen phase of these tests is exactly where the assertion has to
  /// look.
  double revealOpacity(WidgetTester tester) => tester
      .widget<FadeTransition>(
        find
            .ancestor(
              of: find.byKey(
                const Key('owner-own-profile-name'),
                skipOffstage: false,
              ),
              matching: find.byType(FadeTransition, skipOffstage: false),
            )
            // NEAREST ancestor — `.last` would pick the outermost, which is
            // the MaterialApp page-route transition sitting at 1.0.
            .first,
      )
      .opacity
      .value;

  testWidgets('the entrance reveal is SPENT on the first VISIBLE build, not '
      'burned off-screen', (tester) async {
    await tester.pumpApp(
      const _VisibilityHost(),
      overrides: _overrides((owner: _owner, master: (_master, _services))),
    );
    // Resolve the loader while the tab is OFF-SCREEN, then let a full
    // entrance's worth of time pass. This is the reported sequence: tap
    // «Профіль», tap away before it resolves, come back.
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('owner-own-profile-name'), skipOffstage: false),
      findsOneWidget,
      reason:
          'sanity: the loaded body must really be built while off-screen — '
          'an IndexedStack lays out its non-current children, so if this is '
          'absent the test is not reproducing the reported situation.',
    );
    expect(
      revealOpacity(tester),
      0.0,
      reason:
          'The one-shot entrance must NOT have run while the tab was '
          'off-screen. Under the bug _startReveal() ran the full 950 ms '
          'ticker on an unpainted subtree and burned the '
          '`_controller.value == 0` guard, so the user\'s FIRST REAL VIEW of '
          'the tab had no entrance at all.',
    );

    // Now the user selects «Профіль».
    await tester.tap(find.byKey(const Key('toggle-visible')));
    await tester.pump();
    // fixed-wait-ok: this IS the assertion. The claim is that the 950 ms
    // entrance is PARTWAY THROUGH 200 ms after the tab became visible — i.e.
    // that it is animating from 0 rather than having been spent off-screen
    // and jumped to 1.0. "Pump until it appears" cannot express a
    // mid-animation value; any settle-based wait would land at 1.0 and make
    // the bug and the fix indistinguishable.
    await tester.pump(const Duration(milliseconds: 200));

    final double midway = revealOpacity(tester);
    expect(
      midway,
      greaterThan(0.0),
      reason: 'the reveal must START on the first visible build',
    );
    expect(
      midway,
      lessThan(1.0),
      reason:
          'and it must ANIMATE from there — a value already pinned at 1.0 '
          '200 ms in means the controller was spent off-screen and merely '
          'jumped, which is the defect this test exists for.',
    );

    await tester.pumpAndSettle();
    expect(revealOpacity(tester), 1.0);
  });

  testWidgets('screen protection is held only while the tab is VISIBLE', (
    tester,
  ) async {
    final manager = ScreenProtectionManager();
    await tester.pumpApp(
      const _VisibilityHost(),
      overrides: <Object>[
        ..._overrides((owner: _owner, master: (_master, _services))),
        screenProtectionProvider.overrideWithValue(manager),
      ],
    );
    await tester.pumpAndSettle();

    expect(
      manager.acquirerCount,
      0,
      reason:
          'an off-screen tab renders no PII to the app switcher, so it must '
          'not hold the guard',
    );

    await tester.tap(find.byKey(const Key('toggle-visible')));
    await tester.pumpAndSettle();
    expect(manager.acquirerCount, 1);

    // Tab away again. `IndexedStack` never disposes the child, so an
    // initState-acquire / dispose-release pair latched the iOS app-switcher
    // blur across every OTHER salon tab for the rest of the shell visit — the
    // refcount only cleared on logout's reset().
    await tester.tap(find.byKey(const Key('toggle-visible')));
    await tester.pumpAndSettle();
    expect(
      manager.acquirerCount,
      0,
      reason:
          'the reference must be released when the tab stops being the '
          'visible one, not only when the screen is disposed',
    );

    // And the acquire/release pair must survive repeated flips.
    await tester.tap(find.byKey(const Key('toggle-visible')));
    await tester.pumpAndSettle();
    expect(manager.acquirerCount, 1);
  });

  // =========================================================================
  // mobile-qa (2026-09-01) — closing the gaps this file's header listed.
  // =========================================================================
  //
  // WHAT IS COVERED WHERE, so the next reader does not duplicate:
  //   • loading / error / empty-catalogue rendering + the retry's TARGET
  //     — HERE (below);
  //   • the `/profile/owner` route's `mySalonsGuard` role gate — HERE, against
  //     the REAL `appRouterProvider`;
  //   • the `hasMasterProfile` TRI-STATE and the `/masters/me` 404-degrade at
  //     the loader level — `owner_own_profile_notifier_test.dart` (stubbed
  //     notifiers) and, across the wire, `integration_test/
  //     owner_own_profile_flow_test.dart` (which is the only place the `null`
  //     arm is exercised as a genuinely ABSENT JSON KEY rather than a Dart
  //     null);
  //   • the shell slot-2 swap — `salon_shell_screen_test.dart` plus the same
  //     integration flow.

  group('AsyncValue states', () {
    testWidgets('loading — the neumorphic skeleton renders, and neither the '
        'body nor an error does', (tester) async {
      // A Completer that is never completed: the provider stays in
      // AsyncLoading for the whole test, which is the state under assertion.
      final Completer<OwnerOwnProfileData> pending =
          Completer<OwnerOwnProfileData>();
      addTearDown(() {
        if (!pending.isCompleted) {
          pending.complete((owner: _owner, master: null));
        }
      });

      await tester.pumpApp(
        const OwnerOwnProfileScreen(embedded: true),
        overrides: <Object>[
          ownerOwnProfileProvider.overrideWith((ref) => pending.future),
          approvedCategoriesProvider.overrideWith(
            (ref) async => const <ServiceCategoryOption>[],
          ),
        ],
      );
      // `pump`, never `pumpAndSettle`: the skeleton runs
      // `SkeletonShimmerScope`'s REPEATING shimmer, which never settles — a
      // settle here would hang the test rather than fail it.
      await tester.pump();

      expect(
        find.byType(SkeletonBlock),
        findsWidgets,
        reason:
            'the loading state must be the shaped skeleton, not a bare '
            'spinner — the owner\'s master row is auto-created on first-salon '
            'registration, so the section it reserves space for is present in '
            'the common case and a spinner would relayout under the user.',
      );
      expect(find.byKey(const Key('owner-own-profile-name')), findsNothing);
      expect(find.byType(ErrorState), findsNothing);
    });

    testWidgets('error — an ErrorState with a working retry affordance '
        'renders in place of the body', (tester) async {
      await tester.pumpApp(
        const OwnerOwnProfileScreen(embedded: true),
        overrides: <Object>[
          // ASYNC throw (`async` body), never `thenThrow`/a synchronous throw:
          // a Dio-backed repository always fails asynchronously, and a
          // synchronous throw during a provider build short-circuits Riverpod's
          // retry machinery entirely — so a sync-throwing fixture would assert
          // a state real users never reach that way.
          ownerOwnProfileProvider.overrideWith(
            (ref) async => throw const ServerFailure(),
          ),
          approvedCategoriesProvider.overrideWith(
            (ref) async => const <ServiceCategoryOption>[],
          ),
        ],
        // Disabled so the assertion lands on the TERMINAL error rather than on
        // `AsyncLoading(retrying: true)`; a ServerFailure is transient, so the
        // production predicate would park the element in that state for ~38 s.
        retry: (_, _) => null,
      );
      await tester.pumpAndSettle();

      expect(find.byType(ErrorState), findsOneWidget);
      expect(
        find.byKey(const Key('error_state_retry_button')),
        findsOneWidget,
        reason:
            'an error the owner cannot act on is a dead end — the retry '
            'affordance is part of the contract, not decoration.',
      );
      expect(find.byKey(const Key('owner-own-profile-name')), findsNothing);
      expect(find.byType(SkeletonBlock), findsNothing);
    });

    testWidgets('error — tapping retry re-invokes ONLY the /users/me upstream, '
        'and the recovered body renders', (tester) async {
      // The REAL loader runs here (nothing overrides `ownerOwnProfileProvider`
      // itself) — that is the whole point: the screen's `onRetry` invalidates
      // `clientEditProfileProvider`, and only a test that keeps the real
      // composition can observe which upstream that actually reaches.
      final List<String> log = <String>[];
      final repo = _MockServiceRepository();
      when(
        () => repo.getMasterServices(any()),
      ).thenAnswer((_) async => _services);

      await tester.pumpApp(
        const OwnerOwnProfileScreen(embedded: true),
        overrides: <Object>[
          clientEditProfileProvider.overrideWith(
            () => _FlakyClientEditProfile(log),
          ),
          // cycle-stub-ok: leaf data dep of the loader under test — the
          // masterProfile → authProvider edge is exercised for real by
          // `master_profile_notifier_test.dart`.
          masterProfileProvider.overrideWith(() => _CountingMasterProfile(log)),
          publicServiceRepositoryProvider.overrideWithValue(repo),
          approvedCategoriesProvider.overrideWith(
            (ref) async => const <ServiceCategoryOption>[],
          ),
        ],
        retry: (_, _) => null,
      );
      await tester.pumpAndSettle();

      expect(
        find.byType(ErrorState),
        findsOneWidget,
        reason: 'sanity: the first /users/me attempt really did fail',
      );
      expect(log.where((String e) => e == 'users/me').length, 1);
      final int masterCallsBeforeRetry = log
          .where((String e) => e == 'masters/me')
          .length;

      await tester.tap(find.byKey(const Key('error_state_retry_button')));
      await tester.pumpAndSettle();

      expect(
        log.where((String e) => e == 'users/me').length,
        2,
        reason:
            'retry must genuinely re-invoke the identity read — '
            '`ref.invalidate(clientEditProfileProvider)`, not a repaint of the '
            'same stale error.',
      );
      expect(
        log.where((String e) => e == 'masters/me').length,
        masterCallsBeforeRetry,
        reason:
            'ONLY the /users/me read can put this provider into AsyncError, so '
            'that is the one upstream retry has to clear. Invalidating '
            '`masterProfileProvider` here too would refetch an OPTIONAL '
            'section that never failed — and would blow away a master profile '
            'other screens are still reading from the same keepAlive cache.',
      );
      expect(
        find.byKey(const Key('owner-own-profile-name')),
        findsOneWidget,
        reason: 'the recovered attempt must actually render the body',
      );
      expect(find.byType(ErrorState), findsNothing);
    });

    testWidgets('empty catalogue — the categories section renders its own '
        'empty line, not a silently collapsed section', (tester) async {
      await tester.pumpApp(
        const OwnerOwnProfileScreen(embedded: true),
        overrides: _overrides((
          owner: _owner,
          master: (_master, const <MasterService>[]),
        )),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('owner-own-profile-categories')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('owner-own-profile-categories-empty')),
        findsOneWidget,
        reason:
            'an owner who works as a master but has published no services must '
            'be told so. `ServiceCategoryCardList` short-circuits to '
            'SizedBox.shrink() on an empty list, so without this branch the '
            'section header would sit above nothing at all.',
      );
      expect(
        find.byKey(const Key('owner-profile-category-NAILS')),
        findsNothing,
      );
      // The rest of the master section is unaffected — an empty catalogue is
      // not an absent master row.
      expect(find.byKey(const Key('owner-own-profile-stats')), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // The `/profile/owner` route's `mySalonsGuard` gate.
  //
  // Nothing links to this route today (it is the stand-alone entry only), so
  // without a test the guard is exactly the kind of line a refactor removes
  // silently: no screen would go red, and the route would quietly become
  // reachable by every authenticated role. Driven through the REAL
  // `appRouterProvider`, because a guard that is not run by the real router is
  // not a guard.
  // -------------------------------------------------------------------------
  group('/profile/owner — mySalonsGuard', () {
    setUp(
      () => AppStartTime.setStartForTest(
        DateTime.now().subtract(const Duration(seconds: 5)),
      ),
    );
    tearDown(AppStartTime.resetForTest);

    ProviderContainer makeRouterContainer(User user) {
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          authProvider.overrideWith(
            () => _FixedAuthNotifier(
              AsyncData<AuthSession>(
                AuthSession.authenticated(user: user, accessToken: 'token'),
              ),
            ),
          ),
          authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
          secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
          // Resolves IMMEDIATELY — keeps the owner landing off the real
          // Dio-backed repository and off a never-settling shimmer.
          mySalonsProvider.overrideWith(_SettledMySalons.new),
          ownerOwnProfileProvider.overrideWith(
            (ref) async => (owner: _owner, master: null),
          ),
          approvedCategoriesProvider.overrideWith(
            (ref) async => const <ServiceCategoryOption>[],
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    Future<GoRouter> pumpRouterAs(WidgetTester tester, User user) async {
      final ProviderContainer container = makeRouterContainer(user);
      final GoRouter router = container.read(appRouterProvider);
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _RouterApp(router: router),
        ),
      );
      await tester.pumpAndSettle();
      return router;
    }

    testWidgets('a SALON_OWNER is ADMITTED and gets the stand-alone screen '
        '(back chevron, not the embedded tab)', (tester) async {
      final GoRouter router = await pumpRouterAs(tester, _routerOwner);

      router.go(RouteNames.ownerOwnProfile);
      await tester.pumpAndSettle();

      expect(
        find.byType(OwnerOwnProfileScreen),
        findsOneWidget,
        reason:
            'the resolved PAGE TYPE, not merely a matching location string — '
            '`/profile` is a fresh top-level prefix, but a future `/profile/:id`'
            ' declared before it would shadow this literal.',
      );
      expect(
        find.byIcon(Icons.arrow_back_ios_new_rounded),
        findsOneWidget,
        reason:
            'the stand-alone registration passes `embedded: false`, so unlike '
            'the shell tab it must keep a way back.',
      );
    });

    testWidgets('an INDEPENDENT_MASTER is BOUNCED — the route never resolves '
        'the owner profile', (tester) async {
      final GoRouter router = await pumpRouterAs(tester, _routerMaster);

      router.go(RouteNames.ownerOwnProfile);
      await tester.pumpAndSettle();

      expect(
        find.byType(OwnerOwnProfileScreen),
        findsNothing,
        reason:
            'mySalonsGuard is SALON_OWNER-only. Without it every authenticated '
            'role could deep-link to an owner-shaped profile that reads '
            'GET /masters/me and the owner\'s own catalogue.',
      );
      // This test only ever calls `router.go`, never `context.push`, so no
      // `ImperativeRouteMatch` is on the stack and the raw read reports the
      // real post-redirect location. The push-safe `AppHarness.location`
      // helper lives in the integration_test tier, which a `test/` file must
      // not import.
      expect(
        // router-location-ok: `.go` only in this test — see the note above.
        router.routerDelegate.currentConfiguration.uri.toString(),
        isNot(RouteNames.ownerOwnProfile),
        reason: 'the guard must REDIRECT, not merely render something else',
      );
    });

    // NO CLIENT CASE, deliberately. `mySalonsGuard` branches on "is this
    // session a SALON_OWNER", not per-role, so a CLIENT adds no new guard
    // decision — and its bounce destination is the real client home hub, whose
    // `myRatingProvider` opens a 5-minute Timer that would have to be stubbed
    // along with the rest of that provider tree. That is a large stub surface
    // bought for zero extra signal; the INDEPENDENT_MASTER case above already
    // proves the deny arm.
  });
}

/// Mounts [OwnerOwnProfileScreen] inside a raw [IndexedStack] and flips which
/// slot is current — the exact shape `SalonShellScreen` uses, including the
/// `visible: stackSlot == 2` hand-off. Starts OFF-SCREEN.
class _VisibilityHost extends StatefulWidget {
  const _VisibilityHost();

  @override
  State<_VisibilityHost> createState() => _VisibilityHostState();
}

class _VisibilityHostState extends State<_VisibilityHost> {
  int _slot = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _slot,
        children: <Widget>[
          const SizedBox.shrink(),
          OwnerOwnProfileScreen(embedded: true, visible: _slot == 1),
        ],
      ),
      bottomNavigationBar: TextButton(
        key: const Key('toggle-visible'),
        onPressed: () => setState(() => _slot = _slot == 0 ? 1 : 0),
        child: const Text('toggle'),
      ),
    );
  }
}
