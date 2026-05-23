// Phase 2.16 — Unit + widget tests for [PasswordChecklist] and the
// [passwordRules] factory.
//
// Covered scenarios:
//   1. passwordRules() returns exactly 3 rules (max-128 rule was removed in
//      Phase 2.16; the factory must NOT contain a 4th "≤ 128 chars" row).
//   2. passwordRules() rule labels match the expected Ukrainian strings.
//   3. PasswordChecklist renders one row per rule (3 rows for the default
//      8-char minimum factory).
//   4. An empty string shows all 3 rows in the unmet state
//      (radio_button_unchecked icon for each).
//   5. "Abcde123" satisfies all three rules → all 3 rows show
//      check_circle_rounded.
//   6. "abcde123" (no uppercase) → only the uppercase rule row is unmet.
//   7. "ABCDEFGH" (no digit) → only the digit rule row is unmet.
//   8. passwordRules(minLength: 12) returns 3 rules with updated label.

import 'package:beautica_mobile/features/auth/presentation/widgets/password_checklist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // -------------------------------------------------------------------------
  // passwordRules() factory — rule count and label regression tests
  // -------------------------------------------------------------------------

  group('passwordRules factory', () {
    test('1. returns exactly 3 rules (max-128 rule removed in Phase 2.16)', () {
      final rules = passwordRules();
      expect(
        rules,
        hasLength(3),
        reason:
            'passwordRules() must return exactly 3 rules: min-length, '
            'has-digit, has-uppercase. The old "≤ 128 chars" (max-bound) '
            'rule was removed in Phase 2.16 — it is enforced by maxLength '
            'on the TextField, not as a live checklist row.',
      );
    });

    test('2. rule labels match expected Ukrainian strings (min 8)', () {
      final rules = passwordRules();
      // Rule 0 — min length
      expect(rules[0].label, equals('Щонайменше 8 символів'));
      // Rule 1 — digit
      expect(rules[1].label, equals('Хоча б одна цифра'));
      // Rule 2 — uppercase
      expect(rules[2].label, equals('Хоча б одна велика літера'));
    });

    test('3. no rule label contains "128" (max-bound row must be absent)', () {
      final rules = passwordRules();
      for (final rule in rules) {
        expect(
          rule.label.contains('128'),
          isFalse,
          reason:
              'The "max 128 chars" label must not appear in the live '
              'checklist — it was removed in Phase 2.16.',
        );
      }
    });

    test(
      '4. passwordRules(minLength: 12) returns 3 rules with updated label',
      () {
        final rules = passwordRules(minLength: 12);
        expect(rules, hasLength(3));
        expect(rules[0].label, equals('Щонайменше 12 символів'));
      },
    );
  });

  // -------------------------------------------------------------------------
  // PasswordRule predicates — direct unit coverage
  // -------------------------------------------------------------------------

  group('PasswordRule predicates', () {
    final rules = passwordRules();
    final minRule = rules[0];
    final digitRule = rules[1];
    final upperRule = rules[2];

    test('5. min-length rule: "abcde123" (8 chars) passes', () {
      expect(minRule.test('abcde123'), isTrue);
    });

    test('6. min-length rule: "abc1" (4 chars) fails', () {
      expect(minRule.test('abc1'), isFalse);
    });

    test('7. digit rule: "Abcdefg1" passes', () {
      expect(digitRule.test('Abcdefg1'), isTrue);
    });

    test('8. digit rule: "Abcdefgh" (no digit) fails', () {
      expect(digitRule.test('Abcdefgh'), isFalse);
    });

    test('9. uppercase rule: "Abcde123" passes', () {
      expect(upperRule.test('Abcde123'), isTrue);
    });

    test('10. uppercase rule: "abcde123" (no uppercase) fails', () {
      expect(upperRule.test('abcde123'), isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // PasswordChecklist widget — rendered states
  // -------------------------------------------------------------------------

  group('PasswordChecklist widget', () {
    testWidgets('11. renders exactly 3 rows for the default 8-char factory', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(PasswordChecklist(value: '', rules: passwordRules())),
      );

      // Each row is a _RuleRow which renders one AnimatedSwitcher per row.
      // Since the widget is private we count via Icon subtypes.
      // All 3 rows unmet → 3 radio_button_unchecked icons.
      expect(find.byIcon(Icons.radio_button_unchecked), findsNWidgets(3));
    });

    testWidgets('12. empty string → all 3 rows show unmet icon '
        '(radio_button_unchecked)', (tester) async {
      await tester.pumpWidget(
        _wrap(PasswordChecklist(value: '', rules: passwordRules())),
      );

      expect(find.byIcon(Icons.radio_button_unchecked), findsNWidgets(3));
      expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
    });

    testWidgets('13. "Abcde123" satisfies all 3 rules → all rows show '
        'check_circle_rounded', (tester) async {
      await tester.pumpWidget(
        _wrap(PasswordChecklist(value: 'Abcde123', rules: passwordRules())),
      );
      await tester.pumpAndSettle(); // allow AnimatedSwitcher to settle

      expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(3));
      expect(find.byIcon(Icons.radio_button_unchecked), findsNothing);
    });

    testWidgets(
      '14. "abcde123" (no uppercase) → 2 met, 1 unmet (uppercase row fails)',
      (tester) async {
        await tester.pumpWidget(
          _wrap(PasswordChecklist(value: 'abcde123', rules: passwordRules())),
        );
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(2));
        expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
      },
    );

    testWidgets(
      '15. "ABCDEFGH" (no digit) → 2 met, 1 unmet (digit row fails)',
      (tester) async {
        await tester.pumpWidget(
          _wrap(PasswordChecklist(value: 'ABCDEFGH', rules: passwordRules())),
        );
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(2));
        expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
      },
    );
  });
}
