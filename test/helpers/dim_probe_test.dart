// Self-test for `dim_probe.dart` — pins the shared layer-opacity probe
// independently of any production widget (Phase 301 reuses it at ~14 sites,
// so the probe itself must be trustworthy).

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dim_probe.dart';

const Color _ground = Color(0xFFFFFFFF);
const Color _ink = Color(0xFF8B1A1A);

const Key _kFull = Key('probe-full');
const Key _kDim = Key('probe-dim');

/// One captured cell: opaque ground INSIDE the boundary, [child] centred.
Widget _cell(Key key, Widget child) => RepaintBoundary(
  key: key,
  child: ColoredBox(
    color: _ground,
    child: SizedBox(width: 60, height: 60, child: Center(child: child)),
  ),
);

Widget _box({Color color = _ink}) =>
    SizedBox(width: 40, height: 40, child: ColoredBox(color: color));

Widget _host({required Widget full, required Widget dimmed}) => Directionality(
  textDirection: TextDirection.ltr,
  child: Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _cell(_kFull, full),
        const SizedBox(height: 8),
        _cell(_kDim, dimmed),
      ],
    ),
  ),
);

Future<void> _measure(
  WidgetTester tester, {
  required double expected,
  double tolerance = kDimProbeTolerance,
}) => expectDimRatio(
  tester: tester,
  dimmed: find.byKey(_kDim),
  full: find.byKey(_kFull),
  ground: _ground,
  expected: expected,
  tolerance: tolerance,
);

void main() {
  group('layer Opacity', () {
    for (final double a in <double>[0.3, 0.6, 1.0]) {
      testWidgets('Opacity($a) measures as $a', (tester) async {
        await tester.pumpWidget(
          _host(
            full: _box(),
            dimmed: Opacity(opacity: a, child: _box()),
          ),
        );

        await _measure(tester, expected: a);
      });
    }
  });

  group('per-element alpha', () {
    testWidgets('Color.withValues(alpha: 0.4) measures as 0.4', (tester) async {
      await tester.pumpWidget(
        _host(
          full: _box(),
          dimmed: _box(color: _ink.withValues(alpha: 0.4)),
        ),
      );

      await _measure(tester, expected: 0.4);
    });
  });

  group('the assertion reads the measurement', () {
    testWidgets('fails when expected is wrong for a real 0.6 dim', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          full: _box(),
          dimmed: Opacity(opacity: 0.6, child: _box()),
        ),
      );

      await expectLater(
        _measure(tester, expected: 0.9),
        throwsA(isA<TestFailure>()),
      );
    });

    testWidgets('fails when no dim is applied but a dim is expected', (
      tester,
    ) async {
      await tester.pumpWidget(_host(full: _box(), dimmed: _box()));

      await expectLater(
        _measure(tester, expected: 0.6),
        throwsA(isA<TestFailure>()),
      );
    });

    testWidgets('a widened tolerance does not hide a gross mismatch', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          full: _box(),
          dimmed: Opacity(opacity: 0.3, child: _box()),
        ),
      );

      await expectLater(
        _measure(tester, expected: 0.6, tolerance: 0.1),
        throwsA(isA<TestFailure>()),
      );
    });
  });

  group('degenerate control', () {
    testWidgets(
      'a full control identical to the ground fails with a clear reason',
      (tester) async {
        // Nothing but ground in both cells: zero denominator.
        await tester.pumpWidget(
          _host(
            full: _box(color: _ground),
            dimmed: Opacity(opacity: 0.6, child: _box(color: _ground)),
          ),
        );

        await expectLater(
          _measure(tester, expected: 0.6),
          throwsA(
            isA<TestFailure>().having(
              (e) => e.message,
              'message',
              contains('full-opacity control must paint something'),
            ),
          ),
        );
      },
    );
  });
}
