// Phase 13.1 — CLIENT 5-tab shell widget tests.
//
// The StatefulShellRoute branch selection + CLIENT↔MASTER role gating is
// exercised exhaustively by the pure-seam tests in
// `test/routing/auth_redirect_test.dart` (CLIENT lands on /home; CLIENT cannot
// reach /master/*, /services, /schedule; non-CLIENT roles cannot reach the
// five client branches). These widget tests cover the [ClientBottomNav] surface
// itself: the 5 tabs render, the elevated center search disc is present (and is
// NOT a Material FAB), tap callbacks fire with the correct index, and the
// active tile highlights — plus the branch placeholder bodies render.

import 'package:beautica_mobile/features/shell/presentation/branch_placeholders.dart';
import 'package:beautica_mobile/features/shell/presentation/widgets/client_bottom_nav.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
  locale: const Locale('uk'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  group('ClientBottomNav', () {
    Widget bar({int activeIndex = 0, ValueChanged<int>? onTap}) => _wrap(
      Align(
        alignment: Alignment.bottomCenter,
        child: ClientBottomNav(
          activeIndex: activeIndex,
          onTap: onTap ?? (_) {},
          homeLabel: 'Головна',
          favoritesLabel: 'Улюблені',
          searchLabel: 'Пошук',
          bookingsLabel: 'Записи',
        ),
      ),
    );

    testWidgets('renders the four flanking tiles + elevated center disc', (
      tester,
    ) async {
      await tester.pumpWidget(bar());

      // 4 flanking tiles (0,1,3,4) — index 2 is the center disc, not a tile.
      expect(find.byKey(const Key('client-nav-tile-0')), findsOneWidget);
      expect(find.byKey(const Key('client-nav-tile-1')), findsOneWidget);
      expect(find.byKey(const Key('client-nav-tile-3')), findsOneWidget);
      expect(find.byKey(const Key('client-nav-tile-4')), findsOneWidget);
      expect(find.byKey(const Key('client-nav-tile-2')), findsNothing);

      // The elevated center Пошук disc.
      expect(find.byKey(const Key('client-nav-search-center')), findsOneWidget);
    });

    testWidgets('center search disc is NOT a Material FloatingActionButton', (
      tester,
    ) async {
      await tester.pumpWidget(bar());
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('shows the four localised flanking labels + brand passport', (
      tester,
    ) async {
      await tester.pumpWidget(bar());
      expect(find.text('Головна'), findsOneWidget);
      expect(find.text('Улюблені'), findsOneWidget);
      expect(find.text('Записи'), findsOneWidget);
      // The untranslated brand constant (the 5th tab caption).
      expect(find.text('BEAUTY PASSPORT'), findsOneWidget);
      // The center disc is icon-only — no "Пошук" caption beneath it.
      expect(find.text('Пошук'), findsNothing);
    });

    testWidgets('tapping a flanking tile reports its index', (tester) async {
      final taps = <int>[];
      await tester.pumpWidget(bar(onTap: taps.add));

      await tester.tap(find.byKey(const Key('client-nav-tile-3')));
      await tester.pump();
      expect(taps, equals(<int>[3]));
    });

    testWidgets('tapping the center disc reports index 2', (tester) async {
      final taps = <int>[];
      await tester.pumpWidget(bar(onTap: taps.add));

      await tester.tap(find.byKey(const Key('client-nav-search-center')));
      await tester.pump();
      expect(taps, equals(<int>[2]));
    });

    testWidgets('active tile swaps to its filled icon, inactive stay outline', (
      tester,
    ) async {
      await tester.pumpWidget(bar(activeIndex: 1));

      // The active Улюблені tile renders the filled glyph; the inactive Головна
      // tile keeps its outline glyph — the visible signal of selection.
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
      expect(find.byIcon(Icons.favorite_outline_rounded), findsNothing);
      expect(find.byIcon(Icons.home_outlined), findsOneWidget);
      expect(find.byIcon(Icons.home_rounded), findsNothing);
    });

    testWidgets('active tile carries the selected accessibility flag', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(bar(activeIndex: 1));

      // The keyed tile's merged node carries the Semantics label + the Text
      // child label (hence the doubled label), the button + selected flags,
      // and a single tap action.
      expect(
        tester.getSemantics(find.byKey(const Key('client-nav-tile-1'))),
        matchesSemantics(
          isSelected: true,
          isButton: true,
          label: 'Улюблені\nУлюблені',
          hasTapAction: true,
          hasSelectedState: true,
        ),
      );
      handle.dispose();
    });
  });

  group('Client branch placeholders', () {
    testWidgets('home placeholder renders its localised title + coming-soon', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const ClientHomePlaceholderScreen()));
      await tester.pump(const Duration(seconds: 1)); // settle the reveal

      expect(find.byKey(const Key('client-branch-home')), findsOneWidget);
      expect(find.text('Головна'), findsOneWidget);
      expect(find.text('Скоро…'), findsOneWidget);
    });

    testWidgets('passport placeholder shows the untranslated brand title', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const ClientPassportPlaceholderScreen()));
      await tester.pump(const Duration(seconds: 1));

      expect(find.byKey(const Key('client-branch-passport')), findsOneWidget);
      expect(find.text('BEAUTY PASSPORT'), findsOneWidget);
    });
  });
}
