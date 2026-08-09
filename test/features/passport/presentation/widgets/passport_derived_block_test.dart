// Phase 238 — [PassportDerivedBlock] widget tests.
//
// THE ORIGINAL BUG
// ----------------
// «Шевченківський» clipped to «Шев…» in a cramped column is the defect this
// whole redesign exists to fix. `passport_derived_block.dart`'s header answers
// it STRUCTURALLY rather than by budget: each locality name is its own [Text]
// with NO `maxLines` and NO `TextOverflow`, laid out in a [Wrap]. A name that
// does not fit the current run moves to the next run; a name wider than the
// whole field wraps inside itself. Neither path can ellipsise.
//
// A `findsOneWidget` on the name would be satisfied by «Шев…» — the finder
// matches the `Text`'s DATA, not what was painted. So the assertions here are
// geometric: the rendered paragraph box must be exactly the size the same span
// takes laid out unbounded, which is only true when the whole string is on one
// unclipped line.
//
// THE SEPARATOR RULE
// ------------------
// Each «·» is bundled into a min-size [Row] with the name it FOLLOWS, so a run
// can end with «Голосіївський ·» but can never BEGIN with «·». Asserting that
// at one width is nearly vacuous — the orphan only appears when a run break
// lands exactly between a name and its separator. So the test SWEEPS the width
// and asserts the invariant at every break position, and records the widths at
// which the un-bundled shape would have orphaned one.
//
// MUTATION-PROVEN 2026-08-07: emitting each separator as its OWN `Wrap` child
// (the shape the header forbids) turns `should_bundleSeparatorWithPrecedingName`
// RED — it reports «at 278.0 dp a locality run OPENS with «·»». Re-verified
// green on revert. Note the spot-check twin BELOW it stayed GREEN under the same
// mutation: at 320 dp no break lands between a name and its separator, which is
// exactly why the sweep exists and why one width is not evidence.

import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/widgets/price_tag.dart';
import 'package:beautica_mobile/features/passport/presentation/widgets/passport_derived_block.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

const Key _kBlock = Key('passport_derived_block');
const Key _kAverageUnknown = Key('passport_average_unknown');

/// The rank separator `_LocalityLine` draws. Duplicated from the (private)
/// widget constant on purpose — if the glyph ever changes, these tests should
/// have to say so explicitly.
const String _kSeparator = '·';

/// Worst-case fixtures, verbatim from the approved preview's
/// `PassportSampleData.derived` — «Шевченківський» first because it is the
/// exact string that used to be clipped to «Шев…».
const List<String> _kDistricts = <String>[
  'Шевченківський',
  'Голосіївський',
  'Печерський',
];
const List<String> _kCities = <String>['Київ', 'Бровари'];

/// A pre-formatted PURE money string, exactly as `passport_screen.dart` hands
/// it over (`l10n.passportBudgetAverage(750)`). The block never formats money.
const String _kAverage = '750 ₴';

Future<AppLocalizations> _uk() =>
    AppLocalizations.delegate.load(const Locale('uk'));

/// Pumps the block at a DEVICE width [width] inside the passport page's own
/// `EdgeInsets.all(VelvetSpacing.lg)`, so the widget sees the real field budget
/// (270 dp at 360 dp, 230 dp at 320 dp per its own header).
Future<void> _pumpBlock(
  WidgetTester tester, {
  required double width,
  List<String> districts = _kDistricts,
  List<String> cities = _kCities,
  String? averageSpend = _kAverage,
  double? textScaleFactor,
}) async {
  await tester.pumpApp(
    Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.all(VelvetSpacing.lg),
        child: PassportDerivedBlock(
          districts: districts,
          cities: cities,
          averageSpend: averageSpend,
        ),
      ),
    ),
    width: width,
    textScaleFactor: textScaleFactor,
  );
  await tester.pumpAndSettle();
}

/// The size the [Text] at [finder] takes with NO width constraint.
Size _unboundedTextSize(WidgetTester tester, Finder finder) {
  final RenderParagraph p = tester.renderObject<RenderParagraph>(finder);
  final TextPainter painter = TextPainter(
    text: p.text,
    textDirection: p.textDirection,
    textScaler: p.textScaler,
  )..layout();
  final Size size = painter.size;
  painter.dispose();
  return size;
}

/// Asserts [name] is rendered whole: one line, full natural width, no
/// `maxLines`, no `TextOverflow`.
void _expectWholeNameRendered(
  WidgetTester tester,
  String name, {
  required double width,
}) {
  // i18n-finder-ok: locality names are BACKEND-DERIVED DATA passed straight in
  // by this test, never AppLocalizations copy — they are identical in every
  // locale.
  final Finder finder = find.text(name);
  expect(finder, findsOneWidget, reason: '«$name» must render at $width dp');

  final Text widget = tester.widget<Text>(finder);
  expect(
    widget.maxLines,
    isNull,
    reason:
        'a locality name must carry NO maxLines — that is the structural half '
        'of the no-truncation guarantee',
  );
  expect(
    widget.overflow,
    isNull,
    reason:
        'a locality name must carry NO TextOverflow — an ellipsis here IS the '
        'original «Шев…» bug',
  );

  final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
    finder,
  );
  expect(paragraph.didExceedMaxLines, isFalse);

  final Size laidOut = tester.getSize(finder);
  final Size natural = _unboundedTextSize(tester, finder);
  expect(
    laidOut.width,
    closeTo(natural.width, 0.5),
    reason:
        '«$name» must occupy its FULL natural width at $width dp — a narrower '
        'box means it was clipped or wrapped inside itself '
        '(laidOut=$laidOut natural=$natural)',
  );
  expect(
    laidOut.height,
    closeTo(natural.height, 0.5),
    reason:
        '«$name» must fit on ONE line at $width dp — the field has ~2.5x '
        'headroom for it (laidOut=$laidOut natural=$natural)',
  );
}

/// One rendered locality token: either a NAME or a separator.
class _Token {
  const _Token(this.text, this.rect);
  final String text;
  final Rect rect;
  bool get isSeparator => text == _kSeparator;
}

/// Every locality token currently on screen (names + separators), in paint
/// order, with its global rect.
List<_Token> _localityTokens(
  WidgetTester tester, {
  required List<String> districts,
  required List<String> cities,
}) {
  final Set<String> wanted = <String>{...districts, ...cities, _kSeparator};
  final List<_Token> out = <_Token>[];
  for (final Element e
      in find
          .descendant(of: find.byKey(_kBlock), matching: find.byType(Text))
          .evaluate()) {
    final Text w = e.widget as Text;
    final String? data = w.data;
    if (data == null || !wanted.contains(data)) continue;
    final RenderBox box = e.renderObject! as RenderBox;
    out.add(_Token(data, box.localToGlobal(Offset.zero) & box.size));
  }
  return out;
}

/// Groups [tokens] into RUNS by their top edge, then returns each run's
/// left-most token.
List<_Token> _runOpeners(List<_Token> tokens) {
  final Map<int, List<_Token>> byRun = <int, List<_Token>>{};
  for (final _Token t in tokens) {
    byRun.putIfAbsent(t.rect.top.round(), () => <_Token>[]).add(t);
  }
  return byRun.values
      .map((List<_Token> run) {
        run.sort((_Token a, _Token b) => a.rect.left.compareTo(b.rect.left));
        return run.first;
      })
      .toList(growable: false);
}

void main() {
  // -------------------------------------------------------------------------
  // 1. THE ORIGINAL BUG.
  // -------------------------------------------------------------------------
  group('PassportDerivedBlock — locality names are never truncated', () {
    for (final double width in <double>[320, 360]) {
      testWidgets(
        'should_wrapNotTruncate_when_districtIsShevchenkivskyi @$width dp',
        (tester) async {
          await _pumpBlock(tester, width: width);

          expect(find.byKey(_kBlock), findsOneWidget);
          for (final String name in <String>[..._kDistricts, ..._kCities]) {
            _expectWholeNameRendered(tester, name, width: width);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'NON-VACUITY: the district line genuinely WRAPS at 320 dp, so the '
      'no-truncation assertions are measuring a cramped field',
      (tester) async {
        // If all three districts fitted on one run, the test above would prove
        // nothing about the wrap path — it would pass against a `maxLines: 1`
        // widget too, because nothing would have needed to break.
        await _pumpBlock(tester, width: 320, cities: const <String>[]);

        final List<_Token> tokens = _localityTokens(
          tester,
          districts: _kDistricts,
          cities: const <String>[],
        );
        final Set<int> runs = tokens
            .map((_Token t) => t.rect.top.round())
            .toSet();
        expect(
          runs.length,
          greaterThanOrEqualTo(2),
          reason:
              'the three worst-case districts must take more than one run at '
              '320 dp — otherwise the wrap path is untested',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // 2. NO RUN EVER OPENS WITH «·».
  // -------------------------------------------------------------------------
  group('PassportDerivedBlock — separators are bundled with their name', () {
    testWidgets('should_bundleSeparatorWithPrecedingName', (tester) async {
      // SWEPT, not spot-checked. The orphan only appears when a run break lands
      // exactly between a name and its separator, so a single width can be
      // green against the un-bundled shape by luck. The sweep walks every break
      // position the field can produce for these fixtures.
      //
      // MUTATION-PROVEN: with each «·» emitted as its OWN `Wrap` child, this
      // test goes red — the assertion below names the offending width.
      int widthsWithMultipleRuns = 0;

      for (double width = 240; width <= 400; width += 2) {
        await _pumpBlock(tester, width: width);

        final List<_Token> tokens = _localityTokens(
          tester,
          districts: _kDistricts,
          cities: _kCities,
        );
        expect(
          tokens.where((_Token t) => t.isSeparator).length,
          _kDistricts.length - 1 + _kCities.length - 1,
          reason: 'every non-final name must be followed by exactly one «·»',
        );

        if (tokens.map((_Token t) => t.rect.top.round()).toSet().length > 1) {
          widthsWithMultipleRuns++;
        }

        for (final _Token opener in _runOpeners(tokens)) {
          expect(
            opener.isSeparator,
            isFalse,
            reason:
                'at $width dp a locality run OPENS with «$_kSeparator». Each '
                'separator must be bundled into the min-size Row of the name '
                'it FOLLOWS, so a break can only land AFTER it. An orphaned '
                'interpunct at the head of a line is the defect '
                'passport_derived_block.dart forbids by name.',
          );
        }
      }

      expect(
        widthsWithMultipleRuns,
        greaterThan(0),
        reason:
            'the sweep must actually produce run breaks — with everything on '
            'one run the invariant is trivially satisfied and proves nothing',
      );
    });

    testWidgets(
      'each «·» shares its run with the name it follows, and sits to its right',
      (tester) async {
        // The structural twin of the sweep: bundling means the separator and
        // its preceding name are ONE Wrap child, so they can never be on
        // different runs and the separator is always to the right.
        await _pumpBlock(tester, width: 320, cities: const <String>[]);

        final List<_Token> tokens = _localityTokens(
          tester,
          districts: _kDistricts,
          cities: const <String>[],
        );
        final List<_Token> separators = tokens
            .where((_Token t) => t.isSeparator)
            .toList(growable: false);
        expect(separators.length, _kDistricts.length - 1);

        for (int i = 0; i < separators.length; i++) {
          final _Token name = tokens.firstWhere(
            (_Token t) => t.text == _kDistricts[i],
          );
          expect(
            separators[i].rect.top.round(),
            name.rect.top.round(),
            reason:
                '«$_kSeparator» #$i must share a run with «${_kDistricts[i]}»',
          );
          expect(
            separators[i].rect.left,
            greaterThan(name.rect.left),
            reason: '«$_kSeparator» #$i must follow its name, not precede it',
          );
        }
      },
    );
  });

  // -------------------------------------------------------------------------
  // 3. UNKNOWN AVERAGE — a bare «—», and NO pill.
  // -------------------------------------------------------------------------
  group('PassportDerivedBlock — unknown average', () {
    testWidgets('should_renderBareDash_when_averageIsNull', (tester) async {
      await _pumpBlock(tester, width: 360, averageSpend: null);

      final AppLocalizations l10n = await _uk();
      expect(find.byKey(_kAverageUnknown), findsOneWidget);
      expect(find.text(l10n.passportBudgetUnknown), findsOneWidget);

      expect(
        find.byType(PriceTag),
        findsNothing,
        reason:
            'a recessed pill is chrome that says "here is a figure" — wrapping '
            'an em dash in it would read as a value that exists. Absence must '
            'look like absence.',
      );
      expect(
        find.text(kApproximatelyMarker),
        findsNothing,
        reason:
            'the «≈» marker qualifies a DERIVED FIGURE; with no figure there '
            'is nothing to qualify',
      );

      // The eyebrow stays — the field is present and states "not known", which
      // is different from the field being absent.
      expect(
        find.text(l10n.passportAverageSpendLabel.toUpperCase()),
        findsOneWidget,
      );
    });

    testWidgets(
      'POSITIVE CONTROL: a known average renders the pill and the «≈» marker',
      (tester) async {
        // Without this the test above would pass against a block that never
        // renders a PriceTag at all.
        await _pumpBlock(tester, width: 360);

        final AppLocalizations l10n = await _uk();
        expect(find.byType(PriceTag), findsOneWidget);
        expect(find.text(kApproximatelyMarker), findsOneWidget);
        expect(find.byKey(_kAverageUnknown), findsNothing);
        expect(find.text(l10n.passportBudgetUnknown), findsNothing);

        // The money string is passed through VERBATIM — this widget never
        // formats money.
        // i18n-finder-ok: the caller-supplied pre-formatted money string, not
        // AppLocalizations copy resolved inside the widget.
        expect(find.text(_kAverage), findsOneWidget);
        expect(tester.widget<PriceTag>(find.byType(PriceTag)).price, _kAverage);
      },
    );
  });

  // -------------------------------------------------------------------------
  // 4. NO LOCATION HISTORY — the field AND its rule go together.
  // -------------------------------------------------------------------------
  group('PassportDerivedBlock — no locality history', () {
    /// The block's hairline rule: `Container(height: 1, color: …)`.
    final Finder rule = find.descendant(
      of: find.byKey(_kBlock),
      matching: find.byWidgetPredicate(
        (Widget w) =>
            w is Container &&
            w.constraints == const BoxConstraints.tightFor(height: 1),
      ),
    );

    testWidgets('should_omitLocalityFieldAndRule_when_noLocations', (
      tester,
    ) async {
      await _pumpBlock(
        tester,
        width: 360,
        districts: const <String>[],
        cities: const <String>[],
      );

      final AppLocalizations l10n = await _uk();

      // The block is still there — the average alone is content.
      expect(find.byKey(_kBlock), findsOneWidget);
      expect(find.byType(PriceTag), findsOneWidget);

      expect(
        find.text(l10n.passportLocalitiesLabel.toUpperCase()),
        findsNothing,
        reason:
            'an empty locality field must be omitted, never left as an '
            'empty row under its eyebrow',
      );
      expect(find.text(_kSeparator), findsNothing);
      expect(
        rule,
        findsNothing,
        reason:
            'the rule SEPARATES the locality field from the spend row — with '
            'nothing to separate, a lone rule above the only remaining row '
            'would read as a field that failed to render',
      );
    });

    testWidgets(
      'POSITIVE CONTROL: with localities, the eyebrow AND the rule are present',
      (tester) async {
        // Proves the finders above can actually match something — otherwise
        // `findsNothing` is satisfied by a typo.
        await _pumpBlock(tester, width: 360);

        final AppLocalizations l10n = await _uk();
        expect(
          find.text(l10n.passportLocalitiesLabel.toUpperCase()),
          findsOneWidget,
        );
        expect(rule, findsOneWidget);
      },
    );

    testWidgets('districts alone, and cities alone, each render their line', (
      tester,
    ) async {
      // `hasLocations` is an OR: either list alone must render the field.
      await _pumpBlock(tester, width: 360, cities: const <String>[]);
      _expectWholeNameRendered(tester, _kDistricts.first, width: 360);
      expect(
        find.text(_kSeparator),
        findsNWidgets(_kDistricts.length - 1),
        reason: 'no separator may be emitted for the absent cities line',
      );

      await _pumpBlock(tester, width: 360, districts: const <String>[]);
      _expectWholeNameRendered(tester, _kCities.first, width: 360);
      expect(find.text(_kSeparator), findsNWidgets(_kCities.length - 1));
    });
  });

  // -------------------------------------------------------------------------
  // 5. hasLocations / hasContent — the CALLER's gate.
  // -------------------------------------------------------------------------
  group('PassportDerivedBlock — hasContent gate', () {
    test('hasContent is false only when there is nothing at all to report', () {
      const PassportDerivedBlock nothing = PassportDerivedBlock(
        districts: <String>[],
        cities: <String>[],
        averageSpend: null,
      );
      expect(nothing.hasLocations, isFalse);
      expect(nothing.hasContent, isFalse);

      expect(
        const PassportDerivedBlock(
          districts: <String>[],
          cities: <String>[],
          averageSpend: _kAverage,
        ).hasContent,
        isTrue,
      );
      expect(
        const PassportDerivedBlock(
          districts: _kDistricts,
          cities: <String>[],
          averageSpend: null,
        ).hasContent,
        isTrue,
      );
      expect(
        const PassportDerivedBlock(
          districts: <String>[],
          cities: _kCities,
          averageSpend: null,
        ).hasContent,
        isTrue,
      );
    });
  });

  // -------------------------------------------------------------------------
  // 6. Large text scale — the a11y net for the Wrap and the spend Row.
  // -------------------------------------------------------------------------
  group('PassportDerivedBlock — large text scale', () {
    for (final (double width, double scale) in <(double, double)>[
      (320, 1.3),
      (320, 1.5),
      (360, 1.3),
      (360, 1.5),
    ]) {
      testWidgets('no overflow at $width dp @${scale}x', (tester) async {
        await _pumpBlock(tester, width: width, textScaleFactor: scale);

        expect(find.byKey(_kBlock), findsOneWidget);
        expect(tester.takeException(), isNull);

        for (final _Token opener in _runOpeners(
          _localityTokens(tester, districts: _kDistricts, cities: _kCities),
        )) {
          expect(
            opener.isSeparator,
            isFalse,
            reason:
                'no locality run may open with «$_kSeparator» at $width dp '
                '@${scale}x either',
          );
        }
      });
    }
  });
}
