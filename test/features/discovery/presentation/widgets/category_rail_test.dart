// Phase 13.x (Variant A «Рейка + послуги») — widget tests for [CategoryRailTile]
// in isolation.
//
// The redesign removed the `take(6)` cap and the «Всі категорії» more-tile, and
// reworked each tile to size to its own label so the FULL category name renders
// — short («Брови») on one line, long («Перманентний макіяж») wrapped onto a
// second line — never clipped to an ellipsis. These tests pin that tile-level
// contract directly (the screen-level «all categories render» count is pinned in
// search_filters_screen_test.dart):
//   • a long label renders in FULL (Text.data == the full label, no truncation);
//   • the label Text never opts into TextOverflow.ellipsis (softWrap, maxLines:2);
//   • the tile is width-bounded (minWidth 72 .. maxWidth 132) via a ConstrainedBox
//     so a short label still reads as a comfortable pill and a long one wraps
//     instead of stretching the rail.
//
// All finders are type/widget-based; the label string is fixture data asserted
// only as rendered content.

import 'package:beautica_mobile/features/discovery/presentation/widgets/category_rail.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/overflow_guard.dart';

/// The longest realistic category name in the live taxonomy — two words that
/// must wrap onto a second line rather than clip. Used to prove the no-ellipsis
/// full-label contract.
const String _longLabel = 'Перманентний макіяж';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

/// Finds the tile's caption [Text] (the one carrying the category label),
/// excluding any incidental text. The tile renders exactly one Text — its label.
Text _labelText(WidgetTester tester, String label) {
  return tester.widget<Text>(find.text(label));
}

void main() {
  setUp(installOverflowGuard);

  testWidgets('renders a long label IN FULL — no ellipsis, no truncation', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        CategoryRailTile(
          icon: Icons.gesture_outlined,
          label: _longLabel,
          selected: false,
          onTap: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The full label is present as rendered content — not clipped to «Перман…».
    expect(find.text(_longLabel), findsOneWidget);

    final Text label = _labelText(tester, _longLabel);
    // Ground-truth no-clip contract: the caption never opts into the ellipsis
    // overflow, wraps softly, and is allowed two lines for a long name.
    expect(
      label.overflow,
      isNot(TextOverflow.ellipsis),
      reason: 'the caption must never clip the category name to «…»',
    );
    expect(label.softWrap, isTrue, reason: 'a long label wraps, not clips');
    expect(label.maxLines, 2, reason: 'a long label gets a second line');
    // The Text data is the untruncated label verbatim.
    expect(label.data, _longLabel);
  });

  testWidgets(
    'long label actually lays out on two lines (render-layer, no overflow)',
    (tester) async {
      await tester.pumpWidget(
        _host(
          CategoryRailTile(
            icon: Icons.gesture_outlined,
            label: _longLabel,
            selected: false,
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Ground truth from the render tree: the bounded-width tile forces the
      // long two-word label onto a second line WITHOUT firing the maxLines clip
      // — i.e. it fits in 2 lines and is not truncated.
      final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
        find.text(_longLabel),
      );
      expect(
        paragraph.didExceedMaxLines,
        isFalse,
        reason: 'the long label must fit within 2 lines, not overflow/clip',
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'the tile must lay out cleanly with no RenderFlex overflow',
      );
    },
  );

  testWidgets('a short label renders in full as well (single line)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        CategoryRailTile(
          icon: Icons.remove_red_eye_outlined,
          label: 'Брови',
          selected: false,
          onTap: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Брови'), findsOneWidget);
    expect(_labelText(tester, 'Брови').data, 'Брови');
    expect(tester.takeException(), isNull);
  });

  testWidgets('tile is width-bounded by a ConstrainedBox (72..132) so it sizes '
      'to its label', (tester) async {
    await tester.pumpWidget(
      _host(
        CategoryRailTile(
          icon: Icons.gesture_outlined,
          label: _longLabel,
          selected: false,
          onTap: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The tile constrains its own width so a long label wraps instead of
    // stretching the rail; a short label still reads as a comfortable pill.
    final ConstrainedBox box = tester.widget<ConstrainedBox>(
      find
          .descendant(
            of: find.byType(CategoryRailTile),
            matching: find.byType(ConstrainedBox),
          )
          .first,
    );
    expect(box.constraints.minWidth, 72);
    expect(box.constraints.maxWidth, 132);

    // And the rendered tile width actually falls inside that band.
    final double width = tester.getSize(find.byType(CategoryRailTile)).width;
    expect(width, greaterThanOrEqualTo(72));
    expect(width, lessThanOrEqualTo(132));
  });

  testWidgets('tapping the tile fires its onTap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        CategoryRailTile(
          icon: Icons.remove_red_eye_outlined,
          label: 'Брови',
          selected: false,
          onTap: () => taps++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(CategoryRailTile));
    await tester.pump();

    expect(taps, 1);
  });
}
