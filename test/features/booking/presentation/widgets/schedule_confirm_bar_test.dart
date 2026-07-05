// Phase 14.17 — Widget tests for ScheduleConfirmBar (the salon booking
// flow's step-3 pinned summary shelf).
//
// Covers:
//   1. "Разом" sums typed price/duration fields across EVERY assigned
//      service of EVERY assigned master (not just the primary service).
//   2. Progress line reflects scheduledCount/totalCount, flipping to the
//      "Усе заплановано" label once every master is scheduled.
//   3. "Підтвердити" is disabled until scheduledCount == totalCount, and
//      fires [onConfirm] once enabled and tapped.

import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/booking/domain/salon_master_schedule.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/schedule_confirm_bar.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

const _svc1 = SalonCatalogService(
  id: 'svc-1',
  name: 'Манікюр з покриттям',
  durationLabel: '1 год 30 хв',
  priceDisplay: '500 грн',
  durationMinutes: 90,
  priceType: ServicePriceType.fixed,
  priceMin: 500,
);
const _svc2 = SalonCatalogService(
  id: 'svc-2',
  name: 'Педикюр з покриттям',
  durationLabel: '2 год',
  priceDisplay: '800 грн',
  durationMinutes: 120,
  priceType: ServicePriceType.fixed,
  priceMin: 800,
);
const _svc3 = SalonCatalogService(
  id: 'svc-3',
  name: 'Стрижка',
  durationLabel: '1 год',
  priceDisplay: '450 грн',
  durationMinutes: 60,
  priceType: ServicePriceType.fixed,
  priceMin: 450,
);

const _m1Schedule = SalonMasterSchedule(
  masterId: 'm1',
  firstName: 'Олена',
  lastName: 'Ковальчук',
  type: MasterType.independentMaster,
  services: <SalonCatalogService>[_svc1, _svc2],
  // ScheduleConfirmBar never reads this field (it only sums `services`), so
  // any non-empty fixture value satisfies the required constructor param —
  // see `salon_master_schedule.dart`'s doc comment for what it means.
  primaryServiceAssignmentId: 'assignment-m1-svc-1',
);
const _m2Schedule = SalonMasterSchedule(
  masterId: 'm2',
  firstName: 'Софія',
  lastName: 'Мельник',
  type: MasterType.salonMaster,
  services: <SalonCatalogService>[_svc3],
  primaryServiceAssignmentId: 'assignment-m2-svc-3',
);

void main() {
  testWidgets('sums price/duration across every assigned service of every '
      'master (not just each master\'s primary service)', (tester) async {
    await tester.pumpApp(
      Scaffold(
        bottomNavigationBar: ScheduleConfirmBar(
          schedules: const <SalonMasterSchedule>[_m1Schedule, _m2Schedule],
          scheduledCount: 0,
          totalCount: 2,
          onConfirm: () {},
        ),
      ),
    );

    // 500 + 800 + 450 = 1750 грн; 90 + 120 + 60 = 270 хв = 4 год 30 хв.
    expect(find.textContaining('1750'), findsOneWidget);
    expect(find.textContaining('4 год 30 хв'), findsOneWidget);
  });

  testWidgets('progress line shows "X з Y заплановано" while incomplete, '
      '"Усе заплановано" once every master is scheduled', (tester) async {
    await tester.pumpApp(
      Scaffold(
        bottomNavigationBar: ScheduleConfirmBar(
          schedules: const <SalonMasterSchedule>[_m1Schedule, _m2Schedule],
          scheduledCount: 1,
          totalCount: 2,
          onConfirm: () {},
        ),
      ),
    );
    final l10n = AppLocalizations.of(
      tester.element(find.byType(ScheduleConfirmBar)),
    );
    expect(find.text(l10n.salonScheduleProgress(1, 2)), findsOneWidget);
    expect(find.text(l10n.salonScheduleAllScheduledLabel), findsNothing);

    await tester.pumpApp(
      Scaffold(
        bottomNavigationBar: ScheduleConfirmBar(
          schedules: const <SalonMasterSchedule>[_m1Schedule, _m2Schedule],
          scheduledCount: 2,
          totalCount: 2,
          onConfirm: () {},
        ),
      ),
    );
    expect(find.text(l10n.salonScheduleAllScheduledLabel), findsOneWidget);
    expect(find.text(l10n.salonScheduleProgress(1, 2)), findsNothing);
  });

  testWidgets('CTA is disabled until every master is scheduled, then fires '
      'onConfirm when tapped', (tester) async {
    bool confirmed = false;
    await tester.pumpApp(
      Scaffold(
        bottomNavigationBar: ScheduleConfirmBar(
          schedules: const <SalonMasterSchedule>[_m1Schedule, _m2Schedule],
          scheduledCount: 1,
          totalCount: 2,
          onConfirm: () => confirmed = true,
        ),
      ),
    );
    NeumorphicButton cta = tester.widget<NeumorphicButton>(
      find.byKey(const Key('schedule-confirm-cta')),
    );
    expect(cta.onPressed, isNull);

    await tester.pumpApp(
      Scaffold(
        bottomNavigationBar: ScheduleConfirmBar(
          schedules: const <SalonMasterSchedule>[_m1Schedule, _m2Schedule],
          scheduledCount: 2,
          totalCount: 2,
          onConfirm: () => confirmed = true,
        ),
      ),
    );
    cta = tester.widget<NeumorphicButton>(
      find.byKey(const Key('schedule-confirm-cta')),
    );
    expect(cta.onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('schedule-confirm-cta')));
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
  });
}
