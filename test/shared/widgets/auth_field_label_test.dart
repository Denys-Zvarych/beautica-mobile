// Widget tests for AuthFieldLabel — Phase 2.x (visual polish).
//
// AuthFieldLabel is a shared primitive used on both login and register screens.
// These tests pin its text transformation, font size, letter spacing, and the
// required 6 px gap below the label.

import 'package:beautica_mobile/shared/widgets/auth_field_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(String text) =>
      MaterialApp(home: Scaffold(body: AuthFieldLabel(text)));

  group('AuthFieldLabel', () {
    testWidgets('1. renders text in uppercase', (tester) async {
      await tester.pumpWidget(wrap('email'));
      await tester.pumpAndSettle();

      expect(find.text('EMAIL'), findsOneWidget);
      expect(find.text('email'), findsNothing);
    });

    testWidgets('2. passes through already-uppercase text unchanged', (
      tester,
    ) async {
      await tester.pumpWidget(wrap('PASSWORD'));
      await tester.pumpAndSettle();

      expect(find.text('PASSWORD'), findsOneWidget);
    });

    testWidgets('3. applies fontSize 13 to the label text', (tester) async {
      await tester.pumpWidget(wrap('email'));
      await tester.pumpAndSettle();

      final text = tester.widget<Text>(find.text('EMAIL'));
      expect(text.style?.fontSize, equals(13.0));
    });

    testWidgets('4. applies letterSpacing 0.91 to the label text', (
      tester,
    ) async {
      await tester.pumpWidget(wrap('email'));
      await tester.pumpAndSettle();

      final text = tester.widget<Text>(find.text('EMAIL'));
      expect(text.style?.letterSpacing, equals(0.91));
    });

    testWidgets('5. includes a 6 px SizedBox gap below the label', (
      tester,
    ) async {
      await tester.pumpWidget(wrap('email'));
      await tester.pumpAndSettle();

      final sizedBoxes = tester
          .widgetList<SizedBox>(
            find.descendant(
              of: find.byType(AuthFieldLabel),
              matching: find.byType(SizedBox),
            ),
          )
          .toList();

      expect(
        sizedBoxes.any((sb) => sb.height == 6),
        isTrue,
        reason:
            'AuthFieldLabel must include a 6 px SizedBox gap below the text',
      );
    });
  });
}
