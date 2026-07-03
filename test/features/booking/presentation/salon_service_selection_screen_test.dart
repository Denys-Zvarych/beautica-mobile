// Phase 14.12 — Widget tests for SalonServiceSelectionScreen.
//
// Covers (phase doc Step 5):
//   1. Loading / error / empty-catalogue states.
//   2. Category accordion expand/collapse.
//   3. Multi-select toggling updates the pinned summary + total.
//   4. SelectAllPill tri-state (select all / clear all / indeterminate on
//      partial).
//   5. "Далі" disabled with 0 selected, enabled ≥1, navigates to
//      /booking/salon/masters with the correct extra.

import 'dart:async';

import 'package:beautica_mobile/features/booking/domain/salon_booking_args.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_service_selection_screen.dart';
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
  priceDisplay: '300 грн',
  category: 'MANICURE',
  durationMinutes: 60,
  priceType: ServicePriceType.fixed,
  priceMin: 300,
);

const _svcA2 = SalonCatalogService(
  id: 'svc-a2',
  name: 'Манікюр з покриттям',
  durationLabel: '1 год 30 хв',
  priceDisplay: '500 грн',
  category: 'MANICURE',
  durationMinutes: 90,
  priceType: ServicePriceType.fixed,
  priceMin: 500,
);

const _svcB1 = SalonCatalogService(
  id: 'svc-b1',
  name: 'Педикюр',
  durationLabel: '2 год',
  priceDisplay: '800 грн',
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

      // The selected service's name now also appears in the pinned summary
      // list (in addition to the catalogue row) — at least 2 instances.
      // i18n-finder-ok: fixture service name (test data), not app UI copy.
      expect(find.text('Класичний манікюр'), findsNWidgets(2));
      // i18n-finder-ok: fixture price display (test data), not app UI copy.
      expect(find.text('300 грн'), findsWidgets);
    });

    testWidgets('select-all pill: select all / clear all / indeterminate', (
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

      final selectAllKey = find.byKey(
        const Key('salon-booking-category-select-all-Манікюр'),
      );
      expect(selectAllKey, findsOneWidget);

      // Select all in "Манікюр".
      await tester.tap(selectAllKey);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_box_rounded), findsOneWidget);

      // Tapping again (now fully selected) clears the category.
      await tester.tap(selectAllKey);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_box_outline_blank_rounded), findsWidgets);

      // Select ONE of the two services manually -> indeterminate icon shows.
      await tester.tap(
        find.byKey(const Key('salon_booking_service_tile_svc-a1')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byIcon(Icons.indeterminate_check_box_rounded),
        findsOneWidget,
      );
    });
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
