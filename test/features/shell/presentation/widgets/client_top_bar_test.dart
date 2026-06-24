// Phase 13.3 — Minimal render + interaction tests for the shared [ClientTopBar]
// (the relocated wordmark · bell · burger chrome used by Головна, BEAUTY
// PASSPORT and Пошук).
//
// The BellButton idle/unread asset swap is exhaustively covered in
// home_hub_screen_test.dart; here we only assert the SHARED bar renders its
// three parts, honours the caller-supplied keys + callbacks, and forwards
// hasUnread to the bell asset (so the swap is wired through the shared widget,
// not just the home hub).

import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/shell/presentation/widgets/client_top_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(
    body: Padding(padding: const EdgeInsets.all(16), child: child),
  ),
);

/// Hosts [child] inside the SMALLEST supported phone width (360dp) so the
/// wordmark layout is exercised under the tightest real device constraint.
/// The 16dp horizontal page padding mirrors the production branch-root shells
/// (Головна / BEAUTY PASSPORT / Пошук), reproducing the original clip
/// condition — the wordmark gets 360 − 32 = 328dp of row width to share with
/// the bell + burger.
Widget _phoneHost(
  Widget child, {
  TextScaler textScaler = TextScaler.noScaling,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: const Size(360, 800), textScaler: textScaler),
      child: Scaffold(
        body: SizedBox(
          width: 360,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: child,
          ),
        ),
      ),
    ),
  );
}

/// Reads the wordmark's [RenderParagraph] and reports whether the laid-out
/// text overflowed its `maxLines: 1` — i.e. whether the ellipsis guard fired.
///
/// `didExceedMaxLines` is the ground-truth render-layer signal: it is `true`
/// exactly when the paragraph could not fit on its single line and was
/// clipped to "Beatu…". Asserting on it (rather than pixel widths) is robust
/// to font-metric jitter while still failing on the old `Flexible` + `Spacer`
/// layout that starved the wordmark to ~50% of the row.
bool _wordmarkDidOverflow(WidgetTester tester) {
  final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
    find.text('beautica'),
  );
  return paragraph.didExceedMaxLines;
}

ClientTopBar _bar() => ClientTopBar(
  onBell: () {},
  onBurger: () {},
  bellSemanticLabel: 'Сповіщення',
  burgerSemanticLabel: 'Меню',
  burgerKey: const Key('btn-menu-search'),
);

/// The asset path of the rendered bell [AppIcon].
String _bellAsset(WidgetTester tester) {
  final AppIcon icon = tester.widget<AppIcon>(
    find.byKey(BellButton.bellIconKey),
  );
  return icon.asset;
}

void main() {
  testWidgets(
    'renders the beautica wordmark + bell + burger with caller keys',
    (tester) async {
      await tester.pumpWidget(
        _host(
          ClientTopBar(
            onBell: () {},
            onBurger: () {},
            bellSemanticLabel: 'Сповіщення',
            burgerSemanticLabel: 'Меню',
            bellKey: const Key('search_bell_button'),
            burgerKey: const Key('btn-menu-search'),
          ),
        ),
      );

      // Brand wordmark (untranslated literal) + both action buttons by key.
      expect(find.text('beautica'), findsOneWidget);
      expect(find.byKey(const Key('search_bell_button')), findsOneWidget);
      expect(find.byKey(const Key('btn-menu-search')), findsOneWidget);
    },
  );

  // ── Optional burger (regression pin for the new nullable onBurger) ──────────
  //
  // The burger is now OPTIONAL: Пошук passes no onBurger, so no burger renders;
  // Головна / BEAUTY PASSPORT still pass it, so it does. These two cases pin BOTH
  // branches of the `if (onBurger != null)` guard so a refactor that drops the
  // optionality (or always renders the burger) fails the build.
  testWidgets('omits the burger when onBurger is null — bell still renders', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        ClientTopBar(
          onBell: () {},
          // onBurger intentionally omitted (null) — the Пошук configuration.
          bellSemanticLabel: 'Сповіщення',
          bellKey: const Key('search_bell_button'),
        ),
      ),
    );

    // Bell present (it is a BellButton/AppIcon, NOT a NeumorphicIconButton).
    expect(find.byKey(const Key('search_bell_button')), findsOneWidget);
    expect(find.byKey(BellButton.bellIconKey), findsOneWidget);
    // No burger: the only NeumorphicIconButton in the bar is the burger, so a
    // zero count proves the burger branch did not render.
    expect(find.byType(NeumorphicIconButton), findsNothing);
  });

  testWidgets(
    'renders the burger when onBurger is provided (Головна / passport config)',
    (tester) async {
      await tester.pumpWidget(
        _host(
          ClientTopBar(
            onBell: () {},
            onBurger: () {},
            bellSemanticLabel: 'Сповіщення',
            burgerSemanticLabel: 'Меню',
            bellKey: const Key('btn-bell-client'),
            burgerKey: const Key('btn-menu-client'),
          ),
        ),
      );

      // Both the keyed burger AND the underlying NeumorphicIconButton render.
      expect(find.byKey(const Key('btn-menu-client')), findsOneWidget);
      expect(find.byType(NeumorphicIconButton), findsOneWidget);
      expect(find.byKey(const Key('btn-bell-client')), findsOneWidget);
    },
  );

  testWidgets('bell and burger fire their callbacks when tapped', (
    tester,
  ) async {
    var bellTaps = 0;
    var burgerTaps = 0;
    await tester.pumpWidget(
      _host(
        ClientTopBar(
          onBell: () => bellTaps++,
          onBurger: () => burgerTaps++,
          bellSemanticLabel: 'Сповіщення',
          burgerSemanticLabel: 'Меню',
          bellKey: const Key('search_bell_button'),
          burgerKey: const Key('btn-menu-search'),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('search_bell_button')));
    await tester.tap(find.byKey(const Key('btn-menu-search')));
    await tester.pump();

    expect(bellTaps, 1);
    expect(burgerTaps, 1);
  });

  testWidgets('idle bar renders the dotless bell asset (hasUnread: false)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        ClientTopBar(
          onBell: () {},
          onBurger: () {},
          bellSemanticLabel: 'Сповіщення',
          burgerSemanticLabel: 'Меню',
          burgerKey: const Key('btn-menu-search'),
        ),
      ),
    );

    expect(_bellAsset(tester), BeauticaAssetIcons.notificationPlain);
  });

  testWidgets('unread bar swaps to the dotted bell asset (hasUnread: true)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        ClientTopBar(
          onBell: () {},
          onBurger: () {},
          bellSemanticLabel: 'Сповіщення',
          burgerSemanticLabel: 'Меню',
          burgerKey: const Key('btn-menu-search'),
          hasUnread: true,
        ),
      ),
    );

    expect(_bellAsset(tester), BeauticaAssetIcons.notificationUnread);
  });

  // ---------------------------------------------------------------------------
  // Regression — wordmark truncation ("Beatu…") on every CLIENT page.
  //
  // The bug: the wordmark Text was wrapped in a `Flexible` that competed 1:1
  // with the adjacent `const Spacer()` for the Row's free space. RenderFlex
  // split the leftover width 1:1, granting the wordmark only ~50% (~110–136dp
  // on a 360dp phone) — less than its ~140–155dp intrinsic width (Comfortaa
  // 22pt w700, letterSpacing 3.52px). With `maxLines: 1` + ellipsis, the bar
  // rendered "Beatu…" on Головна / BEAUTY PASSPORT / Пошук.
  //
  // The fix removed the `Flexible` wrapper: the bare Text now takes its
  // intrinsic width and the lone Spacer absorbs all slack. These tests pin the
  // render-layer overflow state so re-introducing a Flexible (or any layout
  // that re-starves the wordmark) fails the build.
  // ---------------------------------------------------------------------------

  testWidgets(
    'wordmark is NOT truncated at the smallest phone width (360dp, 1.0x)',
    (tester) async {
      await tester.pumpWidget(_phoneHost(_bar()));
      await tester.pumpAndSettle();

      // Ground truth: the single-line paragraph fit without firing ellipsis.
      // FAILS on the old Flexible+Spacer layout (wordmark clipped to "Beatu…");
      // PASSES now that the bare Text sizes to its intrinsic width.
      expect(
        _wordmarkDidOverflow(tester),
        isFalse,
        reason: 'wordmark must render in full — not clipped to "Beatu…"',
      );
    },
  );

  testWidgets(
    'wordmark layout survives elevated text scale (1.3x) without RenderFlex '
    'overflow',
    (tester) async {
      await tester.pumpWidget(
        _phoneHost(_bar(), textScaler: const TextScaler.linear(1.3)),
      );
      await tester.pumpAndSettle();

      // At elevated scale the row must still lay out cleanly — no RenderFlex
      // "overflowed by N pixels" exception is the realistic guarantee here.
      // The maxLines:1 + ellipsis guard is permitted to engage at extreme
      // scale, so we do NOT assert no-truncation; we assert the bar renders
      // and the three parts are still present (the bar did not break).
      expect(tester.takeException(), isNull);
      expect(find.text('beautica'), findsOneWidget);
      expect(find.byKey(const Key('btn-menu-search')), findsOneWidget);
    },
  );
}
