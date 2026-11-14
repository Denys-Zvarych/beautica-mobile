// Phase 484 — ForwardedScrollDrag: a horizontal drag from a non-scrollable
// (the week strip, the week grid's header row) forwarded onto a scrollable's
// position as a real `ScrollPosition.drag`. Pins: no-op without exactly one
// position, 1:1 and scaled updates, release velocity → the target's own
// fling (scaled / inverted), zero velocity → no motion, cancel, restart, and
// the position taking over (jumpTo) clearing `isActive`.
import 'package:beautica_mobile/features/booking/presentation/widgets/forwarded_scroll_drag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const double _start = 1000;

/// A horizontal list 400 px wide, 5000 px of content, clamping physics,
/// parked at [_start]. Returns the attached controller.
Future<ScrollController> _pumpList(WidgetTester tester) async {
  final ScrollController c = ScrollController(initialScrollOffset: _start);
  addTearDown(c.dispose);
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 400,
          height: 100,
          child: ListView.builder(
            controller: c,
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            itemCount: 50,
            itemExtent: 100,
            itemBuilder: (BuildContext context, int i) => Text('$i'),
          ),
        ),
      ),
    ),
  );
  return c;
}

DragStartDetails _down() =>
    DragStartDetails(globalPosition: const Offset(200, 50));

DragUpdateDetails _move(double dx) => DragUpdateDetails(
  globalPosition: Offset(200 + dx, 50),
  delta: Offset(dx, 0),
  primaryDelta: dx,
);

DragEndDetails _up(double vx) => DragEndDetails(
  velocity: Velocity(pixelsPerSecond: Offset(vx, 0)),
  primaryVelocity: vx,
);

void main() {
  test('unattached controller: start is a no-op, nothing throws', () {
    final ScrollController c = ScrollController();
    addTearDown(c.dispose);
    final ForwardedScrollDrag drag = ForwardedScrollDrag();

    drag.start(c, _down());
    drag.update(_move(10));
    drag.end(_up(500));
    drag.cancel();

    expect(drag.isActive, isFalse);
  });

  testWidgets('two attached positions: start is a no-op', (tester) async {
    final ScrollController shared = ScrollController(
      initialScrollOffset: _start,
    );
    addTearDown(shared.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: <Widget>[
            for (int k = 0; k < 2; k++)
              SizedBox(
                width: 400,
                height: 100,
                child: ListView(
                  controller: shared,
                  scrollDirection: Axis.horizontal,
                  children: const <Widget>[SizedBox(width: 5000)],
                ),
              ),
          ],
        ),
      ),
    );
    expect(shared.positions.length, 2);
    final ForwardedScrollDrag drag = ForwardedScrollDrag();

    drag.start(shared, _down());

    expect(drag.isActive, isFalse);
  });

  testWidgets('scale 1: finger right moves the content right (pixels down)', (
    tester,
  ) async {
    final ScrollController c = await _pumpList(tester);
    final ForwardedScrollDrag drag = ForwardedScrollDrag()..start(c, _down());

    drag.update(_move(30));

    expect(drag.isActive, isTrue);
    expect(c.position.pixels, _start - 30);
    drag.cancel();
  });

  testWidgets(
    'scale -2: finger right moves the pixels up by twice the travel',
    (tester) async {
      final ScrollController c = await _pumpList(tester);
      final ForwardedScrollDrag drag = ForwardedScrollDrag()..start(c, _down());

      drag.update(_move(30), scale: -2);

      expect(c.position.pixels, _start + 60);
      drag.cancel();
    },
  );

  testWidgets('end with velocity: the target physics flings past the release '
      'point; isActive clears', (tester) async {
    final ScrollController c = await _pumpList(tester);
    final ForwardedScrollDrag drag = ForwardedScrollDrag()
      ..start(c, _down())
      ..update(_move(-20));
    final double released = c.position.pixels;

    drag.end(_up(-2000));
    await tester.pumpAndSettle();

    expect(drag.isActive, isFalse);
    expect(c.position.pixels, greaterThan(released + 100));
  });

  testWidgets('end with a negative scale inverts the fling direction', (
    tester,
  ) async {
    final ScrollController c = await _pumpList(tester);
    final ForwardedScrollDrag drag = ForwardedScrollDrag()
      ..start(c, _down())
      ..update(_move(20), scale: -1);
    final double released = c.position.pixels;
    expect(released, _start + 20);

    // Finger flung RIGHT; scale -1 → the pixels keep increasing.
    drag.end(_up(2000), scale: -1);
    await tester.pumpAndSettle();

    expect(c.position.pixels, greaterThan(released + 100));
  });

  testWidgets('end with zero velocity: no motion after release', (
    tester,
  ) async {
    final ScrollController c = await _pumpList(tester);
    final ForwardedScrollDrag drag = ForwardedScrollDrag()
      ..start(c, _down())
      ..update(_move(-40));

    drag.end(_up(0));
    await tester.pumpAndSettle();

    expect(c.position.pixels, _start + 40);
  });

  testWidgets('cancel: isActive clears, later updates/ends are no-ops, the '
      'position is free again', (tester) async {
    final ScrollController c = await _pumpList(tester);
    final ForwardedScrollDrag drag = ForwardedScrollDrag()
      ..start(c, _down())
      ..update(_move(-10));

    drag.cancel();
    drag.update(_move(-50));
    drag.end(_up(-3000));
    await tester.pumpAndSettle();

    expect(drag.isActive, isFalse);
    expect(c.position.pixels, _start + 10);
    expect(c.position.isScrollingNotifier.value, isFalse);
  });

  testWidgets('a second start replaces the first: one drag, deltas not '
      'doubled', (tester) async {
    final ScrollController c = await _pumpList(tester);
    final ForwardedScrollDrag drag = ForwardedScrollDrag()
      ..start(c, _down())
      ..update(_move(-10));

    drag.start(c, _down());
    drag.update(_move(-10));

    expect(drag.isActive, isTrue);
    expect(c.position.pixels, _start + 20);
    drag.end(_up(0));
    await tester.pumpAndSettle();
    expect(drag.isActive, isFalse);
  });

  testWidgets('the position taking over (jumpTo) drops the drag', (
    tester,
  ) async {
    final ScrollController c = await _pumpList(tester);
    final ForwardedScrollDrag drag = ForwardedScrollDrag()..start(c, _down());

    c.jumpTo(500);
    drag.update(_move(-50));

    expect(drag.isActive, isFalse);
    expect(c.position.pixels, 500);
  });
}
