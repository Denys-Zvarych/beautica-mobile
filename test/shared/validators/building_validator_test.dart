// Phase 2.19 — Pure-Dart unit tests for validateBuilding().
//
// Bounds from building_validator.dart: min 1 trimmed char, max 20 raw chars,
// required (empty/null → error). Used by provider roles only.
//
// Covered scenarios:
//   1. null                       → errBuildingRequired
//   2. empty string               → errBuildingRequired
//   3. whitespace-only            → errBuildingRequired (trim rule)
//   4. 1-char (min valid)         → null (a single digit "5" is valid)
//   5. 20-char (max valid)        → null
//   6. 21-char (exceeds max)      → errBuildingTooLong
//   7. typical building "12А"     → null

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/validators/building_validator.dart';
import 'package:flutter_test/flutter_test.dart';

final class _FakeL10n extends Fake implements AppLocalizations {
  @override
  String get errBuildingRequired => 'building_required';

  @override
  String get errBuildingTooLong => 'building_too_long';
}

void main() {
  final l10n = _FakeL10n();

  test('null → errBuildingRequired', () {
    expect(validateBuilding(null, l10n), equals('building_required'));
  });

  test('empty string → errBuildingRequired', () {
    expect(validateBuilding('', l10n), equals('building_required'));
  });

  test('whitespace-only → errBuildingRequired', () {
    expect(validateBuilding('   ', l10n), equals('building_required'));
  });

  test('1-char (minimum valid) → null', () {
    expect(validateBuilding('5', l10n), isNull);
  });

  test('$kBuildingMaxLength chars (maximum valid) → null', () {
    expect(validateBuilding('1' * kBuildingMaxLength, l10n), isNull);
  });

  test(
    '${kBuildingMaxLength + 1} chars (exceeds max) → errBuildingTooLong',
    () {
      expect(
        validateBuilding('1' * (kBuildingMaxLength + 1), l10n),
        equals('building_too_long'),
      );
    },
  );

  test('typical building "12А" → null', () {
    expect(validateBuilding('12А', l10n), isNull);
  });
}
