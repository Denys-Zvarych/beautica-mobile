// mobile-qa — widget tests for the shared ServiceCategoryCardList /
// ServiceCategoryCard / ServiceCategoryCountBadge extracted from Phase 4.2's
// `_ProfileCategoriesSection` (master_profile_screen.dart) into
// service_category_cards.dart so BOTH the owner's MasterProfileScreen
// (`interactive: true`) and the CLIENT-facing PublicMasterProfileScreen
// (`interactive: false`) render the identical grouped-by-category summary
// list.
//
// mobile-security LOW (closed): `interactive` used to default to `true` — a
// fail-open default on a security-relevant toggle. The two current call
// sites were always correct, but nothing at the shared-widget level pinned
// that `interactive: false` actually strips ALL owner-only affordances (no
// chevron, no GestureDetector, no navigation on tap), and a FUTURE
// client-facing call site could still have forgotten `interactive: false`
// and silently fallen back to the owner-only navigation. Root-cause fix:
// `interactive` is now a REQUIRED named parameter on both
// [ServiceCategoryCardList] and [ServiceCategoryCard] — no default — so the
// compiler rejects any call site that doesn't state its intent explicitly.
// This file is the behavioural pin, exercised directly against
// [ServiceCategoryCard] / [ServiceCategoryCardList] so a regression here is
// caught regardless of which screen embeds them. (public_master_profile_
// screen_test.dart separately pins the REAL call site — see the "service
// categories section" group there — which is what actually catches someone
// changing `interactive: false` to `interactive: true` in
// public_master_profile_screen.dart.)
//
// CRITICAL traps observed:
//   - approvedCategoriesProvider is NOT sourced through serviceRepositoryProvider
//     (it hits the real Dio-backed categoryRequestApiProvider) — every test
//     below overrides it directly, never relying on a repo-fake override.
//   - nav-detection MUST drive a real tap → real context.push. A test that
//     called `router.go(...)` directly would false-pass even if the shipped
//     card had lost its tap handler, because it never exercises the widget's
//     own onTapUp callback.

import 'package:beautica_mobile/features/master/presentation/widgets/service_category_cards.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../../helpers/pump_app.dart';

// ---------------------------------------------------------------------------
// Stub data
// ---------------------------------------------------------------------------

const List<MasterService> _twoCategoryServices = <MasterService>[
  MasterService(
    id: 'svc-1',
    serviceDefId: 'def-1',
    name: 'Манікюр з покриттям',
    durationMinutes: 60,
    priceMin: 500,
    priceDisplay: '500 ₴',
    category: 'MANICURE',
  ),
  MasterService(
    id: 'svc-2',
    serviceDefId: 'def-2',
    name: 'Корекція брів',
    durationMinutes: 30,
    priceMin: 250,
    priceDisplay: '250 ₴',
    category: 'BROWS',
  ),
  MasterService(
    id: 'svc-3',
    serviceDefId: 'def-3',
    name: 'Ще один манікюр',
    durationMinutes: 45,
    priceMin: 400,
    priceDisplay: '400 ₴',
    category: 'MANICURE',
  ),
];

const List<MasterService> _uncategorizedServices = <MasterService>[
  MasterService(
    id: 'svc-none-1',
    serviceDefId: 'def-none-1',
    name: 'Без категорії',
    durationMinutes: 20,
    priceMin: 100,
    priceDisplay: '100 ₴',
    // category deliberately absent → "_none" bucket.
  ),
];

// The category-label lookup provider — bypasses serviceRepositoryProvider
// entirely (sourced from categoryRequestApiProvider / real Dio). MUST be
// overridden directly in every test that mounts this widget, or
// pumpAndSettle() hangs on a leaked real-network Timer.
List<Object> _overrides() => <Object>[
  approvedCategoriesProvider.overrideWith(
    (ref) async => const <ServiceCategoryOption>[],
  ),
];

void main() {
  group('grouping', () {
    testWidgets('renders one card per non-empty category with the correct '
        'count, and an empty services list renders no cards', (tester) async {
      await tester.pumpApp(
        const ServiceCategoryCardList(
          services: _twoCategoryServices,
          keyPrefix: 'test-category',
          interactive: true,
        ),
        overrides: _overrides(),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('test-category-MANICURE')), findsOneWidget);
      expect(find.byKey(const Key('test-category-BROWS')), findsOneWidget);

      // MANICURE bucket has 2 services (svc-1 + svc-3); BROWS has 1.
      final ServiceCategoryCard manicureCard = tester.widget(
        find.byKey(const Key('test-category-MANICURE')),
      );
      final ServiceCategoryCard browsCard = tester.widget(
        find.byKey(const Key('test-category-BROWS')),
      );
      expect(manicureCard.count, 2);
      expect(browsCard.count, 1);
    });

    testWidgets('an empty services list renders no cards at all', (
      tester,
    ) async {
      await tester.pumpApp(
        const ServiceCategoryCardList(
          services: <MasterService>[],
          keyPrefix: 'test-category',
          interactive: true,
        ),
        overrides: _overrides(),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ServiceCategoryCard), findsNothing);
    });

    testWidgets('services with no category are grouped under the _none '
        'bucket key', (tester) async {
      await tester.pumpApp(
        const ServiceCategoryCardList(
          services: _uncategorizedServices,
          keyPrefix: 'test-category',
          interactive: true,
        ),
        overrides: _overrides(),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('test-category-_none')), findsOneWidget);
      final ServiceCategoryCard card = tester.widget(
        find.byKey(const Key('test-category-_none')),
      );
      expect(card.count, 1);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // interactive: true (owner) — chevron + GestureDetector present, tapping
  // navigates to /services?expandCategory=<slug>.
  // ──────────────────────────────────────────────────────────────────────────
  group('interactive: true (owner) — navigates', () {
    testWidgets('renders a forward chevron and a GestureDetector', (
      tester,
    ) async {
      await tester.pumpApp(
        const ServiceCategoryCardList(
          services: _twoCategoryServices,
          keyPrefix: 'test-category',
          // `interactive` is now a REQUIRED named param (mobile-security LOW
          // fix — no more `= true` default), so the compiler enforces this
          // choice at every call site; this test still pins the resulting
          // owner-facing behaviour (chevron + GestureDetector present).
          interactive: true,
        ),
        overrides: _overrides(),
      );
      await tester.pumpAndSettle();

      final Finder card = find.byKey(const Key('test-category-MANICURE'));
      expect(
        find.descendant(
          of: card,
          matching: find.byIcon(Icons.arrow_forward_ios_rounded),
        ),
        findsOneWidget,
        reason: 'the owner card must show the disclosure chevron',
      );
      expect(
        find.descendant(of: card, matching: find.byType(GestureDetector)),
        findsOneWidget,
        reason: 'the owner card must be tappable',
      );
    });

    testWidgets('tapping a card pushes /services?expandCategory=<slug>', (
      tester,
    ) async {
      final List<String> pushedLocations = <String>[];
      final GoRouter router = GoRouter(
        initialLocation: '/host',
        routes: <RouteBase>[
          GoRoute(
            path: '/host',
            builder: (context, _) => const Scaffold(
              body: ServiceCategoryCardList(
                services: _twoCategoryServices,
                keyPrefix: 'test-category',
                interactive: true,
              ),
            ),
          ),
          GoRoute(
            path: RouteNames.services,
            builder: (context, state) {
              pushedLocations.add(state.uri.toString());
              return const Scaffold(body: Text('services-page'));
            },
          ),
        ],
      );

      await tester.pumpRoutedApp(router, overrides: _overrides());
      await tester.pumpAndSettle();

      final Finder card = find.byKey(const Key('test-category-MANICURE'));
      expect(card, findsOneWidget);

      // Real tap → real onTapUp → real context.push. NEVER stand this in with
      // router.go/router.push directly (nav-detection trap).
      await tester.tap(card);
      await tester.pumpAndSettle();

      expect(find.text('services-page'), findsOneWidget);
      expect(pushedLocations, hasLength(1));
      expect(pushedLocations.single, contains('expandCategory=MANICURE'));
    });

    testWidgets(
      'tapping the uncategorized (_none) card pushes /services with NO '
      'expandCategory query param',
      (tester) async {
        final List<String> pushedLocations = <String>[];
        final GoRouter router = GoRouter(
          initialLocation: '/host',
          routes: <RouteBase>[
            GoRoute(
              path: '/host',
              builder: (context, _) => const Scaffold(
                body: ServiceCategoryCardList(
                  services: _uncategorizedServices,
                  keyPrefix: 'test-category',
                  interactive: true,
                ),
              ),
            ),
            GoRoute(
              path: RouteNames.services,
              builder: (context, state) {
                pushedLocations.add(state.uri.toString());
                return const Scaffold(body: Text('services-page'));
              },
            ),
          ],
        );

        await tester.pumpRoutedApp(router, overrides: _overrides());
        await tester.pumpAndSettle();

        final Finder card = find.byKey(const Key('test-category-_none'));
        await tester.tap(card);
        await tester.pumpAndSettle();

        expect(find.text('services-page'), findsOneWidget);
        expect(pushedLocations, hasLength(1));
        expect(pushedLocations.single, isNot(contains('expandCategory')));
      },
    );
  });

  // ──────────────────────────────────────────────────────────────────────────
  // interactive: false (CLIENT public profile) — SECURITY REGRESSION GUARD.
  //
  // mobile-security LOW (closed): `interactive` used to default to `true`
  // (fail-open); it is now a REQUIRED named param, so a call site can no
  // longer omit it — but this group still pins the explicit
  // `interactive: false` opt-out's actual BEHAVIOUR at the shared-widget
  // level: no chevron, no GestureDetector anywhere in the card, and forcing
  // a tap on the card's position never navigates. If a future edit flips the
  // internal `if (widget.interactive)` guard or otherwise starts wiring a tap
  // handler for the non-interactive branch, this test goes red.
  // ──────────────────────────────────────────────────────────────────────────
  group(
    'interactive: false (client, read-only) — SECURITY REGRESSION GUARD',
    () {
      testWidgets('renders NO forward chevron and NO GestureDetector', (
        tester,
      ) async {
        await tester.pumpApp(
          const ServiceCategoryCardList(
            services: _twoCategoryServices,
            keyPrefix: 'test-category',
            interactive: false,
          ),
          overrides: _overrides(),
        );
        await tester.pumpAndSettle();

        final Finder card = find.byKey(const Key('test-category-MANICURE'));
        expect(card, findsOneWidget);

        expect(
          find.descendant(
            of: card,
            matching: find.byIcon(Icons.arrow_forward_ios_rounded),
          ),
          findsNothing,
          reason: 'a read-only card must never show the disclosure chevron',
        );
        expect(
          find.descendant(of: card, matching: find.byType(GestureDetector)),
          findsNothing,
          reason: 'a read-only card must have NO tap handler whatsoever',
        );

        // The Semantics node must not be flagged as a button either. Semantics
        // is the widget ServiceCategoryCard's own build() returns (its build
        // OUTPUT, not an ancestor of the ServiceCategoryCard element) — so this
        // looks among its DESCENDANTS, not ancestors.
        final Semantics semantics = tester.widget(
          find.descendant(of: card, matching: find.byType(Semantics)).first,
        );
        expect(
          semantics.properties.button,
          isNot(true),
          reason: 'a read-only card must not expose button semantics',
        );
      });

      testWidgets('forcing a tap on a non-interactive card never navigates', (
        tester,
      ) async {
        final List<String> pushedLocations = <String>[];
        final GoRouter router = GoRouter(
          initialLocation: '/host',
          routes: <RouteBase>[
            GoRoute(
              path: '/host',
              builder: (context, _) => const Scaffold(
                body: ServiceCategoryCardList(
                  services: _twoCategoryServices,
                  keyPrefix: 'test-category',
                  interactive: false,
                ),
              ),
            ),
            GoRoute(
              path: RouteNames.services,
              builder: (context, state) {
                pushedLocations.add(state.uri.toString());
                return const Scaffold(body: Text('services-page'));
              },
            ),
          ],
        );

        await tester.pumpRoutedApp(router, overrides: _overrides());
        await tester.pumpAndSettle();

        final Finder card = find.byKey(const Key('test-category-MANICURE'));
        expect(card, findsOneWidget);

        // No GestureDetector under the card to receive a real tap, so this
        // forces a tap at the card's location — mirroring the "would a stray
        // tap accidentally fire something" question. `warnIfMissed: false`
        // because there is (by design) no hit-testable gesture target here.
        await tester.tap(card, warnIfMissed: false);
        await tester.pumpAndSettle();

        expect(
          find.text('services-page'),
          findsNothing,
          reason: 'a read-only card must never push /services on tap',
        );
        expect(
          pushedLocations,
          isEmpty,
          reason:
              'a read-only card must never navigate — this is the guard for '
              'the mobile-security LOW (interactive used to default to true, '
              'fail-open; it is now a required named param): a future edit '
              'changing `interactive: false` to `true` at a client-facing '
              'call site would flip this test red',
        );
      });
    },
  );
}
