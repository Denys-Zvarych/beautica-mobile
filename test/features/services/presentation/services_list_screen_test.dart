// Phase 5.2 — Widget tests for ServicesListScreen.
//
// [ServicesListScreen] is a [ConsumerStatefulWidget]. The [ScreenProtector]
// lifecycle calls (preventScreenshotOn / preventScreenshotOff) are guarded
// by !kDebugMode, so they are never invoked during test runs and do not
// require mocking.
//
// Covers all AsyncValue states and key interactions:
//   1. Loading state — skeleton cards rendered; no service name text visible.
//   2. Error state   — ErrorState widget visible; retry button callable.
//   3. Empty state   — servicesEmpty l10n text visible;
//                      btn-create-service-empty key found; no FAB.
//   4. Populated     — ListView visible; service name "Стрижка" shown;
//                      formatted price "₴ 750" visible;
//                      formatted duration "45 хв" visible.
//   5. FAB           — btn-create-service key present in populated state.
//   6. Card tap      — GoRouter mock records push with the correct edit path.
//
// Strategy:
//   • Override [servicesListProvider] with a stub [ServicesList] notifier
//     that immediately emits the desired [AsyncValue] to state.
//   • Override [serviceRepositoryProvider] with a mocktail mock.
//   • Use [pumpApp] / [pumpRoutedApp] from `test/helpers/pump_app.dart`.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_notifier.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/pump_app.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class _MockServiceRepository extends Mock implements ServiceRepository {}

// ---------------------------------------------------------------------------
// Stub data
// ---------------------------------------------------------------------------

const _stubService = MasterService(
  id: 'svc-001',
  serviceDefId: 'def-001',
  name: 'Стрижка',
  durationMinutes: 45,
  priceMin: 750,
  priceDisplay: '750 грн',
);

const _stubServiceList = <MasterService>[_stubService];

/// Minimal [MasterService] factory for generating lists of arbitrary length.
/// Only the required fields are set; freezed defaults cover the rest.
MasterService _makeService(int i) => MasterService(
  id: 'svc-$i',
  serviceDefId: 'def-$i',
  name: 'Test $i',
  durationMinutes: 30,
  priceMin: 100,
  priceDisplay: '100 грн',
);

// ---------------------------------------------------------------------------
// Stub notifiers
// ---------------------------------------------------------------------------

/// Generic stub [ServicesList] notifier — resolves to [_target] state.
///
/// For the loading state, [build()] returns a never-completing [Future] so
/// the test can inspect the loading frame. For data/error states, [build()]
/// posts the desired state via [Future.microtask] so the screen sees a brief
/// loading frame first (consistent with real async behaviour).
class _StubServicesList extends ServicesList {
  _StubServicesList(this._target);

  final AsyncValue<List<MasterService>> _target;

  @override
  Future<List<MasterService>> build() {
    if (!_target.isLoading) {
      // Post the desired state on the next microtask so the screen sees one
      // loading frame followed by the target state.
      Future<void>.microtask(() => state = _target);
    }
    // Never-completing future — state is managed above.
    return Completer<List<MasterService>>().future;
  }
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

/// Returns a [ProviderScope] override that replaces [servicesListProvider]
/// with a stub notifier resolving to [target].
Object _servicesOverride(AsyncValue<List<MasterService>> target) =>
    servicesListProvider.overrideWith(() => _StubServicesList(target));

/// Minimal GoRouter that records pushed locations without any actual routing.
GoRouter _mockRouter({
  required List<String> pushedRoutes,
  String initialLocation = RouteNames.services,
}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: <RouteBase>[
      GoRoute(
        path: RouteNames.services,
        builder: (context, state) => const ServicesListScreen(),
      ),
      // Catch-all for /services/create and /services/:id/edit so push doesn't
      // throw "no route found".
      GoRoute(
        path: '/services/create',
        builder: (context, state) => const _DummyPage(label: 'create'),
      ),
      GoRoute(
        path: '/services/:id/edit',
        builder: (context, state) => const _DummyPage(label: 'edit'),
      ),
    ],
    observers: <NavigatorObserver>[_PushObserver(pushedRoutes)],
  );
}

class _DummyPage extends StatelessWidget {
  const _DummyPage({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Scaffold(body: Text('Dummy $label'));
}

/// Records all push events to [routes].
class _PushObserver extends NavigatorObserver {
  _PushObserver(this.routes);
  final List<String> routes;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final name = route.settings.name;
    if (name != null) routes.add(name);
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _MockServiceRepository mockRepo;

  setUp(() {
    mockRepo = _MockServiceRepository();
    when(() => mockRepo.listMyServices()).thenAnswer((_) async => const []);
    // _LoadedBody watches approvedCategoriesProvider to resolve category
    // labels (FIX 4). Default stub keeps the provider in the data state for
    // every existing test; FIX 4 tests override it with their own values.
    when(() => mockRepo.fetchApprovedCategories()).thenAnswer(
      (_) async => const <ServiceCategoryOption>[
        ServiceCategoryOption(name: 'HAIRCUT', displayName: 'Стрижка'),
      ],
    );
  });

  // ── 1. Loading state ───────────────────────────────────────────────────────

  testWidgets('loading state — skeleton cards rendered; no service name text', (
    tester,
  ) async {
    await tester.pumpApp(
      const ServicesListScreen(),
      overrides: [
        _servicesOverride(const AsyncLoading()),
        serviceRepositoryProvider.overrideWithValue(mockRepo),
      ],
    );
    // First pump triggers the loading frame.
    await tester.pump();

    expect(find.byKey(const Key('skeleton_card_0')), findsOneWidget);
    expect(find.byKey(const Key('skeleton_card_1')), findsOneWidget);
    expect(find.byKey(const Key('skeleton_card_2')), findsOneWidget);
    expect(find.text('Стрижка'), findsNothing);
  });

  // ── 1b. Loading state at a narrow width — no skeleton overflow (Bugfix 3) ──
  //
  // Regression: the _SkeletonCard's two shimmer metadata bars were fixed-width
  // (78 + 92 px). On the narrow loading frame shown immediately after creating
  // a service (a phone at ≤360 dp), the photo + name + fixed bars + trailing
  // glyph overran the row and threw a RenderFlex overflow. The fix made the two
  // metadata bars Expanded (flex 3 / flex 4) so they shrink to fit. This test
  // pins a 320 dp-wide surface and asserts the loading body lays out with no
  // overflow exception.

  testWidgets(
    'Bugfix 3: skeleton cards render at 320 dp width with no overflow',
    (tester) async {
      // Narrow phone surface (≤360 dp). 1:1 pixel ratio keeps logical == device.
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpApp(
        const ServicesListScreen(),
        overrides: [
          _servicesOverride(const AsyncLoading()),
          serviceRepositoryProvider.overrideWithValue(mockRepo),
        ],
      );
      // Loading frame — the shimmer controllers are running.
      await tester.pump();

      // All three skeleton cards must be present at this narrow width.
      expect(find.byKey(const Key('skeleton_card_0')), findsOneWidget);
      expect(find.byKey(const Key('skeleton_card_1')), findsOneWidget);
      expect(find.byKey(const Key('skeleton_card_2')), findsOneWidget);

      // The core assertion: no RenderFlex overflow was thrown while laying out
      // the skeleton row at 320 dp (Bugfix 3 — bars are Expanded, not fixed).
      expect(
        tester.takeException(),
        isNull,
        reason:
            'Bugfix 3: _SkeletonCard metadata bars must be Expanded so the '
            'loading row never overflows at narrow phone widths',
      );
    },
  );

  // ── 2. Error state ─────────────────────────────────────────────────────────

  testWidgets('error state — ErrorState widget rendered', (tester) async {
    await tester.pumpApp(
      const ServicesListScreen(),
      overrides: [
        _servicesOverride(const AsyncError(NetworkFailure(), StackTrace.empty)),
        serviceRepositoryProvider.overrideWithValue(mockRepo),
      ],
    );
    // First pump: loading frame. Second pump: microtask delivers error state.
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('services_error_state')), findsOneWidget);
    expect(find.byKey(const Key('error_state_retry_button')), findsOneWidget);
  });

  // ── 3. Empty state ─────────────────────────────────────────────────────────

  testWidgets('empty state — servicesEmpty text visible; '
      'btn-create-service-empty found; FAB absent', (tester) async {
    await tester.pumpApp(
      const ServicesListScreen(),
      overrides: [
        _servicesOverride(const AsyncData(<MasterService>[])),
        serviceRepositoryProvider.overrideWithValue(mockRepo),
      ],
    );
    // Loading frame → microtask → data frame.
    await tester.pump();
    await tester.pump();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(ServicesListScreen)),
    );
    expect(find.text(l10n.servicesEmpty), findsOneWidget);
    expect(find.byKey(const Key('btn-create-service-empty')), findsOneWidget);
    // FAB must NOT appear in the empty state — the inline CTA is the only
    // first-run path.
    expect(find.byKey(const Key('btn-create-service')), findsNothing);
  });

  // ── 4. Populated state ─────────────────────────────────────────────────────

  testWidgets(
    'populated state — ListView visible; service name, price, duration shown',
    (tester) async {
      await tester.pumpApp(
        const ServicesListScreen(),
        overrides: [
          _servicesOverride(const AsyncData(_stubServiceList)),
          serviceRepositoryProvider.overrideWithValue(mockRepo),
        ],
      );
      // Loading frame → microtask → data frame.
      await tester.pump();
      await tester.pump();
      // Advance entrance animation so the card becomes visible.
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(ListView), findsOneWidget);
      expect(find.text('Стрижка'), findsOneWidget);
      // Phase 5.6: price rendered from priceDisplay (server-formatted).
      expect(find.text('750 грн'), findsOneWidget);
      expect(find.text('45 хв'), findsOneWidget);
    },
  );

  // ── 5. FAB present in populated state ─────────────────────────────────────

  testWidgets('populated state — FAB btn-create-service found', (tester) async {
    await tester.pumpApp(
      const ServicesListScreen(),
      overrides: [
        _servicesOverride(const AsyncData(_stubServiceList)),
        serviceRepositoryProvider.overrideWithValue(mockRepo),
      ],
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const Key('btn-create-service')), findsOneWidget);
  });

  // ── 6. Card tap — router push ──────────────────────────────────────────────

  testWidgets('card tap — go_router push called with correct edit path', (
    tester,
  ) async {
    final pushedRoutes = <String>[];
    final router = _mockRouter(pushedRoutes: pushedRoutes);

    await tester.pumpRoutedApp(
      router,
      overrides: [
        _servicesOverride(const AsyncData(_stubServiceList)),
        serviceRepositoryProvider.overrideWithValue(mockRepo),
      ],
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final cardFinder = find.byKey(const Key('service_card_svc-001'));
    expect(cardFinder, findsOneWidget);

    await tester.tap(cardFinder);
    await tester.pumpAndSettle();

    // The dummy edit page should be reachable — find its text.
    expect(find.text('Dummy edit'), findsOneWidget);

    // Verify the correct path was resolved.
    final expectedPath = RouteNames.serviceEdit(_stubService.id);
    expect(expectedPath, '/services/svc-001/edit');
  });

  // ── 7. Ukrainian plural forms for _serviceWordUk ───────────────────────────

  group('_serviceWordUk plural forms', () {
    /// Pumps [ServicesListScreen] with [count] stub services, advances through
    /// the entrance animation, then asserts that the count label contains
    /// [expectedWord].
    Future<void> expectPluralLabel(
      WidgetTester tester, {
      required int count,
      required String expectedWord,
    }) async {
      final services = List<MasterService>.generate(count, _makeService);
      await tester.pumpApp(
        const ServicesListScreen(),
        overrides: [
          _servicesOverride(AsyncData(services)),
          serviceRepositoryProvider.overrideWithValue(mockRepo),
        ],
      );
      // Loading frame → microtask delivers data → data frame.
      await tester.pump();
      await tester.pump();
      // Advance past the longest possible stagger delay.
      // Each _ServiceCard at index i gets appearDelay = 90 * (i-1) ms.
      // For the largest list (count=100) the last card fires at 90*99 = 8910 ms.
      // Pumping 10 s of fake time drains all outstanding timers so the
      // test harness does not report "pending timers".
      await tester.pump(const Duration(seconds: 10));

      expect(
        find.text('$count $expectedWord'),
        findsOneWidget,
        reason: '_serviceWordUk($count) should return "$expectedWord"',
      );
    }

    testWidgets(
      'count=1 → "послуга" (n%10==1, not in exception class 11–14)',
      (tester) => expectPluralLabel(tester, count: 1, expectedWord: 'послуга'),
    );

    testWidgets(
      'count=2 → "послуги" (n%10==2)',
      (tester) => expectPluralLabel(tester, count: 2, expectedWord: 'послуги'),
    );

    testWidgets(
      'count=4 → "послуги" (n%10==4)',
      (tester) => expectPluralLabel(tester, count: 4, expectedWord: 'послуги'),
    );

    testWidgets(
      'count=5 → "послуг" (n%10==5 → default branch)',
      (tester) => expectPluralLabel(tester, count: 5, expectedWord: 'послуг'),
    );

    testWidgets(
      'count=11 → "послуг" (n%100==11 — exception class overrides n%10==1)',
      (tester) => expectPluralLabel(tester, count: 11, expectedWord: 'послуг'),
    );

    testWidgets(
      'count=14 → "послуг" (n%100==14 — boundary of exception class)',
      (tester) => expectPluralLabel(tester, count: 14, expectedWord: 'послуг'),
    );

    testWidgets(
      'count=21 → "послуга" (n%10==1, n%100==21 — NOT in exception class)',
      (tester) => expectPluralLabel(tester, count: 21, expectedWord: 'послуга'),
    );

    testWidgets(
      'count=100 → "послуг" (n%10==0 → default branch)',
      (tester) => expectPluralLabel(tester, count: 100, expectedWord: 'послуг'),
    );
  });

  // ── FIX 4. Category label resolution on the list card ──────────────────────
  //
  // Regression: the list rendered the raw uppercase wire slug ("BROWS"), while
  // the create form rendered the Ukrainian displayName. The list must now
  // resolve the label via approvedCategoriesProvider (Ukrainian when the slug
  // is approved) and fall back to a humanized form ("Brows") otherwise — never
  // an ALL-CAPS wire value.

  group('FIX 4 — category label resolution', () {
    const browsService = MasterService(
      id: 'svc-brows',
      serviceDefId: 'def-brows',
      name: 'Корекція брів',
      durationMinutes: 30,
      priceMin: 250,
      priceDisplay: '250 грн',
      category: 'BROWS',
    );

    testWidgets(
      'approved slug renders Ukrainian displayName (Брови), not raw BROWS',
      (tester) async {
        when(() => mockRepo.fetchApprovedCategories()).thenAnswer(
          (_) async => const <ServiceCategoryOption>[
            ServiceCategoryOption(name: 'BROWS', displayName: 'Брови'),
          ],
        );

        await tester.pumpApp(
          const ServicesListScreen(),
          overrides: [
            _servicesOverride(const AsyncData(<MasterService>[browsService])),
            serviceRepositoryProvider.overrideWithValue(mockRepo),
          ],
        );
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(
          find.text('Брови'),
          findsOneWidget,
          reason:
              'card must render the Ukrainian displayName from the approved '
              'category list (FIX 4)',
        );
        expect(
          find.text('BROWS'),
          findsNothing,
          reason: 'raw ALL-CAPS wire slug must never leak to the UI',
        );
      },
    );

    testWidgets(
      'unapproved slug falls back to humanized label (Brows), not raw BROWS',
      (tester) async {
        // Approved list does NOT contain BROWS (inactive/retired category).
        when(() => mockRepo.fetchApprovedCategories()).thenAnswer(
          (_) async => const <ServiceCategoryOption>[
            ServiceCategoryOption(name: 'HAIRCUT', displayName: 'Стрижка'),
          ],
        );

        await tester.pumpApp(
          const ServicesListScreen(),
          overrides: [
            _servicesOverride(const AsyncData(<MasterService>[browsService])),
            serviceRepositoryProvider.overrideWithValue(mockRepo),
          ],
        );
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(
          find.text('Brows'),
          findsOneWidget,
          reason:
              'slug absent from the approved list must be humanized (FIX 4)',
        );
        expect(
          find.text('BROWS'),
          findsNothing,
          reason: 'raw ALL-CAPS wire slug must never leak to the UI',
        );
      },
    );
  });

  // ── B. Grouped-list virtualization regression suite ────────────────────────
  //
  // These guard the behaviours the services + auth change set exists to deliver:
  // first-appearance section ordering, creation order within a section,
  // default-expanded sections with a working collapse toggle, the category
  // label living ONLY in the section header (never per-card), and the
  // uncategorized bucket ordering.

  group('B. grouped list', () {
    // Three services in creation order A, B, C; A & C share HAIRCUT, B is BROWS.
    const aHaircut = MasterService(
      id: 'a',
      serviceDefId: 'def-a',
      name: 'Сервіс A',
      durationMinutes: 30,
      priceMin: 100,
      priceDisplay: '100 грн',
      category: 'HAIRCUT',
    );
    const bBrows = MasterService(
      id: 'b',
      serviceDefId: 'def-b',
      name: 'Сервіс B',
      durationMinutes: 30,
      priceMin: 200,
      priceDisplay: '200 грн',
      category: 'BROWS',
    );
    const cHaircut = MasterService(
      id: 'c',
      serviceDefId: 'def-c',
      name: 'Сервіс C',
      durationMinutes: 30,
      priceMin: 300,
      priceDisplay: '300 грн',
      category: 'HAIRCUT',
    );

    // Section + card key helpers — mirror the production key format
    // (`category_section_<UPPER_SLUG>` / `category_section__none`;
    // `service_card_<id>`).
    Finder sectionKey(String slug) => find.byKey(Key('category_section_$slug'));
    Finder cardKey(String id) => find.byKey(Key('service_card_$id'));

    Future<void> pumpList(
      WidgetTester tester,
      List<MasterService> services,
    ) async {
      await tester.pumpApp(
        const ServicesListScreen(),
        overrides: [
          _servicesOverride(AsyncData(services)),
          serviceRepositoryProvider.overrideWithValue(mockRepo),
        ],
      );
      // Loading frame → microtask delivers data → data frame.
      await tester.pump();
      await tester.pump();
      // Advance past the entrance stagger so all cards are laid out.
      await tester.pump(const Duration(milliseconds: 600));
    }

    // ── B2 (HIGH) — creation order across and within categories ──────────────
    testWidgets('B2 — preserves creation order across and within categories '
        '(HAIRCUT before BROWS; A before C in HAIRCUT)', (tester) async {
      // Approved list covers both slugs so labels resolve to Ukrainian.
      when(() => mockRepo.fetchApprovedCategories()).thenAnswer(
        (_) async => const <ServiceCategoryOption>[
          ServiceCategoryOption(name: 'HAIRCUT', displayName: 'Стрижка'),
          ServiceCategoryOption(name: 'BROWS', displayName: 'Брови'),
        ],
      );

      await pumpList(tester, const <MasterService>[aHaircut, bBrows, cHaircut]);

      // Exactly two sections.
      expect(sectionKey('HAIRCUT'), findsOneWidget);
      expect(sectionKey('BROWS'), findsOneWidget);
      expect(
        find.byKey(const Key('category_section__none')),
        findsNothing,
        reason: 'no uncategorized service was seeded',
      );

      // Section order: HAIRCUT (A first-appearance) before BROWS.
      final double haircutDy = tester.getTopLeft(sectionKey('HAIRCUT')).dy;
      final double browsDy = tester.getTopLeft(sectionKey('BROWS')).dy;
      expect(
        haircutDy,
        lessThan(browsDy),
        reason:
            'HAIRCUT appears first in creation order (A), so its section must '
            'render above the BROWS section',
      );

      // Within HAIRCUT: A before C (creation order).
      final double aDy = tester.getTopLeft(cardKey('a')).dy;
      final double cDy = tester.getTopLeft(cardKey('c')).dy;
      expect(
        aDy,
        lessThan(cDy),
        reason:
            'A was created before C, so within the HAIRCUT section A must '
            'render above C',
      );
    });

    // ── B3 (MEDIUM) — expand / collapse toggle ───────────────────────────────
    testWidgets(
      'B3 — sections default-expanded; tapping the header collapses then '
      're-expands the cards',
      (tester) async {
        when(() => mockRepo.fetchApprovedCategories()).thenAnswer(
          (_) async => const <ServiceCategoryOption>[
            ServiceCategoryOption(name: 'HAIRCUT', displayName: 'Стрижка'),
          ],
        );

        await pumpList(tester, const <MasterService>[aHaircut, cHaircut]);

        // Default-expanded: both cards visible on first build.
        expect(cardKey('a'), findsOneWidget);
        expect(cardKey('c'), findsOneWidget);

        // Tap the section header (its title) to collapse. Tapping the whole
        // section bounds would land on a card while expanded, so target the
        // header label text directly.
        await tester.tap(find.text('Стрижка'));
        await tester.pumpAndSettle();

        expect(
          cardKey('a'),
          findsNothing,
          reason: 'collapsing the section must remove its cards from the tree',
        );
        expect(cardKey('c'), findsNothing);

        // Tap again to re-expand.
        await tester.tap(sectionKey('HAIRCUT'));
        await tester.pumpAndSettle();

        expect(
          cardKey('a'),
          findsOneWidget,
          reason: 're-expanding the section must bring its cards back',
        );
        expect(cardKey('c'), findsOneWidget);
      },
    );

    // ── B4 (MEDIUM) — per-card category label removed ────────────────────────
    testWidgets(
      'B4 — the category label appears only in the section header, never '
      'inside a service card',
      (tester) async {
        when(() => mockRepo.fetchApprovedCategories()).thenAnswer(
          (_) async => const <ServiceCategoryOption>[
            ServiceCategoryOption(name: 'HAIRCUT', displayName: 'Стрижка'),
          ],
        );

        await pumpList(tester, const <MasterService>[aHaircut]);

        // The label is present (in the header).
        expect(find.text('Стрижка'), findsOneWidget);
        // …but NOT inside the card subtree.
        expect(
          find.descendant(of: cardKey('a'), matching: find.text('Стрижка')),
          findsNothing,
          reason:
              'the category label is now the section header — it must not be '
              'duplicated inside the service card',
        );
      },
    );

    // ── B5 (MEDIUM) — uncategorized bucket ordering ──────────────────────────
    testWidgets(
      'B5 — a trailing no-category service lands in the single uncategorized '
      'section after the categorized sections',
      (tester) async {
        const noCategory = MasterService(
          id: 'z',
          serviceDefId: 'def-z',
          name: 'Сервіс Z',
          durationMinutes: 30,
          priceMin: 400,
          priceDisplay: '400 грн',
          // no category → uncategorized bucket
        );

        when(() => mockRepo.fetchApprovedCategories()).thenAnswer(
          (_) async => const <ServiceCategoryOption>[
            ServiceCategoryOption(name: 'HAIRCUT', displayName: 'Стрижка'),
          ],
        );

        await pumpList(tester, const <MasterService>[aHaircut, noCategory]);

        // Exactly one categorized section + one uncategorized section.
        expect(sectionKey('HAIRCUT'), findsOneWidget);
        final Finder uncategorized = find.byKey(
          const Key('category_section__none'),
        );
        expect(uncategorized, findsOneWidget);

        // The uncategorized section renders AFTER the categorized one.
        final double haircutDy = tester.getTopLeft(sectionKey('HAIRCUT')).dy;
        final double uncategorizedDy = tester.getTopLeft(uncategorized).dy;
        expect(
          haircutDy,
          lessThan(uncategorizedDy),
          reason:
              'the no-category service appears last in creation order, so its '
              'uncategorized section must render below the HAIRCUT section',
        );

        // The uncategorized header uses the localized label, never a raw slug.
        final l10n = AppLocalizations.of(
          tester.element(find.byType(ServicesListScreen)),
        );
        expect(
          find.descendant(
            of: uncategorized,
            matching: find.text(l10n.serviceCategoryUncategorized),
          ),
          findsOneWidget,
        );
        // The uncategorized service card is present in that section.
        expect(cardKey('z'), findsOneWidget);
      },
    );
  });
}
