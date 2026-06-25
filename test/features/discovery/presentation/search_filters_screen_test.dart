// Phase 13.3 — Widget tests for [ClientSearchScreen] (the Пошук filters screen).
//
// Drives the real screen with the keepAlive filter controllers running against
// a stubbed authProvider (so build() settles) and an overridden
// approvedCategoriesProvider so each of the grid's loading / loaded / empty /
// error states can be pumped deterministically.
//
// The screen is pumped inside a minimal GoRouter (the CTA does
// context.push(/search/results) — a real router context is required) so the
// nav-with-filters handoff can be asserted end-to-end here too.
//
// All finders are key/predicate-based (locale-invariant); city/category NAMES
// are backend data, asserted as content only.
//
// States / interactions covered (Variant A «Рейка + послуги» redesign):
//   • the sections render (search field, the THREE locality fields
//     region/city/district, category RAIL, price slider + readout, sticky CTA)
//     — all by Key;
//   • locality gating funnel — City is DISABLED until a Region is picked (helper
//     «Спочатку оберіть регіон»), District is DISABLED until a City is picked
//     and stays disabled (helper «У цьому місті немає районів») for a city with
//     no districts; each becomes enabled as its parent is chosen;
//   • cascade clears — picking a Region clears City + District, picking a City
//     clears District, and the per-field clear («×») tears down the right slice
//     (region-clear → all three, city-clear → district only, region kept);
//   • district-optional — a Region + City selection with NO district is a valid
//     committed filter set carried to the results screen;
//   • the rail renders one tile per provided category (keyed by slug) PLUS the
//     «Всі категорії» more-tile, laid out horizontally;
//   • tapping a rail tile selects it (visual inset well) AND sets the
//     controller's categoryKey;
//   • dragging the slider updates the readout and the controller's maxPrice;
//   • category LOADING → skeleton (no rail, no error retry);
//   • category ERROR → retry button (search_categories_retry), no rail;
//   • category EMPTY → empty message, no rail;
//   • CTA is enabled and pushes /search/results carrying the assembled filters.

import 'dart:async';

import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/discovery/data/category_service_providers.dart';
import 'package:beautica_mobile/features/discovery/domain/category_service_option.dart';
import 'package:beautica_mobile/features/discovery/domain/search_filters.dart';
import 'package:beautica_mobile/features/discovery/presentation/search_filters_screen.dart';
import 'package:beautica_mobile/features/discovery/presentation/state/search_filters_controller.dart';
import 'package:beautica_mobile/features/discovery/presentation/widgets/category_rail.dart';
import 'package:beautica_mobile/features/discovery/presentation/widgets/service_chip_drawer.dart';
import 'package:beautica_mobile/features/location/domain/city.dart';
import 'package:beautica_mobile/features/location/domain/city_district.dart';
import 'package:beautica_mobile/features/location/domain/oblast.dart';
import 'package:beautica_mobile/features/location/state/location_providers.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';
import '../../../helpers/overflow_guard.dart';

// The production approvedCategoriesProvider now sources categories DIRECTLY
// from categoryRequestApiProvider.listApproved() (a CLIENT-search 403
// decoupling — it no longer delegates to ServiceRepository.fetchApproved
// categories()). So each test overrides approvedCategoriesProvider itself with
// an async body that resolves / throws / never-completes to drive the grid's
// loaded / error / loading states deterministically.
class _MockServiceRepository extends Mock implements ServiceRepository {}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _testUser = User(
  id: 'u-client-1',
  email: 'client@beautica.ua',
  role: UserRole.client,
  firstName: 'Дмитро',
  lastName: 'Клієнт',
);

const _authenticated = AsyncData<AuthSession>(
  AuthSession.authenticated(user: _testUser, accessToken: 'tok'),
);

const _categories = <ServiceCategoryOption>[
  ServiceCategoryOption(name: 'NAILS', displayName: 'Манікюр'),
  ServiceCategoryOption(name: 'BROWS', displayName: 'Брови'),
  ServiceCategoryOption(name: 'HAIR', displayName: 'Волосся'),
];

// Eight categories — MORE than the old `take(6)` cap. Used to prove the rail now
// renders EVERY category (no 6-cap, no «Всі категорії» more-tile). The last two
// entries (indices 6,7) existing AND rendering is the regression that fails on
// the old capped rail. One entry carries the longest real label to also prove
// the full-name (no-ellipsis) tile renders inside the screen's rail context.
const _eightCategories = <ServiceCategoryOption>[
  ServiceCategoryOption(name: 'NAILS', displayName: 'Манікюр'),
  ServiceCategoryOption(name: 'BROWS', displayName: 'Брови'),
  ServiceCategoryOption(name: 'HAIR', displayName: 'Волосся'),
  ServiceCategoryOption(name: 'LASH', displayName: 'Вії'),
  ServiceCategoryOption(name: 'MAKEUP', displayName: 'Макіяж'),
  ServiceCategoryOption(name: 'MASSAGE', displayName: 'Масаж'),
  ServiceCategoryOption(name: 'PERMANENT', displayName: 'Перманентний макіяж'),
  ServiceCategoryOption(name: 'COSMETOLOGY', displayName: 'Косметологія'),
];

// ── Locality cascade fixtures (drive the THREE-field location funnel) ────────
//
// The screen opens the REAL showLocalityPickerSheet, which reads
// oblastListProvider / cityListProvider(oblastId) / districtListProvider(cityId).
// Each test overrides those three providers DIRECTLY with deterministic fakes so
// the Region → City → District picks resolve without any network. Two cities are
// seeded: «Київ» (hasDistricts: true) to prove the District row ENABLES, and
// «Львів» (hasDistricts: false) to prove it stays DISABLED with the
// «no districts» helper.
const _kOblastId = 'oblast-kyiv';
const _kOblast = Oblast(
  id: _kOblastId,
  name: 'Київська',
  katotthCode: 'UA32000000000000000',
);

const _kCityWithDistrictsId = 'city-kyiv';
const _kCityWithDistricts = City(
  id: _kCityWithDistrictsId,
  oblastId: _kOblastId,
  name: 'Київ',
  katotthCode: 'UA80000000000093317',
  hasDistricts: true,
);

const _kCityNoDistrictsId = 'city-lviv';
const _kCityNoDistricts = City(
  id: _kCityNoDistrictsId,
  oblastId: _kOblastId,
  name: 'Львів',
  katotthCode: 'UA46000000000026870',
  hasDistricts: false,
);

const _kDistrictId = 'dist-pechersk';
const _kDistrict = CityDistrict(
  id: _kDistrictId,
  cityId: _kCityWithDistrictsId,
  name: 'Печерський',
  katotthCode: 'UA80000000001000000',
);

// Stub authProvider so the keepAlive search controllers build cleanly.
// Posts AsyncData(Authenticated) synchronously inside build() so authProvider
// is settled from the first frame.
class _FixedAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async {
    state = _authenticated;
    return const AuthSession.authenticated(user: _testUser, accessToken: 'tok');
  }
}

Future<AppLocalizations> _uk() =>
    AppLocalizations.delegate.load(const Locale('uk'));

// Captures the SearchFilters the CTA pushes to /search/results.
SearchFilters? _pushedFilters;

/// A mutable holder for the desired [approvedCategoriesProvider] result, read
/// fresh on every provider (re-)run. Lets the retry test flip the result from
/// error → data and have a subsequent `ref.invalidate` re-resolve to the new
/// value — exactly as the production retry affordance does.
class _CategoriesController {
  _CategoriesController(this.current);

  AsyncValue<List<ServiceCategoryOption>> current;

  /// Produces the body for the [approvedCategoriesProvider] override, reflecting
  /// the latest [current] each time the provider runs:
  ///   • AsyncData(value) → completes with the value,
  ///   • AsyncError       → throws (settles to AsyncError),
  ///   • AsyncLoading     → never completes (skeleton stays up).
  Future<List<ServiceCategoryOption>> build(Ref ref) {
    final categories = current;
    switch (categories) {
      case AsyncError(:final Object error):
        return Future<List<ServiceCategoryOption>>.error(error);
      case AsyncData(:final List<ServiceCategoryOption> value):
        return Future<List<ServiceCategoryOption>>.value(value);
      default:
        return Completer<List<ServiceCategoryOption>>().future;
    }
  }
}

/// Pumps [ClientSearchScreen] with [approvedCategoriesProvider] overridden to
/// reflect [categories]. Returns a [_CategoriesController] so a test can re-set
/// the result (e.g. retry: error → data) before invalidating.
///
/// By default the screen is the `home:` of a plain [MaterialApp]. Pass
/// [withRouter] = true for the CTA-handoff test (which needs go_router's
/// `context.push` to reach /search/results). A plain `home:` avoids the
/// initial route-transition frame that, with [MaterialApp.router], defers the
/// grid's first provider read into the seamless AsyncLoading(error:) state.
Future<_CategoriesController> _pumpScreen(
  WidgetTester tester, {
  AsyncValue<List<ServiceCategoryOption>> categories = const AsyncData(
    _categories,
  ),
  bool withRouter = false,
}) async {
  installOverflowGuard();
  _pushedFilters = null;

  final repo = _MockServiceRepository();
  final categoriesController = _CategoriesController(categories);

  // Tall surface so the whole scrollable filter column (incl. the price slider
  // near the bottom) lays out on-screen — drag()/tap() need an on-screen,
  // hit-testable target, not just a present-in-tree one.
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  // Construct the GoRouter ONLY for the routed variant — building it eagerly
  // for the plain-home case perturbs the first-frame settle that the error
  // test relies on.
  final Widget app = withRouter
      ? MaterialApp.router(
          routerConfig: GoRouter(
            initialLocation: '/search',
            routes: <RouteBase>[
              GoRoute(
                path: '/search',
                builder: (_, _) => const ClientSearchScreen(),
              ),
              GoRoute(
                path: '/search/results',
                builder: (_, GoRouterState state) {
                  _pushedFilters = state.extra as SearchFilters?;
                  return const Scaffold(key: Key('test-results-sink'));
                },
              ),
              GoRoute(
                path: '/client/menu',
                builder: (_, _) => const Scaffold(key: Key('test-menu-sink')),
              ),
            ],
          ),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('uk'),
        )
      : const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('uk'),
          home: ClientSearchScreen(),
        );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(_FixedAuthNotifier.new),
        authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
        secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
        // Repo override kept for any other repository-backed reads the screen
        // performs; categories now come straight from the provider override.
        serviceRepositoryProvider.overrideWithValue(repo),
        // Drive the grid's loaded / error / loading states directly via the
        // production provider, reading the mutable controller on each run.
        approvedCategoriesProvider.overrideWith(categoriesController.build),
        // The second-level service drawer is now async (categoryServiceOptions
        // Provider → CategoryServiceRepository). Resolve NAILS to a fake family
        // so the «select a tile → drawer reveals» assertion resolves to the data
        // state deterministically (no real network).
        categoryServiceOptionsProvider('NAILS').overrideWith(
          (ref) async => const <CategoryServiceOption>[
            CategoryServiceOption(key: 'manicure', displayName: 'Манікюр'),
          ],
        ),
        // Locality cascade — drive the picker sheets deterministically. Oblast
        // → both cities, and the with-districts city → one district. The
        // no-districts city deliberately has NO district override (the screen
        // never requests districts for it — hasDistricts gates that).
        oblastListProvider.overrideWith(
          (ref) async => const <Oblast>[_kOblast],
        ),
        cityListProvider(_kOblastId).overrideWith(
          (ref) async => const <City>[_kCityWithDistricts, _kCityNoDistricts],
        ),
        districtListProvider(
          _kCityWithDistrictsId,
        ).overrideWith((ref) async => const <CityDistrict>[_kDistrict]),
      ],
      child: app,
    ),
  );

  return categoriesController;
}

// ── Locality picker drive helpers ────────────────────────────────────────────
//
// Each opens the on-screen field, taps the row in the resulting sheet (keyed by
// the item's UUID — the picker tile key is `locality_picker_tile_<id>`), and
// settles. They mirror the real user gesture, so the screen's _pickRegion /
// _pickCity / _pickDistrict cascade callbacks run end to end.

Future<void> _pickRegion(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('search_region_value')));
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const ValueKey<String>('locality_picker_tile_$_kOblastId')),
  );
  await tester.pumpAndSettle();
}

Future<void> _pickCity(WidgetTester tester, String cityId) async {
  await tester.tap(find.byKey(const Key('search_city_value')));
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(ValueKey<String>('locality_picker_tile_$cityId')),
  );
  await tester.pumpAndSettle();
}

Future<void> _pickDistrict(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('search_district_value')));
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const ValueKey<String>('locality_picker_tile_$_kDistrictId')),
  );
  await tester.pumpAndSettle();
}

/// Reads the labels controller off the screen's element container.
SearchFilterLabels _labels(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(ClientSearchScreen)),
).read(searchFilterLabelsControllerProvider);

/// Reads the wire-facing SearchFilters off the screen's element container.
SearchFilters _filters(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(ClientSearchScreen)),
).read(searchFiltersControllerProvider);

/// The key of a field's inline clear («×») affordance. The source derives it
/// from the field key's underlying string value as `Key('<value>_clear')`
/// (e.g. `search_region_value_clear`). Mirror that construction exactly so the
/// finder tracks whatever the widget emits.
Key _clearKey(ValueKey<String> fieldKey) => Key('${fieldKey.value}_clear');

void main() {
  group('ClientSearchScreen — sections', () {
    testWidgets('renders the filter sections incl. the THREE locality fields '
        '(by Key)', (tester) async {
      await _pumpScreen(tester);
      await tester.pumpAndSettle();

      // 2026-06-24 wordmark-jump hoist: the top bar (bell, no burger on Пошук)
      // is shell-owned now, so it is NOT present when the screen is pumped in
      // isolation. Its config (search_bell_button present, btn-menu-search
      // absent) is pinned in test/features/shell/client_shell_top_bar_test.dart.
      expect(find.byKey(const Key('search_bell_button')), findsNothing);

      // 1. pill search field.
      expect(find.byKey(const Key('search_query_field')), findsOneWidget);
      // 2. THREE discrete locality fields (Регіон → Місто → Район).
      expect(find.byKey(const Key('search_region_value')), findsOneWidget);
      expect(find.byKey(const Key('search_city_value')), findsOneWidget);
      expect(find.byKey(const Key('search_district_value')), findsOneWidget);
      // 3. category rail (Variant A).
      expect(find.byKey(const Key('search_category_rail')), findsOneWidget);
      // 4. price slider + readout.
      expect(find.byKey(const Key('search_price_slider')), findsOneWidget);
      expect(find.byKey(const Key('search_price_readout')), findsOneWidget);
      // 5. sticky CTA.
      expect(find.byKey(const Key('search_show_masters_cta')), findsOneWidget);
    });

    testWidgets('region row shows the placeholder until a region is picked', (
      tester,
    ) async {
      await _pumpScreen(tester);
      await tester.pumpAndSettle();

      final AppLocalizations l10n = await _uk();
      final Text regionText = tester.widget<Text>(
        find.byKey(const Key('search_region_value')),
      );
      expect(regionText.data, l10n.searchRegionPlaceholder);
    });

    testWidgets('city row shows the placeholder once a region is picked', (
      tester,
    ) async {
      await _pumpScreen(tester, withRouter: true);
      await tester.pumpAndSettle();
      await _pickRegion(tester);

      final AppLocalizations l10n = await _uk();
      final Text cityText = tester.widget<Text>(
        find.byKey(const Key('search_city_value')),
      );
      expect(cityText.data, l10n.searchCityPlaceholder);
    });
  });

  // ── Locality gating funnel — Region → City → District ─────────────────────
  //
  // The single combined «Місто · Район» row was replaced by three discrete,
  // gated fields. City is inert until a Region is chosen; District is inert
  // until a City that subdivides is chosen. Each gated field is non-tappable AND
  // shows a quiet helper line explaining WHY. These tests pin the gating
  // invariant: a disabled field's tap does nothing AND a Semantics(enabled:false)
  // node is exposed (so a tap cannot mutate the lower cascade level out of order).
  group('ClientSearchScreen — locality gating funnel', () {
    /// Reads the [Semantics] data the field exposes (button/enabled), via the
    /// SemanticsNode for the row's value Text key.
    bool fieldEnabled(WidgetTester tester, Key fieldKey) {
      // The Semantics wrapper sits ABOVE the value Text; walk up from the keyed
      // Text to the nearest Semantics and read its enabled flag.
      final Finder semantics = find.ancestor(
        of: find.byKey(fieldKey),
        matching: find.byType(Semantics),
      );
      final Semantics widget = tester.widgetList<Semantics>(semantics).first;
      return widget.properties.enabled ?? false;
    }

    testWidgets('City is DISABLED until a Region is picked — helper «Спочатку '
        'оберіть регіон» shown, tap is inert', (tester) async {
      await _pumpScreen(tester, withRouter: true);
      await tester.pumpAndSettle();

      final AppLocalizations l10n = await _uk();

      // Disabled-state assertion: the City field reads as disabled, shows the
      // gating helper, and a tap opens NO picker sheet (no oblast/city rows).
      expect(
        fieldEnabled(tester, const Key('search_city_value')),
        isFalse,
        reason: 'City must be disabled while no Region is selected',
      );
      expect(find.text(l10n.searchCityDisabledHint), findsOneWidget);

      await tester.tap(find.byKey(const Key('search_city_value')));
      await tester.pumpAndSettle();
      // A disabled field swallows the tap: no locality picker sheet opens.
      expect(find.byKey(const Key('locality_picker_search')), findsNothing);
      expect(_filters(tester).cityId, isNull);
    });

    testWidgets('City becomes ENABLED after a Region is picked — helper gone', (
      tester,
    ) async {
      await _pumpScreen(tester, withRouter: true);
      await tester.pumpAndSettle();
      final AppLocalizations l10n = await _uk();

      await _pickRegion(tester);

      expect(
        fieldEnabled(tester, const Key('search_city_value')),
        isTrue,
        reason: 'picking a Region must enable the City field',
      );
      expect(find.text(l10n.searchCityDisabledHint), findsNothing);
      expect(_labels(tester).oblastName, 'Київська');
    });

    testWidgets(
      'District is DISABLED until a City is picked — helper «Спочатку '
      'оберіть місто» shown',
      (tester) async {
        await _pumpScreen(tester, withRouter: true);
        await tester.pumpAndSettle();
        final AppLocalizations l10n = await _uk();

        // Even with a Region picked, District stays gated until a City exists.
        await _pickRegion(tester);

        expect(
          fieldEnabled(tester, const Key('search_district_value')),
          isFalse,
          reason: 'District must be disabled while no City is selected',
        );
        expect(find.text(l10n.searchDistrictDisabledHint), findsOneWidget);
      },
    );

    testWidgets('District stays DISABLED for a city with no districts — helper '
        '«У цьому місті немає районів»', (tester) async {
      await _pumpScreen(tester, withRouter: true);
      await tester.pumpAndSettle();
      final AppLocalizations l10n = await _uk();

      await _pickRegion(tester);
      await _pickCity(
        tester,
        _kCityNoDistrictsId,
      ); // Львів — hasDistricts:false

      expect(_labels(tester).cityName, 'Львів');
      expect(_labels(tester).cityHasDistricts, isFalse);
      expect(
        fieldEnabled(tester, const Key('search_district_value')),
        isFalse,
        reason: 'a city with no districts must keep the District row disabled',
      );
      expect(find.text(l10n.searchDistrictNoneHint), findsOneWidget);
    });

    testWidgets('District ENABLES for a city that subdivides — no helper', (
      tester,
    ) async {
      await _pumpScreen(tester, withRouter: true);
      await tester.pumpAndSettle();
      final AppLocalizations l10n = await _uk();

      await _pickRegion(tester);
      await _pickCity(
        tester,
        _kCityWithDistrictsId,
      ); // Київ — hasDistricts:true

      expect(_labels(tester).cityHasDistricts, isTrue);
      expect(
        fieldEnabled(tester, const Key('search_district_value')),
        isTrue,
        reason: 'a subdividing city must enable the District field',
      );
      // Neither gating helper is shown once District is live.
      expect(find.text(l10n.searchDistrictDisabledHint), findsNothing);
      expect(find.text(l10n.searchDistrictNoneHint), findsNothing);
    });
  });

  // ── Cascade clears — picking / clearing a parent tears down its children ──
  //
  // Region → City → District is a funnel: a change at any level must invalidate
  // the levels below it (they belonged to the prior parent). Both the pick path
  // and the per-field clear («×») paths are covered.
  group('ClientSearchScreen — cascade clears', () {
    testWidgets('picking a Region clears a previously-chosen City + District', (
      tester,
    ) async {
      await _pumpScreen(tester, withRouter: true);
      await tester.pumpAndSettle();

      // Build a full Region → City → District selection.
      await _pickRegion(tester);
      await _pickCity(tester, _kCityWithDistrictsId);
      await _pickDistrict(tester);
      expect(_filters(tester).cityId, _kCityWithDistrictsId);
      expect(_filters(tester).districtId, _kDistrictId);

      // Re-picking the Region resets the whole locality below it.
      await _pickRegion(tester);

      expect(_filters(tester).oblastId, _kOblastId);
      expect(_filters(tester).cityId, isNull);
      expect(_filters(tester).districtId, isNull);
      expect(_labels(tester).cityName, isNull);
      expect(_labels(tester).districtName, isNull);
    });

    testWidgets('re-picking a City clears the previously-chosen District label '
        '(the visible district selection resets)', (tester) async {
      await _pumpScreen(tester, withRouter: true);
      await tester.pumpAndSettle();

      await _pickRegion(tester);
      await _pickCity(tester, _kCityWithDistrictsId);
      await _pickDistrict(tester);
      expect(_labels(tester).districtName, 'Печерський');

      // Re-pick a City through the field → _pickCity calls setDistrictName(null),
      // so the visible district selection resets. (The screen clears the district
      // LABEL + cityHasDistricts on a city pick; the wire-id cascade integrity is
      // enforced by the region-first re-selection — pinned in the controller
      // test. Here we assert the user-visible district reset on a city change.)
      await _pickCity(tester, _kCityWithDistrictsId);

      expect(_filters(tester).cityId, _kCityWithDistrictsId);
      expect(
        _labels(tester).districtName,
        isNull,
        reason: 'a city re-pick must drop the prior district label',
      );
      // The District row re-reads the picker fresh (no stale district shown).
      final AppLocalizations l10n = await _uk();
      final Text districtText = tester.widget<Text>(
        find.byKey(const Key('search_district_value')),
      );
      expect(districtText.data, l10n.searchDistrictPlaceholder);
    });

    testWidgets('the Region clear («×») tears down ALL three levels', (
      tester,
    ) async {
      await _pumpScreen(tester, withRouter: true);
      await tester.pumpAndSettle();

      await _pickRegion(tester);
      await _pickCity(tester, _kCityWithDistrictsId);
      await _pickDistrict(tester);

      // Tap the region field's inline clear.
      await tester.tap(
        find.byKey(_clearKey(const ValueKey<String>('search_region_value'))),
      );
      await tester.pumpAndSettle();

      expect(_filters(tester).oblastId, isNull);
      expect(_filters(tester).cityId, isNull);
      expect(_filters(tester).districtId, isNull);
      expect(_labels(tester).oblastName, isNull);
      expect(_labels(tester).cityName, isNull);
      expect(_labels(tester).districtName, isNull);
    });

    testWidgets('the City clear («×») clears District but KEEPS the Region', (
      tester,
    ) async {
      await _pumpScreen(tester, withRouter: true);
      await tester.pumpAndSettle();

      await _pickRegion(tester);
      await _pickCity(tester, _kCityWithDistrictsId);
      await _pickDistrict(tester);

      await tester.tap(
        find.byKey(_clearKey(const ValueKey<String>('search_city_value'))),
      );
      await tester.pumpAndSettle();

      expect(
        _filters(tester).oblastId,
        _kOblastId,
        reason: 'clearing the city must not drop the region it lives in',
      );
      expect(_filters(tester).cityId, isNull);
      expect(_filters(tester).districtId, isNull);
      expect(_labels(tester).oblastName, 'Київська');
      expect(_labels(tester).cityName, isNull);
      expect(_labels(tester).districtName, isNull);
    });

    testWidgets('the District clear («×») clears only the district — Region + '
        'City survive', (tester) async {
      await _pumpScreen(tester, withRouter: true);
      await tester.pumpAndSettle();

      await _pickRegion(tester);
      await _pickCity(tester, _kCityWithDistrictsId);
      await _pickDistrict(tester);
      expect(_filters(tester).districtId, _kDistrictId);

      await tester.tap(
        find.byKey(_clearKey(const ValueKey<String>('search_district_value'))),
      );
      await tester.pumpAndSettle();

      expect(_filters(tester).oblastId, _kOblastId);
      expect(_filters(tester).cityId, _kCityWithDistrictsId);
      expect(
        _filters(tester).districtId,
        isNull,
        reason: 'the optional district clears back to a city-wide search',
      );
      expect(_labels(tester).districtName, isNull);
    });
  });

  // ── District is OPTIONAL — a Region + City with no district is valid ──────
  group('ClientSearchScreen — district is optional', () {
    testWidgets('Region + City + NO district is a valid committed filter set', (
      tester,
    ) async {
      await _pumpScreen(tester, withRouter: true);
      await tester.pumpAndSettle();

      await _pickRegion(tester);
      await _pickCity(tester, _kCityWithDistrictsId);
      // District deliberately skipped — it is optional.

      final SearchFilters f = _filters(tester);
      expect(f.oblastId, _kOblastId);
      expect(f.cityId, _kCityWithDistrictsId);
      expect(
        f.districtId,
        isNull,
        reason: 'a city-scoped search with no district is a valid selection',
      );
      // The city label committed; the district label stayed empty.
      expect(_labels(tester).cityName, 'Київ');
      expect(_labels(tester).districtName, isNull);
    });
  });

  group('ClientSearchScreen — price defaults', () {
    testWidgets(
      'price readout starts at "будь-яка" (slider pinned to ceiling)',
      (tester) async {
        await _pumpScreen(tester);
        await tester.pumpAndSettle();

        final AppLocalizations l10n = await _uk();
        final Text readout = tester.widget<Text>(
          find.byKey(const Key('search_price_readout')),
        );
        expect(readout.data, l10n.searchPriceAny);
      },
    );
  });

  group('ClientSearchScreen — category rail (loaded)', () {
    testWidgets(
      'rail renders one tile per provided category (keyed by slug), laid out '
      'horizontally',
      (tester) async {
        await _pumpScreen(tester);
        await tester.pumpAndSettle();

        // One CategoryRailTile per provided category, each keyed by slug.
        expect(
          find.byType(CategoryRailTile),
          findsNWidgets(_categories.length),
        );
        expect(
          find.byKey(const Key('search_service_type_NAILS')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('search_service_type_BROWS')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('search_service_type_HAIR')),
          findsOneWidget,
        );

        // The rail is a horizontally-scrolling ListView (never grows the page).
        final ListView rail = tester.widget<ListView>(
          find.byKey(const Key('search_category_rail')),
        );
        expect(
          rail.scrollDirection,
          Axis.horizontal,
          reason: 'the Variant A rail scrolls sideways, not vertically',
        );

        // Ukrainian display labels (backend data, content assertion).
        expect(find.text('Манікюр'), findsOneWidget);
        expect(find.text('Брови'), findsOneWidget);
      },
    );

    testWidgets('tapping a tile selects it — inset well + controller key set', (
      tester,
    ) async {
      await _pumpScreen(tester);
      await tester.pumpAndSettle();

      // Read state via the element's container.
      ProviderContainer container() => ProviderScope.containerOf(
        tester.element(find.byType(ClientSearchScreen)),
      );

      // Precondition: nothing selected.
      expect(
        container().read(searchFiltersControllerProvider).categoryKey,
        isNull,
      );

      // Before selection the second-level service drawer is collapsed.
      expect(find.byType(ServiceChipDrawer), findsNothing);

      await tester.tap(find.byKey(const Key('search_service_type_NAILS')));
      await tester.pumpAndSettle();

      // Controller now carries the slug.
      expect(
        container().read(searchFiltersControllerProvider).categoryKey,
        'NAILS',
      );
      // The selected tile renders its concave inset well.
      expect(
        find.descendant(
          of: find.byKey(const Key('search_service_type_NAILS')),
          matching: find.byType(NeumorphicInset),
        ),
        findsOneWidget,
      );
      // The label controller mirrors the display name.
      expect(
        container().read(searchFilterLabelsControllerProvider).categoryName,
        'Манікюр',
      );
      // Variant A second level: selecting a category reveals its service-chip
      // drawer (NAILS resolves via the overridden async categoryServiceOptions
      // Provider to a one-item fake family).
      expect(find.byType(ServiceChipDrawer), findsOneWidget);
    });

    // Variant A layout guard. The OLD grid put `crossAxisCount: 3` tiles in a
    // GridView; the rail replaced it with a fixed-height horizontal ListView so
    // the page never grows vertically and the trailing tile is clipped as a
    // "scroll for more" cue. This asserts the rail's geometry, NOT a grid.
    testWidgets(
      'category rail is a fixed-height horizontal ListView (no GridView)',
      (tester) async {
        await _pumpScreen(tester);
        await tester.pumpAndSettle();

        // The old grid is gone entirely.
        expect(find.byKey(const Key('search_service_type_grid')), findsNothing);

        // The rail is a horizontal ListView bounded to a fixed height.
        final Finder railFinder = find.byKey(const Key('search_category_rail'));
        final ListView rail = tester.widget<ListView>(railFinder);
        expect(rail.scrollDirection, Axis.horizontal);

        final Size railSize = tester.getSize(railFinder);
        expect(
          railSize.height,
          92,
          reason: 'the rail is pinned to its 92 dp design height',
        );
      },
    );
  });

  // ── Rail renders ALL categories (no `take(6)` cap, no «Всі категорії» tile) ─
  //
  // The redesign removed the 6-tile cap and the trailing «Всі категорії»
  // more-tile + its sheet. With a fixture of EIGHT categories the rail must show
  // all eight CategoryRailTiles and NOTHING extra — the old capped rail rendered
  // only 6 + a more-tile, so both assertions below fail on the regression.
  group('ClientSearchScreen — rail renders ALL categories', () {
    testWidgets(
      'renders one tile per category for >6 categories (the 6-cap is gone)',
      (tester) async {
        await _pumpScreen(
          tester,
          categories: const AsyncData(_eightCategories),
        );
        await tester.pumpAndSettle();

        // Every one of the eight categories renders a tile — including the 7th
        // and 8th, which the old `take(6)` cap would have dropped.
        expect(find.byType(CategoryRailTile), findsNWidgets(8));
        expect(
          find.byKey(const Key('search_service_type_PERMANENT')),
          findsOneWidget,
          reason: 'the 7th category must render (proves the 6-cap is gone)',
        );
        expect(
          find.byKey(const Key('search_service_type_COSMETOLOGY')),
          findsOneWidget,
          reason: 'the 8th category must render (proves the 6-cap is gone)',
        );

        // The «Всі категорії» more-tile + its sheet are deleted: no trailing
        // more-tile is laid out anywhere in the rail.
        expect(
          find.byKey(const Key('search_all_categories_tile')),
          findsNothing,
          reason: 'the «Всі категорії» more-tile was removed',
        );
      },
    );

    testWidgets(
      'a long category label renders IN FULL inside the rail (no ellipsis)',
      (tester) async {
        await _pumpScreen(
          tester,
          categories: const AsyncData(_eightCategories),
        );
        await tester.pumpAndSettle();

        // The longest fixture label («Перманентний макіяж») is rendered verbatim
        // by its tile — no truncation, no ellipsis (the tile sizes to its label).
        expect(find.text('Перманентний макіяж'), findsOneWidget);
        final Text label = tester.widget<Text>(
          find.text('Перманентний макіяж'),
        );
        expect(label.data, 'Перманентний макіяж');
        expect(
          label.overflow,
          isNot(TextOverflow.ellipsis),
          reason: 'the rail tile caption must not clip the full category name',
        );
        expect(label.softWrap, isTrue);
        expect(label.maxLines, 2);
      },
    );
  });

  // ── Top bar is shell-owned (2026-06-24 wordmark-jump hoist) ─────────────────
  //
  // ClientSearchScreen no longer builds a ClientTopBar — ClientShell mounts it
  // ONCE above the branch body, and on the Пошук branch the shell config omits
  // the burger (the settings hub it opens reads as redundant on a filter
  // surface). The burger-omission + bell-presence config is now pinned through
  // the real shell in test/features/shell/client_shell_top_bar_test.dart. Here
  // we only assert the screen pumped in isolation carries NO bar at all.
  group(
    'ClientSearchScreen — top bar is shell-owned (absent in isolation)',
    () {
      testWidgets('no bar widgets render when the screen is pumped alone', (
        tester,
      ) async {
        await _pumpScreen(tester);
        await tester.pumpAndSettle();

        // No bell (it lives in the shell), no burger of any key, and the burger
        // glyph widget (NeumorphicIconButton) is absent from the screen body.
        expect(find.byKey(const Key('search_bell_button')), findsNothing);
        expect(find.byKey(const Key('btn-menu-search')), findsNothing);
        expect(find.byType(NeumorphicIconButton), findsNothing);
      });
    },
  );

  group('ClientSearchScreen — category rail (loading/error/empty)', () {
    testWidgets('LOADING → skeleton, no rail and no retry', (tester) async {
      await _pumpScreen(
        tester,
        categories: const AsyncLoading<List<ServiceCategoryOption>>(),
      );
      // Do NOT settle — keep the async provider pending so loading renders.
      await tester.pump();

      expect(find.byKey(const Key('search_category_rail')), findsNothing);
      expect(find.byKey(const Key('search_categories_retry')), findsNothing);
      expect(find.byType(CategoryRailTile), findsNothing);
    });

    testWidgets('ERROR → retry button + error copy rendered, no rail; retry '
        'reloads the rail', (tester) async {
      // The override body returns a rejected Future on first load, settling
      // approvedCategoriesProvider to AsyncError (isLoading false, no prior
      // value) so the section paints _GridError. We pump single frames (bounded)
      // until the rejection settles rather than pumpAndSettle — the keepAlive
      // search controllers rebuild and could otherwise re-enter loading.
      //
      // PRESERVED Riverpod 3.x AsyncError-capture mechanism: a thrown Dart
      // Error + a plain MaterialApp `home:` (NOT MaterialApp.router) + single
      // bounded pump()s. pumpAndSettle would let the keepAlive controllers'
      // rebuild re-resolve the provider into a seamless AsyncLoading(error:).
      final categoriesController = await _pumpScreen(
        tester,
        categories: AsyncError<List<ServiceCategoryOption>>(
          StateError('boom'),
          StackTrace.empty,
        ),
      );
      // Do NOT pumpAndSettle — pump single frames until the error branch appears
      // (bounded, no settle-loop).
      for (var i = 0; i < 4; i++) {
        if (find
            .byKey(const Key('search_categories_retry'))
            .evaluate()
            .isNotEmpty) {
          break;
        }
        await tester.pump();
      }

      // Error branch: retry affordance + localized error copy, NO rail.
      expect(find.byKey(const Key('search_categories_retry')), findsOneWidget);
      expect(find.byKey(const Key('search_category_rail')), findsNothing);
      expect(find.byType(CategoryRailTile), findsNothing);
      final AppLocalizations l10n = await _uk();
      expect(find.text(l10n.searchCategoriesLoadError), findsOneWidget);

      // Tapping retry calls ref.invalidate(approvedCategoriesProvider); flip the
      // controller to succeed so the re-run paints the rail — proving the retry
      // callback rewires the provider, not a dead button.
      categoriesController.current = const AsyncData(_categories);
      await tester.tap(find.byKey(const Key('search_categories_retry')));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('search_category_rail')), findsOneWidget);
      expect(find.byKey(const Key('search_categories_retry')), findsNothing);
    });

    testWidgets('EMPTY → empty message, no rail and no retry', (tester) async {
      await _pumpScreen(
        tester,
        categories: const AsyncData<List<ServiceCategoryOption>>(
          <ServiceCategoryOption>[],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('search_category_rail')), findsNothing);
      expect(find.byKey(const Key('search_categories_retry')), findsNothing);

      final AppLocalizations l10n = await _uk();
      expect(find.text(l10n.searchCategoriesEmpty), findsOneWidget);
    });
  });

  group('ClientSearchScreen — price range', () {
    testWidgets('entering a MAX value updates the readout and maxPrice', (
      tester,
    ) async {
      await _pumpScreen(tester);
      await tester.pumpAndSettle();

      ProviderContainer container() => ProviderScope.containerOf(
        tester.element(find.byType(ClientSearchScreen)),
      );

      // The price line is now a two-thumb RangeSlider (key search_price_slider)
      // bidirectionally synced with the MIN/MAX numeric fields. Driving the MAX
      // field is the deterministic way to set a finite upper bound (a raw drag
      // on a RangeSlider is ambiguous between its two thumbs). The controller
      // keeps the upper bound below the ceiling and leaves "будь-яка".
      await tester.enterText(
        find.byKey(const Key('search_price_max_field')),
        '800',
      );
      await tester.pumpAndSettle();

      final double? maxPrice = container()
          .read(searchFiltersControllerProvider)
          .maxPrice;
      expect(maxPrice, isNotNull);
      expect(maxPrice, lessThan(kSearchPriceCeiling));
      expect(maxPrice, 800);

      // With no lower bound, the four-state readout collapses to «до Y грн».
      final AppLocalizations l10n = await _uk();
      final Text readout = tester.widget<Text>(
        find.byKey(const Key('search_price_readout')),
      );
      expect(readout.data, isNot(l10n.searchPriceAny));
      expect(readout.data, l10n.searchPriceUpTo(maxPrice!.round()));
    });

    testWidgets('entering MIN + MAX shows the «від X до Y грн» range readout', (
      tester,
    ) async {
      await _pumpScreen(tester);
      await tester.pumpAndSettle();

      ProviderContainer container() => ProviderScope.containerOf(
        tester.element(find.byType(ClientSearchScreen)),
      );

      await tester.enterText(
        find.byKey(const Key('search_price_min_field')),
        '300',
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('search_price_max_field')),
        '900',
      );
      await tester.pumpAndSettle();

      final SearchFilters filters = container().read(
        searchFiltersControllerProvider,
      );
      expect(filters.minPrice, 300);
      expect(filters.maxPrice, 900);

      final AppLocalizations l10n = await _uk();
      final Text readout = tester.widget<Text>(
        find.byKey(const Key('search_price_readout')),
      );
      expect(readout.data, l10n.searchPriceRange(300, 900));
    });
  });

  group('ClientSearchScreen — CTA handoff', () {
    testWidgets('CTA is enabled and pushes /search/results with the assembled '
        'SearchFilters in extra', (tester) async {
      // withRouter: the CTA does context.push(/search/results) — needs go_router.
      await _pumpScreen(tester, withRouter: true);
      await tester.pumpAndSettle();

      // Assemble a filter set: pick a category + set a price ceiling via the
      // MAX field (the price line is now a two-thumb RangeSlider synced with the
      // MIN/MAX wells — a field entry is the deterministic way to set a bound).
      await tester.tap(find.byKey(const Key('search_service_type_BROWS')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('search_price_max_field')),
        '750',
      );
      await tester.pumpAndSettle();

      // The CTA is a NeumorphicButton with a non-null onPressed (enabled).
      final NeumorphicButton cta = tester.widget<NeumorphicButton>(
        find.byKey(const Key('search_show_masters_cta')),
      );
      expect(cta.onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('search_show_masters_cta')));
      await tester.pumpAndSettle();

      // Landed on the results sink with the carried filters.
      expect(find.byKey(const Key('test-results-sink')), findsOneWidget);
      expect(_pushedFilters, isNotNull);
      expect(_pushedFilters!.categoryKey, 'BROWS');
      expect(_pushedFilters!.maxPrice, isNotNull);
      expect(_pushedFilters!.maxPrice, 750);
      expect(_pushedFilters!.maxPrice, lessThan(kSearchPriceCeiling));
    });
  });
}
