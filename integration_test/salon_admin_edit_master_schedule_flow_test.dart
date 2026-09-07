// Phase 312 — E2E: a SALON_ADMIN opens a chosen MASTER's schedule from the
// roster («Команда» tab) and edits it.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b)
// ----------------------------------------
// The SALON_OWNER counterpart lives in a SEPARATE file
// (`salon_owner_edit_master_schedule_flow_test.dart`) — that file's header
// carries the full rationale for why the widget/router tier alone cannot
// prove this journey. This file's OWN reason to exist, beyond mirroring
// that: the sharpest regression this phase's own brief names is
// ADMIN-specific. A SALON_ADMIN has NO master row of their own — `GET
// /masters/me` is gated `hasAnyRole('SALON_MASTER','INDEPENDENT_MASTER',
// 'SALON_OWNER')` (`MasterController.java:109`) — so any regression that
// lets `masterProfileProvider` be reached on an admin session would 403,
// rendering as a generic load failure with no obvious cause. Only a REAL
// admin session, driven through the REAL provider graph (`role_home
// .dart:39` sends SALON_ADMIN through the SAME `salonHome` resolver as
// SALON_OWNER), can prove that call is never even attempted — pinned below
// via `fb.getMasterCalls == 0` at multiple checkpoints across the whole
// journey, including after the write.
//
// NO PATROL FLOW: pure screen / route / provider / GET+PUT surface.
//
// TIMING: never `pumpAndSettle`/`AppHarness.settle` — this journey was found
// during authoring to occasionally stall those on this environment. Every
// wait is `AppHarness.pumpUntilFound` (bounded, real-wall-clock) or an
// unconditional fixed-count pump loop.
//
// FIXTURE: `salon-admin-1`'s roster, widened this phase with `userId:
// 'user-master-under-admin'`, `masterId: 'master-admin-target'` —
// DELIBERATELY DIFFERENT ids, mirroring `salon-xyz`'s own `master-removable`
// row, so a userId/masterId swap bug on the admin path is independently
// catchable from the owner path (which uses `master-aaa`, whose two ids
// coincide). `FakeBackend`'s schedule endpoints were widened this phase
// (additive) to also answer for `master-admin-target`.
//
// FINDERS: widget Keys and widget TYPES only — never a Cyrillic UI string.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_shell_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_staff_profile_screen.dart';
import 'package:beautica_mobile/features/schedule/presentation/master_schedule_screen.dart';
import 'package:beautica_mobile/features/schedule/presentation/weekly_template_editor_screen.dart';
import 'package:beautica_mobile/features/schedule/presentation/widgets/schedule_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    'SALON_ADMIN opens a master schedule from the roster, edits it, and '
    'never reaches GET /masters/me',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend();
        await AppHarness.boot(tester, fb);
        await AppHarness.loginAs(tester, fb, UserRole.salonAdmin);

        // The real post-login landing dispatch: role_home.dart:39 sends
        // SALON_ADMIN through the SAME salonHome resolver as SALON_OWNER,
        // landing on the admin's OWN salon (salon-admin-1).
        await AppHarness.pumpUntilFound(
          tester,
          find.byType(SalonShellScreen),
          timeout: const Duration(seconds: 20),
        );

        expect(
          fb.getMasterCalls,
          0,
          reason:
              'reaching the shell at all must never have touched GET '
              '/masters/me — a SALON_ADMIN has no master row '
              '(MasterController.java:109)',
        );

        // -- «Команда» tab -> the real roster grid --
        await AppHarness.pumpUntilFound(
          tester,
          find.byKey(const Key('salon-nav-tile-2')),
          timeout: const Duration(seconds: 20),
        );
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
          const Key('salon-manage-staff-card-user-master-under-admin'),
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
        expect(fb.getMasterCalls, 0);

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

        // The mutation-critical assertion: the wire call must have happened
        // against the VIEWED master, proving the tap pushed the real
        // ScheduleScope.salonMaster (master-admin-target), never "me"/empty.
        expect(find.byType(MasterScheduleScreen), findsOneWidget);
        expect(fb.getScheduleCalls, greaterThanOrEqualTo(1));
        expect(find.byKey(const Key('schedule-retry')), findsNothing);

        // Same "today" fixture as every sibling schedule E2E (kFixedNow is
        // 2026-06-14, a Sunday; the seeded template's Wed-Sun are empty) - the
        // per-day empty banner really is on screen, so the edit-affordance
        // assertions below are not vacuously true (M14).
        expect(find.byType(NoScheduleBanner), findsOneWidget);

        // Edit affordances PRESENT (D2 - admin gets the full editor too).
        expect(find.byKey(const Key('schedule-weekly-card')), findsOneWidget);
        expect(find.byKey(const Key('schedule-day-pencil')), findsOneWidget);
        expect(find.byKey(const Key('no-schedule-add-hours')), findsOneWidget);

        expect(
          fb.getMasterCalls,
          0,
          reason:
              'an editable schedule screen for an admin session must still '
              'never have reached GET /masters/me — own_schedule_scope.dart '
              'is never on this call path at all for SALON_ADMIN',
        );

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
        // wire AT ALL by hitting the literal master-admin-target-keyed PUT
        // route this phase's fixture registers.
        expect(fb.putScheduleCalls, putsBefore + 1);

        // FINAL PIN - the whole journey, including the write, never touched
        // GET /masters/me.
        expect(fb.getMasterCalls, 0);
      });
    },
  );
}
