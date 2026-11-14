// Phase 486 — `WeekStrip.entrance`, the strip half of the week view's load
// moment, at the widget level (the screen-level journey is
// `week_time_grid_entrance_test.dart`'s).
//
// Pinned here:
//   * `entrance: null` (the default, every pre-486 caller) = the window at
//     rest on its page, and the window listens to the bare pager — exactly
//     the pre-486 strip;
//   * the window glides Monday → page with the controller (0 → Monday,
//     mid → between, 1 → identical to `null`);
//   * reduced motion: the entrance is ignored, the window sits on its page
//     even at controller value 0;
//   * the merged (pager, entrance) listenable is built once per pair, not
//     per parent rebuild.
import 'package:beautica_mobile/features/booking/domain/week_day_model.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/week_strip.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/week_time_grid.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

// future-date-ok: pinned fixture week; `today` is injected, never the host.
final DateTime _monday = DateTime(2026, 11, 16);
final DateTime _today = kyivAddDays(_monday, 3);

const List<int> _noCounts = <int>[0, 0, 0, 0, 0, 0, 0];
const List<bool> _noOff = <bool>[
  false,
  false,
  false,
  false,
  false,
  false,
  false,
];

/// Strip + the shared pager it follows. [rebuild] re-runs this widget's
/// build without touching the strip's inputs (a parent `setState`).
class _Harness extends StatelessWidget {
  const _Harness({
    required this.controller,
    required this.entrance,
    required this.rebuild,
  });

  final PageController controller;
  final ValueNotifier<Animation<double>?> entrance;
  final ValueNotifier<int> rebuild;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[entrance, rebuild]),
      builder: (BuildContext context, Widget? _) => Column(
        children: <Widget>[
          WeekStrip(
            weekStart: _monday,
            today: _today,
            counts: _noCounts,
            dayOff: _noOff,
            pageController: controller,
            visibleColumns: 3,
            onTapDay: (int _) {},
            onPrevWeek: () {},
            onNextWeek: () {},
            entrance: entrance.value,
          ),
          SizedBox(
            height: 200,
            child: PageView.builder(
              controller: controller,
              itemCount: kWeekGridDays,
              itemBuilder: (BuildContext context, int i) =>
                  Center(child: Text('$i')),
            ),
          ),
        ],
      ),
    );
  }
}

void main() {
  late PageController pager;
  late AnimationController controller;
  late ValueNotifier<Animation<double>?> entrance;
  late ValueNotifier<int> rebuild;

  setUp(() {
    // Fri–Sun open: the window rests four cells right of Monday.
    pager = WeekTimeGrid.controllerFor(visibleColumns: 3, firstVisibleDay: 4);
    controller = AnimationController(
      vsync: const TestVSync(),
      duration: WeekTimeGrid.entranceDuration,
    );
    entrance = ValueNotifier<Animation<double>?>(null);
    rebuild = ValueNotifier<int>(0);
  });

  tearDown(() {
    pager.dispose();
    controller.dispose();
    entrance.dispose();
    rebuild.dispose();
  });

  Future<void> pump(WidgetTester tester) => tester.pumpApp(
    _Harness(controller: pager, entrance: entrance, rebuild: rebuild),
    width: 360,
  );

  Rect days(WidgetTester tester) =>
      tester.getRect(find.byKey(WeekStrip.daysKey));

  double windowLeft(WidgetTester tester) =>
      tester.getTopLeft(find.byKey(WeekStrip.windowKey)).dx;

  double monday(WidgetTester tester) => days(tester).left + 2;

  double resting(WidgetTester tester) =>
      days(tester).left + 4 * days(tester).width / 7 + 2;

  Listenable windowListenable(WidgetTester tester) => tester
      .widget<AnimatedBuilder>(
        find.descendant(
          of: find.byKey(WeekStrip.windowLayerKey),
          matching: find.byType(AnimatedBuilder),
        ),
      )
      .listenable;

  testWidgets('entrance null: the window rests on its page and listens to '
      'the bare pager (the pre-486 strip)', (WidgetTester tester) async {
    await pump(tester);

    expect(windowLeft(tester), closeTo(resting(tester), 0.5));
    expect(identical(windowListenable(tester), pager), isTrue);
  });

  // MUTATION (mobile-qa 2026-11-13): `_glide` returning 1 for every
  // entrance → the 0 / mid samples sat on the page and this went RED.
  // Restored by cp.
  testWidgets('the window glides from Monday to its page with the entrance; '
      'at 1 it sits exactly where `null` puts it', (WidgetTester tester) async {
    await pump(tester);
    final double atRestWithoutEntrance = windowLeft(tester);

    entrance.value = controller;
    await tester.pump();
    expect(windowLeft(tester), closeTo(monday(tester), 0.5));

    controller.value = 0.4;
    await tester.pump();
    expect(windowLeft(tester), greaterThan(monday(tester) + 1));
    expect(windowLeft(tester), lessThan(resting(tester) - 1));

    controller.value = 1;
    await tester.pump();
    expect(windowLeft(tester), atRestWithoutEntrance);
  });

  // MUTATION (mobile-qa 2026-11-13): dropped the strip's
  // `disableAnimationsOf` gate → the window sat on Monday at value 0 and
  // this went RED. Restored by cp.
  testWidgets('reduced motion: the entrance is ignored — the window is on '
      'its page even at value 0', (WidgetTester tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    entrance.value = controller;
    await pump(tester);

    expect(controller.value, 0, reason: 'fixture guard');
    expect(windowLeft(tester), closeTo(resting(tester), 0.5));
    expect(identical(windowListenable(tester), pager), isTrue);
  });

  // MUTATION (mobile-qa 2026-11-13): `_windowListenable` building a fresh
  // `Listenable.merge` on every call → the identity check went RED.
  // Restored by cp.
  testWidgets('the merged listenable is built once per (pager, entrance) — a '
      'parent rebuild reuses it, a new entrance replaces it', (
    WidgetTester tester,
  ) async {
    entrance.value = controller;
    await pump(tester);
    final Listenable first = windowListenable(tester);
    expect(identical(first, pager), isFalse, reason: 'merged while live');

    rebuild.value++;
    await tester.pump();
    expect(identical(windowListenable(tester), first), isTrue);

    final AnimationController other = AnimationController(
      vsync: const TestVSync(),
      duration: WeekTimeGrid.entranceDuration,
      value: 1,
    );
    addTearDown(other.dispose);
    entrance.value = other;
    await tester.pump();
    expect(identical(windowListenable(tester), first), isFalse);

    // The new merge is live: the pager still moves the window.
    pager.jumpToPage(2);
    await tester.pump();
    expect(
      windowLeft(tester),
      closeTo(days(tester).left + 2 * days(tester).width / 7 + 2, 0.5),
    );
  });
}
