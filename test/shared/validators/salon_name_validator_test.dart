// Phase 2.17 — Pure-Dart unit tests for validateSalonName().
//
// No widget pump needed. A minimal _FakeL10n supplies hardcoded strings so the
// validator can be exercised without spinning up a Flutter widget tree.
//
// Covered scenarios:
//   1. null input                 → errSalonNameRequired
//   2. empty string               → errSalonNameRequired
//   3. whitespace-only string     → errSalonNameRequired (trim rule)
//   4. 1-char string (too short)  → errSalonNameRequired (< 2 trimmed chars)
//   5. 2-char string (min valid)  → null
//   6. 255-char string (max valid)→ null (backend-consistent cap)
//   7. 256-char string (too long) → errSalonNameTooLong
//   8. typical name               → null
//
// Role-conditional contract:
//   - The validator is attached ONLY when role == UserRole.salonOwner.
//   - For non-owner roles the field is not rendered; we verify this contract
//     by confirming validateSalonName is NOT called (returns null on a null
//     value only because the caller skips attachment).
//   - The owner-path is tested via the validator directly (all cases above).
//   - The non-owner path is documented: callers must not attach this
//     validator; there is no validator call for non-owners.

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/validators/salon_name_validator.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake l10n
// ---------------------------------------------------------------------------

final class _FakeL10n extends Fake implements AppLocalizations {
  @override
  String get errSalonNameRequired => 'salon_required';

  @override
  String get errSalonNameTooLong => 'salon_too_long';

  @override
  String get errSalonNameInvalid => 'salon_invalid';
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  final l10n = _FakeL10n();

  group('validateSalonName — SALON_OWNER path (validator attached)', () {
    test('returns errSalonNameRequired for null', () {
      expect(validateSalonName(null, l10n), equals('salon_required'));
    });

    test('returns errSalonNameRequired for empty string', () {
      expect(validateSalonName('', l10n), equals('salon_required'));
    });

    test('returns errSalonNameRequired for whitespace-only string', () {
      expect(validateSalonName('   ', l10n), equals('salon_required'));
    });

    test('returns errSalonNameRequired for 1-char string (too short)', () {
      expect(validateSalonName('A', l10n), equals('salon_required'));
    });

    test('returns null for 2-char string (minimum valid length)', () {
      expect(validateSalonName('AB', l10n), isNull);
    });

    test('returns null for 255-char string (maximum valid length)', () {
      expect(validateSalonName('a' * 255, l10n), isNull);
    });

    test('returns errSalonNameTooLong for 256-char string (exceeds max)', () {
      expect(validateSalonName('a' * 256, l10n), equals('salon_too_long'));
    });

    test('returns null for a typical salon name', () {
      expect(validateSalonName('Salon Lumière', l10n), isNull);
    });

    test('returns errSalonNameInvalid for an embedded NUL (U+0000)', () {
      // Construct via fromCharCode so the control byte is unambiguous in source.
      final withNul = 'Salon${String.fromCharCode(0x00)}Name';
      expect(validateSalonName(withNul, l10n), equals('salon_invalid'));
    });

    test('returns errSalonNameInvalid for an embedded DEL (U+007F)', () {
      final withDel = 'Salon${String.fromCharCode(0x7F)}Name';
      expect(validateSalonName(withDel, l10n), equals('salon_invalid'));
    });

    test('returns errSalonNameInvalid for an embedded newline (U+000A)', () {
      final withNewline = 'Salon${String.fromCharCode(0x0A)}Name';
      expect(validateSalonName(withNewline, l10n), equals('salon_invalid'));
    });

    test('returns null for a valid Cyrillic salon name (no control chars)', () {
      expect(validateSalonName('Салон Краси', l10n), isNull);
    });
  });

  group('validateSalonName — non-OWNER path (validator NOT attached)', () {
    // For CLIENT and INDEPENDENT_MASTER, the salon-name field is not rendered
    // and the validator is never attached. This test documents the contract:
    // the presenter does NOT call validateSalonName for non-owner roles.
    // We verify by confirming that when the validator IS called with a null
    // value (as if it were accidentally attached), it still returns an error
    // (not null), which would correctly block submission — but the real
    // non-owner path is to simply not attach the validator at all.
    test(
      'validator returns error when accidentally called with null (guard)',
      () {
        // This is not a valid use case, but confirms the validator is always
        // strict — callers must never attach it for non-owner roles.
        expect(validateSalonName(null, l10n), equals('salon_required'));
      },
    );

    // DELETED (2026-07-22 vacuous-assertion audit): a test named
    // 'non-owner skip contract is documented (no validator call)' lived here.
    // Its entire body was `const String? nonOwnerResult = null;
    // expect(nonOwnerResult, isNull);` — it never invoked validateSalonName and
    // could not fail under any change to the validator or its callers. It was
    // an assertion about a local it had just declared.
    //
    // The non-owner contract (the validator is not attached at all when the
    // role is not SALON_OWNER — RegisterStep2Screen._fieldsForRole) is really
    // covered, at the widget level, in
    // `test/features/auth/presentation/register_step_2_screen_test.dart`
    // (Tests 1–2: CLIENT and MASTER variants assert
    // `find.byKey(Key('field-salon-name'))` findsNothing).
  });
}
