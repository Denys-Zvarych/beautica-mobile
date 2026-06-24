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
//   • the 5 sections render (search field, city row, category RAIL, price
//     slider + readout, sticky CTA) — all by Key;
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
      ],
      child: app,
    ),
  );

  return categoriesController;
}

void main() {
  group('ClientSearchScreen — sections', () {
    testWidgets('renders the 5 filter sections (by Key)', (tester) async {
      await _pumpScreen(tester);
      await tester.pumpAndSettle();

      // 2026-06-24 wordmark-jump hoist: the top bar (bell, no burger on Пошук)
      // is shell-owned now, so it is NOT present when the screen is pumped in
      // isolation. Its config (search_bell_button present, btn-menu-search
      // absent) is pinned in test/features/shell/client_shell_top_bar_test.dart.
      expect(find.byKey(const Key('search_bell_button')), findsNothing);

      // 1. pill search field.
      expect(find.byKey(const Key('search_query_field')), findsOneWidget);
      // 2. city select row.
      expect(find.byKey(const Key('search_city_value')), findsOneWidget);
      // 3. category rail (Variant A).
      expect(find.byKey(const Key('search_category_rail')), findsOneWidget);
      // 4. price slider + readout.
      expect(find.byKey(const Key('search_price_slider')), findsOneWidget);
      expect(find.byKey(const Key('search_price_readout')), findsOneWidget);
      // 5. sticky CTA.
      expect(find.byKey(const Key('search_show_masters_cta')), findsOneWidget);
    });

    testWidgets('city row shows the placeholder until a city is picked', (
      tester,
    ) async {
      await _pumpScreen(tester);
      await tester.pumpAndSettle();

      final AppLocalizations l10n = await _uk();
      final Text cityText = tester.widget<Text>(
        find.byKey(const Key('search_city_value')),
      );
      expect(cityText.data, l10n.searchCityPlaceholder);
    });

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
