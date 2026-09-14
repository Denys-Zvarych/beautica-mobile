// Phase 5.2 — Widget tests for ServicesListScreen.
//
// [ServicesListScreen] is a [ConsumerStatefulWidget]. The [ScreenProtector]
// lifecycle calls (the app-switcher blur — `preventScreenshotOn/Off` is no
// longer called anywhere, product decision 2026-08-20, see the header of
// `lib/core/security/screen_protection.dart`) are guarded by !kDebugMode, so
// they are never invoked during test runs and do not require mocking.
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
import 'package:beautica_mobile/features/services/presentation/widgets/service_category_list.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../integration_test/support/app_harness.dart';
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
  priceDisplay: '750 ₴',
);

const _stubServiceList = <MasterService>[_stubService];

/// Laid-out width of a [ServiceInfo] name column on [ServicesListScreen] at a
/// pinned 360 dp phone width — the END-TO-END half of Phase 323's "+66 dp"
/// claim (see the geometry group at the bottom of this file).
///
/// Derivation, so a future reader can tell a legitimate design change from a
/// regression rather than just re-blessing whatever the tree now draws:
///   360      viewport
///   -32      the cards ListView's `VelvetSpacing.lg` insets (16 each side)
///   -16      [CategorySection]'s own `VelvetSpacing.sm` insets (8 each side)
///   ----
///   312      the card's own laid-out width
///   -16      the card's `VelvetSpacing.sm` insets (8 each side)
///    -4      `VelvetSpacing.xs` gap before the trailing affordance
///   -22      `_kEditAffordanceSize` edit pillow / blank slot
///   ----
///   270
/// The pre-Phase-323 tree spent a further 50 (photo well + its 10 dp gap),
/// 4 (10 dp card insets), 4 (8 dp trailing gap) and 8 (30 dp pillow) = 66 dp
/// of that, leaving a 204 dp name column on the same phone.
const double _kNameColumnWidthAt360 = 270.0;

/// Geometry fixture for the Phase 323 group — identical to [_stubService]
/// except that it carries a category, so the screen can be mounted with
/// `initialExpandCategory: 'HAIRCUT'` and the card is laid out WITHOUT a tap.
///
/// The name is deliberately long enough to fill the column: a short name would
/// leave the [ServiceInfo] column's own width unconstrained-looking and the
/// reclaim assertions would read the same number whether the trims landed or
/// not (`project_fixture_values_can_defang_assertions`).
const _geomService = MasterService(
  id: 'svc-001',
  serviceDefId: 'def-001',
  name: 'Складне фарбування довгого волосся з доглядом',
  category: 'HAIRCUT',
  durationMinutes: 45,
  priceMin: 750,
  priceDisplay: '750 ₴',
);

/// The default approved-category list. approvedCategoriesProvider now fetches
/// DIRECTLY (not through the repository), so it must be overridden in-scope;
/// _LoadedBody watches it to resolve category labels. This mirrors the list the
/// pre-migration `fetchApprovedCategories` stub returned in setUp.
const _defaultCategories = <ServiceCategoryOption>[
  ServiceCategoryOption(name: 'HAIRCUT', displayName: 'Стрижка'),
];

/// Builds the [approvedCategoriesProvider] override for [categories]. Pass each
/// test's specific category list; defaults to [_defaultCategories].
Object _categoriesOverride([
  List<ServiceCategoryOption> categories = _defaultCategories,
]) => approvedCategoriesProvider.overrideWith((ref) async => categories);

/// Minimal [MasterService] factory for generating lists of arbitrary length.
/// Only the required fields are set; freezed defaults cover the rest.
MasterService _makeService(int i) => MasterService(
  id: 'svc-$i',
  serviceDefId: 'def-$i',
  name: 'Test $i',
  durationMinutes: 30,
  priceMin: 100,
  priceDisplay: '100 ₴',
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

/// A repo-backed stub [ServicesList] that drives BOTH the initial load and the
/// retry / pull-to-refresh re-fetch off [ServiceRepository.listMyServices].
///
/// Why this exists instead of the real notifier: Riverpod surfaces an initial
/// `build()` failure as an [AsyncError] that STILL carries `isLoading: true`
/// (the seamless-loading flag). The screen renders its error branch via a plain
/// `AsyncValue.when`, which treats `isLoading: true` as the loading branch — so
/// the real notifier never paints the error UI on a first-load failure. This
/// stub posts PURE states (no retained loading flag), matching how the existing
/// [_StubServicesList] drives the screen, so the error branch renders exactly
/// as it does for a real reload failure.
///
///   • [build] awaits `listMyServices()`; success → pure [AsyncData],
///     failure → pure [AsyncError]. The production retry callback
///     (`ref.invalidate(servicesListProvider)`) re-creates this stub →
///     `build()` re-runs → the next `listMyServices()` answer is applied.
///   • [refresh] mirrors the real notifier's contract (used by the
///     [RefreshIndicator]) but posts a pure result state.
class _RepoBackedServicesList extends ServicesList {
  @override
  Future<List<MasterService>> build() {
    final repo = ref.watch(serviceRepositoryProvider);
    Future<void>.microtask(() async {
      try {
        state = AsyncData(await repo.listMyServices());
      } catch (e, st) {
        state = AsyncError(e, st);
      }
    });
    // Never-completing future — state is posted above as a pure value.
    return Completer<List<MasterService>>().future;
  }

  @override
  Future<void> refresh() async {
    try {
      state = AsyncData(
        await ref.read(serviceRepositoryProvider).listMyServices(),
      );
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

/// Returns a [ProviderScope] override that replaces [servicesListProvider]
/// with a stub notifier resolving to [target].
Object _servicesOverride(AsyncValue<List<MasterService>> target) =>
    servicesListProvider.overrideWith(() => _StubServicesList(target));

/// Returns a [ProviderScope] override that replaces [servicesListProvider]
/// with the repo-backed stub used by the retry + pull-to-refresh tests.
Object _repoBackedOverride() =>
    servicesListProvider.overrideWith(() => _RepoBackedServicesList());

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
    // _LoadedBody watches approvedCategoriesProvider to resolve category labels
    // (FIX 4). That provider now fetches DIRECTLY (not through the repository),
    // so it is overridden per-test via _categoriesOverride(...) rather than
    // stubbed here. Tests that need specific labels pass their own list.
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
        _categoriesOverride(),
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
          _categoriesOverride(),
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
        _categoriesOverride(),
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
        _categoriesOverride(),
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
          _categoriesOverride(),
        ],
      );
      // Loading frame → microtask → data frame.
      await tester.pump();
      await tester.pump();
      // Advance entrance animation so the card becomes visible.
      await tester.pump(const Duration(milliseconds: 500));

      // _stubService has no category, so it lands in the uncategorized bucket
      // which starts collapsed (new default behaviour). Expand it before
      // asserting on card content.
      await tester.tap(find.byKey(const Key('category_section__none')));
      await tester.pumpAndSettle();

      expect(find.byType(ListView), findsOneWidget);
      expect(find.text('Стрижка'), findsOneWidget);
      // Phase 5.6: price rendered from priceDisplay (server-formatted).
      expect(find.text('750 ₴'), findsOneWidget);
      expect(find.text('45 хв'), findsOneWidget);
    },
  );

  // ── 4b. No draft affordance on the populated card (V80 removal guard) ──────
  //
  // Backend V80 removed the service draft flag; the mobile draft affordance —
  // the draft badge, the "set price" CTA, and the draft card variant — were all
  // deleted (user-approved). The dedicated `services_list_draft_card_test.dart`
  // was removed with them and must NOT be recreated. This test is the widget
  // half of the regression guard: a normal active service renders ONLY the
  // plain duration·price meta line with no draft badge and no set-price CTA.
  //
  // Re-introducing a draft badge/CTA (keyed `service_draft_badge_*` /
  // `btn-set-price-*`, the keys the deleted UI used) would make one of the
  // findsNothing assertions fail here, blocking the regression before it could
  // reach a broken APK build. Finders are keyed/structural (M2/M11) — none of
  // the removed `servicesDraft*` localized strings are referenced.

  testWidgets(
    'populated card shows the plain duration·price meta only — no draft badge, '
    'no set-price CTA',
    (tester) async {
      await tester.pumpApp(
        const ServicesListScreen(),
        overrides: [
          _servicesOverride(const AsyncData(_stubServiceList)),
          serviceRepositoryProvider.overrideWithValue(mockRepo),
          _categoriesOverride(),
        ],
      );
      // Loading frame → microtask → data frame → entrance animation.
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // _stubService has no category → uncategorized bucket starts collapsed.
      await tester.tap(find.byKey(const Key('category_section__none')));
      await tester.pumpAndSettle();

      // The card and its plain duration·price meta line are present.
      expect(find.byKey(const Key('service_card_svc-001')), findsOneWidget);
      expect(find.text('750 ₴'), findsOneWidget);
      expect(find.text('45 хв'), findsOneWidget);

      // No draft affordance — the badge and the set-price CTA the deleted draft
      // UI rendered are absent. Keyed structural finders, matched against the
      // card subtree so an unrelated future key collision can't mask a miss.
      final cardFinder = find.byKey(const Key('service_card_svc-001'));
      expect(
        find.descendant(
          of: cardFinder,
          matching: find.byKey(const Key('service_draft_badge_svc-001')),
        ),
        findsNothing,
        reason: 'V80 removed drafts — no draft badge may render on a card',
      );
      expect(
        find.descendant(
          of: cardFinder,
          matching: find.byKey(const Key('btn-set-price-svc-001')),
        ),
        findsNothing,
        reason: 'V80 removed drafts — no "set price" CTA may render on a card',
      );
      // Belt-and-braces: no draft-keyed widget of any id leaked into the tree.
      expect(
        find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key as ValueKey<String>).value.toLowerCase().contains('draft'),
        ),
        findsNothing,
        reason: 'no draft-keyed widget may exist anywhere in the list',
      );
    },
  );

  // ── 5. FAB present in populated state ─────────────────────────────────────

  testWidgets('populated state — FAB btn-create-service found', (tester) async {
    await tester.pumpApp(
      const ServicesListScreen(),
      overrides: [
        _servicesOverride(const AsyncData(_stubServiceList)),
        serviceRepositoryProvider.overrideWithValue(mockRepo),
        _categoriesOverride(),
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
        _categoriesOverride(),
      ],
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // _stubService has no category → uncategorized bucket starts collapsed.
    // Expand the section before tapping the card.
    await tester.tap(find.byKey(const Key('category_section__none')));
    await tester.pumpAndSettle();

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

  // ── 6b. Phase 317 D3 — the two additive, nullable destination parameters ───
  //
  // `null` must mean exactly what the screen did before phase 317, so every
  // caller shipped today renders and navigates identically. Both halves are
  // here on purpose: the OMITTED case is the "nothing changed" proof (and the
  // one most likely to be vacuous if skipped), the SUPPLIED case is the proof
  // the parameters are actually threaded rather than accepted and ignored.
  //
  // Destinations are asserted by the PAGE that builds, never by a location
  // string — go_router's literal-before-dynamic shadowing makes a string
  // assertion pass while a different page mounts
  // (`project_gorouter_literal_before_dynamic_shadowing`).

  group('Phase 317 D3 — setupRoute / editRouteBuilder', () {
    const String kSalonId = 'salon-S';
    const String kMemberId = 'user-U';

    String salonSetup() =>
        RouteNames.salonManageStaffServiceSetup(kSalonId, kMemberId);
    String salonEdit(String id) =>
        RouteNames.salonManageStaffServiceEdit(kSalonId, kMemberId, id);

    /// A router carrying BOTH destination families, each landing on a
    /// DISTINCTLY LABELLED dummy page, so "which page mounted" answers "which
    /// destination was pushed".
    GoRouter routerFor(ServicesListScreen screen) => GoRouter(
      initialLocation: RouteNames.services,
      routes: <RouteBase>[
        GoRoute(path: RouteNames.services, builder: (_, _) => screen),
        GoRoute(
          path: RouteNames.serviceSetup,
          builder: (_, _) => const _DummyPage(label: 'own-setup'),
        ),
        GoRoute(
          path: '/services/:id/edit',
          builder: (_, _) => const _DummyPage(label: 'own-edit'),
        ),
        GoRoute(
          path: '/salons/:salonId/manage/staff/:memberId/services/setup',
          builder: (_, _) => const _DummyPage(label: 'salon-setup'),
        ),
        GoRoute(
          path:
              '/salons/:salonId/manage/staff/:memberId/services'
              '/:serviceId/edit',
          builder: (_, _) => const _DummyPage(label: 'salon-edit'),
        ),
      ],
    );

    Future<void> pumpWith(
      WidgetTester tester,
      ServicesListScreen screen, {
      required AsyncValue<List<MasterService>> services,
    }) async {
      await tester.pumpRoutedApp(
        routerFor(screen),
        overrides: [
          _servicesOverride(services),
          serviceRepositoryProvider.overrideWithValue(mockRepo),
          _categoriesOverride(),
        ],
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
    }

    /// Taps the extended FAB. `_NeumorphicExtendedFab` wraps an
    /// `AnimatedScale` (0.97 on press), so a tap addressed at the keyed root
    /// can miss its hit box mid-animation. The remedy is a better finder — the
    /// `GestureDetector` that actually receives the pointer — never
    /// `warnIfMissed: false` (`project_animatedscale_root_breaks_tap_by_key`).
    Future<void> tapFab(WidgetTester tester) async {
      final Finder fab = find.byKey(const Key('btn-create-service'));
      expect(fab, findsOneWidget);
      await tester.tap(
        find.descendant(of: fab, matching: find.byType(GestureDetector)).first,
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'OMITTED — the FAB pushes RouteNames.serviceSetup (own), unchanged',
      (tester) async {
        await pumpWith(
          tester,
          const ServicesListScreen(),
          services: const AsyncData(_stubServiceList),
        );

        await tapFab(tester);

        expect(find.text('Dummy own-setup'), findsOneWidget);
        expect(find.text('Dummy salon-setup'), findsNothing);
      },
    );

    testWidgets(
      'OMITTED — the EMPTY-STATE CTA pushes RouteNames.serviceSetup (own), '
      'unchanged',
      (tester) async {
        await pumpWith(
          tester,
          const ServicesListScreen(),
          services: const AsyncData(<MasterService>[]),
        );

        await tester.tap(find.byKey(const Key('btn-create-service-empty')));
        await tester.pumpAndSettle();

        expect(find.text('Dummy own-setup'), findsOneWidget);
        expect(find.text('Dummy salon-setup'), findsNothing);
      },
    );

    testWidgets(
      "OMITTED — a card's onEdit pushes RouteNames.serviceEdit (own), "
      'unchanged',
      (tester) async {
        await pumpWith(
          tester,
          const ServicesListScreen(),
          services: const AsyncData(_stubServiceList),
        );

        await tester.tap(find.byKey(const Key('category_section__none')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('service_card_svc-001')));
        await tester.pumpAndSettle();

        expect(find.text('Dummy own-edit'), findsOneWidget);
        expect(find.text('Dummy salon-edit'), findsNothing);
      },
    );

    testWidgets('SUPPLIED — the FAB pushes the SALON setup leaf', (
      tester,
    ) async {
      await pumpWith(
        tester,
        ServicesListScreen(
          setupRoute: salonSetup(),
          editRouteBuilder: salonEdit,
        ),
        services: const AsyncData(_stubServiceList),
      );

      await tapFab(tester);

      expect(find.text('Dummy salon-setup'), findsOneWidget);
      expect(find.text('Dummy own-setup'), findsNothing);
    });

    testWidgets('SUPPLIED — the EMPTY-STATE CTA pushes the SALON setup leaf', (
      tester,
    ) async {
      await pumpWith(
        tester,
        ServicesListScreen(
          setupRoute: salonSetup(),
          editRouteBuilder: salonEdit,
        ),
        services: const AsyncData(<MasterService>[]),
      );

      await tester.tap(find.byKey(const Key('btn-create-service-empty')));
      await tester.pumpAndSettle();

      expect(find.text('Dummy salon-setup'), findsOneWidget);
      expect(find.text('Dummy own-setup'), findsNothing);
    });

    testWidgets("SUPPLIED — a card's onEdit pushes the SALON edit leaf", (
      tester,
    ) async {
      await pumpWith(
        tester,
        ServicesListScreen(
          setupRoute: salonSetup(),
          editRouteBuilder: salonEdit,
        ),
        services: const AsyncData(_stubServiceList),
      );

      await tester.tap(find.byKey(const Key('category_section__none')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('service_card_svc-001')));
      await tester.pumpAndSettle();

      expect(find.text('Dummy salon-edit'), findsOneWidget);
      expect(find.text('Dummy own-edit'), findsNothing);
    });
  });

  // ── 6c. Phase 320 — writable flag ───────────────────────────────────────────
  //
  // D1: additive, defaults to `true`. The "omitted" proof already exists —
  // every OTHER test in this file mounts `ServicesListScreen()` without ever
  // passing `writable` and still sees the FAB (test 5), the empty-state CTA
  // (test 3) and a navigating card (test 6). Flipping the default to `false`
  // (mutation check 1) breaks all three, which is exactly the regression this
  // phase's own default must never reintroduce. This group covers ONLY the
  // `writable: false` half: affordances 1-3 absent, the services themselves
  // still rendered.

  group('Phase 320 — writable: false removes write affordances only', () {
    testWidgets(
      'non-empty list — FAB absent, the card and its section still render, '
      'but tapping the card navigates nowhere',
      (tester) async {
        final GoRouter router = GoRouter(
          initialLocation: RouteNames.services,
          routes: <RouteBase>[
            GoRoute(
              path: RouteNames.services,
              builder: (context, state) =>
                  const ServicesListScreen(writable: false),
            ),
            GoRoute(
              path: '/services/create',
              builder: (context, state) => const _DummyPage(label: 'create'),
            ),
            GoRoute(
              path: '/services/:id/edit',
              builder: (context, state) => const _DummyPage(label: 'edit'),
            ),
          ],
        );

        await tester.pumpRoutedApp(
          router,
          overrides: [
            _servicesOverride(const AsyncData(_stubServiceList)),
            serviceRepositoryProvider.overrideWithValue(mockRepo),
            _categoriesOverride(),
          ],
        );
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        // Affordance 1 — hidden, not disabled.
        expect(find.byKey(const Key('btn-create-service')), findsNothing);

        // The services themselves still render — a read-only viewer sees
        // their catalogue. _stubService has no category, so it lands in the
        // uncategorized bucket (starts collapsed); expand it before
        // asserting on card content.
        expect(find.byKey(const Key('category_section__none')), findsOneWidget);
        await tester.tap(find.byKey(const Key('category_section__none')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('service_card_svc-001')), findsOneWidget);
        expect(find.text('Стрижка'), findsOneWidget);
        expect(find.text('750 ₴'), findsOneWidget);
        expect(find.text('45 хв'), findsOneWidget);

        // Affordance 3, structural half: the card carries NO GestureDetector
        // at all — "not tappable", never "tappable, does nothing" (D3). A
        // behavioural-only "no navigation" check below cannot distinguish a
        // genuinely non-tappable card from one wired to a no-op callback
        // (mutation check 3 proved this: swapping the screen's `null` for
        // `() {}` left the navigation assertion green).
        final Finder cardFinder = find.byKey(const Key('service_card_svc-001'));
        expect(
          find.descendant(
            of: cardFinder,
            matching: find.byType(GestureDetector),
          ),
          findsNothing,
          reason:
              'writable: false must pass a null onEdit, not a no-op '
              'callback — a GestureDetector here means the card is still '
              '"tappable, does nothing"',
        );

        // Affordance 3, behavioural half — tapping the card performs NO
        // navigation. Pin the resolved location before and after via the
        // push-safe helper
        // (`forbid_naive_router_location.sh` — a direct `.uri`/`.fullPath`
        // read keeps reporting the PRE-push location forever for an
        // ImperativeRouteMatch, so it would vacuously "pass" even if a push
        // DID happen), not merely the absence of an exception
        // (project_gorouter_imperative_match_fullpath).
        final String before = AppHarness.location(router);
        await tester.tap(find.byKey(const Key('service_card_svc-001')));
        await tester.pumpAndSettle();
        final String after = AppHarness.location(router);
        expect(after, before, reason: 'a read-only card tap must not push');
        expect(find.text('Dummy edit'), findsNothing);
      },
    );

    testWidgets(
      'empty list — empty-state copy still renders, only the CTA is absent',
      (tester) async {
        await tester.pumpApp(
          const ServicesListScreen(writable: false),
          overrides: [
            _servicesOverride(const AsyncData(<MasterService>[])),
            serviceRepositoryProvider.overrideWithValue(mockRepo),
            _categoriesOverride(),
          ],
        );
        await tester.pump();
        await tester.pump();

        final l10n = AppLocalizations.of(
          tester.element(find.byType(ServicesListScreen)),
        );
        // Positive half — a `findsNothing`-only test would also pass on a
        // blank screen; prove the copy is actually there.
        expect(find.text(l10n.servicesEmpty), findsOneWidget);
        expect(find.text(l10n.servicesEmptyBody), findsOneWidget);
        // Negative half — affordances 1 and 2, both absent.
        expect(find.byKey(const Key('btn-create-service-empty')), findsNothing);
        expect(find.byKey(const Key('btn-create-service')), findsNothing);
      },
    );
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
          _categoriesOverride(),
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
      priceDisplay: '250 ₴',
      category: 'BROWS',
    );

    testWidgets(
      'approved slug renders Ukrainian displayName (Брови), not raw BROWS',
      (tester) async {
        await tester.pumpApp(
          const ServicesListScreen(),
          overrides: [
            _servicesOverride(const AsyncData(<MasterService>[browsService])),
            serviceRepositoryProvider.overrideWithValue(mockRepo),
            _categoriesOverride(const <ServiceCategoryOption>[
              ServiceCategoryOption(name: 'BROWS', displayName: 'Брови'),
            ]),
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
        await tester.pumpApp(
          const ServicesListScreen(),
          overrides: [
            _servicesOverride(const AsyncData(<MasterService>[browsService])),
            serviceRepositoryProvider.overrideWithValue(mockRepo),
            _categoriesOverride(const <ServiceCategoryOption>[
              ServiceCategoryOption(name: 'HAIRCUT', displayName: 'Стрижка'),
            ]),
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
      priceDisplay: '100 ₴',
      category: 'HAIRCUT',
    );
    const bBrows = MasterService(
      id: 'b',
      serviceDefId: 'def-b',
      name: 'Сервіс B',
      durationMinutes: 30,
      priceMin: 200,
      priceDisplay: '200 ₴',
      category: 'BROWS',
    );
    const cHaircut = MasterService(
      id: 'c',
      serviceDefId: 'def-c',
      name: 'Сервіс C',
      durationMinutes: 30,
      priceMin: 300,
      priceDisplay: '300 ₴',
      category: 'HAIRCUT',
    );

    // Section + card key helpers — mirror the production key format
    // (`category_section_<UPPER_SLUG>` / `category_section__none`;
    // `service_card_<id>`).
    Finder sectionKey(String slug) => find.byKey(Key('category_section_$slug'));
    Finder cardKey(String id) => find.byKey(Key('service_card_$id'));

    Future<void> pumpList(
      WidgetTester tester,
      List<MasterService> services, {
      List<ServiceCategoryOption> categories = _defaultCategories,
    }) async {
      await tester.pumpApp(
        const ServicesListScreen(),
        overrides: [
          _servicesOverride(AsyncData(services)),
          serviceRepositoryProvider.overrideWithValue(mockRepo),
          _categoriesOverride(categories),
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
      await pumpList(
        tester,
        const <MasterService>[aHaircut, bBrows, cHaircut],
        categories: const <ServiceCategoryOption>[
          ServiceCategoryOption(name: 'HAIRCUT', displayName: 'Стрижка'),
          ServiceCategoryOption(name: 'BROWS', displayName: 'Брови'),
        ],
      );

      // Exactly two sections.
      expect(sectionKey('HAIRCUT'), findsOneWidget);
      expect(sectionKey('BROWS'), findsOneWidget);
      expect(
        find.byKey(const Key('category_section__none')),
        findsNothing,
        reason: 'no uncategorized service was seeded',
      );

      // Both sections start collapsed (new default behaviour). Expand them so
      // their cards are laid out and can be measured by getTopLeft.
      await tester.tap(sectionKey('HAIRCUT'));
      await tester.pumpAndSettle();
      await tester.tap(sectionKey('BROWS'));
      await tester.pumpAndSettle();

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
    //
    // Regression: sections used to default-expanded when no initialExpandCategory
    // was set. The UX fix changed the default to COLLAPSED so the list opens
    // without any section contents visible. This test verifies the new default
    // and confirms the toggle still works in both directions.
    testWidgets(
      'B3 — sections default-collapsed; tapping the header expands then '
      're-collapses the cards',
      (tester) async {
        await pumpList(tester, const <MasterService>[aHaircut, cHaircut]);

        // Default-collapsed: neither card is visible on first build.
        expect(
          cardKey('a'),
          findsNothing,
          reason:
              'sections start collapsed when no initialExpandCategory is set '
              '(UX fix — was default-expanded)',
        );
        expect(cardKey('c'), findsNothing);

        // Tap the section header to expand. When the section is collapsed its
        // cards are absent, so sectionKey() reliably targets the header area.
        await tester.tap(sectionKey('HAIRCUT'));
        await tester.pumpAndSettle();

        expect(
          cardKey('a'),
          findsOneWidget,
          reason: 'tapping the header must reveal its cards',
        );
        expect(cardKey('c'), findsOneWidget);

        // Tap again to collapse. When expanded the section key's rect spans
        // the header + all visible cards, so tapping its center would land on
        // a card. Target the header label text instead — it always maps to the
        // header GestureDetector regardless of expansion state.
        await tester.tap(find.text('Стрижка'));
        await tester.pumpAndSettle();

        expect(
          cardKey('a'),
          findsNothing,
          reason: 'tapping the header label again must collapse the section',
        );
        expect(cardKey('c'), findsNothing);
      },
    );

    // ── B4 (MEDIUM) — per-card category label removed ────────────────────────
    testWidgets(
      'B4 — the category label appears only in the section header, never '
      'inside a service card',
      (tester) async {
        await pumpList(tester, const <MasterService>[aHaircut]);

        // The section header is present even when the section is collapsed.
        expect(find.text('Стрижка'), findsOneWidget);

        // Expand the section so the card is in the tree; then assert the label
        // lives only in the header and is NOT duplicated inside the card.
        await tester.tap(sectionKey('HAIRCUT'));
        await tester.pumpAndSettle();

        expect(
          cardKey('a'),
          findsOneWidget,
          reason: 'card must be in the tree after expanding the section',
        );
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
          priceDisplay: '400 ₴',
          // no category → uncategorized bucket
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

        // Expand the uncategorized section so its card enters the tree, then
        // verify the card is present. The section starts collapsed (new default
        // behaviour: null initialExpandCategory → all sections collapsed).
        await tester.tap(uncategorized);
        await tester.pumpAndSettle();

        // The uncategorized service card is present in that section.
        expect(cardKey('z'), findsOneWidget);
      },
    );
  });

  // ── REGRESSION: collapsed-by-default behaviour (UX fix guard) ──────────────
  //
  // These two tests exist solely to guard the UX fix that changed the default
  // initiallyExpanded value from true to false when no initialExpandCategory is
  // provided. They MUST fail against the pre-fix code (where all sections started
  // expanded and service cards were immediately visible). A green run here proves
  // the new collapsed-by-default behaviour is in place.

  group('REGRESSION — collapsed-by-default (null initialExpandCategory)', () {
    // Shared services covering two categories so both code paths are exercised.
    const hairService = MasterService(
      id: 'reg-hair',
      serviceDefId: 'def-reg-hair',
      name: 'Регресія A',
      durationMinutes: 20,
      priceMin: 150,
      priceDisplay: '150 ₴',
      category: 'HAIR',
    );
    const bodyService = MasterService(
      id: 'reg-body',
      serviceDefId: 'def-reg-body',
      name: 'Регресія B',
      durationMinutes: 20,
      priceMin: 200,
      priceDisplay: '200 ₴',
      category: 'BODY',
    );

    // ── REGRESSION-1 ─────────────────────────────────────────────────────────
    //
    // Precondition: ServicesListScreen with null initialExpandCategory (the
    // default — bottom-nav "Послуги" tab, or "Усі послуги" link).
    //
    // Expected (post-fix):  NO service-card keys are present in the widget tree
    //                        immediately after the data frame. All sections are
    //                        collapsed; their children are not built.
    //
    // Pre-fix behaviour: cards were immediately visible because initiallyExpanded
    //                    was `targetSlug == null || group.key == targetSlug`,
    //                    which always evaluated true when targetSlug was null.
    //
    // This test WOULD FAIL against the pre-fix code: both service_card_reg-hair
    // and service_card_reg-body would have been found by the find.byKey finders,
    // and the findsNothing assertions would have thrown.
    testWidgets('REGRESSION-1: null initialExpandCategory — all sections collapsed; '
        'no service-card keys present in the widget tree', (tester) async {
      // ServicesListScreen with the default null initialExpandCategory.
      await tester.pumpApp(
        const ServicesListScreen(),
        overrides: [
          _servicesOverride(
            const AsyncData(<MasterService>[hairService, bodyService]),
          ),
          serviceRepositoryProvider.overrideWithValue(mockRepo),
          _categoriesOverride(const <ServiceCategoryOption>[
            ServiceCategoryOption(name: 'HAIR', displayName: 'Волосся'),
            ServiceCategoryOption(name: 'BODY', displayName: 'Тіло'),
          ]),
        ],
      );
      // Loading frame → microtask delivers data → data frame.
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      // Section HEADERS must be present (collapsed state still renders headers).
      expect(
        find.byKey(const Key('category_section_HAIR')),
        findsOneWidget,
        reason: 'section headers are rendered even when collapsed',
      );
      expect(
        find.byKey(const Key('category_section_BODY')),
        findsOneWidget,
        reason: 'section headers are rendered even when collapsed',
      );

      // Service CARDS must NOT be in the tree — the sections are collapsed.
      // Pre-fix: these findsNothing assertions would have failed because the
      // old initiallyExpanded logic evaluated to true when targetSlug was null.
      expect(
        find.byKey(const Key('service_card_reg-hair')),
        findsNothing,
        reason:
            'HAIR section starts collapsed — its card must not be in the tree',
      );
      expect(
        find.byKey(const Key('service_card_reg-body')),
        findsNothing,
        reason:
            'BODY section starts collapsed — its card must not be in the tree',
      );
    });

    // ── REGRESSION-2 ─────────────────────────────────────────────────────────
    //
    // Precondition: ServicesListScreen with a specific initialExpandCategory
    //               ('HAIR') — the targeted-category-card navigation path.
    //
    // Expected (post-fix):  HAIR section is expanded (card visible); BODY section
    //                        is collapsed (card absent). This path is unchanged by
    //                        the fix; this test confirms no regression there.
    //
    // Pre-fix behaviour was identical for this specific path (targetSlug != null
    // matched the specific section) so the targeted-expand logic was never broken.
    //
    // This test confirms the targeted path is unchanged and also rules out an
    // accidental regression where both sections start collapsed even when a slug
    // is provided.
    testWidgets(
      'REGRESSION-2: specific initialExpandCategory="HAIR" — only HAIR expanded; '
      'BODY section remains collapsed',
      (tester) async {
        await tester.pumpApp(
          const ServicesListScreen(initialExpandCategory: 'HAIR'),
          overrides: [
            _servicesOverride(
              const AsyncData(<MasterService>[hairService, bodyService]),
            ),
            serviceRepositoryProvider.overrideWithValue(mockRepo),
            _categoriesOverride(const <ServiceCategoryOption>[
              ServiceCategoryOption(name: 'HAIR', displayName: 'Волосся'),
              ServiceCategoryOption(name: 'BODY', displayName: 'Тіло'),
            ]),
          ],
        );
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        // HAIR section was requested → must be expanded; card in the tree.
        expect(
          find.byKey(const Key('service_card_reg-hair')),
          findsOneWidget,
          reason:
              'HAIR was explicitly requested — its section must start expanded',
        );

        // BODY section was NOT requested → must remain collapsed; card absent.
        expect(
          find.byKey(const Key('service_card_reg-body')),
          findsNothing,
          reason:
              'BODY was not requested — its section must stay collapsed when a '
              'different category was explicitly targeted',
        );
      },
    );
  });

  // ── 8. Error-state retry interaction (mobile-qa M3 / LOW) ──────────────────
  //
  // The error-state test above only asserts the retry button is PRESENT. These
  // tests close the interaction gap: tapping the retry affordance must
  // re-trigger the load and surface the now-succeeding data.
  //
  // Strategy: drive the REAL [ServicesList] notifier (no stub override) off the
  // mocked repository. The production retry callback is
  // `ref.invalidate(servicesListProvider)`, which re-runs `build()` →
  // `listMyServices()`. By stubbing the repo to throw on the first call and
  // succeed on the second, a single retry tap must flip error → data.

  group('error-state retry', () {
    testWidgets(
      'tapping retry re-fetches and renders the list after the load succeeds',
      (tester) async {
        // First listMyServices() throws (error frame); the second returns data.
        var calls = 0;
        when(() => mockRepo.listMyServices()).thenAnswer((_) async {
          calls++;
          if (calls == 1) throw const NetworkFailure();
          return _stubServiceList;
        });

        // Repo-backed stub so the production retry callback
        // (ref.invalidate(servicesListProvider)) re-runs build() →
        // listMyServices() and the error → data transition is real.
        await tester.pumpApp(
          const ServicesListScreen(),
          overrides: [
            _repoBackedOverride(),
            serviceRepositoryProvider.overrideWithValue(mockRepo),
            _categoriesOverride(),
          ],
        );
        // Loading frame → microtask delivers the pure error state.
        await tester.pump();
        await tester.pump();

        // Error state with the retry button is shown after the first failure.
        expect(find.byKey(const Key('services_error_state')), findsOneWidget);
        final retryButton = find.byKey(const Key('error_state_retry_button'));
        expect(retryButton, findsOneWidget);
        expect(calls, 1, reason: 'only the initial failing fetch has run');

        // Tap retry → ref.invalidate(servicesListProvider) → build() re-runs →
        // second (succeeding) listMyServices() call.
        await tester.tap(retryButton);
        await tester.pump();
        await tester.pump();
        // Advance past the card entrance stagger.
        await tester.pump(const Duration(milliseconds: 500));

        // The error state is gone and the list rendered.
        expect(
          find.byKey(const Key('services_error_state')),
          findsNothing,
          reason: 'a successful retry must clear the error state',
        );
        expect(
          calls,
          2,
          reason: 'retry must trigger exactly one additional fetch',
        );

        // _stubService has no category → uncategorized bucket starts collapsed.
        await tester.tap(find.byKey(const Key('category_section__none')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('service_card_svc-001')),
          findsOneWidget,
          reason: 'the re-fetched service card must render after a retry',
        );
        expect(find.text('Стрижка'), findsOneWidget);
      },
    );

    testWidgets(
      'a still-failing retry keeps the error state and retry button visible',
      (tester) async {
        // Every fetch fails — retry must re-attempt but the error state stays.
        var calls = 0;
        when(() => mockRepo.listMyServices()).thenAnswer((_) async {
          calls++;
          throw const NetworkFailure();
        });

        await tester.pumpApp(
          const ServicesListScreen(),
          overrides: [
            _repoBackedOverride(),
            serviceRepositoryProvider.overrideWithValue(mockRepo),
            _categoriesOverride(),
          ],
        );
        await tester.pump();
        await tester.pump();

        expect(find.byKey(const Key('services_error_state')), findsOneWidget);
        expect(calls, 1);

        await tester.tap(find.byKey(const Key('error_state_retry_button')));
        await tester.pump();
        await tester.pump();

        // The retry re-attempted the load (second call) but it failed again, so
        // the error state and its retry affordance remain on screen.
        expect(
          calls,
          2,
          reason: 'retry must re-attempt the fetch even when it fails again',
        );
        expect(
          find.byKey(const Key('services_error_state')),
          findsOneWidget,
          reason: 'a failing retry must keep the error state visible',
        );
        expect(
          find.byKey(const Key('error_state_retry_button')),
          findsOneWidget,
          reason: 'the retry button must remain tappable after a failed retry',
        );
      },
    );
  });

  // ── 9. Pull-to-refresh interaction (mobile-qa M6 / LOW) ────────────────────
  //
  // A downward fling on the [RefreshIndicator] must invoke
  // [ServicesListNotifier.refresh], which re-reads
  // serviceRepositoryProvider.listMyServices(). These tests drive the real
  // notifier so the fling actually exercises refresh() → a second fetch that
  // surfaces fresh data.

  group('pull-to-refresh', () {
    /// Fling the populated list down far enough to arm the [RefreshIndicator],
    /// then settle so refresh() runs to completion.
    Future<void> pullToRefresh(WidgetTester tester) async {
      await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
    }

    testWidgets('a downward fling re-fetches and renders the updated list', (
      tester,
    ) async {
      // First fetch returns one service; the refresh fetch returns a
      // different service so we can prove fresh data was rendered.
      const refreshed = MasterService(
        id: 'svc-002',
        serviceDefId: 'def-002',
        name: 'Манікюр',
        durationMinutes: 60,
        priceMin: 500,
        priceDisplay: '500 ₴',
      );
      var calls = 0;
      when(() => mockRepo.listMyServices()).thenAnswer((_) async {
        calls++;
        return calls == 1 ? _stubServiceList : const <MasterService>[refreshed];
      });

      // Repo-backed stub so the fling drives refresh() → a real second fetch.
      await tester.pumpApp(
        const ServicesListScreen(),
        overrides: [
          _repoBackedOverride(),
          serviceRepositoryProvider.overrideWithValue(mockRepo),
          _categoriesOverride(),
        ],
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Initial data: the first service is present.
      expect(calls, 1, reason: 'only the initial build() fetch has run');
      // Expand the uncategorized section to see the initial card.
      await tester.tap(find.byKey(const Key('category_section__none')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('service_card_svc-001')), findsOneWidget);

      // Pull down to refresh.
      await pullToRefresh(tester);
      await tester.pump(const Duration(milliseconds: 500));

      // refresh() ran exactly one additional fetch.
      expect(
        calls,
        2,
        reason: 'pull-to-refresh must trigger one additional listMyServices()',
      );

      // The fresh list replaced the old one. The uncategorized section stays
      // expanded across the refresh (`_CategorySectionState` is reused under the
      // same key), so the refreshed card is already on-screen — no second tap.
      expect(
        find.byKey(const Key('service_card_svc-002')),
        findsOneWidget,
        reason: 'the refreshed service must render after pull-to-refresh',
      );
      expect(
        find.byKey(const Key('service_card_svc-001')),
        findsNothing,
        reason: 'the stale service must be gone after a successful refresh',
      );
      expect(find.text('Манікюр'), findsOneWidget);
    });

    // N2 (2026-09-10) — the error state's RETRY BUTTON. The group above covers
    // a retry that STILL FAILS (error state stays put), which a retry button
    // that never fetched at all would also satisfy; nothing covered the
    // recovery path, so nothing could tell a working button from a no-op one.
    //
    // `servicesListProvider` is now a view over `masterServiceCatalogProvider`,
    // the app's single GET, so what the button must ultimately do is drop THAT
    // cache. It calls `invalidateMasterServiceCatalogues` for that reason.
    //
    // MUTATION (2026-09-10): reverted `onRetry` to
    // `ref.invalidate(servicesListProvider)` → this test stayed GREEN. Reported
    // rather than hidden: the screen holds a live subscription, so the rebuilt
    // wrapper re-watches the errored upstream and Riverpod re-runs it. The old
    // form was therefore not broken; the helper is used for guard uniformity
    // (see this screen's `onRetry` comment), not to fix a bug. What this test
    // DOES pin is that the button re-fetches and recovers at all — break the
    // fetch and it goes red.
    //
    // `retry: (_, _) => null` disables Riverpod's own failed-build retry, so
    // `calls` counts the button and nothing else — see pump_app.dart's knob.
    testWidgets(
      'the error-state RETRY BUTTON re-fetches and recovers to the list',
      (tester) async {
        var calls = 0;
        when(() => mockRepo.listMyServices()).thenAnswer((_) async {
          calls++;
          if (calls == 1) throw const NetworkFailure();
          return _stubServiceList;
        });

        await tester.pumpApp(
          const ServicesListScreen(),
          retry: (_, _) => null,
          overrides: [
            _repoBackedOverride(),
            serviceRepositoryProvider.overrideWithValue(mockRepo),
            _categoriesOverride(),
          ],
        );
        await tester.pump();
        await tester.pump();

        expect(find.byKey(const Key('services_error_state')), findsOneWidget);
        expect(calls, 1);

        await tester.tap(find.byKey(const Key('error_state_retry_button')));
        await tester.pumpAndSettle();

        expect(
          calls,
          2,
          reason:
              'the retry button must drop the SHARED catalogue cache — '
              'invalidating the wrapper alone re-reads the errored upstream '
              'and never asks the server again',
        );
        expect(
          find.byKey(const Key('services_error_state')),
          findsNothing,
          reason: 'a successful retry must clear the error state',
        );

        await tester.tap(find.byKey(const Key('category_section__none')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('service_card_svc-001')), findsOneWidget);
      },
    );

    testWidgets(
      'pull-to-refresh on the error state re-fetches and recovers to the list',
      (tester) async {
        // First fetch fails (error frame, which is still scrollable via
        // _errorScrollable); the refresh fetch succeeds.
        var calls = 0;
        when(() => mockRepo.listMyServices()).thenAnswer((_) async {
          calls++;
          if (calls == 1) throw const NetworkFailure();
          return _stubServiceList;
        });

        await tester.pumpApp(
          const ServicesListScreen(),
          overrides: [
            _repoBackedOverride(),
            serviceRepositoryProvider.overrideWithValue(mockRepo),
            _categoriesOverride(),
          ],
        );
        await tester.pump();
        await tester.pump();

        // Error state is shown; it is wrapped in a scrollable so the pull
        // gesture is detectable.
        expect(find.byKey(const Key('services_error_state')), findsOneWidget);
        expect(calls, 1);

        // Fling the error scrollable down to refresh.
        await tester.fling(
          find.byKey(const Key('services_error_state')),
          const Offset(0, 400),
          1000,
        );
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 500));

        expect(
          calls,
          2,
          reason: 'pull-to-refresh must re-fetch even from the error state',
        );
        expect(
          find.byKey(const Key('services_error_state')),
          findsNothing,
          reason: 'a successful pull-to-refresh must clear the error state',
        );

        await tester.tap(find.byKey(const Key('category_section__none')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('service_card_svc-001')), findsOneWidget);
      },
    );
  });

  // ── Regression — servicesTitle must stay role-neutral ─────────────────────
  //
  // ServicesListScreen is reused verbatim across three journeys: an
  // INDEPENDENT_MASTER managing their own catalogue (writable: true, the
  // default), a SALON_OWNER/SALON_ADMIN managing a staff master's catalogue
  // (writable: true, different setup/edit targets), and a SALON_MASTER
  // reading their own catalogue (writable: false). A possessive or
  // role-conditional title would be wrong on two of those three journeys.
  //
  // This pins the invariant directly on what RENDERS, not on the l10n getter:
  // `expect(l10n.servicesTitle, 'Послуги')` is self-referential and would
  // stay green even if the value were restored to "Мої послуги" or made
  // role-conditional — this file's ARB history did exactly the former.
  group('Regression — servicesTitle stays role-neutral', () {
    Future<String> pumpAndReadAppBarTitle(
      WidgetTester tester, {
      required bool writable,
      required Locale locale,
    }) async {
      await tester.pumpApp(
        ServicesListScreen(writable: writable),
        overrides: [
          _servicesOverride(const AsyncData(_stubServiceList)),
          serviceRepositoryProvider.overrideWithValue(mockRepo),
          _categoriesOverride(),
        ],
        locale: locale,
      );
      await tester.pump();
      await tester.pump();
      final Text titleText = tester.widget<Text>(
        find.descendant(of: find.byType(AppBar), matching: find.byType(Text)),
      );
      return titleText.data ?? '';
    }

    testWidgets(
      'uk — the writable (independent-master) and read-only (salon-master) '
      'journeys render the identical AppBar title',
      (tester) async {
        final String writableTitle = await pumpAndReadAppBarTitle(
          tester,
          writable: true,
          locale: const Locale('uk'),
        );
        final String readOnlyTitle = await pumpAndReadAppBarTitle(
          tester,
          writable: false,
          locale: const Locale('uk'),
        );

        expect(
          readOnlyTitle,
          writableTitle,
          reason:
              'the title must not vary by role/writable — a role-conditional '
              'title is locked out for this verbatim-reused screen',
        );
      },
    );

    testWidgets('uk — the rendered title carries no possessive marker', (
      tester,
    ) async {
      final String title = await pumpAndReadAppBarTitle(
        tester,
        writable: true,
        locale: const Locale('uk'),
      );

      expect(
        title.toLowerCase(),
        isNot(contains('мої')),
        reason:
            'a possessive title ("Мої послуги") asserts ownership that is '
            'false on the salon-owner/admin and salon-master journeys',
      );
    });

    testWidgets('en — the rendered title carries no possessive marker', (
      tester,
    ) async {
      final String title = await pumpAndReadAppBarTitle(
        tester,
        writable: true,
        locale: const Locale('en'),
      );

      expect(
        RegExp(r'\bmy\b', caseSensitive: false).hasMatch(title),
        isFalse,
        reason:
            'a possessive title ("My Services") asserts ownership that is '
            'false on the salon-owner/admin and salon-master journeys',
      );
    });
  });

  // ── 7. Phase 323 — CARD GEOMETRY ON THE REAL SCREEN ───────────────────────
  //
  // WHY THIS GROUP EXISTS (mobile-qa gap closure, 2026-09-14).
  //
  // Phase 323's headline claim is "+66 dp of text width on the services
  // management page". The change reaches that number through FOUR independent
  // trims, three of which had NO non-golden coverage at any layer:
  //
  //   50 dp  the leading PhotoThumbnail well + its 10 dp gap
  //          (`ServiceCard.showPhoto: false`)                   ← covered, but
  //          only in `service_category_list_test.dart`, on a BARE ServiceCard
  //          the test itself constructs. That case proves the PARAMETER works;
  //          it cannot prove `services_list_screen.dart` actually passes it.
  //    4 dp  horizontal card padding `sm + 2` (10) → `sm` (8), both sides
  //    4 dp  trailing gap `sm` (8) → `xs` (4)
  //    8 dp  the edit affordance 30 → `_kEditAffordanceSize` (22)
  //   ─────
  //   66 dp
  //
  // The last three were pinned by NOTHING but regenerated golden baselines,
  // and a regenerated baseline is self-referential
  // (`feedback_golden_not_acceptance`) — it re-blesses whatever the code now
  // draws. These goldens are weaker still: the test environment has no font,
  // so glyphs render as solid filled blocks and the goldens prove geometry
  // only.
  //
  // So this group asserts the trims from the LAID-OUT RENDER TREE on the real
  // screen, never from widget fields (`project_widget_field_assertion_is_vacuous`
  // — reading `_EditButton`'s `height: 22` would pass even if the Row never
  // laid it out).

  group('Phase 323 — card geometry on the real screen', () {
    /// Pumps the populated screen at a pinned 360 dp phone width, expands the
    /// uncategorized bucket and returns the laid-out card + name-column boxes.
    ///
    /// 360 dp and devicePixelRatio 1.0 make every number below a LOGICAL
    /// pixel count that is reproducible on any host.
    Future<({RenderBox card, RenderBox info})> pumpAndMeasure(
      WidgetTester tester, {
      bool writable = true,
    }) async {
      await tester.pumpApp(
        // `initialExpandCategory` rather than a tap on the section header:
        // the parity case below pumps this helper TWICE in one body, and the
        // outgoing MaterialApp's route transition keeps an `IgnorePointer`
        // over the second tree long enough that a tap misses. Expanding
        // declaratively removes the gesture entirely — never
        // `warnIfMissed: false`
        // (`project_animatedscale_root_breaks_tap_by_key`).
        ServicesListScreen(
          writable: writable,
          initialExpandCategory: 'HAIRCUT',
        ),
        overrides: [
          _servicesOverride(const AsyncData(<MasterService>[_geomService])),
          serviceRepositoryProvider.overrideWithValue(mockRepo),
          _categoriesOverride(),
        ],
        width: 360,
        height: 800,
      );
      await tester.pump();
      await tester.pump();
      // fixed-wait-ok: draining ServiceCard's 460 ms staggered entrance
      // before measuring the laid-out boxes.
      await tester.pump(const Duration(milliseconds: 600));

      final Finder cardFinder = find.byKey(const Key('service_card_svc-001'));
      expect(
        cardFinder,
        findsOneWidget,
        reason:
            'anti-vacuity — nothing below means anything if the card that '
            'is supposed to be measured never rendered',
      );
      return (
        card: tester.renderObject<RenderBox>(cardFinder),
        info: tester.renderObject<RenderBox>(
          find.descendant(of: cardFinder, matching: find.byType(ServiceInfo)),
        ),
      );
    }

    testWidgets(
      'the name column consumes the whole card minus EXACTLY 42 dp of chrome '
      '(8+8 padding, 4 trailing gap, 22 edit affordance) — no photo well',
      (tester) async {
        final boxes = await pumpAndMeasure(tester);

        // The composite pin. Each of Phase 323's four trims moves this number
        // and nothing else on this screen does:
        //   showPhoto back to `true`      → 92, not 42
        //   padding back to `sm + 2` (10) → 46
        //   trailing gap back to `sm` (8) → 46
        //   edit affordance back to 30    → 50
        expect(
          boxes.card.size.width - boxes.info.size.width,
          42.0,
          reason:
              'Phase 323 chrome budget: 8 dp left inset + 8 dp right inset + '
              '4 dp (VelvetSpacing.xs) trailing gap + 22 dp '
              '(_kEditAffordanceSize) edit pillow, and NO 50 dp photo well — '
              'the screen must pass `showPhoto: false`',
        );

        // The absolute half of the claim. Before Phase 323 this screen gave a
        // 360 dp phone 66 dp LESS room for a service name; pinning the number
        // end-to-end is what catches a regression introduced anywhere ABOVE
        // the card (the ListView's `lg` insets, CategorySection's own inset)
        // rather than inside it.
        expect(
          boxes.info.size.width,
          _kNameColumnWidthAt360,
          reason:
              'the +66 dp reclaim measured end-to-end on a 360 dp phone: '
              'anything less means a caller, a list inset or a card trim '
              'regressed',
        );

        // And the well is genuinely gone from the real screen, not merely
        // sized to zero.
        expect(
          find.descendant(
            of: find.byKey(const Key('service_card_svc-001')),
            matching: find.byType(PhotoThumbnail),
          ),
          findsNothing,
          reason:
              'the services MANAGEMENT page opts out of the leading well; the '
              'booking wizard is the consumer that keeps it',
        );
      },
    );

    testWidgets(
      'the card is 50 dp tall — still above the 48 dp minimum touch target, '
      'and its vertical inset is symmetric `sm`',
      (tester) async {
        final boxes = await pumpAndMeasure(tester);

        expect(
          boxes.card.size.height,
          50.0,
          reason:
              'Phase 323 took the row 56 → 50 dp. The number drives scroll '
              'extent and the tap target, and no other test pins it.',
        );
        // Derived, font-independent half: 8 dp above + 8 dp below the tallest
        // row child. This survives a font-metric change that would move the
        // absolute 50 while the padding contract held.
        expect(
          boxes.card.size.height - boxes.info.size.height,
          16.0,
          reason:
              'vertical inset is symmetric VelvetSpacing.sm; the name column '
              'is the tallest child, so the card is exactly info + 2×8',
        );
        // THE REASON THE SHRINK IS SAFE. The whole row is the edit tap target
        // (the 22 dp pillow carries no gesture of its own), so the row height
        // IS the touch target and must not fall under Material's minimum.
        expect(
          boxes.card.size.height,
          greaterThanOrEqualTo(kMinInteractiveDimension),
          reason:
              'the card row is the edit tap target — shrinking it below '
              '48 dp would make the only write affordance on this screen '
              'un-hittable for a large finger',
        );
      },
    );

    testWidgets(
      'a READ-ONLY card is exactly as wide as a writable one — the blank slot '
      'and the edit pillow share `_kEditAffordanceSize`',
      (tester) async {
        final double writableInfo = (await pumpAndMeasure(
          tester,
        )).info.size.width;
        final double readOnlyInfo = (await pumpAndMeasure(
          tester,
          writable: false,
        )).info.size.width;

        // Anti-vacuity: the two mounts must genuinely differ in the trailing
        // slot, otherwise this is one measurement compared with itself.
        expect(
          find.descendant(
            of: find.byKey(const Key('service_card_svc-001')),
            matching: find.byType(GestureDetector),
          ),
          findsNothing,
          reason:
              'the second pump must really be the read-only branch (null '
              'onEdit → no GestureDetector, no _EditButton)',
        );
        expect(
          readOnlyInfo,
          writableInfo,
          reason:
              'Phase 320 D3 promised "the row does not reflow" and Phase 323 '
              'made that structural by sharing `_kEditAffordanceSize` between '
              '_EditButton and the blank slot. Nothing else guards the '
              'sharing: hard-coding either side back to 30 (or trimming only '
              'one) silently makes a SALON_MASTER read-only card wrap a name '
              'the owner sees whole.',
        );
      },
    );
  });
}
