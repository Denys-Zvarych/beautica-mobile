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
import 'package:beautica_mobile/features/booking/presentation/widgets/selected_services_shelf.dart';
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
  priceDisplay: '500 ₴',
  durationMinutes: 90,
  priceType: ServicePriceType.fixed,
  priceMin: 500,
);
const _svc2 = SalonCatalogService(
  id: 'svc-2',
  name: 'Педикюр з покриттям',
  durationLabel: '2 год',
  priceDisplay: '800 ₴',
  durationMinutes: 120,
  priceType: ServicePriceType.fixed,
  priceMin: 800,
);
const _svc3 = SalonCatalogService(
  id: 'svc-3',
  name: 'Стрижка',
  durationLabel: '1 год',
  priceDisplay: '450 ₴',
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
  // ScheduleConfirmBar never reads `orderedMasterServiceIds` (it only sums
  // `services`), so the default empty list satisfies this display-only
  // fixture — see `salon_master_schedule.dart`'s doc comment (D4) for why no
  // invariant requires a non-empty value here.
);
const _m2Schedule = SalonMasterSchedule(
  masterId: 'm2',
  firstName: 'Софія',
  lastName: 'Мельник',
  type: MasterType.salonMaster,
  services: <SalonCatalogService>[_svc3],
);

/// The client's full original selection across both masters — feeds the
/// pinned [SelectedServicesShelf], mirroring what `SalonTimeScreen` flattens
/// out of every assigned master's [SalonMasterSchedule.services].
final List<MasterService> _selectedServices = <MasterService>[
  salonServiceForShelf(_svc1),
  salonServiceForShelf(_svc2),
  salonServiceForShelf(_svc3),
];

void main() {
  testWidgets('sums price/duration across every assigned service of every '
      'master (not just each master\'s primary service)', (tester) async {
    await tester.pumpApp(
      Scaffold(
        bottomNavigationBar: ScheduleConfirmBar(
          schedules: const <SalonMasterSchedule>[_m1Schedule, _m2Schedule],
          selectedServices: _selectedServices,
          scheduledCount: 0,
          totalCount: 2,
          onConfirm: () {},
        ),
      ),
    );

    // 500 + 800 + 450 = 1750 ₴; 90 + 120 + 60 = 270 хв = 4 год 30 хв.
    expect(find.textContaining('1750'), findsOneWidget);
    expect(find.textContaining('4 год 30 хв'), findsOneWidget);
  });

  testWidgets('progress line shows "X з Y заплановано" while incomplete, '
      '"Усе заплановано" once every master is scheduled', (tester) async {
    await tester.pumpApp(
      Scaffold(
        bottomNavigationBar: ScheduleConfirmBar(
          schedules: const <SalonMasterSchedule>[_m1Schedule, _m2Schedule],
          selectedServices: _selectedServices,
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
          selectedServices: _selectedServices,
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
          selectedServices: _selectedServices,
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
          selectedServices: _selectedServices,
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

  // mobile-qa gap-fix — the bar's composition of the shared
  // `SelectedServicesShelf` (the new "always show selected services" bottom
  // bar behaviour) had NO coverage at all: every test above only drove the
  // "Разом"/progress/CTA content, never the shelf pinned above it. The main
  // regression risk of that change is the shelf's toggle interfering with —
  // or hiding — the progress counter/CTA that already existed on this bar, so
  // this group expands the shelf FIRST and re-asserts every pre-existing
  // contract still holds.
  group('selected-services shelf composition (mobile-qa gap-fix)', () {
    const Key toggleKey = Key('booking-summary-expand-toggle');
    const Key expandedListKey = Key('booking-summary-expanded-list');

    // Every shelf assertion is scoped to the shelf's OWN `expanded-list`
    // subtree rather than searching the whole pumped tree. Nothing else in
    // this bar renders a service name today, so an unscoped finder happens to
    // pass — but that is exactly the latent trap that DID bite on
    // `salon_master_selection_screen_test.dart`, where the master rows'
    // "covers: <service names>" subtitle draws from the SAME fixture names and
    // made an unscoped finder match two widgets. Scoping keeps the assertion
    // proving the SHELF's content specifically.
    Finder inShelf(Finder matching) =>
        find.descendant(of: find.byKey(expandedListKey), matching: matching);

    testWidgets(
      'expanding the shelf reveals every selected service across every '
      'assigned master, while the progress counter and CTA stay visible',
      (tester) async {
        await tester.pumpApp(
          Scaffold(
            bottomNavigationBar: ScheduleConfirmBar(
              schedules: const <SalonMasterSchedule>[_m1Schedule, _m2Schedule],
              selectedServices: _selectedServices,
              scheduledCount: 1,
              totalCount: 2,
              onConfirm: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Collapsed: the shelf's own itemized list is not built at all yet.
        expect(find.byKey(expandedListKey), findsNothing);

        await tester.tap(find.byKey(toggleKey));
        await tester.pumpAndSettle();

        // i18n-finder-ok: fixture service names (test data), not app UI copy.
        expect(inShelf(find.text(_svc1.name)), findsOneWidget);
        // i18n-finder-ok: fixture service names (test data), not app UI copy.
        expect(inShelf(find.text(_svc2.name)), findsOneWidget);
        // i18n-finder-ok: fixture service names (test data), not app UI copy.
        expect(inShelf(find.text(_svc3.name)), findsOneWidget);

        // The pre-existing progress counter + CTA must still be present and
        // functioning once the shelf is expanded — the regression risk this
        // change introduces.
        final l10n = AppLocalizations.of(
          tester.element(find.byType(ScheduleConfirmBar)),
        );
        expect(find.text(l10n.salonScheduleProgress(1, 2)), findsOneWidget);
        final NeumorphicButton cta = tester.widget<NeumorphicButton>(
          find.byKey(const Key('schedule-confirm-cta')),
        );
        expect(
          cta.onPressed,
          isNull,
        ); // still disabled: scheduledCount < totalCount
      },
    );

    testWidgets(
      'the CTA still fires onConfirm once every master is scheduled, even '
      'with the shelf expanded',
      (tester) async {
        bool confirmed = false;
        await tester.pumpApp(
          Scaffold(
            bottomNavigationBar: ScheduleConfirmBar(
              schedules: const <SalonMasterSchedule>[_m1Schedule, _m2Schedule],
              selectedServices: _selectedServices,
              scheduledCount: 2,
              totalCount: 2,
              onConfirm: () => confirmed = true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(toggleKey));
        await tester.pumpAndSettle();

        // i18n-finder-ok: fixture service name (test data), not app UI copy.
        expect(inShelf(find.text(_svc1.name)), findsOneWidget);

        await tester.tap(find.byKey(const Key('schedule-confirm-cta')));
        await tester.pumpAndSettle();

        expect(confirmed, isTrue);
      },
    );
  });
}
