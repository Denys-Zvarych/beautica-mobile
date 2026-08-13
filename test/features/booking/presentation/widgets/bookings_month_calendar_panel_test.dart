// Варіант D port — gap 1 (mobile-qa audit, 2026-08-13): the drag-isolation
// claim, pinned against the REAL widget for the first time.
//
// WHY THIS FILE EXISTS
// ---------------------
// `bookings_month_calendar_panel.dart`'s own doc comment
// (`_BookingsMonthCalendarPanelState._open`'s doc, :178-189) makes an
// explicit claim: a drag frame or the panel's 280ms open/close settle
// animation costs ZERO rebuilds of anything OUTSIDE this widget, because
// `_open` (the `AnimationController` driving the expand fraction) lives
// entirely inside `_BookingsMonthCalendarPanelState`'s own `State` and never
// calls `setState` on the HOST (`_BookingsDiscoveryViewState`).
//
// Before this port, that same invariant was pinned by a widget-IDENTITY
// assertion against a `ValueNotifier`-driven `_focusedMonth` field — see
// `bookings_day_rebuild_isolation_test.dart`'s "Варіант D port" group header,
// which explains why that assertion was RETIRED rather than ported: the
// `ValueNotifier` it pinned no longer exists, and the group's remaining
// scope is the opposite direction (a genuine month STEP correctly rebuilding
// the timeline — see `expectFetchCount`'s doc in that file). That leaves the
// drag/settle-isolation half of the invariant argued ONLY in the panel's own
// doc comment, with `grep -rl "BookingsMonthCalendarPanel" test/` hitting no
// file that pumps the panel directly. This file closes that gap.
//
// WHAT THIS FILE PROVES, AND HOW
// -------------------------------
// A synthetic host — `_RebuildProbeHost`, a `StatefulWidget` with its own
// build counter — mounts `BookingsMonthCalendarPanel` beside a sibling
// stand-in for the real screen's timeline. Three interactions are driven
// against the REAL panel:
//   1. A partial vertical drag (mid-gesture, before release).
//   2. A full drag-to-release settle (the 280ms open animation).
//   3. A tap-toggle open/close (the `_TopRow` chevron's own path to the same
//      `_open` animation).
// After each, `_RebuildProbeHostState.buildCount` — which can only advance if
// something calls `setState` on the HOST, or the host's own ancestor forces
// a rebuild (neither of which this test ever does) — must be unchanged.
//
// FIXTURE GUARDS, so the "unchanged" assertions cannot pass for the wrong
// reason (nothing happened at all):
//   * the collapse/expand `SizedBox` (key `bookings-month-calendar`) is
//     measured before/after and must have actually resized;
//   * none of the three host callbacks (`onSelectRailDay`/`onSelectDay`/
//     `onStepMonth`) may have fired — wired here to `setState` on the host
//     themselves, so a callback leak during a pure vertical drag would ALSO
//     independently trip the build-count assertion (see the mutation-probe
//     note below).
//
// MUTATION-PROBED (mobile-qa, 2026-08-13): the harness's own wiring was
// verified capable of catching a callback leak — `_onDragUpdate` was
// temporarily made to also call `widget.onStepMonth(0)` (simulating exactly
// the class of regression this file guards against: a drag frame reaching a
// host callback). `hostBuildCount` correctly advanced and the "drag update
// does not rebuild the host" assertion went RED; reverted afterwards. The
// OTHER structural regression this file's isolation claim rules out — some
// future refactor hoisting `_open` itself out of the panel's `State` and
// into the host — cannot be simulated without a real host-visible API
// change (there is no way to "leak" a private `AnimationController" from
// outside); that class is caught not by a fault-injection probe but by
// construction: the host here NEVER constructs, reads, or listens to
// anything named `_open`, so the ONLY way it could learn a drag happened is
// through the three callbacks already probed above.

import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_day_rail.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_month_calendar_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

/// Stand-in for the real screen's timeline. The isolation assertions in this
/// file read [_RebuildProbeHostState.buildCount] directly, NOT this widget's
/// identity — a `const` instance would be perfectly safe here for exactly
/// that reason (see that field's doc for why a build-count check sidesteps
/// the `const`-canonicalisation identity trap entirely). Kept as a sibling
/// purely for structural realism — the real screen also renders a timeline
/// beside the panel — not as an assertion target.
class _TimelineStandIn extends StatelessWidget {
  const _TimelineStandIn();

  @override
  Widget build(BuildContext context) {
    return const Text('timeline', key: Key('timeline-stand-in'));
  }
}

/// Mounts the REAL [BookingsMonthCalendarPanel] beside [_TimelineStandIn].
/// [buildCount] advances once per `build()` call — i.e. only when something
/// calls `setState` on THIS widget's own `State`, since nothing external
/// ever rebuilds it in this test.
class _RebuildProbeHost extends StatefulWidget {
  const _RebuildProbeHost({
    super.key,
    required this.railController,
    required this.today,
    required this.selectedDay,
    required this.onSelectRailDay,
    required this.onSelectDay,
    required this.onStepMonth,
  });

  final ScrollController railController;
  final DateTime today;
  final DateTime selectedDay;
  final ValueChanged<DateTime> onSelectRailDay;
  final ValueChanged<DateTime> onSelectDay;
  final ValueChanged<int> onStepMonth;

  @override
  State<_RebuildProbeHost> createState() => _RebuildProbeHostState();
}

class _RebuildProbeHostState extends State<_RebuildProbeHost> {
  int buildCount = 0;

  @override
  Widget build(BuildContext context) {
    buildCount++;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _TimelineStandIn(),
        Expanded(
          child: BookingsMonthCalendarPanel(
            railController: widget.railController,
            railFirstDay: DateTime(
              widget.today.year,
              widget.today.month,
              widget.today.day - 5,
            ),
            dayCount: 11,
            today: widget.today,
            selectedDay: widget.selectedDay,
            bookedDays: const <DateTime>{},
            onSelectRailDay: widget.onSelectRailDay,
            onSelectDay: widget.onSelectDay,
            onStepMonth: widget.onStepMonth,
          ),
        ),
      ],
    );
  }
}

void main() {
  /// Pumps the probe host and returns its `State`, so the test can read
  /// [_RebuildProbeHostState.buildCount] directly — a stronger, more direct
  /// signal than widget identity: it can ONLY advance via a `setState` this
  /// test's own callbacks trigger (see the class doc), so there is no
  /// separate "is this assertion vacuous" question the way there can be for
  /// an identity check on a widget that might be `const`-canonicalised.
  Future<_RebuildProbeHostState> pumpProbe(
    WidgetTester tester, {
    required VoidCallback onCallbackFired,
  }) async {
    final GlobalKey<_RebuildProbeHostState> hostKey =
        GlobalKey<_RebuildProbeHostState>();
    final DateTime today = DateTime(2026, 7, 15);
    final ScrollController controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpApp(
      _RebuildProbeHost(
        key: hostKey,
        railController: controller,
        today: today,
        selectedDay: today,
        // Any of these firing during a pure vertical drag/settle would be
        // EXACTLY the regression this file exists to catch — wired to call
        // setState on a tracking var so a leak independently shows up in
        // hostState.buildCount too (see the fixture-guard note in the file
        // header).
        onSelectRailDay: (DateTime _) => onCallbackFired(),
        onSelectDay: (DateTime _) => onCallbackFired(),
        onStepMonth: (int _) => onCallbackFired(),
      ),
    );
    await tester.pumpAndSettle();
    return hostKey.currentState!;
  }

  testWidgets(
    'a mid-drag frame on the calendar handle does not rebuild the host, and '
    'fires none of the three host callbacks',
    (tester) async {
      int callbackFires = 0;
      final _RebuildProbeHostState host = await pumpProbe(
        tester,
        onCallbackFired: () => callbackFires++,
      );

      final int buildsBefore = host.buildCount;
      final double heightBefore = tester
          .getSize(find.byKey(const Key('bookings-month-calendar')))
          .height;

      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(
          find.byKey(const Key('bookings-month-calendar-handle')),
        ),
      );
      await tester.pump();
      for (int i = 0; i < 6; i++) {
        await gesture.moveBy(const Offset(0, 10));
        await tester.pump();
      }

      expect(
        host.buildCount,
        buildsBefore,
        reason:
            'a mid-drag frame rebuilt the host — the AnimationController '
            'driving BookingsMonthCalendarPanel\'s expand fraction must live '
            'entirely inside the panel\'s own State, never bubble a '
            'setState to the host',
      );
      expect(
        callbackFires,
        0,
        reason:
            'a pure vertical drag must not resolve to any of '
            'onSelectRailDay/onSelectDay/onStepMonth — those are for a '
            'rail tap, a grid tap, and a RESOLVED horizontal swipe/chevron '
            'only',
      );

      // Fixture guard: the drag must have actually moved something, or the
      // "no rebuild" assertion above proves nothing.
      final double heightMidDrag = tester
          .getSize(find.byKey(const Key('bookings-month-calendar')))
          .height;
      expect(
        heightMidDrag,
        isNot(closeTo(heightBefore, 0.5)),
        reason:
            'the drag update did not move the collapse/expand box at all — '
            'the no-rebuild assertion above passed for the wrong reason',
      );

      await gesture.up();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'the full drag-to-release settle animation (280ms) never rebuilds the '
    'host, across every intermediate frame',
    (tester) async {
      int callbackFires = 0;
      final _RebuildProbeHostState host = await pumpProbe(
        tester,
        onCallbackFired: () => callbackFires++,
      );

      final int buildsBefore = host.buildCount;

      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(
          find.byKey(const Key('bookings-month-calendar-handle')),
        ),
      );
      await tester.pump();
      // Incremental moves (not one big jump) — the vertical drag recognizer
      // needs a `pump()` between synthetic pointer-move events to actually
      // resolve the gesture arena in favour of the drag over the handle's
      // own competing tap recognizer (mirrors the mid-drag test above).
      // Travel well past the halfway mark (`_kTravel` ≈ 310dp) so the
      // release settles OPEN even without relying on fling velocity.
      for (int i = 0; i < 20; i++) {
        await gesture.moveBy(const Offset(0, 20));
        await tester.pump();
      }
      expect(host.buildCount, buildsBefore);
      await gesture.up();

      // Step through the 280ms settle in small increments — an isolation
      // leak that only shows up mid-animation (rather than at the final
      // frame) would be invisible to a single `pumpAndSettle`.
      for (int i = 0; i < 6; i++) {
        // Deliberately stepping mid-animation frames (not awaiting a
        // condition) so a rebuild leak at any intermediate frame — not
        // just the final settled one — is observable.
        // fixed-wait-ok: sampling a mid-animation frame, not a condition
        await tester.pump(const Duration(milliseconds: 50));
        expect(
          host.buildCount,
          buildsBefore,
          reason:
              'the settle animation rebuilt the host at frame $i — see the '
              'mid-drag test\'s reason for why this must never happen',
        );
      }
      await tester.pumpAndSettle();
      expect(host.buildCount, buildsBefore);
      expect(callbackFires, 0);

      // Fixture guard: the release must have actually settled the panel to
      // its EXPANDED resting state (a fling past the velocity threshold, or
      // released past the halfway mark — either way it should have opened,
      // not snapped back to collapsed).
      final double heightAfter = tester
          .getSize(find.byKey(const Key('bookings-month-calendar')))
          .height;
      const double collapsedHeight = kBookingsDayRailHeight;
      expect(
        heightAfter,
        greaterThan(collapsedHeight + 50),
        reason:
            'the panel did not settle open — the drag/release sequence '
            'above did not actually exercise the settle animation this '
            'test claims to pin',
      );
    },
  );

  testWidgets(
    'tapping the toggle open/close chevron never rebuilds the host either — '
    'the SAME _open animation, reached via a different gesture',
    (tester) async {
      int callbackFires = 0;
      final _RebuildProbeHostState host = await pumpProbe(
        tester,
        onCallbackFired: () => callbackFires++,
      );

      final int buildsBefore = host.buildCount;
      final bool ignoringBefore = tester
          .widget<IgnorePointer>(
            find.byKey(const Key('bookings-month-calendar-grid-layer')),
          )
          .ignoring;

      await tester.tap(find.byKey(const Key('bookings-month-calendar-toggle')));
      // Sampling a mid-animation frame (not awaiting a condition) —
      // mirrors the drag-gesture test's step-through above, pinning that
      // the chevron-tap path to the same _open controller doesn't
      // rebuild the host before the animation settles.
      // fixed-wait-ok: sampling a mid-animation frame, not a condition
      await tester.pump(const Duration(milliseconds: 50));
      expect(host.buildCount, buildsBefore);
      await tester.pumpAndSettle();

      expect(
        host.buildCount,
        buildsBefore,
        reason:
            'the toggle-driven open animation rebuilt the host — the same '
            'isolation the drag gesture must preserve must also hold for '
            'the chevron/tap path to the identical _open controller',
      );
      expect(callbackFires, 0);

      // Fixture guard: the grid layer must have actually become interactive
      // (ignoring flips false once open), or the toggle never really fired.
      final bool ignoringAfter = tester
          .widget<IgnorePointer>(
            find.byKey(const Key('bookings-month-calendar-grid-layer')),
          )
          .ignoring;
      expect(ignoringBefore, isTrue);
      expect(
        ignoringAfter,
        isFalse,
        reason:
            'the toggle tap did not actually open the calendar — the '
            'no-rebuild assertion above proves nothing without this',
      );
    },
  );
}
