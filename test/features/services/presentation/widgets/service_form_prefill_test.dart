// Phase 16.3 — pure unit tests for [ServiceForm.shouldPrefillName].
//
// `shouldPrefillName` is the pure decision rule behind the service-name
// pre-fill that runs when a master picks a service type. It is the highest-value,
// cheapest unit in the phase: no widget tree, no Riverpod, no controllers — just
// the branch that decides whether the chosen type's `nameUk` may overwrite the
// current name. Exhausting its three branches here guarantees the
// "don't-clobber a user-edited name" invariant independently of the widget glue.
//
// Rule (from the source contract):
//   prefill ⇔ currentName.trim().isEmpty
//            OR (lastAutoFilledName != null && currentName == lastAutoFilledName)
//
// Branches covered:
//   P-1. empty / whitespace name                       → true
//   P-2. name == lastAutoFilled (re-select case)       → true
//   P-3. user-edited name (non-empty, != lastAutoFill) → false  (DON'T CLOBBER)
//   P-4. non-empty name with no prior auto-fill        → false
//   P-5. boundary: whitespace-only name still prefills (trim)

import 'package:beautica_mobile/features/services/presentation/widgets/service_form.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ServiceForm.shouldPrefillName', () {
    test('P-1. empty name → prefill allowed', () {
      expect(
        ServiceForm.shouldPrefillName(
          currentName: '',
          lastAutoFilledName: null,
        ),
        isTrue,
      );
    });

    test('P-1b. empty name with a prior auto-fill → still allowed', () {
      expect(
        ServiceForm.shouldPrefillName(
          currentName: '',
          lastAutoFilledName: 'Манікюр',
        ),
        isTrue,
      );
    });

    test('P-2. name equals last auto-filled value → prefill allowed', () {
      // Master selected a type (auto-filled "Манікюр"), then selects a second
      // type without touching the name. The name still equals the last
      // auto-fill, so it may be replaced.
      expect(
        ServiceForm.shouldPrefillName(
          currentName: 'Манікюр',
          lastAutoFilledName: 'Манікюр',
        ),
        isTrue,
      );
    });

    test('P-3. user-edited name is NOT clobbered', () {
      // The user hand-typed a name that differs from the last auto-fill. A new
      // service-type selection must NOT overwrite it. This is the load-bearing
      // "don't-clobber" invariant.
      expect(
        ServiceForm.shouldPrefillName(
          currentName: 'Мій власний манікюр',
          lastAutoFilledName: 'Манікюр',
        ),
        isFalse,
      );
    });

    test('P-4. non-empty name with no prior auto-fill → not allowed', () {
      // The user typed a name before ever selecting a type (lastAutoFilled is
      // null). The picker must not overwrite it.
      expect(
        ServiceForm.shouldPrefillName(
          currentName: 'Щось',
          lastAutoFilledName: null,
        ),
        isFalse,
      );
    });

    test('P-5. whitespace-only name is treated as empty (trim) → allowed', () {
      expect(
        ServiceForm.shouldPrefillName(
          currentName: '   ',
          lastAutoFilledName: null,
        ),
        isTrue,
      );
    });
  });
}
