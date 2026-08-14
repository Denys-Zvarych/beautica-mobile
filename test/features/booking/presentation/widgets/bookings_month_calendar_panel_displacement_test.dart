// Варіант D port — gap 4 (mobile-qa audit, 2026-08-13): pins the LOCKED
// product requirement that the expandable month calendar DISPLACES the
// booking timeline downward as it opens, and never paints over it.
//
// WHY THIS FILE EXISTS
// ---------------------
// An earlier revision of `BookingsMonthCalendarPanel`'s mobile-perf HIGH fix
// let the expanding panel draw OVER the timeline instead of pushing it down
// — see `bookings_month_calendar_panel.dart`'s file header ("The timeline
// lives INSIDE this widget's subtree") and
// `kBookingsMonthCalendarPanelCollapsedHeight`'s doc for the full history.
// The user rejected that overlay once it shipped. Nothing in the existing
// suite asserted the non-overlap requirement itself — `grep -rl
// "displac" test/` hit nothing before this file. If someone reverts to the
// overlay, or the `Transform.translate` distance drifts out of sync with
// the panel's own growing height, nothing would go red.
//
// WHY GEOMETRY, NOT WIDGET STRUCTURE
// -----------------------------------
// The displacement is done entirely at PAINT time (`Transform.translate`
// inside an `AnimatedBuilder`), clipped by a `ClipRect` sized to a FIXED
// `Positioned` box. Both clip SILENTLY — an overlap here would never throw a
// `RenderFlex overflow` error (the same point
// `bookings_month_calendar_short_device_test.dart`'s header makes about a
// different silent-clip failure mode in this same widget). The only way to
// catch a regression is to measure real `Rect`s via `tester.getRect`, which
// walks the full render-object ancestor chain — including the
// `Transform.translate` — so it reads the ACTUAL post-transform position,
// not the widget tree's static layout slot.
//
// THE INVARIANT PINNED
// ---------------------
// By construction (see `kBookingsMonthCalendarPanelCollapsedHeight`'s doc),
// the timeline's fixed box top sits `VelvetSpacing.sm` below the panel's
// COLLAPSED (t=0) bottom edge, and the translate offset (`_kTravel *
// _open.value`) grows at exactly the same rate as the panel's own bottom
// edge as `_open` increases — so the rendered gap between the panel's
// bottom edge (its drag handle, the last visual element in its own
// `Column`) and the timeline's rendered top edge should stay pinned at
// `VelvetSpacing.sm` at EVERY value of `_open`, not just the two resting
// ends. This file samples that gap at t=0 (collapsed), two intermediate
// mid-drag fractions (~0.3 and ~0.7), and t=1 (fully open, settled) — the
// whole failure mode of the rejected overlay design was content sitting
// under the panel MID-animation, not just at the endpoints.
//
// MUTATION-PROBED (mobile-qa, 2026-08-13): `Offset(0, _kTravel *
// _open.value)` in `bookings_month_calendar_panel.dart`'s `Transform
// .translate` was temporarily changed to `Offset.zero` — restoring exactly
// the rejected overlay (the timeline's rendered position stops tracking
// `_open` at all). Every assertion in the mid-drag and fully-open tests
// below went RED (the t=0 test stayed green, as expected — at rest there is
// nothing to translate either way, so it cannot distinguish the two
// designs; that is exactly why this file also samples t>0). Reverted via
// the backed-up original afterwards — see the mobile-qa report for the
// exact before/after run.

import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_day_rail.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_month_calendar_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

/// A tall, trivially-measurable stand-in for the real screen's timeline —
/// tall enough that its top edge is unambiguous at any expand fraction.
class _TimelineStandIn extends StatelessWidget {
  const _TimelineStandIn();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('displacement-timeline-content'),
      height: 2000,
      color: Colors.blue,
    );
  }
}

/// Mounts the REAL [BookingsMonthCalendarPanel] the same way the real host
/// (`BookingsDiscoveryView`) does — inside an `Expanded`, so the panel's own
/// `Stack` gets a bounded, non-zero height to lay its `Positioned` children
/// out against, exactly mirroring production's composition.
class _Host extends StatelessWidget {
  const _Host({required this.railController, required this.today});

  final PageController railController;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: BookingsMonthCalendarPanel(
            railController: railController,
            railFirstWeekStart: mondayOf(
              DateTime(today.year, today.month, today.day - 7),
            ),
            weekCount: 3,
            today: today,
            selectedDay: today,
            bookedDays: const <DateTime>{},
            onSelectRailDay: (DateTime _) {},
            onSelectDay: (DateTime _) {},
            onStepMonth: (int _) {},
            timeline: const _TimelineStandIn(),
          ),
        ),
      ],
    );
  }
}

void main() {
  Future<void> pumpHost(WidgetTester tester) async {
    final PageController controller = PageController(initialPage: 1);
    addTearDown(controller.dispose);
    final DateTime today = DateTime(2026, 7, 15);

    await tester.pumpApp(
      _Host(railController: controller, today: today),
      // Generous headroom for the panel's OWN Stack — a separate concern
      // (short-device clipping) from the displacement invariant this file
      // pins; that concern belongs to
      // `bookings_month_calendar_short_device_test.dart`.
      height: 1200,
    );
    await tester.pumpAndSettle();
  }

  /// The panel's own painted bottom edge. `_DragHandle` is the LAST visual
  /// element in `_BookingsMonthCalendarPanelState.build`'s own `Column`
  /// (after `_TopRow` and the collapse/expand box) — see
  /// `kBookingsMonthCalendarPanelCollapsedHeight`'s doc, whose sum of terms
  /// this rect's bottom is the runtime witness for.
  double panelBottom(WidgetTester tester) => tester
      .getRect(find.byKey(const Key('bookings-month-calendar-handle')))
      .bottom;

  /// The timeline's rendered top edge, post-`Transform.translate`.
  double timelineTop(WidgetTester tester) => tester
      .getRect(find.byKey(const Key('displacement-timeline-content')))
      .top;

  void expectDisplaced(WidgetTester tester, {required String at}) {
    final double panel = panelBottom(tester);
    final double timeline = timelineTop(tester);
    expect(
      timeline,
      greaterThanOrEqualTo(panel),
      reason:
          'at $at the timeline\'s top edge ($timeline) sits ABOVE the '
          'panel\'s painted bottom edge ($panel) — the calendar is painting '
          'OVER the list again, the exact overlay the user rejected',
    );
    expect(
      timeline - panel,
      closeTo(VelvetSpacing.sm, 0.5),
      reason:
          'at $at the gap between the panel\'s bottom edge and the '
          'timeline\'s top edge is ${timeline - panel}, not the locked '
          'VelvetSpacing.sm margin — the translate offset has drifted out '
          'of sync with the panel\'s growing bottom edge',
    );
  }

  testWidgets('collapsed (t=0): the timeline sits VelvetSpacing.sm below the '
      'collapsed panel, never overlapping it', (tester) async {
    await pumpHost(tester);
    expectDisplaced(tester, at: 't=0 (collapsed)');
  });

  testWidgets(
    'mid-drag (t≈0.3 and t≈0.7): the timeline stays displaced below the '
    'panel at intermediate expand fractions, not just the resting ends — '
    'the failure mode of the rejected overlay design was content sitting '
    'UNDER the panel mid-animation',
    (tester) async {
      await pumpHost(tester);

      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(
          find.byKey(const Key('bookings-month-calendar-handle')),
        ),
      );
      await tester.pump();

      // _kTravel ≈ 262dp (kMonthCalendarExpandedHeight 332 −
      // kBookingsDayRailHeight 70; the expanded height lost 48dp when the
      // grid's own month header was retired). 10 moves of 10dp = 100dp ≈
      // 0.38 * _kTravel — see `_BookingsMonthCalendarPanelState
      // ._onDragUpdate`'s exact conversion this mirrors.
      for (int i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(0, 10));
        await tester.pump();
      }
      expectDisplaced(tester, at: 't≈0.3 (mid-drag)');

      // Continue the SAME drag further open — another 130dp, ≈0.88 total.
      for (int i = 0; i < 13; i++) {
        await gesture.moveBy(const Offset(0, 10));
        await tester.pump();
      }
      expectDisplaced(tester, at: 't≈0.7 (mid-drag, further open)');

      await gesture.up();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'fully open (t=1, settled): the timeline stays displaced below the '
    'fully expanded panel',
    (tester) async {
      await pumpHost(tester);

      await tester.tap(find.byKey(const Key('bookings-month-calendar-toggle')));
      await tester.pumpAndSettle();

      expectDisplaced(tester, at: 't=1 (fully open)');
    },
  );
}
