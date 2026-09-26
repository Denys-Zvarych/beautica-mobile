// Widget tests for ClientPersonalInfoEditScreen (firstName + lastName only).
//
// 1:1 client transcription of the master personal-info screen with the bio field
// REMOVED. Coverage:
//   • NO bio field is rendered (assert absence of field-bio).
//   • firstName / lastName pre-populate from the cached profile.
//   • Save is disabled when pristine, enabled when dirty.
//   • Save sends a ClientProfileUpdate carrying ONLY firstName + lastName (the
//     name slice) and NOT touching location.
//
// Finders use widget Keys (M2). Layer: Widget.

import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/home/application/client_edit_profile_notifier.dart';
import 'package:beautica_mobile/features/home/data/client_profile_repository.dart';
import 'package:beautica_mobile/features/home/domain/client_profile_update.dart';
import 'package:beautica_mobile/features/home/presentation/client_personal_info_edit_screen.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/section_scaffold.dart';
import 'package:beautica_mobile/features/salon/application/salon_management_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_staff_member.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/pump_app.dart';
import '../../../helpers/velvet_snack_matchers.dart';

class _MockClientProfileRepository extends Mock
    implements ClientProfileRepository {}

// Audit-fix cycle 1 (2026-09-26) — `salonId: _kProbeSalonId` is load-bearing
// for the `salonManagementProfileProvider` scoping fix
// (`invalidateOwnIdentity`, `client_edit_profile_notifier.dart`): the
// notifier now derives the salonId to invalidate from
// `authUserSalonIdSettledOrNull(authProvider)` — i.e. `User.salonId` on the
// SAME session `_StubAuthNotifier` below seeds — rather than a bare
// whole-family invalidate. A CLIENT role with a non-null `salonId` is not a
// realistic production shape (only salon roles carry one), but this fixture
// existed for exactly this probe before the fix too — see
// `_kNonProbeSalonId`'s sibling test for the DIFFERENT-salonId negative case.
const _stubUser = User(
  id: 'user-1',
  email: 'client@beautica.ua',
  role: UserRole.client,
  firstName: 'Олена',
  lastName: 'Ковальчук',
  phoneNumber: '+380 50 123 45 67',
  salonId: _kProbeSalonId,
);

class _StubClientEditProfile extends ClientEditProfile {
  @override
  Future<User> build() => Future<User>.value(_stubUser);
}

class _StubAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async => const AuthSession.authenticated(
    user: _stubUser,
    accessToken: 'test-token',
  );
}

GoRouter _buildRouter() => GoRouter(
  initialLocation: RouteNames.clientEditPersonal,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.clientEditPersonal,
      pageBuilder: (_, _) =>
          const NoTransitionPage<void>(child: ClientPersonalInfoEditScreen()),
    ),
    GoRoute(
      path: RouteNames.clientHome,
      pageBuilder: (_, _) => const NoTransitionPage<void>(
        child: Scaffold(body: SizedBox(key: Key('stub-home'))),
      ),
    ),
  ],
);

List<Object> _overrides(_MockClientProfileRepository repo) => <Object>[
  authProvider.overrideWith(_StubAuthNotifier.new),
  clientEditProfileProvider.overrideWith(_StubClientEditProfile.new),
  clientProfileRepositoryProvider.overrideWithValue(repo),
];

Finder _field(String key) =>
    find.descendant(of: find.byKey(Key(key)), matching: find.byType(TextField));

// Phase 356 — `doneRoute` regression + the SALON_ADMIN reuse's cross-family
// refresh (`invalidateOwnIdentity`, `client_edit_profile_notifier.dart`).
// Audit-fix cycle 1 (2026-09-26) scoped that refresh's `salonManagementProfile
// Provider` invalidate to the caller's own salonId (`_stubUser.salonId`,
// derived via `authUserSalonIdSettledOrNull`) instead of a bare whole-family
// invalidate — see this file's `_kOtherSalonId` group below for the negative
// case.

/// A dummy salonId this file's probe overrides — never a real production id,
/// just a key `salonManagementProfileProvider` can be instantiated and kept
/// ALIVE against, mirroring the ONE precondition the whole invalidation fix
/// depends on: `SalonShellScreen`'s slot 0 keeping the family instance
/// warm/watched (see `invalidateOwnIdentity`'s own doc). MUST match
/// [_stubUser]'s `salonId` — the fix derives its invalidate target from the
/// signed-in session, not from this file's fixture naming.
const String _kProbeSalonId = 'salon-probe-1';

/// Counts how many times its `build()` runs — the observable proof that the
/// SCOPED `ref.invalidate(salonManagementProfileProvider(salonId))` reaches
/// an ALREADY-ALIVE keyed instance for the caller's OWN salonId, not just a
/// fresh one created after the fact.
class _CountingSalonManagementProfile extends SalonManagementProfile {
  static int buildCount = 0;

  @override
  Future<SalonManagementProfileData> build(String salonId) async {
    buildCount++;
    return (
      const Salon(id: _kProbeSalonId, name: 'Probe Salon'),
      const <SalonStaffMember>[],
    );
  }
}

/// Keeps [_kProbeSalonId]'s `salonManagementProfileProvider` instance ALIVE
/// (watched) for the lifetime of the pumped tree — the widget-tier stand-in
/// for `SalonShellScreen`'s slot 0, which is what makes the family instance
/// reachable by a bare invalidate in the first place (an unwatched
/// autoDispose element would simply not exist to invalidate).
class _KeepsProbeAlive extends ConsumerWidget {
  const _KeepsProbeAlive({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(salonManagementProfileProvider(_kProbeSalonId));
    return child;
  }
}

GoRouter _buildRouterWithProbe({String? doneRoute}) => GoRouter(
  initialLocation: RouteNames.clientEditPersonal,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.clientEditPersonal,
      pageBuilder: (_, _) => NoTransitionPage<void>(
        child: _KeepsProbeAlive(
          child: ClientPersonalInfoEditScreen(doneRoute: doneRoute),
        ),
      ),
    ),
    GoRoute(
      path: RouteNames.clientHome,
      pageBuilder: (_, _) => const NoTransitionPage<void>(
        child: Scaffold(body: SizedBox(key: Key('stub-home'))),
      ),
    ),
  ],
);

// Audit-fix cycle 1 (2026-09-26) — the scoped-invalidate regression: proves
// `invalidateOwnIdentity` touches ONLY the caller's own keyed
// `salonManagementProfileProvider` element, not the whole family. See
// `client_edit_profile_notifier.dart`'s updated doc.

/// A SECOND dummy salonId, DIFFERENT from [_kProbeSalonId] and from
/// [_stubUser.salonId] — the negative-case target: an already-alive instance
/// keyed on a salon the signed-in session does NOT belong to.
const String _kOtherSalonId = 'salon-other-1';

/// Sibling of [_CountingSalonManagementProfile], counting builds for
/// [_kOtherSalonId] — proves that salonId's already-alive instance is NOT
/// rebuilt by a save under [_stubUser] (whose `salonId` is [_kProbeSalonId]).
class _CountingOtherSalonManagementProfile extends SalonManagementProfile {
  static int buildCount = 0;

  @override
  Future<SalonManagementProfileData> build(String salonId) async {
    buildCount++;
    return (
      const Salon(id: _kOtherSalonId, name: 'Other Salon'),
      const <SalonStaffMember>[],
    );
  }
}

/// Keeps BOTH [_kProbeSalonId] AND [_kOtherSalonId] ALIVE (watched) — two
/// salon family elements warm at once, the shape a scoped (not bare) fix
/// must tell apart.
class _KeepsProbeAndOtherAlive extends ConsumerWidget {
  const _KeepsProbeAndOtherAlive({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(salonManagementProfileProvider(_kProbeSalonId));
    ref.watch(salonManagementProfileProvider(_kOtherSalonId));
    return child;
  }
}

GoRouter _buildRouterWithBothProbes({String? doneRoute}) => GoRouter(
  initialLocation: RouteNames.clientEditPersonal,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.clientEditPersonal,
      pageBuilder: (_, _) => NoTransitionPage<void>(
        child: _KeepsProbeAndOtherAlive(
          child: ClientPersonalInfoEditScreen(doneRoute: doneRoute),
        ),
      ),
    ),
    GoRoute(
      path: RouteNames.clientHome,
      pageBuilder: (_, _) => const NoTransitionPage<void>(
        child: Scaffold(body: SizedBox(key: Key('stub-home'))),
      ),
    ),
  ],
);

void main() {
  late _MockClientProfileRepository repo;

  setUpAll(() {
    registerFallbackValue(const ClientProfileUpdate());
  });

  setUp(() {
    repo = _MockClientProfileRepository();
  });

  testWidgets('does NOT render a bio field', (tester) async {
    await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('field-firstName')), findsOneWidget);
    expect(find.byKey(const Key('field-lastName')), findsOneWidget);
    expect(
      find.byKey(const Key('field-bio')),
      findsNothing,
      reason: 'clients have no bio — the bio field must be absent',
    );
  });

  testWidgets('pre-populates firstName + lastName from the cached profile', (
    tester,
  ) async {
    await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
    await tester.pump();
    await tester.pump();

    expect(
      tester.widget<TextField>(_field('field-firstName')).controller?.text,
      'Олена',
    );
    expect(
      tester.widget<TextField>(_field('field-lastName')).controller?.text,
      'Ковальчук',
    );
  });

  testWidgets('Save is disabled when pristine and enables when dirty', (
    tester,
  ) async {
    await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
    await tester.pump();
    await tester.pump();

    expect(
      tester
          .widget<NeumorphicButton>(find.byKey(const Key('btn-save-personal')))
          .onPressed,
      isNull,
    );

    await tester.enterText(_field('field-firstName'), 'Оля');
    await tester.pump();

    expect(
      tester
          .widget<NeumorphicButton>(find.byKey(const Key('btn-save-personal')))
          .onPressed,
      isNotNull,
    );
  });

  // ── PERF (P2): typing must NOT re-run the screen-level build ───────────────
  //
  // The dirty-state gating Save is driven by a ValueNotifier<bool> +
  // ValueListenableBuilder around the footer, NOT setState(() {}) on the whole
  // screen State. A keystroke must therefore leave the SectionScaffold chrome
  // (app-bar / back-button / footer + reveal-animation wrappers) at the same
  // widget object identity. Under the OLD setState-per-keystroke code build()
  // re-ran on every character and produced a brand-new SectionScaffold; this
  // identity check fails on that old behaviour and passes on the ValueNotifier
  // fix. (The avatar initials follow input via their own listenable and the
  // typed field rebuilds via FormState — neither recreates SectionScaffold.)
  testWidgets('typing a valid name does NOT re-run the screen build '
      '(SectionScaffold chrome preserved) yet still enables Save', (
    tester,
  ) async {
    await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
    await tester.pumpAndSettle();

    SectionScaffold scaffold() =>
        tester.widget<SectionScaffold>(find.byType(SectionScaffold));

    final before = scaffold();

    await tester.enterText(_field('field-firstName'), 'Оля');
    await tester.pump();

    expect(
      identical(before, scaffold()),
      isTrue,
      reason:
          'a keystroke must not re-run the screen build — the old '
          'setState(() {}) recreated the whole SectionScaffold (P2 jank).',
    );

    expect(
      tester
          .widget<NeumorphicButton>(find.byKey(const Key('btn-save-personal')))
          .onPressed,
      isNotNull,
      reason: 'the ValueListenableBuilder footer must still enable Save',
    );
  });

  testWidgets(
    'Save sends a ClientProfileUpdate with only the name slice (no location)',
    (tester) async {
      ClientProfileUpdate? captured;
      when(() => repo.updateMyProfile(any())).thenAnswer((invocation) async {
        captured = invocation.positionalArguments.first as ClientProfileUpdate;
      });

      await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
      await tester.pump();
      await tester.pump();

      await tester.enterText(_field('field-firstName'), 'Оля');
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn-save-personal')));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.firstName, 'Оля');
      expect(captured!.lastName, 'Ковальчук');
      expect(
        captured!.touchesLocation,
        isFalse,
        reason: 'the Personal screen never touches the location slice',
      );
      expect(captured!.phoneNumber, isNull);
    },
  );

  // ===========================================================================
  // Phase 356 — `doneRoute` (additive, default `null`) + the shared
  // `invalidateOwnIdentity` refresh both `ClientPersonalInfoEditScreen` and
  // `ClientContactsEditScreen` now call on save.
  // ===========================================================================
  group('doneRoute (Phase 356)', () {
    testWidgets(
      'with doneRoute null (the default), save still lands on clientHome — '
      'the pre-existing CLIENT behaviour, byte-identical',
      (tester) async {
        when(() => repo.updateMyProfile(any())).thenAnswer((_) async {});

        await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
        await tester.pump();
        await tester.pump();

        await tester.enterText(_field('field-firstName'), 'Оля');
        await tester.pump();
        await tester.tap(find.byKey(const Key('btn-save-personal')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('stub-home')),
          findsOneWidget,
          reason: 'no doneRoute passed -> the original hard-coded clientHome',
        );
      },
    );

    testWidgets(
      'with doneRoute: adminSettings, save lands on the admin hub instead of '
      'clientHome',
      (tester) async {
        when(() => repo.updateMyProfile(any())).thenAnswer((_) async {});

        final router = GoRouter(
          initialLocation: RouteNames.clientEditPersonal,
          routes: <RouteBase>[
            GoRoute(
              path: RouteNames.clientEditPersonal,
              pageBuilder: (_, _) => const NoTransitionPage<void>(
                child: ClientPersonalInfoEditScreen(
                  doneRoute: RouteNames.adminSettings,
                ),
              ),
            ),
            GoRoute(
              path: RouteNames.adminSettings,
              pageBuilder: (_, _) => const NoTransitionPage<void>(
                child: Scaffold(
                  body: SizedBox(key: Key('stub-admin-settings')),
                ),
              ),
            ),
            GoRoute(
              path: RouteNames.clientHome,
              pageBuilder: (_, _) => const NoTransitionPage<void>(
                child: Scaffold(body: SizedBox(key: Key('stub-home'))),
              ),
            ),
          ],
        );

        await tester.pumpRoutedApp(router, overrides: _overrides(repo));
        await tester.pump();
        await tester.pump();

        await tester.enterText(_field('field-firstName'), 'Оля');
        await tester.pump();
        await tester.tap(find.byKey(const Key('btn-save-personal')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('stub-admin-settings')), findsOneWidget);
        expect(
          find.byKey(const Key('stub-home')),
          findsNothing,
          reason: 'a non-null doneRoute must override the clientHome default',
        );
      },
    );

    // mobile-qa (2026-09-26, C4/Phase 356 QA pass) — client-side validation
    // on the ADMIN route specifically. `_validateFirstName`/`_save` are not
    // role-aware, but this exact screen instance (constructed with
    // `doneRoute: adminSettings`) had ZERO validation coverage anywhere in
    // this file before this test — asserts BOTH that the inline error
    // renders and that a validation failure never reaches `doneRoute`.
    testWidgets('with doneRoute: adminSettings, clearing firstName blocks save '
        'client-side — no PATCH sent, no navigation to the admin hub', (
      tester,
    ) async {
      final router = GoRouter(
        initialLocation: RouteNames.clientEditPersonal,
        routes: <RouteBase>[
          GoRoute(
            path: RouteNames.clientEditPersonal,
            pageBuilder: (_, _) => const NoTransitionPage<void>(
              child: ClientPersonalInfoEditScreen(
                doneRoute: RouteNames.adminSettings,
              ),
            ),
          ),
          GoRoute(
            path: RouteNames.adminSettings,
            pageBuilder: (_, _) => const NoTransitionPage<void>(
              child: Scaffold(body: SizedBox(key: Key('stub-admin-settings'))),
            ),
          ),
        ],
      );

      await tester.pumpRoutedApp(router, overrides: _overrides(repo));
      await tester.pump();
      await tester.pump();

      await tester.enterText(_field('field-firstName'), '');
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn-save-personal')));
      await pumpVelvetSnackIn(tester);

      final l10n = AppLocalizations.of(
        tester.element(find.byKey(const Key('field-firstName'))),
      );
      expectVelvetSnack(
        l10n.editValidationSummary,
        variant: VelvetSnackVariant.error,
      );
      verifyNever(() => repo.updateMyProfile(any()));
      expect(
        find.byKey(const Key('stub-admin-settings')),
        findsNothing,
        reason: 'a blocked save must never reach doneRoute',
      );
      expect(find.byType(ClientPersonalInfoEditScreen), findsOneWidget);

      await pumpPastVelvetSnack(tester); // drain the dwell Timer
    });

    testWidgets(
      'Save invalidates salonManagementProfileProvider — a counting override '
      'proves an ALREADY-ALIVE keyed instance actually rebuilds',
      (tester) async {
        _CountingSalonManagementProfile.buildCount = 0;
        when(() => repo.updateMyProfile(any())).thenAnswer((_) async {});

        await tester.pumpRoutedApp(
          _buildRouterWithProbe(),
          overrides: <Object>[
            ..._overrides(repo),
            salonManagementProfileProvider(
              _kProbeSalonId,
            ).overrideWith(_CountingSalonManagementProfile.new),
          ],
        );
        await tester.pump();
        await tester.pump();

        expect(
          _CountingSalonManagementProfile.buildCount,
          1,
          reason:
              'sanity: the probe must be ALIVE (watched) before save, or an '
              'invalidate afterwards would prove nothing',
        );

        await tester.enterText(_field('field-firstName'), 'Оля');
        await tester.pump();
        await tester.tap(find.byKey(const Key('btn-save-personal')));
        await tester.pumpAndSettle();

        expect(
          _CountingSalonManagementProfile.buildCount,
          greaterThanOrEqualTo(2),
          reason:
              'invalidateOwnIdentity must invalidate the CALLER\'S OWN keyed '
              'salonManagementProfileProvider(salonId) element (salonId == '
              '_stubUser.salonId == _kProbeSalonId) — an already-alive keyed '
              'instance must rebuild, not merely a fresh one created after '
              'the fact',
        );
      },
    );

    testWidgets('Save does NOT invalidate a DIFFERENT salonId\'s '
        'salonManagementProfileProvider instance — the fix is SCOPED to the '
        'caller\'s own salon, not a bare whole-family invalidate', (
      tester,
    ) async {
      _CountingSalonManagementProfile.buildCount = 0;
      _CountingOtherSalonManagementProfile.buildCount = 0;
      when(() => repo.updateMyProfile(any())).thenAnswer((_) async {});

      await tester.pumpRoutedApp(
        _buildRouterWithBothProbes(),
        overrides: <Object>[
          ..._overrides(repo),
          salonManagementProfileProvider(
            _kProbeSalonId,
          ).overrideWith(_CountingSalonManagementProfile.new),
          salonManagementProfileProvider(
            _kOtherSalonId,
          ).overrideWith(_CountingOtherSalonManagementProfile.new),
        ],
      );
      await tester.pump();
      await tester.pump();

      expect(
        _CountingSalonManagementProfile.buildCount,
        1,
        reason: 'sanity: both probes must be ALIVE before save',
      );
      expect(
        _CountingOtherSalonManagementProfile.buildCount,
        1,
        reason: 'sanity: both probes must be ALIVE before save',
      );

      await tester.enterText(_field('field-firstName'), 'Оля');
      await tester.pump();
      await tester.tap(find.byKey(const Key('btn-save-personal')));
      await tester.pumpAndSettle();

      expect(
        _CountingSalonManagementProfile.buildCount,
        greaterThanOrEqualTo(2),
        reason: 'the caller\'s own salonId must still rebuild',
      );
      expect(
        _CountingOtherSalonManagementProfile.buildCount,
        1,
        reason:
            'a DIFFERENT salonId\'s already-alive instance must NOT '
            'rebuild — the bare whole-family invalidate this fix replaced '
            'would have rebuilt this one too, which is exactly the LOW '
            'perf finding this test guards against',
      );
    });

    // -------------------------------------------------------------------
    // Audit-fix cycle 2 (2026-09-26, LOW from QA) — the NO-HISTORY back
    // fallback (`onBack`'s `context.go(...)` branch, only reached when
    // `context.canPop()` is false). `back navigation from the reused
    // editors returns to the hub` in `admin_own_profile_screen_test.dart`
    // only exercises the PUSHED case (canPop() true); these two cases
    // cover the OTHER branch directly, at the widget layer.
    // -------------------------------------------------------------------
    testWidgets(
      'CLIENT, no back stack: back falls back to clientMenu (doneRoute '
      'null, pre-existing behaviour unchanged)',
      (tester) async {
        final router = GoRouter(
          initialLocation: RouteNames.clientEditPersonal,
          routes: <RouteBase>[
            GoRoute(
              path: RouteNames.clientEditPersonal,
              pageBuilder: (_, _) => const NoTransitionPage<void>(
                child: ClientPersonalInfoEditScreen(),
              ),
            ),
            GoRoute(
              path: RouteNames.clientMenu,
              pageBuilder: (_, _) => const NoTransitionPage<void>(
                child: Scaffold(body: SizedBox(key: Key('stub-client-menu'))),
              ),
            ),
          ],
        );

        await tester.pumpRoutedApp(router, overrides: _overrides(repo));
        await tester.pump();
        await tester.pump();

        await tester.tap(find.byKey(const Key('btn-back-personal')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('stub-client-menu')),
          findsOneWidget,
          reason:
              'no doneRoute and no back stack -> the CLIENT default '
              '(clientMenu) must be unchanged',
        );
      },
    );

    testWidgets('SALON_ADMIN, no back stack: back falls back to doneRoute '
        '(adminSettings), NOT clientMenu', (tester) async {
      final router = GoRouter(
        initialLocation: RouteNames.adminEditPersonal,
        routes: <RouteBase>[
          GoRoute(
            path: RouteNames.adminEditPersonal,
            pageBuilder: (_, _) => const NoTransitionPage<void>(
              child: ClientPersonalInfoEditScreen(
                doneRoute: RouteNames.adminSettings,
              ),
            ),
          ),
          GoRoute(
            path: RouteNames.adminSettings,
            pageBuilder: (_, _) => const NoTransitionPage<void>(
              child: Scaffold(
                body: SizedBox(key: Key('stub-admin-settings-back')),
              ),
            ),
          ),
          GoRoute(
            path: RouteNames.clientMenu,
            pageBuilder: (_, _) => const NoTransitionPage<void>(
              child: Scaffold(body: SizedBox(key: Key('stub-client-menu'))),
            ),
          ),
        ],
      );

      await tester.pumpRoutedApp(router, overrides: _overrides(repo));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn-back-personal')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('stub-admin-settings-back')),
        findsOneWidget,
        reason:
            'a SALON_ADMIN reaching this route with no back stack must '
            'fall back to their OWN doneRoute (adminSettings), never the '
            'CLIENT clientMenu route (which bounces a non-CLIENT session)',
      );
      expect(find.byKey(const Key('stub-client-menu')), findsNothing);
    });
  });
}
