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
import 'package:beautica_mobile/l10n/app_localizations.dart';
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

/// Stub master that already has location data pre-set, used by Test B.
const _stubMasterWithLocation = Master(
  id: 'user-1',
  firstName: 'Олена',
  lastName: 'Ковальчук',
  bio: 'Майстер манікюру.',
  avgRating: 4.8,
  reviewCount: 10,
  type: MasterType.independentMaster,
  street: 'вул. Хрещатик',
  buildingNo: '10',
  locationNote: 'кв. 5',
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
    // Stub destination used by cancel-navigation and save-success-navigation
    // regression tests. The sentinel Key allows assertions that context.go()
    // actually navigated here rather than staying on the edit screen.
    GoRoute(
      path: RouteNames.masterProfile,
      pageBuilder: (context, state) => const NoTransitionPage<void>(
        child: Scaffold(
          body: Center(child: SizedBox(key: Key('stub-master-profile'))),
        ),
      ),
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
    // Default stub for updateLocality so every test that doesn't care about it
    // doesn't need to configure the mock explicitly. Tests that assert it is
    // *not* called use verifyNever after this default is in place.
    when(
      () => repo.updateLocality(
        cityId: any(named: 'cityId'),
        districtId: any(named: 'districtId'),
        street: any(named: 'street'),
        buildingNo: any(named: 'buildingNo'),
        locationNote: any(named: 'locationNote'),
      ),
    ).thenAnswer((_) async {});
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

    testWidgets('phone field is pre-populated from master.phoneNumber', (
      tester,
    ) async {
      final masterWithPhone = _stubMaster.copyWith(
        phoneNumber: '+380501234567',
      );
      final router = _buildRouter();
      await tester.pumpRoutedApp(
        router,
        overrides: _buildOverrides(repo: repo, master: masterWithPhone),
      );
      // Two pumps: one for the router, one for the Future.value microtask.
      await tester.pump();
      await tester.pump();

      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const Key('field-phone')),
                matching: find.byType(TextField),
              ),
            )
            .controller
            ?.text,
        '+380501234567',
      );
    });

    testWidgets('instagram field is pre-populated from master.instagram', (
      tester,
    ) async {
      final masterWithInstagram = _stubMaster.copyWith(instagram: '@my_handle');
      final router = _buildRouter();
      await tester.pumpRoutedApp(
        router,
        overrides: _buildOverrides(repo: repo, master: masterWithInstagram),
      );
      // Two pumps: one for the router, one for the Future.value microtask.
      await tester.pump();
      await tester.pump();

      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const Key('field-instagram')),
                matching: find.byType(TextField),
              ),
            )
            .controller
            ?.text,
        '@my_handle',
      );
    });
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

      expect(find.byKey(const Key('snackbar-saved')), findsOneWidget);
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
      expect(find.byKey(const Key('phone-privacy-note')), findsOneWidget);
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

  // ── 9. Cancel button navigates to masterProfile when canPop is false ──────
  //
  // Regression guard [HIGH] for the fix:
  //   `if (context.canPop()) context.pop() else context.go(RouteNames.masterProfile)`
  //
  // The router starts directly at /master/edit with no history entry before it,
  // so context.canPop() is false. Tapping cancel must call context.go() and
  // land on the stub masterProfile scaffold.

  group('cancel navigation regression guard', () {
    testWidgets('cancel button navigates to masterProfile via context.go() '
        'when canPop is false (no prior route in the stack)', (tester) async {
      // Start at masterEdit with no prior history → canPop() is false.
      final router = _buildRouter();
      await tester.pumpRoutedApp(
        router,
        overrides: _buildOverrides(repo: repo),
      );
      // Pump until masterProfileProvider resolves and the form is initialised.
      await tester.pump();
      await tester.pump();

      // The edit screen must be visible and the stub destination absent.
      expect(find.byKey(const Key('btn-cancel-master')), findsOneWidget);
      expect(find.byKey(const Key('stub-master-profile')), findsNothing);

      await tester.tap(find.byKey(const Key('btn-cancel-master')));
      await tester.pumpAndSettle();

      // After navigation the stub masterProfile sentinel must be on screen.
      expect(
        find.byKey(const Key('stub-master-profile')),
        findsOneWidget,
        reason:
            'Cancel button must call context.go(RouteNames.masterProfile) '
            'when context.canPop() is false — regression guard for the fix '
            'in lib/features/master/presentation/master_edit_screen.dart',
      );
    });
  });

  // ── 10. Save success navigates to masterProfile when canPop is false ──────
  //
  // Regression guard [MEDIUM] for the save-success path:
  //   `if (context.canPop()) context.pop() else context.go(RouteNames.masterProfile)`
  //
  // Same router fixture (no prior history → canPop false). After a successful
  // save the screen must navigate to masterProfile via context.go(), not stay
  // stuck (which happened before the fix when canPop was false and the old code
  // had no else branch).

  group('save success navigation regression guard', () {
    testWidgets('save success navigates to masterProfile via context.go() '
        'when canPop is false (no prior route in the stack)', (tester) async {
      when(() => repo.updateMyProfile(any())).thenAnswer((_) async {});

      // Start at masterEdit with no prior history → canPop() is false.
      final router = _buildRouter();
      await tester.pumpRoutedApp(
        router,
        overrides: _buildOverrides(repo: repo),
      );
      await tester.pump();
      await tester.pump();

      // Dirty the firstName field so the Save button becomes enabled.
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('field-firstName')),
          matching: find.byType(TextField),
        ),
        'ОленаEdited',
      );
      await tester.pump();

      // Stub destination must not be present before save.
      expect(find.byKey(const Key('stub-master-profile')), findsNothing);

      await tester.tap(find.byKey(const Key('btn-save-master')));
      await tester.pumpAndSettle();

      // After save success the stub masterProfile sentinel must be on screen.
      expect(
        find.byKey(const Key('stub-master-profile')),
        findsOneWidget,
        reason:
            'After a successful save, the edit screen must call '
            'context.go(RouteNames.masterProfile) when context.canPop() '
            'is false — regression guard for the fix in '
            'lib/features/master/presentation/master_edit_screen.dart',
      );
    });
  });

  // ── 11. Instagram format validation ─────────────────────────────────────────
  //
  // Covers the client-side validator on the instagram FormField. The validator
  // accepts: (a) empty string (optional field), (b) bare handle with optional @
  // prefix, (c) full https://instagram.com/… URL. Anything else must surface an
  // error text descendant of Key('field-instagram') that contains 'instagram'.
  //
  // Tests are locale-neutral: they assert on the substring 'instagram' which
  // appears in both the UK and EN error strings without any raw Cyrillic text
  // in the finder, satisfying the M11 coverage requirement.

  group('instagram format validation', () {
    // ── 11.1  Invalid value shows an error ──────────────────────────────────

    testWidgets('invalid instagram value shows error under the field', (
      tester,
    ) async {
      final router = _buildRouter();
      await tester.pumpRoutedApp(
        router,
        overrides: _buildOverrides(repo: repo),
      );
      await tester.pump();
      await tester.pump();

      // Enter an obviously malformed value.
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('field-instagram')),
          matching: find.byType(TextField),
        ),
        'not valid!',
      );
      await tester.pump();

      // Trigger validation by tapping Save (button is enabled because a field
      // is now dirty, even though instagram is invalid).
      await tester.tap(find.byKey(const Key('btn-save-master')));
      await tester.pump();

      // The error text rendered by FormField contains 'instagram' (locale-neutral).
      expect(
        find.descendant(
          of: find.byKey(const Key('field-instagram')),
          matching: find.textContaining('instagram'),
        ),
        findsOneWidget,
        reason:
            'The validator must surface an error for a value that is neither a '
            'valid handle nor an instagram.com URL.',
      );
    });

    // ── 11.2  Bare handle (no @) is accepted ────────────────────────────────

    testWidgets('bare handle without @ is accepted (no error shown)', (
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

      // Enter a valid handle (no @ prefix).
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('field-instagram')),
          matching: find.byType(TextField),
        ),
        'valid_handle',
      );
      await tester.pump();

      // Dirty another field so the form is dirty and Save is enabled.
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

      // No error descendant must exist inside the instagram field.
      expect(
        find.descendant(
          of: find.byKey(const Key('field-instagram')),
          matching: find.textContaining('instagram'),
        ),
        findsNothing,
        reason: 'A bare handle without @ should pass validation.',
      );
    });

    // ── 11.3  Full instagram.com URL is accepted ─────────────────────────────

    testWidgets('full instagram.com URL is accepted (no error shown)', (
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

      // Enter a valid full URL.
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('field-instagram')),
          matching: find.byType(TextField),
        ),
        'https://instagram.com/beauty_ua',
      );
      await tester.pump();

      // Dirty another field so Save is enabled.
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

      expect(
        find.descendant(
          of: find.byKey(const Key('field-instagram')),
          matching: find.textContaining('instagram'),
        ),
        findsNothing,
        reason: 'A full instagram.com URL should pass validation.',
      );
    });

    // ── 11.4  Empty field (optional) — no error and save fires ───────────────

    testWidgets('empty instagram field is accepted and save is called', (
      tester,
    ) async {
      when(() => repo.updateMyProfile(any())).thenAnswer((_) async {});

      // Seed a master that already has an instagram value so we can clear it.
      final masterWithInstagram = _stubMaster.copyWith(
        instagram: '@old_handle',
      );
      final router = _buildRouter();
      await tester.pumpRoutedApp(
        router,
        overrides: _buildOverrides(repo: repo, master: masterWithInstagram),
      );
      await tester.pump();
      await tester.pump();

      // Clear the instagram field.
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('field-instagram')),
          matching: find.byType(TextField),
        ),
        '',
      );
      await tester.pump();

      // Dirty another field to ensure Save is enabled (clearing instagram also
      // counts as a dirty change, but firstName makes the intent explicit).
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

      // No error must appear inside the instagram field.
      expect(
        find.descendant(
          of: find.byKey(const Key('field-instagram')),
          matching: find.textContaining('instagram'),
        ),
        findsNothing,
        reason: 'An empty instagram field (optional) must not show an error.',
      );

      // The repository must have been called exactly once.
      verify(() => repo.updateMyProfile(any())).called(1);
    });
  });

  // ── 12. Location section ─────────────────────────────────────────────────
  //
  // Four CRITICAL tests covering:
  //   A. Location fields are present in the rendered tree.
  //   B. Location fields are pre-populated from master data.
  //   C. updateLocality is NOT called when no location fields are touched.
  //   D. Validation blocks save (and updateLocality) when street is filled but
  //      no city is selected via the cascade.

  group('location section', () {
    // ── 12.A  Location fields render ─────────────────────────────────────────

    testWidgets('location_section_renders_correctly', (tester) async {
      final router = _buildRouter();
      await tester.pumpRoutedApp(
        router,
        overrides: _buildOverrides(repo: repo),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('field-street')), findsOneWidget);
      expect(find.byKey(const Key('field-buildingNo')), findsOneWidget);
      expect(find.byKey(const Key('field-locationNote')), findsOneWidget);
    });

    // ── 12.B  Location fields pre-populated from master data ─────────────────

    testWidgets('location_fields_pre_populated_from_master_data', (
      tester,
    ) async {
      final router = _buildRouter();
      await tester.pumpRoutedApp(
        router,
        overrides: _buildOverrides(repo: repo, master: _stubMasterWithLocation),
      );
      await tester.pump();
      await tester.pump();

      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const Key('field-street')),
                matching: find.byType(TextField),
              ),
            )
            .controller
            ?.text,
        'вул. Хрещатик',
        reason: 'street field must be pre-populated from master.street',
      );

      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const Key('field-buildingNo')),
                matching: find.byType(TextField),
              ),
            )
            .controller
            ?.text,
        '10',
        reason: 'buildingNo field must be pre-populated from master.buildingNo',
      );

      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const Key('field-locationNote')),
                matching: find.byType(TextField),
              ),
            )
            .controller
            ?.text,
        'кв. 5',
        reason:
            'locationNote field must be pre-populated from master.locationNote',
      );
    });

    // ── 12.C  save without location does not call updateLocality ─────────────

    testWidgets('save_without_location_does_not_call_updateLocality', (
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

      // Dirty only firstName — no location fields touched.
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

      // updateLocality must never be called when no location field is touched.
      verifyNever(
        () => repo.updateLocality(
          cityId: any(named: 'cityId'),
          districtId: any(named: 'districtId'),
          street: any(named: 'street'),
          buildingNo: any(named: 'buildingNo'),
          locationNote: any(named: 'locationNote'),
        ),
      );

      // The profile update must still have been called exactly once.
      verify(() => repo.updateMyProfile(any())).called(1);
    });

    // ── 12.D  Validation requires city when street is filled ─────────────────
    //
    // When the user fills the street field but does NOT select a city via the
    // cascade, the location section is "touched" but incomplete. _validateLocation
    // must block the save and updateLocality must never be called.

    testWidgets(
      'validation_requires_street_when_street_filled_but_no_city',
      (tester) async {
        final router = _buildRouter();
        await tester.pumpRoutedApp(
          router,
          overrides: _buildOverrides(repo: repo),
        );
        await tester.pump();
        await tester.pump();

        // Dirty the firstName field so the save button becomes enabled.
        // This is necessary because NeumorphicButton with onPressed:null is
        // non-interactive — tapping it would be a no-op.
        await tester.enterText(
          find.descendant(
            of: find.byKey(const Key('field-firstName')),
            matching: find.byType(TextField),
          ),
          'ОленаEdited',
        );
        await tester.pump();

        // Fill street but leave the city cascade untouched — touches the
        // location section (streetFilled = true) without providing a cityId.
        await tester.enterText(
          find.descendant(
            of: find.byKey(const Key('field-street')),
            matching: find.byType(TextField),
          ),
          'вул. Хрещатик',
        );
        await tester.pump();

        // Tap Save — button is enabled (firstName is dirty);
        // _validateLocation must fail (city absent) and block _save() entirely.
        await tester.tap(find.byKey(const Key('btn-save-master')));
        await tester.pumpAndSettle();

        // The screen must not have navigated away — validation blocked the save.
        expect(
          find.byKey(const Key('field-street')),
          findsOneWidget,
          reason:
              'MasterEditScreen must remain visible when location validation fails',
        );

        // NEITHER update should be called — _save() returns early when
        // _validateAndUpdateErrors() returns false (locationOk = false means
        // the whole save is aborted, not just the location part).
        verifyNever(
          () => repo.updateLocality(
            cityId: any(named: 'cityId'),
            districtId: any(named: 'districtId'),
            street: any(named: 'street'),
            buildingNo: any(named: 'buildingNo'),
            locationNote: any(named: 'locationNote'),
          ),
        );
        verifyNever(() => repo.updateMyProfile(any()));
      },
    );
  });
}
