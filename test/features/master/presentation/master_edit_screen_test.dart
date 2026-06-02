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
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/location/domain/city.dart';
import 'package:beautica_mobile/features/location/domain/city_district.dart';
import 'package:beautica_mobile/features/location/domain/oblast.dart';
import 'package:beautica_mobile/features/location/presentation/widgets/locality_cascade.dart';
import 'package:beautica_mobile/features/location/state/location_providers.dart';
import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/domain/master_update.dart';
import 'package:beautica_mobile/features/master/presentation/master_edit_screen.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/pump_app.dart';

// ---------------------------------------------------------------------------
// _ProfileInvalidationWatcher
// ---------------------------------------------------------------------------

/// Watches [masterProfileProvider] and appends every received [AsyncValue] to
/// [states], enabling assertions that the provider was invalidated after save.
///
/// Wrap the widget under test with this widget before calling
/// [tester.pumpRoutedApp]; the first state received is [AsyncLoading] (initial
/// build), then [AsyncData] once resolved. Each [ref.invalidate] call causes a
/// fresh [AsyncLoading] → [AsyncData] cycle — detectable by list length growth.
class _ProfileInvalidationWatcher extends ConsumerWidget {
  const _ProfileInvalidationWatcher({
    required this.child,
    required this.states,
  });

  final Widget child;
  final List<AsyncValue<Object?>> states;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    states.add(ref.watch(masterProfileProvider));
    return child;
  }
}

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class _MockMasterRepository extends Mock implements MasterRepository {}

/// Ukrainian localizations resolved off-tree for SnackBar text assertions —
/// mirrors the `lookupAppLocalizations(const Locale('uk'))` pattern used
/// elsewhere in the suite (e.g. register_step_3_screen_test.dart).
final AppLocalizations _l10nUk = lookupAppLocalizations(const Locale('uk'));

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

/// Stub [City] used by the updateLocality success-path test.
const _stubCity = City(
  id: 'city-99',
  oblastId: 'oblast-01',
  name: 'Київ',
  katotthCode: 'UA80000000000093317',
  hasDistricts: false,
);

// ── Seeded-locality fixtures (regression for the "Save does nothing" bug) ───
//
// A master that already has a NON-NULL cityId/oblastId/districtId. Street and
// buildingNo are intentionally null/empty so the location section is "seeded
// but unmodified" — the exact pre-population + dirty-tracking path that broke
// for real users and was never exercised before (no prior fixture set any of
// the three locality UUIDs). _prePopulateLocality must resolve _selectedCity /
// _selectedOblast against the list providers and reconcile _orig*Id so that an
// unrelated edit (e.g. firstName) correctly enables the Save button.
const _seededOblastId = 'oblast-seed';
const _seededCityId = 'city-seed';

const _stubMasterWithLocality = Master(
  id: 'user-1',
  firstName: 'Олена',
  lastName: 'Ковальчук',
  bio: 'Майстер манікюру.',
  avgRating: 4.8,
  reviewCount: 10,
  type: MasterType.independentMaster,
  oblastId: _seededOblastId,
  cityId: _seededCityId,
  // No districtId, street, or buildingNo — a partial saved address. The city
  // resolves but no street is present, so the location section stays optional.
);

/// Reference-data [Oblast] matching [_stubMasterWithLocality.oblastId] so that
/// `_prePopulateLocality` resolves `_selectedOblast`.
const _seededOblast = Oblast(
  id: _seededOblastId,
  name: 'Київська область',
  katotthCode: 'UA32000000000000000',
);

/// Reference-data [City] matching [_stubMasterWithLocality.cityId]. Has no
/// districts so `_prePopulateLocality` never touches the district provider.
const _seededCity = City(
  id: _seededCityId,
  oblastId: _seededOblastId,
  name: 'Київ',
  katotthCode: 'UA80000000000093317',
  hasDistricts: false,
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
  List<Object> extraOverrides = const <Object>[],
}) {
  return <Object>[
    authProvider.overrideWith(() => _StubAuthNotifier(_stubUser)),
    masterProfileProvider.overrideWith(
      () => _StubMasterProfileNotifier(master),
    ),
    masterRepositoryProvider.overrideWithValue(repo),
    ...extraOverrides,
  ];
}

/// Overrides the oblast/city list providers so that [_prePopulateLocality]
/// resolves `_selectedOblast` and `_selectedCity` for a seeded-locality master.
/// The district provider is left at its default (no districts on [_seededCity]).
List<Object> _seededLocalityOverrides() => <Object>[
  oblastListProvider.overrideWith((ref) async => const <Oblast>[_seededOblast]),
  cityListProvider(
    _seededOblastId,
  ).overrideWith((ref) async => const <City>[_seededCity]),
];

/// Like [_seededLocalityOverrides] but the city-list lookup THROWS, so that the
/// `_prePopulateLocality` resolution fails and is swallowed. Used to prove that
/// a failed pre-population does not wedge the Save button.
List<Object> _failingLocalityOverrides() => <Object>[
  // The city lookup throws AFTER the oblast resolved, so _prePopulateLocality
  // partially resolves (oblast matched, city/district unresolved) and the catch
  // swallows the throw. The reconcile block then runs with matchedCity == null.
  oblastListProvider.overrideWith((ref) async => const <Oblast>[_seededOblast]),
  cityListProvider(
    _seededOblastId,
  ).overrideWith((ref) async => throw const NetworkFailure()),
];

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

  // ── 7b. Optional "необов’язково" marker scoping (Bugfix 1 regression) ─────
  //
  // Bugfix 1: the phone field no longer renders the muted "необов’язково"
  // optional marker (VelvetField.optional was removed from the phone field),
  // while the Instagram and location-note fields STILL show it. The marker is
  // a permanent design token of VelvetField (a Unicode-apostrophe string baked
  // into the widget, not an l10n key), so we assert against that exact literal
  // — scoped per-field via find.descendant so a future accidental re-add to the
  // phone field, or removal from Instagram / location-note, is caught.

  group('optional marker scoping (Bugfix 1)', () {
    // The exact token rendered by VelvetField when optional == true. Contains a
    // Unicode RIGHT SINGLE QUOTATION MARK (U+2019), matching velvet_field.dart.
    const String optionalMarker = 'необов’язково';

    testWidgets('phone field shows NO optional marker, while Instagram and '
        'location-note fields STILL show it', (tester) async {
      final router = _buildRouter();
      await tester.pumpRoutedApp(
        router,
        overrides: _buildOverrides(repo: repo),
      );
      await tester.pump();
      await tester.pump();

      // All three fields are present.
      expect(find.byKey(const Key('field-phone')), findsOneWidget);
      expect(find.byKey(const Key('field-instagram')), findsOneWidget);
      expect(find.byKey(const Key('field-locationNote')), findsOneWidget);

      // Phone: the optional marker must NOT appear inside the phone field
      // subtree (Bugfix 1 — the marker was removed from the phone field).
      expect(
        find.descendant(
          of: find.byKey(const Key('field-phone')),
          matching: find.text(optionalMarker),
        ),
        findsNothing,
        reason:
            'Bugfix 1: the phone field must not render the "необов’язково" '
            'optional marker',
      );

      // Instagram: the marker MUST still appear (regression guard — removal
      // must stay scoped to phone only).
      expect(
        find.descendant(
          of: find.byKey(const Key('field-instagram')),
          matching: find.text(optionalMarker),
        ),
        findsOneWidget,
        reason:
            'the Instagram field must keep its optional marker — Bugfix 1 '
            'scopes the removal to the phone field only',
      );

      // Location note: the marker MUST still appear.
      expect(
        find.descendant(
          of: find.byKey(const Key('field-locationNote')),
          matching: find.text(optionalMarker),
        ),
        findsOneWidget,
        reason:
            'the location-note field must keep its optional marker — '
            'Bugfix 1 scopes the removal to the phone field only',
      );
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

    testWidgets('validation_requires_street_when_street_filled_but_no_city', (
      tester,
    ) async {
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
    });
  });

  // ── 13. updateLocality success path ─────────────────────────────────────────
  //
  // MEDIUM finding: the save path that calls updateLocality was untested.
  //
  // Simulates a city selection via the LocalityCascade onCity callback
  // (the cascade is a ConsumerWidget — we obtain it via tester.widget and
  // invoke onCity directly, bypassing the UI picker bottom-sheet which requires
  // real HTTP calls to the locality providers).
  //
  // Steps:
  //   1. Start with a master whose locality fields are null.
  //   2. Invoke LocalityCascade.onCity with _stubCity to select a city.
  //   3. Enter street + buildingNo.
  //   4. Dirty firstName so the Save button is enabled.
  //   5. Tap Save.
  //   6. Verify updateLocality was called once with the expected arguments.

  group('updateLocality success path', () {
    testWidgets(
      'saves location — calls updateLocality with correct cityId, street, '
      'and buildingNo',
      (tester) async {
        when(() => repo.updateMyProfile(any())).thenAnswer((_) async {});
        when(
          () => repo.updateLocality(
            cityId: any(named: 'cityId'),
            districtId: any(named: 'districtId'),
            street: any(named: 'street'),
            buildingNo: any(named: 'buildingNo'),
            locationNote: any(named: 'locationNote'),
          ),
        ).thenAnswer((_) async {});

        final router = _buildRouter();
        await tester.pumpRoutedApp(
          router,
          overrides: _buildOverrides(repo: repo),
        );
        await tester.pump();
        await tester.pump();

        // Simulate city selection by invoking onCity on the LocalityCascade
        // widget directly — bypasses the bottom-sheet picker that needs HTTP.
        final cascade = tester.widget<LocalityCascade>(
          find.byKey(const Key('location-cascade')),
        );
        cascade.onCity(_stubCity);
        await tester.pump();

        // Enter street.
        await tester.enterText(
          find.descendant(
            of: find.byKey(const Key('field-street')),
            matching: find.byType(TextField),
          ),
          'вул. Шевченка',
        );
        await tester.pump();

        // Enter buildingNo.
        await tester.enterText(
          find.descendant(
            of: find.byKey(const Key('field-buildingNo')),
            matching: find.byType(TextField),
          ),
          '1',
        );
        await tester.pump();

        // Dirty firstName so the Save button becomes enabled.
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

        verify(
          () => repo.updateLocality(
            cityId: 'city-99',
            districtId: null,
            street: 'вул. Шевченка',
            buildingNo: '1',
            locationNote: null,
          ),
        ).called(1);
      },
    );
  });

  // ── 14. masterProfileProvider invalidation on save success ──────────────────
  //
  // MEDIUM finding: save-success tests did not assert that masterProfileProvider
  // is invalidated after a successful save.
  //
  // Strategy: pump the MasterEditScreen wrapped in a top-level
  // _ProfileInvalidationWatcher (outside the Router widget tree) so that the
  // watcher persists even after the inner GoRouter navigates to masterProfile.
  // The watcher catches the AsyncLoading emission that Riverpod fires when
  // ref.invalidate(masterProfileProvider) is called.

  group('masterProfileProvider invalidation on save success', () {
    testWidgets(
      'ref.invalidate(masterProfileProvider) is called after successful save',
      (tester) async {
        when(() => repo.updateMyProfile(any())).thenAnswer((_) async {});

        final states = <AsyncValue<Object?>>[];

        final router = GoRouter(
          initialLocation: RouteNames.masterEdit,
          routes: <RouteBase>[
            GoRoute(
              path: RouteNames.masterEdit,
              pageBuilder: (context, state) =>
                  const NoTransitionPage<void>(child: MasterEditScreen()),
            ),
            GoRoute(
              path: RouteNames.masterProfile,
              pageBuilder: (context, state) => const NoTransitionPage<void>(
                child: Scaffold(
                  body: Center(
                    child: SizedBox(key: Key('stub-master-profile')),
                  ),
                ),
              ),
            ),
          ],
        );

        // Pump with a _ProfileInvalidationWatcher at the very top of the tree
        // (wrapping MaterialApp.router) so that the watcher lives outside the
        // router page stack and persists after navigation.
        final overrides = _buildOverrides(repo: repo);
        await tester.pumpWidget(
          ProviderScope(
            overrides: overrides.cast(),
            child: _ProfileInvalidationWatcher(
              states: states,
              child: MaterialApp.router(
                routerConfig: router,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                locale: const Locale('uk'),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        // Capture the number of states received before the save action.
        // The watcher receives at least one state (AsyncLoading or AsyncData)
        // during the initial build.
        final statesBefore = states.length;
        expect(statesBefore, greaterThanOrEqualTo(1));

        // Dirty firstName to enable Save.
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

        // ref.invalidate(masterProfileProvider) transitions the provider back
        // to AsyncLoading → AsyncData. The watcher (outside the router page
        // stack) observes these transitions regardless of navigation.
        expect(
          states.length,
          greaterThan(statesBefore),
          reason:
              'masterProfileProvider must be invalidated after a successful '
              'save — the watcher must receive at least one additional '
              'AsyncValue emission after ref.invalidate() fires.',
        );
      },
    );
  });

  // ── 15. Seeded-locality dirty-tracking regression ───────────────────────────
  //
  // [HIGH] The exact gap that let the "Save button does nothing" bug ship green
  // TWICE: no prior test seeded a master with a non-null cityId/oblastId/
  // districtId, so the _prePopulateLocality + dirty-tracking reconciliation path
  // was never exercised. With a seeded locality, _origCityId/_origOblastId start
  // non-null, then get reconciled against the resolved _selected* objects in the
  // microtask. If reconciliation is wrong, _isDirty stays false (or true) for the
  // wrong reasons and the Save button never enables on a plain firstName edit.

  group('seeded-locality dirty tracking regression', () {
    // ── 15.1  city-only seed → firstName edit enables Save + Save fires ──────

    testWidgets(
      'with a seeded city locality, editing firstName enables Save and a '
      'successful tap fires updateMyProfile + shows the saved snackbar',
      (tester) async {
        when(() => repo.updateMyProfile(any())).thenAnswer((_) async {});

        final router = _buildRouter();
        await tester.pumpRoutedApp(
          router,
          overrides: _buildOverrides(
            repo: repo,
            master: _stubMasterWithLocality,
            extraOverrides: _seededLocalityOverrides(),
          ),
        );
        // Three pumps: router build, masterProfile Future.value microtask, and
        // the _prePopulateLocality microtask (oblast + city list resolution +
        // the setState that reconciles _orig*Id with the resolved _selected*).
        await tester.pump();
        await tester.pump();
        await tester.pumpAndSettle();

        // Before any edit the form is seeded-but-pristine → Save is disabled.
        expect(
          tester
              .widget<NeumorphicButton>(
                find.byKey(const Key('btn-save-master')),
              )
              .onPressed,
          isNull,
          reason:
              'A seeded-but-unmodified master must leave Save disabled — '
              'reconciliation must NOT falsely mark the form dirty.',
        );

        // Edit firstName only — the locality section is untouched.
        await tester.enterText(
          find.descendant(
            of: find.byKey(const Key('field-firstName')),
            matching: find.byType(TextField),
          ),
          'ОленаEdited',
        );
        await tester.pump();

        // THE REGRESSION: the Save button must now be ENABLED. Before the fix
        // the seeded locality skewed _isDirty and the button stayed disabled.
        expect(
          tester
              .widget<NeumorphicButton>(
                find.byKey(const Key('btn-save-master')),
              )
              .onPressed,
          isNotNull,
          reason:
              'Editing firstName on a seeded-locality master must enable Save. '
              'This is the core regression — the button previously stayed '
              'disabled and tapping it did absolutely nothing.',
        );

        await tester.tap(find.byKey(const Key('btn-save-master')));
        await tester.pumpAndSettle();

        // Save actually fired and produced visible feedback.
        verify(() => repo.updateMyProfile(any())).called(1);
        expect(find.byKey(const Key('snackbar-saved')), findsOneWidget);
      },
    );

    // ── 15.2  pre-population lookup throws → Save still enables + gives feedback ─

    testWidgets(
      'when the locality lookup throws during pre-population, editing firstName '
      'still enables Save and tapping it still produces feedback (no silent '
      'no-op)',
      (tester) async {
        when(() => repo.updateMyProfile(any())).thenAnswer((_) async {});

        final router = _buildRouter();
        await tester.pumpRoutedApp(
          router,
          overrides: _buildOverrides(
            repo: repo,
            master: _stubMasterWithLocality,
            extraOverrides: _failingLocalityOverrides(),
          ),
        );
        // The city lookup throws — _prePopulateLocality swallows it. Drain the
        // router build, the masterProfile microtask, and the pre-population
        // microtask before interacting.
        await tester.pump();
        await tester.pump();
        await tester.pumpAndSettle();

        // Dirty firstName (the locality section is also dirty by virtue of the
        // failed pre-population — see below — but editing firstName makes the
        // user intent explicit and mirrors the real-world repro).
        await tester.enterText(
          find.descendant(
            of: find.byKey(const Key('field-firstName')),
            matching: find.byType(TextField),
          ),
          'ОленаEdited',
        );
        await tester.pump();

        // The Save button MUST be interactive — never a dead no-op. (When the
        // city lookup throws, the section is also dirty because the seeded
        // _origCityId no longer matches the now-null _selectedCity; either way
        // the button is enabled and tappable.)
        expect(
          tester
              .widget<NeumorphicButton>(
                find.byKey(const Key('btn-save-master')),
              )
              .onPressed,
          isNotNull,
          reason:
              'A failed locality pre-population must never leave the Save '
              'button disabled — that was the original dead-button bug.',
        );

        await tester.tap(find.byKey(const Key('btn-save-master')));
        // Single pump frame: any resulting SnackBar mounts synchronously while
        // the edit screen is still present (a success path would navigate away
        // on pumpAndSettle and tear the ScaffoldMessenger down).
        await tester.pump();

        // CORE GUARANTEE (Fix 1 generic catch): tapping Save after a failed
        // pre-population MUST produce visible feedback — never the original
        // "absolutely nothing happens" no-op. Whether the city resolved or not,
        // SOME SnackBar (saved on success, or the validation summary when the
        // unresolved-but-seeded city forces an inline location error) must show.
        expect(
          find.byType(SnackBar),
          findsOneWidget,
          reason:
              'Tapping Save after a failed locality pre-population must surface '
              'a SnackBar — never a silent no-op. This is the regression guard '
              'for the "Save button does nothing" bug.',
        );

        // Drain any post-save navigation so the test ends on a settled tree.
        await tester.pumpAndSettle();
      },
    );

    // ── 15.3  generic non-Failure throw in save → errUnknown snackbar ────────

    testWidgets(
      'a non-Failure error thrown by updateMyProfile shows the errUnknown '
      'snackbar and re-enables the Save button (catch-all guards the no-op bug)',
      (tester) async {
        // Throw a raw StateError — NOT a Failure subtype — so the generic
        // catch (e, st) branch in _save() is the only thing that can react.
        when(() => repo.updateMyProfile(any())).thenThrow(StateError('boom'));

        final router = _buildRouter();
        await tester.pumpRoutedApp(
          router,
          overrides: _buildOverrides(
            repo: repo,
            master: _stubMasterWithLocality,
            extraOverrides: _seededLocalityOverrides(),
          ),
        );
        await tester.pump();
        await tester.pump();
        await tester.pumpAndSettle();

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

        // The generic catch must surface the errUnknown localized message.
        expect(
          find.text(_l10nUk.errUnknown),
          findsOneWidget,
          reason:
              'A non-Failure throw must be caught by the catch-all and surface '
              'the errUnknown snackbar — the regression guard for the original '
              '"absolutely nothing happens" bug.',
        );

        // _saving must be cleared → Save button is interactive again (still
        // dirty, so onPressed is non-null).
        expect(
          tester
              .widget<NeumorphicButton>(
                find.byKey(const Key('btn-save-master')),
              )
              .onPressed,
          isNotNull,
          reason: '_saving must be cleared after the catch-all fires.',
        );
        verify(() => repo.updateMyProfile(any())).called(1);
      },
    );
  });

  // ── 16. Per-field dirty matrix ───────────────────────────────────────────
  //
  // [HIGH] Regression protection for the "Save inert / silent no-op" bug
  // (commit 26cf884): a stale _isDirty flag failed to rebuild the pinned footer
  // when a SINGLE field changed. Prior coverage only exercised firstName. Here
  // every editable field is checked in isolation: pump a fully-seeded pristine
  // master (Save disabled, onPressed == null), edit ONLY that field, and assert
  // Save becomes enabled (onPressed != null).
  //
  // The footer button is a NeumorphicButton whose onPressed is `_isDirty ? _save
  // : null`, so onPressed nullability is the direct, locale-neutral proxy for
  // the dirty flag.

  group('per-field dirty matrix', () {
    // A master seeded with non-empty values in every editable field so that an
    // edit to any one of them is unambiguously a change from the pristine seed.
    final seededMaster = _stubMaster.copyWith(
      phoneNumber: '+380 50 123 45 67',
      instagram: '@seed_handle',
      street: 'вул. Стара',
      buildingNo: '7',
      locationNote: 'офіс 2',
    );

    /// Reads the current onPressed of the pinned Save button.
    VoidCallback? saveOnPressed(WidgetTester tester) => tester
        .widget<NeumorphicButton>(find.byKey(const Key('btn-save-master')))
        .onPressed;

    /// Pumps the edit screen seeded with [seededMaster] and asserts it starts
    /// pristine (Save disabled). Returns once the form is initialised.
    Future<void> pumpPristine(WidgetTester tester) async {
      final router = _buildRouter();
      await tester.pumpRoutedApp(
        router,
        overrides: _buildOverrides(repo: repo, master: seededMaster),
      );
      await tester.pump();
      await tester.pump();

      expect(
        saveOnPressed(tester),
        isNull,
        reason: 'A fully-seeded, unmodified master must leave Save disabled.',
      );
    }

    Finder fieldInput(String fieldKey) => find.descendant(
      of: find.byKey(Key(fieldKey)),
      matching: find.byType(TextField),
    );

    testWidgets('editing lastName alone enables Save', (tester) async {
      await pumpPristine(tester);
      await tester.enterText(fieldInput('field-lastName'), 'Новенька');
      await tester.pump();
      expect(saveOnPressed(tester), isNotNull);
    });

    testWidgets('editing bio alone enables Save', (tester) async {
      await pumpPristine(tester);
      await tester.enterText(fieldInput('field-bio'), 'Оновлене біо.');
      await tester.pump();
      expect(saveOnPressed(tester), isNotNull);
    });

    testWidgets('editing phone alone enables Save', (tester) async {
      await pumpPristine(tester);
      await tester.enterText(fieldInput('field-phone'), '+380509998877');
      await tester.pump();
      expect(saveOnPressed(tester), isNotNull);
    });

    testWidgets('editing instagram alone enables Save', (tester) async {
      await pumpPristine(tester);
      await tester.enterText(fieldInput('field-instagram'), '@brand_new');
      await tester.pump();
      expect(saveOnPressed(tester), isNotNull);
    });

    testWidgets('editing locationNote alone enables Save', (tester) async {
      await pumpPristine(tester);
      await tester.enterText(fieldInput('field-locationNote'), 'нова примітка');
      await tester.pump();
      expect(saveOnPressed(tester), isNotNull);
    });

    testWidgets('editing street alone enables Save', (tester) async {
      await pumpPristine(tester);
      await tester.enterText(fieldInput('field-street'), 'вул. Нова');
      await tester.pump();
      expect(saveOnPressed(tester), isNotNull);
    });

    testWidgets('editing buildingNo alone enables Save', (tester) async {
      await pumpPristine(tester);
      await tester.enterText(fieldInput('field-buildingNo'), '99');
      await tester.pump();
      expect(saveOnPressed(tester), isNotNull);
    });

    // ── oblast / district dirty via the locality cascade callbacks ──────────
    //
    // The cascade selection (oblast/city/district) is part of _isDirty. We seed
    // a master with a resolved city (so the cascade is pristine) and then change
    // the district through the LocalityCascade.onDistrict callback, proving the
    // cascade slice of _isDirty also flips Save on. (oblast/city changes follow
    // the same code path and are covered transitively by the success-path test
    // group #13, which selects a city from a null seed.)

    testWidgets('changing district via the cascade enables Save', (
      tester,
    ) async {
      final router = _buildRouter();
      await tester.pumpRoutedApp(
        router,
        overrides: _buildOverrides(
          repo: repo,
          master: _stubMasterWithLocality,
          extraOverrides: _seededLocalityOverrides(),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      // Seeded-but-unmodified → Save disabled.
      expect(
        tester
            .widget<NeumorphicButton>(find.byKey(const Key('btn-save-master')))
            .onPressed,
        isNull,
        reason: 'Seeded locality with no edits must leave Save disabled.',
      );

      // Select a district through the cascade callback — _selectedDistrict.id
      // now differs from the seeded _origDistrictId (null), flipping _isDirty.
      final cascade = tester.widget<LocalityCascade>(
        find.byKey(const Key('location-cascade')),
      );
      cascade.onDistrict(
        const CityDistrict(
          id: 'district-1',
          cityId: _seededCityId,
          name: 'Шевченківський',
          katotthCode: 'UA80000000000000001',
        ),
      );
      await tester.pump();

      expect(
        tester
            .widget<NeumorphicButton>(find.byKey(const Key('btn-save-master')))
            .onPressed,
        isNotNull,
        reason:
            'Selecting a district must mark the form dirty and enable Save.',
      );
    });
  });

  // ── 17. Per-field persist assertions (captured-argument matchers) ────────
  //
  // [HIGH] Prior save-path verifies all used `any()`, so a regression that sent
  // a stale/blank value to the backend would pass green. Here each profile field
  // is edited in isolation, Save is tapped, and the captured MasterUpdate is
  // asserted field-by-field: the edited field carries its NEW value and the
  // others retain the seed.
  //
  // MasterUpdate is a hand-written value object with NO == override, so equality
  // matching is impossible — we capture the argument and assert its fields.
  // _save() trims every value, so captured strings are trimmed. The phone field
  // is reformatted live by UaPhoneInputFormatter, so contactPhone is asserted
  // against the FORMATTED string, not the raw keystrokes.

  group('per-field persist assertions', () {
    // Seed every profile field so a single-field edit is provably isolated.
    final seededMaster = _stubMaster.copyWith(
      firstName: 'Олена',
      lastName: 'Ковальчук',
      bio: 'Майстер манікюру.',
      phoneNumber: '+380 50 111 22 33',
      instagram: '@seed_handle',
    );

    Finder fieldInput(String fieldKey) => find.descendant(
      of: find.byKey(Key(fieldKey)),
      matching: find.byType(TextField),
    );

    /// Pumps the edit screen seeded, edits [fieldKey] to [value], taps Save,
    /// and returns the single captured [MasterUpdate].
    Future<MasterUpdate> editAndCapture(
      WidgetTester tester, {
      required String fieldKey,
      required String value,
    }) async {
      when(() => repo.updateMyProfile(any())).thenAnswer((_) async {});

      final router = _buildRouter();
      await tester.pumpRoutedApp(
        router,
        overrides: _buildOverrides(repo: repo, master: seededMaster),
      );
      await tester.pump();
      await tester.pump();

      await tester.enterText(fieldInput(fieldKey), value);
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn-save-master')));
      await tester.pumpAndSettle();

      final captured = verify(
        () => repo.updateMyProfile(captureAny()),
      ).captured;
      expect(
        captured,
        hasLength(1),
        reason: 'updateMyProfile must be called exactly once.',
      );
      return captured.single as MasterUpdate;
    }

    testWidgets('firstName change is carried in MasterUpdate', (tester) async {
      final update = await editAndCapture(
        tester,
        fieldKey: 'field-firstName',
        value: 'Оксана',
      );
      expect(update.firstName, 'Оксана');
      expect(update.lastName, 'Ковальчук');
      expect(update.bio, 'Майстер манікюру.');
      expect(update.contactPhone, '+380 50 111 22 33');
      expect(update.instagram, '@seed_handle');
    });

    testWidgets('lastName change is carried in MasterUpdate', (tester) async {
      final update = await editAndCapture(
        tester,
        fieldKey: 'field-lastName',
        value: 'Петренко',
      );
      expect(update.lastName, 'Петренко');
      expect(update.firstName, 'Олена');
      expect(update.bio, 'Майстер манікюру.');
      expect(update.contactPhone, '+380 50 111 22 33');
      expect(update.instagram, '@seed_handle');
    });

    testWidgets('bio change is carried in MasterUpdate', (tester) async {
      final update = await editAndCapture(
        tester,
        fieldKey: 'field-bio',
        value: 'Стиліст-візажист.',
      );
      expect(update.bio, 'Стиліст-візажист.');
      expect(update.firstName, 'Олена');
      expect(update.lastName, 'Ковальчук');
      expect(update.contactPhone, '+380 50 111 22 33');
      expect(update.instagram, '@seed_handle');
    });

    testWidgets('phone change is carried in MasterUpdate as contactPhone', (
      tester,
    ) async {
      // UaPhoneInputFormatter reformats the raw digits to +380 XX XXX XX XX, so
      // contactPhone carries the FORMATTED string (trim() leaves it unchanged).
      final update = await editAndCapture(
        tester,
        fieldKey: 'field-phone',
        value: '+380679998877',
      );
      expect(update.contactPhone, '+380 67 999 88 77');
      expect(update.firstName, 'Олена');
      expect(update.lastName, 'Ковальчук');
      expect(update.bio, 'Майстер манікюру.');
      expect(update.instagram, '@seed_handle');
    });

    testWidgets('instagram change is carried in MasterUpdate', (tester) async {
      final update = await editAndCapture(
        tester,
        fieldKey: 'field-instagram',
        value: '@new_handle',
      );
      expect(update.instagram, '@new_handle');
      expect(update.firstName, 'Олена');
      expect(update.lastName, 'Ковальчук');
      expect(update.bio, 'Майстер манікюру.');
      expect(update.contactPhone, '+380 50 111 22 33');
    });
  });

  // ── 18. locationNote persist assertion ───────────────────────────────────
  //
  // [MEDIUM] The updateLocality success path (#13) only ever asserted
  // locationNote: null. Here a city is selected (so updateLocality fires) AND a
  // note is entered — the captured updateLocality call must carry the entered
  // locationNote verbatim (trimmed). Street + buildingNo are also asserted so
  // the whole locality payload is pinned.

  group('locationNote persist assertion', () {
    testWidgets(
      'entering a locationNote with a selected city sends it to updateLocality',
      (tester) async {
        when(() => repo.updateMyProfile(any())).thenAnswer((_) async {});
        when(
          () => repo.updateLocality(
            cityId: any(named: 'cityId'),
            districtId: any(named: 'districtId'),
            street: any(named: 'street'),
            buildingNo: any(named: 'buildingNo'),
            locationNote: any(named: 'locationNote'),
          ),
        ).thenAnswer((_) async {});

        final router = _buildRouter();
        await tester.pumpRoutedApp(
          router,
          overrides: _buildOverrides(repo: repo),
        );
        await tester.pump();
        await tester.pump();

        // Select a city via the cascade callback so updateLocality fires.
        final cascade = tester.widget<LocalityCascade>(
          find.byKey(const Key('location-cascade')),
        );
        cascade.onCity(_stubCity);
        await tester.pump();

        // Enter the required address fields plus the note under test.
        await tester.enterText(
          find.descendant(
            of: find.byKey(const Key('field-street')),
            matching: find.byType(TextField),
          ),
          'вул. Шевченка',
        );
        await tester.enterText(
          find.descendant(
            of: find.byKey(const Key('field-buildingNo')),
            matching: find.byType(TextField),
          ),
          '12',
        );
        await tester.enterText(
          find.descendant(
            of: find.byKey(const Key('field-locationNote')),
            matching: find.byType(TextField),
          ),
          'другий поверх',
        );
        await tester.pump();

        await tester.tap(find.byKey(const Key('btn-save-master')));
        await tester.pumpAndSettle();

        // Capture ONLY the locationNote (the field under test) and pin every
        // other named arg with a literal matcher. Capturing a single named arg
        // keeps `.captured` unambiguous — mixing multiple captureAny(named:)
        // matchers flattens them in evaluation order, not declaration order.
        final captured = verify(
          () => repo.updateLocality(
            cityId: 'city-99',
            districtId: null,
            street: 'вул. Шевченка',
            buildingNo: '12',
            locationNote: captureAny(named: 'locationNote'),
          ),
        ).captured;

        expect(captured, hasLength(1));
        expect(
          captured.single,
          'другий поверх',
          reason: 'locationNote must carry the entered value, not null',
        );
      },
    );
  });

  // ── 19. Empty-fieldErrors ValidationFailure → generic SnackBar ───────────
  //
  // [HIGH] Step 2.7 Rule 3 regression guard for the "silent dead Save" bug.
  //
  // A 400 ValidationFailure whose `fieldErrors` map is EMPTY used to highlight
  // no input (the inline mirroring in `_validateAndUpdateErrors()` renders
  // nothing) and showed NO SnackBar — tapping Save did absolutely nothing.
  //
  // The fix (master_edit_screen.dart, `on ValidationFailure` branch):
  //   if (f.fieldErrors.isEmpty) → show SnackBar Key('snackbar-validation-error')
  //   text = serverMessage (trimmed, if non-blank) else l10n.errValidation.
  //
  // These two tests pin BOTH branches of that fallback. If the guard is
  // reverted, no SnackBar mounts and both tests fail — proving they guard the
  // fix (see the mutation check in the QA report).

  group('empty-fieldErrors validation snackbar regression guard', () {
    // ── 19.1  empty fieldErrors + non-blank serverMessage → server text ──────

    testWidgets(
      'ValidationFailure with empty fieldErrors and a non-blank serverMessage '
      'shows the snackbar-validation-error SnackBar with that server message',
      (tester) async {
        const serverMsg = 'Сталася помилка валідації на сервері.';
        when(() => repo.updateMyProfile(any())).thenThrow(
          const ValidationFailure(
            fieldErrors: <String, String>{},
            serverMessage: serverMsg,
          ),
        );

        final router = _buildRouter();
        await tester.pumpRoutedApp(
          router,
          overrides: _buildOverrides(repo: repo),
        );
        await tester.pump();
        await tester.pump();

        // Dirty firstName so the Save button is enabled.
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

        // THE REGRESSION: an empty field map must NOT be a silent no-op — the
        // generic SnackBar with the dedicated Key must mount and carry the
        // server message verbatim.
        final snack = find.byKey(const Key('snackbar-validation-error'));
        expect(
          snack,
          findsOneWidget,
          reason:
              'An empty-fieldErrors ValidationFailure must surface the '
              'snackbar-validation-error SnackBar — never a silent dead Save.',
        );
        expect(
          find.descendant(of: snack, matching: find.text(serverMsg)),
          findsOneWidget,
          reason:
              'The SnackBar must show the non-blank serverMessage from the '
              'ValidationFailure.',
        );
      },
    );

    // ── 19.2  empty fieldErrors + blank serverMessage → l10n fallback ────────

    testWidgets(
      'ValidationFailure with empty fieldErrors and a blank serverMessage '
      'shows the snackbar-validation-error SnackBar with the errValidation '
      'fallback text',
      (tester) async {
        // Blank serverMessage (whitespace-only) → must fall back to errValidation.
        when(() => repo.updateMyProfile(any())).thenThrow(
          const ValidationFailure(
            fieldErrors: <String, String>{},
            serverMessage: '   ',
          ),
        );

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

        final snack = find.byKey(const Key('snackbar-validation-error'));
        expect(
          snack,
          findsOneWidget,
          reason:
              'An empty-fieldErrors ValidationFailure with a blank '
              'serverMessage must still surface the SnackBar — never a silent '
              'dead Save.',
        );
        expect(
          find.descendant(
            of: snack,
            matching: find.text(_l10nUk.errValidation),
          ),
          findsOneWidget,
          reason:
              'A blank serverMessage must fall back to the localized '
              'errValidation message inside the SnackBar.',
        );
      },
    );
  });
}
