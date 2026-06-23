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
// States / interactions covered:
//   • the 5 sections render (search field, city row, category grid, price
//     slider + readout, sticky CTA) — all by Key;
//   • the category grid renders one tile per provided category, keyed by slug;
//   • tapping a tile selects it (visual inset well) AND sets the controller's
//     categoryKey;
//   • dragging the slider updates the readout and the controller's maxPrice;
//   • grid LOADING → skeleton (no grid, no error retry);
//   • grid ERROR → retry button (search_categories_retry), no grid;
//   • grid EMPTY → empty message, no grid;
//   • CTA is enabled and pushes /search/results carrying the assembled filters.

import 'dart:async';

import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/discovery/domain/search_filters.dart';
import 'package:beautica_mobile/features/discovery/presentation/search_filters_screen.dart';
import 'package:beautica_mobile/features/discovery/presentation/state/search_filters_controller.dart';
import 'package:beautica_mobile/features/discovery/presentation/widgets/service_type_tile.dart';
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
      ],
      child: app,
    ),
  );

  return categoriesController;
}

void main() {
  group('ClientSearchScreen — sections', () {
    testWidgets('renders the 5 filter sections + top bar chrome (by Key)', (
      tester,
    ) async {
      await _pumpScreen(tester);
      await tester.pumpAndSettle();

      // Top bar (shared ClientTopBar).
      expect(find.byKey(const Key('search_bell_button')), findsOneWidget);
      expect(find.byKey(const Key('btn-menu-search')), findsOneWidget);

      // 1. pill search field.
      expect(find.byKey(const Key('search_query_field')), findsOneWidget);
      // 2. city select row.
      expect(find.byKey(const Key('search_city_value')), findsOneWidget);
      // 3. category grid.
      expect(find.byKey(const Key('search_service_type_grid')), findsOneWidget);
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

  group('ClientSearchScreen — category grid (loaded)', () {
    testWidgets('renders one tile per provided category, keyed by slug', (
      tester,
    ) async {
      await _pumpScreen(tester);
      await tester.pumpAndSettle();

      expect(find.byType(ServiceTypeTile), findsNWidgets(_categories.length));
      expect(
        find.byKey(const Key('search_service_type_NAILS')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('search_service_type_BROWS')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('search_service_type_HAIR')), findsOneWidget);

      // Ukrainian display labels (backend data, content assertion).
      expect(find.text('Манікюр'), findsOneWidget);
      expect(find.text('Брови'), findsOneWidget);
    });

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
    });

    // Regression guard for the 4→3 column change (full category names were
    // truncated at 4 columns / 0.78 aspect). Reads the grid's delegate rather
    // than counting on-screen rows so it is layout-deterministic and would FAIL
    // on the old crossAxisCount: 4, childAspectRatio: 0.78 values.
    testWidgets('category grid lays out 3 columns at 0.95 aspect ratio', (
      tester,
    ) async {
      await _pumpScreen(tester);
      await tester.pumpAndSettle();

      final GridView grid = tester.widget<GridView>(
        find.byKey(const Key('search_service_type_grid')),
      );
      final delegate = grid.gridDelegate;
      expect(
        delegate,
        isA<SliverGridDelegateWithFixedCrossAxisCount>(),
        reason: 'grid must use a fixed cross-axis count delegate',
      );
      final fixed = delegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(
        fixed.crossAxisCount,
        3,
        reason: 'full category names need 3 columns (4 truncated them)',
      );
      expect(fixed.childAspectRatio, 0.95);
    });
  });

  group('ClientSearchScreen — category grid (loading/error/empty)', () {
    testWidgets('LOADING → skeleton, no grid and no retry', (tester) async {
      await _pumpScreen(
        tester,
        categories: const AsyncLoading<List<ServiceCategoryOption>>(),
      );
      // Do NOT settle — keep the async provider pending so loading renders.
      await tester.pump();

      expect(find.byKey(const Key('search_service_type_grid')), findsNothing);
      expect(find.byKey(const Key('search_categories_retry')), findsNothing);
      expect(find.byType(ServiceTypeTile), findsNothing);
    });

    testWidgets('ERROR → retry button + error copy rendered, no grid; retry '
        'reloads the grid', (tester) async {
      // The override body returns a rejected Future on first load, settling
      // approvedCategoriesProvider to AsyncError (isLoading false, no prior
      // value) so the grid paints _GridError. We pump single frames (bounded)
      // until the rejection settles rather than pumpAndSettle — the keepAlive
      // search controllers rebuild and could otherwise re-enter loading.
      final categoriesController = await _pumpScreen(
        tester,
        categories: AsyncError<List<ServiceCategoryOption>>(
          StateError('boom'),
          StackTrace.empty,
        ),
      );
      // Do NOT pumpAndSettle — that lets the keepAlive controllers' rebuild
      // re-resolve the provider into seamless loading. Pump single frames until
      // the error branch appears (bounded, no settle-loop).
      for (var i = 0; i < 4; i++) {
        if (find
            .byKey(const Key('search_categories_retry'))
            .evaluate()
            .isNotEmpty) {
          break;
        }
        await tester.pump();
      }

      // Error branch: retry affordance + localized error copy, NO grid.
      expect(find.byKey(const Key('search_categories_retry')), findsOneWidget);
      expect(find.byKey(const Key('search_service_type_grid')), findsNothing);
      expect(find.byType(ServiceTypeTile), findsNothing);
      final AppLocalizations l10n = await _uk();
      expect(find.text(l10n.searchCategoriesLoadError), findsOneWidget);

      // Tapping retry calls ref.invalidate(approvedCategoriesProvider); flip the
      // controller to succeed so the re-run paints the grid — proving the retry
      // callback rewires the provider, not a dead button.
      categoriesController.current = const AsyncData(_categories);
      await tester.tap(find.byKey(const Key('search_categories_retry')));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('search_service_type_grid')), findsOneWidget);
      expect(find.byKey(const Key('search_categories_retry')), findsNothing);
    });

    testWidgets('EMPTY → empty message, no grid and no retry', (tester) async {
      await _pumpScreen(
        tester,
        categories: const AsyncData<List<ServiceCategoryOption>>(
          <ServiceCategoryOption>[],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('search_service_type_grid')), findsNothing);
      expect(find.byKey(const Key('search_categories_retry')), findsNothing);

      final AppLocalizations l10n = await _uk();
      expect(find.text(l10n.searchCategoriesEmpty), findsOneWidget);
    });
  });

  group('ClientSearchScreen — price slider', () {
    testWidgets('dragging the slider updates the readout and maxPrice', (
      tester,
    ) async {
      await _pumpScreen(tester);
      await tester.pumpAndSettle();

      ProviderContainer container() => ProviderScope.containerOf(
        tester.element(find.byType(ClientSearchScreen)),
      );

      // Drag the thumb left from the ceiling — must produce a finite maxPrice
      // strictly below kSearchPriceCeiling (and the readout leaves "будь-яка").
      final Finder slider = find.byKey(const Key('search_price_slider'));
      await tester.drag(slider, const Offset(-200, 0));
      await tester.pumpAndSettle();

      final double? maxPrice = container()
          .read(searchFiltersControllerProvider)
          .maxPrice;
      expect(maxPrice, isNotNull);
      expect(maxPrice, lessThan(kSearchPriceCeiling));

      final AppLocalizations l10n = await _uk();
      final Text readout = tester.widget<Text>(
        find.byKey(const Key('search_price_readout')),
      );
      expect(readout.data, isNot(l10n.searchPriceAny));
      expect(readout.data, l10n.searchPriceUpTo(maxPrice!.round()));
    });
  });

  group('ClientSearchScreen — CTA handoff', () {
    testWidgets('CTA is enabled and pushes /search/results with the assembled '
        'SearchFilters in extra', (tester) async {
      // withRouter: the CTA does context.push(/search/results) — needs go_router.
      await _pumpScreen(tester, withRouter: true);
      await tester.pumpAndSettle();

      // Assemble a filter set: pick a category + drag price.
      await tester.tap(find.byKey(const Key('search_service_type_BROWS')));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const Key('search_price_slider')),
        const Offset(-150, 0),
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
      expect(_pushedFilters!.maxPrice, lessThan(kSearchPriceCeiling));
    });
  });
}
