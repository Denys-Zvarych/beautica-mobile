// Phase 5.3 — Pure-Dart unit tests for numeric_validators.dart.
//
// No widget pump needed. A minimal _FakeL10n supplies hardcoded strings so
// validators can be exercised without spinning up a Flutter widget tree.
//
// Covered scenarios for validateDurationMinutes:
//   1. null input              → errRequired
//   2. blank string            → errRequired
//   3. '0'                     → errDurationPositive
//   4. '-1'                    → errDurationPositive
//   5. 'abc'                   → errDurationPositive
//   6. '1'                     → null (valid minimum)
//   7. '1440'                  → null (valid maximum)
//   8. '1441'                  → errDurationMax
//
// Covered scenarios for validatePriceUah:
//   1. null input              → errRequired
//   2. blank string            → errRequired
//   3. '0'                     → null (zero is valid)
//   4. '500'                   → null
//   5. 'abc'                   → errPriceNonNegative

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/validators/numeric_validators.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake l10n — hardcoded strings avoid a widget tree in pure unit tests.
// ---------------------------------------------------------------------------

final class _FakeL10n extends Fake implements AppLocalizations {
  @override
  String get errRequired => 'required';

  @override
  String get errDurationPositive => 'duration positive';

  @override
  String get errDurationMax => 'duration max';

  @override
  String get errPriceNonNegative => 'price non negative';
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  final l10n = _FakeL10n();

  group('validateDurationMinutes', () {
    test('returns errRequired for null', () {
      expect(validateDurationMinutes(null, l10n), equals('required'));
    });

    test('returns errRequired for blank string', () {
      expect(validateDurationMinutes('   ', l10n), equals('required'));
    });

    test('returns errDurationPositive for zero', () {
      expect(validateDurationMinutes('0', l10n), equals('duration positive'));
    });

    test('returns errDurationPositive for negative integer', () {
      expect(validateDurationMinutes('-1', l10n), equals('duration positive'));
    });

    test('returns errDurationPositive for non-numeric string', () {
      expect(validateDurationMinutes('abc', l10n), equals('duration positive'));
    });

    test('returns null for minimum valid value (1)', () {
      expect(validateDurationMinutes('1', l10n), isNull);
    });

    test('returns null for maximum valid value (1440)', () {
      expect(validateDurationMinutes('1440', l10n), isNull);
    });

    test('returns errDurationMax for value exceeding maximum (1441)', () {
      expect(validateDurationMinutes('1441', l10n), equals('duration max'));
    });
  });

  group('validatePriceUah', () {
    test('returns errRequired for null', () {
      expect(validatePriceUah(null, l10n), equals('required'));
    });

    test('returns errRequired for blank string', () {
      expect(validatePriceUah('   ', l10n), equals('required'));
    });

    test('returns null for zero (zero is a valid price)', () {
      expect(validatePriceUah('0', l10n), isNull);
    });

    test('returns null for typical positive price', () {
      expect(validatePriceUah('500', l10n), isNull);
    });

    test('returns errPriceNonNegative for non-numeric string', () {
      expect(validatePriceUah('abc', l10n), equals('price non negative'));
    });
  });
}
