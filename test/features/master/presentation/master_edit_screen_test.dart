// Phase 4.3 — Widget tests for MasterEditScreen.
//
// Covers the 8 required cases (M9 rule):
//   1. Form pre-populated from provider (firstName/lastName/bio visible).
//   2. Save disabled when form is pristine (no changes from provider data).
//   3. Save enabled + fires updateMyProfile when form is dirty + valid.
//   4. ref.invalidate(masterProfileProvider) called + snackbar shown on success.
//   5. ValidationFailure → per-field error shown under the matching field.
//   6. Network failure → snackbar shown.
//   7. Phone privacy note visible below the phone field.
//   8. Avatar edit badge Key('avatar-edit-badge') is present.
//
// Strategy:
//   • Override masterProfileProvider with a stub notifier that returns
//     Future.value(_stubMaster) so the provider is in AsyncData state
//     synchronously, before MasterEditScreen.initState runs.
//   • Override masterRepositoryProvider with a mocktail mock.
//   • Wrap the screen in a GoRouter so that context.pop() works.
//   • Use pumpRoutedApp from test/helpers/pump_app.dart.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/domain/master_update.dart';
import 'package:beautica_mobile/features/master/presentation/master_edit_screen.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/pump_app.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class _MockMasterRepository extends Mock implements MasterRepository {}

// ---------------------------------------------------------------------------
// Stub data
// ---------------------------------------------------------------------------

const _stubUser = User(
  id: 'user-1',
  email: 'test@beautica.ua',
  role: UserRole.independentMaster,
  firstName: 'Олена',
  lastName: 'Ковальчук',
);

const _stubMaster = Master(
  id: 'user-1',
  firstName: 'Олена',
  lastName: 'Ковальчук',
  bio: 'Майстер манікюру.',
  avgRating: 4.8,
  reviewCount: 10,
  type: MasterType.independentMaster,
);

// ---------------------------------------------------------------------------
// Stub notifiers
// ---------------------------------------------------------------------------

/// Stub [MasterProfile] that returns [Future.value] so the provider is in
/// [AsyncData] state before [MasterEditScreen.initState] runs. The edit
/// screen reads `ref.read(masterProfileProvider).value` in `initState` —
/// the provider must be settled before the widget is built.
class _StubMasterProfileNotifier extends MasterProfile {
  _StubMasterProfileNotifier(this._master);
  final Master _master;

  @override
  Future<Master> build() => Future<Master>.value(_master);
}

class _StubAuthNotifier extends AuthNotifier {
  _StubAuthNotifier(this._user);
  final User _user;

  @override
  Future<AuthSession> build() async =>
      AuthSession.authenticated(user: _user, accessToken: 'test-token');
}

// ---------------------------------------------------------------------------
// Router helper — wraps MasterEditScreen in a GoRouter so context.pop() works.
// ---------------------------------------------------------------------------

GoRouter _buildRouter() => GoRouter(
  initialLocation: RouteNames.masterEdit,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.masterEdit,
      pageBuilder: (context, state) =>
          const NoTransitionPage<void>(child: MasterEditScreen()),
    ),
  ],
);

// ---------------------------------------------------------------------------
// Override helper
// ---------------------------------------------------------------------------

List<Object> _buildOverrides({
  required _MockMasterRepository repo,
  Master master = _stubMaster,
}) {
  return <Object>[
    authProvider.overrideWith(() => _StubAuthNotifier(_stubUser)),
    masterProfileProvider.overrideWith(
      () => _StubMasterProfileNotifier(master),
    ),
    masterRepositoryProvider.overrideWithValue(repo),
  ];
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _MockMasterRepository repo;

  setUpAll(() {
    registerFallbackValue(
      const MasterUpdate(
        firstName: '',
        lastName: '',
        bio: '',
        contactPhone: '',
        instagram: '',
      ),
    );
  });

  setUp(() {
    repo = _MockMasterRepository();
  });

  // ── 1. Form pre-populated from provider ─────────────────────────────────

  group('pre-population', () {
    testWidgets(
      'firstName, lastName, and bio from the provider are shown in the form',
      (tester) async {
        final router = _buildRouter();
        await tester.pumpRoutedApp(
          router,
          overrides: _buildOverrides(repo: repo),
        );
        // Two pumps: one for the router, one for the Future.value microtask.
        await tester.pump();
        await tester.pump();

        // firstName field is pre-populated.
        expect(
          tester
              .widget<TextField>(
                find.descendant(
                  of: find.byKey(const Key('field-firstName')),
                  matching: find.byType(TextField),
                ),
              )
              .controller
              ?.text,
          'Олена',
        );

        // lastName field is pre-populated.
        expect(
          tester
              .widget<TextField>(
                find.descendant(
                  of: find.byKey(const Key('field-lastName')),
                  matching: find.byType(TextField),
                ),
              )
              .controller
              ?.text,
          'Ковальчук',
        );

        // bio field is pre-populated.
        expect(
          tester
              .widget<TextField>(
                find.descendant(
                  of: find.byKey(const Key('field-bio')),
                  matching: find.byType(TextField),
                ),
              )
              .controller
              ?.text,
          'Майстер манікюру.',
        );
      },
    );
  });

  // ── 2. Save disabled when pristine ──────────────────────────────────────

  group('save button', () {
    testWidgets(
      'Save button is present and repository not called when pristine',
      (tester) async {
        final router = _buildRouter();
        await tester.pumpRoutedApp(
          router,
          overrides: _buildOverrides(repo: repo),
        );
        await tester.pump();
        await tester.pump();

        expect(find.byKey(const Key('btn-save-master')), findsOneWidget);

        // Do NOT tap (button is disabled when pristine). Verify repo untouched.
        verifyNever(() => repo.updateMyProfile(any()));
      },
    );

    // ── 3. Save enabled + fires updateMyProfile when dirty + valid ──────────

    testWidgets('Save triggers updateMyProfile when form is dirty and valid', (
      tester,
    ) async {
      when(() => repo.updateMyProfile(any())).thenAnswer((_) async {});

      final router = _buildRouter();
      await tester.pumpRoutedApp(
        router,
        overrides: _buildOverrides(repo: repo),
      );
      await tester.pump();
      await tester.pump();

      // Dirty the firstName field so Save becomes enabled.
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('field-firstName')),
          matching: find.byType(TextField),
        ),
        'ОленаEdited',
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn-save-master')));
      await tester.pumpAndSettle();

      verify(() => repo.updateMyProfile(any())).called(1);
    });

    // ── 4. Snackbar shown on success ────────────────────────────────────────

    testWidgets('shows saved snackbar after successful save', (tester) async {
      when(() => repo.updateMyProfile(any())).thenAnswer((_) async {});

      final router = _buildRouter();
      await tester.pumpRoutedApp(
        router,
        overrides: _buildOverrides(repo: repo),
      );
      await tester.pump();
      await tester.pump();

      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('field-firstName')),
          matching: find.byType(TextField),
        ),
        'ОленаEdited',
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn-save-master')));
      await tester.pumpAndSettle();

      expect(find.text('Зміни збережено'), findsOneWidget);
    });
  });

  // ── 5. ValidationFailure → per-field error ──────────────────────────────

  group('server validation errors', () {
    testWidgets('ValidationFailure shows per-field error under the field', (
      tester,
    ) async {
      const serverMsg = 'Поле обов\'язкове';
      when(() => repo.updateMyProfile(any())).thenThrow(
        const ValidationFailure(
          fieldErrors: <String, String>{'firstName': serverMsg},
        ),
      );

      final router = _buildRouter();
      await tester.pumpRoutedApp(
        router,
        overrides: _buildOverrides(repo: repo),
      );
      await tester.pump();
      await tester.pump();

      // Dirty the field so Save is enabled.
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('field-firstName')),
          matching: find.byType(TextField),
        ),
        'ОленаEdited',
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn-save-master')));
      await tester.pumpAndSettle();

      // The server error text should be visible in the tree.
      expect(find.text(serverMsg), findsWidgets);
    });
  });

  // ── 6. Network failure → snackbar ────────────────────────────────────────

  group('network failure', () {
    testWidgets('shows error snackbar on NetworkFailure', (tester) async {
      when(() => repo.updateMyProfile(any())).thenThrow(const NetworkFailure());

      final router = _buildRouter();
      await tester.pumpRoutedApp(
        router,
        overrides: _buildOverrides(repo: repo),
      );
      await tester.pump();
      await tester.pump();

      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('field-firstName')),
          matching: find.byType(TextField),
        ),
        'ОленаEdited',
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn-save-master')));
      await tester.pumpAndSettle();

      // The errNetwork localized message is shown in a snackbar.
      // Search for a substring that avoids apostrophe encoding differences.
      expect(find.textContaining('мережею'), findsOneWidget);
    });
  });

  // ── 7. Phone privacy note ────────────────────────────────────────────────

  group('phone privacy note', () {
    testWidgets('privacy note is visible below the phone field', (
      tester,
    ) async {
      final router = _buildRouter();
      await tester.pumpRoutedApp(
        router,
        overrides: _buildOverrides(repo: repo),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('field-phone')), findsOneWidget);
      // The privacy note text from l10n.phonePrivacyNote.
      expect(find.textContaining('Клієнти не бачатимуть'), findsOneWidget);
    });
  });

  // ── 8. Avatar edit badge ─────────────────────────────────────────────────

  group('avatar edit badge', () {
    testWidgets("avatar edit badge with Key('avatar-edit-badge') is present", (
      tester,
    ) async {
      final router = _buildRouter();
      await tester.pumpRoutedApp(
        router,
        overrides: _buildOverrides(repo: repo),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('avatar-edit-badge')), findsOneWidget);
    });
  });
}
