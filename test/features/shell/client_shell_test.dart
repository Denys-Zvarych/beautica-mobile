// Phase 13.1 — CLIENT 5-tab shell widget tests.
//
// Updated in Phase 13.7 (SVG icon migration complete): all five tabs now use
// SVG assets via AppIcon/BeauticaAssetIcons. Material IconData on the flanking
// tabs have been fully replaced. Tests have been updated accordingly:
//   - "only home is SVG" and "no SVG bleed" assertions FLIPPED → all five tabs
//     are asserted to use SVG (AppIcon), and leftover Material glyphs for
//     favorite/note/badge/search are asserted absent.
//   - Per-tab outline+filled assertions added for tabs 1, 3, 4.
//   - Center search disc asserted to render the searchFilled SVG.
//
// The StatefulShellRoute branch selection + CLIENT↔MASTER role gating is
// exercised exhaustively by the pure-seam tests in
// `test/routing/auth_redirect_test.dart`. These widget tests cover the
// [ClientBottomNav] surface itself: the 5 tabs render, the elevated center
// search disc is present (NOT a Material FAB), tap callbacks fire with the
// correct index, and the active tile highlights — plus the branch placeholder
// bodies render.

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

    // ── ALL 5 tabs are now SVG ────────────────────────────────────────────────

    testWidgets(
      'all four flanking tiles render AppIcon (SVG), not Material Icon '
      '(all tabs migrated)',
      (tester) async {
        // With activeIndex=0 every tab is visible (0 active, 1/3/4 inactive).
        await tester.pumpWidget(bar(activeIndex: 0));

        // Every flanking tile must contain an AppIcon in its subtree.
        for (final int tileIndex in <int>[0, 1, 3, 4]) {
          final Finder tile = find.byKey(Key('client-nav-tile-$tileIndex'));
          expect(
            find.descendant(of: tile, matching: find.byType(AppIcon)),
            findsOneWidget,
            reason:
                'client-nav-tile-$tileIndex must render an AppIcon (SVG) — '
                'all five tabs have migrated to SVG assets.',
          );
        }
      },
    );

    testWidgets(
      'no leftover Material icon glyphs for favorites/search/bookings/passport '
      '(old Icons.* constants absent from flanking tiles)',
      (tester) async {
        await tester.pumpWidget(bar(activeIndex: 0));

        // Icons that lived on the four flanking tabs before SVG migration.
        // If any of these appear, the nav has a leftover Material glyph.
        final List<IconData> legacyGlyphs = <IconData>[
          Icons.favorite_outline_rounded,
          Icons.favorite_rounded,
          Icons.event_note_outlined,
          Icons.event_note_rounded,
          Icons.badge_outlined,
          Icons.badge_rounded,
          Icons.search_rounded,
        ];
        for (final IconData glyph in legacyGlyphs) {
          expect(
            find.byIcon(glyph),
            findsNothing,
            reason:
                '${glyph.codePoint} — this Material glyph must not appear in '
                'the nav; the flanking tabs are now fully SVG.',
          );
        }
      },
    );

    testWidgets(
      'center search disc renders searchFilled SVG (not Material search glyph)',
      (tester) async {
        await tester.pumpWidget(bar(activeIndex: 2));

        // The center disc must not use the legacy Material search icon.
        expect(find.byIcon(Icons.search_rounded), findsNothing);

        // The disc contains an AppIcon with the searchFilled asset.
        final List<AppIcon> appIcons = tester
            .widgetList<AppIcon>(find.byType(AppIcon))
            .toList();
        expect(
          appIcons.any((w) => w.asset == BeauticaAssetIcons.searchFilled),
          isTrue,
          reason:
              'The center search disc must render searchFilled via AppIcon.',
        );
      },
    );

    // ── Tab 0 — home ─────────────────────────────────────────────────────────

    testWidgets('active home tab renders homeFilled SVG via AppIcon', (
      tester,
    ) async {
      await tester.pumpWidget(bar(activeIndex: 0));

      expect(find.byIcon(Icons.home_outlined), findsNothing);
      expect(find.byIcon(Icons.home_rounded), findsNothing);
      final homeAppIcons = tester.widgetList<AppIcon>(find.byType(AppIcon));
      expect(
        homeAppIcons.any((w) => w.asset == BeauticaAssetIcons.homeFilled),
        isTrue,
        reason: 'Active home tab must render homeFilled SVG via AppIcon',
      );
    });

    testWidgets('inactive home tab renders homeOutline SVG via AppIcon', (
      tester,
    ) async {
      await tester.pumpWidget(bar(activeIndex: 1));

      expect(find.byIcon(Icons.home_outlined), findsNothing);
      expect(find.byIcon(Icons.home_rounded), findsNothing);
      final homeAppIcons = tester.widgetList<AppIcon>(find.byType(AppIcon));
      expect(
        homeAppIcons.any((w) => w.asset == BeauticaAssetIcons.homeOutline),
        isTrue,
        reason: 'Inactive home tab must render homeOutline SVG via AppIcon',
      );
    });

    testWidgets('inactive home AppIcon carries BrandColors.muted ColorFilter', (
      tester,
    ) async {
      await tester.pumpWidget(bar(activeIndex: 1));

      final SvgPicture outlinePic = tester
          .widgetList<SvgPicture>(find.byType(SvgPicture))
          .firstWhere(
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
        equals(const ColorFilter.mode(Color(0xFF9A8367), BlendMode.srcIn)),
        reason:
            'Inactive home AppIcon must be tinted BrandColors.muted '
            '(0xFF9A8367).',
      );
    });

    testWidgets(
      'active home AppIcon carries BrandColors.accentDeep ColorFilter',
      (tester) async {
        await tester.pumpWidget(bar(activeIndex: 0));

        final SvgPicture filledPic = tester
            .widgetList<SvgPicture>(find.byType(SvgPicture))
            .firstWhere(
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
          equals(const ColorFilter.mode(Color(0xFF6A4A28), BlendMode.srcIn)),
          reason:
              'Active home AppIcon must be tinted BrandColors.accentDeep '
              '(0xFF6A4A28).',
        );
      },
    );

    // ── Tab 1 — favorites (heart) ─────────────────────────────────────────────

    testWidgets('active favorites tab renders heartFilled SVG via AppIcon', (
      tester,
    ) async {
      await tester.pumpWidget(bar(activeIndex: 1));

      final List<AppIcon> appIcons = tester
          .widgetList<AppIcon>(find.byType(AppIcon))
          .toList();
      expect(
        appIcons.any((w) => w.asset == BeauticaAssetIcons.heartFilled),
        isTrue,
        reason: 'Active favorites tab (index 1) must render heartFilled SVG.',
      );
      expect(
        appIcons.any((w) => w.asset == BeauticaAssetIcons.heartOutline),
        isFalse,
        reason:
            'Active favorites tab must not show heartOutline — only heartFilled.',
      );
    });

    testWidgets('inactive favorites tab renders heartOutline SVG via AppIcon', (
      tester,
    ) async {
      await tester.pumpWidget(bar(activeIndex: 0));

      final List<AppIcon> appIcons = tester
          .widgetList<AppIcon>(find.byType(AppIcon))
          .toList();
      expect(
        appIcons.any((w) => w.asset == BeauticaAssetIcons.heartOutline),
        isTrue,
        reason:
            'Inactive favorites tab (index 1) must render heartOutline SVG.',
      );
    });

    // ── Tab 3 — bookings (note) ───────────────────────────────────────────────

    testWidgets('active bookings tab renders noteFilled SVG via AppIcon', (
      tester,
    ) async {
      await tester.pumpWidget(bar(activeIndex: 3));

      final List<AppIcon> appIcons = tester
          .widgetList<AppIcon>(find.byType(AppIcon))
          .toList();
      expect(
        appIcons.any((w) => w.asset == BeauticaAssetIcons.noteFilled),
        isTrue,
        reason: 'Active bookings tab (index 3) must render noteFilled SVG.',
      );
      expect(
        appIcons.any((w) => w.asset == BeauticaAssetIcons.noteOutline),
        isFalse,
        reason:
            'Active bookings tab must not show noteOutline — only noteFilled.',
      );
    });

    testWidgets('inactive bookings tab renders noteOutline SVG via AppIcon', (
      tester,
    ) async {
      await tester.pumpWidget(bar(activeIndex: 0));

      final List<AppIcon> appIcons = tester
          .widgetList<AppIcon>(find.byType(AppIcon))
          .toList();
      expect(
        appIcons.any((w) => w.asset == BeauticaAssetIcons.noteOutline),
        isTrue,
        reason: 'Inactive bookings tab (index 3) must render noteOutline SVG.',
      );
    });

    // ── Tab 4 — BEAUTY PASSPORT ───────────────────────────────────────────────

    testWidgets('active passport tab renders passportFilled SVG via AppIcon', (
      tester,
    ) async {
      await tester.pumpWidget(bar(activeIndex: 4));

      final List<AppIcon> appIcons = tester
          .widgetList<AppIcon>(find.byType(AppIcon))
          .toList();
      expect(
        appIcons.any((w) => w.asset == BeauticaAssetIcons.passportFilled),
        isTrue,
        reason: 'Active passport tab (index 4) must render passportFilled SVG.',
      );
      expect(
        appIcons.any((w) => w.asset == BeauticaAssetIcons.passportOutline),
        isFalse,
        reason:
            'Active passport tab must not show passportOutline — only '
            'passportFilled.',
      );
    });

    testWidgets(
      'inactive passport tab renders passportOutline SVG via AppIcon',
      (tester) async {
        await tester.pumpWidget(bar(activeIndex: 0));

        final List<AppIcon> appIcons = tester
            .widgetList<AppIcon>(find.byType(AppIcon))
            .toList();
        expect(
          appIcons.any((w) => w.asset == BeauticaAssetIcons.passportOutline),
          isTrue,
          reason:
              'Inactive passport tab (index 4) must render passportOutline SVG.',
        );
      },
    );

    // ── Tint assertions for remaining tabs (1, 3, 4) ─────────────────────────
    //
    // The home tab (index 0) already has active/inactive tint assertions
    // (lines above). These cover the other three flanking tabs so that any
    // regression that hard-codes BrandColors.muted for all tabs — or that
    // forgets to pass `color:` to AppIcon — is caught immediately.
    //
    // BrandColors.muted  = 0xFF9A8367  (inactive)
    // BrandColors.accentDeep = 0xFF6A4A28  (active)

    testWidgets(
      'inactive favorites AppIcon (index 1) carries BrandColors.muted ColorFilter',
      (tester) async {
        await tester.pumpWidget(bar(activeIndex: 0));

        final SvgPicture outlinePic = tester
            .widgetList<SvgPicture>(find.byType(SvgPicture))
            .firstWhere(
              (p) =>
                  p.bytesLoader is SvgAssetLoader &&
                  (p.bytesLoader as SvgAssetLoader).assetName ==
                      BeauticaAssetIcons.heartOutline,
              orElse: () => throw TestFailure(
                'heartOutline SvgPicture not found — favorites tab inactive',
              ),
            );

        expect(
          outlinePic.colorFilter,
          equals(const ColorFilter.mode(Color(0xFF9A8367), BlendMode.srcIn)),
          reason:
              'Inactive favorites AppIcon must be tinted BrandColors.muted '
              '(0xFF9A8367).',
        );
      },
    );

    testWidgets(
      'active favorites AppIcon (index 1) carries BrandColors.accentDeep ColorFilter',
      (tester) async {
        await tester.pumpWidget(bar(activeIndex: 1));

        final SvgPicture filledPic = tester
            .widgetList<SvgPicture>(find.byType(SvgPicture))
            .firstWhere(
              (p) =>
                  p.bytesLoader is SvgAssetLoader &&
                  (p.bytesLoader as SvgAssetLoader).assetName ==
                      BeauticaAssetIcons.heartFilled,
              orElse: () => throw TestFailure(
                'heartFilled SvgPicture not found — favorites tab active',
              ),
            );

        expect(
          filledPic.colorFilter,
          equals(const ColorFilter.mode(Color(0xFF6A4A28), BlendMode.srcIn)),
          reason:
              'Active favorites AppIcon must be tinted BrandColors.accentDeep '
              '(0xFF6A4A28).',
        );
      },
    );

    testWidgets(
      'inactive bookings AppIcon (index 3) carries BrandColors.muted ColorFilter',
      (tester) async {
        await tester.pumpWidget(bar(activeIndex: 0));

        final SvgPicture outlinePic = tester
            .widgetList<SvgPicture>(find.byType(SvgPicture))
            .firstWhere(
              (p) =>
                  p.bytesLoader is SvgAssetLoader &&
                  (p.bytesLoader as SvgAssetLoader).assetName ==
                      BeauticaAssetIcons.noteOutline,
              orElse: () => throw TestFailure(
                'noteOutline SvgPicture not found — bookings tab inactive',
              ),
            );

        expect(
          outlinePic.colorFilter,
          equals(const ColorFilter.mode(Color(0xFF9A8367), BlendMode.srcIn)),
          reason:
              'Inactive bookings AppIcon must be tinted BrandColors.muted '
              '(0xFF9A8367).',
        );
      },
    );

    testWidgets(
      'active bookings AppIcon (index 3) carries BrandColors.accentDeep ColorFilter',
      (tester) async {
        await tester.pumpWidget(bar(activeIndex: 3));

        final SvgPicture filledPic = tester
            .widgetList<SvgPicture>(find.byType(SvgPicture))
            .firstWhere(
              (p) =>
                  p.bytesLoader is SvgAssetLoader &&
                  (p.bytesLoader as SvgAssetLoader).assetName ==
                      BeauticaAssetIcons.noteFilled,
              orElse: () => throw TestFailure(
                'noteFilled SvgPicture not found — bookings tab active',
              ),
            );

        expect(
          filledPic.colorFilter,
          equals(const ColorFilter.mode(Color(0xFF6A4A28), BlendMode.srcIn)),
          reason:
              'Active bookings AppIcon must be tinted BrandColors.accentDeep '
              '(0xFF6A4A28).',
        );
      },
    );

    testWidgets(
      'inactive passport AppIcon (index 4) carries BrandColors.muted ColorFilter',
      (tester) async {
        await tester.pumpWidget(bar(activeIndex: 0));

        final SvgPicture outlinePic = tester
            .widgetList<SvgPicture>(find.byType(SvgPicture))
            .firstWhere(
              (p) =>
                  p.bytesLoader is SvgAssetLoader &&
                  (p.bytesLoader as SvgAssetLoader).assetName ==
                      BeauticaAssetIcons.passportOutline,
              orElse: () => throw TestFailure(
                'passportOutline SvgPicture not found — passport tab inactive',
              ),
            );

        expect(
          outlinePic.colorFilter,
          equals(const ColorFilter.mode(Color(0xFF9A8367), BlendMode.srcIn)),
          reason:
              'Inactive passport AppIcon must be tinted BrandColors.muted '
              '(0xFF9A8367).',
        );
      },
    );

    testWidgets(
      'active passport AppIcon (index 4) carries BrandColors.accentDeep ColorFilter',
      (tester) async {
        await tester.pumpWidget(bar(activeIndex: 4));

        final SvgPicture filledPic = tester
            .widgetList<SvgPicture>(find.byType(SvgPicture))
            .firstWhere(
              (p) =>
                  p.bytesLoader is SvgAssetLoader &&
                  (p.bytesLoader as SvgAssetLoader).assetName ==
                      BeauticaAssetIcons.passportFilled,
              orElse: () => throw TestFailure(
                'passportFilled SvgPicture not found — passport tab active',
              ),
            );

        expect(
          filledPic.colorFilter,
          equals(const ColorFilter.mode(Color(0xFF6A4A28), BlendMode.srcIn)),
          reason:
              'Active passport AppIcon must be tinted BrandColors.accentDeep '
              '(0xFF6A4A28).',
        );
      },
    );

    // ── Semantics ─────────────────────────────────────────────────────────────

    testWidgets('active tile carries the selected accessibility flag', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(bar(activeIndex: 1));

      // Since all tiles now use AppIcon (SvgPicture without a semanticsLabel),
      // flutter_svg adds the isImage semantics flag to the merged node. We pass
      // isImage: true to matchesSemantics so the flag set matches exactly.
      expect(
        tester.getSemantics(find.byKey(const Key('client-nav-tile-1'))),
        matchesSemantics(
          isSelected: true,
          isButton: true,
          isImage: true,
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
        await tester.pumpWidget(_wrap(const ClientHomePlaceholderScreen()));
        await tester.pump(const Duration(seconds: 1));

        expect(
          find.byType(AppIcon),
          findsOneWidget,
          reason:
              'ClientHomePlaceholderScreen must render AppIcon for the filled '
              'home SVG — not a Material Icon fallback.',
        );

        final AppIcon appIcon = tester.widget<AppIcon>(find.byType(AppIcon));
        expect(appIcon.asset, equals(BeauticaAssetIcons.homeFilled));
        expect(
          appIcon.color,
          equals(const Color(0xFF6A4A28)), // BrandColors.accentDeep
        );
        expect(appIcon.size, equals(40.0));
      },
    );

    // The favorites branch has NO placeholder any more — Phase 111 mounts the
    // real FavoritesScreen at RouteNames.clientFavorites, and
    // ClientFavoritesPlaceholderScreen was deleted with it. Its icon-pillow
    // test went with the widget: there is nothing left for it to assert. The
    // branch's `client-branch-favorites` Key (the one contract that outlived
    // the placeholder) is pinned by the router-tier matrix
    // (test/routing/client_branch_chrome_matrix.dart) and by
    // scripts/forbid_missing_client_branch_key.sh.

    testWidgets(
      'search placeholder icon pillow uses searchFilled SVG at accentDeep tint',
      (tester) async {
        await tester.pumpWidget(_wrap(const ClientSearchPlaceholderScreen()));
        await tester.pump(const Duration(seconds: 1));

        expect(find.byIcon(Icons.search_rounded), findsNothing);

        expect(find.byType(AppIcon), findsOneWidget);
        final AppIcon appIcon = tester.widget<AppIcon>(find.byType(AppIcon));
        expect(
          appIcon.asset,
          equals(BeauticaAssetIcons.searchFilled),
          reason: 'Search placeholder must use searchFilled SVG via AppIcon.',
        );
        expect(appIcon.color, equals(const Color(0xFF6A4A28)));
        expect(appIcon.size, equals(40.0));
      },
    );

    testWidgets(
      'bookings placeholder icon pillow uses noteFilled SVG at accentDeep tint',
      (tester) async {
        await tester.pumpWidget(_wrap(const ClientBookingsPlaceholderScreen()));
        await tester.pump(const Duration(seconds: 1));

        expect(find.byIcon(Icons.event_note_rounded), findsNothing);

        expect(find.byType(AppIcon), findsOneWidget);
        final AppIcon appIcon = tester.widget<AppIcon>(find.byType(AppIcon));
        expect(
          appIcon.asset,
          equals(BeauticaAssetIcons.noteFilled),
          reason: 'Bookings placeholder must use noteFilled SVG via AppIcon.',
        );
        expect(appIcon.color, equals(const Color(0xFF6A4A28)));
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

    testWidgets(
      'passport placeholder icon pillow uses passportFilled SVG at accentDeep tint',
      (tester) async {
        await tester.pumpWidget(_wrap(const ClientPassportPlaceholderScreen()));
        await tester.pump(const Duration(seconds: 1));

        expect(find.byIcon(Icons.badge_rounded), findsNothing);

        expect(find.byType(AppIcon), findsOneWidget);
        final AppIcon appIcon = tester.widget<AppIcon>(find.byType(AppIcon));
        expect(
          appIcon.asset,
          equals(BeauticaAssetIcons.passportFilled),
          reason:
              'Passport placeholder must use passportFilled SVG via AppIcon.',
        );
        expect(appIcon.color, equals(const Color(0xFF6A4A28)));
        expect(appIcon.size, equals(40.0));
      },
    );
  });

  // ── app_icon_test.dart dependency — new asset path constants ────────────────

  group('BeauticaAssetIcons — new SVG path constants', () {
    test('searchOutline resolves to the registered asset path', () {
      expect(
        BeauticaAssetIcons.searchOutline,
        'assets/icons/search_outline.svg',
      );
    });
    test('searchFilled resolves to the registered asset path', () {
      expect(BeauticaAssetIcons.searchFilled, 'assets/icons/search_filled.svg');
    });
    test('heartOutline resolves to the registered asset path', () {
      expect(BeauticaAssetIcons.heartOutline, 'assets/icons/heart_outline.svg');
    });
    test('heartFilled resolves to the registered asset path', () {
      expect(BeauticaAssetIcons.heartFilled, 'assets/icons/heart_filled.svg');
    });
    test('noteOutline resolves to the registered asset path', () {
      expect(BeauticaAssetIcons.noteOutline, 'assets/icons/note_outline.svg');
    });
    test('noteFilled resolves to the registered asset path', () {
      expect(BeauticaAssetIcons.noteFilled, 'assets/icons/note_filled.svg');
    });
    test('passportOutline resolves to the registered asset path', () {
      expect(
        BeauticaAssetIcons.passportOutline,
        'assets/icons/passport_outline.svg',
      );
    });
    test('passportFilled resolves to the registered asset path', () {
      expect(
        BeauticaAssetIcons.passportFilled,
        'assets/icons/passport_filled.svg',
      );
    });
    test('notificationOutline resolves to the registered asset path', () {
      expect(
        BeauticaAssetIcons.notificationOutline,
        'assets/icons/notification_outline.svg',
      );
    });
    test('notificationFilled resolves to the registered asset path', () {
      expect(
        BeauticaAssetIcons.notificationFilled,
        'assets/icons/notification_filled.svg',
      );
    });
  });
}
