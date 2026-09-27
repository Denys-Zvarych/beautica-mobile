// Phase 21.3 QA follow-up — pure-Dart unit tests for validateSalonPhone().
//
// Direct coverage was missing entirely: `validateSalonPhone` was previously
// exercised ONLY transitively, through `RegisterSalonScreen`'s and
// `SalonContactsEditScreen`'s own widget-tier tests (which only drive a
// handful of shapes each screen happens to need for its OWN scenarios, never
// the validator's boundary conditions as a unit). This file is the
// dedicated unit suite the spec's "Every form validator... boundary inputs"
// rule requires, mirroring `salon_name_validator_test.dart`'s own
// `_FakeL10n` pattern.
//
// Covered scenarios:
//   1. null                                  → errPhoneRequired
//   2. empty string                          → errPhoneRequired
//   3. whitespace-only string                → errPhoneRequired
//   4. 20-char string (max valid length)     → null
//   5. 21-char string (exceeds max)          → errPhoneTooLongEdit
//   6. allowed-charset string                → null
//   7. disallowed character (letter)         → errPhoneInvalidEdit
//   8. a UA-formatted phone with spaces      → null (allowed charset)
//   9. leading/trailing whitespace is trimmed before length/charset checks

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/validators/salon_phone_validator.dart';
import 'package:flutter_test/flutter_test.dart';

final class _FakeL10n extends Fake implements AppLocalizations {
  @override
  String get errPhoneRequired => 'phone_required';

  @override
  String get errPhoneTooLongEdit => 'phone_too_long';

  @override
  String get errPhoneInvalidEdit => 'phone_invalid';
}

void main() {
  final l10n = _FakeL10n();

  group('validateSalonPhone', () {
    test('returns errPhoneRequired for null', () {
      expect(validateSalonPhone(null, l10n), equals('phone_required'));
    });

    test('returns errPhoneRequired for empty string', () {
      expect(validateSalonPhone('', l10n), equals('phone_required'));
    });

    test('returns errPhoneRequired for whitespace-only string', () {
      expect(validateSalonPhone('   ', l10n), equals('phone_required'));
    });

    test('returns null for a 20-char string (maximum valid length)', () {
      // '+' + 19 digits = 20 chars, all within the allowed charset.
      final String twentyChars = '+${'1' * 19}';
      expect(twentyChars.length, 20);
      expect(validateSalonPhone(twentyChars, l10n), isNull);
    });

    test('returns errPhoneTooLongEdit for a 21-char string (exceeds max)', () {
      final String twentyOneChars = '+${'1' * 20}';
      expect(twentyOneChars.length, 21);
      expect(
        validateSalonPhone(twentyOneChars, l10n),
        equals('phone_too_long'),
      );
    });

    test('returns null for a UA-formatted phone with spaces/parens/dashes', () {
      expect(validateSalonPhone('+380 (50) 123-45-67', l10n), isNull);
    });

    test('returns errPhoneInvalidEdit for an embedded letter', () {
      expect(
        validateSalonPhone('+380501234a67', l10n),
        equals('phone_invalid'),
      );
    });

    test('trims surrounding whitespace before validating', () {
      expect(validateSalonPhone('  +380501234567  ', l10n), isNull);
    });
  });
}
