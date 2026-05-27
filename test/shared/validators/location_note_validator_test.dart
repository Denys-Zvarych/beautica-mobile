// Phase 2.19 — Pure-Dart unit tests for validateLocationNote().
//
// Bounds from location_note_validator.dart: OPTIONAL (null/empty OK), max 250
// raw chars. Used by provider roles only.
//
// Covered scenarios:
//   1. null                       → null (optional)
//   2. empty string               → null (optional)
//   3. whitespace-only            → null (length under cap, not trimmed)
//   4. typical note               → null
//   5. 250-char (max valid)       → null
//   6. 251-char (exceeds max)     → errLocationNoteTooLong

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/validators/location_note_validator.dart';
import 'package:flutter_test/flutter_test.dart';

final class _FakeL10n extends Fake implements AppLocalizations {
  @override
  String get errLocationNoteTooLong => 'note_too_long';
}

void main() {
  final l10n = _FakeL10n();

  test('null → null (optional field)', () {
    expect(validateLocationNote(null, l10n), isNull);
  });

  test('empty string → null (optional field)', () {
    expect(validateLocationNote('', l10n), isNull);
  });

  test('whitespace-only → null (under cap)', () {
    expect(validateLocationNote('   ', l10n), isNull);
  });

  test('typical note → null', () {
    expect(validateLocationNote('Дзвоніть у домофон №3', l10n), isNull);
  });

  test('$kLocationNoteMaxLength chars (maximum valid) → null', () {
    expect(validateLocationNote('a' * kLocationNoteMaxLength, l10n), isNull);
  });

  test(
    '${kLocationNoteMaxLength + 1} chars (exceeds max) → errLocationNoteTooLong',
    () {
      expect(
        validateLocationNote('a' * (kLocationNoteMaxLength + 1), l10n),
        equals('note_too_long'),
      );
    },
  );
}
