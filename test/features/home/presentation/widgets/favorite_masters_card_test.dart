// Regression tests for [FavoriteMastersCard] — guards the rail's 2-line name +
// the _railHeight bump that keeps it overflow-free.
//
// The favourites rail base height was raised 140 → 158 specifically so a master
// mini-card's name can wrap to TWO lines (full name + surname) without the
// fixed-height horizontal rail RenderFlex-overflowing. The rail uses ellipsis as
// a last resort, so a long name need not be shown in full here — but it MUST:
//   1. attempt both allowed lines (computeLineMetrics().length == 2), and
//   2. NOT overflow the rail at the new height — at textScale 1.0 AND 1.3.
//
// The overflow check is enforced by the Phase 17.2 overflow guard installed by
// pumpApp: any RenderFlex overflow at the stress size fails the test in
// tearDown, so no manual takeException is needed. A revert of _railHeight to 140
// re-introduces the overflow the bump removed → these tests go red.
//
// Layer: Widget. The card is a ConsumerWidget but reads no provider at build
// time (the unlike notifier is read only inside the heart's onTap), so it pumps
// directly with the default ProviderScope.

import 'package:beautica_mobile/features/home/domain/home_hub_models.dart';
import 'package:beautica_mobile/features/home/presentation/widgets/favorite_masters_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

// A long master name (full name + double surname) — the case the _railHeight
// bump was made for. Located by fixture data, not a UI string.
const String _longName = 'Олександра Зварич-Пономаренко';

FavoriteMasterItem _master({String name = _longName}) => FavoriteMasterItem(
  masterId: 'm1',
  favoriteId: 'f1',
  name: name,
  lastServiceName: 'Манікюр',
  rating: 4.8,
  reviewCount: 42,
  initials: 'ОЗ',
);

Future<void> _pumpRail(WidgetTester tester, {required double textScaleFactor}) {
  return tester.pumpApp(
    FavoriteMastersCard(
      masters: <FavoriteMasterItem>[_master()],
      totalCount: 1,
    ),
    width: 320,
    textScaleFactor: textScaleFactor,
  );
}

/// The [RenderParagraph] backing the mini-card name [Text].
RenderParagraph _nameParagraph(WidgetTester tester) =>
    tester.renderObject<RenderParagraph>(find.text(_longName));

/// Number of lines the paragraph actually laid out, reproduced from its own
/// span + style + the width it was given. [RenderParagraph] exposes no line
/// count directly, so re-run the layout in a [TextPainter] (which does expose
/// [TextPainter.computeLineMetrics]) at the paragraph's incoming max width.
int _lineCount(RenderParagraph p) {
  final painter = TextPainter(
    text: p.text,
    textAlign: p.textAlign,
    textDirection: p.textDirection,
    textScaler: p.textScaler,
    maxLines: p.maxLines,
  )..layout(maxWidth: p.constraints.maxWidth);
  final int lines = painter.computeLineMetrics().length;
  painter.dispose();
  return lines;
}

void main() {
  group('FavoriteMastersCard rail long-name (320dp, _railHeight 158)', () {
    testWidgets('long name attempts two lines without overflow at x1.0', (
      tester,
    ) async {
      await _pumpRail(tester, textScaleFactor: 1.0);

      // The rail container renders (it is the SizedBox keyed below).
      expect(find.byKey(const Key('favorite_masters_rail')), findsOneWidget);

      final paragraph = _nameParagraph(tester);
      expect(
        _lineCount(paragraph),
        2,
        reason:
            'the mini-card name uses both allowed lines so the full name+surname '
            'can show — maxLines: 1 would cap it to one line.',
      );
      // No explicit overflow assertion: pumpApp's overflow guard fails the test
      // in tearDown if the rail RenderFlex-overflows at _railHeight.
    });

    testWidgets('rail height holds the 158 floor (revert guard)', (
      tester,
    ) async {
      await _pumpRail(tester, textScaleFactor: 1.0);

      final SizedBox rail = tester.widget<SizedBox>(
        find.byKey(const Key('favorite_masters_rail')),
      );
      expect(
        rail.height,
        greaterThanOrEqualTo(158),
        reason:
            'the rail base height must stay at the 158 floor (was 140) so a '
            '2-line name does not overflow — a revert to 140 trips this.',
      );
    });

    testWidgets('long name attempts two lines without overflow at x1.3', (
      tester,
    ) async {
      await _pumpRail(tester, textScaleFactor: 1.3);

      final paragraph = _nameParagraph(tester);
      expect(
        _lineCount(paragraph),
        2,
        reason: 'the name still uses both lines at the larger text scale.',
      );
      // Overflow at the scaled rail height is caught by the guard in tearDown.
    });
  });
}
