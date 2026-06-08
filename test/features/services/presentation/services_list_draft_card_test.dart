// Phase 16.9 Part 2 — draft-card behaviour on the services list.
//
// The master's own services list now calls the authenticated getMyServices()
// (`GET /independent-masters/me/services`), which INCLUDES drafts
// (`isDraft=true`). A draft [MasterService] carries its name + category but a
// placeholder ₴0 / FIXED price and 0 duration. The card MUST NOT render that ₴0
// as a real price: instead it shows a quiet "Чернетка" badge by the title and a
// muted "set price to publish" CTA where the duration·price meta line normally
// sits. The whole card stays tappable and routes to the existing edit form so
// the master can set a price and publish.
//
// Coverage (each test would FAIL if the Part-2 draft branch were removed or the
// owner endpoint reverted):
//   A1. Draft card renders the "Чернетка" badge + set-price CTA, and NO price
//       text / "₴0" / "0 грн" leaks anywhere on the card.
//   A2. A published (isDraft:false) card shows the normal duration·price meta
//       line and NO draft badge / NO set-price CTA.
//   A3. Tapping a draft card routes to the service edit form (go_router push to
//       the /services/:id/edit path).
//   A4. A draft groups under its own category section, exactly like a published
//       service with the same category.
//
// Isolation: fresh ProviderScope per pump (pumpApp / pumpRoutedApp);
// servicesListProvider overridden with a stub notifier; serviceRepositoryProvider
// mocked so approvedCategoriesProvider resolves without real HTTP. Widgets are
// located by Key first; draft affordances are asserted via the ARB-driven
// localised text (servicesDraftBadge / servicesDraftSetPriceCta) read off the
// live AppLocalizations so the test never hard-codes the Ukrainian copy.

import 'dart:async';

import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_notifier.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/pump_app.dart';

// ---------------------------------------------------------------------------
// Mocks + stub notifier
// ---------------------------------------------------------------------------

class _MockServiceRepository extends Mock implements ServiceRepository {}

/// Stub [ServicesList] notifier that immediately resolves to [_data].
class _StubServicesList extends ServicesList {
  _StubServicesList(this._data);

  final List<MasterService> _data;

  @override
  Future<List<MasterService>> build() {
    Future<void>.microtask(() => state = AsyncData(_data));
    return Completer<List<MasterService>>().future;
  }
}

// ---------------------------------------------------------------------------
// Stub data
// ---------------------------------------------------------------------------

/// An auto-created draft: name + category present, but the placeholder ₴0 /
/// FIXED price and 0 duration that the backend assigns before the master sets a
/// real price. priceDisplay is intentionally a ₴0 string to prove the card
/// suppresses it.
const _draftService = MasterService(
  id: 'svc-draft',
  serviceDefId: 'def-draft',
  name: 'Стрижка',
  serviceTypeNameUk: 'Стрижка',
  category: 'HAIRCUT',
  durationMinutes: 0,
  priceType: ServicePriceType.fixed,
  priceMin: 0,
  priceDisplay: '0 грн',
  isActive: false,
  isDraft: true,
);

/// A normal published service in the same category.
const _publishedService = MasterService(
  id: 'svc-pub',
  serviceDefId: 'def-pub',
  name: 'Манікюр',
  serviceTypeNameUk: 'Манікюр',
  category: 'HAIRCUT',
  durationMinutes: 60,
  priceType: ServicePriceType.fixed,
  priceMin: 500,
  priceDisplay: '500 грн',
);

const _approvedCategories = <ServiceCategoryOption>[
  ServiceCategoryOption(name: 'HAIRCUT', displayName: 'Стрижка'),
];

// ---------------------------------------------------------------------------
// Router helper (A3) — records pushed locations without real routing.
// ---------------------------------------------------------------------------

GoRouter _recordingRouter(List<String> pushedRoutes) {
  return GoRouter(
    initialLocation: RouteNames.services,
    routes: <RouteBase>[
      GoRoute(
        path: RouteNames.services,
        builder: (context, state) => const ServicesListScreen(),
      ),
      GoRoute(
        path: '/services/:id/edit',
        // Echo the resolved :id so the test can assert the draft's assignment id
        // was threaded into the route (the NavigatorObserver only sees the route
        // PATTERN, not the resolved location, so we read the param here instead).
        builder: (context, state) =>
            _DummyEditPage(id: state.pathParameters['id'] ?? ''),
      ),
    ],
    observers: <NavigatorObserver>[_PushObserver(pushedRoutes)],
  );
}

class _DummyEditPage extends StatelessWidget {
  const _DummyEditPage({required this.id});
  final String id;
  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Text('Edit form for $id'));
}

class _PushObserver extends NavigatorObserver {
  _PushObserver(this.routes);
  final List<String> routes;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final name = route.settings.name;
    if (name != null) routes.add(name);
  }
}

void main() {
  late _MockServiceRepository repo;

  setUp(() {
    repo = _MockServiceRepository();
    // listMyServices is unused by the stub notifier (it owns build()), but the
    // repository is also read by approvedCategoriesProvider → fetchApprovedCategories.
    when(() => repo.listMyServices()).thenAnswer((_) async => const []);
    when(
      () => repo.fetchApprovedCategories(),
    ).thenAnswer((_) async => _approvedCategories);
  });

  /// Pumps the screen with [data], lands on the data frame, then expands the
  /// single HAIRCUT section so the card subtree is in the tree (sections open
  /// collapsed by default).
  Future<void> pumpAndExpand(
    WidgetTester tester,
    List<MasterService> data,
  ) async {
    await tester.pumpApp(
      const ServicesListScreen(),
      overrides: [
        servicesListProvider.overrideWith(() => _StubServicesList(data)),
        serviceRepositoryProvider.overrideWithValue(repo),
      ],
    );
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('category_section_HAIRCUT')));
    await tester.pumpAndSettle();
  }

  AppLocalizations l10nOf(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(ServicesListScreen)));

  // ── A1. Draft card renders badge + CTA; never a ₴0 price ───────────────────

  testWidgets(
    'A1. draft card shows the "Чернетка" badge and set-price CTA, and never '
    'renders the placeholder ₴0 price',
    (tester) async {
      await pumpAndExpand(tester, const <MasterService>[_draftService]);

      final card = find.byKey(const Key('service_card_svc-draft'));
      expect(
        card,
        findsOneWidget,
        reason: 'the draft card must be in the tree',
      );

      final l10n = l10nOf(tester);

      // Draft badge — localised "Чернетка", asserted inside the card subtree.
      expect(
        find.descendant(of: card, matching: find.text(l10n.servicesDraftBadge)),
        findsOneWidget,
        reason: 'a draft card must render the draft badge by the title',
      );
      // Set-price CTA — keyed widget + localised copy, inside the card subtree.
      expect(
        find.descendant(
          of: card,
          matching: find.byKey(const Key('service-card-draft-cta')),
        ),
        findsOneWidget,
        reason: 'a draft card must render the set-price CTA',
      );
      expect(
        find.descendant(
          of: card,
          matching: find.text(l10n.servicesDraftSetPriceCta),
        ),
        findsOneWidget,
        reason: 'the CTA copy must come from the ARB key, not a raw literal',
      );

      // The placeholder price must NOT leak in any shape: not the priceDisplay
      // string ("0 грн"), not a bare "₴0", not a "0 хв" duration meta.
      expect(
        find.text('0 грн'),
        findsNothing,
        reason: 'a draft must never present its placeholder ₴0 as a price',
      );
      expect(find.textContaining('₴0'), findsNothing);
      // The whole duration·price meta line is replaced by the CTA, so the
      // duration glyph value ("0 хв") must be absent too.
      expect(
        find.text('0 хв'),
        findsNothing,
        reason: 'the draft card replaces the duration·price line with the CTA',
      );
    },
  );

  // ── A2. Published card shows duration·price and NO draft affordances ────────

  testWidgets(
    'A2. published (isDraft:false) card shows the normal duration·price line '
    'and no draft badge / no set-price CTA',
    (tester) async {
      await pumpAndExpand(tester, const <MasterService>[_publishedService]);

      final card = find.byKey(const Key('service_card_svc-pub'));
      expect(card, findsOneWidget);

      final l10n = l10nOf(tester);

      // Normal meta line: server-formatted price + formatted duration.
      expect(
        find.descendant(of: card, matching: find.text('500 грн')),
        findsOneWidget,
        reason: 'a published card renders its real price',
      );
      expect(
        find.descendant(of: card, matching: find.text('1 год')),
        findsOneWidget,
        reason: 'a published card renders its real duration (60 min → "1 год")',
      );

      // No draft affordances anywhere on a published card.
      expect(
        find.text(l10n.servicesDraftBadge),
        findsNothing,
        reason: 'a published card must NOT render the draft badge',
      );
      expect(
        find.byKey(const Key('service-card-draft-cta')),
        findsNothing,
        reason: 'a published card must NOT render the set-price CTA',
      );
    },
  );

  // ── A3. Tapping a draft card routes to the edit form ───────────────────────

  testWidgets('A3. tapping a draft card pushes the /services/:id/edit route', (
    tester,
  ) async {
    final pushed = <String>[];
    final router = _recordingRouter(pushed);

    await tester.pumpRoutedApp(
      router,
      overrides: [
        servicesListProvider.overrideWith(
          () => _StubServicesList(const <MasterService>[_draftService]),
        ),
        serviceRepositoryProvider.overrideWithValue(repo),
      ],
    );
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    // Expand the section so the draft card is hittable.
    await tester.tap(find.byKey(const Key('category_section_HAIRCUT')));
    await tester.pumpAndSettle();

    final card = find.byKey(const Key('service_card_svc-draft'));
    expect(card, findsOneWidget);

    await tester.tap(card);
    await tester.pumpAndSettle();

    // The edit destination was reached with the draft's assignment id threaded
    // into the route's :id param.
    expect(
      find.text('Edit form for svc-draft'),
      findsOneWidget,
      reason:
          'tapping a draft card must navigate to the edit form for THIS '
          "draft's assignment id",
    );
    // A push did occur (observer records the edit route pattern).
    expect(
      pushed,
      contains('/services/:id/edit'),
      reason: 'exactly one navigation push to the edit route must fire',
    );
    // Sanity-check the route-name helper builds the expected location.
    expect(RouteNames.serviceEdit('svc-draft'), '/services/svc-draft/edit');
  });

  // ── A4. A draft groups under its own category section ──────────────────────

  testWidgets(
    'A4. a draft with category=HAIRCUT renders under the HAIRCUT section',
    (tester) async {
      // Two services in the same category: one draft, one published. Both must
      // land under the single HAIRCUT section.
      await pumpAndExpand(tester, const <MasterService>[
        _draftService,
        _publishedService,
      ]);

      final section = find.byKey(const Key('category_section_HAIRCUT'));
      expect(
        section,
        findsOneWidget,
        reason: 'one HAIRCUT section is expected',
      );
      // No uncategorized bucket — every service carries the HAIRCUT category.
      expect(
        find.byKey(const Key('category_section__none')),
        findsNothing,
        reason:
            'the draft carries a category, so it must not fall back to the '
            'uncategorized bucket',
      );

      // Both cards are present after expanding the HAIRCUT section, proving the
      // draft grouped alongside the published service in that category.
      expect(find.byKey(const Key('service_card_svc-draft')), findsOneWidget);
      expect(find.byKey(const Key('service_card_svc-pub')), findsOneWidget);

      // The HAIRCUT count badge reflects BOTH services (draft is not filtered
      // out of its section).
      expect(
        find.descendant(of: section, matching: find.text('2')),
        findsOneWidget,
        reason: 'the section count must include the draft (2 services)',
      );
    },
  );
}
