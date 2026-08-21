// Phase 264 — Widget tests for WalkInServiceStepScreen, the second screen of
// the routed walk-in chain (`/master/bookings/new/services`).
//
// Covers the phase doc's "Service step" test cases (10-14):
//   10. should_selectThreeServices_inTapOrder
//   11. should_warnAndRefuse_when_eleventhServiceTapped — maxServicesPerVisit
//   12. should_allowDeselect_when_atCap
//   13. should_seedSlotPickerArgs_when_nextTapped
//   14. should_notRenderStepIndicator_when_serviceStepShown
//
// Plus D8 coverage unique to this screen (the wizard's shared
// masterProfileProvider loading/error states, now owned by THIS screen
// instead of the retiring wizard's root).
//
// Strategy mirrors `master_create_booking_screen_test.dart`'s former
// service-step group: a test-local bare GoRouter (no auth guard), fake
// `MasterProfile` / `ServicesList` notifier overrides.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/booking/data/slot_repository.dart'
    show maxServicesPerVisit;
import 'package:beautica_mobile/features/booking/domain/booking_slot_picker_args.dart';
import 'package:beautica_mobile/features/booking/domain/create_master_booking_request.dart'
    show WalkInGuest;
import 'package:beautica_mobile/features/booking/presentation/walk_in_service_step_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_wizard_steps.dart'
    show StepIndicator;
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_notifier.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/pump_app.dart';
import '../../../helpers/velvet_snack_matchers.dart';

const Master _kMaster = Master(
  id: 'master-1',
  firstName: 'Олена',
  lastName: 'Ковальчук',
  reviewCount: 0,
  type: MasterType.independentMaster,
);

const WalkInGuest _kGuest = WalkInGuest(
  name: 'Марина',
  surname: 'Кравчук',
  phone: '+380501234567',
);

const MasterService _kService1 = MasterService(
  id: 'svc-1',
  serviceDefId: 'def-1',
  name: 'Манікюр',
  durationMinutes: 60,
  priceMin: 500,
  priceDisplay: '500 ₴',
  category: 'NAILS',
);
const MasterService _kService2 = MasterService(
  id: 'svc-2',
  serviceDefId: 'def-2',
  name: 'Педикюр',
  durationMinutes: 45,
  priceMin: 400,
  priceDisplay: '400 ₴',
  category: 'NAILS',
);
const MasterService _kService3 = MasterService(
  id: 'svc-3',
  serviceDefId: 'def-3',
  name: 'Покриття гель-лак',
  durationMinutes: 30,
  priceMin: 300,
  priceDisplay: '300 ₴',
  category: 'NAILS',
);

/// `maxServicesPerVisit` fixture services in one category, for the cap test.
List<MasterService> _manyServices(int n) => <MasterService>[
  for (int i = 0; i < n; i++)
    MasterService(
      id: 'svc-cap-$i',
      serviceDefId: 'def-cap-$i',
      name: 'Послуга $i',
      durationMinutes: 30,
      priceMin: 100,
      priceDisplay: '100 ₴',
      category: 'NAILS',
    ),
];

class _FakeMasterProfile extends MasterProfile {
  @override
  Future<Master> build() async => _kMaster;
}

class _FailingMasterProfile extends MasterProfile {
  @override
  Future<Master> build() async => throw const NetworkFailure();
}

class _ForeverLoadingMasterProfile extends MasterProfile {
  @override
  Future<Master> build() => Completer<Master>().future;
}

class _FakeServicesList extends ServicesList {
  _FakeServicesList([this._services = const <MasterService>[_kService1]]);

  final List<MasterService> _services;

  @override
  Future<List<MasterService>> build() async => _services;
}

/// mobile-qa gap re-homed from the retired wizard's own "service step
/// loading/error" group — `ServiceStep`'s OWN `servicesListProvider` states
/// (one provider layer below `masterProfileProvider`), reused verbatim by
/// this screen.
class _ForeverLoadingServicesList extends ServicesList {
  @override
  Future<List<MasterService>> build() =>
      Completer<List<MasterService>>().future;
}

class _FailingServicesList extends ServicesList {
  @override
  Future<List<MasterService>> build() async => throw const NetworkFailure();
}

/// Captures every `extra` pushed to [RouteNames.bookingSlots].
final List<Object?> _pushedExtras = <Object?>[];

GoRouter _router() {
  _pushedExtras.clear();
  return GoRouter(
    initialLocation: RouteNames.masterBookingNewServices,
    routes: <RouteBase>[
      GoRoute(
        path: RouteNames.masterBookingNewServices,
        builder: (context, state) =>
            const WalkInServiceStepScreen(guest: _kGuest),
      ),
      GoRoute(
        path: RouteNames.bookingSlots,
        builder: (context, state) {
          _pushedExtras.add(state.extra);
          return const Scaffold(body: SizedBox.shrink());
        },
      ),
    ],
  );
}

Future<GoRouter> _pump(
  WidgetTester tester, {
  List<MasterService> services = const <MasterService>[
    _kService1,
    _kService2,
    _kService3,
  ],
  MasterProfile Function() masterProfileOverride = _FakeMasterProfile.new,
  ServicesList Function()? servicesListOverride,
  bool settle = true,
}) async {
  final GoRouter router = _router();
  await tester.pumpRoutedApp(
    router,
    overrides: <Object>[
      masterProfileProvider.overrideWith(masterProfileOverride),
      servicesListProvider.overrideWith(
        servicesListOverride ?? () => _FakeServicesList(services),
      ),
      approvedCategoriesProvider.overrideWith(
        (ref) async => const <ServiceCategoryOption>[],
      ),
    ],
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    // A never-resolving `masterProfileProvider` override (`_
    // ForeverLoadingMasterProfile`) would hang `pumpAndSettle` forever —
    // pump a bounded number of frames instead, mirroring the retired
    // wizard's own loading-state test.
    await tester.pump();
    await tester.pump();
  }
  return router;
}

void main() {
  testWidgets(
    'should_selectThreeServices_inTapOrder — tapping svc-2 then svc-1 then '
    'svc-3 renders them in TAP order in the summary shelf',
    (tester) async {
      await _pump(tester);

      await tester.tap(find.byKey(const Key('mcb_service_card_svc-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('mcb_service_card_svc-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('mcb_service_card_svc-3')));
      await tester.pumpAndSettle();

      // Assert order via the eventual push instead of scraping shelf text —
      // exercised together with case 13 below (same drive), but pinned here
      // independently too.
      await tester.tap(find.byKey(const Key('booking-summary-cta')));
      await tester.pumpAndSettle();

      final BookingSlotPickerArgs args =
          _pushedExtras.single! as BookingSlotPickerArgs;
      expect(args.services.map((MasterService s) => s.id).toList(), <String>[
        'svc-2',
        'svc-1',
        'svc-3',
      ]);
    },
  );

  testWidgets('should_warnAndRefuse_when_eleventhServiceTapped — the '
      'maxServicesPerVisit cap refuses an 11th add with a warning snack', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 8000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final List<MasterService> many = _manyServices(maxServicesPerVisit + 1);
    await _pump(tester, services: many);

    for (int i = 0; i < maxServicesPerVisit; i++) {
      await tester.tap(find.byKey(Key('mcb_service_card_svc-cap-$i')));
      await tester.pump();
    }
    // The 11th tap must be refused.
    await tester.tap(
      find.byKey(const Key('mcb_service_card_svc-cap-$maxServicesPerVisit')),
    );
    await pumpVelvetSnackIn(tester);

    final l10n = AppLocalizations.of(
      tester.element(find.byType(WalkInServiceStepScreen)),
    );
    expectVelvetSnack(
      l10n.bookingMaxServicesReached(maxServicesPerVisit),
      variant: VelvetSnackVariant.warning,
    );
    await pumpPastVelvetSnack(tester);

    await tester.tap(find.byKey(const Key('booking-summary-cta')));
    await tester.pumpAndSettle();
    final BookingSlotPickerArgs args =
        _pushedExtras.single! as BookingSlotPickerArgs;
    expect(args.services, hasLength(maxServicesPerVisit));
  });

  testWidgets(
    'should_allowDeselect_when_atCap — a removal is never cap-blocked even '
    'while already at the maximum',
    (tester) async {
      tester.view.physicalSize = const Size(800, 8000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final List<MasterService> many = _manyServices(maxServicesPerVisit);
      await _pump(tester, services: many);

      for (int i = 0; i < maxServicesPerVisit; i++) {
        await tester.tap(find.byKey(Key('mcb_service_card_svc-cap-$i')));
        await tester.pumpAndSettle();
      }
      // Deselect one — must succeed without any snack.
      await tester.tap(find.byKey(const Key('mcb_service_card_svc-cap-0')));
      await tester.pumpAndSettle();
      expect(find.byType(VelvetSnack), findsNothing);

      await tester.tap(find.byKey(const Key('booking-summary-cta')));
      await tester.pumpAndSettle();
      final BookingSlotPickerArgs args =
          _pushedExtras.single! as BookingSlotPickerArgs;
      expect(args.services, hasLength(maxServicesPerVisit - 1));
    },
  );

  testWidgets('should_seedSlotPickerArgs_when_nextTapped — the pushed '
      'BookingSlotPickerArgs carries the guest, hides the master identity, '
      'and the tap-ordered services', (tester) async {
    await _pump(tester);

    await tester.tap(find.byKey(const Key('mcb_service_card_svc-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('booking-summary-cta')));
    await tester.pumpAndSettle();

    final BookingSlotPickerArgs args =
        _pushedExtras.single! as BookingSlotPickerArgs;
    expect(args.masterId, _kMaster.id);
    expect(args.master, _kMaster);
    expect(args.services.single.id, 'svc-1');
    expect(args.guest, _kGuest);
    expect(args.hideMasterIdentity, isTrue);
  });

  testWidgets('should_notRenderStepIndicator_when_serviceStepShown — the 4-dot '
      'indicator is dropped from the routed walk-in chain (brief decision 4)', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.byType(StepIndicator), findsNothing);
  });

  testWidgets(
    'renders the spinner while masterProfileProvider is loading (D8 — this '
    'screen, not the guest step, now owns the master read)',
    (tester) async {
      await _pump(
        tester,
        masterProfileOverride: _ForeverLoadingMasterProfile.new,
        settle: false,
      );
      expect(
        find.byKey(const Key('walk-in-service-master-loading')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'renders an error state + retry when masterProfileProvider fails',
    (tester) async {
      await _pump(tester, masterProfileOverride: _FailingMasterProfile.new);
      expect(
        find.byKey(const Key('walk-in-service-master-error')),
        findsOneWidget,
      );
    },
  );

  // Re-homed from the retired wizard's own "service step loading/error"
  // group — `ServiceStep`'s OWN `servicesListProvider` states, one provider
  // layer below `masterProfileProvider`, reused verbatim by this screen.
  testWidgets('renders the spinner while servicesListProvider is loading', (
    tester,
  ) async {
    await _pump(
      tester,
      servicesListOverride: _ForeverLoadingServicesList.new,
      settle: false,
    );
    expect(
      find.byKey(const Key('master-create-booking-service-loading')),
      findsOneWidget,
    );
  });

  testWidgets(
    'renders ErrorState with a working retry when servicesListProvider fails',
    (tester) async {
      await _pump(tester, servicesListOverride: _FailingServicesList.new);
      expect(
        find.byKey(const Key('master-create-booking-service-error')),
        findsOneWidget,
      );
      final Finder retryBtn = find.byKey(const Key('error_state_retry_button'));
      expect(retryBtn, findsOneWidget);
      await tester.tap(retryBtn);
      await tester.pumpAndSettle();
      expect(find.byType(ErrorState), findsOneWidget);
    },
  );
}
