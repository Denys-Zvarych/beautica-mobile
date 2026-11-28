// M544 — the promoted SwipeActionBackground: its defaults are the original
// «Мої салони» delete reveal; icon / label / colour are additive overrides.
// Pixels: test/golden/swipe_action_background_golden_test.dart.

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/swipe_action_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

Color? _fill(WidgetTester tester) =>
    (tester.widget<Container>(find.byType(Container).first).decoration
            as BoxDecoration?)
        ?.color;

void main() {
  testWidgets('defaults: the salon delete reveal', (tester) async {
    await tester.pumpApp(
      const Scaffold(
        body: SizedBox(height: 64, child: SwipeActionBackground()),
      ),
    );
    final AppLocalizations l10n = AppLocalizations.of(
      tester.element(find.byType(SwipeActionBackground)),
    );
    expect(find.text(l10n.deleteSalonAction), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
    expect(_fill(tester), BrandColors.error);
  });

  testWidgets('icon, label and colour overrides', (tester) async {
    await tester.pumpApp(
      const Scaffold(
        body: SizedBox(
          height: 64,
          child: SwipeActionBackground(
            icon: Icons.person_remove_outlined,
            label: 'remove-label',
            color: BrandColors.accentDeep,
          ),
        ),
      ),
    );
    expect(find.text('remove-label'), findsOneWidget);
    expect(find.byIcon(Icons.person_remove_outlined), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
    expect(_fill(tester), BrandColors.accentDeep);
  });
}
