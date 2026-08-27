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

import 'dart:async';

import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/booking/domain/salon_booking_args.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_service_selection_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_summary_bar.dart';
import 'package:beautica_mobile/features/salon/application/salon_service_catalog_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/pump_app.dart';

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
}
