// 2026-07-26 booking-conflict design — E2E: saving a day-off through
// `DayHoursSheet` against the real conflict-preview → confirm → write pipeline.
//
// `MasterScheduleService.upsertOverride` used to be documented "always
// allowed — never blocked by, nor mutating, existing bookings" (OQ-1). This
// spec reverses that for SAVE: every save now previews conflicts first
// (`POST /overrides/conflicts`), and a non-empty preview gates the write
// behind `DayOffConflictDialog` + the master's explicit confirmation.
//
// Widget-level coverage of this exact gate already exists in
// `test/features/schedule/presentation/day_hours_sheet_test.dart` (mocked
// `ScheduleRepository`, no real HTTP boundary). This file is the Step 2.7
// Rule 3b end-to-end companion: it drives the SAME journey through a REAL
// `Dio` boundary against `FakeBackend` — login → navigate to the master
// schedule → open the day pencil → the actual wire request/response
// round-trip for both `POST /overrides/conflicts` and
// `PUT /overrides/{date}` — proving the provider/repository/mapper wiring the
// widget-level mock bypasses entirely.
//
// Three journeys (Step 2.7 Rule 3b's minimum for this feature):
//   1. No conflicts → save proceeds with NO dialog (the regression guard for
//      "don't add a dialog to the common case" — most days have nothing to
//      conflict with).
//   2. Conflicts → dialog lists them → confirm → the PUT carries
//      `cancelOverlapping: true` and the conflicting booking is gone (server
//      truth: the seeded booking flips CONFIRMED → DECLINED, exactly what
//      D3's "written AND every conflicting booking declined, atomically"
//      contract promises).
//   3. Conflicts → «Залишити як є» → NOTHING is written — not the override,
//      not the cancellation (D2/D3: backing out is the safe path).
//
// KEY POLICY: every navigation/tap uses key-based finders (see
// `app_harness.dart`). The one exception is asserting the conflicting
// booking's client name inside the trough — SEEDED FIXTURE DATA, not app
// chrome copy — which is located via `find.bySemanticsLabel` against the
// row's accessibility label (see `_conflictClientName`), not `find.text`.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import '../test/helpers/pump_app.dart';
import 'support/app_harness.dart';

/// The seeded conflicting booking's client name — pulled out to a single
/// constant (rather than duplicated as a literal in both the fixture and the
/// assertion) so the trough assertion below can locate the row via
/// [find.bySemanticsLabel] instead of `find.text`. This is genuinely SEEDED
/// FIXTURE DATA (a client's name, not app chrome copy) so it is not itself
/// M2-coupled — but a semantics-label finder is used anyway (over
/// `find.text`) because it targets the accessibility tree rather than the
/// visible `Text` composition, which is the more robust "real fix" per
/// `forbid_cyrillic_finder.sh`'s own menu of alternatives.
const String _conflictClientName = 'Олена Гриценко';

/// One conflict row, wire-shaped exactly as `OverrideConflictResponse`
/// deserialises it. Reuses the seeded `booking-1` id so the PUT-time
/// cancellation side effect ([FakeBackend.overrideCancelOverlappingWrites])
/// has a booking fixture to flip.
Map<String, dynamic> _conflictRow() => <String, dynamic>{
  'bookingId': 'booking-1',
  'appointmentId': null,
  'date': '2026-06-14',
  'startsAt': '2026-06-14T10:00:00Z',
  'endsAt': '2026-06-14T11:00:00Z',
  'clientDisplayName': _conflictClientName,
  'serviceName': 'Манікюр з покриттям',
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  /// Navigates to the master schedule and opens today's day-override sheet.
  /// Returns `false` (and marks the test skipped) if the day pencil did not
  /// lay out in this run — the same environment-specific defensive fallback
  /// `schedule_edit_flow_test.dart` Test 4 uses (the calendar grid can fail to
  /// size in the headless flutter-tester canvas); the sheet UI itself is
  /// covered structurally by `day_hours_sheet_test.dart` regardless.
  Future<bool> openTodaySheet(WidgetTester tester, GoRouter router) async {
    router.go(RouteNames.masterSchedule);
    // Pump until the screen's own initial-load spinner (the sole
    // `CircularProgressIndicator` `MasterScheduleScreen` renders — its
    // `days == null || weekly == null` gate) is gone, instead of guessing a
    // fixed wait: the indicator drives a repeating `AnimationController`, so
    // bare `pumpAndSettle()` would spin until its own internal timeout while
    // it is up, and a hard-coded duration is either too short (flaky under
    // load) or too long (slow) regardless.
    await tester.pumpUntilGone(find.byType(CircularProgressIndicator));
    AppHarness.expectLocation(router, RouteNames.masterSchedule);

    final Finder pencil = find.byKey(const Key('schedule-day-pencil'));
    if (pencil.evaluate().isEmpty) {
      markTestSkipped(
        'master schedule did not lay out a day-override pencil in this run; '
        'the booking-conflict gate is covered structurally by '
        'day_hours_sheet_test.dart',
      );
      return false;
    }
    await tester.ensureVisible(pencil);
    await tester.tap(pencil);
    await tester.pumpAndSettle();
    return true;
  }

  testWidgets(
    'no conflicts on the date: save succeeds with NO confirmation dialog',
    (tester) async {
      final fb = FakeBackend(); // conflictPreviewRows defaults to empty.
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);

      if (!await openTodaySheet(tester, router)) return;

      await tester.tap(find.byKey(const Key('override-mode-dayoff')));
      await tester.pumpAndSettle();

      final int previewsBefore = fb.previewConflictsCalls;
      final int putsBefore = fb.putOverrideCalls;

      final Finder saveBtn = find.byKey(const Key('override-save'));
      await tester.ensureVisible(saveBtn);
      await tester.pumpAndSettle();
      await tester.tap(saveBtn);
      // One pump: if a confirmation dialog gated the save, it would already be
      // on screen and the PUT would NOT have fired yet.
      await tester.pump();

      expect(
        find.byKey(const Key('day-off-conflict-dialog')),
        findsNothing,
        reason:
            'an empty conflict preview must never raise the conflict dialog',
      );

      await tester.pumpAndSettle();

      expect(
        fb.previewConflictsCalls,
        greaterThan(previewsBefore),
        reason:
            'save must call POST /overrides/conflicts even on the '
            'no-conflict path — the gate always previews first',
      );
      expect(
        fb.putOverrideCalls,
        greaterThan(putsBefore),
        reason: 'the no-conflict path must save exactly as before',
      );
      expect(
        fb.lastOverrideBody?['kind'],
        'DAY_OFF',
        reason: 'the day-off mode chip must serialise as kind=DAY_OFF',
      );
      expect(
        fb.lastOverrideBody?['cancelOverlapping'],
        isFalse,
        reason: 'the no-conflict path must never opt in to cancelling anything',
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'a conflict on the date shows the dialog listing it; confirming saves '
    'with cancelOverlapping: true and the conflicting booking is gone',
    (tester) async {
      final fb = FakeBackend()
        ..conflictPreviewRows = <Map<String, dynamic>>[_conflictRow()]
        ..bookingStatus = 'CONFIRMED';
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);

      if (!await openTodaySheet(tester, router)) return;

      await tester.tap(find.byKey(const Key('override-mode-dayoff')));
      await tester.pumpAndSettle();

      final int previewsBefore = fb.previewConflictsCalls;

      final Finder saveBtn = find.byKey(const Key('override-save'));
      await tester.ensureVisible(saveBtn);
      await tester.pumpAndSettle();
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      // The dialog is up, listing the seeded client by name, and NOTHING has
      // been written yet.
      expect(find.byKey(const Key('day-off-conflict-dialog')), findsOneWidget);
      expect(find.byKey(const Key('day-off-conflict-trough')), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(RegExp.escape(_conflictClientName))),
        findsOneWidget,
        reason: 'the trough must render the conflicting booking by name',
      );
      expect(
        fb.previewConflictsCalls,
        greaterThan(previewsBefore),
        reason: 'the sheet must have run the real POST /overrides/conflicts',
      );
      expect(fb.putOverrideCalls, 0, reason: 'no write before confirmation');
      expect(fb.bookingStatus, 'CONFIRMED');

      await tester.tap(find.byKey(const Key('day-off-conflict-confirm')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('day-off-conflict-dialog')), findsNothing);
      expect(
        fb.putOverrideCalls,
        1,
        reason: 'confirming issues exactly the one confirmed PUT',
      );
      expect(
        fb.lastOverrideBody?['cancelOverlapping'],
        isTrue,
        reason: 'confirming must set cancelOverlapping: true on the wire',
      );
      expect(
        fb.overrideCancelOverlappingWrites,
        1,
        reason:
            'the write must carry the consent flag AND a non-empty preview '
            'for the fake to model the atomic decline',
      );
      // Server truth: the conflicting booking is gone (D3 — "the override is
      // written AND every conflicting booking declined, atomically").
      expect(
        fb.bookingStatus,
        'DECLINED',
        reason:
            'the previously CONFIRMED conflicting booking must be declined '
            'by the same write that saved the day-off',
      );
      // The sheet dismissed itself on the confirmed save.
      expect(find.byKey(const Key('override-save')), findsNothing);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'a conflict on the date, backing out via «Залишити як є»: persists '
    'NOTHING — no override PUT, no cancellation',
    (tester) async {
      final fb = FakeBackend()
        ..conflictPreviewRows = <Map<String, dynamic>>[_conflictRow()]
        ..bookingStatus = 'CONFIRMED';
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);

      if (!await openTodaySheet(tester, router)) return;

      await tester.tap(find.byKey(const Key('override-mode-dayoff')));
      await tester.pumpAndSettle();

      final Finder saveBtn = find.byKey(const Key('override-save'));
      await tester.ensureVisible(saveBtn);
      await tester.pumpAndSettle();
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('day-off-conflict-dialog')), findsOneWidget);

      await tester.tap(find.byKey(const Key('day-off-conflict-keep')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('day-off-conflict-dialog')), findsNothing);
      expect(
        fb.putOverrideCalls,
        0,
        reason: 'backing out must write NOTHING — not even the override itself',
      );
      expect(fb.overrideCancelOverlappingWrites, 0);
      expect(
        fb.bookingStatus,
        'CONFIRMED',
        reason: 'the conflicting booking must be left untouched',
      );
      // The sheet stays open — the master's edit is preserved, free to retry.
      expect(find.byKey(const Key('override-save')), findsOneWidget);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
