// Phase 2.5 — Pure-Dart unit tests for validateEmail().
//
// No widget pump needed. A minimal _FakeL10n supplies hardcoded strings so the
// validator can be exercised without spinning up a Flutter widget tree.
//
// Covered scenarios:
//   1. null input    → errEmailRequired
//   2. empty string  → errEmailRequired
//   3. missing @     → errEmailInvalid
//   4. 256-char addr → errEmailTooLong
//   5. valid address → null
//   6. valid at max length (255 chars) → null

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/validators/email_validator.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake l10n — hardcoded strings avoid a widget tree in pure unit tests.
// ---------------------------------------------------------------------------

final class _FakeL10n extends Fake implements AppLocalizations {
  @override
  String get errEmailRequired => 'required';

  @override
  String get errEmailInvalid => 'invalid';

  @override
  String get errEmailTooLong => 'too long';
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  final l10n = _FakeL10n();

  group('validateEmail', () {
    test('returns errEmailRequired for null', () {
      expect(validateEmail(null, l10n), equals('required'));
    });

    test('returns errEmailRequired for empty string', () {
      expect(validateEmail('', l10n), equals('required'));
    });

    test('returns errEmailInvalid for missing @ symbol', () {
      expect(validateEmail('notanemail', l10n), equals('invalid'));
    });

    test('returns errEmailTooLong for 256-char string', () {
      // 249 'a' chars + '@b.com' (6 chars) = 255 — still valid,
      // so we need 250 + '@b.com' = 256 chars to trigger the length guard.
      final longEmail = '${'a' * 250}@b.com';
      expect(longEmail.length, equals(256));
      expect(validateEmail(longEmail, l10n), equals('too long'));
    });

    test('returns null for valid email', () {
      expect(validateEmail('user@example.com', l10n), isNull);
    });

    test('returns null for valid email at max length (255 chars)', () {
      // 248 'a' chars + '@b.com' (6 chars) = 254 — one under the guard,
      // so use 249 + '@b.com' = 255 chars to hit the exact boundary.
      final maxEmail = '${'a' * 249}@b.com';
      expect(maxEmail.length, equals(255));
      expect(validateEmail(maxEmail, l10n), isNull);
    });
  });
}
