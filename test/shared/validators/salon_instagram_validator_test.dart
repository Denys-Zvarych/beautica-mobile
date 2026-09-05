// Phase 21.3 QA follow-up — pure-Dart unit tests for
// validateSalonInstagram().
//
// Direct coverage was missing entirely — see `salon_phone_validator_test
// .dart`'s identical header note; this validator had the same gap (only
// exercised transitively through `RegisterSalonScreen`'s/
// `SalonContactsEditScreen`'s own widget tests).
//
// Covered scenarios:
//   1. null                                    → null (optional)
//   2. empty string                            → null (optional)
//   3. whitespace-only string                  → null (optional)
//   4. bare handle (no @)                      → null
//   5. @-prefixed handle                       → null
//   6. handle at the 30-char cap                → null
//   7. handle exceeding the 30-char cap         → errInstagram
//   8. full instagram.com URL                   → null
//   9. www.instagram.com URL                    → null
//  10. instagram.com URL with trailing slash    → null
//  11. a garbage URL (wrong host)               → errInstagram
//  12. a handle with a disallowed character (space) → errInstagram
//  13. leading/trailing whitespace is trimmed before validating

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/validators/salon_instagram_validator.dart';
import 'package:flutter_test/flutter_test.dart';

final class _FakeL10n extends Fake implements AppLocalizations {
  @override
  String get masterEditInstagramError => 'instagram_invalid';
}

void main() {
  final l10n = _FakeL10n();

  group('validateSalonInstagram', () {
    test('returns null for null (optional field)', () {
      expect(validateSalonInstagram(null, l10n), isNull);
    });

    test('returns null for empty string (optional field)', () {
      expect(validateSalonInstagram('', l10n), isNull);
    });

    test('returns null for whitespace-only string (optional field)', () {
      expect(validateSalonInstagram('   ', l10n), isNull);
    });

    test('returns null for a bare handle with no @', () {
      expect(validateSalonInstagram('velvet_salon', l10n), isNull);
    });

    test('returns null for an @-prefixed handle', () {
      expect(validateSalonInstagram('@velvet_salon', l10n), isNull);
    });

    test('returns null for a handle at the 30-char cap', () {
      final String thirtyChars = 'a' * 30;
      expect(validateSalonInstagram(thirtyChars, l10n), isNull);
    });

    test(
      'returns instagram_invalid for a handle exceeding the 30-char cap',
      () {
        final String thirtyOneChars = 'a' * 31;
        expect(
          validateSalonInstagram(thirtyOneChars, l10n),
          equals('instagram_invalid'),
        );
      },
    );

    test('returns null for a full instagram.com URL', () {
      expect(
        validateSalonInstagram('https://instagram.com/velvet_salon', l10n),
        isNull,
      );
    });

    test('returns null for a www.instagram.com URL', () {
      expect(
        validateSalonInstagram('https://www.instagram.com/velvet_salon', l10n),
        isNull,
      );
    });

    test('returns null for an instagram.com URL with a trailing slash', () {
      expect(
        validateSalonInstagram('https://instagram.com/velvet_salon/', l10n),
        isNull,
      );
    });

    test('returns instagram_invalid for a garbage/wrong-host URL', () {
      expect(
        validateSalonInstagram('https://evil.example.com/velvet_salon', l10n),
        equals('instagram_invalid'),
      );
    });

    test('returns instagram_invalid for a handle containing a space', () {
      expect(
        validateSalonInstagram('velvet salon', l10n),
        equals('instagram_invalid'),
      );
    });

    test('trims surrounding whitespace before validating', () {
      expect(validateSalonInstagram('  velvet_salon  ', l10n), isNull);
    });
  });
}
