// Phase 2.17 — Pure-Dart unit tests for validatePhone().
//
// No widget pump needed. A minimal _FakeL10n supplies hardcoded strings so the
// validator can be exercised without spinning up a Flutter widget tree.
//
// Covered scenarios (6 branches):
//   1. null input                  → errPhoneInvalid
//   2. empty / whitespace string   → errPhoneInvalid
//   3. valid +380 + 9 digits       → null
//   4. valid space-formatted +380  → null
//   5. invalid (too few digits)    → errPhoneInvalid
//   6. invalid (too many digits)   → errPhoneInvalid
//   7. non-digit characters        → errPhoneInvalid
//   8. paste-guard: startsWith('38') && !startsWith('380') → errPhoneInvalid
//   9. valid 380-prefix (no '+')   → null
//  10. valid local 0XX format      → null

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/validators/phone_validator.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake l10n — hardcoded strings avoid a widget tree in pure unit tests.
// ---------------------------------------------------------------------------

final class _FakeL10n extends Fake implements AppLocalizations {
  @override
  String get errPhoneInvalid => 'invalid_phone';
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  final l10n = _FakeL10n();

  group('validatePhone', () {
    // Branch 1 — null
    test('returns errPhoneInvalid for null', () {
      expect(validatePhone(null, l10n), equals('invalid_phone'));
    });

    // Branch 2 — empty / whitespace
    test('returns errPhoneInvalid for empty string', () {
      expect(validatePhone('', l10n), equals('invalid_phone'));
    });

    test('returns errPhoneInvalid for whitespace-only string', () {
      expect(validatePhone('   ', l10n), equals('invalid_phone'));
    });

    // Branch 3 — valid +380 compact
    test('returns null for valid +380 + 9-digit compact number', () {
      expect(validatePhone('+380501111111', l10n), isNull);
    });

    // Branch 4 — valid space-formatted +380
    test('returns null for valid +380 XX XXX XXXX format', () {
      expect(validatePhone('+380 50 111 1111', l10n), isNull);
    });

    // Branch 5 — too few digits
    test(
      'returns errPhoneInvalid for too-few digits (8 subscriber digits)',
      () {
        // +380 + 8 digits = subscriber 8 chars (not 9) → invalid
        expect(validatePhone('+38050123456', l10n), equals('invalid_phone'));
      },
    );

    // Branch 5 cont. — bare "123" (only 3 digits)
    test('returns errPhoneInvalid for very short number', () {
      expect(validatePhone('123', l10n), equals('invalid_phone'));
    });

    // Branch 6 — too many digits
    test(
      'returns errPhoneInvalid for too-many digits (10 subscriber digits)',
      () {
        // +380 + 10 digits = subscriber 10 chars (not 9) → invalid
        expect(validatePhone('+3805012345678', l10n), equals('invalid_phone'));
      },
    );

    // Branch 7 — non-digit characters inside the number
    test('returns errPhoneInvalid for number containing letters', () {
      expect(validatePhone('+380ABC123456', l10n), equals('invalid_phone'));
    });

    // Branch 8 — paste-guard: "38" prefix without the "0"
    test('returns errPhoneInvalid for 38-prefixed number without leading 0 '
        '(paste-guard edge case)', () {
      // "38501234567" starts with "38" but NOT "380" → rejected
      expect(validatePhone('38501234567', l10n), equals('invalid_phone'));
    });

    // Branch 8 cont. — bare "38" paste (no "0", no subscriber digits)
    test('returns errPhoneInvalid for bare "38" prefix '
        '(paste-guard against "338..." bug)', () {
      // "38" hits startsWith('38') && !startsWith('380') → rejected early,
      // not treated as a bare subscriber number.
      expect(validatePhone('38', l10n), equals('invalid_phone'));
    });

    // Branch 9 — valid 380-prefix without '+'
    test('returns null for 380-prefixed number without leading +', () {
      expect(validatePhone('380501111111', l10n), isNull);
    });

    // Branch 10 — valid local 0XX format (10 digits starting with 0)
    test('returns null for local 0XX format (10 digits, leading 0)', () {
      expect(validatePhone('0501111111', l10n), isNull);
    });

    // Branch 10 cont. — local format with spaces
    test('returns null for local 0XX format with spaces', () {
      expect(validatePhone('050 111 1111', l10n), isNull);
    });
  });
}
