// Phase 2.6 — Pure-Dart unit tests for validateName().
//
// No widget pump needed. A minimal _FakeL10n supplies hardcoded strings so the
// validator can be exercised without spinning up a Flutter widget tree.
//
// Covered scenarios:
//   1. null input              → errNameRequired
//   2. whitespace-only string  → errNameRequired  (trim rule)
//   3. 101-char string         → errNameTooLong   (one beyond the 100-char cap)
//   4. 100-char string         → null             (maximum valid length)
//   5. typical name            → null
//
// Step 2.7 Rule 3 — no-digit name guard (mirrors backend @NoDigits). Covers
// nameContainsDigit() across scripts and validateName()'s digit layer + its
// precedence (required / too-long fire BEFORE the digit check).

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/validators/name_validator.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake l10n — hardcoded strings avoid a widget tree in pure unit tests.
// ---------------------------------------------------------------------------

final class _FakeL10n extends Fake implements AppLocalizations {
  @override
  String get errNameRequired => 'required';

  @override
  String get errNameTooLong => 'too long';

  @override
  String get errNameHasDigit => 'has digit';
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  final l10n = _FakeL10n();

  group('validateName', () {
    test('returns errNameRequired for null', () {
      expect(validateName(null, l10n), equals('required'));
    });

    test('returns errNameRequired for whitespace-only string', () {
      expect(validateName('   ', l10n), equals('required'));
    });

    test('returns errNameTooLong for 101-char string', () {
      expect(validateName('a' * 101, l10n), equals('too long'));
    });

    test('returns null for valid name at max length (100 chars)', () {
      expect(validateName('a' * 100, l10n), isNull);
    });

    test('returns null for typical name', () {
      expect(validateName('Іван', l10n), isNull);
    });

    // ── Step 2.7 Rule 3 — digit guard via validateName ────────────────────
    test('returns errNameHasDigit for a name with a trailing ASCII digit', () {
      expect(validateName('John2', l10n), equals('has digit'));
    });

    test('returns errNameHasDigit for a single ASCII digit', () {
      expect(validateName('4', l10n), equals('has digit'));
    });

    test('returns errNameHasDigit for a digit in the middle of a name', () {
      expect(validateName('a1b', l10n), equals('has digit'));
    });

    test('returns errNameHasDigit for an Arabic-Indic digit (٤)', () {
      expect(validateName('٤', l10n), equals('has digit'));
    });

    test('returns errNameHasDigit for a Devanagari digit (९)', () {
      expect(validateName('९', l10n), equals('has digit'));
    });

    test('returns null for names with hyphen / apostrophe / space', () {
      expect(validateName("O'Brien", l10n), isNull);
      expect(validateName('Anne-Marie', l10n), isNull);
      expect(validateName('Mary Jane', l10n), isNull);
      expect(validateName('John', l10n), isNull);
      expect(validateName('Петренко-Сидоренко', l10n), isNull);
    });

    // ── Precedence: required / too-long fire BEFORE the digit check ─────────
    test('null wins over the digit check (required, not has-digit)', () {
      expect(validateName(null, l10n), equals('required'));
    });

    test('whitespace-only wins over the digit check (required)', () {
      // The trimmed value is empty, so the required rule fires first even
      // though no digit is present.
      expect(validateName('   ', l10n), equals('required'));
    });

    test('too-long wins over the digit check when a digit is also present', () {
      // 101 chars AND a digit → the length rule is layered before the digit
      // rule, so errNameTooLong must be returned, not errNameHasDigit.
      expect(validateName('${'a' * 100}1', l10n), equals('too long'));
    });
  });

  // ── nameContainsDigit — the raw predicate used by inline screen validators ─
  group('nameContainsDigit', () {
    test('true for ASCII digits anywhere in the string', () {
      expect(nameContainsDigit('John2'), isTrue);
      expect(nameContainsDigit('4'), isTrue);
      expect(nameContainsDigit('a1b'), isTrue);
    });

    test('true for non-ASCII Unicode decimal digits', () {
      expect(nameContainsDigit('٤'), isTrue); // Arabic-Indic
      expect(nameContainsDigit('९'), isTrue); // Devanagari
    });

    test('false for digit-free names across scripts and separators', () {
      expect(nameContainsDigit('John'), isFalse);
      expect(nameContainsDigit("O'Brien"), isFalse);
      expect(nameContainsDigit('Anne-Marie'), isFalse);
      expect(nameContainsDigit('Mary Jane'), isFalse);
      expect(nameContainsDigit('Іван'), isFalse);
      expect(nameContainsDigit('Петренко-Сидоренко'), isFalse);
    });
  });
}
