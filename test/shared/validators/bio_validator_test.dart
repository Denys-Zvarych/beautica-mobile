// Phase 4.3 — Pure-Dart unit tests for validateBio().
//
// Bounds from bio_validator.dart: OPTIONAL (null/empty/whitespace-only → null),
// 2000-code-unit hard cap on the TRIMMED value (mirrors the backend's
// `@Size(max = 2000)` on MasterDetailResponse.bio). No character-class
// restrictions — any Unicode is allowed.
//
// Covered scenarios:
//   1. null                              → null (optional)
//   2. empty string                      → null (optional)
//   3. whitespace-only                   → null (trimmed to empty)
//   4. typical Cyrillic bio              → null
//   5. bio with emoji / punctuation      → null (no char-class restriction)
//   6. exactly 2000 trimmed chars        → null (at the cap, inclusive)
//   7. 2001 trimmed chars                → errBioTooLong (over the cap)
//   8. surrounding whitespace ignored    → null (trim makes a 2001-raw value fit)

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/validators/bio_validator.dart';
import 'package:flutter_test/flutter_test.dart';

final class _FakeL10n extends Fake implements AppLocalizations {
  @override
  String get errBioTooLong => 'bio_too_long';
}

void main() {
  final l10n = _FakeL10n();

  test('null → null (optional field)', () {
    expect(validateBio(null, l10n), isNull);
  });

  test('empty string → null (optional field)', () {
    expect(validateBio('', l10n), isNull);
  });

  test('whitespace-only → null (trims to empty)', () {
    expect(validateBio('   \n\t ', l10n), isNull);
  });

  test('typical Cyrillic bio → null', () {
    expect(validateBio('Майстер манікюру з 10-річним досвідом.', l10n), isNull);
  });

  test('emoji and punctuation are allowed → null', () {
    expect(validateBio('Nails 💅 — best in town! (Kyiv)', l10n), isNull);
  });

  test('exactly 2000 trimmed chars (at the cap) → null', () {
    expect(validateBio('a' * 2000, l10n), isNull);
  });

  test('2001 trimmed chars (over the cap) → errBioTooLong', () {
    expect(validateBio('a' * 2001, l10n), equals('bio_too_long'));
  });

  test('cap is measured on the trimmed value, not the raw input → null', () {
    // 2000 content chars wrapped in whitespace: raw length 2002, trimmed 2000.
    final padded = '  ${'a' * 2000}  ';
    expect(validateBio(padded, l10n), isNull);
  });
}
