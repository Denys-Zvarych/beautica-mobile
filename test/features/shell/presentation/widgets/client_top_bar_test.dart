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
import 'package:beautica_mobile/features/shell/presentation/widgets/client_top_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(
    body: Padding(padding: const EdgeInsets.all(16), child: child),
  ),
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
}
