// mobile-qa (2026-07-20) — regression coverage for `month_names.dart`.
//
// Lifted out of `features/schedule/domain/schedule_model.dart` in Phase 7.7
// (see that file's re-export) as new `shared/` infra with a second caller in
// the booking feature — but neither the old location nor the new one ever
// had a direct test asserting the table itself: `schedule_model_test.dart`
// does not reference `monthNominative`/`monthNamesNominative`, and no
// booking test asserts against a specific month string (the period-range
// picker tests exercise the WIDGET, not this table).
//
// [monthNominative] indexes a fixed 12-entry list by `month - 1` with no
// bounds check — an off-by-one (e.g. reading `DateTime.month` before
// subtracting, or a caller passing a 0-based month) throws `RangeError`
// rather than returning a wrong-but-harmless string, so the boundary values
// (1 and 12) are the load-bearing cases here, not decoration.

import 'package:flutter_test/flutter_test.dart';

import 'package:beautica_mobile/shared/formatters/month_names.dart';

void main() {
  group('monthNominative', () {
    test('January (the lower 1-based boundary) resolves to "Січень"', () {
      expect(monthNominative(1), 'Січень');
    });

    test('December (the upper 1-based boundary) resolves to "Грудень"', () {
      expect(monthNominative(12), 'Грудень');
    });

    test('every DateTime.month value 1..12 resolves to a distinct name', () {
      final List<String> resolved = List<String>.generate(
        12,
        (int i) => monthNominative(i + 1),
      );
      expect(
        resolved.toSet().length,
        12,
        reason:
            'all twelve months must be distinct strings — a collapsed table '
            'would silently mislabel a month rather than crash',
      );
    });

    test('a July DateTime.month (7, the value most call sites derive via '
        '.month) resolves to "Липень"', () {
      expect(monthNominative(DateTime(2026, 7, 20).month), 'Липень');
    });
  });

  group('monthNamesNominative', () {
    test(
      'carries exactly 12 entries, in calendar order starting at Січень',
      () {
        final List<String> names = monthNamesNominative;
        expect(names, hasLength(12));
        expect(names.first, 'Січень');
        expect(names.last, 'Грудень');
      },
    );

    test('is unmodifiable — a caller mutating its copy must not corrupt the '
        'shared table for every other reader', () {
      expect(
        () => monthNamesNominative.add('Тринадцятий'),
        throwsUnsupportedError,
      );
    });

    test(
      'each entry agrees with monthNominative at the same 1-based index',
      () {
        final List<String> names = monthNamesNominative;
        for (int month = 1; month <= 12; month++) {
          expect(names[month - 1], monthNominative(month));
        }
      },
    );
  });
}
