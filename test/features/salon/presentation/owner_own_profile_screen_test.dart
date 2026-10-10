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
import 'dart:io';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/media/pick/image_source_sheet.dart';
import 'package:beautica_mobile/core/media/pick/media_pick_service.dart';
import 'package:beautica_mobile/core/media/upload/avatar_upload_controller.dart';
import 'package:beautica_mobile/core/media/upload/media_upload_repository.dart';
import 'package:beautica_mobile/core/media/upload/upload_task.dart';
import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/features/notifications/presentation/unread_notifications_notifier.dart';
import 'package:beautica_mobile/shared/widgets/notification_bell_button.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/master/application/master_review_summary_notifier.dart';
import 'package:beautica_mobile/features/master/application/master_reviews_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/domain/master_review.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/master_reviews_body.dart';
import 'package:beautica_mobile/features/master/presentation/settings_hub_screen.dart';
import 'package:beautica_mobile/features/home/presentation/client_personal_info_edit_screen.dart';
import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/features/master/domain/master_update.dart';
import 'package:beautica_mobile/features/master/presentation/personal_info_edit_screen.dart';
import 'package:beautica_mobile/features/salon/application/owner_own_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/presentation/owner_own_profile_screen.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/home/application/client_edit_profile_notifier.dart';
import 'package:beautica_mobile/features/home/domain/client_profile_update.dart';
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
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/profile_avatar.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/profile_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../core/media/pick/scripted_pick_gateway.dart';
import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';
import '../../../helpers/pump_app.dart';
import '../../../helpers/test_container.dart';

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

/// Phase 365 addendum — a global unread count of two, so the bell shows its dot.
class _TwoUnread extends UnreadNotifications {
  @override
  FutureOr<int> build() => 2;
}

/// The REAL `appRouterProvider` over a fixed [user] session — shared by the
/// `/profile/owner` guard group and the phase 379 master-mode group.
ProviderContainer _makeRouterContainer(
  User user, {
  List<Object> extraOverrides = const <Object>[],
  Object? meResult,
}) {
  final container = makeTestContainer(
    retry: (_, _) => null,
    overrides: [
      authProvider.overrideWith(
        () => _FixedAuthNotifier(
          AsyncData<AuthSession>(
            AuthSession.authenticated(user: user, accessToken: 'token'),
          ),
        ),
      ),
      authRepositoryProvider.overrideWith(
        (_) => FakeAuthRepository()..meResult = meResult,
      ),
      secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
      // Resolves IMMEDIATELY — keeps the owner landing off the real
      // Dio-backed repository and off a never-settling shimmer.
      mySalonsProvider.overrideWith(_SettledMySalons.new),
      // Phase 379 mobile-qa — the `/owner/master/*` shell
      // (`_SalonMasterTabsShell(role: salonOwner)`) WATCHES `/masters/me` for
      // an owner session; un-overridden it reached the real Dio-backed
      // repository. Settles to the owner's own row instead.
      masterProfileProvider.overrideWith(
        () => _CountingMasterProfile(<String>[]),
      ),
      ownerOwnProfileProvider.overrideWith(
        (ref) async => (owner: _owner, master: null),
      ),
      approvedCategoriesProvider.overrideWith(
        (ref) async => const <ServiceCategoryOption>[],
      ),
      ...extraOverrides,
    ],
  );
  return container;
}

Future<GoRouter> _pumpRealRouterAs(
  WidgetTester tester,
  User user, {
  List<Object> extraOverrides = const <Object>[],
  Object? meResult,
}) async {
  final ProviderContainer container = _makeRouterContainer(
    user,
    extraOverrides: extraOverrides,
    meResult: meResult,
  );
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

class _MockMasterRepository extends Mock implements MasterRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(const ClientProfileUpdate());
    registerFallbackValue(
      const MasterUpdate(
        firstName: '',
        lastName: '',
        bio: '',
        contactPhone: '',
        instagram: '',
        professionalTitle: '',
      ),
    );
  });

  _identityAvatarTests();
  _masterModeTests();
  _avatarUploadNoReloadTests();
  _profileTabsTests();
  // Phase 365 addendum — the global notification bell, left of the tune button.
  group('notification bell in the header (phase 365 addendum)', () {
    GoRouter bellRouter() => GoRouter(
      initialLocation: '/profile/owner',
      routes: <RouteBase>[
        GoRoute(
          path: '/profile/owner',
          builder: (_, _) => const OwnerOwnProfileScreen(embedded: true),
        ),
        GoRoute(
          path: RouteNames.notifications,
          builder: (_, _) => const Scaffold(body: Text('feed-stub')),
        ),
        GoRoute(
          path: RouteNames.ownerSettings,
          builder: (_, _) => const Scaffold(body: Text('owner-hub-stub')),
        ),
      ],
    );

    Future<void> pumpBell(
      WidgetTester tester,
      GoRouter router, {
      List<Object> extra = const <Object>[],
    }) async {
      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[
          ..._overrides((owner: _owner, master: (_master, _services))),
          ...extra,
        ],
      );
      await tester.pumpAndSettle();
    }

    testWidgets('should_sitLeftOfTheTuneButton_with12dpGap', (tester) async {
      final GoRouter router = bellRouter();
      addTearDown(router.dispose);
      await pumpBell(tester, router);

      final Rect bell = tester.getRect(
        find.byKey(const Key('owner-profile-bell')),
      );
      final Rect button = tester.getRect(
        find.byKey(const Key('btn-owner-own-profile-settings')),
      );
      expect(bell.right, lessThan(button.left));
      expect(button.left - bell.right, VelvetSpacing.sm + 4);
    });

    testWidgets('should_pushOwnerSettings_whenTuneTapped', (tester) async {
      final GoRouter router = bellRouter();
      addTearDown(router.dispose);
      await pumpBell(tester, router);

      await tester.tap(find.byKey(const Key('btn-owner-own-profile-settings')));
      await tester.pumpAndSettle();

      expect(find.text('owner-hub-stub'), findsOneWidget);
    });

    testWidgets('should_showTheUnreadDot_fromTheGlobalCount', (tester) async {
      final GoRouter router = bellRouter();
      addTearDown(router.dispose);
      await pumpBell(
        tester,
        router,
        extra: <Object>[
          unreadNotificationsProvider.overrideWith(_TwoUnread.new),
        ],
      );

      expect(
        tester
            .widget<AppIcon>(find.byKey(NotificationBellButton.bellIconKey))
            .asset,
        BeauticaAssetIcons.notificationUnread,
      );
    });

    testWidgets('should_showThePlainBell_whenNothingIsUnread', (tester) async {
      final GoRouter router = bellRouter();
      addTearDown(router.dispose);
      await pumpBell(tester, router);

      expect(
        tester
            .widget<AppIcon>(find.byKey(NotificationBellButton.bellIconKey))
            .asset,
        BeauticaAssetIcons.notificationPlain,
      );
    });

    testWidgets('should_pushTheFeed_whenTheBellIsTapped', (tester) async {
      final GoRouter router = bellRouter();
      addTearDown(router.dispose);
      await pumpBell(tester, router);

      await tester.tap(find.byKey(const Key('owner-profile-bell')));
      await tester.pumpAndSettle();

      expect(find.text('feed-stub'), findsOneWidget);
      expect(router.canPop(), isTrue, reason: 'push, never go');
    });
  });

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
    for (final int i in <int>[0, 1, 2]) {
      expect(find.byKey(Key('owner-own-profile-tab-$i')), findsOneWidget);
    }
    // Tab 0 («Про майстра») is the default: bio + contacts; the services tab
    // body is not built until tab 1.
    expect(find.byKey(const Key('owner-own-profile-bio')), findsOneWidget);
    expect(find.byKey(const Key('owner-own-profile-categories')), findsNothing);
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

  testWidgets('master section absent; tune is enabled', (tester) async {
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
    for (final int i in <int>[0, 1, 2]) {
      expect(find.byKey(Key('owner-own-profile-tab-$i')), findsNothing);
    }
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

    // Phase 137 — the tune is live: enabled (no dim/absorb wrapper).
    final tune = find.byKey(const Key('btn-owner-own-profile-settings'));
    expect(tune, findsOneWidget);
    expect(tester.widget<NeumorphicIconButton>(tune).enabled, isTrue);

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

  testWidgets('a reveal interrupted mid-flight is PAUSED, then RESUMES — it '
      'neither keeps ticking off-screen nor freezes half-faded', (
    tester,
  ) async {
    // Phase 21.16 follow-up. `didUpdateWidget` used to sync ONLY the screen
    // protection when `visible` flipped, so a reveal still running when the
    // user tabbed away kept a `Ticker` scheduling a frame every vsync for the
    // rest of its ~950 ms, driving five `FadeTransition`/`SlideTransition`
    // pairs on a subtree the `IndexedStack` is not painting (it sets neither
    // `Offstage` nor `TickerMode` — see `OwnerOwnProfileScreen.visible`).
    //
    // The fix is a PAIR, and this test pins both halves, because either one
    // alone is a different bug: `stop()` without widening `_startReveal`'s
    // restart guard from `value == 0` to `!isCompleted` would leave the
    // entrance frozen at a fractional opacity for the rest of the shell visit.
    await tester.pumpApp(
      const _VisibilityHost(),
      overrides: _overrides((owner: _owner, master: (_master, _services))),
    );
    await tester.pumpAndSettle();

    // Show the tab and let the entrance get under way…
    await tester.tap(find.byKey(const Key('toggle-visible')));
    await tester.pump();
    // fixed-wait-ok: the assertion is about a MID-animation value, which no
    // settle-based wait can express — a settle lands at 1.0 and makes the bug
    // and the fix indistinguishable.
    await tester.pump(const Duration(milliseconds: 200));
    final double atInterrupt = revealOpacity(tester);
    expect(atInterrupt, greaterThan(0.0));
    expect(atInterrupt, lessThan(1.0));

    // …then tab away mid-reveal.
    await tester.tap(find.byKey(const Key('toggle-visible')));
    await tester.pump();
    // fixed-wait-ok: the claim is that MORE THAN a full entrance's worth of
    // time passing off-screen advances the reveal by NOTHING. That is a
    // statement about elapsed time, so time is what has to be advanced.
    await tester.pump(const Duration(milliseconds: 1200));
    expect(
      revealOpacity(tester),
      atInterrupt,
      reason: 'the controller must be stop()ped when the slot goes off-screen',
    );

    // …and coming back must RESUME, not leave it frozen.
    await tester.tap(find.byKey(const Key('toggle-visible')));
    await tester.pumpAndSettle();
    expect(revealOpacity(tester), 1.0);
  });

  // ---------------------------------------------------------------------
  // mobile-qa re-audit (cycle 2, 2026-09-05) — the OTHER half of the
  // off-screen ticker fix, which the reveal tests above cannot reach.
  //
  // `didUpdateWidget`'s `stop()`/resume pair governs `_controller`, this
  // State's OWN entrance controller, in the LOADED state — which is what
  // the tests above pin. `TickerMode(enabled: widget.visible)`
  // (`owner_own_profile_screen.dart:351`) exists for a ticker this State
  // does not own: `SkeletonShimmerScope`'s `..repeat(reverse: true)`
  // controller in the LOADING state. Tabbing to «Профіль» and away again
  // before the profile read returns leaves that shimmer scheduling a vsync
  // frame every ~16 ms on a subtree a raw `IndexedStack` never paints.
  //
  // Deleting the `TickerMode` wrapper leaves every reveal test above GREEN
  // — in the loaded state `_controller.stop()` has already muted the only
  // ticker they observe. This is the assertion that goes red instead.
  //
  // `transientCallbackCount` is the count of frame callbacks the scheduler
  // holds — what a running `Ticker` registers and a muted one unregisters.
  // Reading `TickerMode.of(context)` or the screen's own `visible` field
  // would be vacuous: those report what was CONFIGURED, never whether a
  // ticker stopped asking for frames.
  //
  // MUTATION-VERIFIED (2026-09-05) on the identical wrapper in
  // `admin_own_profile_screen.dart` — replacing `TickerMode(enabled:
  // widget.visible, child: …)` with its bare child flips the off-screen
  // count from 0 to 1 and turns this shape of test RED.
  // ---------------------------------------------------------------------
  testWidgets('the LOADING skeleton\'s shimmer schedules NO frames while the '
      'tab is off-screen, and resumes when it is shown', (tester) async {
    final Completer<OwnerOwnProfileData> pending =
        Completer<OwnerOwnProfileData>();
    addTearDown(() {
      if (!pending.isCompleted) {
        pending.complete((owner: _owner, master: (_master, _services)));
      }
    });

    await tester.pumpApp(
      const _VisibilityHost(),
      overrides: <Object>[
        ownerOwnProfileProvider.overrideWith((ref) => pending.future),
        approvedCategoriesProvider.overrideWith(
          (ref) async => const <ServiceCategoryOption>[],
        ),
      ],
    );
    // `pump`, never `pumpAndSettle`: the shimmer REPEATS, so a settle can
    // never return.
    await tester.pump();

    expect(
      find.byType(SkeletonBlock, skipOffstage: false),
      findsWidgets,
      reason:
          'sanity: the off-screen slot must really be in the LOADING state — '
          'an IndexedStack lays out its non-current children, so if the '
          'skeleton is absent this test is not reproducing the situation '
          'under test and the count below would be zero for free.',
    );
    expect(
      tester.binding.transientCallbackCount,
      0,
      reason:
          'a muted Ticker unregisters its frame callback. Any non-zero count '
          'here is the shimmer driving ~60 fps of vsync work on a subtree the '
          'IndexedStack is not painting.',
    );

    await tester.tap(find.byKey(const Key('toggle-visible')));
    await tester.pump();

    expect(
      tester.binding.transientCallbackCount,
      greaterThan(0),
      reason:
          'and it must ACTUALLY TICK once shown — without this half, a '
          'skeleton that never animates at all would satisfy the zero above '
          'and the test would pin nothing.',
    );
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

    testWidgets('empty catalogue — tab 1 shows the add-services CTA, not a '
        'silently collapsed section', (tester) async {
      await tester.pumpApp(
        const OwnerOwnProfileScreen(embedded: true),
        overrides: _overrides((
          owner: _owner,
          master: (_master, const <MasterService>[]),
        )),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('owner-own-profile-tab-1')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('owner-own-profile-categories')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('btn-master-add-services')), findsOneWidget);
      expect(
        find.byKey(const Key('owner-profile-category-NAILS')),
        findsNothing,
      );
      // An empty catalogue is not an absent master row.
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

    Future<GoRouter> pumpRouterAs(WidgetTester tester, User user) =>
        _pumpRealRouterAs(tester, user);

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

    // Phase 137 (21.15) — the Owner Settings Hub route.
    testWidgets('/profile/owner/settings builds SettingsHubScreen for a '
        'SALON_OWNER (owner config: no contacts, no location)', (tester) async {
      final GoRouter router = await pumpRouterAs(tester, _routerOwner);

      router.go(RouteNames.ownerSettings);
      await tester.pumpAndSettle();

      expect(find.byType(SettingsHubScreen), findsOneWidget);
      expect(find.byKey(const Key('row-personal')), findsOneWidget);
      expect(find.byKey(const Key('row-account')), findsOneWidget);
      expect(find.byKey(const Key('row-help')), findsOneWidget);
      expect(find.byKey(const Key('row-logout')), findsOneWidget);
      expect(find.byKey(const Key('row-contacts')), findsNothing);
      expect(find.byKey(const Key('row-location')), findsNothing);
    });

    testWidgets('/profile/owner/settings BOUNCES an INDEPENDENT_MASTER', (
      tester,
    ) async {
      final GoRouter router = await pumpRouterAs(tester, _routerMaster);

      router.go(RouteNames.ownerSettings);
      await tester.pumpAndSettle();

      expect(find.byType(SettingsHubScreen), findsNothing);
      expect(
        // router-location-ok: `.go` only in this test.
        router.routerDelegate.currentConfiguration.uri.toString(),
        isNot(RouteNames.ownerSettings),
      );
    });

    testWidgets('/profile/owner/settings BOUNCES a SALON_ADMIN', (
      tester,
    ) async {
      final GoRouter router = await pumpRouterAs(
        tester,
        _routerOwner.copyWith(role: UserRole.salonAdmin),
      );

      router.go(RouteNames.ownerSettings);
      await tester.pumpAndSettle();

      expect(find.byType(SettingsHubScreen), findsNothing);
      expect(
        // router-location-ok: `.go` only in this test.
        router.routerDelegate.currentConfiguration.uri.toString(),
        isNot(RouteNames.ownerSettings),
      );
    });

    testWidgets('/owner/edit/personal: a real save of the master label + bio '
        'lands on the master-mode profile (doneRoute = /owner/master/profile)', (
      tester,
    ) async {
      final repo = _MockMasterRepository();
      MasterUpdate? captured;
      when(() => repo.updateMyProfile(any())).thenAnswer((i) async {
        captured = i.positionalArguments.first as MasterUpdate;
      });
      final GoRouter router = await _pumpRealRouterAs(
        tester,
        _routerOwner,
        // `refreshUser()` re-reads `/auth/me` on save; the default fake
        // answers with a different role, which would redirect off the owner
        // shell and mask the destination under test.
        meResult: _routerOwner,
        extraOverrides: <Object>[
          clientEditProfileProvider.overrideWith(_SettledClientEditProfile.new),
          masterRepositoryProvider.overrideWithValue(repo),
        ],
      );

      router.go(RouteNames.ownerEditPersonal);
      // Not pumpAndSettle: the edit screen never settles here.
      await tester.pumpUntilFound(find.byType(PersonalInfoEditScreen));
      await tester.pump();
      await tester.pump();

      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('field-professionalTitle')),
          matching: find.byType(TextField),
        ),
        'Візажист-стиліст',
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('field-bio')),
          matching: find.byType(TextField),
        ),
        'Унікальна біографія 399.',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('btn-save-personal')));
      await tester.pump();
      await tester.pumpUntilGone(find.byType(PersonalInfoEditScreen));

      verify(() => repo.updateMyProfile(any())).called(1);
      expect(captured?.professionalTitle, 'Візажист-стиліст');
      expect(captured?.bio, 'Унікальна біографія 399.');
      expect(
        // router-location-ok: `.go` only in this test.
        router.routerDelegate.currentConfiguration.uri.toString(),
        RouteNames.ownerMasterProfile,
        reason: 'saving the owner personal edit must return to master mode',
      );

      // fixed-wait-ok: drains the snackbar auto-dismiss Timer before teardown;
      // there is no widget condition to poll for a pending Timer.
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('/owner/edit/personal builds the master PersonalInfoEditScreen '
        '(label + bio fields), not the client editor', (tester) async {
      final GoRouter router = await _pumpRealRouterAs(
        tester,
        _routerOwner,
        meResult: _routerOwner,
        extraOverrides: <Object>[
          clientEditProfileProvider.overrideWith(_SettledClientEditProfile.new),
        ],
      );

      router.go(RouteNames.ownerEditPersonal);
      await tester.pumpUntilFound(find.byType(PersonalInfoEditScreen));
      await tester.pump();
      await tester.pump();

      expect(find.byType(ClientPersonalInfoEditScreen), findsNothing);
      expect(find.byKey(const Key('field-professionalTitle')), findsOneWidget);
      expect(find.byKey(const Key('field-bio')), findsOneWidget);
    });

    // NO CLIENT CASE for the owner-hub route either, deliberately. `mySalonsGuard` branches on "is this
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

// ---------------------------------------------------------------------------
// Phase 367 (9.6) — the identity card carries the OWN avatar with the live
// camera badge (the shared `SelfAvatarEditor`), sourced from the session user.
// ---------------------------------------------------------------------------

class _AvatarAuth extends AuthNotifier {
  _AvatarAuth(this._u);
  final User _u;
  @override
  Future<AuthSession> build() async =>
      AuthSession.authenticated(user: _u, accessToken: 't');
}

void _identityAvatarTests() {
  const String url = 'https://media.test/avatars/u1/1.jpg';
  final Finder editor = find.descendant(
    of: find.byKey(const Key('owner-own-profile-avatar-editor')),
    matching: find.byType(NeumorphicAvatarEditor),
    matchRoot: true,
  );

  group('identity avatar (Phase 367)', () {
    for (final String? avatar in <String?>[url, null]) {
      testWidgets('session avatar ${avatar ?? 'null'} -> '
          '${avatar == null ? 'monogram' : 'photo'} + a live camera badge', (
        tester,
      ) async {
        await tester.pumpApp(
          const OwnerOwnProfileScreen(embedded: true),
          overrides: <Object>[
            ..._overrides((owner: _owner, master: (_master, _services))),
            authProvider.overrideWith(
              () => _AvatarAuth(_owner.copyWith(avatarUrl: avatar)),
            ),
          ],
        );
        await tester.pumpAndSettle();

        final NeumorphicAvatarEditor e = tester.widget<NeumorphicAvatarEditor>(
          editor,
        );
        expect(e.imageUrl, avatar);
        expect(
          e.state,
          avatar == null ? AvatarEditState.pristine : AvatarEditState.loaded,
        );
        expect(e.initials, 'ОК');
        expect(
          find.byType(ProfileAvatar),
          findsNothing,
          reason: 'own profile: no read-only well',
        );
        expect(find.byKey(const Key('avatar-edit-badge')), findsOneWidget);

        // The badge is live: it opens the 071 source sheet.
        await tester.tap(find.byKey(const Key('avatar-edit-badge')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('image-source-gallery')), findsOneWidget);
        expect(
          find.byKey(const Key('image-source-remove')),
          avatar == null ? findsNothing : findsOneWidget,
        );
      });
    }
  });
}

// ---------------------------------------------------------------------------
// Phase 367 fix — an own-avatar upload must NOT reload the owner loader.
// ---------------------------------------------------------------------------

/// `/users/me`, settled immediately with [_owner].
class _SettledClientEditProfile extends ClientEditProfile {
  @override
  Future<User> build() async => _owner;
}

/// `POST /media/avatar` whose result the test completes by hand.
class _HeldUploads implements MediaUploadRepository {
  final List<File> uploaded = <File>[];
  final Completer<String> result = Completer<String>();

  @override
  UploadTask<String> uploadAvatar(File file) {
    uploaded.add(file);
    return UploadTask<String>(
      progress: const Stream<double>.empty(),
      result: result.future,
      onCancel: () {},
    );
  }

  @override
  Future<void> deleteAvatar() async {}

  // Phase 369 — salon logo / cover: not exercised by this file.
  @override
  UploadTask<String> uploadSalonImage(
    String salonId,
    SalonImageSlot slot,
    File file,
  ) => throw UnimplementedError();

  @override
  Future<void> deleteSalonImage(String salonId, SalonImageSlot slot) =>
      throw UnimplementedError();
}

void _avatarUploadNoReloadTests() {
  const String newUrl = 'https://media.test/avatars/u1/new.jpg';

  group('own-avatar upload keeps the loaded body (Phase 367 fix)', () {
    testWidgets('the skeleton never appears between the upload completing and '
        'the new photo rendering; nothing is refetched', (tester) async {
      final Directory scratch = Directory.systemTemp.createTempSync('own_av');
      final Directory outside = Directory.systemTemp.createTempSync('own_av_o');
      addTearDown(() {
        scratch.deleteSync(recursive: true);
        outside.deleteSync(recursive: true);
      });
      final ScriptedPickGateway gw = ScriptedPickGateway(
        scratch: scratch,
        outside: outside,
      );
      final _HeldUploads uploads = _HeldUploads();
      final List<String> log = <String>[];

      // FALSIFIER: the first catalogue read answers; any later one PARKS
      // forever. A loader rebuilt by the avatar patch would re-issue it and
      // sit in `AsyncLoading` — the skeleton — on every frame below.
      final repo = _MockServiceRepository();
      var catalogueCalls = 0;
      when(() => repo.getMasterServices(any())).thenAnswer((_) {
        catalogueCalls++;
        return catalogueCalls == 1
            ? Future<List<MasterService>>.value(_services)
            : Completer<List<MasterService>>().future;
      });

      await tester.pumpApp(
        const OwnerOwnProfileScreen(embedded: true),
        overrides: <Object>[
          authProvider.overrideWith(() => _AvatarAuth(_owner)),
          clientEditProfileProvider.overrideWith(_SettledClientEditProfile.new),
          // cycle-stub-ok: leaf data dep of the loader under test.
          masterProfileProvider.overrideWith(() => _CountingMasterProfile(log)),
          publicServiceRepositoryProvider.overrideWithValue(repo),
          approvedCategoriesProvider.overrideWith(
            (ref) async => const <ServiceCategoryOption>[],
          ),
          mediaPickServiceProvider.overrideWithValue(
            MediaPickService(gw, tempDir: () async => scratch),
          ),
          mediaUploadRepositoryProvider.overrideWithValue(uploads),
          secureStorageProvider.overrideWithValue(FakeSecureStorage()),
        ],
        retry: (_, _) => null,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('owner-own-profile-name')), findsOneWidget);
      expect(catalogueCalls, 1);
      expect(log.where((String e) => e == 'masters/me'), hasLength(1));

      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(OwnerOwnProfileScreen)),
      );
      // Every state the loader emits from here on.
      final List<AsyncValue<OwnerOwnProfileData>> states =
          <AsyncValue<OwnerOwnProfileData>>[];
      final ProviderSubscription<AsyncValue<OwnerOwnProfileData>> sub =
          container.listen(
            ownerOwnProfileProvider,
            (_, AsyncValue<OwnerOwnProfileData> next) => states.add(next),
          );
      addTearDown(sub.close);

      // The pick / crop / compress steps do real file IO, so the flow runs
      // in the real zone; frames are pumped between its event-loop turns.
      AvatarChangeResult? result;
      await tester.runAsync(() async {
        unawaited(
          container
              .read(avatarUploadControllerProvider.notifier)
              .change(ImageSourceChoice.gallery)
              .then((AvatarChangeResult r) => result = r),
        );
        for (var i = 0; i < 5000 && uploads.uploaded.isEmpty; i++) {
          await Future<void>.delayed(Duration.zero);
        }
      });
      expect(uploads.uploaded, hasLength(1), reason: 'sanity: upload started');
      await tester.pump();

      uploads.result.complete(newUrl);

      final Finder editor = find.descendant(
        of: find.byKey(const Key('owner-own-profile-avatar-editor')),
        matching: find.byType(NeumorphicAvatarEditor),
        matchRoot: true,
      );
      var frames = 0;
      while (true) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        // fixed-wait-ok: one 16 ms FRAME per iteration — the test asserts on
        // every frame; the loop itself waits on the condition below.
        await tester.pump(const Duration(milliseconds: 16));
        frames++;
        expect(
          find.byType(SkeletonBlock),
          findsNothing,
          reason: 'frame $frames: the loading skeleton flashed',
        );
        expect(find.byType(ErrorState), findsNothing);
        expect(find.byKey(const Key('owner-own-profile-name')), findsOneWidget);
        final NeumorphicAvatarEditor e = tester.widget(editor);
        if (result != null && e.imageUrl == newUrl && e.previewFile == null) {
          break;
        }
        if (frames > 400) fail('the new photo never rendered');
      }

      expect(result, isA<AvatarChangeSucceeded>());
      expect(
        container.read(masterProfileProvider).value?.avatarUrl,
        newUrl,
        reason: 'the cached master row is still patched in place',
      );
      expect(
        states.where((AsyncValue<OwnerOwnProfileData> s) => s.isLoading),
        isEmpty,
        reason: 'an avatar-only patch must not rebuild the owner loader',
      );
      expect(catalogueCalls, 1, reason: 'no services refetch');
      expect(log.where((String e) => e == 'masters/me'), hasLength(1));
    });
  });
}

// ---------------------------------------------------------------------------
// Phase 379 (24.1b) — the owner «master mode» mount at
// `RouteNames.ownerMasterProfile`: additive `bottomNavBar` / `backLabel` /
// `backSemanticLabel` / `onBack`, and the router's «‹ Салон» + SYSTEM BACK
// exits, which must agree (both `go(salonHome)`, never an app exit).
// ---------------------------------------------------------------------------

const Key _masterModeBack = Key('owner-master-mode-back');

/// Whether nav tile [index] is announced as the active one.
bool _navTileSelected(WidgetTester tester, int index) =>
    tester
        .widget<Semantics>(
          find
              .descendant(
                of: find.byKey(Key('master-nav-tile-$index')),
                matching: find.byType(Semantics),
              )
              .first,
        )
        .properties
        .selected ??
    false;

void _masterModeTests() {
  final AppLocalizations l10n = lookupAppLocalizations(const Locale('uk'));
  final List<Object> data = _overrides((
    owner: _owner,
    master: (_master, _services),
  ));

  group('master-mode params (phase 379) — widget', () {
    for (final bool embedded in <bool>[false, true]) {
      testWidgets('defaults (embedded: $embedded) — no nav bar, no labelled '
          'back: the pre-379 tree', (tester) async {
        await tester.pumpApp(
          OwnerOwnProfileScreen(embedded: embedded),
          overrides: data,
        );
        await tester.pumpAndSettle();

        expect(find.byType(VelvetBottomNavBar), findsNothing);
        expect(find.byKey(_masterModeBack), findsNothing);
        expect(find.text(l10n.ownerMasterModeBack), findsNothing);
      });
    }

    testWidgets('bottomNavBar renders the independent-master nav with '
        '«Профіль» (tile 3) active', (tester) async {
      await tester.pumpApp(
        const OwnerOwnProfileScreen(
          embedded: true,
          bottomNavBar: VelvetBottomNavBar(
            activeIndex: 3,
            profileRoute: RouteNames.ownerMasterProfile,
          ),
        ),
        overrides: data,
      );
      await tester.pumpAndSettle();

      expect(find.byType(VelvetBottomNavBar), findsOneWidget);
      expect(_navTileSelected(tester, 3), isTrue);
      for (final int i in <int>[0, 1, 2]) {
        expect(_navTileSelected(tester, i), isFalse, reason: 'tile $i');
      }
    });

    testWidgets('backLabel + onBack render the labelled pill EVEN when '
        'embedded, and a tap calls onBack', (tester) async {
      int backs = 0;
      await tester.pumpApp(
        OwnerOwnProfileScreen(
          embedded: true,
          backLabel: l10n.ownerMasterModeBack,
          backSemanticLabel: l10n.ownerMasterModeBackSemantics,
          onBack: () => backs++,
        ),
        overrides: data,
      );
      await tester.pumpAndSettle();

      expect(find.byKey(_masterModeBack), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(_masterModeBack),
          matching: find.text(l10n.ownerMasterModeBack),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(l10n.ownerMasterModeBackSemantics),
        findsOneWidget,
      );

      await tester.tap(find.byKey(_masterModeBack));
      await tester.pumpAndSettle();
      expect(backs, 1);
    });

    testWidgets('fitWholeTitle is true in master mode (backLabel), false '
        'otherwise', (tester) async {
      await tester.pumpApp(
        OwnerOwnProfileScreen(
          embedded: true,
          backLabel: l10n.ownerMasterModeBack,
          backSemanticLabel: l10n.ownerMasterModeBackSemantics,
          onBack: () {},
        ),
        overrides: data,
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ProfileScaffold>(find.byType(ProfileScaffold))
            .fitWholeTitle,
        isTrue,
      );

      await tester.pumpApp(
        const OwnerOwnProfileScreen(embedded: true),
        overrides: data,
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ProfileScaffold>(find.byType(ProfileScaffold))
            .fitWholeTitle,
        isFalse,
      );
    });
  });

  group('/owner/master/profile — real router (phase 379)', () {
    setUp(
      () => AppStartTime.setStartForTest(
        DateTime.now().subtract(const Duration(seconds: 5)),
      ),
    );
    tearDown(AppStartTime.resetForTest);

    String locationOf(GoRouter router) =>
        // router-location-ok: `.go` only in this group — no imperative match.
        router.routerDelegate.currentConfiguration.uri.toString();

    /// Records `SystemNavigator.pop` — the app-EXIT a system back on a lone
    /// root page would otherwise trigger.
    List<String> recordAppExits() {
      final List<String> exits = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'SystemNavigator.pop') exits.add(call.method);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      return exits;
    }

    /// Lands the owner on the real post-login landing (the salon shell via
    /// `/salons/home`), records it, then `go`es to the master-mode profile.
    Future<(GoRouter, String)> enterMasterMode(WidgetTester tester) async {
      final GoRouter router = await _pumpRealRouterAs(tester, _routerOwner);
      final String salonLanding = locationOf(router);

      router.go(RouteNames.ownerMasterProfile);
      await tester.pumpAndSettle();

      expect(locationOf(router), RouteNames.ownerMasterProfile);
      expect(find.byType(OwnerOwnProfileScreen), findsOneWidget);
      return (router, salonLanding);
    }

    testWidgets('a SALON_OWNER is ADMITTED: own profile + independent-master '
        'nav («Профіль» active) + «‹ Салон»', (tester) async {
      await enterMasterMode(tester);

      expect(find.byType(VelvetBottomNavBar), findsOneWidget);
      expect(_navTileSelected(tester, 3), isTrue);
      expect(find.byKey(_masterModeBack), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(_masterModeBack),
          matching: find.text(l10n.ownerMasterModeBack),
        ),
        findsOneWidget,
      );
    });

    testWidgets('tapping «‹ Салон» returns to the salon shell (salonHome '
        'resolver → last salon)', (tester) async {
      final (GoRouter router, String salonLanding) = await enterMasterMode(
        tester,
      );

      await tester.tap(find.byKey(_masterModeBack));
      await tester.pumpAndSettle();

      expect(locationOf(router), salonLanding);
      expect(find.byType(VelvetBottomNavBar), findsNothing);
    });

    testWidgets('SYSTEM BACK on the master-mode root does the SAME as '
        '«‹ Салон» — salon shell, never an app exit', (tester) async {
      final List<String> exits = recordAppExits();
      final (GoRouter router, String salonLanding) = await enterMasterMode(
        tester,
      );
      expect(router.canPop(), isFalse, reason: 'a go-entered tab root');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(exits, isEmpty, reason: 'system back must not exit the app');
      expect(locationOf(router), salonLanding);
      expect(find.byType(VelvetBottomNavBar), findsNothing);
    });

    testWidgets('an INDEPENDENT_MASTER is BOUNCED off /owner/master/profile', (
      tester,
    ) async {
      final GoRouter router = await _pumpRealRouterAs(tester, _routerMaster);

      router.go(RouteNames.ownerMasterProfile);
      await tester.pumpAndSettle();

      expect(find.byType(OwnerOwnProfileScreen), findsNothing);
      expect(locationOf(router), isNot(RouteNames.ownerMasterProfile));
    });
  });
}

// ---------------------------------------------------------------------------
// Phase 389 (24.5b) — the master tabs on the owner's own profile.
// ---------------------------------------------------------------------------

final _tabsReview = MasterReviewItem(
  id: 'r-1',
  clientDisplayName: 'Ірина К.',
  rating: 5,
  comment: 'Чудова робота',
  createdAt: DateTime(2026, 9, 1),
);

List<Object> _tabsOverrides(
  OwnerOwnProfileData data, {
  required String reviewsMasterId,
}) => <Object>[
  ..._overrides(data),
  masterReviewSummaryProvider(reviewsMasterId).overrideWith(
    (Ref ref) async => const MasterReviewSummary(
      avgRating: 5,
      reviewCount: 1,
      distribution: <int>[1, 0, 0, 0, 0],
    ),
  ),
  masterReviewsProvider(
    reviewsMasterId,
    MasterReviewSort.newest,
  ).overrideWith((Ref ref) async => <MasterReviewItem>[_tabsReview]),
];

/// The screen mounted at `/` with stub sibling destinations, so `context.go`
/// is observable via the router location.
GoRouter _tabsRouter() => GoRouter(
  routes: <RouteBase>[
    GoRoute(
      path: '/',
      builder: (_, _) => const OwnerOwnProfileScreen(embedded: true),
    ),
    GoRoute(
      path: RouteNames.ownerMasterServices,
      builder: (_, _) => const Scaffold(key: Key('stub-owner-services')),
      routes: <RouteBase>[
        GoRoute(
          path: 'setup',
          builder: (_, _) => const Scaffold(key: Key('stub-owner-setup')),
        ),
      ],
    ),
  ],
);

String _loc(GoRouter r) =>
    // router-location-ok: `.go` only in this group — no imperative match.
    r.routerDelegate.currentConfiguration.uri.toString();

void _profileTabsTests() {
  group('master tabs (phase 389)', () {
    late GoRouter router;

    Future<void> pumpTabs(
      WidgetTester tester, {
      List<MasterService> services = _services,
      String? reviewsMasterId,
    }) async {
      router = _tabsRouter();
      addTearDown(router.dispose);
      await tester.pumpRoutedApp(
        router,
        overrides: _tabsOverrides((
          owner: _owner,
          master: (_master, services),
        ), reviewsMasterId: reviewsMasterId ?? _master.id),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('tab 0 default shows bio + contacts; services/reviews absent', (
      tester,
    ) async {
      await pumpTabs(tester);
      expect(find.byKey(const Key('owner-own-profile-bio')), findsOneWidget);
      expect(
        find.byKey(const Key('owner-own-profile-contact-phone')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('owner-own-profile-categories')),
        findsNothing,
      );
      expect(find.byType(MasterReviewsBody), findsNothing);
    });

    testWidgets('tab 1 renders interactive categories; a card tap goes to the '
        'expanded master-mode services tab', (tester) async {
      await pumpTabs(tester);
      await tester.tap(find.byKey(const Key('owner-own-profile-tab-1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('owner-own-profile-bio')), findsNothing);
      final Finder card = find.byKey(const Key('owner-profile-category-NAILS'));
      expect(card, findsOneWidget);
      await tester.tap(card);
      await tester.pumpAndSettle();

      expect(
        _loc(router),
        '${RouteNames.ownerMasterServices}?expandCategory=NAILS',
      );
    });

    testWidgets('tab 1 «all services» link goes to the master-mode services '
        'tab', (tester) async {
      await pumpTabs(tester);
      await tester.tap(find.byKey(const Key('owner-own-profile-tab-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('profile-services-all-link')));
      await tester.pumpAndSettle();

      expect(_loc(router), RouteNames.ownerMasterServices);
    });

    testWidgets('tab 1 empty list: add CTA goes to master-mode setup', (
      tester,
    ) async {
      await pumpTabs(tester, services: const <MasterService>[]);
      await tester.tap(find.byKey(const Key('owner-own-profile-tab-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn-master-add-services')));
      await tester.pumpAndSettle();

      expect(_loc(router), RouteNames.ownerMasterServiceSetup);
    });

    testWidgets('tab 2 shows the owner master\'s reviews (keyed on '
        'master.id)', (tester) async {
      await pumpTabs(tester);
      await tester.tap(find.byKey(const Key('owner-own-profile-tab-2')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('master-review-r-1')), findsOneWidget);
    });

    testWidgets('tab 1: an INVALID backend category slug falls back to the '
        'plain services route, with no assert', (tester) async {
      await pumpTabs(
        tester,
        services: const <MasterService>[
          MasterService(
            id: 's-bad',
            serviceDefId: 'd-bad',
            name: 'Bad',
            durationMinutes: 30,
            priceMin: 100,
            priceDisplay: '100 ₴',
            category: 'bad slug',
          ),
        ],
      );
      await tester.tap(find.byKey(const Key('owner-own-profile-tab-1')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('owner-profile-category-BAD SLUG')),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(_loc(router), RouteNames.ownerMasterServices);
    });

    testWidgets('pull-to-refresh on tab 2 re-fetches the reviews + summary', (
      tester,
    ) async {
      int reviewCalls = 0;
      int summaryCalls = 0;
      router = _tabsRouter();
      addTearDown(router.dispose);
      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[
          ..._overrides((owner: _owner, master: (_master, _services))),
          masterReviewSummaryProvider(_master.id).overrideWith((Ref ref) async {
            summaryCalls++;
            return const MasterReviewSummary(
              avgRating: 5,
              reviewCount: 1,
              distribution: <int>[1, 0, 0, 0, 0],
            );
          }),
          masterReviewsProvider(
            _master.id,
            MasterReviewSort.newest,
          ).overrideWith((Ref ref) async {
            reviewCalls++;
            return <MasterReviewItem>[_tabsReview];
          }),
        ],
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('owner-own-profile-tab-2')));
      await tester.pumpAndSettle();
      expect(reviewCalls, 1);
      expect(summaryCalls, 1);

      await tester.fling(
        find.byType(SingleChildScrollView).first,
        const Offset(0, 400),
        1000,
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(reviewCalls, 2);
      expect(summaryCalls, 2);
      expect(find.byKey(const Key('master-review-r-1')), findsOneWidget);
    });

    testWidgets('only the ACTIVE tab body is built — 0 -> 1 -> 2 -> 0 round '
        'trip', (tester) async {
      await pumpTabs(tester);
      final Finder bio = find.byKey(const Key('owner-own-profile-bio'));
      final Finder cats = find.byKey(const Key('owner-own-profile-categories'));
      final Finder reviews = find.byType(MasterReviewsBody);

      await tester.tap(find.byKey(const Key('owner-own-profile-tab-1')));
      await tester.pumpAndSettle();
      expect(cats, findsOneWidget);
      expect(bio, findsNothing);
      expect(reviews, findsNothing);

      await tester.tap(find.byKey(const Key('owner-own-profile-tab-2')));
      await tester.pumpAndSettle();
      expect(reviews, findsOneWidget);
      expect(cats, findsNothing);
      expect(bio, findsNothing);

      await tester.tap(find.byKey(const Key('owner-own-profile-tab-0')));
      await tester.pumpAndSettle();
      expect(bio, findsOneWidget);
      expect(
        find.byKey(const Key('owner-own-profile-contact-phone')),
        findsOneWidget,
      );
      expect(cats, findsNothing);
      expect(reviews, findsNothing);
    });

    testWidgets('stat cards are display-only — a tap leaves the tab '
        'unchanged', (tester) async {
      await pumpTabs(tester);
      await tester.tap(
        find.byKey(const Key('owner-own-profile-reviews-value')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('owner-own-profile-services-value')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('owner-own-profile-bio')), findsOneWidget);
      expect(find.byType(MasterReviewsBody), findsNothing);
    });
  });
}
