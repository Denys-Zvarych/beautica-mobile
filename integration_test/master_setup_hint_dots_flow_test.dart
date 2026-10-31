// E2E — master-nav setup-hint dots (2026-10-30).
//
// Journey (INDEPENDENT_MASTER, nothing set up):
//   1. Login → /master/profile. Both setup dots render on the bottom nav:
//      «Послуги» (Key('master-nav-setup-dot-0')) and «Графік»
//      (Key('master-nav-setup-dot-2')); same on /master/bookings.
//   2. Add a service through the real bulk service-setup screen → land on
//      /services → the «Послуги» dot clears, the «Графік» dot stays.
//   3. Open «Графік» → weekly editor → enable Monday, pick a validity window,
//      Save → back on /master/schedule → the «Графік» dot clears too.
//
// FAKE BACKEND
// ------------
//   • `clearServices()` → `GET /independent-masters/me/services` is `[]`.
//   • `bulkCreatePersists` → the bulk POST lands in the catalogue, so the
//     re-fetch after the save sees an ACTIVE service.
//   • `seedNoWeeklySchedule()` → no template at boot.
//   • `deriveEffectiveScheduleFromWeekly` → `GET …/effective-schedule`
//     (the readiness rule's 180-day window) is derived from the live weekly
//     templates, so the weekly POST is what flips the «Графік» dot. Without it
//     the route answers `[]` forever and step 3 could never pass.
//
// Clock: the tier pins `kFixedNow` (2026-06-14, Kyiv) for the app; the fake
// derives days from the request's own `from`/`to`, so there is one clock
// (M15). Finders are key-based (app_harness.dart policy).

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/schedule/presentation/master_schedule_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import '../test/helpers/pump_app.dart';
import 'support/app_harness.dart';

const Key _servicesDot = Key('master-nav-setup-dot-0');
const Key _scheduleDot = Key('master-nav-setup-dot-2');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  Future<void> addService(WidgetTester tester, FakeBackend fb) async {
    // Not `type-nails-classic` — see service_crud_flow_test.dart Test 1.
    const String typeId = 'type-nails-gel';
    final Finder nailsChip = find.byKey(const ValueKey<String>('cat_NAILS'));
    await tester.pumpUntilFound(nailsChip.hitTestable());
    await tester.tap(nailsChip);
    final Finder row = find.byKey(const Key('setup_row_$typeId'));
    await tester.pumpUntilFound(row);
    final Finder toggle = find.byKey(const Key('setup_row_toggle_$typeId'));
    await tester.ensureVisible(toggle);
    await tester.pumpUntilFound(toggle.hitTestable());
    await tester.tap(toggle);
    final Finder duration = find.descendant(
      of: row,
      matching: find.byKey(const Key('service-setup-duration')),
    );
    final Finder price = find.descendant(
      of: row,
      matching: find.byKey(const Key('pricing-fixed-amount')),
    );
    await tester.pumpUntilFound(duration);
    await tester.pumpUntilFound(price);
    await tester.enterText(duration, '60');
    await tester.pump();
    await tester.enterText(price, '400');
    await tester.pump();
    final Finder save = find.byKey(const Key('btn-setup-save'));
    await tester.pumpUntilFound(save.hitTestable());
    await tester.tap(save);
    await AppHarness.pumpUntilCondition(
      tester,
      () => fb.bulkCreateCalls >= 1,
      description: 'the bulk service POST',
    );
  }

  Future<void> saveMondaySchedule(WidgetTester tester, FakeBackend fb) async {
    final Finder monday = find.byKey(const Key('weekly-toggle-1'));
    await tester.pumpUntilFound(monday);
    await tester.ensureVisible(monday);
    await tester.pumpAndSettle();
    await tester.tap(monday);
    await tester.pump();
    await tester.pumpAndSettle();

    final Finder windowCard = find.byKey(
      const Key('weekly-active-window-card'),
    );
    await tester.scrollUntilVisible(
      windowCard,
      -120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(windowCard);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('preset-this-month')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('btn-apply-schedule')));
    await tester.pumpAndSettle();

    final Finder save = find.byKey(const Key('btn-save-weekly-template'));
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await AppHarness.pumpUntilCondition(
      tester,
      () => fb.postScheduleCalls >= 1,
      description: 'the weekly-schedule POST',
    );
  }

  testWidgets(
    'INDEPENDENT_MASTER with nothing set up sees both nav dots; adding a '
    'service clears «Послуги», saving a working weekday clears «Графік»',
    (tester) async {
      final FakeBackend fb = FakeBackend()
        ..clearServices()
        ..bulkCreatePersists = true
        ..seedNoWeeklySchedule()
        ..deriveEffectiveScheduleFromWeekly = true;

      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
      AppHarness.expectLocation(router, RouteNames.masterProfile);

      // ── 1. Both dots ─────────────────────────────────────────────────────
      await tester.pumpUntilFound(find.byKey(_servicesDot));
      await tester.pumpUntilFound(find.byKey(_scheduleDot));
      expect(find.byKey(_servicesDot), findsOneWidget);
      expect(find.byKey(_scheduleDot), findsOneWidget);

      // The «Записи» tab's bar opts in too (4th opted-in screen).
      router.go(RouteNames.masterBookings);
      await tester.pumpUntilFound(find.byKey(_servicesDot));
      await tester.pumpUntilFound(find.byKey(_scheduleDot));
      AppHarness.expectLocation(router, RouteNames.masterBookings);

      // ── 2. Add a service → «Послуги» dot clears ──────────────────────────
      router.go(RouteNames.serviceSetup);
      await addService(tester, fb);
      await AppHarness.pumpUntilCondition(
        tester,
        () => AppHarness.location(router) == RouteNames.services,
        description: 'the setup screen to leave back to /services',
      );
      await AppHarness.pumpUntilCondition(
        tester,
        () => find.byKey(_servicesDot).evaluate().isEmpty,
        description: 'the «Послуги» dot to clear after the service was added',
      );
      expect(find.byKey(_servicesDot), findsNothing);
      expect(
        find.byKey(_scheduleDot),
        findsOneWidget,
        reason: 'no schedule yet — the «Графік» dot must stay',
      );

      // The services save raises a VelvetSnack on the root overlay; let it
      // auto-dismiss so it cannot cover the schedule sheet's Apply button.
      await AppHarness.pumpUntilCondition(
        tester,
        () => find.byType(VelvetSnack).evaluate().isEmpty,
        description: 'the services-saved snack to auto-dismiss',
      );

      // ── 3. Save a weekly schedule → «Графік» dot clears ──────────────────
      router.go(RouteNames.masterSchedule);
      await tester.pumpUntilFound(find.byType(MasterScheduleScreen));
      await tester.pumpAndSettle();
      AppHarness.expectLocation(router, RouteNames.masterSchedule);
      expect(find.byKey(_scheduleDot), findsOneWidget);
      router.go(RouteNames.scheduleWeeklyEditor);
      await tester.pumpUntilFound(find.byKey(const Key('weekly-toggle-1')));
      await tester.pumpAndSettle();
      AppHarness.expectLocation(router, RouteNames.scheduleWeeklyEditor);

      await saveMondaySchedule(tester, fb);
      await AppHarness.pumpUntilCondition(
        tester,
        () => AppHarness.location(router) == RouteNames.masterSchedule,
        description: 'the editor to return to /master/schedule after Save',
      );
      expect(fb.postScheduleCalls, 1, reason: 'first-create Save → one POST');

      await AppHarness.pumpUntilCondition(
        tester,
        () => find.byKey(_scheduleDot).evaluate().isEmpty,
        description: 'the «Графік» dot to clear after the weekly save',
      );
      expect(find.byKey(_scheduleDot), findsNothing);
      expect(find.byKey(_servicesDot), findsNothing);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
