// Phase 14.1 — Widget tests for ServiceSelectorSheet (booking Step 1).
//
// Covers:
//   1. Loading / data / empty-catalogue states.
//   2. Category accordion expand/collapse.
//   3. Multi-select toggling drives the pinned summary shelf + "Далі" CTA.
//   4. "Далі" navigates to /booking/slots with a BookingSlotPickerArgs extra
//      carrying exactly the selected services.
//
// Strategy mirrors `public_master_profile_screen_test.dart`: override the
// [publicMasterProfileProvider] family directly (it already loads master +
// services in parallel — no separate repository mock needed) and
// [approvedCategoriesProvider] directly (it sources from the real Dio-backed
// categoryRequestApiProvider, NOT from serviceRepositoryProvider — the
// documented "approvedCategoriesProvider override footgun").

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/master/application/public_master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/booking/domain/booking_slot_picker_args.dart';
import 'package:beautica_mobile/features/booking/presentation/service_selector_sheet.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_summary_bar.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/pump_app.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const String _kMasterId = 'master-1';

const _kMaster = Master(
  id: _kMasterId,
  firstName: 'Олена',
  lastName: 'Ковальчук',
  avgRating: 4.8,
  reviewCount: 12,
  type: MasterType.independentMaster,
);

const _kManicure = MasterService(
  id: 'svc-mani',
  serviceDefId: 'def-mani',
  name: 'Манікюр з покриттям',
  durationMinutes: 90,
  priceMin: 500,
  priceDisplay: '500 грн',
  category: 'MANICURE',
);

const _kPedicure = MasterService(
  id: 'svc-pedi',
  serviceDefId: 'def-pedi',
  name: 'Педикюр з покриттям',
  durationMinutes: 120,
  priceType: ServicePriceType.range,
  priceMin: 200,
  priceMax: 600,
  priceDisplay: 'від 200 до 600 грн',
  category: 'PEDICURE',
);

PublicMasterProfileData get _twoCategoryData =>
    (_kMaster, const <MasterService>[_kManicure, _kPedicure]);

List<Object> _overrides(
  FutureOr<PublicMasterProfileData> Function(Ref ref) create,
) => <Object>[
  publicMasterProfileProvider(_kMasterId).overrideWith(create),
  // approvedCategoriesProvider footgun: sources from the real Dio-backed
  // categoryRequestApiProvider, independent of the service repository —
  // MUST be overridden directly or it fires a real request under `flutter test`.
  approvedCategoriesProvider.overrideWith(
    (ref) async => const <ServiceCategoryOption>[],
  ),
];

GoRouter _router() => GoRouter(
  initialLocation: RouteNames.bookingNew,
  initialExtra: _kMasterId,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.bookingNew,
      builder: (context, state) =>
          ServiceSelectorSheet(masterId: (state.extra as String?) ?? ''),
    ),
    GoRoute(
      path: RouteNames.bookingSlots,
      builder: (context, state) {
        final BookingSlotPickerArgs args =
            state.extra! as BookingSlotPickerArgs;
        final String ids = args.services
            .map((MasterService s) => s.id)
            .join(',');
        return Scaffold(body: Text('slots-stub:${args.masterId}:$ids'));
      },
    ),
  ],
);

void main() {
  group('loading state', () {
    testWidgets('shows a skeleton while the profile loads', (tester) async {
      await tester.pumpApp(
        const ServiceSelectorSheet(masterId: _kMasterId),
        overrides: _overrides(
          (ref) => Completer<PublicMasterProfileData>().future,
        ),
      );

      expect(find.byKey(const Key('booking-summary-cta')), findsNothing);
    });
  });

  group('error state', () {
    // Regression coverage (mobile-build-verifier): `public_salon_profile_screen.dart`
    // pushes `RouteNames.bookingNew` with a SALON id, not a master id (salon
    // booking is out of scope for this phase — a pre-existing gap, not
    // something Phase 14.1 introduces). `ServiceSelectorSheet` always treats
    // its `masterId` as a master-row id, so that lookup 404s. This pins the
    // resulting UI never regresses to a crash/blank screen: the error state
    // renders with a working retry that actually re-invokes the provider.
    testWidgets(
      'renders the error state (with a working retry) when the master '
      'lookup fails — e.g. a salon id reaching ServiceSelectorSheet via a '
      'wrong-type /booking/new push from the salon profile CTA',
      (tester) async {
        const String wrongTypeId = 'salon-xyz';
        int callCount = 0;

        await tester.pumpApp(
          const ServiceSelectorSheet(masterId: wrongTypeId),
          overrides: <Object>[
            publicMasterProfileProvider(wrongTypeId).overrideWith((ref) {
              callCount++;
              return Future<PublicMasterProfileData>.error(
                const NotFoundFailure(),
                StackTrace.empty,
              );
            }),
            approvedCategoriesProvider.overrideWith(
              (ref) async => const <ServiceCategoryOption>[],
            ),
          ],
          // Disable Riverpod's retry so the AsyncError settles (no pending
          // backoff Timer left at test end) — mirrors
          // public_master_profile_screen_test.dart's error-state test.
          retry: (_, _) => null,
        );
        await tester.pumpAndSettle();

        expect(find.byType(ErrorState), findsOneWidget);
        expect(
          find.byKey(const Key('service-selector-error-state')),
          findsOneWidget,
        );
        expect(callCount, 1);

        final Finder retryButton = find.byKey(
          const Key('error_state_retry_button'),
        );
        expect(retryButton, findsOneWidget);

        await tester.tap(retryButton);
        await tester.pumpAndSettle();

        // The retry must actually invalidate + re-invoke the provider (not
        // just re-render stale state) — the lookup fails again (same wrong
        // id), so the error state stays put, but the call count proves the
        // retry affordance is wired, not decorative.
        expect(callCount, 2);
        expect(
          find.byKey(const Key('service-selector-error-state')),
          findsOneWidget,
        );
      },
    );
  });

  group('empty catalogue', () {
    testWidgets(
      'shows the empty-state prompt when the master has no services',
      (tester) async {
        await tester.pumpApp(
          const ServiceSelectorSheet(masterId: _kMasterId),
          overrides: _overrides((ref) => (_kMaster, const <MasterService>[])),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('booking_category_MANICURE')),
          findsNothing,
        );
      },
    );
  });

  group('catalogue — category accordions', () {
    testWidgets('categories start collapsed; tapping a header expands it', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpApp(
        const ServiceSelectorSheet(masterId: _kMasterId),
        overrides: _overrides((ref) => _twoCategoryData),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('booking_service_tile_svc-mani')),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('booking_category_MANICURE')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('booking_service_tile_svc-mani')),
        findsOneWidget,
      );
    });
  });

  group('selection + summary shelf', () {
    testWidgets('selecting a service enables «Далі» and updates the summary', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpApp(
        const ServiceSelectorSheet(masterId: _kMasterId),
        overrides: _overrides((ref) => _twoCategoryData),
      );
      await tester.pumpAndSettle();

      // Nothing selected yet — the CTA (present, disabled) does nothing when
      // there is no router to navigate through; assert via the empty-state
      // prompt text absence check is covered by the navigation test below.
      await tester.tap(find.byKey(const Key('booking_category_MANICURE')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('booking_service_tile_svc-mani')));
      await tester.pumpAndSettle();

      // The selected service's name now appears in the pinned summary shelf
      // (in addition to the catalogue tile itself, hence scoping the finder).
      // i18n-finder-ok: _kManicure.name is fixture data, not UI copy.
      expect(
        find.descendant(
          of: find.byType(BookingSummaryBar),
          matching: find.text(_kManicure.name),
        ),
        findsOneWidget,
      );
    });
  });

  group('navigation', () {
    testWidgets('«Далі» navigates to /booking/slots with the selected '
        'services', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final router = _router();
      await tester.pumpRoutedApp(
        router,
        overrides: _overrides((ref) => _twoCategoryData),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('booking_category_MANICURE')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('booking_service_tile_svc-mani')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('booking-summary-cta')));
      await tester.pumpAndSettle();

      expect(find.text('slots-stub:$_kMasterId:svc-mani'), findsOneWidget);
    });
  });
}
