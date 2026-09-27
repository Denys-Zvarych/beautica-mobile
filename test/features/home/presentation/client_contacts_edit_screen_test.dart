// Widget tests for ClientContactsEditScreen (phone only).
//
// 1:1 client transcription of the master contacts screen with the Instagram
// field REMOVED. Coverage:
//   • the phone field renders and pre-populates from the cached profile.
//   • NO Instagram field is rendered (assert absence of field-instagram).
//   • Save sends a ClientProfileUpdate carrying only the phone slice.
//   • The repository is never asked to send instagram (verified at the unit
//     layer in client_profile_repository_test.dart).
//
// Finders use widget Keys (M2). Layer: Widget.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/home/application/client_edit_profile_notifier.dart';
import 'package:beautica_mobile/features/home/data/client_profile_repository.dart';
import 'package:beautica_mobile/features/home/domain/client_profile_update.dart';
import 'package:beautica_mobile/features/home/presentation/client_contacts_edit_screen.dart';
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
// whole-family invalidate.
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
  initialLocation: RouteNames.clientEditContacts,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.clientEditContacts,
      pageBuilder: (_, _) =>
          const NoTransitionPage<void>(child: ClientContactsEditScreen()),
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
// refresh (`invalidateOwnIdentity`, `client_edit_profile_notifier.dart`). See
// `client_personal_info_edit_screen_test.dart`'s identical fixtures for the
// full rationale — mirrored here rather than shared, since both screens'
// tests are otherwise fully independent files.
//
// Audit-fix cycle 1 (2026-09-26) scoped that refresh's
// `salonManagementProfileProvider` invalidate to the caller's own salonId
// (`_stubUser.salonId`) instead of a bare whole-family invalidate — see the
// `_kOtherSalonId` fixtures below for the negative case.
const String _kProbeSalonId = 'salon-probe-1';

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
  initialLocation: RouteNames.clientEditContacts,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.clientEditContacts,
      pageBuilder: (_, _) => NoTransitionPage<void>(
        child: _KeepsProbeAlive(
          child: ClientContactsEditScreen(doneRoute: doneRoute),
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
  initialLocation: RouteNames.clientEditContacts,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.clientEditContacts,
      pageBuilder: (_, _) => NoTransitionPage<void>(
        child: _KeepsProbeAndOtherAlive(
          child: ClientContactsEditScreen(doneRoute: doneRoute),
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

  testWidgets(
    'renders the phone field and does NOT render an Instagram field',
    (tester) async {
      await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('field-phone')), findsOneWidget);
      expect(
        find.byKey(const Key('field-instagram')),
        findsNothing,
        reason:
            'clients have no Instagram — the master instagram field key must '
            'be absent',
      );
    },
  );

  testWidgets('pre-populates the phone from the cached profile', (
    tester,
  ) async {
    await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
    await tester.pump();
    await tester.pump();

    expect(
      tester.widget<TextField>(_field('field-phone')).controller?.text,
      '+380 50 123 45 67',
    );
  });

  testWidgets(
    'Save sends a ClientProfileUpdate with only the phone slice (no location)',
    (tester) async {
      ClientProfileUpdate? captured;
      when(() => repo.updateMyProfile(any())).thenAnswer((invocation) async {
        captured = invocation.positionalArguments.first as ClientProfileUpdate;
      });

      await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
      await tester.pump();
      await tester.pump();

      await tester.enterText(_field('field-phone'), '+380 67 000 11 22');
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn-save-contacts')));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.phoneNumber, isNotNull);
      expect(captured!.firstName, isNull);
      expect(captured!.lastName, isNull);
      expect(
        captured!.touchesLocation,
        isFalse,
        reason: 'the Contacts screen never touches the location slice',
      );
    },
  );

  testWidgets(
    'a ServerFailure on save surfaces an error snackbar and does NOT navigate '
    'away',
    (tester) async {
      when(
        () => repo.updateMyProfile(any()),
      ).thenThrow(const ServerFailure(statusCode: 500));

      await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
      await tester.pump();
      await tester.pump();

      // Make the form dirty so the Save CTA is enabled.
      await tester.enterText(_field('field-phone'), '+380 67 000 11 22');
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn-save-contacts')));
      await pumpVelvetSnackIn(tester); // run the save future, mount + enter

      // The screen stays put — no navigation to the stub home occurred.
      expect(find.byKey(const Key('stub-home')), findsNothing);
      expect(find.byKey(const Key('field-phone')), findsOneWidget);

      // The localized ServerFailure message renders in a root-overlay
      // VelvetSnack — NOT a SnackBar/ScaffoldMessenger descendant (see
      // test/helpers/velvet_snack_matchers.dart header).
      final BuildContext ctx = tester.element(
        find.byKey(const Key('field-phone')),
      );
      final String expected = AppLocalizations.of(ctx).errServer;
      expectVelvetSnack(expected, variant: VelvetSnackVariant.error);

      await pumpPastVelvetSnack(tester); // drain the dwell Timer
    },
  );

  testWidgets('renders the CLIENT phone privacy note (not the master one)', (
    tester,
  ) async {
    await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
    await tester.pump();
    await tester.pump();

    final BuildContext ctx = tester.element(
      find.byKey(const Key('field-phone')),
    );
    final AppLocalizations l10n = AppLocalizations.of(ctx);

    expect(
      find.text(l10n.clientPhonePrivacyNote),
      findsOneWidget,
      reason:
          'the client phone field shows the client-appropriate privacy note '
          '(masters do not see the client number)',
    );
    expect(
      find.text(l10n.phonePrivacyNote),
      findsNothing,
      reason:
          'the master-context privacy note must not appear on the client '
          'screen',
    );
  });

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

        await tester.enterText(_field('field-phone'), '+380 67 000 11 22');
        await tester.pump();
        await tester.tap(find.byKey(const Key('btn-save-contacts')));
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
          initialLocation: RouteNames.clientEditContacts,
          routes: <RouteBase>[
            GoRoute(
              path: RouteNames.clientEditContacts,
              pageBuilder: (_, _) => const NoTransitionPage<void>(
                child: ClientContactsEditScreen(
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

        await tester.enterText(_field('field-phone'), '+380 67 000 11 22');
        await tester.pump();
        await tester.tap(find.byKey(const Key('btn-save-contacts')));
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
    // on the ADMIN route specifically. `_validatePhone`/`_save` are not
    // role-aware, but this exact screen instance (constructed with
    // `doneRoute: adminSettings`) had ZERO validation coverage anywhere in
    // this file before this test — asserts BOTH that the error snack fires
    // and that a validation failure never reaches `doneRoute`.
    testWidgets('with doneRoute: adminSettings, clearing the phone blocks save '
        'client-side — no PATCH sent, no navigation to the admin hub', (
      tester,
    ) async {
      final router = GoRouter(
        initialLocation: RouteNames.clientEditContacts,
        routes: <RouteBase>[
          GoRoute(
            path: RouteNames.clientEditContacts,
            pageBuilder: (_, _) => const NoTransitionPage<void>(
              child: ClientContactsEditScreen(
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

      await tester.enterText(_field('field-phone'), '');
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn-save-contacts')));
      await pumpVelvetSnackIn(tester);

      final l10n = AppLocalizations.of(
        tester.element(find.byKey(const Key('field-phone'))),
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
      expect(find.byType(ClientContactsEditScreen), findsOneWidget);

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

        await tester.enterText(_field('field-phone'), '+380 67 000 11 22');
        await tester.pump();
        await tester.tap(find.byKey(const Key('btn-save-contacts')));
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

      await tester.enterText(_field('field-phone'), '+380 67 000 11 22');
      await tester.pump();
      await tester.tap(find.byKey(const Key('btn-save-contacts')));
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
          initialLocation: RouteNames.clientEditContacts,
          routes: <RouteBase>[
            GoRoute(
              path: RouteNames.clientEditContacts,
              pageBuilder: (_, _) => const NoTransitionPage<void>(
                child: ClientContactsEditScreen(),
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

        await tester.tap(find.byKey(const Key('btn-back-contacts')));
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
        initialLocation: RouteNames.adminEditContacts,
        routes: <RouteBase>[
          GoRoute(
            path: RouteNames.adminEditContacts,
            pageBuilder: (_, _) => const NoTransitionPage<void>(
              child: ClientContactsEditScreen(
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

      await tester.tap(find.byKey(const Key('btn-back-contacts')));
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
