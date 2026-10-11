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

/// Awaits [run] and returns its [TestFailure], or null if it passed. Region
/// mode pumps inside the call, so `expectLater` (which refuses to start while
/// a tester call is pending) cannot wrap it.
Future<TestFailure?> _failureOf(Future<void> run) async {
  try {
    await run;
  } on TestFailure catch (e) {
    return e;
  }
  return null;
}

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

  group('region mode (two pumps, crop from ancestor boundary)', () {
    const Key kTarget = Key('region-target');

    /// Target embedded in a larger tree; the only RepaintBoundary is the
    /// outer one that owns the ground — none wraps the target.
    Widget tree({
      double opacity = 1.0,
      Widget? target,
      Color sibling = _ink,
      double targetSize = 40,
      double inset = 10,
    }) => Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          child: ColoredBox(
            color: _ground,
            child: Padding(
              padding: EdgeInsets.all(inset),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  KeyedSubtree(
                    key: kTarget,
                    child:
                        target ??
                        Opacity(
                          opacity: opacity,
                          child: SizedBox(
                            width: targetSize,
                            height: 40,
                            child: const ColoredBox(color: _ink),
                          ),
                        ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: 80,
                    height: 40,
                    child: ColoredBox(color: sibling),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    Future<void> measure(
      WidgetTester tester, {
      required Widget full,
      required Widget dimmed,
      required double expected,
    }) => expectRegionDimRatio(
      tester: tester,
      target: find.byKey(kTarget),
      pumpFull: () => tester.pumpWidget(full),
      pumpDimmed: () => tester.pumpWidget(dimmed),
      ground: _ground,
      expected: expected,
    );

    testWidgets('Opacity(0.3) vs 1.0 across two pumps measures as 0.3', (
      tester,
    ) async {
      await measure(
        tester,
        full: tree(),
        dimmed: tree(opacity: 0.3),
        expected: 0.3,
      );
    });

    testWidgets('fails when expected is wrong for a real 0.3 dim', (
      tester,
    ) async {
      expect(
        await _failureOf(
          measure(
            tester,
            full: tree(),
            dimmed: tree(opacity: 0.3),
            expected: 0.6,
          ),
        ),
        isNotNull,
      );
    });

    testWidgets(
      'a sibling changing OUTSIDE the region does not move the ratio',
      (tester) async {
        await measure(
          tester,
          full: tree(),
          dimmed: tree(opacity: 0.3, sibling: const Color(0xFF1A1A8B)),
          expected: 0.3,
        );
      },
    );

    testWidgets(
      'different target geometry between pumps fails with the reason',
      (tester) async {
        expect(
          (await _failureOf(
            measure(
              tester,
              full: tree(),
              dimmed: tree(opacity: 0.3, targetSize: 30),
              expected: 0.3,
            ),
          ))?.message,
          contains('geometry differs'),
        );
      },
    );

    testWidgets(
      'a 1dp shift fails by default but passes with geometryTolerance',
      (tester) async {
        Future<void> shifted({double? geometryTolerance}) =>
            expectRegionDimRatio(
              tester: tester,
              target: find.byKey(kTarget),
              pumpFull: () => tester.pumpWidget(tree()),
              pumpDimmed: () =>
                  tester.pumpWidget(tree(opacity: 0.3, inset: 11)),
              ground: _ground,
              expected: 0.3,
              geometryTolerance: geometryTolerance ?? 0.01,
            );

        expect(
          (await _failureOf(shifted()))?.message,
          contains('geometry differs'),
        );
        await shifted(geometryTolerance: 1.01);
      },
    );

    testWidgets('a missing target fails with a clear reason', (tester) async {
      expect(
        (await _failureOf(
          expectRegionDimRatio(
            tester: tester,
            target: find.byKey(const Key('nope')),
            pumpFull: () => tester.pumpWidget(tree()),
            pumpDimmed: () => tester.pumpWidget(tree()),
            ground: _ground,
            expected: 0.3,
          ),
        ))?.message,
        contains('exactly one'),
      );
    });

    testWidgets('AnimatedOpacity pumped past its tween measures correctly', (
      tester,
    ) async {
      Widget animated(double a) => AnimatedOpacity(
        opacity: a,
        duration: const Duration(milliseconds: 200),
        child: const SizedBox(
          width: 40,
          height: 40,
          child: ColoredBox(color: _ink),
        ),
      );

      await expectRegionDimRatio(
        tester: tester,
        target: find.byKey(kTarget),
        pumpFull: () => tester.pumpWidget(tree(target: animated(1.0))),
        pumpDimmed: () async {
          await tester.pumpWidget(tree(target: animated(0.4)));
          // AnimatedOpacity runs on tickers (no Timers): settle past its tween.
          await tester.pumpAndSettle();
        },
        ground: _ground,
        expected: 0.4,
      );
    });

    testWidgets(
      'a 2.0 view crops the logical rect, not a DPR-scaled one (sibling outside the region differs)',
      (tester) async {
        // A crop scaled by the DPR while capturing at 1.0 would reach
        // (20..100)px and swallow the recoloured sibling below the target;
        // the correct (10..50) crop never touches it.
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.resetDevicePixelRatio);
        await measure(
          tester,
          full: tree(),
          dimmed: tree(opacity: 0.3, sibling: const Color(0xFF1A1A8B)),
          expected: 0.3,
        );
      },
    );

    testWidgets('a supplied reason is appended to a ratio failure', (
      tester,
    ) async {
      final TestFailure? f = await _failureOf(
        expectRegionDimRatio(
          tester: tester,
          target: find.byKey(kTarget),
          pumpFull: () => tester.pumpWidget(tree()),
          pumpDimmed: () => tester.pumpWidget(tree(opacity: 0.3)),
          ground: _ground,
          expected: 0.6,
          reason: 'replica drifted?',
        ),
      );
      expect(f?.message, contains('replica drifted?'));
    });
  });
}
