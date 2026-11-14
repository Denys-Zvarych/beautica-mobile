// Phase 481 — `FixedLinesText` (promoted from `master_booking_card.dart`'s
// private `_FixedLinesText`) and its additive `FixedLinesText.fit` mode.
import 'package:beautica_mobile/shared/widgets/fixed_lines_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

const TextStyle _kStyle = TextStyle(fontSize: 10, height: 1.2);
const String _kLong =
    'Манікюр з покриттям гель-лак, корекція брів, ламінування вій, '
    'педикюр апаратний, догляд за шкірою рук з парафінотерапією';
const Key _kKey = Key('fixed-lines');

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double? height,
  double scale = 1.0,
}) => tester.pumpApp(
  Center(
    child: SizedBox(width: 120, height: height, child: child),
  ),
  textScaleFactor: scale,
);

Text _text(WidgetTester tester) => tester.widget<Text>(
  find.descendant(of: find.byKey(_kKey), matching: find.byType(Text)),
);

void main() {
  group('fixedLineHeight — whole dp, scale-aware', () {
    for (final (double scale, double expected) in <(double, double)>[
      (1.0, 12),
      (1.3, 16), // ceil(13 × 1.2 = 15.6)
    ]) {
      testWidgets('10 sp × 1.2 @ ${scale}x = $expected', (tester) async {
        late double measured;
        await _pump(
          tester,
          Builder(
            builder: (BuildContext context) {
              measured = fixedLineHeight(context, _kStyle);
              return const SizedBox.shrink();
            },
          ),
          scale: scale,
        );
        expect(measured, expected);
      });
    }
  });

  group('original constructor — exact lines box', () {
    testWidgets('occupies lines × line height whatever the text', (
      tester,
    ) async {
      await _pump(
        tester,
        const FixedLinesText('Іра', key: _kKey, style: _kStyle, lines: 2),
      );
      expect(tester.getSize(find.byKey(_kKey)).height, 24);
      expect(_text(tester).maxLines, 2);
    });
  });

  group('fit — whole lines from the height given', () {
    // (height, scale) → whole lines: floor(height / ceil(10·s·1.2)), min 1.
    for (final (double h, double scale, int lines) in <(double, double, int)>[
      (12, 1.0, 1),
      (35, 1.0, 2),
      (36, 1.0, 3),
      (60, 1.0, 5),
      (15, 1.3, 1),
      (31, 1.3, 1),
      (32, 1.3, 2),
      (60, 1.3, 3),
      (5, 1.0, 1), // below one line → still 1 (min)
    ]) {
      testWidgets('${h.toInt()} dp @ ${scale}x → $lines line(s)', (
        tester,
      ) async {
        await _pump(
          tester,
          const FixedLinesText.fit(_kLong, key: _kKey, style: _kStyle),
          height: h,
          scale: scale,
        );
        expect(_text(tester).maxLines, lines);
        expect(_text(tester).overflow, TextOverflow.ellipsis);
      });
    }

    testWidgets('unbounded height falls back to `lines` (1)', (tester) async {
      await tester.pumpApp(
        const Center(
          child: SizedBox(
            width: 120,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                FixedLinesText.fit(_kLong, key: _kKey, style: _kStyle),
              ],
            ),
          ),
        ),
      );
      expect(_text(tester).maxLines, 1);
    });

    testWidgets('a short text in a tall slot is NOT stretched or centred', (
      tester,
    ) async {
      await tester.pumpApp(
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 120,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: const FixedLinesText.fit(
                'Брови',
                key: _kKey,
                style: _kStyle,
              ),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byKey(_kKey)).height, 12);
    });

    group('availableHeight (caller already measured — no LayoutBuilder)', () {
      for (final (double h, int lines) in <(double, int)>[
        (5, 1),
        (36, 3),
        (37, 3),
      ]) {
        testWidgets('${h.toInt()} dp → $lines line(s), unbounded parent', (
          tester,
        ) async {
          await tester.pumpApp(
            Center(
              child: SizedBox(
                width: 120,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    FixedLinesText.fit(
                      _kLong,
                      key: _kKey,
                      style: _kStyle,
                      availableHeight: h,
                    ),
                  ],
                ),
              ),
            ),
          );
          expect(_text(tester).maxLines, lines);
          expect(
            find.descendant(
              of: find.byKey(_kKey),
              matching: find.byType(LayoutBuilder),
            ),
            findsNothing,
          );
          expect(tester.getSize(find.byKey(_kKey)).height, 12.0 * lines);
        });
      }

      testWidgets('a short text is top-aligned at its own height', (
        tester,
      ) async {
        await tester.pumpApp(
          const Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 120,
              child: FixedLinesText.fit(
                'Брови',
                key: _kKey,
                style: _kStyle,
                availableHeight: 200,
              ),
            ),
          ),
        );
        expect(_text(tester).maxLines, FixedLinesText.linesFor(200, 12));
        expect(tester.getSize(find.byKey(_kKey)).height, 12);
      });
    });
  });
}
