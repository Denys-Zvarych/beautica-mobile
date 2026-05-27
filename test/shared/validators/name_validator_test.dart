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
  });
}
