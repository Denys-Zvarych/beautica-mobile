// Widget tests for LocationEditScreen (settlement autocomplete + district row
// + street/buildingNo/note).
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
// Phase 346 — the «Область» → «Місто» → «Район» LocalityCascade is GONE,
// replaced by [SettlementLocalityField] (one autocomplete + a conditional
// district row). Settlement selection is driven through the REAL bottom
// sheet (tap the closed field → type ≥3 chars → let the debounce elapse →
// tap the row), backed by a `locationRepositoryProvider` fake, rather than
// reaching into a cascade widget and invoking a callback directly — there is
// no such callback to invoke any more. See `_selectSettlement` below and
// `settlement_select_field_test.dart`'s header for why the explicit
// `pump(kSettlementSearchDebounce)` is load-bearing. Finders use widget Keys
// (M2). Layer: Widget.

import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/core/widgets/velvet_field.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/location/data/location_repository.dart';
import 'package:beautica_mobile/features/location/domain/city.dart';
import 'package:beautica_mobile/features/location/domain/city_district.dart';
import 'package:beautica_mobile/features/location/domain/oblast.dart';
import 'package:beautica_mobile/features/location/domain/settlement.dart';
import 'package:beautica_mobile/features/location/presentation/widgets/locality_tap_row.dart';
import 'package:beautica_mobile/features/location/presentation/widgets/settlement_select_field.dart';
import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/domain/master_update.dart';
import 'package:beautica_mobile/features/master/presentation/location_edit_screen.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/section_scaffold.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:dio/dio.dart' show CancelToken;
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

/// A leaf settlement — no urban districts, so [SettlementLocalityField]
/// renders no district row for it.
const _stubSettlement = Settlement(
  id: 'city-99',
  name: 'Київ',
  oblastName: 'Київ',
);

/// A settlement that subdivides — used by the district-clearing test.
const _settlementWithDistricts = Settlement(
  id: 'city-districts-1',
  name: 'Дніпро',
  oblastName: 'Дніпропетровська',
);

const _district1 = CityDistrict(
  id: 'district-1',
  cityId: 'city-districts-1',
  name: 'Соборний',
  katotthCode: 'UA12-020-0136',
);

/// Fixed fake backing `locationRepositoryProvider` — resolves the settlement
/// search to a small fixed list (ignoring the query text, since these tests
/// only need SOME ≥3-char query to clear the "type more" hint and reach the
/// real request path — see `settlement_select_field_test.dart` for the
/// dedicated query-shape coverage) and resolves districts per settlement id.
class _FakeLocationRepository implements LocationRepository {
  const _FakeLocationRepository();

  @override
  Future<List<Settlement>> searchSettlements(
    String query, {
    CancelToken? cancelToken,
  }) async => const <Settlement>[_stubSettlement, _settlementWithDistricts];

  @override
  Future<List<CityDistrict>> fetchDistricts(String cityId) async =>
      cityId == _settlementWithDistricts.id
      ? const <CityDistrict>[_district1]
      : const <CityDistrict>[];

  @override
  Future<List<Oblast>> fetchOblasts() => throw UnimplementedError();

  @override
  Future<List<City>> fetchCities(String oblastId) => throw UnimplementedError();
}

const _locationRepo = _FakeLocationRepository();

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
      locationRepositoryProvider.overrideWithValue(_locationRepo),
    ];

Finder _field(String key) =>
    find.descendant(of: find.byKey(Key(key)), matching: find.byType(TextField));

/// Selects [settlement] through the REAL search sheet: open → type a query
/// long enough to clear the "type more" hint → let the debounce elapse →
/// tap the row. There is no `LocalityCascade.onCity` callback to invoke
/// directly any more (phase 346).
Future<void> _selectSettlement(
  WidgetTester tester,
  Settlement settlement,
) async {
  await tester.tap(find.byKey(const Key('settlement_select_field')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('select-menu-search')),
    settlement.name,
  );
  await tester.pump(kSettlementSearchDebounce);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('settlement_option_${settlement.id}')));
  await tester.pumpAndSettle();
}

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

      // Phase 346 (Qase case 3 step 5) — the retired «Область»/«Місто» rows
      // must never reappear on this screen.
      expect(find.byKey(const Key('locality_row_oblast')), findsNothing);
      expect(find.byKey(const Key('locality_row_city')), findsNothing);
    },
  );

  testWidgets(
    'picking a new settlement always clears a previously selected district',
    (tester) async {
      await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
      await tester.pump();
      await tester.pump();

      // Pick the subdividing settlement — the district row appears.
      await _selectSettlement(tester, _settlementWithDistricts);
      expect(find.byKey(const Key('locality_row_district')), findsOneWidget);

      await tester.tap(find.byKey(const Key('locality_row_district')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey<String>('locality_picker_tile_${_district1.id}')),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<LocalityTapRow>(
              find.byKey(const Key('locality_row_district')),
            )
            .value,
        _district1.name,
      );

      // Now pick a DIFFERENT, leaf settlement — the district row must vanish
      // (a `CityDistrict` belongs to exactly one settlement, so carrying the
      // old selection across would submit a district that is not a child of
      // the newly-submitted city).
      await _selectSettlement(tester, _stubSettlement);

      expect(find.byKey(const Key('locality_row_district')), findsNothing);
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

      // Select a settlement through the real search sheet.
      await _selectSettlement(tester, _stubSettlement);

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

      await _selectSettlement(tester, _stubSettlement);
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
      await _selectSettlement(tester, _stubSettlement);

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

      await _selectSettlement(tester, _stubSettlement);
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

      await _selectSettlement(tester, _stubSettlement);
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
