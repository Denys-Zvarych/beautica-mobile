// Phase 486 — the master «Записи» week view's ONE load moment end to end on
// the fake backend (headless: `flutter test
// integration_test/master_bookings_week_entrance_flow_test.dart
// -d flutter-tester`).
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b — integration-test gate)
// --------------------------------------------------------------
// `week_time_grid_entrance_test.dart` / `week_strip_entrance_test.dart` pin
// the mechanism against a mocked repository. This proves the journey wired
// together through login, the master shell and a real HTTP boundary:
//
//   * motion on: opening «Записи» plays the entrance (columns fade/rise, the
//     strip window glides in from Monday) and it comes to rest; ‹ › week
//     step and the «День» toggle afterwards do NOT replay it;
//   * reduced motion (`disableAnimations`): no frame of the open ever shows
//     a column fade or the strip window off its page.
//
// Patrol is NOT required — nothing here is a native interaction. Fixture
// windows anchor to the injected clock (kFixedNow, Sun 2026-06-14), so
// «3 дні» opens on Fri–Sun and the window has four cells to glide (pattern M).

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/application/master_bookings_view_mode.dart';
import 'package:beautica_mobile/features/booking/presentation/master_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/week_nav_bar.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/week_strip.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/week_time_grid.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/formatters/api_date.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';
import 'support/week_grid_driver.dart';

/// Moves the seeded `booking-1` to 09:00 UTC on the injected clock's own
/// Kyiv day (a Sunday) — an empty week renders the empty state, not the
/// grid. Mirrors `master_bookings_week_flow_test.dart`'s helper.
void _seedBookingThisWeek(FakeBackend fb) {
  final DateTime today = dateOnly(toBeauticaTime(kFixedNow));
  final DateTime start = DateTime.utc(today.year, today.month, today.day, 9);
  fb
    ..bookingStartsAt = start.toIso8601String()
    ..bookingEndsAt = start.add(const Duration(minutes: 90)).toIso8601String();
}

WeekTimeGrid _grid(WidgetTester tester) =>
    tester.widget<WeekTimeGrid>(find.byType(WeekTimeGrid));

Animation<double> _entrance(WidgetTester tester) {
  final Animation<double>? a = _grid(tester).entrance;
  expect(a, isNotNull, reason: 'the screen hands the grid its entrance');
  return a ?? kAlwaysCompleteAnimation;
}

/// Whether any mounted column is still wrapped in its entrance fade (a
/// `FadeTransition` INSIDE the pager — the route transition is an ancestor
/// too, so it is scoped out).
bool _anyColumnFading(WidgetTester tester) {
  for (int day = 0; day < 7; day++) {
    final Finder column = find.byKey(WeekTimeGrid.columnKey(day));
    if (column.evaluate().isEmpty) continue;
    final Finder fade = find.ancestor(
      of: column,
      matching: find.descendant(
        of: find.byKey(WeekTimeGrid.pagerKey),
        matching: find.byType(FadeTransition),
      ),
    );
    if (fade.evaluate().isNotEmpty) return true;
  }
  return false;
}

/// The mounted strip, or `null` before the screen has built one.
WeekStrip? _strip(WidgetTester tester) {
  final Iterable<Element> e = find.byType(WeekStrip).evaluate();
  return e.isEmpty ? null : e.single.widget as WeekStrip;
}

/// The strip window's distance (px) from where the pager says it rests.
double _windowOffRest(WidgetTester tester, WeekStrip strip) {
  final Rect days = tester.getRect(find.byKey(WeekStrip.daysKey));
  final PageController pager = strip.pageController;
  final double page = pager.hasClients && pager.position.haveDimensions
      ? pager.page ?? pager.initialPage.toDouble()
      : pager.initialPage.toDouble();
  final double rest = days.left + page * days.width / 7 + 2;
  return (tester.getTopLeft(find.byKey(WeekStrip.windowKey)).dx - rest).abs();
}

/// What the frames from now until the entrance is at rest showed.
class _Observed {
  bool midFlight = false;
  bool columnFade = false;
  bool windowOff = false;

  bool get anyMotion => midFlight || columnFade || windowOff;
}

/// Pumps single frames (bounded) from NOW — typically right after the tap
/// that opens the screen, so the loading frames and the grid's very first
/// frame are sampled too — until the grid is up, the entrance has completed
/// and three more frames have passed, recording every sign of motion.
Future<_Observed> _watchFrames(WidgetTester tester) async {
  final _Observed seen = _Observed();
  int restFrames = 0;
  for (int i = 0; i < 400 && restFrames < 3; i++) {
    final WeekStrip? strip = _strip(tester);
    final Animation<double>? a = strip?.entrance;
    if (strip != null && a != null) {
      if (a.value > 0 && a.value < 1) seen.midFlight = true;
      if (_windowOffRest(tester, strip) > 1) seen.windowOff = true;
    }
    if (_anyColumnFading(tester)) seen.columnFade = true;
    final bool atRest =
        find.byType(WeekTimeGrid).evaluate().isNotEmpty &&
        (a?.isCompleted ?? false);
    restFrames = atRest ? restFrames + 1 : 0;
    // fixed-wait-ok: frame-by-frame sampling of a 750 ms animation; a
    // settle would skip the very frames this records.
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(find.byType(WeekTimeGrid), findsOneWidget);
  expect(
    _entrance(tester).status,
    AnimationStatus.completed,
    reason: 'the entrance must come to rest',
  );
  return seen;
}

/// Boots, logs in and taps «Записи» — NOT pumped further: the caller's
/// [_watchFrames] observes the open from the tap on.
Future<GoRouter> _tapBookings(WidgetTester tester, FakeBackend fb) async {
  final GoRouter router = await AppHarness.boot(tester, fb);
  _seedBookingThisWeek(fb);
  await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
  await tester.tap(find.byKey(const Key('master-nav-tile-1')));
  return router;
}

void _expectOnBookings(WidgetTester tester, GoRouter router) {
  AppHarness.expectLocation(router, RouteNames.masterBookings);
  expect(find.byType(MasterBookingsScreen), findsOneWidget);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets('opening «Записи» plays the entrance once; a week step and '
      '«День» do not replay it', (WidgetTester tester) async {
    final FakeBackend fb = FakeBackend()
      ..currentRole = UserRole.independentMaster;
    final GoRouter router = await _tapBookings(tester, fb);

    final _Observed open = await _watchFrames(tester);
    _expectOnBookings(tester, router);
    expect(_grid(tester).visibleColumns, 3);
    expect(
      _grid(tester).pageController.initialPage,
      greaterThan(0),
      reason: 'fixture guard: the window has cells to glide from Monday',
    );
    expect(open.midFlight, isTrue, reason: 'the entrance ran');
    expect(open.columnFade, isTrue, reason: 'columns faded in');
    expect(open.windowOff, isTrue, reason: 'the window glided in');
    final Animation<double> entrance = _entrance(tester);
    expect(_anyColumnFading(tester), isFalse, reason: 'collapsed at rest');
    await AppHarness.settle(tester);

    // ‹ then › — the fixture's next week is empty (no grid), so step there
    // and back: this week's grid REMOUNTS on the completed controller.
    final DateTime week = _grid(tester).weekStart;
    await tester.tap(find.byKey(WeekStepButton.nextKey).first);
    await AppHarness.settle(tester);
    expect(
      find.byWidgetPredicate(
        (Widget w) => w is WeekTimeGrid && w.weekStart == week,
      ),
      findsNothing,
      reason: 'stepped off the week',
    );
    expect(
      tester.widget<WeekStrip>(find.byType(WeekStrip)).entrance?.value,
      1,
      reason: 'the step left the entrance at rest',
    );
    await tester.tap(find.byKey(WeekStepButton.prevKey).first);
    final _Observed step = await _watchFrames(tester);
    expect(_grid(tester).weekStart, week);
    expect(identical(_entrance(tester), entrance), isTrue);
    expect(step.anyMotion, isFalse, reason: 'a week step replayed it');
    await AppHarness.settle(tester);

    await switchViewMode(
      tester,
      BookingsWeekViewMode.day,
      settle: (WidgetTester t) => t.pump(),
    );
    expect(_grid(tester).visibleColumns, 1);
    final _Observed toggle = await _watchFrames(tester);
    expect(toggle.anyMotion, isFalse, reason: '«День» replayed it');
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion: no frame of the open moves — no column fade, '
      'the strip window on its page', (WidgetTester tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final FakeBackend fb = FakeBackend()
      ..currentRole = UserRole.independentMaster;
    final GoRouter router = await _tapBookings(tester, fb);

    // From the tap: the loading frames, the grid's first frame and on.
    final _Observed open = await _watchFrames(tester);
    _expectOnBookings(tester, router);
    expect(_grid(tester).visibleColumns, 3);
    expect(open.columnFade, isFalse, reason: 'a column faded in');
    expect(open.windowOff, isFalse, reason: 'the window glided');
    expect(open.midFlight, isFalse, reason: 'jumped to rest, not run');
    expect(tester.takeException(), isNull);
  });
}
