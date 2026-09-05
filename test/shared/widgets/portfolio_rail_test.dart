// Widget tests for `PortfolioRail` / `PortfolioTile`
// (lib/shared/widgets/portfolio_rail.dart).
//
// Written 2026-09-01 by mobile-qa alongside the shared-widget promotion that
// turned two hand-duplicated private portfolio rails (in
// `master_profile_screen.dart` and `public_master_profile_screen.dart`) plus
// a brand-new third consumer (`salon_management_profile_screen.dart`) into
// this single shared widget. Screen-level tests already pin PRESENCE of the
// rail per consumer (`public-master-profile-portfolio` key absence/presence
// by master type, `salon-manage-portfolio` position — see
// `salon_management_profile_screen_test.dart`), but until this file existed
// nothing tested the widget's OWN contract in isolation:
//
//   1. The `onSeeAll` fork — the ONE behavioural divergence the promotion
//      had to preserve between the master's own editable profile (link
//      visible) and the read-only public master / salon screens (link
//      omitted). Nothing pinned this at the widget level, so a future "always
//      show the link" edit would silently change two of the three consumers
//      with no test going red.
//   2. The tile's Semantics contract — `image: true`, NOT `button: true`.
//      This was a `mobile-security` fix in the same chain that produced this
//      widget (the tile press-flash reads as a photo, not an actionable
//      control, since tapping currently does nothing). Read via
//      `tester.getSemantics(...).getSemanticsData().flagsCollection`, never
//      a constructor field.
//   3. Tile count + the `index % 6` gradient wrap — proven BEHAVIOURALLY
//      (tile 0's rendered gradient colors == tile 6's, and != tile 1's)
//      rather than against hard-coded palette constants, so the test survives
//      a future palette change and still catches a broken modulus.
//
// Isolation: `PortfolioRail`/`PortfolioTile` take no Riverpod providers —
// plain constructor args, `AppLocalizations.of(context)` only. Every test
// pumps via the shared `pumpApp` helper (installs the overflow guard,
// configures l10n).

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/portfolio_rail.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

void main() {
  group('PortfolioRail — onSeeAll contract', () {
    testWidgets('renders the «Всі фото» link when onSeeAll is supplied', (
      tester,
    ) async {
      int tapCount = 0;
      await tester.pumpApp(
        Scaffold(body: PortfolioRail(onSeeAll: () => tapCount++)),
      );
      await tester.pumpAndSettle();

      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(PortfolioRail)),
      );
      final Finder link = find.text(l10n.masterAllPhotos);
      expect(link, findsOneWidget);

      await tester.tap(link);
      expect(
        tapCount,
        1,
        reason: 'the link must actually fire the supplied callback',
      );
    });

    testWidgets(
      'omits the «Всі фото» link entirely when onSeeAll is null — used by '
      'the read-only public master profile and the salon «Про салон» tab, '
      'neither of which has a gallery route yet',
      (tester) async {
        await tester.pumpApp(const Scaffold(body: PortfolioRail()));
        await tester.pumpAndSettle();

        final AppLocalizations l10n = AppLocalizations.of(
          tester.element(find.byType(PortfolioRail)),
        );
        expect(find.text(l10n.masterAllPhotos), findsNothing);
        // The section label itself must still render — only the link is
        // conditional, not the whole header.
        expect(find.text(l10n.masterPortfolioLabel), findsOneWidget);
      },
    );
  });

  group('PortfolioRail — tile count', () {
    testWidgets('renders exactly `count` PortfolioTile widgets', (
      tester,
    ) async {
      await tester.pumpApp(const Scaffold(body: PortfolioRail(count: 4)));
      await tester.pumpAndSettle();

      expect(find.byType(PortfolioTile), findsNWidgets(4));
    });

    testWidgets('defaults to 6 tiles when count is not supplied', (
      tester,
    ) async {
      await tester.pumpApp(const Scaffold(body: PortfolioRail()));
      await tester.pumpAndSettle();

      expect(find.byType(PortfolioTile), findsNWidgets(6));
    });
  });

  group('PortfolioTile — gradient index wrap', () {
    /// The AnimatedContainer's resolved gradient colors for the tile at
    /// [index] within a pumped [PortfolioRail]. Reads the ACTUAL painted
    /// decoration the widget computed from `index % _fills.length`, not a
    /// hard-coded palette constant — so this stays valid even if the
    /// palette itself changes, and only breaks if the wrap logic breaks.
    List<Color> gradientColorsFor(WidgetTester tester, int index) {
      final Finder tileFinder = find.byWidgetPredicate(
        (Widget w) => w is PortfolioTile && w.index == index,
      );
      final AnimatedContainer container = tester.widget<AnimatedContainer>(
        find.descendant(
          of: tileFinder,
          matching: find.byType(AnimatedContainer),
        ),
      );
      final BoxDecoration decoration = container.decoration! as BoxDecoration;
      return (decoration.gradient! as LinearGradient).colors;
    }

    testWidgets(
      'tile 6 wraps back to tile 0\'s gradient (index % 6); tile 1 differs '
      'from both',
      (tester) async {
        // 7 tiles (indices 0..6) so index 6 is reachable — production
        // callers all use the default count of 6, but the wrap only
        // becomes observable one tile past that.
        await tester.pumpApp(const Scaffold(body: PortfolioRail(count: 7)));
        await tester.pumpAndSettle();

        final List<Color> tile0 = gradientColorsFor(tester, 0);
        final List<Color> tile1 = gradientColorsFor(tester, 1);
        final List<Color> tile6 = gradientColorsFor(tester, 6);

        expect(
          tile6,
          equals(tile0),
          reason:
              '6 % 6 == 0 — the palette must wrap, not throw or repeat '
              'the last entry',
        );
        expect(
          tile1,
          isNot(equals(tile0)),
          reason:
              'sanity check that adjacent tiles are NOT accidentally '
              'identical (which would make the wrap assertion above '
              'vacuous)',
        );
      },
    );
  });

  group('PortfolioTile — semantics contract (mobile-security fix)', () {
    testWidgets('announces image: true, NOT button: true — the tile has no tap '
        'handler yet, so a screen reader must not claim it is actionable', (
      tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpApp(
        const Scaffold(
          body: PortfolioTile(key: Key('tile-under-test'), index: 0),
        ),
      );
      await tester.pumpAndSettle();

      final SemanticsData data = tester
          .getSemantics(find.byKey(const Key('tile-under-test')))
          .getSemanticsData();

      expect(data.flagsCollection.isImage, isTrue);
      expect(data.flagsCollection.isButton, isFalse);

      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byKey(const Key('tile-under-test'))),
      );
      expect(data.label, l10n.masterPortfolioTileSemantics(1));

      handle.dispose();
    });
  });
}
