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
// All finders are key/predicate-based (locale-invariant); settlement/category
// NAMES are backend data, asserted as content only.
//
// States / interactions covered (Phase 346 «Область»→«Місто»→«Район» cascade
// replaced by ONE settlement autocomplete):
//   • the sections render (search field, the settlement autocomplete, the
//     District row, category RAIL, price slider + readout, sticky CTA) — all
//     by Key;
//   • the settlement field shows its placeholder until something is picked;
//   • District gating — DISABLED until a settlement is picked (helper
//     «Спочатку оберіть місто»), stays DISABLED (helper «У цьому місті немає
//     районів») for a settlement with no districts, and ENABLES for one that
//     subdivides;
//   • cascade clears — re-picking the settlement clears a previously-chosen
//     District label, the settlement's inline clear («×») tears down the
//     District too, and the District's own clear («×») leaves the settlement
//     untouched;
//   • district-optional — a settlement with NO district is a valid committed
//     filter set carried to the results screen;
//   • the settlement search sheet resolves via the debounced
//     `settlementSearchProvider` — a below-minimum query shows the "type at
//     least 3 characters" hint and issues no pick, a 3+ character query
//     resolves after the debounce and the row is pickable;
//   • the rail renders one tile per provided category (keyed by slug) PLUS
//     the «Всі категорії» more-tile, laid out horizontally;
//   • tapping a rail tile selects it (visual inset well) AND sets the
//     controller's categoryKey;
//   • dragging the slider updates the readout and the controller's maxPrice;
//   • category LOADING → skeleton (no rail, no error retry);
//   • category ERROR → retry button (search_categories_retry), no rail;
//   • category EMPTY → empty message, no rail;
//   • CTA is enabled and pushes /search/results carrying the assembled
//     filters, with or without a settlement — an unset settlement is a
//     legitimate nationwide search (the retired "region without a city"
//     disabled gate cannot be reached any more — there is no half-chosen
//     locality state left to be in).

import 'dart:async';

import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
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
import 'package:beautica_mobile/features/home/application/client_edit_profile_notifier.dart';
import 'package:beautica_mobile/features/location/data/location_repository.dart';
import 'package:beautica_mobile/features/location/domain/city.dart';
import 'package:beautica_mobile/features/location/domain/city_district.dart';
import 'package:beautica_mobile/features/location/domain/oblast.dart';
import 'package:beautica_mobile/features/location/domain/settlement.dart';
import 'package:beautica_mobile/features/location/presentation/widgets/settlement_select_field.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:dio/dio.dart' show CancelToken;
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

// ── Settlement autocomplete fixtures (Phase 346) ─────────────────────────────
//
// The screen opens the shared SettlementSelectField sheet, which reads
// settlementSearchProvider(query) → LocationRepository.searchSettlements. Two
// settlements are seeded: «Київ» (subdivides — District enables) and «Львів»
// (does not — District stays disabled with the «no districts» helper).
// `districtsOf` (the same read the address screens use) decides which is
// which, so the fake's `fetchDistricts` is what actually drives the gate —
// there is no upfront `hasDistricts` flag on the wire any more.
const _kCityWithDistrictsId = 'city-kyiv';
const _kSettlementWithDistricts = Settlement(
  id: _kCityWithDistrictsId,
  name: 'Київ',
  // Kyiv is an oblast-equivalent whose oblast name equals its own —
  // `composeSettlementLabel` drops the repeated segment, so the composed
  // label is bare «Київ» (see `settlement.dart`'s doc on the degenerate case).
  oblastName: 'Київ',
);

const _kCityNoDistrictsId = 'city-lviv';
const _kSettlementNoDistricts = Settlement(
  id: _kCityNoDistrictsId,
  name: 'Львів',
  oblastName: 'Львівська',
);
// Composed label for the Lviv fixture (distinct oblast, so both segments are
// kept): «Львів, Львівська».
const _kLvivLabel = 'Львів, Львівська';

const _kDistrictId = 'dist-pechersk';
const _kDistrict = CityDistrict(
  id: _kDistrictId,
  cityId: _kCityWithDistrictsId,
  name: 'Печерський',
  katotthCode: 'UA80000000001000000',
);

/// Phase 346 — the fake locality data source. Every SettlementSelectField call
/// site (this screen included) now resolves locality through this ONE
/// interface instead of the retired oblast/city cascade, so a single fake
/// implementing it replaces the three separate family overrides
/// (`oblastListProvider` / `cityListProvider` / `districtListProvider`) the
/// pre-346 version of this file used.
class _FakeLocationRepository implements LocationRepository {
  @override
  Future<List<Oblast>> fetchOblasts() async => const <Oblast>[];

  @override
  Future<List<City>> fetchCities(String oblastId) async => const <City>[];

  /// Only the Kyiv fixture subdivides — this is what makes the District row
  /// enable for «Київ» and stay disabled (with the «no districts» hint) for
  /// «Львів».
  @override
  Future<List<CityDistrict>> fetchDistricts(String cityId) async =>
      cityId == _kCityWithDistrictsId
      ? const <CityDistrict>[_kDistrict]
      : const <CityDistrict>[];

  /// Both settlement fixtures on every query (blank query included — the
  /// pre-typing major-settlement list), so a test can pick either one without
  /// needing a query that would actually narrow to it.
  @override
  Future<List<Settlement>> searchSettlements(
    String query, {
    CancelToken? cancelToken,
  }) async => const <Settlement>[
    _kSettlementWithDistricts,
    _kSettlementNoDistricts,
  ];
}

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

// Stub the CLIENT profile the locality prefill reads on screen open. _testUser
// carries NO saved location, so prefillFromProfileIfNeeded resolves it and bails
// (filter left empty) WITHOUT touching the real clientProfileRepository / Dio —
// which would otherwise leak a connect-timeout Timer in the no-settle loading /
// error tests below.
class _FixedClientEditProfile extends ClientEditProfile {
  @override
  Future<User> build() => Future<User>.value(_testUser);
}

// A CLIENT whose saved profile carries a locality (settlement «Київ»,
// denormalised onto the profile as `cityId`/`cityName` — Phase 346 needs no
// taxonomy resolution for the label, it reads `cityName` straight off the
// profile). Used by the «Скинути фільтри» tests as the prefill source so the
// locality row resolves to «Київ» on open — the regression baseline: a
// prefilled location that a clear must never wipe.
const _clientWithLocation = User(
  id: 'u-client-1',
  email: 'client@beautica.ua',
  role: UserRole.client,
  firstName: 'Дмитро',
  lastName: 'Клієнт',
  cityId: _kCityWithDistrictsId,
  cityName: 'Київ',
);

class _FixedClientEditProfileLocated extends ClientEditProfile {
  @override
  Future<User> build() => Future<User>.value(_clientWithLocation);
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
  ClientEditProfile Function() profile = _FixedClientEditProfile.new,
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
      retry: beauticaProviderRetry,
      overrides: [
        authProvider.overrideWith(_FixedAuthNotifier.new),
        authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
        secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
        // The locality prefill reads clientEditProfileProvider on screen open;
        // stub it to a no-location user so it bails without a real Dio call.
        clientEditProfileProvider.overrideWith(profile),
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
        // Settlement autocomplete (Phase 346) — the ONE locality data source,
        // driving both the settlement sheet and the District row's
        // `districtsOf` gate through the same fake.
        locationRepositoryProvider.overrideWithValue(_FakeLocationRepository()),
      ],
      child: app,
    ),
  );

  return categoriesController;
}

// ── Locality picker drive helpers ────────────────────────────────────────────

/// Opens the settlement sheet and taps [settlementId]'s row from the blank
/// pre-typing major-settlement list (the fake serves both fixtures for every
/// query, blank included, so no typing is needed to reach either one).
Future<void> _pickSettlement(WidgetTester tester, String settlementId) async {
  await tester.tap(find.byKey(const Key('search_city_value')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('settlement_option_$settlementId')));
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

/// The key of the District row's inline clear («×») affordance. The source
/// derives it from the field key's underlying string value as
/// `Key('<value>_clear')` (e.g. `search_district_value_clear`). Mirror that
/// construction exactly so the finder tracks whatever the widget emits.
///
/// The settlement field's own clear button is NOT keyed this way any more —
/// `SettlementSelectField` delegates to the shared `SearchableSelectField`,
/// whose clear affordance carries the fixed key `select-field-clear`
/// (`searchable_select_field.dart`), not one derived from its `fieldKey`.
Key _clearKey(ValueKey<String> fieldKey) => Key('${fieldKey.value}_clear');

/// The settlement field's CLOSED display text (its current selection, or the
/// placeholder).
///
/// `search_city_value` (`SettlementSelectField.fieldKey`) is NOT a [Text] key
/// any more — `SearchableSelectField` puts it on the whole tappable
/// [GestureDetector] (`searchable_select_field.dart:343`), unlike the District
/// row's `_LocalityTapRow`, which still keys its inner `Text` directly. The
/// display `Text` inside the settlement field carries no key of its own, so it
/// is read by walking down from the keyed `GestureDetector` instead of up from
/// a keyed `Text`.
String? _cityValueText(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(
        of: find.byKey(const Key('search_city_value')),
        matching: find.byType(Text),
      ),
    )
    .data;

void main() {
  group('ClientSearchScreen — sections', () {
    testWidgets('renders the filter sections incl. the settlement '
        'autocomplete and the District row (by Key)', (tester) async {
      await _pumpScreen(tester);
      await tester.pumpAndSettle();

      // 2026-06-24 wordmark-jump hoist: the top bar (bell, no burger on Пошук)
      // is shell-owned now, so it is NOT present when the screen is pumped in
      // isolation. Its config (search_bell_button present, btn-menu-search
      // absent) is pinned in test/features/shell/client_shell_top_bar_test.dart.
      expect(find.byKey(const Key('search_bell_button')), findsNothing);

      // 1. pill search field.
      expect(find.byKey(const Key('search_query_field')), findsOneWidget);
      // 2. the settlement autocomplete (Phase 346 — ONE field, no cascade) +
      //    the (optional) District row.
      expect(find.byKey(const Key('search_settlement_field')), findsOneWidget);
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

    testWidgets('settlement field shows the placeholder until something is '
        'picked', (tester) async {
      await _pumpScreen(tester);
      await tester.pumpAndSettle();

      final AppLocalizations l10n = await _uk();
      expect(_cityValueText(tester), l10n.settlementPlaceholder);
    });
  });

  // ── District gating — the ONE remaining dependent field ───────────────────
  //
  // Phase 346 retired the Region→City cascade; District is now the only field
  // that depends on another. It is inert until a settlement is picked, and a
  // quiet helper line explains WHY. These tests pin the gating invariant: a
  // disabled field's tap does nothing AND a Semantics(enabled:false) node is
  // exposed.
  group('ClientSearchScreen — District gating', () {
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

    testWidgets('District is DISABLED until a settlement is picked — helper '
        '«Спочатку оберіть місто» shown, tap is inert', (tester) async {
      await _pumpScreen(tester, withRouter: true);
      await tester.pumpAndSettle();

      final AppLocalizations l10n = await _uk();

      expect(
        fieldEnabled(tester, const Key('search_district_value')),
        isFalse,
        reason: 'District must be disabled while no settlement is selected',
      );
      expect(find.text(l10n.searchDistrictDisabledHint), findsOneWidget);

      await tester.tap(find.byKey(const Key('search_district_value')));
      await tester.pumpAndSettle();
      // A disabled field swallows the tap: no district picker sheet opens.
      expect(find.byKey(const Key('locality_picker_search')), findsNothing);
      expect(_filters(tester).districtId, isNull);
    });

    testWidgets('District stays DISABLED for a settlement with no districts '
        '— helper «У цьому місті немає районів»', (tester) async {
      await _pumpScreen(tester, withRouter: true);
      await tester.pumpAndSettle();
      final AppLocalizations l10n = await _uk();

      await _pickSettlement(tester, _kCityNoDistrictsId); // Львів

      expect(_labels(tester).cityName, _kLvivLabel);
      expect(
        fieldEnabled(tester, const Key('search_district_value')),
        isFalse,
        reason: 'a settlement with no districts must keep District disabled',
      );
      expect(find.text(l10n.searchDistrictNoneHint), findsOneWidget);
    });

    testWidgets('District ENABLES for a settlement that subdivides — no '
        'helper', (tester) async {
      await _pumpScreen(tester, withRouter: true);
      await tester.pumpAndSettle();
      final AppLocalizations l10n = await _uk();

      await _pickSettlement(tester, _kCityWithDistrictsId); // Київ

      expect(
        fieldEnabled(tester, const Key('search_district_value')),
        isTrue,
        reason: 'a subdividing settlement must enable the District field',
      );
      // Neither gating helper is shown once District is live.
      expect(find.text(l10n.searchDistrictDisabledHint), findsNothing);
      expect(find.text(l10n.searchDistrictNoneHint), findsNothing);
    });
  });

  // ── Cascade clears — settlement / district ─────────────────────────────────
  //
  // A settlement change must invalidate the District picked under the PRIOR
  // settlement, on both the pick path and the settlement's own inline clear.
  // The District's own clear only ever touches the District.
  group('ClientSearchScreen — cascade clears', () {
    testWidgets('re-picking the settlement clears the previously-chosen '
        'District label (the visible district selection resets)', (
      tester,
    ) async {
      await _pumpScreen(tester, withRouter: true);
      await tester.pumpAndSettle();

      await _pickSettlement(tester, _kCityWithDistrictsId);
      await _pickDistrict(tester);
      expect(_labels(tester).districtName, 'Печерський');

      // `selectSettlement` unconditionally clears the district — even a
      // re-pick of the SAME settlement (Phase 346: any settlement change
      // clears it, since a flat autocomplete could otherwise land anywhere).
      await _pickSettlement(tester, _kCityWithDistrictsId);

      expect(_filters(tester).cityId, _kCityWithDistrictsId);
      expect(
        _labels(tester).districtName,
        isNull,
        reason: 'a settlement re-pick must drop the prior district label',
      );
      final AppLocalizations l10n = await _uk();
      final Text districtText = tester.widget<Text>(
        find.byKey(const Key('search_district_value')),
      );
      expect(districtText.data, l10n.searchDistrictPlaceholder);
    });

    testWidgets('the settlement clear («×») tears down the District too', (
      tester,
    ) async {
      await _pumpScreen(tester, withRouter: true);
      await tester.pumpAndSettle();

      await _pickSettlement(tester, _kCityWithDistrictsId);
      await _pickDistrict(tester);

      // The settlement field's clear affordance carries the fixed key
      // `select-field-clear` (SearchableSelectField), not one derived from
      // `search_city_value` — there is only one such field on this screen.
      await tester.tap(find.byKey(const Key('select-field-clear')));
      await tester.pumpAndSettle();

      expect(_filters(tester).cityId, isNull);
      expect(_filters(tester).districtId, isNull);
      expect(_labels(tester).cityName, isNull);
      expect(_labels(tester).districtName, isNull);
    });

    testWidgets('the District clear («×») clears only the district — the '
        'settlement survives', (tester) async {
      await _pumpScreen(tester, withRouter: true);
      await tester.pumpAndSettle();

      await _pickSettlement(tester, _kCityWithDistrictsId);
      await _pickDistrict(tester);
      expect(_filters(tester).districtId, _kDistrictId);

      await tester.tap(
        find.byKey(_clearKey(const ValueKey<String>('search_district_value'))),
      );
      await tester.pumpAndSettle();

      expect(_filters(tester).cityId, _kCityWithDistrictsId);
      expect(
        _filters(tester).districtId,
        isNull,
        reason: 'the optional district clears back to a settlement-wide search',
      );
      expect(_labels(tester).districtName, isNull);
    });
  });

  // ── District is OPTIONAL — a settlement with no district is valid ────────
  group('ClientSearchScreen — district is optional', () {
    testWidgets('Settlement + NO district is a valid committed filter set', (
      tester,
    ) async {
      await _pumpScreen(tester, withRouter: true);
      await tester.pumpAndSettle();

      await _pickSettlement(tester, _kCityWithDistrictsId);
      // District deliberately skipped — it is optional.

      final SearchFilters f = _filters(tester);
      expect(f.cityId, _kCityWithDistrictsId);
      expect(
        f.districtId,
        isNull,
        reason: 'a settlement-scoped search with no district is valid',
      );
      expect(_labels(tester).cityName, 'Київ');
      expect(_labels(tester).districtName, isNull);
    });
  });

  // ── Settlement search sheet — debounced remote autocomplete ──────────────
  //
  // The sheet is backed by `settlementSearchProvider`, debounced by
  // `kSettlementSearchDebounce`. `pumpAndSettle()` alone fires NO `Timer` —
  // without the explicit `pump(kSettlementSearchDebounce)` a test measures the
  // pre-tap state and passes vacuously (a recorded trap in this repo). Below
  // three characters the sheet shows the "type at least 3 characters" hint and
  // issues no request; at/above it the debounce elapses and the row resolves.
  group('ClientSearchScreen — settlement search debounce', () {
    testWidgets('a below-minimum query shows the hint and offers no row; a '
        '3+ character query resolves the row after the debounce', (
      tester,
    ) async {
      await _pumpScreen(tester, withRouter: true);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('search_city_value')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('select-menu-search')), 'ки');
      await tester.pump(kSettlementSearchDebounce);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('select-menu-minimum')), findsOneWidget);
      expect(
        find.byKey(const Key('settlement_option_$_kCityWithDistrictsId')),
        findsNothing,
      );

      await tester.enterText(
        find.byKey(const Key('select-menu-search')),
        'київ',
      );
      await tester.pump(kSettlementSearchDebounce);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('select-menu-minimum')), findsNothing);
      final Finder row = find.byKey(
        const Key('settlement_option_$_kCityWithDistrictsId'),
      );
      expect(row, findsOneWidget);

      await tester.tap(row);
      await tester.pumpAndSettle();

      expect(_filters(tester).cityId, _kCityWithDistrictsId);
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
          CategoryRailTile.kTileHeight + 8,
          reason:
              'the rail is pinned to the uniform tile height plus the '
              '4 dp top/bottom list padding',
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
        // and 8th, which the old `take(6)` cap would have dropped. The rail is a
        // LAZY horizontal list of uniform-width tiles, so the trailing tiles
        // only build once scrolled into view; reaching each key by scrolling
        // proves there is no cap (and no «Всі категорії» more-tile in between).
        final Finder railScrollable = find.descendant(
          of: find.byKey(const Key('search_category_rail')),
          matching: find.byType(Scrollable),
        );
        for (final String slug in const <String>[
          'NAILS',
          'BROWS',
          'HAIR',
          'LASH',
          'MAKEUP',
          'MASSAGE',
          'PERMANENT',
          'COSMETOLOGY',
        ]) {
          final Finder tile = find.byKey(Key('search_service_type_$slug'));
          await tester.scrollUntilVisible(
            tile,
            120,
            scrollable: railScrollable,
          );
          expect(
            tile,
            findsOneWidget,
            reason: 'category $slug must render (proves the 6-cap is gone)',
          );
        }

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

      // With no lower bound, the four-state readout collapses to «до Y ₴».
      final AppLocalizations l10n = await _uk();
      final Text readout = tester.widget<Text>(
        find.byKey(const Key('search_price_readout')),
      );
      expect(readout.data, isNot(l10n.searchPriceAny));
      expect(readout.data, l10n.searchPriceUpTo(maxPrice!.round()));
    });

    testWidgets('entering MIN + MAX shows the «від X до Y ₴» range readout', (
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

  // ── CTA query-length gate ────────────────────────────────────────────────
  //
  // A 1–2 character term is below what the backend honours, so it is never
  // promoted onto SearchFilters.query. The CTA used to sail straight through
  // it and push a search for whatever had been applied BEFORE — the user
  // arrived at results for a term they had already edited away. Watching the
  // draft is what makes the sub-minimum term visible to this gate at all;
  // watching `SearchFilters.query` cannot see it by construction.
  //
  // Phase 346 — the sibling "region without a city" disabled gate is GONE with
  // the cascade: a flat settlement autocomplete has no half-chosen locality
  // state to be in (see `search_filters_screen.dart`'s `_ShowMastersCta`
  // doc). This group therefore covers the query-length gate only; settlement
  // presence/absence is covered separately under "settlement carried to
  // results" below.
  group('ClientSearchScreen — CTA query-length gate', () {
    NeumorphicButton cta(WidgetTester tester) =>
        tester.widget<NeumorphicButton>(
          find.byKey(const Key('search_show_masters_cta')),
        );

    testWidgets('a 1-character term DISABLES the CTA', (tester) async {
      await _pumpScreen(tester, withRouter: true);
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('search_query_field')), 'м');
      await tester.pumpAndSettle();

      expect(
        cta(tester).onPressed,
        isNull,
        reason:
            'the user must not be able to reach results with a term the '
            'backend will not honour',
      );
    });

    testWidgets('a 2-character term DISABLES the CTA, and tapping is inert', (
      tester,
    ) async {
      await _pumpScreen(tester, withRouter: true);
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('search_query_field')), 'ма');
      await tester.pumpAndSettle();

      expect(cta(tester).onPressed, isNull);

      await tester.tap(find.byKey(const Key('search_show_masters_cta')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('test-results-sink')), findsNothing);
      expect(
        _pushedFilters,
        isNull,
        reason: 'the old behaviour pushed a search for the PREVIOUS term',
      );
    });

    testWidgets('an EMPTY box leaves the CTA enabled', (tester) async {
      await _pumpScreen(tester, withRouter: true);
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('search_query_field')), 'ма');
      await tester.pumpAndSettle();
      expect(cta(tester).onPressed, isNull);

      // Escape hatch 1: clear the box. A filters-only search is legitimate, so
      // an empty term is NOT an error and must not keep the CTA disabled.
      await tester.enterText(find.byKey(const Key('search_query_field')), '');
      await tester.pumpAndSettle();

      expect(cta(tester).onPressed, isNotNull);
    });

    testWidgets('completing the term to 3 characters RE-ENABLES the CTA', (
      tester,
    ) async {
      await _pumpScreen(tester, withRouter: true);
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('search_query_field')), 'ма');
      await tester.pumpAndSettle();
      expect(cta(tester).onPressed, isNull);

      // Escape hatch 2: finish the word.
      await tester.enterText(
        find.byKey(const Key('search_query_field')),
        'ман',
      );
      await tester.pumpAndSettle();

      expect(cta(tester).onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('search_show_masters_cta')));
      await tester.pumpAndSettle();
      expect(_pushedFilters?.query, 'ман');
    });
  });

  // ── Settlement carried to results — no gate on presence/absence ──────────
  //
  // Phase 346: an unset settlement is, and always was, a legitimate nationwide
  // search — there is no "settlement required" gate on the CTA any more (see
  // the query-length gate group's header comment for what replaced it).
  group('ClientSearchScreen — settlement carried to results', () {
    testWidgets('picking a settlement → CTA stays enabled and tapping pushes '
        '/search/results with the settlement carried', (tester) async {
      await _pumpScreen(tester, withRouter: true);
      await tester.pumpAndSettle();

      await _pickSettlement(tester, _kCityWithDistrictsId);
      expect(_filters(tester).cityId, _kCityWithDistrictsId);

      final NeumorphicButton cta = tester.widget<NeumorphicButton>(
        find.byKey(const Key('search_show_masters_cta')),
      );
      expect(cta.onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('search_show_masters_cta')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('test-results-sink')), findsOneWidget);
      expect(_pushedFilters, isNotNull);
      expect(_pushedFilters!.cityId, _kCityWithDistrictsId);
    });

    testWidgets('NO location at all (cityId null) → CTA stays enabled and '
        'tapping pushes a location-less «search everywhere»', (tester) async {
      await _pumpScreen(tester, withRouter: true);
      await tester.pumpAndSettle();

      expect(_filters(tester).cityId, isNull);
      final NeumorphicButton cta = tester.widget<NeumorphicButton>(
        find.byKey(const Key('search_show_masters_cta')),
      );
      expect(
        cta.onPressed,
        isNotNull,
        reason: 'a fully location-less search (browse everywhere) is allowed',
      );

      await tester.tap(find.byKey(const Key('search_show_masters_cta')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('test-results-sink')), findsOneWidget);
      expect(_pushedFilters, isNotNull);
      expect(_pushedFilters!.cityId, isNull);
    });
  });

  // ── «Скинути фільтри» — the non-location reset link ─────────────────────────
  //
  // The quiet reset link surfaces ONLY when a CLEARABLE (non-location) filter is
  // active, and tapping it clears those facets while the prefilled location
  // survives. These tests use a saved-profile CLIENT (settlement «Київ») so the
  // locality row is pre-filled on open — the core regression guard is that a
  // clear never wipes that prefilled location.
  group('ClientSearchScreen — clear filters («Скинути фільтри»)', () {
    testWidgets(
      'is HIDDEN when only the prefilled location is present (no clearable '
      'filter active)',
      (tester) async {
        await _pumpScreen(tester, profile: _FixedClientEditProfileLocated.new);
        await tester.pumpAndSettle();

        // The saved location prefilled the row (regression baseline: a location
        // IS present) ...
        expect(
          _cityValueText(tester),
          'Київ',
          reason: 'the saved-profile settlement must prefill the locality row',
        );
        expect(_filters(tester).cityId, _kCityWithDistrictsId);
        // ... yet with no query / category / price / service the reset link is
        // never surfaced (clearing would be a location-preserving no-op).
        expect(find.byKey(const Key('search_clear_filters')), findsNothing);
      },
    );

    testWidgets(
      'appears once a category is picked; tapping it clears the category + '
      'hides the link while KEEPING the prefilled location',
      (tester) async {
        await _pumpScreen(tester, profile: _FixedClientEditProfileLocated.new);
        await tester.pumpAndSettle();

        // Precondition: prefilled location, link hidden.
        expect(_filters(tester).cityId, _kCityWithDistrictsId);
        expect(find.byKey(const Key('search_clear_filters')), findsNothing);

        // Pick a category → the reset link surfaces.
        await tester.tap(find.byKey(const Key('search_service_type_NAILS')));
        await tester.pumpAndSettle();
        expect(_filters(tester).categoryKey, 'NAILS');
        expect(
          find.byKey(const Key('search_clear_filters')),
          findsOneWidget,
          reason: 'an active category must surface «Скинути фільтри»',
        );

        // Tap «Скинути фільтри».
        await tester.tap(find.byKey(const Key('search_clear_filters')));
        await tester.pumpAndSettle();

        // Category + its label cleared, and the link hides itself again ...
        expect(_filters(tester).categoryKey, isNull);
        expect(_labels(tester).categoryName, isNull);
        expect(find.byKey(const Key('search_clear_filters')), findsNothing);

        // ... but the prefilled locality is UNTOUCHED — the core regression guard.
        expect(_filters(tester).cityId, _kCityWithDistrictsId);
        expect(_labels(tester).cityName, 'Київ');
        expect(
          _cityValueText(tester),
          'Київ',
          reason: 'clearing filters must never wipe the prefilled location',
        );
      },
    );

    testWidgets(
      'clearing also resets an entered price + query to their defaults (readout '
      'returns to «будь-яка», query field emptied)',
      (tester) async {
        await _pumpScreen(tester, profile: _FixedClientEditProfileLocated.new);
        await tester.pumpAndSettle();
        final AppLocalizations l10n = await _uk();

        // Enter a price ceiling + a free-text query → the reset link surfaces.
        await tester.enterText(
          find.byKey(const Key('search_price_max_field')),
          '800',
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('search_query_field')),
          'манікюр',
        );
        await tester.pumpAndSettle();
        expect(_filters(tester).maxPrice, 800);
        expect(_filters(tester).query, 'манікюр');
        expect(find.byKey(const Key('search_clear_filters')), findsOneWidget);

        // Clear.
        await tester.tap(find.byKey(const Key('search_clear_filters')));
        await tester.pumpAndSettle();

        // Price + query reset; the readout returns to «будь-яка»; link hidden.
        expect(_filters(tester).maxPrice, isNull);
        expect(_filters(tester).minPrice, isNull);
        expect(_filters(tester).query, isNull);
        final Text readout = tester.widget<Text>(
          find.byKey(const Key('search_price_readout')),
        );
        expect(readout.data, l10n.searchPriceAny);
        expect(find.byKey(const Key('search_clear_filters')), findsNothing);
        // The search field's own TextEditingController was cleared too (the
        // onClear callback calls _searchController.clear()).
        final TextField queryField = tester.widget<TextField>(
          find.byKey(const Key('search_query_field')),
        );
        expect(queryField.controller?.text ?? '', isEmpty);

        // Location survived the clear.
        expect(_filters(tester).cityId, _kCityWithDistrictsId);
        expect(_cityValueText(tester), 'Київ');
      },
    );
  });
}
