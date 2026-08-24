// Phase 111 (mobile-qa) — widget tests for the two «Улюблені» card kinds.
//
// WHY THIS FILE EXISTS
// --------------------
// `favorite_cards.dart` had no test at all. Two of its behaviours are the kind
// that rot silently:
//
//   1. THE ADDRESS SUPPRESSION GUARD (`favorite_cards.dart:489-493`). A
//      salon-affiliated master's premises are their EMPLOYER's, and the card
//      refuses to print street/building/note for them. mobile-security noted
//      that this guard is currently INERT — the shipped DTO never populates
//      `salonName`, so `isAffiliated` is always false and the branch is never
//      taken. An inert guard is precisely the code that gets deleted as dead
//      during a refactor. Feeding a card a non-null `salonName` directly makes
//      it live and pins it against that day.
//
//   2. THE UNRATED SLOT. A `0.0` beside a star reads as a BAD score to a human,
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
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/pump_app.dart';
import 'favorites_test_fixtures.dart';

/// A wire-shaped arrival note. Latin, so no Cyrillic-finder escape is needed.
const String _note = 'entrance from the yard';

Future<void> _pumpCard(WidgetTester tester, Widget card) => tester.pumpApp(
  Scaffold(
    body: Center(
      child: Padding(padding: const EdgeInsets.all(8), child: card),
    ),
  ),
);

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
  group('FavoriteMasterCard — address suppression by affiliation', () {
    testWidgets('an INDEPENDENT master renders street, building and note', (
      WidgetTester tester,
    ) async {
      // The control. Without it, a card that rendered NOTHING would satisfy the
      // suppression test below.
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

    testWidgets('a SALON-AFFILIATED master renders NEITHER street NOR note', (
      WidgetTester tester,
    ) async {
      // RED WHEN the `ownsPremises` guard at `favorite_cards.dart:489-493` is
      // deleted (the branch is currently unreachable off the shipped DTO, so
      // nothing else in the app would notice).
      //
      // The fixture deliberately supplies street/buildingNo/note ALONGSIDE a
      // salonName — a combination the backend masks server-side today via
      // `MasterType.disclosesOwnAddress`. That is the whole point: the client
      // guard must hold on its own, so a contract change that starts returning
      // those fields cannot print an employer's address on an employee's row.
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

      expect(find.text('Khreshchatyk, 22'), findsNothing);
      expect(find.text(_note), findsNothing);
      // The LOCALITY survives — it is the client's orientation cue and belongs
      // to nobody's premises. Asserting it is what stops this test from passing
      // on a card that simply failed to render an address block at all.
      expect(find.text('Kyiv'), findsOneWidget);
      expect(find.byType(ResultAddressBlock), findsOneWidget);
      // And the affiliation line names the place that owns that address.
      expect(find.text('Crystal Room'), findsOneWidget);
    });

    testWidgets('an affiliated master keeps the suppressed note OUT of its '
        'spoken label too', (WidgetTester tester) async {
      // A screen reader must not be handed what the screen refuses to print.
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
      expect(label, contains('Kyiv'));
      expect(label, isNot(contains(_note)));
      expect(label, isNot(contains('Khreshchatyk')));
    });

    testWidgets('an affiliated master draws no address block when the '
        'locality is also absent', (WidgetTester tester) async {
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

      expect(find.byType(ResultAddressBlock), findsNothing);
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
