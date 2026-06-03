// Phase 2.19 — Pure-Dart unit tests for validateStreet().
//
// Bounds from street_validator.dart: min 2 trimmed chars, max 255 raw chars
// (kStreetMaxLength — aligned to the backend address DTO), required (empty/null
// → error). Used by provider roles only.
//
// The boundary cases key off the kStreetMaxLength constant directly, so they
// track the backend-aligned limit automatically.
//
// Covered scenarios:
//   1. null                       → errStreetRequired
//   2. empty string               → errStreetRequired
//   3. whitespace-only            → errStreetRequired (trim rule)
//   4. 1-char (below min)         → errStreetRequired
//   5. 2-char (min valid)         → null
//   6. 255-char (max valid)       → null
//   7. 256-char (exceeds max)     → errStreetTooLong
//   8. typical street             → null

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/validators/street_validator.dart';
import 'package:flutter_test/flutter_test.dart';

final class _FakeL10n extends Fake implements AppLocalizations {
  @override
  String get errStreetRequired => 'street_required';

  @override
  String get errStreetTooLong => 'street_too_long';
}

void main() {
  final l10n = _FakeL10n();

  test('null → errStreetRequired', () {
    expect(validateStreet(null, l10n), equals('street_required'));
  });

  test('empty string → errStreetRequired', () {
    expect(validateStreet('', l10n), equals('street_required'));
  });

  test('whitespace-only → errStreetRequired', () {
    expect(validateStreet('   ', l10n), equals('street_required'));
  });

  test('1-char (below min 2) → errStreetRequired', () {
    expect(validateStreet('A', l10n), equals('street_required'));
  });

  test('2-char (minimum valid) → null', () {
    expect(validateStreet('AB', l10n), isNull);
  });

  test('$kStreetMaxLength chars (maximum valid) → null', () {
    expect(validateStreet('a' * kStreetMaxLength, l10n), isNull);
  });

  test('${kStreetMaxLength + 1} chars (exceeds max) → errStreetTooLong', () {
    expect(
      validateStreet('a' * (kStreetMaxLength + 1), l10n),
      equals('street_too_long'),
    );
  });

  test('typical street → null', () {
    expect(validateStreet('вул. Хрещатик', l10n), isNull);
  });
}
