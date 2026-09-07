// Phase 312 — E2E: a SALON_OWNER opens a chosen MASTER's schedule from the
// roster («Команда» tab) and edits it.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b)
// ----------------------------------------
// Phase 312's dense unit/widget tier proves its own slice against hand-built
// routers/containers with providers overridden directly. None of it drives
// the REAL «Команда» tab -> a real master's roster card -> the REAL
// `SettingsRow` D3 adds to `SalonStaffProfileScreen` -> the REAL push
// carrying `ScheduleScope.salonMaster` as `extra` -> the SAME
// `MasterScheduleScreen`/`WeeklyTemplateEditorScreen` widget tree an
// INDEPENDENT_MASTER edits their own hours with, now rendering — and
// WRITING — against the VIEWED master, never "me".
//
// The SALON_ADMIN counterpart lives in a SEPARATE file
// (`salon_admin_edit_master_schedule_flow_test.dart`) — this journey was
// observed during authoring to be reliable only as a single test per file;
// see that file's own header for the admin-specific pin (never reaching
// GET /masters/me).
//
// SALON_MASTER's own read-only journey (and the negative "no edit
// affordance" pin) is NOT re-proven here — `salon_master_schedule_nav_flow_test
// .dart` (Phase 309-311) already covers it end to end and Phase 312 did not
// touch that file.
//
// NO PATROL FLOW: pure screen / route / provider / GET+PUT surface.
//
// TIMING: never `pumpAndSettle`/`AppHarness.settle` — this journey was found
// during authoring to occasionally stall those on this environment. Every
// wait is `AppHarness.pumpUntilFound` (bounded, real-wall-clock) or an
// unconditional fixed-count pump loop.
//
// FIXTURE: `salon-xyz`'s pre-existing roster row `master-aaa`
// (`userId == masterId`). `FakeBackend`'s schedule endpoints were widened
// this phase (additive) to also answer for `master-aaa`.
//
// FINDERS: widget Keys and widget TYPES only — never a Cyrillic UI string.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_shell_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_staff_profile_screen.dart';
import 'package:beautica_mobile/features/schedule/presentation/master_schedule_screen.dart';
import 'package:beautica_mobile/features/schedule/presentation/weekly_template_editor_screen.dart';
import 'package:beautica_mobile/features/schedule/presentation/widgets/schedule_widgets.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    'SALON_OWNER opens master-aaa schedule from the roster and edits it',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend();
        // salon-xyz is not in the owner persona's default mySalons
        // (salon-owner-1 only) - seed BEFORE boot so salonManageGuard's
        // owner arm admits it.
        fb.mySalons.add(<String, dynamic>{
          'id': 'salon-xyz',
          'ownerId': 'user-owner-1',
          'name': 'Студія Краси «Камелія»',
          'city': 'Київ',
          'cityId': 'city-kyiv',
          'oblastId': 'oblast-kyiv',
          'street': 'вул. Хрещатик',
          'buildingNo': '12',
          'isActive': true,
          'isPrimary': false,
        });
        final GoRouter router = await AppHarness.boot(tester, fb);
        await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
        await AppHarness.pumpUntilFound(
          tester,
          find.byType(SalonShellScreen),
          timeout: const Duration(seconds: 20),
        );

        router.go(RouteNames.salonShell('salon-xyz'));
        await AppHarness.pumpUntilFound(
          tester,
          find.byKey(const Key('salon-nav-tile-2')),
          timeout: const Duration(seconds: 20),
        );

        // -- «Команда» tab -> the real roster grid --
        try {
          await tester.ensureVisible(find.byKey(const Key('salon-nav-tile-2')));
        } catch (_) {}
        await AppHarness.pumpUntilFound(
          tester,
          find.byKey(const Key('salon-nav-tile-2')).hitTestable(),
          timeout: const Duration(seconds: 20),
        );
        await tester.tap(find.byKey(const Key('salon-nav-tile-2')));
        await tester.pump();

        final Finder masterCard = find.byKey(
          const Key('salon-manage-staff-card-master-aaa'),
        );
        await AppHarness.pumpUntilFound(
          tester,
          masterCard,
          timeout: const Duration(seconds: 20),
        );
        try {
          await tester.ensureVisible(masterCard);
        } catch (_) {}
        await AppHarness.pumpUntilFound(
          tester,
          masterCard.hitTestable(),
          timeout: const Duration(seconds: 20),
        );
        await tester.tap(masterCard);
        await tester.pump();

        await AppHarness.pumpUntilFound(
          tester,
          find.byType(SalonStaffProfileScreen),
          timeout: const Duration(seconds: 20),
        );

        // -- the D3 «Графік роботи» row -> the real schedule screen --
        final Finder scheduleRow = find.byKey(
          const Key('salon-staff-profile-schedule-row'),
        );
        await AppHarness.pumpUntilFound(
          tester,
          scheduleRow,
          timeout: const Duration(seconds: 20),
        );
        // Drain the six staggered RevealTransitions off SalonStaffProfileScreen's
        // one 950ms AnimationController.
        // fixed-wait-ok: `pumpAndSettle`/`AppHarness.settle` were found during
        // authoring to stall reproducibly on this journey (this file's own
        // TIMING header note above) — bisected repeatedly without isolating a
        // root cause, so this is a deliberate bounded lockstep pump advancing
        // in step with the transition's known 950ms duration, not an
        // arbitrary sleep.
        await tester.pump(const Duration(milliseconds: 300));
        // fixed-wait-ok: second of three lockstep pumps — see the annotation
        // immediately above.
        await tester.pump(const Duration(milliseconds: 300));
        // fixed-wait-ok: third of three lockstep pumps — see the annotation
        // two above.
        await tester.pump(const Duration(milliseconds: 300));
        try {
          await tester.ensureVisible(scheduleRow);
        } catch (_) {}
        await AppHarness.pumpUntilFound(
          tester,
          scheduleRow.hitTestable(),
          timeout: const Duration(seconds: 20),
        );
        await tester.tap(scheduleRow);
        await tester.pump();

        for (var i = 0; i < 100; i++) {
          // fixed-wait-ok: bounded settle loop (100 x 50ms = 5s wall-clock
          // cap) standing in for `pumpAndSettle`, which was found during
          // authoring to stall reproducibly on this journey (this file's own
          // TIMING header note) — bisected repeatedly without isolating a
          // root cause. Deliberate bounded wait, not an arbitrary sleep.
          await tester.pump(const Duration(milliseconds: 50));
        }

        // The mutation-critical assertion: the SCREEN mounted at all is not
        // enough proof by itself (see the router-level pin in
        // salon_manage_staff_schedule_route_test.dart for the "route builds
        // with no scope -> wrong masterId" case) - here what matters is that
        // the REAL wire call happened, which only succeeds if the tap really
        // pushed the VIEWED master's ScheduleScope.
        expect(find.byType(MasterScheduleScreen), findsOneWidget);
        expect(
          fb.getScheduleCalls,
          greaterThanOrEqualTo(1),
          reason: 'the screen must read the weekly template over the wire',
        );

        // No error surface - the real (fake) wire calls all resolved.
        expect(find.byKey(const Key('schedule-retry')), findsNothing);

        // Same "today" fixture as every sibling schedule E2E (kFixedNow is
        // 2026-06-14, a Sunday; the seeded template's Wed-Sun are empty) - the
        // per-day empty banner really is on screen, so the edit-affordance
        // assertions below are not vacuously true (M14).
        expect(find.byType(NoScheduleBanner), findsOneWidget);

        // Edit affordances PRESENT (D2 - owner gets the full editor).
        expect(find.byKey(const Key('schedule-weekly-card')), findsOneWidget);
        expect(find.byKey(const Key('schedule-day-pencil')), findsOneWidget);
        expect(find.byKey(const Key('no-schedule-add-hours')), findsOneWidget);

        // -- open the weekly editor and confirm it targets the SAME master --
        final int putsBefore = fb.putScheduleCalls;
        final Finder weeklyCard = find.byKey(const Key('schedule-weekly-card'));
        try {
          await tester.ensureVisible(weeklyCard);
        } catch (_) {}
        await AppHarness.pumpUntilFound(
          tester,
          weeklyCard.hitTestable(),
          timeout: const Duration(seconds: 20),
        );
        await tester.tap(weeklyCard);
        await tester.pump();

        for (var i = 0; i < 100; i++) {
          // fixed-wait-ok: bounded settle loop (100 x 50ms = 5s wall-clock
          // cap) standing in for `pumpAndSettle`, which was found during
          // authoring to stall reproducibly on this journey (this file's own
          // TIMING header note) — bisected repeatedly without isolating a
          // root cause. Deliberate bounded wait, not an arbitrary sleep.
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(find.byType(WeeklyTemplateEditorScreen), findsOneWidget);

        // Monday (dow 1) - the FIRST day card, always on screen with no
        // scroll needed. Toggling it OFF is still a real, non-all-off edit:
        // Tuesday (dow 2) stays open in the seeded template, so this is the
        // UPDATE (PUT) path, never the delete path.
        final Finder monToggle = find.byKey(const Key('weekly-toggle-1'));
        await AppHarness.pumpUntilFound(
          tester,
          monToggle,
          timeout: const Duration(seconds: 20),
        );
        try {
          await tester.ensureVisible(monToggle);
        } catch (_) {}
        await AppHarness.pumpUntilFound(
          tester,
          monToggle.hitTestable(),
          timeout: const Duration(seconds: 20),
        );
        await tester.tap(monToggle);
        await tester.pump();

        final Finder saveBtn = find.byKey(
          const Key('btn-save-weekly-template'),
        );
        try {
          await tester.ensureVisible(saveBtn);
        } catch (_) {}
        await AppHarness.pumpUntilFound(
          tester,
          saveBtn.hitTestable(),
          timeout: const Duration(seconds: 20),
        );
        await tester.tap(saveBtn);
        await tester.pump();

        for (var i = 0; i < 60; i++) {
          // fixed-wait-ok: bounded settle loop (60 x 100ms = 6s wall-clock
          // cap) standing in for `pumpAndSettle`, which was found during
          // authoring to stall reproducibly on this journey (this file's own
          // TIMING header note) — bisected repeatedly without isolating a
          // root cause. Deliberate bounded wait, not an arbitrary sleep.
          await tester.pump(const Duration(milliseconds: 100));
        }

        // The write reached the wire - and it could only have reached the
        // wire AT ALL by hitting the literal master-aaa-keyed PUT route this
        // phase's fixture registers: a wrong masterId (e.g. the empty
        // refusal id) has NO registered handler and would leave this count
        // unchanged.
        expect(fb.putScheduleCalls, putsBefore + 1);
      });
    },
  );
}
