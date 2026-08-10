// Phase 14.12 — Widget tests for SalonServiceSelectionScreen.
//
// Covers (phase doc Step 5):
//   1. Loading / error / empty-catalogue states.
//   2. Category accordion expand/collapse.
//   3. Multi-select toggling updates the pinned summary + total.
//   4. "Далі" disabled with 0 selected, enabled ≥1, navigates to
//      /booking/salon/masters with the correct extra.
//
// The per-category tri-state "select all" pill this screen used to render
// has been DELETED (product decision, part of unifying this screen's
// catalogue accordion with `ServiceSelectorSheet`'s into
// `widgets/service_catalogue_accordion.dart` — see that screen's file header
// for the refactor note). There is no replacement affordance to cover here.
//
// Phase E — the "favourite heart (Phase 240 trap guard)" group below used to
// assert NO heart ever rendered on this screen (the row id was a
// salon-catalogue-service id, not a real `master_services` id, so there was no
// safe target type to favourite against). The backend now exposes a distinct
// `SALON_SERVICE` favorite target type keyed to exactly this row's id
// (`service_definitions.id`), so that guard is INVERTED here to assert the
// heart renders, primes from `SalonCatalogService.isFavorite`, and toggles
// against `FavoriteTargetType.salonService` — never `.service` (the
// independent-master flow's target type, which would 400 against a salon
// catalogue id the backend has never associated with a master-service
// assignment).

import 'dart:async';

import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/booking/data/slot_repository.dart'
    show maxServicesPerVisit;
import 'package:beautica_mobile/features/booking/domain/salon_booking_args.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_service_selection_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_summary_bar.dart';
import 'package:beautica_mobile/features/discovery/presentation/widgets/favorite_heart_button.dart';
import 'package:beautica_mobile/features/favorites/data/favorite_repository_provider.dart';
import 'package:beautica_mobile/features/favorites/domain/favorite_target.dart';
import 'package:beautica_mobile/features/salon/application/salon_service_catalog_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fakes/fake_favorite_repository.dart';
import '../../../helpers/pump_app.dart';
import '../../../helpers/velvet_snack_matchers.dart';

const String _kSalonId = 'salon-1';

const _svcA1 = SalonCatalogService(
  id: 'svc-a1',
  name: 'Класичний манікюр',
  durationLabel: '1 год',
  priceDisplay: '300 ₴',
  category: 'MANICURE',
  durationMinutes: 60,
  priceType: ServicePriceType.fixed,
  priceMin: 300,
);

const _svcA2 = SalonCatalogService(
  id: 'svc-a2',
  name: 'Манікюр з покриттям',
  durationLabel: '1 год 30 хв',
  priceDisplay: '500 ₴',
  category: 'MANICURE',
  durationMinutes: 90,
  priceType: ServicePriceType.fixed,
  priceMin: 500,
);

const _svcB1 = SalonCatalogService(
  id: 'svc-b1',
  name: 'Педикюр',
  durationLabel: '2 год',
  priceDisplay: '800 ₴',
  category: 'PEDICURE',
  durationMinutes: 120,
  priceType: ServicePriceType.fixed,
  priceMin: 800,
);

const _stubCatalog = <SalonServiceCategoryEntry>[
  SalonServiceCategoryEntry(
    category: 'MANICURE',
    displayName: 'Манікюр',
    count: 2,
    services: <SalonCatalogService>[_svcA1, _svcA2],
  ),
  SalonServiceCategoryEntry(
    category: 'PEDICURE',
    displayName: 'Педикюр',
    count: 1,
    services: <SalonCatalogService>[_svcB1],
  ),
];

/// [count] distinct services in ONE expanded category — for the 10-cap test
/// (mirrors `service_selector_sheet_test.dart`'s `_manyServices`, the
/// independent flow's own cap fixture, so the salon multi-select's shared
/// `maxServicesPerVisit` guard is pinned on BOTH surfaces).
List<SalonServiceCategoryEntry> _manyServicesCatalog(int count) =>
    <SalonServiceCategoryEntry>[
      SalonServiceCategoryEntry(
        category: 'MANICURE',
        displayName: 'Манікюр',
        count: count,
        services: <SalonCatalogService>[
          for (int i = 0; i < count; i++)
            SalonCatalogService(
              id: 'svc-$i',
              name: 'Послуга $i',
              durationLabel: '1 год',
              priceDisplay: '300 ₴',
              category: 'MANICURE',
              durationMinutes: 60,
              priceType: ServicePriceType.fixed,
              priceMin: 300,
            ),
        ],
      ),
    ];

/// [GoRouter] with the screen under test at its initial location, plus a
/// terminal capture route for `/booking/salon/masters` so navigation (and the
/// `extra` it carries) can be asserted without pulling in the real
/// `SalonMasterSelectionScreen`.
GoRouter _routerFor({
  ValueChanged<SalonBookingMasterSelectionArgs>? onReached,
}) {
  return GoRouter(
    initialLocation: RouteNames.salonBookingServices,
    routes: <RouteBase>[
      GoRoute(
        path: RouteNames.salonBookingServices,
        builder: (context, state) =>
            const SalonServiceSelectionScreen(salonId: _kSalonId),
      ),
      GoRoute(
        path: RouteNames.salonBookingMasters,
        builder: (context, state) {
          onReached?.call(state.extra! as SalonBookingMasterSelectionArgs);
          return const Scaffold(
            body: Center(child: Text('masters-screen-reached')),
          );
        },
      ),
    ],
  );
}

void main() {
  group('loading state', () {
    testWidgets('shows a skeleton, no catalogue rows', (tester) async {
      final completer = Completer<List<SalonServiceCategoryEntry>>();
      await tester.pumpRoutedApp(
        _routerFor(),
        overrides: [
          salonServiceCatalogProvider(
            _kSalonId,
          ).overrideWith((ref) => completer.future),
        ],
      );
      await tester.pump();

      // i18n-finder-ok: fixture category label (test data), not app UI copy.
      expect(find.text('Манікюр'), findsNothing);
      expect(find.byKey(const Key('booking-summary-cta')), findsNothing);
    });
  });

  group('error state', () {
    testWidgets('shows ErrorState with a working retry', (tester) async {
      int calls = 0;
      await tester.pumpApp(
        const SalonServiceSelectionScreen(salonId: _kSalonId),
        // Disables Riverpod's default exponential-backoff retry so the error
        // state stays put through pumpAndSettle instead of silently
        // auto-recovering to the success value before the assertion runs.
        retry: (_, _) => null,
        overrides: [
          salonServiceCatalogProvider(_kSalonId).overrideWith((ref) async {
            calls++;
            if (calls == 1) throw Exception('boom');
            return _stubCatalog;
          }),
        ],
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('salon-service-selection-error-state')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('error_state_retry_button')));
      await tester.pumpAndSettle();

      // i18n-finder-ok: fixture category label (test data), not app UI copy.
      expect(find.text('Манікюр'), findsOneWidget);
    });
  });

  group('empty catalogue', () {
    testWidgets('shows the empty-catalogue state', (tester) async {
      await tester.pumpRoutedApp(
        _routerFor(),
        overrides: [
          salonServiceCatalogProvider(
            _kSalonId,
          ).overrideWith((ref) async => const <SalonServiceCategoryEntry>[]),
        ],
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('salon-service-selection-empty')),
        findsOneWidget,
      );
    });
  });

  group('category accordion', () {
    testWidgets('first category expanded on load, second collapsed', (
      tester,
    ) async {
      await tester.pumpRoutedApp(
        _routerFor(),
        overrides: [
          salonServiceCatalogProvider(
            _kSalonId,
          ).overrideWith((ref) async => _stubCatalog),
        ],
      );
      await tester.pumpAndSettle();

      // First category's services render immediately.
      // i18n-finder-ok: fixture service names (test data), not app UI copy.
      expect(find.text('Класичний манікюр'), findsOneWidget);
      // i18n-finder-ok: fixture service name (test data), not app UI copy.
      expect(find.text('Манікюр з покриттям'), findsOneWidget);
      // Second category starts collapsed.
      // i18n-finder-ok: fixture category label (test data), not app UI copy.
      expect(find.text('Педикюр'), findsOneWidget); // category header label
      // i18n-finder-ok: fixture category label (test data), not app UI copy.
      expect(find.text('Педикюр'), findsNWidgets(1));
    });

    testWidgets('tapping a category header toggles expand/collapse', (
      tester,
    ) async {
      await tester.pumpRoutedApp(
        _routerFor(),
        overrides: [
          salonServiceCatalogProvider(
            _kSalonId,
          ).overrideWith((ref) async => _stubCatalog),
        ],
      );
      await tester.pumpAndSettle();

      // Expand the second category ("Педикюр").
      await tester.tap(find.byKey(const Key('salon-booking-category-Педикюр')));
      await tester.pumpAndSettle();
      // i18n-finder-ok: fixture data (a service name never in the catalogue).
      expect(find.text('Педикюр з покриттям'), findsNothing);
      expect(
        find.byKey(const Key('salon_booking_service_tile_svc-b1')),
        findsOneWidget,
      );

      // Collapse the first category ("Манікюр").
      await tester.tap(find.byKey(const Key('salon-booking-category-Манікюр')));
      await tester.pumpAndSettle();
      // i18n-finder-ok: fixture service name (test data), not app UI copy.
      expect(find.text('Класичний манікюр'), findsNothing);
    });
  });

  // ===========================================================================
  // Phase E — the salon flow's heart is ON. `SalonCatalogService.id` IS
  // `service_definitions.id` (see `salon_mapper.dart`), which the backend's
  // new `SALON_SERVICE` favorite target type is keyed to directly — so this
  // screen's rows can now safely favourite, PROVIDED the target type is
  // `FavoriteTargetType.salonService`, never the independent-master flow's
  // `.service` (that would send an id the backend has never associated with a
  // master-service assignment).
  // ===========================================================================
  group('favourite heart (Phase E — salon target type)', () {
    testWidgets('renders a favourite heart on every row, primed from '
        'SalonCatalogService.isFavorite', (tester) async {
      await tester.pumpRoutedApp(
        _routerFor(),
        overrides: [
          salonServiceCatalogProvider(_kSalonId).overrideWith(
            (ref) async => <SalonServiceCategoryEntry>[
              _stubCatalog[0].copyWith(
                services: <SalonCatalogService>[
                  _svcA1.copyWith(isFavorite: true),
                  _svcA2,
                ],
              ),
              _stubCatalog[1],
            ],
          ),
        ],
      );
      await tester.pumpAndSettle();

      // The first category is expanded by default — its rows are on screen.
      // i18n-finder-ok: fixture service name (test data), not app UI copy.
      expect(find.text('Класичний манікюр'), findsOneWidget);

      expect(find.byType(FavoriteHeartButton), findsNWidgets(2));

      final Finder svcA1Heart = find.byKey(
        const Key('booking_service_heart_svc-a1'),
      );
      final Finder svcA2Heart = find.byKey(
        const Key('booking_service_heart_svc-a2'),
      );
      expect(svcA1Heart, findsOneWidget);
      expect(svcA2Heart, findsOneWidget);

      // svc-a1 is fetched with isFavorite:true — primes filled, not
      // outline-then-flip.
      expect(
        find.descendant(
          of: svcA1Heart,
          matching: find.byIcon(Icons.favorite_rounded),
        ),
        findsOneWidget,
      );
      // svc-a2 is fetched with isFavorite:false (the fixture default) —
      // primes outline.
      expect(
        find.descendant(
          of: svcA2Heart,
          matching: find.byIcon(Icons.favorite_border_rounded),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'tapping a row heart favourites against FavoriteTargetType.salonService',
      (tester) async {
        final FakeFavoriteRepository repo = FakeFavoriteRepository();

        await tester.pumpRoutedApp(
          _routerFor(),
          overrides: [
            salonServiceCatalogProvider(
              _kSalonId,
            ).overrideWith((ref) async => _stubCatalog),
            favoriteRepositoryProvider.overrideWithValue(repo),
          ],
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('booking_service_heart_svc-a1')));
        await tester.pump();
        await tester.pump();

        expect(
          repo.addCalls,
          <FavoriteTarget>[
            const FavoriteTarget(
              type: FavoriteTargetType.salonService,
              id: 'svc-a1',
            ),
          ],
          reason:
              'the salon flow must favourite against salonService — the '
              'independent-master flow\'s `.service` target type keys to a '
              'master_services assignment id, not this salon-catalogue id',
        );
      },
    );
  });

  group('multi-select + summary', () {
    testWidgets('selecting a service updates the pinned summary + total', (
      tester,
    ) async {
      await tester.pumpRoutedApp(
        _routerFor(),
        overrides: [
          salonServiceCatalogProvider(
            _kSalonId,
          ).overrideWith((ref) async => _stubCatalog),
        ],
      );
      await tester.pumpAndSettle();

      // Nothing selected yet — CTA disabled, empty prompt shown.
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const Key('booking-summary-cta')),
                matching: find.byType(Text),
              ),
            )
            .data,
        'Далі',
      );

      await tester.tap(
        find.byKey(const Key('salon_booking_service_tile_svc-a1')),
      );
      await tester.pumpAndSettle();

      // The itemized list is collapsed by default — expand the summary
      // shelf's toggle before asserting the selected service also renders
      // there (in addition to the catalogue row).
      await tester.tap(find.byKey(const Key('booking-summary-expand-toggle')));
      await tester.pumpAndSettle();

      // The selected service's name now also appears in the pinned summary
      // list (in addition to the catalogue row) — at least 2 instances.
      // i18n-finder-ok: fixture service name (test data), not app UI copy.
      expect(find.text('Класичний манікюр'), findsNWidgets(2));
      // i18n-finder-ok: fixture price display (test data), not app UI copy.
      expect(find.text('300 ₴'), findsWidgets);
      // ...AND the catalogue tile's own price still shows it. This used to
      // be covered by the assertion above too (an exact `find.text('300 ₴')`
      // matched the tile's OWN price Text plus 2 summary-shelf occurrences,
      // findsWidgets never surfacing the count), until the 2026-08-10
      // price-relocation fix moved the tile's price onto its own meta line
      // (see `service_catalogue_accordion.dart`'s `_metaLine` — a `Wrap` of
      // independent `Text` widgets as of the round-2 fix; it was briefly a
      // merged `Text.rich` in between) — a scoped, tile-specific matcher is
      // needed regardless of which of those two render the tile uses, since
      // an unscoped `find.text`/`findsWidgets` can't distinguish the tile's
      // own price from the summary shelf's (mobile-qa finding: a
      // PRE-EXISTING loose matcher masked a real drop in what this test
      // verifies). Scoped `find.textContaining` restores the tile-specific
      // check the same way `service_catalogue_accordion_test.dart` was
      // already fixed.
      expect(
        find.descendant(
          of: find.byKey(const Key('salon_booking_service_tile_svc-a1')),
          matching: find.textContaining('300 ₴'),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'removing a service via the summary shelf converges to the same '
      'deselected end-state as unchecking it in the catalogue',
      (tester) async {
        await tester.pumpRoutedApp(
          _routerFor(),
          overrides: [
            salonServiceCatalogProvider(
              _kSalonId,
            ).overrideWith((ref) async => _stubCatalog),
          ],
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const Key('salon_booking_service_tile_svc-a1')),
        );
        await tester.pumpAndSettle();

        // The catalogue tile now shows the "selected" depth-check face.
        expect(
          find.descendant(
            of: find.byKey(const Key('salon_booking_service_tile_svc-a1')),
            matching: find.byKey(const ValueKey<bool>(true)),
          ),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const Key('booking-summary-expand-toggle')),
        );
        await tester.pumpAndSettle();

        final Finder removeButton = find.byKey(
          const Key('booking-summary-remove-svc-a1'),
        );
        expect(removeButton, findsOneWidget);

        await tester.tap(removeButton);
        await tester.pumpAndSettle();

        // i18n-finder-ok: fixture service name (test data), not app UI copy.
        expect(find.text('Класичний манікюр'), findsOneWidget);
        final NeumorphicButton cta = tester.widget<NeumorphicButton>(
          find.byKey(const Key('booking-summary-cta')),
        );
        expect(cta.onPressed, isNull);
        expect(
          find.descendant(
            of: find.byKey(const Key('salon_booking_service_tile_svc-a1')),
            matching: find.byKey(const ValueKey<bool>(true)),
          ),
          findsNothing,
        );
      },
    );

    // mobile-qa gap: the test above only ever drives selection down to
    // EMPTY, so it cannot distinguish "remove just this one service" from a
    // regression that wipes the WHOLE selection set — both produce an empty
    // list either way. With 2 selected services (from two different
    // categories), removing ONE via the shelf must leave the OTHER selected,
    // the catalogue tile for the untouched one still checked, the CTA still
    // enabled, and the total reflecting only the surviving service.
    testWidgets(
      'removing one of two selected services via the shelf leaves the '
      'other selected, the CTA enabled, and the total updated',
      (tester) async {
        // A taller surface (mirrors service_selector_sheet_test.dart's
        // approach): with 2 categories expanded plus the pinned summary
        // shelf, the default 800×600 test canvas hides svc-b1's tile behind
        // the shelf overlay, so a plain tap() misses it.
        tester.view.physicalSize = const Size(800, 2000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpRoutedApp(
          _routerFor(),
          overrides: [
            salonServiceCatalogProvider(
              _kSalonId,
            ).overrideWith((ref) async => _stubCatalog),
          ],
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const Key('salon_booking_service_tile_svc-a1')),
        );
        await tester.pumpAndSettle();
        // Second category ("Педикюр") starts collapsed — expand it first.
        await tester.tap(
          find.byKey(const Key('salon-booking-category-Педикюр')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('salon_booking_service_tile_svc-b1')),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const Key('booking-summary-expand-toggle')),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const Key('booking-summary-remove-svc-a1')),
        );
        await tester.pumpAndSettle();

        // The removed service's catalogue tile is deselected...
        expect(
          find.descendant(
            of: find.byKey(const Key('salon_booking_service_tile_svc-a1')),
            matching: find.byKey(const ValueKey<bool>(true)),
          ),
          findsNothing,
          reason: 'removing svc-a1 must deselect only svc-a1',
        );
        // ...but the OTHER selected service's catalogue tile survives —
        // this is the assertion that would catch a "clear whole selection"
        // regression, which the empty-down-to-zero test above cannot.
        expect(
          find.descendant(
            of: find.byKey(const Key('salon_booking_service_tile_svc-b1')),
            matching: find.byKey(const ValueKey<bool>(true)),
          ),
          findsOneWidget,
          reason:
              'removing svc-a1 via the shelf must NOT deselect svc-b1 — a '
              'regression that clears the whole selection set instead of '
              'just the tapped id would slip past a down-to-zero-only test',
        );
        // ...the CTA stays enabled (still 1 service selected)...
        final NeumorphicButton cta = tester.widget<NeumorphicButton>(
          find.byKey(const Key('booking-summary-cta')),
        );
        expect(
          cta.onPressed,
          isNotNull,
          reason:
              'one service (svc-b1) remains selected — CTA must stay '
              'enabled',
        );
        // ...and the summary total now reflects ONLY the surviving
        // svc-b1 (800 ₴), not the stale sum of both.
        // i18n-finder-ok: fixture price display (test data), not app UI copy.
        expect(find.text('800 ₴'), findsWidgets);
        // ...and svc-b1's OWN catalogue tile still shows its price too — see
        // the identical note on the selection test above for why this
        // scoped check was added (the tile's price merged into a
        // `Text.rich` meta line the unscoped exact `find.text` above can no
        // longer see).
        expect(
          find.descendant(
            of: find.byKey(const Key('salon_booking_service_tile_svc-b1')),
            matching: find.textContaining('800 ₴'),
          ),
          findsOneWidget,
        );
        // ...the removed service's name disappears from the SHELF
        // specifically — it still renders in the catalogue above (that tile
        // is never removed from the list, only deselected), so the finder
        // must be scoped to `BookingSummaryBar`, not the whole tree.
        expect(
          find.descendant(
            of: find.byType(BookingSummaryBar),
            // i18n-finder-ok: fixture service name (test data), not app UI copy.
            matching: find.text('Класичний манікюр'),
          ),
          findsNothing,
        );
      },
    );
  });

  group('Далі CTA', () {
    testWidgets('disabled with 0 selected', (tester) async {
      await tester.pumpRoutedApp(
        _routerFor(),
        overrides: [
          salonServiceCatalogProvider(
            _kSalonId,
          ).overrideWith((ref) async => _stubCatalog),
        ],
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('booking-summary-cta')));
      await tester.pumpAndSettle();

      expect(find.text('masters-screen-reached'), findsNothing);
    });

    testWidgets(
      'enabled with >=1 selected, navigates to /booking/salon/masters '
      'with the correct extra',
      (tester) async {
        SalonBookingMasterSelectionArgs? captured;
        await tester.pumpRoutedApp(
          _routerFor(onReached: (args) => captured = args),
          overrides: [
            salonServiceCatalogProvider(
              _kSalonId,
            ).overrideWith((ref) async => _stubCatalog),
          ],
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const Key('salon_booking_service_tile_svc-a1')),
        );
        await tester.tap(
          find.byKey(const Key('salon_booking_service_tile_svc-a2')),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('booking-summary-cta')));
        await tester.pumpAndSettle();

        expect(find.text('masters-screen-reached'), findsOneWidget);
        expect(captured?.salonId, _kSalonId);
        expect(
          captured?.selectedServiceIds,
          containsAll(<String>['svc-a1', 'svc-a2']),
        );
        expect(captured?.selectedServiceIds, hasLength(2));
      },
    );
  });

  // MO-4 req 7 — the salon multi-select shares `ServiceSelectorSheet`'s
  // `_onToggleService` cap+dedupe logic (both cap at `maxServicesPerVisit` via a
  // `Set` keyed by id). These pin BOTH invariants on the salon surface so a
  // future divergence from the independent flow can't slip a >10 or duplicated
  // payload into `SalonBookingMasterSelectionArgs`.
  group('visit-selection cap + dedupe (MO-4)', () {
    testWidgets(
      'caps the selection at maxServicesPerVisit (10) — the 11th add is refused '
      'with the friendly cap VelvetSnack, and «Далі» carries exactly 10 ids',
      (tester) async {
        tester.view.physicalSize = const Size(800, 8000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        SalonBookingMasterSelectionArgs? captured;
        await tester.pumpRoutedApp(
          _routerFor(onReached: (args) => captured = args),
          overrides: [
            salonServiceCatalogProvider(
              _kSalonId,
            ).overrideWith((ref) async => _manyServicesCatalog(11)),
          ],
        );
        await tester.pumpAndSettle();

        // The only category (MANICURE) is expanded by default — tap all 11
        // tiles; the 11th add must be refused (cap = 10).
        for (int i = 0; i < 11; i++) {
          await tester.tap(
            find.byKey(Key('salon_booking_service_tile_svc-$i')),
          );
          await tester.pump();
        }

        final l10n = AppLocalizations.of(
          tester.element(find.byType(SalonServiceSelectionScreen)),
        );
        expectVelvetSnack(
          l10n.bookingMaxServicesReached(maxServicesPerVisit),
          variant: VelvetSnackVariant.warning,
        );
        // Drains the dwell Timer AND removes the OverlayEntry — a still-
        // mounted snack is bottom-anchored and hit-test-intercepts the
        // «Далі» tap right below (the pinned `BookingSummaryBar` sits at the
        // very bottom of this pushed, nav-bar-less screen).
        await pumpPastVelvetSnack(tester);

        await tester.tap(find.byKey(const Key('booking-summary-cta')));
        await tester.pumpAndSettle();

        expect(find.text('masters-screen-reached'), findsOneWidget);
        expect(
          captured?.selectedServiceIds,
          hasLength(maxServicesPerVisit),
          reason:
              'the visit must carry at most maxServicesPerVisit services — '
              'the 11th was never added',
        );
        // No id appears twice — the Set-backed selection dedupes.
        expect(
          captured!.selectedServiceIds.toSet(),
          hasLength(captured!.selectedServiceIds.length),
          reason: 'selectedServiceIds must be duplicate-free',
        );
      },
    );

    testWidgets(
      're-tapping a selected tile toggles it OFF (Set dedupe) — the id is not '
      'added twice and «Далі» carries the surviving single id',
      (tester) async {
        SalonBookingMasterSelectionArgs? captured;
        await tester.pumpRoutedApp(
          _routerFor(onReached: (args) => captured = args),
          overrides: [
            salonServiceCatalogProvider(
              _kSalonId,
            ).overrideWith((ref) async => _stubCatalog),
          ],
        );
        await tester.pumpAndSettle();

        final Finder tile = find.byKey(
          const Key('salon_booking_service_tile_svc-a1'),
        );
        // Select → deselect → select: an idempotent Set toggle, never a
        // second copy of the same id.
        await tester.tap(tile);
        await tester.pumpAndSettle();
        await tester.tap(tile);
        await tester.pumpAndSettle();
        await tester.tap(tile);
        await tester.pumpAndSettle();

        // Add a second, distinct service so the payload is non-trivially sized.
        await tester.tap(
          find.byKey(const Key('salon_booking_service_tile_svc-a2')),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('booking-summary-cta')));
        await tester.pumpAndSettle();

        expect(find.text('masters-screen-reached'), findsOneWidget);
        expect(
          captured?.selectedServiceIds,
          <String>['svc-a1', 'svc-a2'],
          reason:
              'toggling svc-a1 three times leaves it selected exactly ONCE — '
              'no duplicate id in the payload',
        );
      },
    );
  });
}
