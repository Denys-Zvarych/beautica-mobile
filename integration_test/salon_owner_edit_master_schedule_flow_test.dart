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
import 'package:beautica_mobile/features/master/presentation/widgets/management_action_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
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
        // 2026-09-14 (mobile-qa) — the NON-CONTIGUOUS «Пн, Ср, Пт ·
        // 10:00–19:00» template, not the default contiguous «Пн–Вт» one.
        // Required by the management-card truncation assertion added below:
        // a short value would fit any column and make that assertion pass
        // with OR without the text-token fix. Drop-in for the default seed —
        // still ≥2 working days (so this flow's Monday toggle is still the
        // PUT path) and still Sunday-empty (so the NoScheduleBanner
        // assertion below is unaffected). See the seeder's own doc.
        fb.seedNonContiguousWeeklySchedule();
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
        // `AppHarness.revealRosterCard` is the single shared way to locate a
        // roster card in the lazily-inflated `SliverGrid.builder`: it gates on
        // the grid having LOADED, then drags only when the target cell was
        // never built. This target sits in row 0 by fixture shape, so it
        // no-ops and this path behaves exactly as before.
        await AppHarness.revealRosterCard(tester, masterCard);
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

        // ── 2026-09-14 (mobile-qa, Rule 3b) — THE TRUNCATION REGRESSION ──
        //
        // The widget tier
        // (`test/features/salon/presentation/
        // salon_staff_profile_management_card_text_fit_test.dart`) pins this
        // against an OVERRIDDEN `weeklyScheduleProvider`. This is the same
        // contract against the REAL wire: the value on screen right now was
        // produced by `weeklyScheduleSummary` from a real
        // `GET …/weekly-schedules` response, through the real notifier, into
        // the real card.
        //
        // Only the NAVIGATION half of this journey was already covered; this
        // assertion is the genuinely new part, so it is added HERE rather
        // than in a duplicate flow file (CLAUDE.md REUSE-FIRST, and this
        // file's own header records the journey being reliable only as a
        // single test per file).
        //
        // flutter-tester's surface is 800x600, which gives each card a
        // ~336 dp text column — far wider than any shipped phone and wide
        // enough to hide the defect entirely. Narrow to a real 360 dp phone
        // for the measurement, then restore before the journey continues.
        final Size surfaceBefore = tester.view.physicalSize;
        final double dprBefore = tester.view.devicePixelRatio;
        tester.view.physicalSize = const Size(360, 760);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        // fixed-wait-ok: one frame to re-lay-out at the narrowed surface;
        // nothing async is in flight (the schedule value already resolved —
        // asserted immediately below).
        await tester.pump();

        for (final Key card in <Key>[
          const Key('salon-staff-profile-schedule-row'),
          const Key('salon-staff-profile-services-row'),
        ]) {
          for (final Key line in <Key>[
            kManagementActionCardLabelKey,
            kManagementActionCardValueKey,
          ]) {
            final Finder f = find.descendant(
              of: find.byKey(card),
              matching: find.byKey(line),
            );
            expect(f, findsOneWidget);
            final RenderParagraph p = tester.renderObject<RenderParagraph>(f);
            expect(
              p.didExceedMaxLines,
              isFalse,
              reason:
                  'card $card line $line was ELLIPSIZED at 360 dp — the '
                  'exact CRITICAL defect the 2026-09-14 text-token fix '
                  'removed. A TextOverflow.ellipsis is not a RenderFlex '
                  'overflow, so `installOverflowGuard` above cannot see it.',
            );
          }
        }

        // Anti-vacuity (M14) — the value really is the long non-contiguous
        // summary the seeder produces, not «Не задано» or a still-loading
        // empty string. Without this the loop above would pass on a card
        // rendering nothing at all.
        final ManagementActionCard scheduleCard = tester
            .widget<ManagementActionCard>(scheduleRow);
        expect(
          scheduleCard.value.length,
          greaterThan(18),
          reason:
              'the real wire must have delivered the seeded non-contiguous '
              'weekly template — a short value here silently defangs the '
              'truncation assertions above',
        );

        tester.view.physicalSize = surfaceBefore;
        tester.view.devicePixelRatio = dprBefore;
        // fixed-wait-ok: one frame to restore the original surface before the
        // journey continues.
        await tester.pump();
        // ── end truncation regression ──────────────────────────────────

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
