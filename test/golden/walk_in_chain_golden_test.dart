// mobile-qa (Track 258-265 audit, 2026-08-21) — visual regression coverage
// for the FIRST TWO screens of the routed walk-in chain:
// [WalkInGuestStepScreen] (`/master/bookings/new`) and
// [WalkInServiceStepScreen] (`/master/bookings/new/services`).
//
// WHY THIS FILE EXISTS. Before Phase 264, these two layouts (`ClientStep` /
// `ServiceStep`) were hosted inside the single-screen wizard
// (`master_create_booking_screen.dart`), and
// `master_create_booking_wizard_golden_test.dart` photographed them as its
// `client` / `service` cells — 12 of its 30 PNGs. Phase 265 deleted that
// wizard AND its golden file outright (see `booking_slot_flow_golden_test
// .dart`'s own header, D4: "the ... 30 of
// `master_create_booking_wizard_golden_test.dart` ... [are] untouched" — true
// only in the sense that nothing EDITED them; they were deleted alongside the
// screen). Phase 265's own replacement golden file
// (`booking_slot_flow_golden_test.dart`) deliberately scopes its 4 new
// walk-in cells to `slot-date`/`slot-time`/`confirm`/`success` only (D6) —
// the two NEW screens that host `ClientStep`/`ServiceStep` in this chain
// (`WalkInGuestStepScreen`, `WalkInServiceStepScreen`) were left with ZERO
// golden coverage, and the salon wizard's own use of the same two widgets
// (`salon_create_booking_screen.dart`) has never had golden coverage of its
// own either. Net effect: two screens actual master users see on every
// walk-in booking had a visual-regression tripwire until this diff, and lost
// it — mobile-qa M8 gap, not coverage-theater (these are currently
// UNPHOTOGRAPHED production screens, not a redundant re-shoot of an already
// -covered widget).
//
// SCOPE — deliberately narrow, mirroring the retired wizard's own "one state
// per step" cell count (not the 4-state loading/loaded/empty/error matrix
// `booking_slot_flow_golden_test.dart` uses for the reused CLIENT screens):
//   • `walk-in-guest`            — WalkInGuestStepScreen, empty form.
//   • `walk-in-service`          — WalkInServiceStepScreen, catalogue loaded,
//                                   nothing selected yet (summary shelf empty).
//   • `walk-in-service-selected` — same, with two services tapped (summary
//                                   shelf populated) — the ONE state the
//                                   empty-selection cell above cannot show.
// Loading/error states for both screens are already pinned as WIDGET tests
// (`walk_in_guest_step_screen_test.dart`, `walk_in_service_step_screen_test
// .dart`) — a golden adds nothing there beyond what those already assert, so
// they are not duplicated here (avoiding exactly the coverage-theater this
// audit was warned against).
//
// Matrix: 3 cells x {320, 360, 414} dp x {textScale 1.0, 1.3} = 18 PNGs,
// freshly generated (this is a NEW file for NEW screens — no existing
// baseline to protect, unlike `booking_slot_flow_golden_test.dart`'s locked
// CLIENT cells, which this file never touches).

import 'package:beautica_mobile/features/booking/domain/create_master_booking_request.dart'
    show WalkInGuest;
import 'package:beautica_mobile/features/booking/presentation/walk_in_guest_step_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/walk_in_service_step_screen.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/golden_pump.dart';

// ---------------------------------------------------------------------------
// Fixtures — small, self-contained; not shared with other golden files so
// this file's cells never drift if a sibling's fixtures change.
// ---------------------------------------------------------------------------

const Master _kMaster = Master(
  id: 'master-1',
  firstName: 'Олена',
  lastName: 'Ковальчук',
  reviewCount: 0,
  type: MasterType.independentMaster,
);

const MasterService _kService1 = MasterService(
  id: 'svc-1',
  serviceDefId: 'def-1',
  name: 'Манікюр класичний',
  durationMinutes: 60,
  priceMin: 500,
  priceDisplay: '500 ₴',
  category: 'NAILS',
);

const MasterService _kService2 = MasterService(
  id: 'svc-2',
  serviceDefId: 'def-2',
  name: 'Педикюр SPA',
  durationMinutes: 45,
  priceMin: 400,
  priceMax: 600,
  priceDisplay: '400–600 ₴',
  category: 'NAILS',
);

const WalkInGuest _kGuest = WalkInGuest(
  name: 'Марина',
  surname: 'Кравчук',
  phone: '+380501234567',
);

class _FakeMasterProfile extends MasterProfile {
  @override
  Future<Master> build() async => _kMaster;
}

class _FakeServicesList extends ServicesList {
  @override
  Future<List<MasterService>> build() async => const <MasterService>[
    _kService1,
    _kService2,
  ];
}

List<Object> get _serviceStepOverrides => <Object>[
  masterProfileProvider.overrideWith(_FakeMasterProfile.new),
  servicesListProvider.overrideWith(_FakeServicesList.new),
  approvedCategoriesProvider.overrideWith(
    (ref) async => const <ServiceCategoryOption>[],
  ),
];

// ---------------------------------------------------------------------------
// Goldens
// ---------------------------------------------------------------------------

void main() {
  for (final width in kGoldenWidths) {
    for (final scale in kGoldenTextScales) {
      final String suffix = widthScaleSuffix(width, scale);

      goldenTest(
        'walk-in-guest ${width.toInt()}dp text-${scale}x',
        fileName: 'walk_in_chain_guest_$suffix',
        constraints: BoxConstraints.tight(Size(width, kGoldenHeight)),
        textScaleFactor: scale,
        pumpBeforeTest: onlyPumpAndSettle,
        pumpWidget: goldenPumpWidget(width: width),
        builder: () => const WalkInGuestStepScreen(),
      );

      goldenTest(
        'walk-in-service (empty selection) ${width.toInt()}dp text-${scale}x',
        fileName: 'walk_in_chain_service_$suffix',
        constraints: BoxConstraints.tight(Size(width, kGoldenHeight)),
        textScaleFactor: scale,
        pumpBeforeTest: onlyPumpAndSettle,
        pumpWidget: goldenPumpWidget(
          width: width,
          overrides: _serviceStepOverrides,
        ),
        builder: () => const WalkInServiceStepScreen(guest: _kGuest),
      );

      goldenTest(
        'walk-in-service (two selected) ${width.toInt()}dp text-${scale}x',
        fileName: 'walk_in_chain_service_selected_$suffix',
        constraints: BoxConstraints.tight(Size(width, kGoldenHeight)),
        textScaleFactor: scale,
        pumpBeforeTest: onlyPumpAndSettle,
        pumpWidget: (WidgetTester tester, Widget alchemistWidget) async {
          await goldenPumpWidget(
            width: width,
            overrides: _serviceStepOverrides,
          )(tester, alchemistWidget);
          await tester.tap(find.byKey(const Key('mcb_service_card_svc-1')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('mcb_service_card_svc-2')));
          await tester.pumpAndSettle();
        },
        builder: () => const WalkInServiceStepScreen(guest: _kGuest),
      );
    }
  }
}
