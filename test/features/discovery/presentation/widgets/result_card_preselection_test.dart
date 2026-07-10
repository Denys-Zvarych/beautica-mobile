// Widget tests — tapping a discovery result card records the search service
// pre-selection for the booking flow.
//
// Pins the DISCOVERY half of the search→booking handoff (the booking half is
// pinned in test/features/booking/presentation/booking_preselection_seed_test.dart):
//   • with an active service filter, tapping a master / salon card calls
//     `PendingServicePreselectionController.set` with the card's OWN target id
//     (masterId / salonId) and the filter's exact serviceTypeSlugs (+ the
//     defensive display labels resolved from categoryServiceOptionsProvider);
//   • with NO service filter (empty serviceTypeSlugs / null activeFilters) the
//     provider is LEFT null — nothing is handed to the booking flow.
//
// Harness notes:
//   • The card calls `context.push`, so it is pumped inside a real GoRouter
//     (pumpRoutedApp) with stub destination routes for /masters/:id + /salons/:id.
//   • pendingServicePreselectionControllerProvider is overridden with a probe
//     subclass whose build() returns null WITHOUT watching authProvider — the
//     real `set()` still runs (that is what is under test), but the auth graph
//     stays out of the widget test entirely.
//   • categoryServiceOptionsProvider is the documented override footgun (it
//     sources from the real Dio-backed request api, NOT the service repo) — it
//     is overridden directly so label resolution is deterministic and no real
//     request fires.
//   • favoriteToggleProvider is overridden auth-free so the favourite heart
//     renders network-free (same pattern as master_result_card_test.dart).

import 'package:beautica_mobile/features/booking/application/pending_service_preselection_provider.dart';
import 'package:beautica_mobile/features/booking/domain/pending_service_preselection.dart';
import 'package:beautica_mobile/features/discovery/data/category_service_providers.dart';
import 'package:beautica_mobile/features/discovery/domain/category_service_option.dart';
import 'package:beautica_mobile/features/discovery/domain/master_search_item.dart';
import 'package:beautica_mobile/features/discovery/domain/salon_search_item.dart';
import 'package:beautica_mobile/features/discovery/domain/search_filters.dart';
import 'package:beautica_mobile/features/discovery/presentation/widgets/master_result_card.dart';
import 'package:beautica_mobile/features/discovery/presentation/widgets/salon_result_card.dart';
import 'package:beautica_mobile/features/favorites/application/favorite_toggle_notifier.dart';
import 'package:beautica_mobile/features/favorites/domain/favorite_target.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../../helpers/pump_app.dart';

// ---------------------------------------------------------------------------
// Auth-free favourite toggle — skips the production build()'s auth watch.
// ---------------------------------------------------------------------------
class _AuthFreeFavoriteToggleNotifier extends FavoriteToggleNotifier {
  @override
  Map<FavoriteTarget, FavoriteEntry> build() =>
      const <FavoriteTarget, FavoriteEntry>{};
}

// ---------------------------------------------------------------------------
// Probe preselection controller — build() returns null WITHOUT watching
// authProvider, so the auth graph stays out of the widget test. The real
// `set()` (the method under test) is inherited unchanged.
// ---------------------------------------------------------------------------
class _ProbePreselectionController
    extends PendingServicePreselectionController {
  @override
  PendingServicePreselection? build() => null;
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _kMaster = MasterSearchItem(
  masterId: 'master-1',
  firstName: 'Софія',
  lastName: 'Бондар',
  avatarUrl: null,
  avgRating: 4.9,
  reviewCount: 24,
  cityLabel: 'Київ',
  districtLabel: 'Печерський',
  minEffectivePrice: 450,
  priceMax: null,
  street: null,
  buildingNo: null,
  locationNote: null,
);

const _kSalon = SalonSearchItem(
  salonId: 'salon-xyz',
  name: 'Студія Краси «Камелія»',
  avatarUrl: null,
  avgRating: null,
  cityLabel: 'Київ',
  districtLabel: 'Печерський',
  priceMin: 300,
  priceMax: 1200,
  street: null,
  buildingNo: null,
  locationNote: null,
);

const _kFilters = SearchFilters(
  categoryKey: 'NAILS',
  serviceTypeSlugs: <String>{'CLASSIC_MANICURE'},
);

const _kNoServiceFilters = SearchFilters(
  categoryKey: 'NAILS',
  serviceTypeSlugs: <String>{},
);

List<Object> _overrides() => <Object>[
  favoriteToggleProvider.overrideWith(_AuthFreeFavoriteToggleNotifier.new),
  pendingServicePreselectionControllerProvider.overrideWith(
    _ProbePreselectionController.new,
  ),
  // Footgun: sources from the real Dio-backed request api — MUST be overridden
  // directly or `resolveServiceTypeLabels` fires a real request. The resolved
  // option lets the test assert the defensive display label too.
  categoryServiceOptionsProvider('NAILS').overrideWith(
    (ref) async => const <CategoryServiceOption>[
      CategoryServiceOption(
        key: 'CLASSIC_MANICURE',
        displayName: 'Класичний манікюр',
      ),
    ],
  ),
];

GoRouter _routerFor(Widget card) => GoRouter(
  initialLocation: '/',
  routes: <RouteBase>[
    GoRoute(
      path: '/',
      builder: (context, state) => Scaffold(body: card),
    ),
    GoRoute(
      path: '/masters/:id',
      builder: (context, state) =>
          const Scaffold(body: Text('master-profile-stub')),
    ),
    GoRoute(
      path: '/salons/:id',
      builder: (context, state) =>
          const Scaffold(body: Text('salon-profile-stub')),
    ),
  ],
);

/// Reads the live preselection state off the ProviderScope container. Captured
/// while the card is still mounted (before navigation replaces it).
PendingServicePreselection? _readState(ProviderContainer container) =>
    container.read(pendingServicePreselectionControllerProvider);

/// Warms + keeps the overridden async options provider alive so its `.value`
/// is populated (AsyncData) by the time the card's tap handler reads it.
Future<void> _warmOptions(WidgetTester tester, ProviderContainer c) async {
  c.listen(
    categoryServiceOptionsProvider('NAILS'),
    (_, _) {},
    fireImmediately: true,
  );
  await tester.pumpAndSettle();
}

void main() {
  group('MasterResultCard → set preselection', () {
    testWidgets(
      'tapping a master card with an active service filter records the '
      'preselection with the master id + the filter slugs (+ labels)',
      (tester) async {
        await tester.pumpRoutedApp(
          _routerFor(
            const MasterResultCard(master: _kMaster, activeFilters: _kFilters),
          ),
          overrides: _overrides(),
        );
        await tester.pumpAndSettle();

        final ProviderContainer container = ProviderScope.containerOf(
          tester.element(find.byType(MasterResultCard)),
        );
        await _warmOptions(tester, container);

        await tester.tap(find.byType(MasterResultCard));
        await tester.pumpAndSettle();

        // Navigation to the master profile happened …
        expect(find.text('master-profile-stub'), findsOneWidget);

        // … AND the pre-selection was recorded for THIS master with the
        // filter's exact slugs and the resolved defensive label.
        final PendingServicePreselection? state = _readState(container);
        expect(state, isNotNull);
        expect(state!.targetId, 'master-1');
        expect(state.serviceTypeSlugs, <String>{'CLASSIC_MANICURE'});
        expect(state.serviceTypeLabels, <String>{'Класичний манікюр'});
      },
    );

    testWidgets(
      'tapping a master card with NO active service filter leaves the '
      'preselection null',
      (tester) async {
        await tester.pumpRoutedApp(
          _routerFor(
            const MasterResultCard(
              master: _kMaster,
              activeFilters: _kNoServiceFilters,
            ),
          ),
          overrides: _overrides(),
        );
        await tester.pumpAndSettle();

        final ProviderContainer container = ProviderScope.containerOf(
          tester.element(find.byType(MasterResultCard)),
        );

        await tester.tap(find.byType(MasterResultCard));
        await tester.pumpAndSettle();

        expect(find.text('master-profile-stub'), findsOneWidget);
        expect(
          _readState(container),
          isNull,
          reason:
              'an empty service filter must hand nothing to the booking '
              'flow',
        );
      },
    );
  });

  group('SalonResultCard → set preselection', () {
    testWidgets(
      'tapping a salon card with an active service filter records the '
      'preselection with the salon id + the filter slugs (+ labels)',
      (tester) async {
        await tester.pumpRoutedApp(
          _routerFor(
            const SalonResultCard(salon: _kSalon, activeFilters: _kFilters),
          ),
          overrides: _overrides(),
        );
        await tester.pumpAndSettle();

        final ProviderContainer container = ProviderScope.containerOf(
          tester.element(find.byType(SalonResultCard)),
        );
        await _warmOptions(tester, container);

        await tester.tap(find.byKey(Key('salon_card_${_kSalon.salonId}')));
        await tester.pumpAndSettle();

        expect(find.text('salon-profile-stub'), findsOneWidget);

        final PendingServicePreselection? state = _readState(container);
        expect(state, isNotNull);
        expect(state!.targetId, 'salon-xyz');
        expect(state.serviceTypeSlugs, <String>{'CLASSIC_MANICURE'});
        expect(state.serviceTypeLabels, <String>{'Класичний манікюр'});
      },
    );

    testWidgets('tapping a salon card with NO active service filter leaves the '
        'preselection null', (tester) async {
      await tester.pumpRoutedApp(
        _routerFor(
          const SalonResultCard(
            salon: _kSalon,
            activeFilters: _kNoServiceFilters,
          ),
        ),
        overrides: _overrides(),
      );
      await tester.pumpAndSettle();

      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(SalonResultCard)),
      );

      await tester.tap(find.byKey(Key('salon_card_${_kSalon.salonId}')));
      await tester.pumpAndSettle();

      expect(find.text('salon-profile-stub'), findsOneWidget);
      expect(_readState(container), isNull);
    });
  });

  // The route-name constants the stubs stand in for — pinned so a route
  // rename that breaks the card's push target is caught here, not only in the
  // integration flow.
  test('card push targets resolve to the profile routes the stubs model', () {
    expect(RouteNames.masterPublicProfile('master-1'), '/masters/master-1');
    expect(RouteNames.salonPublicProfile('salon-xyz'), '/salons/salon-xyz');
  });
}
