// Audit LOW (feat/duplicate-services) — [NameWithHint] on its own: hint
// bidi isolation (FSI/PDI), name ellipsis, the 50 % hint cap, and the
// no-hint path rendering exactly one plain `Text`.

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/name_with_hint.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const Key _nameKey = Key('nwh-name');
const Key _hintKey = Key('service-name-hint');
const TextStyle _style = TextStyle(fontSize: 14);
const String _fsi = '\u2068';
const String _pdi = '\u2069';

Future<void> _pump(
  WidgetTester tester, {
  required String name,
  String? hint,
  double width = 300,
  bool singleLine = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('uk'),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: NameWithHint(
              name: name,
              hint: hint,
              nameStyle: _style,
              nameKey: _nameKey,
              singleLine: singleLine,
            ),
          ),
        ),
      ),
    ),
  );
  expect(tester.takeException(), isNull, reason: 'no overflow / layout error');
}

RenderParagraph _paragraph(WidgetTester tester, Key key) =>
    tester.renderObject<RenderParagraph>(
      find.descendant(of: find.byKey(key), matching: find.byType(RichText)),
    );

void main() {
  group('no hint', () {
    for (final String? hint in <String?>[null, '']) {
      testWidgets('hint ${hint == null ? 'null' : 'empty'} renders one plain '
          'ellipsizing Text', (WidgetTester tester) async {
        await _pump(tester, name: 'Манікюр', hint: hint);

        final Text name = tester.widget<Text>(find.byKey(_nameKey));
        expect(name.data, 'Манікюр');
        expect(name.maxLines, 1);
        expect(name.overflow, TextOverflow.ellipsis);
        expect(find.byKey(_hintKey), findsNothing);
        expect(
          find.descendant(
            of: find.byType(NameWithHint),
            matching: find.byType(LayoutBuilder),
          ),
          findsNothing,
        );
      });
    }

    testWidgets('wrapping mode without a hint is one plain Text', (
      WidgetTester tester,
    ) async {
      await _pump(tester, name: 'Манікюр', singleLine: false);

      final Text name = tester.widget<Text>(find.byKey(_nameKey));
      expect(name.data, 'Манікюр');
      expect(name.textSpan, isNull);
      expect(name.maxLines, isNull);
    });
  });

  group('hint isolation', () {
    testWidgets('single-line: hint is wrapped in FSI … PDI inside the suffix', (
      WidgetTester tester,
    ) async {
      await _pump(tester, name: 'Манікюр', hint: '90 хв');

      final Text hint = tester.widget<Text>(find.byKey(_hintKey));
      // Suffix from l10n `serviceNameHintSuffix` (« · {hint}»).
      expect(hint.data, ' · ${_fsi}90 хв$_pdi');
      // The name is its own paragraph here — plain, not isolated.
      expect(tester.widget<Text>(find.byKey(_nameKey)).data, 'Манікюр');
    });

    testWidgets('wrapping: name AND hint are each isolated in one paragraph', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        name: 'Манікюр\u200F',
        hint: 'גבות',
        singleLine: false,
      );

      final Text rich = tester.widget<Text>(find.byKey(_nameKey));
      final List<InlineSpan> spans = (rich.textSpan! as TextSpan).children!;
      expect((spans[0] as TextSpan).text, '\u2068Манікюр\u200F\u2069');
      expect((spans[1] as TextSpan).text, ' · \u2068גבות\u2069');
    });

    test('isolate() wraps exactly once', () {
      expect(NameWithHint.isolate('a'), '${_fsi}a$_pdi');
    });
  });

  group('single-line layout', () {
    testWidgets('a long name ellipsizes; the short hint stays whole', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        name: 'Дуже довга назва послуги, що ніяк не влазить у рядок',
        hint: '90 хв',
        // The test font draws each glyph 14 dp wide: the ~10-glyph suffix
        // (140 dp) fits under the 200 dp cap.
        width: 400,
      );

      final Text name = tester.widget<Text>(find.byKey(_nameKey));
      expect(name.overflow, TextOverflow.ellipsis);
      expect(_paragraph(tester, _nameKey).didExceedMaxLines, isTrue);
      expect(_paragraph(tester, _hintKey).didExceedMaxLines, isFalse);
      expect(
        tester.getTopRight(find.byKey(_hintKey)).dx,
        lessThanOrEqualTo(400),
      );
    });

    testWidgets('a long hint is capped at 50% of the row and ellipsizes', (
      WidgetTester tester,
    ) async {
      const double width = 240;
      await _pump(
        tester,
        name: 'Манікюр',
        hint: 'Дуже довга відмінна назва копії послуги без кінця',
        width: width,
      );

      final double hintWidth = tester.getSize(find.byKey(_hintKey)).width;
      expect(hintWidth, lessThanOrEqualTo(width * 0.5));
      expect(hintWidth, greaterThan(width * 0.5 - 1));
      expect(_paragraph(tester, _hintKey).didExceedMaxLines, isTrue);
      // The name keeps the other half.
      expect(tester.getSize(find.byKey(_nameKey)).width, greaterThan(0));
    });
  });
}
