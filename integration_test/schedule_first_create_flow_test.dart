// END-TO-END regression for BUG 2(b) — calendar FIRST-CREATE: no eager persist.
//
// WHY THIS FILE EXISTS
// --------------------
// On a first-create (the master has NO weekly template yet), the editor's Save
// is the SINGLE commit point. Two contracts the fix guarantees:
//
//   (B) NO EAGER PERSIST — opening the editor, enabling a day + interval (and
//       optionally picking an Apply-window period), then leaving via the top-bar
//       BACK without pressing Save must write NOTHING. Previously the Apply
//       sheet's pick eagerly persisted, materialising a template the master
//       never confirmed; and the master returned to a calendar that had silently
//       become "active".
//
//   (A) SAVE CREATES EXACTLY ONE TEMPLATE — pressing the editor Save persists
//       exactly one weekly schedule (POST, open-ended) and the Master-Schedule
//       calendar then renders the active template (no longer the empty state).
//
// We drive the REAL app (real editor, real notifier, real ScheduleRepository)
// against the Phase 17.3 FakeBackend whose `postScheduleCalls` / `putScheduleCalls`
// counters record every upsertWeeklySchedule the editor issues. The fake is
// seeded with NO schedule (`seedNoWeeklySchedule()`) so the editor is genuinely
// in first-create mode and the schedule screen shows its empty body.
//
// MARKERS
// -------
//   • Empty / NO_SCHEDULE schedule body  → `NoScheduleBanner` present AND
//     `schedule-weekly-card` (the active-calendar template card) ABSENT.
//   • Active calendar                     → `schedule-weekly-card` present.
//
// KEY POLICY: navigation taps use keyed finders; the top-bar back affordance has
// no Key, so it is tapped via its widget TYPE inside the VelvetTopBar (still not
// a raw-text tap driver — see app_harness.dart policy).

import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/schedule/presentation/widgets/schedule_widgets.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/velvet_top_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  void expectLocation(GoRouter router, String expected) {
    final String current = router.routerDelegate.currentConfiguration.uri
        .toString();
    expect(
      current,
      startsWith(expected),
      reason: 'Expected router location to start with $expected, got $current',
    );
  }

  /// Boots an INDEPENDENT_MASTER on the empty Master-Schedule screen and PUSHES
  /// the weekly editor (push — so the editor's top-bar back `context.pop()`s
  /// back to the schedule screen, mirroring the real `_openTemplateEditor`
  /// which uses `context.push`). Returns the live router.
  Future<GoRouter> bootIntoEditor(WidgetTester tester, FakeBackend fb) async {
    fb.seedNoWeeklySchedule(); // first-create: GET returns []
    final GoRouter router = await AppHarness.boot(tester, fb);
    await AppHarness.loginAs(tester, fb, UserRole.independentMaster);

    router.go(RouteNames.masterSchedule);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expectLocation(router, RouteNames.masterSchedule);

    // Navigate to the editor via `go` (the canonical handle for this suite —
    // `push` does not stack reliably in the headless flutter-tester canvas). The
    // editor's top-bar back handler is `if (canPop) pop() else go(masterSchedule)`;
    // after a `go` canPop is false, so tapping back exercises the
    // `go(masterSchedule)` branch — still a genuine "leave the editor WITHOUT
    // Save" that lands on the schedule screen.
    router.go(RouteNames.scheduleWeeklyEditor);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expectLocation(router, RouteNames.scheduleWeeklyEditor);
    return router;
  }

  /// Toggles Monday ON in the editor (seeds a valid 09:00–18:00 interval) so the
  /// draft is dirty + valid (first-create Save enabled).
  Future<void> enableMonday(WidgetTester tester) async {
    final Finder mondayToggle = find.byKey(const Key('weekly-toggle-1'));
    expect(mondayToggle, findsOneWidget);
    await tester.ensureVisible(mondayToggle);
    await tester.pumpAndSettle();
    await tester.tap(mondayToggle);
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
  }

  /// Taps the editor's top-bar BACK affordance (the NeumorphicIconButton inside
  /// the VelvetTopBar). The editor was PUSHED, so this pops back to the schedule
  /// screen.
  Future<void> tapTopBarBack(WidgetTester tester) async {
    final Finder back = find.descendant(
      of: find.byType(VelvetTopBar),
      matching: find.byType(NeumorphicIconButton),
    );
    expect(
      back,
      findsOneWidget,
      reason: 'editor top bar must render a back btn',
    );
    await tester.tap(back);
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  // ── Test 1 — BACK WITHOUT SAVE persists NOTHING; calendar stays EMPTY ──────

  testWidgets(
    'first-create: enable a day (and pick a window) then BACK without Save → '
    'ZERO upsertWeeklySchedule calls AND the schedule screen stays empty',
    (tester) async {
      final fb = FakeBackend();
      final GoRouter router = await bootIntoEditor(tester, fb);

      // Enable Monday with a valid interval — Save becomes enabled.
      await enableMonday(tester);
      expect(find.byKey(const Key('btn-save-weekly-template')), findsOneWidget);

      // Optionally open the Apply-window sheet and pick a preset period. On a
      // first-create this only STAGES the window (returns a DateTimeRange) — it
      // must NOT persist. Scroll the card into view first (enabling Monday
      // expanded its card; the ListView lazily builds, so the top card may need
      // scrolling back into the viewport).
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
      await tester.tap(find.byKey(const Key('preset-whole-year')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn-apply-schedule')));
      await tester.pumpAndSettle();

      // Still nothing persisted after picking the window.
      expect(
        fb.postScheduleCalls + fb.putScheduleCalls,
        0,
        reason:
            'picking an Apply-window period on first-create must not persist '
            '(the editor Save is the single commit point)',
      );

      // Leave via the top-bar BACK without pressing Save.
      await tapTopBarBack(tester);
      expectLocation(router, RouteNames.masterSchedule);

      // (i) ZERO upserts fired — nothing was created.
      expect(
        fb.postScheduleCalls,
        0,
        reason: 'back-without-save must issue NO create (POST)',
      );
      expect(
        fb.putScheduleCalls,
        0,
        reason: 'back-without-save must issue NO update (PUT)',
      );

      // (ii) The schedule screen still shows its EMPTY body — calendar NOT
      // active.
      expect(
        find.byType(NoScheduleBanner),
        findsWidgets,
        reason: 'with nothing persisted the empty NO_SCHEDULE body must render',
      );
      expect(
        find.byKey(const Key('schedule-weekly-card')),
        findsNothing,
        reason: 'the active-calendar template card must NOT render',
      );
    },
    timeout: const Timeout(Duration(seconds: 40)),
  );

  // ── Test 2 — SAVE creates exactly ONE template; calendar goes ACTIVE ───────

  testWidgets('first-create: enable a day then PRESS Save → exactly ONE '
      'upsertWeeklySchedule (POST) AND the calendar renders the template', (
    tester,
  ) async {
    final fb = FakeBackend();
    final GoRouter router = await bootIntoEditor(tester, fb);

    await enableMonday(tester);

    // Press the editor Save — the single commit point.
    final Finder saveBtn = find.byKey(const Key('btn-save-weekly-template'));
    expect(saveBtn, findsOneWidget);
    await tester.ensureVisible(saveBtn);
    await tester.pumpAndSettle();
    await tester.tap(saveBtn);
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Exactly ONE create fired (first-create → null scheduleId → POST), and
    // no update path.
    expect(
      fb.postScheduleCalls,
      1,
      reason: 'first-create Save must issue exactly one create (POST)',
    );
    expect(
      fb.putScheduleCalls,
      0,
      reason: 'first-create must not use the update (PUT) path',
    );
    // It persisted open-ended (no Apply-window picked).
    expect(fb.lastWeeklyDays, isNotNull);

    // The editor popped back to the schedule screen, which now renders the
    // ACTIVE calendar (the template card is present, not the empty body).
    expectLocation(router, RouteNames.masterSchedule);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(
      find.byKey(const Key('schedule-weekly-card')),
      findsOneWidget,
      reason: 'after a successful create the active calendar must render',
    );
  }, timeout: const Timeout(Duration(seconds: 40)));
}
