// Phase 2.5 — Pure-Dart unit tests for validatePassword().
//
// No widget pump needed. A minimal _FakeL10n supplies hardcoded strings so the
// validator can be exercised without spinning up a Flutter widget tree.
//
// Covered scenarios:
//   1. null input      → errPasswordRequired
//   2. empty string    → errPasswordRequired
//   3. 129-char string → errPasswordLength  (one beyond the 128-char cap)
//   4. 1-char string   → null              (minimum valid length)
//   5. 128-char string → null              (maximum valid length)

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
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  final l10n = _FakeL10n();

  group('validatePassword', () {
    test('returns errPasswordRequired for null', () {
      expect(validatePassword(null, l10n), equals('required'));
    });

    test('returns errPasswordRequired for empty string', () {
      expect(validatePassword('', l10n), equals('required'));
    });

    test('returns errPasswordLength for 129-char string', () {
      expect(validatePassword('a' * 129, l10n), equals('length'));
    });

    test('returns null for 1-char string', () {
      expect(validatePassword('a', l10n), isNull);
    });

    test('returns null for 128-char string', () {
      expect(validatePassword('a' * 128, l10n), isNull);
    });
  });
}
