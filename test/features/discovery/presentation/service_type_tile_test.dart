// Phase 13.3 — Widget + mapper tests for [ServiceTypeTile] and
// [serviceTypeIcon].
//
// Coverage:
//   serviceTypeIcon — representative slug → glyph mappings, substring matching
//     across the dynamic taxonomy (MANICURE/NAIL → hand; PEDICURE → spa; etc.),
//     and the generic spa_outlined fallback for an unmapped slug.
//   ServiceTypeTile — unselected (raised pillow, muted glyph, no inset well) vs
//     selected (concave NeumorphicInset well, camel glyph), the caption renders,
//     Semantics.selected tracks [selected], and tapping fires onTap.

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/discovery/presentation/widgets/service_type_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

/// The [Icon] glyph rendered inside [tile] under the given [tester].
IconData _iconOf(WidgetTester tester) =>
    tester.widget<Icon>(find.byType(Icon)).icon!;

/// The [Icon] glyph colour rendered inside the tile.
Color? _iconColorOf(WidgetTester tester) =>
    tester.widget<Icon>(find.byType(Icon)).color;

void main() {
  group('serviceTypeIcon', () {
    test('maps nail-family slugs to the hand glyph', () {
      expect(serviceTypeIcon('MANICURE'), Icons.back_hand_outlined);
      expect(serviceTypeIcon('NAIL_ART'), Icons.back_hand_outlined);
    });

    test('maps PEDICURE to the spa glyph (checked before MANICURE/NAIL)', () {
      expect(serviceTypeIcon('PEDICURE'), Icons.spa_outlined);
    });

    test('maps hair-family slugs to the scissors glyph', () {
      expect(serviceTypeIcon('HAIRCUT'), Icons.content_cut_outlined);
      expect(serviceTypeIcon('BARBER'), Icons.content_cut_outlined);
    });

    test('maps lash + brow slugs to their eye glyphs', () {
      expect(serviceTypeIcon('LASH_EXTENSIONS'), Icons.visibility_outlined);
      expect(serviceTypeIcon('BROW_CORRECTION'), Icons.remove_red_eye_outlined);
    });

    test('is case-insensitive (lowercase slug resolves the same)', () {
      expect(serviceTypeIcon('manicure'), Icons.back_hand_outlined);
    });

    test('falls back to spa_outlined for an unmapped slug', () {
      expect(serviceTypeIcon('SOMETHING_UNKNOWN'), Icons.spa_outlined);
      expect(serviceTypeIcon(''), Icons.spa_outlined);
    });
  });

  group('ServiceTypeTile — unselected', () {
    testWidgets(
      'renders a raised pillow (no inset well) with a muted glyph and '
      'the caption',
      (tester) async {
        await tester.pumpWidget(
          _host(
            ServiceTypeTile(
              icon: Icons.back_hand_outlined,
              label: 'Манікюр',
              selected: false,
              onTap: () {},
            ),
          ),
        );

        // Raised state: a DecoratedBox circle, NOT a NeumorphicInset well.
        expect(find.byType(NeumorphicInset), findsNothing);
        expect(_iconOf(tester), Icons.back_hand_outlined);
        expect(
          _iconColorOf(tester),
          BrandColors.textSecondary,
          reason: 'unselected glyph is the muted secondary tone',
        );
        expect(find.text('Манікюр'), findsOneWidget);
      },
    );

    testWidgets('exposes a button Semantics that is NOT selected', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          ServiceTypeTile(
            icon: Icons.spa_outlined,
            label: 'Спа',
            selected: false,
            onTap: () {},
          ),
        ),
      );

      // The tile wraps a Semantics(button: true, selected: <selected>) — assert
      // the selected flag is OFF on the unselected tile.
      final Semantics sem = tester.widget<Semantics>(
        find
            .descendant(
              of: find.byType(ServiceTypeTile),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(sem.properties.button, isTrue);
      expect(sem.properties.selected, isFalse);
    });
  });

  group('ServiceTypeTile — selected', () {
    testWidgets('renders the concave inset well with the camel glyph', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          ServiceTypeTile(
            icon: Icons.back_hand_outlined,
            label: 'Манікюр',
            selected: true,
            onTap: () {},
          ),
        ),
      );

      // Selected state: the glyph sits inside a NeumorphicInset (pressed well).
      expect(find.byType(NeumorphicInset), findsOneWidget);
      expect(_iconOf(tester), Icons.back_hand_outlined);
      expect(
        _iconColorOf(tester),
        BrandColors.accent,
        reason: 'selected glyph warms to the camel accent',
      );
    });

    testWidgets('exposes a button Semantics that IS selected', (tester) async {
      await tester.pumpWidget(
        _host(
          ServiceTypeTile(
            icon: Icons.spa_outlined,
            label: 'Спа',
            selected: true,
            onTap: () {},
          ),
        ),
      );

      final Semantics sem = tester.widget<Semantics>(
        find
            .descendant(
              of: find.byType(ServiceTypeTile),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(sem.properties.button, isTrue);
      expect(sem.properties.selected, isTrue);
    });
  });

  group('ServiceTypeTile — interaction', () {
    testWidgets('tapping fires onTap exactly once', (tester) async {
      int taps = 0;
      await tester.pumpWidget(
        _host(
          ServiceTypeTile(
            icon: Icons.spa_outlined,
            label: 'Спа',
            selected: false,
            onTap: () => taps++,
          ),
        ),
      );

      await tester.tap(find.byType(ServiceTypeTile));
      await tester.pump();

      expect(taps, 1);
    });
  });
}
