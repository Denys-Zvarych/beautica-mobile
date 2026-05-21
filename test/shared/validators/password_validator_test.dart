// Phase 2.5 — Pure-Dart unit tests for validatePassword() and
// validateNewPassword().
//
// No widget pump needed. A minimal _FakeL10n supplies hardcoded strings so the
// validators can be exercised without spinning up a Flutter widget tree.
//
// validatePassword (LENIENT — login path) covered scenarios:
//   1. null input      → errPasswordRequired
//   2. empty string    → errPasswordRequired
//   3. 129-char string → errPasswordLength  (one beyond the 128-char cap)
//   4. 1-char string   → null              (minimum valid for login)
//   5. 128-char string → null              (maximum valid length)
//   6. "asd"           → null              (short passwords still accepted at login)
//   7. "abc"           → null              (no-uppercase short value still accepted)
//
// validateNewPassword (STRICT — registration path) covered scenarios:
//   8.  null input                → errPasswordRequired
//   9.  empty string              → errPasswordRequired
//   10. "asd" (3 chars)           → errPasswordTooShort
//   11. "abcdefg1" (8 chars, no uppercase) → errPasswordNoUppercase
//       (checks length OK, digit OK, uppercase FAIL)
//   12. "ABCDEFGH" (8 chars, no digit)     → errPasswordNoDigit
//   13. 129-char string           → errPasswordLength
//   14. "Abcde123" (valid)        → null
//   15. "Abcdefg1" (valid)        → null  (exact-8 boundary)
//   16. 128-char string with digit + uppercase → null (maximum valid)
//
// The login / registration split is locked by tests 6-7 vs 10-15 so that
// neither validator accidentally regresses the other.

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/validators/password_validator.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake l10n — hardcoded strings avoid a widget tree in pure unit tests.
// ---------------------------------------------------------------------------

final class _FakeL10n extends Fake implements AppLocalizations {
  @override
  String get errPasswordRequired => 'required';

  @override
  String get errPasswordLength => 'length';

  @override
  String get errPasswordTooShort => 'too_short';

  @override
  String get errPasswordNoDigit => 'no_digit';

  @override
  String get errPasswordNoUppercase => 'no_uppercase';
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  final l10n = _FakeL10n();

  // -------------------------------------------------------------------------
  // validatePassword — lenient, used by the LOGIN screen.
  // -------------------------------------------------------------------------

  group('validatePassword (login — lenient)', () {
    test('1. returns errPasswordRequired for null', () {
      expect(validatePassword(null, l10n), equals('required'));
    });

    test('2. returns errPasswordRequired for empty string', () {
      expect(validatePassword('', l10n), equals('required'));
    });

    test('3. returns errPasswordLength for 129-char string', () {
      expect(validatePassword('a' * 129, l10n), equals('length'));
    });

    test('4. returns null for 1-char string (login minimum)', () {
      expect(validatePassword('a', l10n), isNull);
    });

    test('5. returns null for 128-char string (login maximum)', () {
      expect(validatePassword('a' * 128, l10n), isNull);
    });

    // Lock-in: short passwords must remain valid at login so users whose
    // existing passwords predate the strength rule can still sign in.

    test(
      '6. returns null for "asd" (3 chars, all lowercase — still valid at login)',
      () {
        expect(validatePassword('asd', l10n), isNull);
      },
    );

    test(
      '7. returns null for short no-uppercase value "abc" (valid at login)',
      () {
        expect(validatePassword('abc', l10n), isNull);
      },
    );
  });

  // -------------------------------------------------------------------------
  // validateNewPassword — strict, used by the REGISTRATION password field.
  // -------------------------------------------------------------------------

  group('validateNewPassword (registration — strict)', () {
    test('8. returns errPasswordRequired for null', () {
      expect(validateNewPassword(null, l10n), equals('required'));
    });

    test('9. returns errPasswordRequired for empty string', () {
      expect(validateNewPassword('', l10n), equals('required'));
    });

    test('10. returns errPasswordTooShort for "asd" (3 chars)', () {
      expect(validateNewPassword('asd', l10n), equals('too_short'));
    });

    test(
      '11. returns errPasswordNoDigit for 8-char all-alpha value (no digit)',
      () {
        // 8 chars, has uppercase — but no digit.
        expect(validateNewPassword('Abcdefgh', l10n), equals('no_digit'));
      },
    );

    test(
      '12. returns errPasswordNoUppercase for 8-char value with digit but no uppercase',
      () {
        // 8 chars, has digit — but no uppercase letter.
        expect(validateNewPassword('abcdefg1', l10n), equals('no_uppercase'));
      },
    );

    test('13. returns errPasswordLength for 129-char string', () {
      // Build a 129-char string that would otherwise pass digit + uppercase
      // checks so length is the only failing rule.
      final long = 'A1${'a' * 127}'; // 129 chars total
      expect(validateNewPassword(long, l10n), equals('length'));
    });

    test('14. returns null for valid password "Abcde123"', () {
      expect(validateNewPassword('Abcde123', l10n), isNull);
    });

    test('15. returns null for exact-8-char valid password "Abcdefg1"', () {
      // Exactly 8 chars — boundary of the minimum length rule.
      expect(validateNewPassword('Abcdefg1', l10n), isNull);
    });

    test('16. returns null for 128-char valid password (maximum boundary)', () {
      // 128 chars: starts with 'A1' so digit + uppercase checks pass.
      final maxValid = 'A1${'a' * 126}'; // 128 chars total
      expect(validateNewPassword(maxValid, l10n), isNull);
    });

    // Rule-order lock-in: null/empty always fires before too-short.
    test('17. rule order — empty returns required, not too_short', () {
      expect(validateNewPassword('', l10n), equals('required'));
    });

    // Rule-order lock-in: too-short fires before digit/uppercase checks.
    test(
      '18. rule order — 3-char no-digit no-uppercase returns too_short, not no_digit',
      () {
        expect(validateNewPassword('asd', l10n), equals('too_short'));
      },
    );

    // Rule-order lock-in: too-short fires before the length-cap check.
    // (A 3-char value cannot also exceed 128, but the ordering is verified
    // by the fact that too_short fires for 3-char regardless of other rules.)
    test('19. rule order — digit check precedes uppercase check', () {
      // 8 chars, no digit, no uppercase — digit rule should fire first.
      expect(validateNewPassword('abcdefgh', l10n), equals('no_digit'));
    });
  });
}
