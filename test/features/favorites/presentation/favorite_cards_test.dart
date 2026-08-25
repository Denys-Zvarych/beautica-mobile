// Phase 111 (mobile-qa) — widget tests for the two «Улюблені» card kinds.
//
// WHY THIS FILE EXISTS
// --------------------
// `favorite_cards.dart` had no test at all. Behaviours worth pinning
// separately from the mapper/screen tiers:
//
//   1. THE AFFILIATED-MASTER ADDRESS (`favorite_cards.dart`,
//      `FavoriteMasterCard.build`). Since backend `ca2c98a`, a
//      salon-affiliated master's `street`/`buildingNo`/`locationNote` are
//      their EMPLOYING SALON's, and the card renders them exactly like an
//      independent master's own address — no suppression. An earlier revision
//      of this card DID suppress them (`ownsPremises`), on the theory that the
//      backend nulled those fields for an affiliated master anyway; that
//      theory no longer holds, and the guard was deleted. These tests pin the
//      CURRENT contract so a future "helpful" restoration of that guard goes
//      red immediately.
//
//   2. THE TWO-LINE NAME (`_IdentityLine`). Field testing on real Ukrainian
//      names showed one-line ellipsis truncating identity; the card now wraps
//      a long name to two lines before ellipsizing, with the rating readout
//      pinned to the first line.
//
//   3. THE UNRATED SLOT. A `0.0` beside a star reads as a BAD score to a human,
//      not a missing one, and would libel every unrated provider on the screen
//      — which, for masters, is most of them. The dash is the mark that is not
//      a zero.
//
// Cards are pumped DIRECTLY (no router, no notifier): `onOpen`/`onUnlike` are
// plain callbacks, so a full screen boot would only add noise between the
// fixture and the assertion.

import 'package:beautica_mobile/features/discovery/presentation/widgets/result_address_block.dart';
import 'package:beautica_mobile/features/favorites/presentation/widgets/favorite_cards.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/pump_app.dart';
import 'favorites_test_fixtures.dart';

/// A wire-shaped arrival note. Latin, so no Cyrillic-finder escape is needed.
const String _note = 'entrance from the yard';

/// A provider name long enough to force a two-line wrap in a narrow card
/// column — Latin, per this file's no-`i18n-finder-ok` convention.
const String _longName = 'Solomiya Constantinovska Zabrodska Marchenko';

Future<void> _pumpCard(WidgetTester tester, Widget card) => tester.pumpApp(
  Scaffold(
    body: Center(
      child: Padding(padding: const EdgeInsets.all(8), child: card),
    ),
  ),
);

/// Same as [_pumpCard], but at a fixed, narrow logical width — needed to force
/// a wrap deterministically; the default test surface is wide enough that
/// even [_longName] would fit on one line.
Future<void> _pumpCardNarrow(WidgetTester tester, Widget card) =>
    tester.pumpApp(
      Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: Padding(padding: const EdgeInsets.all(8), child: card),
        ),
      ),
      width: 260,
    );

/// The [RenderParagraph] backing the [Text] showing [text] (located by its
/// fixture data — a fixture literal, not a UI string).
RenderParagraph _paragraphFor(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(find.text(text));

/// Number of lines the paragraph actually laid out, reproduced from its own
/// span + style + the width it was given. [RenderParagraph] exposes no line
/// count directly, so re-run the layout in a [TextPainter] (which does expose
/// [TextPainter.computeLineMetrics]) at the paragraph's incoming max width.
/// Same technique as `salon_result_card_test.dart`'s `_lineCount`.
int _lineCount(RenderParagraph p) {
  final TextPainter painter = TextPainter(
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

/// The semantic label the card hands a screen reader.
String _semanticLabel(WidgetTester tester, Type cardType) {
  final Iterable<Semantics> all = tester.widgetList<Semantics>(
    find.descendant(
      of: find.byType(cardType),
      matching: find.byType(Semantics),
    ),
  );
  final Semantics shell = all.firstWhere(
    (Semantics s) => s.properties.button == true && s.properties.label != null,
  );
  return shell.properties.label!;
}

void main() {
  group('FavoriteMasterCard — affiliated-master address (backend ca2c98a)', () {
    testWidgets('an INDEPENDENT master renders street, building and note', (
      WidgetTester tester,
    ) async {
      // The control. Without it, a card that rendered NOTHING would satisfy the
      // affiliated-master test below by coincidence.
      await _pumpCard(
        tester,
        FavoriteMasterCard(
          item: favMaster(
            'm1',
            cityLabel: 'Kyiv',
            street: 'Khreshchatyk',
            buildingNo: '22',
            locationNote: _note,
          ),
          onOpen: () {},
          onUnlike: () {},
        ),
      );

      expect(find.text('Kyiv'), findsOneWidget);
      expect(find.text('Khreshchatyk, 22'), findsOneWidget);
      expect(find.text(_note), findsOneWidget);
    });

    testWidgets('a SALON-AFFILIATED master renders BOTH the affiliation line '
        'AND the (salon\'s) street and note', (WidgetTester tester) async {
      // RED WHEN a client-side suppression guard is reintroduced onto
      // `FavoriteMasterCard.build`. Since backend `ca2c98a`, an affiliated
      // master's street/buildingNo/locationNote ARE the employing salon's, and
      // the product decision is to render them exactly like an independent
      // master's own address — the affiliation line carries the salon's NAME,
      // this block carries its STREET, nothing duplicated.
      await _pumpCard(
        tester,
        FavoriteMasterCard(
          item: favMaster(
            'm1',
            salonName: 'Crystal Room',
            cityLabel: 'Kyiv',
            street: 'Khreshchatyk',
            buildingNo: '22',
            locationNote: _note,
          ),
          onOpen: () {},
          onUnlike: () {},
        ),
      );

      expect(find.text('Kyiv'), findsOneWidget);
      expect(find.text('Khreshchatyk, 22'), findsOneWidget);
      expect(find.text(_note), findsOneWidget);
      expect(find.byType(ResultAddressBlock), findsOneWidget);
      // And the affiliation line names the place that owns that address.
      expect(find.text('Crystal Room'), findsOneWidget);
    });

    testWidgets('an affiliated master\'s spoken label leads with the salon '
        'name, then carries the (salon\'s) address', (
      WidgetTester tester,
    ) async {
      await _pumpCard(
        tester,
        FavoriteMasterCard(
          item: favMaster(
            'm1',
            salonName: 'Crystal Room',
            cityLabel: 'Kyiv',
            street: 'Khreshchatyk',
            locationNote: _note,
          ),
          onOpen: () {},
          onUnlike: () {},
        ),
      );

      final String label = _semanticLabel(tester, FavoriteMasterCard);
      expect(label, contains('Crystal Room'));
      expect(label, contains('Kyiv'));
      expect(label, contains('Khreshchatyk'));
      expect(label, contains(_note));
      // Salon name reads BEFORE the address, mirroring the visual order —
      // name, affiliation, address.
      expect(label.indexOf('Crystal Room'), lessThan(label.indexOf('Kyiv')));
    });

    testWidgets('an affiliated master still draws an address block from '
        'street alone, with no locality', (WidgetTester tester) async {
      await _pumpCard(
        tester,
        FavoriteMasterCard(
          item: favMaster(
            'm1',
            salonName: 'Crystal Room',
            street: 'Khreshchatyk',
          ),
          onOpen: () {},
          onUnlike: () {},
        ),
      );

      expect(find.byType(ResultAddressBlock), findsOneWidget);
      expect(find.text('Khreshchatyk'), findsOneWidget);
    });
  });

  group('FavoriteSalonCard — a salon owns its own premises', () {
    testWidgets('renders street and note with NO suppression', (
      WidgetTester tester,
    ) async {
      // The salon card has no affiliation concept, so its address must always
      // render. RED WHEN someone copies the master card's `ownsPremises` guard
      // onto it.
      await _pumpCard(
        tester,
        FavoriteSalonCard(
          item: favSalon(
            's1',
            cityLabel: 'Kyiv',
            districtLabel: 'Shevchenkivskyi',
            street: 'Khreshchatyk',
            buildingNo: '22',
            locationNote: _note,
          ),
          onOpen: () {},
          onUnlike: () {},
        ),
      );

      expect(find.text('Khreshchatyk, 22'), findsOneWidget);
      expect(find.text(_note), findsOneWidget);
      final String label = _semanticLabel(tester, FavoriteSalonCard);
      expect(label, contains(_note));
    });
  });

  group('_IdentityLine — the two-line name wrap', () {
    testWidgets('a long name wraps to a SECOND line rather than being '
        'truncated to one', (WidgetTester tester) async {
      // RED WHEN `_IdentityLine`'s `maxLines` reverts to 1. User decision,
      // 2026-08-25, superseding the earlier one-line-ellipsis call: field
      // testing on real Ukrainian names showed truncation.
      await _pumpCardNarrow(
        tester,
        FavoriteMasterCard(
          item: favMaster('m1', name: _longName, rating: 4.7),
          onOpen: () {},
          onUnlike: () {},
        ),
      );

      final Text text = tester.widget<Text>(find.text(_longName));
      expect(text.maxLines, 2);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(
        _lineCount(_paragraphFor(tester, _longName)),
        2,
        reason:
            'a static maxLines:2 alone does not prove the layout actually '
            'used a second line — the narrow column must genuinely wrap it.',
      );
    });

    testWidgets('the rating readout stays pinned to the FIRST line, not '
        'centred against a two-line name', (WidgetTester tester) async {
      // RatingReadout and the name Text are siblings in `_IdentityLine`'s Row.
      // With `crossAxisAlignment: start`, both start at the SAME top offset
      // regardless of how tall the name column grows; with the Row's default
      // `center`, a two-line name would push the Row taller and drag the
      // rating down to the new vertical middle. Comparing top offsets catches
      // that regression directly, independent of any specific pixel budget.
      await _pumpCardNarrow(
        tester,
        FavoriteMasterCard(
          item: favMaster('m1', name: _longName, rating: 4.7),
          onOpen: () {},
          onUnlike: () {},
        ),
      );

      final double nameTop = tester.getTopLeft(find.text(_longName)).dy;
      final double ratingTop = tester.getTopLeft(find.byType(RatingReadout)).dy;
      expect(
        ratingTop,
        closeTo(nameTop, 1.0),
        reason:
            'the rating readout drifted away from the first line\'s top — '
            'the identity Row is no longer top-aligned',
      );
    });
  });

  group('RatingReadout — the constant slot', () {
    testWidgets('an UNRATED provider gets the en dash, never a 0.0', (
      WidgetTester tester,
    ) async {
      await _pumpCard(
        tester,
        FavoriteMasterCard(
          item: favMaster('m1'),
          onOpen: () {},
          onUnlike: () {},
        ),
      );

      // U+2013 EN DASH — the mark that is not a zero.
      expect(find.text('–'), findsOneWidget);
      expect(find.text('0.0'), findsNothing);
      // The star is still DRAWN (dimmed), so the identity line keeps its shape
      // down a scroll rather than the column appearing and vanishing row to
      // row.
      expect(find.byIcon(Icons.star_rounded), findsOneWidget);
    });

    testWidgets('a rated provider renders exactly one decimal', (
      WidgetTester tester,
    ) async {
      await _pumpCard(
        tester,
        FavoriteMasterCard(
          item: favMaster('m1', rating: 4.6666),
          onOpen: () {},
          onUnlike: () {},
        ),
      );

      expect(find.text('4.7'), findsOneWidget);
      expect(find.text('–'), findsNothing);
    });

    testWidgets('the spoken label says «no ratings» in WORDS, never a dash', (
      WidgetTester tester,
    ) async {
      await _pumpCard(
        tester,
        FavoriteMasterCard(
          item: favMaster('m1'),
          onOpen: () {},
          onUnlike: () {},
        ),
      );

      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(FavoriteMasterCard)),
      );
      final String label = _semanticLabel(tester, FavoriteMasterCard);
      expect(label, contains(l10n.favoritesNoRatingSpoken));
      expect(label, isNot(contains('–')));
    });
  });

  group('Identity marks — the kind cue', () {
    testWidgets('a master card draws the initials disc, a salon card the '
        'storefront well', (WidgetTester tester) async {
      await _pumpCard(
        tester,
        FavoriteMasterCard(
          item: favMaster('m1'),
          onOpen: () {},
          onUnlike: () {},
        ),
      );
      expect(find.byType(MasterMark), findsOneWidget);
      expect(find.byType(SalonMark), findsNothing);
      expect(find.text('MH'), findsOneWidget);

      await _pumpCard(
        tester,
        FavoriteSalonCard(item: favSalon('s1'), onOpen: () {}, onUnlike: () {}),
      );
      expect(find.byType(SalonMark), findsOneWidget);
      expect(find.byType(MasterMark), findsNothing);
      expect(find.byIcon(Icons.storefront_rounded), findsOneWidget);
    });
  });

  group('UnlikeHeart', () {
    testWidgets('fires onUnlike WITHOUT firing the card\'s onOpen', (
      WidgetTester tester,
    ) async {
      int opens = 0;
      int unlikes = 0;
      await _pumpCard(
        tester,
        FavoriteMasterCard(
          item: favMaster('m1'),
          onOpen: () => opens++,
          onUnlike: () => unlikes++,
        ),
      );

      // The heart carries no Key of its own (pre-existing). Its AnimatedScale
      // is a DESCENDANT of the GestureDetector, not the widget root, so the hit
      // test reaches the handler — `warnIfMissed` is never silenced here.
      await tester.tap(find.byType(UnlikeHeart));
      await tester.pumpAndSettle();

      expect(unlikes, 1);
      expect(opens, 0);
    });
  });
}
