// Phase 482 — DaySnapScrollPhysics: a fling lands on the nearest whole
// column, clamped to Monday-left .. Sunday-last-visible.
import 'package:beautica_mobile/features/booking/presentation/widgets/day_snap_scroll_physics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// 3 of 7 days on a 360 dp pager: one column = 120, max = 4 columns.
const double _kViewport = 360;
const double _kColumn = 120;
const double _kMax = 4 * _kColumn;

ScrollMetrics _at(double pixels) => FixedScrollMetrics(
  minScrollExtent: 0,
  maxScrollExtent: _kMax,
  pixels: pixels,
  viewportDimension: _kViewport,
  axisDirection: AxisDirection.right,
  devicePixelRatio: 1,
);

const DaySnapScrollPhysics _physics = DaySnapScrollPhysics(
  visibleColumns: 3,
  parent: ClampingScrollPhysics(),
);

double _restOf(Simulation sim) {
  double t = 0;
  while (!sim.isDone(t) && t < 10) {
    t += 0.016;
  }
  return sim.x(t);
}

void main() {
  test('zero-velocity end is left alone (the settle timer snaps)', () {
    expect(_physics.createBallisticSimulation(_at(50), 0), isNull);
  });

  test('a hard fling runs to the week end, clamped at Sunday', () {
    final Simulation? sim = _physics.createBallisticSimulation(_at(0), 6000);
    expect(sim, isNotNull);
    expect(
      _restOf(sim ?? (throw StateError('no simulation'))),
      closeTo(_kMax, 0.5),
    );
  });

  test('a hard fling back is clamped at Monday', () {
    final Simulation? sim = _physics.createBallisticSimulation(
      _at(_kMax),
      -6000,
    );
    expect(
      _restOf(sim ?? (throw StateError('no simulation'))),
      closeTo(0, 0.5),
    );
  });

  test('a moderate fling rests on the nearest whole column', () {
    for (final double v in <double>[150, 400, 900, -300, -700]) {
      final Simulation? sim = _physics.createBallisticSimulation(_at(170), v);
      final double rest = _restOf(sim ?? (throw StateError('no simulation')));
      final double columns = rest / _kColumn;
      expect(
        (columns - columns.round()).abs(),
        lessThan(0.01),
        reason: 'v=$v rests at $rest',
      );
    }
  });

  test('applyTo keeps visibleColumns', () {
    final DaySnapScrollPhysics applied = _physics.applyTo(
      const BouncingScrollPhysics(),
    );
    expect(applied.visibleColumns, 3);
  });
}
