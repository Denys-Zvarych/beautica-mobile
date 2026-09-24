// Widget tests for ClientLocationEditScreen (settlement + district only).
//
// For a CLIENT only the locality (settlement + district) is meaningful, so
// the free-text address fields (street / buildingNo / locationNote) are NOT
// shown, collected, validated, or sent. Save goes through
// updateMyProfile(touchesLocation: true) on PATCH /users/me. Coverage:
//   • the three address fields are NO LONGER rendered.
//   • with no settlement chosen the Save CTA stays disabled (the settlement
//     field picks atomically and this screen wires no clear affordance, so a
//     "dirty but still unset" state cannot be reached through the UI).
//   • selecting a settlement (without districts) persists with that cityId.
//   • selecting a settlement WITH districts but no district chosen blocks
//     save.
//   • D7 prefill — a profile carrying cityId + cityName shows that name on
//     the closed field with NO settlement search request issued.
//
// Phase 346 — the «Область» → «Місто» cascade is GONE, replaced by the shared
// [SettlementLocalityField] (one «Населений пункт» autocomplete + a
// conditional «Район» row). The primary settlement pick is driven through the
// REAL bottom sheet (open → type → debounce → tap a row) to prove the
// screen's wiring to [SettlementSelectField.onSelected] end-to-end, per the
// recorded trap: `pumpAndSettle` alone fires no debounce `Timer`, so the
// explicit `pump(kSettlementSearchDebounce)` below is load-bearing — skipping
// it would measure the pre-tap state and pass vacuously. Secondary tests
// (validation/error/regression paths, where the sheet mechanics are not what
// is under test) invoke `SettlementLocalityField.onSettlement` directly on the
// widget instance — the same shortcut the pre-346 suite used against
// `LocalityCascade.onCity`, and equivalent to a sheet pick because both paths
// converge on the exact same screen callback.
//
// City selection needs `districtListProvider` (`districtsOf`) to resolve, so
// every test that touches the screen overrides `locationRepositoryProvider`
// with a fake — unlike the pre-346 suite, which never needed a location repo
// at all because `City.hasDistricts` travelled on the picked object itself.
// Finders use widget Keys (M2). Layer: Widget.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/discovery/presentation/state/search_filters_controller.dart';
import 'package:beautica_mobile/features/home/application/client_edit_profile_notifier.dart';
import 'package:beautica_mobile/features/home/data/client_profile_repository.dart';
import 'package:beautica_mobile/features/home/domain/client_profile_update.dart';
import 'package:beautica_mobile/features/home/presentation/client_location_edit_screen.dart';
import 'package:beautica_mobile/features/location/data/location_repository.dart';
import 'package:beautica_mobile/features/location/domain/city.dart';
import 'package:beautica_mobile/features/location/domain/city_district.dart';
import 'package:beautica_mobile/features/location/domain/oblast.dart';
import 'package:beautica_mobile/features/location/domain/settlement.dart';
import 'package:beautica_mobile/features/location/presentation/widgets/settlement_locality_field.dart';
import 'package:beautica_mobile/features/location/presentation/widgets/settlement_select_field.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/pump_app.dart';
import '../../../helpers/velvet_snack_matchers.dart';

class _MockClientProfileRepository extends Mock
    implements ClientProfileRepository {}

// A CLIENT with NO locality UUIDs, so _prePopulateDistrict never fires
// (cityId is null) and the settlement field renders no district row — keeps
// the test purely local (no district fetch either).
const _stubUser = User(
  id: 'user-1',
  email: 'client@beautica.ua',
  role: UserRole.client,
  firstName: 'Олена',
  lastName: 'Ковальчук',
  phoneNumber: '+380 50 123 45 67',
);

// ---------------------------------------------------------------------------
// Settlement fixtures — 'city-99' is a leaf (no districts, like the old
// cascade's Kyiv fixture); 'city-77' subdivides (like the old Lviv fixture).
// ---------------------------------------------------------------------------

const _settlementKyiv = Settlement(
  id: 'city-99',
  name: 'Київ',
  oblastName: 'Київська',
);

const _settlementLviv = Settlement(
  id: 'city-77',
  name: 'Львів',
  oblastName: 'Львівська',
);

const _districtLviv = CityDistrict(
  id: 'd1',
  cityId: 'city-77',
  name: 'Галицький',
  katotthCode: 'UA4610136',
);

/// Fake [LocationRepository] backing both the settlement autocomplete
/// ([searchSettlements]) and the district row ([fetchDistricts], via
/// `districtsOf`/`districtListProvider`). [fetchOblasts]/[fetchCities] are
/// unimplemented — this screen never reaches the retired cascade endpoints.
class _FakeLocationRepository implements LocationRepository {
  _FakeLocationRepository({
    this.settlements = const <Settlement>[_settlementKyiv, _settlementLviv],
    Map<String, List<CityDistrict>>? districtsByCity,
  }) : districtsByCity =
           districtsByCity ??
           const <String, List<CityDistrict>>{
             'city-77': <CityDistrict>[_districtLviv],
           };

  final List<Settlement> settlements;
  final Map<String, List<CityDistrict>> districtsByCity;

  /// Every query [searchSettlements] was called with — the D7 assertion
  /// proves this stays EMPTY when a prefilled label needs no lookup.
  final List<String> searchQueries = <String>[];

  @override
  Future<List<Settlement>> searchSettlements(
    String query, {
    CancelToken? cancelToken,
  }) async {
    searchQueries.add(query);
    if (query.isEmpty) return settlements;
    final String needle = query.toLowerCase();
    return settlements
        .where((Settlement s) => s.name.toLowerCase().contains(needle))
        .toList();
  }

  @override
  Future<List<CityDistrict>> fetchDistricts(String cityId) async =>
      districtsByCity[cityId] ?? const <CityDistrict>[];

  @override
  Future<List<Oblast>> fetchOblasts() => throw UnimplementedError(
    'ClientLocationEditScreen no longer walks the oblast cascade (phase 346)',
  );

  @override
  Future<List<City>> fetchCities(String oblastId) => throw UnimplementedError(
    'ClientLocationEditScreen no longer walks the city cascade (phase 346)',
  );
}

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

// ---------------------------------------------------------------------------
// Regression fixtures — Search-tab re-sync on save (bug: after a client saves
// a NEW locality here, `_save()` used to `ref.invalidate(...)` the Search
// tab's keepAlive filter controllers directly. Because the Search tab lives
// inside `ClientShell`'s `StatefulShellRoute.indexedStack`, its State is never
// disposed on a tab switch, so `prefillFromProfileIfNeeded()` — the ONLY call
// site that can re-seed those controllers — never re-fires from
// `initState()`. The invalidate blanked both controllers to their empty
// default with nothing left to re-seed them: the Search tab came back
// EMPTY, not merely stale. The fix replaces the invalidate with an explicit
// `prefillFromProfileIfNeeded()` call so the same locality save that updates
// this screen also re-seeds Search inline.
//
// Both settlements are leaves (no districts), so the district-selection path
// stays out of the way of this regression.
// ---------------------------------------------------------------------------

const _settlementStaleKyiv = Settlement(
  id: 'city-stale-kyiv',
  name: 'Київ',
  oblastName: 'Київська',
);

const _settlementNewOdesa = Settlement(
  id: 'city-new-odesa',
  name: 'Одеса',
  oblastName: 'Одеська',
);

// The CLIENT's saved profile locality BEFORE the save under test — what
// [SearchFiltersController.prefillFromProfileIfNeeded] seeds the Search tab
// with on the FIRST (pre-save) call, mirroring the Search tab having already
// been opened once earlier in the session.
const _userAtStaleCity = User(
  id: 'user-1',
  email: 'client@beautica.ua',
  role: UserRole.client,
  firstName: 'Олена',
  lastName: 'Ковальчук',
  phoneNumber: '+380 50 123 45 67',
  cityId: 'city-stale-kyiv',
  cityName: 'Київ',
);

// Module-level "server state" the fake repository mutates on a successful
// PATCH — mirrors how a real /users/me re-fetch reflects the just-saved
// locality. Reset at the top of the regression tests below.
User _mutableProfileAfterPatch = _userAtStaleCity;

class _MutableStubClientEditProfile extends ClientEditProfile {
  @override
  Future<User> build() async => _mutableProfileAfterPatch;
}

List<Object> _overridesWithSearchSync(
  _MockClientProfileRepository repo,
  LocationRepository locationRepo,
) => <Object>[
  authProvider.overrideWith(_StubAuthNotifier.new),
  clientEditProfileProvider.overrideWith(_MutableStubClientEditProfile.new),
  clientProfileRepositoryProvider.overrideWithValue(repo),
  locationRepositoryProvider.overrideWithValue(locationRepo),
];

GoRouter _buildRouter() => GoRouter(
  initialLocation: RouteNames.clientEditLocation,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.clientEditLocation,
      pageBuilder: (_, _) =>
          const NoTransitionPage<void>(child: ClientLocationEditScreen()),
    ),
    GoRoute(
      path: RouteNames.clientHome,
      pageBuilder: (_, _) => const NoTransitionPage<void>(
        child: Scaffold(body: SizedBox(key: Key('stub-home'))),
      ),
    ),
  ],
);

List<Object> _overrides(
  _MockClientProfileRepository repo, {
  LocationRepository? locationRepo,
}) => <Object>[
  authProvider.overrideWith(_StubAuthNotifier.new),
  clientEditProfileProvider.overrideWith(_StubClientEditProfile.new),
  clientProfileRepositoryProvider.overrideWithValue(repo),
  locationRepositoryProvider.overrideWithValue(
    locationRepo ?? _FakeLocationRepository(),
  ),
];

/// Opens the settlement sheet, types [query], lets the debounce elapse, and
/// taps the row for [settlementId] — the REAL end-to-end pick path.
///
/// The explicit `pump(kSettlementSearchDebounce)` is load-bearing:
/// `pumpAndSettle` alone fires no `Timer`, so a test that skips it measures
/// the pre-keystroke (blank-query major-list) state.
Future<void> _pickSettlementViaSheet(
  WidgetTester tester, {
  required String query,
  required String settlementId,
}) async {
  await tester.tap(find.byKey(const Key('settlement_select_field')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('select-menu-search')), query);
  await tester.pump(kSettlementSearchDebounce);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('settlement_option_$settlementId')));
  await tester.pumpAndSettle();
}

void main() {
  late _MockClientProfileRepository repo;

  setUpAll(() {
    registerFallbackValue(const ClientProfileUpdate());
  });

  setUp(() {
    repo = _MockClientProfileRepository();
    when(() => repo.updateMyProfile(any())).thenAnswer((_) async {});
  });

  testWidgets(
    'the free-text address fields (street / buildingNo / locationNote) are NOT '
    'rendered for a CLIENT',
    (tester) async {
      await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
      await tester.pump();
      await tester.pump();

      // The settlement locality field still renders…
      expect(find.byKey(const Key('location-cascade')), findsOneWidget);
      // …but the three address fields are gone.
      expect(find.byKey(const Key('field-street')), findsNothing);
      expect(find.byKey(const Key('field-buildingNo')), findsNothing);
      expect(find.byKey(const Key('field-locationNote')), findsNothing);
      // Structural guard: with the address fields removed, the loaded Location
      // screen owns NO free-text input at all — the settlement field opens a
      // sheet on tap, it is not itself a TextField. A surviving TextField here
      // would mean an address field slipped back in.
      expect(
        find.byType(TextField),
        findsNothing,
        reason: 'the CLIENT Location screen must render no free-text input',
      );
    },
  );

  testWidgets(
    'renders the CLIENT location subheading copy above the locality field',
    (tester) async {
      await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
      await tester.pump();
      await tester.pump();

      // Read the expected copy through the l10n getter (NOT a hardcoded literal)
      // so the assertion survives copy revisions to [locationSubheading] — it
      // guards that the CLIENT screen wires the key, not a specific wording.
      final BuildContext ctx = tester.element(
        find.byKey(const Key('location-cascade')),
      );
      final String expected = AppLocalizations.of(ctx).locationSubheading;
      expect(find.text(expected), findsOneWidget);
    },
  );

  testWidgets(
    'with no settlement chosen, the Save CTA is disabled — a dirty-but-unset '
    'state is UI-unreachable now that a settlement pick is atomic and this '
    'screen wires no clear affordance (the old "oblast only" intermediate '
    'dirty state is gone with the oblast step itself)',
    (tester) async {
      await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
      await tester.pump();
      await tester.pump();

      expect(
        tester
            .widget<NeumorphicButton>(
              find.byKey(const Key('btn-save-location')),
            )
            .onPressed,
        isNull,
        reason: 'Save must be disabled while the form is pristine',
      );

      // Functional proof, not just the field read above: tapping the disabled
      // CTA does nothing.
      await tester.tap(find.byKey(const Key('btn-save-location')));
      await tester.pumpAndSettle();

      verifyNever(() => repo.updateMyProfile(any()));
      expect(find.byKey(const Key('location-cascade')), findsOneWidget);
      expect(find.byKey(const Key('stub-home')), findsNothing);
    },
  );

  testWidgets(
    'picking a settlement (no districts) through the REAL sheet persists that '
    'cityId and sends no address keys',
    (tester) async {
      ClientProfileUpdate? captured;
      when(() => repo.updateMyProfile(any())).thenAnswer((invocation) async {
        captured = invocation.positionalArguments.first as ClientProfileUpdate;
      });

      await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
      await tester.pump();
      await tester.pump();

      await _pickSettlementViaSheet(
        tester,
        query: 'Київ',
        settlementId: 'city-99',
      );

      await tester.tap(find.byKey(const Key('btn-save-location')));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.touchesLocation, isTrue);
      expect(captured!.cityId, 'city-99');
      expect(captured!.districtId, isNull);
      expect(find.byKey(const Key('stub-home')), findsOneWidget);
    },
  );

  testWidgets(
    'picking a settlement WITH districts through the REAL sheet but no '
    'district chosen blocks save',
    (tester) async {
      await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
      await tester.pump();
      await tester.pump();

      await _pickSettlementViaSheet(
        tester,
        query: 'Львів',
        settlementId: 'city-77',
      );

      // The district row must now be showing (city-77 subdivides).
      expect(find.byKey(const Key('locality_row_district')), findsOneWidget);

      await tester.tap(find.byKey(const Key('btn-save-location')));
      await tester.pumpAndSettle();

      // Still on the edit screen; nothing persisted (district required).
      expect(find.byKey(const Key('location-cascade')), findsOneWidget);
      expect(find.byKey(const Key('stub-home')), findsNothing);
      verifyNever(() => repo.updateMyProfile(any()));

      final BuildContext ctx = tester.element(
        find.byKey(const Key('location-cascade')),
      );
      expect(find.text(AppLocalizations.of(ctx).errRequired), findsOneWidget);
    },
  );

  testWidgets(
    'D7 — a profile carrying cityId + cityName shows that settlement name on '
    'the closed field with NO settlement search request issued',
    (tester) async {
      final locationRepo = _FakeLocationRepository();

      final router = GoRouter(
        initialLocation: RouteNames.clientEditLocation,
        routes: <RouteBase>[
          GoRoute(
            path: RouteNames.clientEditLocation,
            pageBuilder: (_, _) =>
                const NoTransitionPage<void>(child: ClientLocationEditScreen()),
          ),
        ],
      );

      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[
          authProvider.overrideWith(
            () => _StubAuthNotifierFor(_userAtStaleCity),
          ),
          clientEditProfileProvider.overrideWith(
            () => _StubClientEditProfileFor(_userAtStaleCity),
          ),
          clientProfileRepositoryProvider.overrideWithValue(repo),
          locationRepositoryProvider.overrideWithValue(locationRepo),
        ],
      );
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      // The denormalised name shows WITHOUT opening the sheet.
      // i18n-finder-ok: a settlement NAME is government reference data served
      // verbatim as `nameUk`; it is not UI copy and does not change with the
      // app locale.
      expect(find.text('Київ'), findsOneWidget);
      expect(
        locationRepo.searchQueries,
        isEmpty,
        reason:
            'the prefilled label is seeded straight from User.cityName; no '
            '/settlements request should ever be issued for it',
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

      // Dirty the form by picking a (leaf) settlement directly on the field —
      // equivalent to a sheet pick since both converge on the same
      // `onSettlement` callback; the sheet mechanics themselves are proven by
      // the dedicated picking tests above.
      tester
          .widget<SettlementLocalityField>(
            find.byKey(const Key('location-cascade')),
          )
          .onSettlement('city-99', 'Тестове, Тестівська');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn-save-location')));
      await pumpVelvetSnackIn(tester); // run the save future, mount + enter

      // The screen stays put — no navigation to the stub home occurred.
      expect(find.byKey(const Key('stub-home')), findsNothing);
      expect(find.byKey(const Key('location-cascade')), findsOneWidget);

      // The localized ServerFailure message renders in a root-overlay
      // VelvetSnack — NOT a SnackBar/ScaffoldMessenger descendant (see
      // test/helpers/velvet_snack_matchers.dart header).
      final BuildContext ctx = tester.element(
        find.byKey(const Key('location-cascade')),
      );
      final String expected = AppLocalizations.of(ctx).errServer;
      expectVelvetSnack(expected, variant: VelvetSnackVariant.error);

      await pumpPastVelvetSnack(tester); // drain the dwell Timer
    },
  );

  testWidgets(
    'saving a NEW locality re-seeds SearchFiltersController with the NEW city '
    '— NOT blank, NOT the stale one (the ref.invalidate(...)-blanks-Search '
    'regression)',
    (tester) async {
      _mutableProfileAfterPatch = _userAtStaleCity;

      final searchRepo = _MockClientProfileRepository();
      ClientProfileUpdate? captured;
      when(() => searchRepo.updateMyProfile(any())).thenAnswer((
        invocation,
      ) async {
        captured = invocation.positionalArguments.first as ClientProfileUpdate;
        // Mirrors the backend persisting the PATCH: the very next /users/me
        // read (triggered by this screen's post-save re-fetch) reflects the
        // NEW locality.
        _mutableProfileAfterPatch = _userAtNewCity;
      });

      final locationRepo = _FakeLocationRepository(
        settlements: const <Settlement>[
          _settlementStaleKyiv,
          _settlementNewOdesa,
        ],
        districtsByCity: const <String, List<CityDistrict>>{},
      );

      await tester.pumpRoutedApp(
        _buildRouter(),
        overrides: _overridesWithSearchSync(searchRepo, locationRepo),
      );
      await tester.pump();
      await tester.pump();

      final container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('location-cascade'))),
      );

      // ARRANGE: the Search tab was already opened once earlier this session
      // and seeded with the STALE locality — exactly the precondition this
      // regression depends on (a prior seed that must now be UPDATED, not
      // wiped).
      await container
          .read(searchFiltersControllerProvider.notifier)
          .prefillFromProfileIfNeeded();
      expect(
        container.read(searchFiltersControllerProvider).cityId,
        'city-stale-kyiv',
        reason:
            'precondition: the Search filter starts seeded with the OLD '
            'locality, as if the Search tab had been opened earlier this '
            'session',
      );

      // ACT: pick the NEW city on the Location screen and save.
      tester
          .widget<SettlementLocalityField>(
            find.byKey(const Key('location-cascade')),
          )
          .onSettlement('city-new-odesa', 'Одеса, Одеська');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn-save-location')));
      await tester.pumpAndSettle();

      // The save itself persisted the new city and navigated home.
      expect(captured, isNotNull);
      expect(captured!.cityId, 'city-new-odesa');
      expect(find.byKey(const Key('stub-home')), findsOneWidget);

      // The Пошук tab's locality LABEL must move with the id.
      //
      // This assertion exists because it once did not. `_settlementLabel` was
      // seeded from `user.cityName` in `_maybeInit` and never reassigned,
      // because `SettlementLocalityField.onSettlement` dropped the label the
      // field had already composed. `_save()` then forwarded that stale name
      // to `applyProfileLocationSave(cityName: ...)`, so after saving Одеса
      // the Search chip still read «Київ» while filtering by Odesa's id — a
      // filter labelled with a different city than the one it applies. The
      // handler now carries the label alongside the id; a regression that
      // drops it again fails HERE, not in a screenshot.
      expect(
        container.read(searchFilterLabelsControllerProvider).cityName,
        'Одеса, Одеська',
      );

      // THE REGRESSION ASSERTION — pre-fix, `_save()` called
      // `ref.invalidate(searchFiltersControllerProvider)` /
      // `ref.invalidate(searchFilterLabelsControllerProvider)`, which reset
      // both keepAlive controllers to their empty `build()` default (cityId
      // null) with nothing left to re-seed them — since Search's State is
      // never disposed inside `ClientShell`'s `StatefulShellRoute.indexedStack`,
      // nothing re-triggers `prefillFromProfileIfNeeded()` afterwards. That
      // would leave `cityId` at `null` here — worse than the ORIGINAL
      // staleness bug (which would instead leave it stuck at
      // 'city-stale-kyiv'). Only the actual fix — calling
      // `prefillFromProfileIfNeeded()` directly from `_save()` — lands on the
      // NEW city id.
      expect(
        container.read(searchFiltersControllerProvider).cityId,
        'city-new-odesa',
        reason:
            'the fix re-seeds the Search filter locality inline via '
            'prefillFromProfileIfNeeded() instead of blanking it with a bare '
            'invalidate',
      );
    },
  );

  // ---------------------------------------------------------------------------
  // Regression — the FIVE-TIMES-PATCHED bug: `_userTouchedLocality` is set by
  // the user-driven mutators (`selectSettlement`/`selectDistrict` — what
  // Пошук's OWN locality picker taps call, phase-346 renamed from
  // `selectOblast`/`selectCity`) and is NEVER cleared for the rest of the
  // session. `prefillFromProfileIfNeeded()` — the PASSIVE, anti-clobber
  // prefill — returns early once that flag is set. `_save()` used to call
  // THAT guarded method after a successful PATCH, so once a CLIENT had ever
  // touched Пошук's own picker, every subsequent profile-location save
  // silently no-op'd on Search.
  //
  // THE TRAP the test above ("saving a NEW locality re-seeds...") fell into:
  // it arms its precondition via `prefillFromProfileIfNeeded()`, which NEVER
  // sets `_userTouchedLocality` — so that test's precondition is `false`
  // throughout and it would pass IDENTICALLY against the pre-fix code. It
  // does not pin this regression at all (see mobile-qa mutation-test note).
  //
  // THIS test arms the guard the way a real user does: calling
  // `selectSettlement` directly on `SearchFiltersController` — the exact
  // mutator Пошук's own picker tap invokes — with a DIFFERENT locality (X)
  // than the one saved on THIS screen (Y). Only the AUTHORITATIVE
  // `applyProfileLocationSave` path (not `prefillFromProfileIfNeeded`) can
  // land Y.
  // ---------------------------------------------------------------------------

  testWidgets(
    'a locality armed via selectSettlement (the Пошук picker mutator — NOT '
    'prefillFromProfileIfNeeded) does not block a later profile-location save '
    'from reaching SearchFiltersController with the NEW city',
    (tester) async {
      _mutableProfileAfterPatch = _userAtStaleCity;

      final searchRepo = _MockClientProfileRepository();
      ClientProfileUpdate? captured;
      when(() => searchRepo.updateMyProfile(any())).thenAnswer((
        invocation,
      ) async {
        captured = invocation.positionalArguments.first as ClientProfileUpdate;
        _mutableProfileAfterPatch = _userAtNewCity;
      });

      final locationRepo = _FakeLocationRepository(
        settlements: const <Settlement>[
          _settlementStaleKyiv,
          _settlementNewOdesa,
        ],
        districtsByCity: const <String, List<CityDistrict>>{},
      );

      await tester.pumpRoutedApp(
        _buildRouter(),
        overrides: _overridesWithSearchSync(searchRepo, locationRepo),
      );
      await tester.pump();
      await tester.pump();

      final container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('location-cascade'))),
      );

      // This test's minimal `_buildRouter()` — unlike the real app router's
      // redirect guard — never reads `authProvider` itself, and neither does
      // `ClientLocationEditScreen` (only `clientEditProfileProvider`, a fully
      // custom stub). So NOTHING touches `authProvider` until
      // `SearchFiltersController.build()`'s own `ref.watch(authProvider
      // .select(...))` lazily triggers it below — and since that build() is its
      // FIRST read, it captures `authProvider` still mid-resolve (selectedId
      // null), then legitimately RE-RUNS (wiping `_userTouchedLocality`) the
      // instant the async auth settles a microtask later. Force + await
      // `authProvider` to settle FIRST, so `SearchFiltersController`'s own first
      // build() already sees the settled id and never re-runs out from under
      // the guard we are about to arm.
      await container.read(authProvider.future);
      await tester.pump();

      // ARRANGE: arm the guard the way a REAL user arms it — tapping Пошук's
      // OWN locality picker, i.e. calling `selectSettlement` on the controller
      // directly (exactly what `search_filters_screen.dart`'s picker tap
      // handler invokes) — with a DIFFERENT locality (X = city-stale-kyiv)
      // than what this screen saves below (Y = city-new-odesa).
      container
          .read(searchFiltersControllerProvider.notifier)
          .selectSettlement(cityId: 'city-stale-kyiv');
      expect(
        container.read(searchFiltersControllerProvider).cityId,
        'city-stale-kyiv',
        reason:
            'precondition: the guard is armed via the SAME mutator the real '
            'Search picker uses (selectSettlement), not the passive prefill',
      );

      // ACT: pick the NEW city (Y) on the Location screen and save.
      tester
          .widget<SettlementLocalityField>(
            find.byKey(const Key('location-cascade')),
          )
          .onSettlement('city-new-odesa', 'Одеса, Одеська');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn-save-location')));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.cityId, 'city-new-odesa');
      expect(find.byKey(const Key('stub-home')), findsOneWidget);

      // THE REGRESSION ASSERTION — pre-fix, `_save()` called the PASSIVE
      // `prefillFromProfileIfNeeded()`. `_userTouchedLocality` is true from
      // the ARRANGE step above, so that method returns immediately and this
      // would stay at 'city-stale-kyiv' (X) — the STALE touched value, not
      // even null. Only the AUTHORITATIVE `applyProfileLocationSave` path
      // unconditionally lands on Y.
      expect(
        container.read(searchFiltersControllerProvider).cityId,
        'city-new-odesa',
        reason:
            'an explicit profile-location save must ALWAYS win over an '
            'earlier Search-picker touch — this is the five-times-patched bug',
      );

      // Self-consistency: applyProfileLocationSave must leave the
      // `_lastSeeded*` bookkeeping matching what it just wrote, so a
      // SUBSEQUENT prefillFromProfileIfNeeded() call is a genuine no-op that
      // does NOT undo the save — it must not revert to X (city-stale-kyiv),
      // nor to null.
      await container
          .read(searchFiltersControllerProvider.notifier)
          .prefillFromProfileIfNeeded();
      expect(
        container.read(searchFiltersControllerProvider).cityId,
        'city-new-odesa',
        reason:
            'a later passive prefill must be a no-op — applyProfileLocationSave '
            'must leave _lastSeeded* self-consistent with what it just wrote',
      );
    },
  );
}

/// Stubbed [AuthNotifier] parameterised by the [User] under test — used by
/// the D7 prefill test, which needs a profile that already carries a
/// denormalised `cityName` rather than the blank `_stubUser`.
class _StubAuthNotifierFor extends AuthNotifier {
  _StubAuthNotifierFor(this._user);

  final User _user;

  @override
  Future<AuthSession> build() async =>
      AuthSession.authenticated(user: _user, accessToken: 'test-token');
}

class _StubClientEditProfileFor extends ClientEditProfile {
  _StubClientEditProfileFor(this._user);

  final User _user;

  @override
  Future<User> build() => Future<User>.value(_user);
}

// The same CLIENT profile AFTER the search-tab-resync test's save persists —
// what a real `GET /users/me` would return once the PATCH has landed.
const _userAtNewCity = User(
  id: 'user-1',
  email: 'client@beautica.ua',
  role: UserRole.client,
  firstName: 'Олена',
  lastName: 'Ковальчук',
  phoneNumber: '+380 50 123 45 67',
  cityId: 'city-new-odesa',
  cityName: 'Одеса',
);
