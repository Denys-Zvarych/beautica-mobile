// Phase 352 D8 — SelectOptionTile: the promoted shared option row (out of
// SearchableSelectField's private `_SelectOptionTile`), now also used by the
// «Пошук» suggestion list.

import 'package:beautica_mobile/features/services/presentation/widgets/select_option_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the label, is a Semantics button, and is tappable', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectOptionTile(
            key: const Key('tile-under-test'),
            label: 'Манікюр',
            onTap: () => tapped = true,
          ),
        ),
      ),
    );

    // i18n-finder-ok: the tile's `label` param is caller-supplied catalogue
    // data (a category/service name), never app UI copy — it is passed
    // verbatim here as the fixture, not read from AppLocalizations.
    expect(find.text('Манікюр'), findsOneWidget);

    // Inspect the constructed Semantics widget's properties directly — the
    // `Semantics(button: true, ...)` merges into an ancestor node once
    // rendered, so walking the compiled semantics tree from a descendant
    // (`tester.getSemantics`) resolves to the app-root node instead; the
    // constructor-level property is what this row actually declares.
    final Semantics semantics = tester.widget<Semantics>(
      find
          .ancestor(
            // i18n-finder-ok: caller-supplied catalogue data, not UI copy.
            of: find.text('Манікюр'),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(semantics.properties.button, isTrue);
    expect(semantics.properties.label, 'Манікюр');

    await tester.tap(find.byKey(const Key('tile-under-test')));
    await tester.pump();
    expect(tapped, isTrue);
  });

  testWidgets('the tile is at least 48dp tall (tap-target minimum)', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectOptionTile(
            key: const Key('tile-under-test'),
            label: 'Педикюр',
            onTap: () {},
          ),
        ),
      ),
    );

    final Size size = tester.getSize(find.byKey(const Key('tile-under-test')));
    expect(size.height, greaterThanOrEqualTo(48.0));
  });

  testWidgets('long labels ellipsise past maxLines rather than overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 120,
            child: SelectOptionTile(
              key: const Key('tile-under-test'),
              label: 'Дуже довга назва послуги, яка не поміщається в рядок',
              onTap: () {},
              maxLines: 1,
            ),
          ),
        ),
      ),
    );

    final Text text = tester.widget<Text>(
      // i18n-finder-ok: caller-supplied catalogue data, not app UI copy.
      find.text('Дуже довга назва послуги, яка не поміщається в рядок'),
    );
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
    // No overflow render error — pumping without a caught FlutterError proves
    // the layout did not overflow.
  });
}
