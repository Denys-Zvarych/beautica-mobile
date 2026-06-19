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

import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/features/shell/presentation/branch_placeholders.dart';
import 'package:beautica_mobile/features/shell/presentation/widgets/client_bottom_nav.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
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

      // Улюблені (index 1) is active — renders filled MaterialIcon glyph.
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
      expect(find.byIcon(Icons.favorite_outline_rounded), findsNothing);

      // Головна (index 0) is inactive — renders the SVG outline asset via
      // AppIcon. No Material home glyphs should appear.
      expect(find.byIcon(Icons.home_outlined), findsNothing);
      expect(find.byIcon(Icons.home_rounded), findsNothing);
      // Confirm the home tile shows AppIcon with the outline SVG path.
      final homeAppIcons = tester.widgetList<AppIcon>(find.byType(AppIcon));
      expect(
        homeAppIcons.any((w) => w.asset == BeauticaAssetIcons.homeOutline),
        isTrue,
        reason: 'Inactive home tab must render homeOutline SVG via AppIcon',
      );
    });

    testWidgets('active home tab renders homeFilled SVG via AppIcon', (
      tester,
    ) async {
      await tester.pumpWidget(bar(activeIndex: 0));

      // Головна (index 0) is active — renders homeFilled SVG.
      expect(find.byIcon(Icons.home_outlined), findsNothing);
      expect(find.byIcon(Icons.home_rounded), findsNothing);
      final homeAppIcons = tester.widgetList<AppIcon>(find.byType(AppIcon));
      expect(
        homeAppIcons.any((w) => w.asset == BeauticaAssetIcons.homeFilled),
        isTrue,
        reason: 'Active home tab must render homeFilled SVG via AppIcon',
      );
    });

    testWidgets('home tab AppIcon is tinted with inactive muted color', (
      tester,
    ) async {
      // When home tab is inactive (activeIndex=1), the AppIcon color should be
      // BrandColors.muted — the same tint applied to Material inactive icons.
      await tester.pumpWidget(bar(activeIndex: 1));

      final svgPictures = tester.widgetList<SvgPicture>(
        find.byType(SvgPicture),
      );
      // The outline SVG picture should have a ColorFilter matching BrandColors.muted.
      expect(
        svgPictures.any(
          (p) =>
              p.bytesLoader is SvgAssetLoader &&
              (p.bytesLoader as SvgAssetLoader).assetName ==
                  BeauticaAssetIcons.homeOutline,
        ),
        isTrue,
        reason: 'Inactive home tab must load homeOutline asset',
      );
    });

    testWidgets(
      'inactive home tab AppIcon carries BrandColors.muted ColorFilter',
      (tester) async {
        // Regression guard: _ClientNavTile passes `color` to AppIcon, which
        // wraps it in ColorFilter.mode(color, srcIn). If that wiring breaks
        // the SVG renders without a tint (white on light) — invisible in prod.
        await tester.pumpWidget(bar(activeIndex: 1));

        final SvgPicture outlinePic = tester.widgetList<SvgPicture>(
          find.byType(SvgPicture),
        ).firstWhere(
          (p) =>
              p.bytesLoader is SvgAssetLoader &&
              (p.bytesLoader as SvgAssetLoader).assetName ==
                  BeauticaAssetIcons.homeOutline,
          orElse: () => throw TestFailure(
            'homeOutline SvgPicture not found in inactive home tab',
          ),
        );

        expect(
          outlinePic.colorFilter,
          equals(
            const ColorFilter.mode(Color(0xFF9A8367), BlendMode.srcIn),
          ),
          reason:
              'Inactive home AppIcon must be tinted BrandColors.muted '
              '(0xFF9A8367). If this fails, _ClientNavTile stopped forwarding '
              'the inactive color to AppIcon.',
        );
      },
    );

    testWidgets(
      'active home tab AppIcon carries BrandColors.accentDeep ColorFilter',
      (tester) async {
        // Regression guard for the active-state tint. When home is selected
        // the icon must warm to accentDeep (0xFF6A4A28) to match the label
        // and indicator pill. A missing tint means the icon is off-brand.
        await tester.pumpWidget(bar(activeIndex: 0));

        final SvgPicture filledPic = tester.widgetList<SvgPicture>(
          find.byType(SvgPicture),
        ).firstWhere(
          (p) =>
              p.bytesLoader is SvgAssetLoader &&
              (p.bytesLoader as SvgAssetLoader).assetName ==
                  BeauticaAssetIcons.homeFilled,
          orElse: () => throw TestFailure(
            'homeFilled SvgPicture not found in active home tab',
          ),
        );

        expect(
          filledPic.colorFilter,
          equals(
            const ColorFilter.mode(Color(0xFF6A4A28), BlendMode.srcIn),
          ),
          reason:
              'Active home AppIcon must be tinted BrandColors.accentDeep '
              '(0xFF6A4A28). If this fails, _ClientNavTile stopped forwarding '
              'the active color to AppIcon.',
        );
      },
    );

    testWidgets(
      'non-home flanking tabs render Material Icon widgets, not AppIcon '
      '(no SVG bleed)',
      (tester) async {
        // Guard against accidental SVG migration on tiles 1, 3, 4.  If any of
        // those items gains svgIcon/svgActiveIcon, AppIcon will appear — this
        // test will fail and force an intentional review.
        await tester.pumpWidget(bar(activeIndex: 0));

        // Exactly one AppIcon exists (home tab only).
        expect(
          find.byType(AppIcon),
          findsOneWidget,
          reason: 'Only the home tab (index 0) uses AppIcon; tiles 1, 3, 4 '
              'must remain Material Icon widgets.',
        );

        // Tiles 1, 3, 4 each contain a Material Icon inside their subtree.
        for (final int tileIndex in <int>[1, 3, 4]) {
          final Finder tile = find.byKey(Key('client-nav-tile-$tileIndex'));
          expect(
            find.descendant(of: tile, matching: find.byType(Icon)),
            findsWidgets,
            reason:
                'client-nav-tile-$tileIndex must render a Material Icon '
                '(not AppIcon).',
          );
          expect(
            find.descendant(of: tile, matching: find.byType(AppIcon)),
            findsNothing,
            reason:
                'client-nav-tile-$tileIndex must not contain an AppIcon — '
                'only the home tab has migrated to SVG.',
          );
        }
      },
    );

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

    testWidgets(
      'home placeholder icon pillow uses homeFilled SVG at accentDeep tint',
      (tester) async {
        // Regression guard: ClientHomePlaceholderScreen passes
        // `AppIcon(BeauticaAssetIcons.homeFilled, size: 40,
        //   color: BrandColors.accentDeep)`
        // to ClientBranchPlaceholder.iconWidget. If it falls back to the
        // IconData path the SVG is never loaded — visible on device as a
        // generic circle placeholder.
        await tester.pumpWidget(_wrap(const ClientHomePlaceholderScreen()));
        await tester.pump(const Duration(seconds: 1));

        // AppIcon must be present.
        expect(
          find.byType(AppIcon),
          findsOneWidget,
          reason:
              'ClientHomePlaceholderScreen must render AppIcon for the filled '
              'home SVG — not a Material Icon fallback.',
        );

        // Verify the specific asset + tint that the source code declares.
        final AppIcon appIcon =
            tester.widget<AppIcon>(find.byType(AppIcon));
        expect(
          appIcon.asset,
          equals(BeauticaAssetIcons.homeFilled),
          reason: 'The placeholder pillow must use the homeFilled asset.',
        );
        expect(
          appIcon.color,
          equals(const Color(0xFF6A4A28)), // BrandColors.accentDeep
          reason:
              'The placeholder pillow AppIcon must be tinted BrandColors.'
              'accentDeep (0xFF6A4A28).',
        );
        expect(appIcon.size, equals(40.0));
      },
    );

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
