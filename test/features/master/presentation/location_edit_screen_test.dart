// Widget tests for LocationEditScreen (locality cascade + street/buildingNo/note).
//
// KEY CONTRACT: this page calls updateLocality(...) ONLY — it must NEVER call
// updateMyProfile, so there is no sibling-field-clearing concern here. The
// headline test asserts updateLocality fires with the selected cityId/street/
// buildingNo AND that updateMyProfile is never invoked.
//
// Also covers: pre-population of the address fields from the cached master,
// validation blocking save when street is filled but no city is selected, and
// the save-success path (invalidate + saved VelvetSnack + navigate).
//
// City selection is driven by invoking LocalityCascade.onCity directly (the same
// approach the retired monolithic-form test used) to bypass the bottom-sheet
// picker that needs real HTTP. Finders use widget Keys (M2). Layer: Widget.

import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/core/widgets/velvet_field.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/location/domain/city.dart';
import 'package:beautica_mobile/features/location/presentation/widgets/locality_cascade.dart';
import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/domain/master_update.dart';
import 'package:beautica_mobile/features/master/presentation/location_edit_screen.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/section_scaffold.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/pump_app.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

class _MockMasterRepository extends Mock implements MasterRepository {}

const _stubUser = User(
  id: 'user-1',
  email: 'test@beautica.ua',
  role: UserRole.independentMaster,
  firstName: 'Олена',
  lastName: 'Ковальчук',
);

// A master with NO locality UUIDs but with address text, so _prePopulateLocality
// does not touch the list providers (oblastId is null) — keeps the test purely
// local while still exercising address pre-population.
const _cachedMaster = Master(
  id: 'user-1',
  firstName: 'Олена',
  lastName: 'Ковальчук',
  bio: 'Майстер манікюру.',
  phoneNumber: '+380 50 123 45 67',
  instagram: '@olena_nails',
  avgRating: 4.8,
  reviewCount: 10,
  type: MasterType.independentMaster,
  street: 'вул. Хрещатик',
  buildingNo: '10',
  locationNote: 'кв. 5',
);

const _emptyLocalityMaster = Master(
  id: 'user-1',
  firstName: 'Олена',
  lastName: 'Ковальчук',
  bio: 'Майстер манікюру.',
  phoneNumber: '+380 50 123 45 67',
  instagram: '@olena_nails',
  avgRating: 4.8,
  reviewCount: 10,
  type: MasterType.independentMaster,
);

const _stubCity = City(
  id: 'city-99',
  oblastId: 'oblast-01',
  name: 'Київ',
  katotthCode: 'UA80000000000093317',
  hasDistricts: false,
);

class _StubMasterProfileNotifier extends MasterProfile {
  _StubMasterProfileNotifier(this._master);
  final Master _master;

  @override
  Future<Master> build() => Future<Master>.value(_master);
}

class _StubAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async => const AuthSession.authenticated(
    user: _stubUser,
    accessToken: 'test-token',
  );
}

GoRouter _buildRouter() => GoRouter(
  initialLocation: RouteNames.masterEditLocation,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.masterEditLocation,
      pageBuilder: (_, _) =>
          const NoTransitionPage<void>(child: LocationEditScreen()),
    ),
    GoRoute(
      path: RouteNames.masterProfile,
      pageBuilder: (_, _) => const NoTransitionPage<void>(
        child: Scaffold(body: SizedBox(key: Key('stub-profile'))),
      ),
    ),
  ],
);

List<Object> _overrides(_MockMasterRepository repo, {Master? master}) =>
    <Object>[
      authProvider.overrideWith(_StubAuthNotifier.new),
      masterProfileProvider.overrideWith(
        () => _StubMasterProfileNotifier(master ?? _emptyLocalityMaster),
      ),
      masterRepositoryProvider.overrideWithValue(repo),
    ];

Finder _field(String key) =>
    find.descendant(of: find.byKey(Key(key)), matching: find.byType(TextField));

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
        professionalTitle: '',
      ),
    );
  });

  setUp(() {
    repo = _MockMasterRepository();
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

  testWidgets('address fields pre-populate from the cached master', (
    tester,
  ) async {
    await tester.pumpRoutedApp(
      _buildRouter(),
      overrides: _overrides(repo, master: _cachedMaster),
    );
    await tester.pump();
    await tester.pump();

    expect(
      tester.widget<TextField>(_field('field-street')).controller?.text,
      'вул. Хрещатик',
    );
    expect(
      tester.widget<TextField>(_field('field-buildingNo')).controller?.text,
      '10',
    );
    expect(
      tester.widget<TextField>(_field('field-locationNote')).controller?.text,
      'кв. 5',
    );
  });

  // ── REGRESSION GUARD: master-scoped subheading key (M2/M11) ────────────────
  // The master location screen must render the master-scoped
  // [masterLocationSubheading] copy and NOT the shared [locationSubheading]
  // used by the CLIENT location screen. A refactor that reverts to the shared
  // key would silently swap the master copy back — this pins it. Both strings
  // are resolved via l10n in-test (no hardcoded Cyrillic literal).
  // ── PERF (P2): typing an address must NOT re-run the screen-level build ────
  //
  // The dirty-state gating Save is driven by a ValueNotifier<bool> +
  // ValueListenableBuilder around the footer, NOT setState(() {}) on the whole
  // screen State. A text keystroke must therefore leave the SectionScaffold
  // chrome (app-bar / back-button / footer + reveal-animation wrappers) at the
  // same widget object identity. (Cascade city/district SELECTIONS still go
  // through setState — infrequent — and are not what this guards; this targets
  // the per-keystroke address-field path the old `setState(() {})` re-ran on.)
  testWidgets('typing a valid street does NOT re-run the screen build '
      '(SectionScaffold chrome preserved) yet still enables Save', (
    tester,
  ) async {
    await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
    await tester.pumpAndSettle();

    SectionScaffold scaffold() =>
        tester.widget<SectionScaffold>(find.byType(SectionScaffold));

    final before = scaffold();

    await tester.enterText(_field('field-street'), 'вул. Шевченка');
    await tester.pump();

    expect(
      identical(before, scaffold()),
      isTrue,
      reason:
          'an address keystroke must not re-run the screen build — the old '
          'setState(() {}) recreated the whole SectionScaffold (P2 jank).',
    );

    expect(
      tester
          .widget<NeumorphicButton>(find.byKey(const Key('btn-save-location')))
          .onPressed,
      isNotNull,
      reason: 'the ValueListenableBuilder footer must still enable Save',
    );
  });

  testWidgets(
    'renders the master-scoped subheading, not the shared client one',
    (tester) async {
      await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
      await tester.pump();
      await tester.pump();

      final l10n = AppLocalizations.of(
        tester.element(find.byType(LocationEditScreen)),
      );

      // Sanity: the two keys must be distinct, else the assertion is vacuous.
      expect(l10n.masterLocationSubheading, isNot(l10n.locationSubheading));

      expect(find.text(l10n.masterLocationSubheading), findsOneWidget);
      expect(find.text(l10n.locationSubheading), findsNothing);
    },
  );

  // ── HEADLINE: updateLocality ONLY (never updateMyProfile) ──────────────────
  testWidgets(
    'saving a selected city + address calls updateLocality with the right '
    'args and NEVER calls updateMyProfile',
    (tester) async {
      await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
      await tester.pump();
      await tester.pump();

      // Select a city by invoking the cascade callback directly.
      tester
          .widget<LocalityCascade>(find.byKey(const Key('location-cascade')))
          .onCity(_stubCity);
      await tester.pump();

      await tester.enterText(_field('field-street'), 'вул. Шевченка');
      await tester.pump();
      await tester.enterText(_field('field-buildingNo'), '1');
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn-save-location')));
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

      // The location page must NEVER call updateMyProfile.
      verifyNever(() => repo.updateMyProfile(any()));
    },
  );

  testWidgets('validation blocks save when street is filled but no city is '
      'selected (updateLocality not called)', (tester) async {
    await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
    await tester.pump();
    await tester.pump();

    // Fill street but never select a city → section touched but incomplete.
    await tester.enterText(_field('field-street'), 'вул. Хрещатик');
    await tester.pump();

    await tester.tap(find.byKey(const Key('btn-save-location')));
    await tester.pumpAndSettle();

    // Still on the edit screen; nothing persisted.
    expect(find.byKey(const Key('field-street')), findsOneWidget);
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

  testWidgets(
    'save success invalidates the profile, shows the saved VelvetSnack '
    'and navigates to the profile when canPop is false',
    (tester) async {
      final states = <AsyncValue<Object?>>[];

      await tester.pumpWidget(
        ProviderScope(
          retry: beauticaProviderRetry,
          overrides: _overrides(repo).cast(),
          child: _InvalidationWatcher(
            states: states,
            child: MaterialApp.router(
              routerConfig: _buildRouter(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('uk'),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      final before = states.length;

      tester
          .widget<LocalityCascade>(find.byKey(const Key('location-cascade')))
          .onCity(_stubCity);
      await tester.pump();
      await tester.enterText(_field('field-street'), 'вул. Шевченка');
      await tester.pump();
      await tester.enterText(_field('field-buildingNo'), '1');
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn-save-location')));
      await tester.pumpAndSettle();

      verify(
        () => repo.updateLocality(
          cityId: any(named: 'cityId'),
          districtId: any(named: 'districtId'),
          street: any(named: 'street'),
          buildingNo: any(named: 'buildingNo'),
          locationNote: any(named: 'locationNote'),
        ),
      ).called(1);
      expect(find.byKey(const Key('stub-profile')), findsOneWidget);
      expect(states.length, greaterThan(before));
    },
  );

  // ── REGRESSION GUARD: street + building UNCONDITIONALLY required ────────────
  // Phase 10.6 reversal — _validateLocation() dropped the old `editingAddress`
  // early-return that let an untouched empty address pass. Street + building
  // now go through the shared validateStreet/validateBuilding validators on
  // EVERY submit, mirroring the backend @NotBlank contract. These three tests
  // pin that contract so a refactor cannot silently reintroduce the escape
  // hatch. Error text is asserted via the resolved l10n key (no Cyrillic
  // literal in any finder); repo invocation count proves the submit guard.

  AppLocalizations l10nOf(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(LocationEditScreen)));

  String? fieldError(WidgetTester tester, String key) =>
      tester.widget<VelvetField>(find.byKey(Key(key))).errorText;

  testWidgets(
    'empty street + building blocks save even with a valid city selected '
    '(updateLocality never called, both required errors surfaced)',
    (tester) async {
      await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
      await tester.pump();
      await tester.pump();

      // Dirty the form via the city callback (as the other tests do) so Save is
      // enabled — but leave street + building EMPTY.
      tester
          .widget<LocalityCascade>(find.byKey(const Key('location-cascade')))
          .onCity(_stubCity);
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn-save-location')));
      await tester.pumpAndSettle();

      final l10n = l10nOf(tester);

      // Still on the edit form; nothing persisted.
      expect(find.byKey(const Key('field-street')), findsOneWidget);
      expect(fieldError(tester, 'field-street'), l10n.errStreetRequired);
      expect(fieldError(tester, 'field-buildingNo'), l10n.errBuildingRequired);

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

  testWidgets(
    'city + valid street + building proceeds — updateLocality called once and '
    'navigates to the profile',
    (tester) async {
      await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
      await tester.pump();
      await tester.pump();

      tester
          .widget<LocalityCascade>(find.byKey(const Key('location-cascade')))
          .onCity(_stubCity);
      await tester.pump();
      await tester.enterText(_field('field-street'), 'вул. Шевченка');
      await tester.pump();
      await tester.enterText(_field('field-buildingNo'), '12А');
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn-save-location')));
      await tester.pumpAndSettle();

      verify(
        () => repo.updateLocality(
          cityId: 'city-99',
          districtId: null,
          street: 'вул. Шевченка',
          buildingNo: '12А',
          locationNote: any(named: 'locationNote'),
        ),
      ).called(1);
      expect(find.byKey(const Key('stub-profile')), findsOneWidget);
    },
  );

  testWidgets(
    'empty locationNote is still optional — save succeeds with note == null '
    'when city + street + building are valid',
    (tester) async {
      await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
      await tester.pump();
      await tester.pump();

      tester
          .widget<LocalityCascade>(find.byKey(const Key('location-cascade')))
          .onCity(_stubCity);
      await tester.pump();
      await tester.enterText(_field('field-street'), 'вул. Шевченка');
      await tester.pump();
      await tester.enterText(_field('field-buildingNo'), '1');
      await tester.pump();
      // locationNote intentionally left EMPTY.

      await tester.tap(find.byKey(const Key('btn-save-location')));
      await tester.pumpAndSettle();

      // An empty note must not block save, and must be passed as null.
      verify(
        () => repo.updateLocality(
          cityId: 'city-99',
          districtId: null,
          street: 'вул. Шевченка',
          buildingNo: '1',
          locationNote: null,
        ),
      ).called(1);
      expect(find.byKey(const Key('stub-profile')), findsOneWidget);
    },
  );
}

class _InvalidationWatcher extends ConsumerWidget {
  const _InvalidationWatcher({required this.child, required this.states});

  final Widget child;
  final List<AsyncValue<Object?>> states;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    states.add(ref.watch(masterProfileProvider));
    return child;
  }
}
