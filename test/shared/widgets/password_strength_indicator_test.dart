// Tests for PasswordStrengthIndicator widget and evaluatePasswordStrength().
//
// The unit tests cover the pure function in isolation (no widget tree needed).
// The widget tests wrap PasswordStrengthIndicator in a minimal MaterialApp that
// supplies AppLocalizations so the strength label Text widgets are resolvable.
//
// Strength rules (from widget source):
//   Weak:   empty, OR length < 8, OR only one character class.
//   Medium: length ≥ 8 AND ≥ 2 character classes.
//   Strong: length ≥ 8 AND ≥ 3 character classes AND ≥ 1 special character.
//
// Character classes: uppercase [A-Z], lowercase [a-z], digit [\d], special [^A-Za-z\d].

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/password_strength_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Widget wrapper
// ---------------------------------------------------------------------------

Widget _wrap(String password) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('uk'),
  home: Scaffold(body: PasswordStrengthIndicator(password: password)),
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // -------------------------------------------------------------------------
  // Unit tests — evaluatePasswordStrength()
  // -------------------------------------------------------------------------

  group('evaluatePasswordStrength()', () {
    // -----------------------------------------------------------------------
    // Test U1 — empty string → weak
    // -----------------------------------------------------------------------
    test('empty string → weak', () {
      expect(evaluatePasswordStrength(''), equals(PasswordStrength.weak));
    });

    // -----------------------------------------------------------------------
    // Test U2 — 7 chars, all lowercase → weak (length < 8)
    // -----------------------------------------------------------------------
    test('7-char all-lowercase → weak (length < 8 forces weak)', () {
      expect(
        evaluatePasswordStrength('abcdefg'),
        equals(PasswordStrength.weak),
      );
    });

    // -----------------------------------------------------------------------
    // Test U3 — 8 chars, single class (all lowercase) → weak
    // -----------------------------------------------------------------------
    test('8-char single class (lowercase only) → weak', () {
      expect(
        evaluatePasswordStrength('abcdefgh'),
        equals(PasswordStrength.weak),
      );
    });

    // -----------------------------------------------------------------------
    // Test U4 — 8 chars, exactly 2 classes (lowercase + digit) → medium
    // -----------------------------------------------------------------------
    test('8-char two classes (lowercase + digit) → medium', () {
      // 'abcdefg1' — 7 lowercase + 1 digit = 2 classes, length == 8.
      expect(
        evaluatePasswordStrength('abcdefg1'),
        equals(PasswordStrength.medium),
      );
    });

    // -----------------------------------------------------------------------
    // Test U5 — 8 chars, uppercase + lowercase only → medium
    // -----------------------------------------------------------------------
    test('8-char two classes (uppercase + lowercase) → medium', () {
      // 'Abcdefgh' — 1 uppercase + 7 lowercase = 2 classes, no special.
      expect(
        evaluatePasswordStrength('Abcdefgh'),
        equals(PasswordStrength.medium),
      );
    });

    // -----------------------------------------------------------------------
    // Test U6 — 8 chars, 3 classes (upper + lower + digit), no special → medium
    // -----------------------------------------------------------------------
    test('8-char three classes but no special char → medium (not strong)', () {
      // 'Abcdef1g' — upper + lower + digit = 3 classes, no special char.
      // Strong requires ≥ 3 classes AND ≥ 1 special — the missing special
      // character keeps it at medium.
      expect(
        evaluatePasswordStrength('Abcdef1g'),
        equals(PasswordStrength.medium),
      );
    });

    // -----------------------------------------------------------------------
    // Test U7 — 8 chars, 3 classes + special char → strong
    // -----------------------------------------------------------------------
    test('8-char three classes + special char → strong', () {
      // 'Abcdef1!' — upper + lower + digit + special = 4 classes.
      expect(
        evaluatePasswordStrength('Abcdef1!'),
        equals(PasswordStrength.strong),
      );
    });

    // -----------------------------------------------------------------------
    // Test U8 — long password with all 4 classes → strong
    // -----------------------------------------------------------------------
    test('long password with all 4 classes → strong', () {
      expect(
        evaluatePasswordStrength('MyP@ssw0rdIsVeryLong!'),
        equals(PasswordStrength.strong),
      );
    });

    // -----------------------------------------------------------------------
    // Test U9 — 3 special chars only, length < 8 → weak
    // -----------------------------------------------------------------------
    test('three special chars only, length < 8 → weak', () {
      // '!@#' — 3 chars, single class (special). Length < 8 forces weak.
      expect(evaluatePasswordStrength('!@#'), equals(PasswordStrength.weak));
    });
  });

  // -------------------------------------------------------------------------
  // Widget tests — PasswordStrengthIndicator
  // -------------------------------------------------------------------------

  group('PasswordStrengthIndicator widget', () {
    // -----------------------------------------------------------------------
    // Test W1 — empty password renders nothing (SizedBox.shrink)
    // -----------------------------------------------------------------------
    testWidgets('empty password renders SizedBox.shrink (no label visible)', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(''));
      await tester.pumpAndSettle();

      final l10n = lookupAppLocalizations(const Locale('uk'));

      // No strength label should be present in the tree.
      expect(find.text(l10n.passwordStrengthWeak), findsNothing);
      expect(find.text(l10n.passwordStrengthMedium), findsNothing);
      expect(find.text(l10n.passwordStrengthStrong), findsNothing);
    });

    // -----------------------------------------------------------------------
    // Test W2 — weak password renders the weak label
    // -----------------------------------------------------------------------
    testWidgets('weak password renders weak label', (tester) async {
      // 'abcdefg' — 7 chars, single class → weak.
      await tester.pumpWidget(_wrap('abcdefg'));
      await tester.pumpAndSettle();

      final l10n = lookupAppLocalizations(const Locale('uk'));
      expect(find.text(l10n.passwordStrengthWeak), findsOneWidget);
      expect(find.text(l10n.passwordStrengthMedium), findsNothing);
      expect(find.text(l10n.passwordStrengthStrong), findsNothing);
    });

    // -----------------------------------------------------------------------
    // Test W3 — medium password renders the medium label
    // -----------------------------------------------------------------------
    testWidgets('medium password renders medium label', (tester) async {
      // 'abcdefg1' — 8 chars, lowercase + digit = 2 classes, no special → medium.
      await tester.pumpWidget(_wrap('abcdefg1'));
      await tester.pumpAndSettle();

      final l10n = lookupAppLocalizations(const Locale('uk'));
      expect(find.text(l10n.passwordStrengthMedium), findsOneWidget);
      expect(find.text(l10n.passwordStrengthWeak), findsNothing);
      expect(find.text(l10n.passwordStrengthStrong), findsNothing);
    });

    // -----------------------------------------------------------------------
    // Test W4 — strong password renders the strong label
    // -----------------------------------------------------------------------
    testWidgets('strong password renders strong label', (tester) async {
      // 'Abcdef1!' — 8 chars, upper + lower + digit + special = 4 classes → strong.
      await tester.pumpWidget(_wrap('Abcdef1!'));
      await tester.pumpAndSettle();

      final l10n = lookupAppLocalizations(const Locale('uk'));
      expect(find.text(l10n.passwordStrengthStrong), findsOneWidget);
      expect(find.text(l10n.passwordStrengthWeak), findsNothing);
      expect(find.text(l10n.passwordStrengthMedium), findsNothing);
    });
  });
}
