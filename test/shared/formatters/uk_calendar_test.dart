// Phase 23.1 — the pinning test for `shared/formatters/uk_calendar.dart`.
//
// This is the load-bearing artifact of the phase: it asserts, by literal
// hard-coded expected lists (never re-derived from the module under test),
// that the five canonical tables are byte-for-byte what the app renders
// today across `month_names.dart`, `schedule_model.dart`,
// `schedule_mapper.dart`, `master_schedule_screen.dart` and
// `booking_date_labels.dart`. 23.2/23.3 migrate those files onto this module
// and must re-run this test UNCHANGED — if a later phase needs to edit an
// expectation here, that phase has changed rendering and must stop.
//
// The Friday U+02BC assertion is deliberately a codepoint check, not a
// string-literal eyeball comparison: `schedule_mapper.dart`'s existing table
// spells Friday with U+2019 (RIGHT SINGLE QUOTATION MARK) instead, and the
// two glyphs are visually indistinguishable in a diff.

import 'package:flutter_test/flutter_test.dart';

import 'package:beautica_mobile/shared/formatters/uk_calendar.dart';

void main() {
  group('monthNominative', () {
    const List<String> expected = <String>[
      'Січень',
      'Лютий',
      'Березень',
      'Квітень',
      'Травень',
      'Червень',
      'Липень',
      'Серпень',
      'Вересень',
      'Жовтень',
      'Листопад',
      'Грудень',
    ];

    test('resolves all 12 months, in calendar order, verbatim', () {
      final List<String> resolved = List<String>.generate(
        12,
        (int i) => monthNominative(i + 1),
      );
      expect(resolved, expected);
    });

    test('index 0 throws RangeError', () {
      expect(() => monthNominative(0), throwsRangeError);
    });

    test('index 13 throws RangeError', () {
      expect(() => monthNominative(13), throwsRangeError);
    });
  });

  group('monthGenitive', () {
    const List<String> expected = <String>[
      'січня',
      'лютого',
      'березня',
      'квітня',
      'травня',
      'червня',
      'липня',
      'серпня',
      'вересня',
      'жовтня',
      'листопада',
      'грудня',
    ];

    test('resolves all 12 months, in calendar order, verbatim', () {
      final List<String> resolved = List<String>.generate(
        12,
        (int i) => monthGenitive(i + 1),
      );
      expect(resolved, expected);
    });

    test('index 0 throws RangeError', () {
      expect(() => monthGenitive(0), throwsRangeError);
    });

    test('index 13 throws RangeError', () {
      expect(() => monthGenitive(13), throwsRangeError);
    });
  });

  group('monthAbbrev', () {
    const List<String> expected = <String>[
      'січ',
      'лют',
      'бер',
      'кві',
      'тра',
      'чер',
      'лип',
      'сер',
      'вер',
      'жов',
      'лис',
      'гру',
    ];

    test('resolves all 12 months, in calendar order, verbatim', () {
      final List<String> resolved = List<String>.generate(
        12,
        (int i) => monthAbbrev(i + 1),
      );
      expect(resolved, expected);
    });

    test('index 0 throws RangeError', () {
      expect(() => monthAbbrev(0), throwsRangeError);
    });

    test('index 13 throws RangeError', () {
      expect(() => monthAbbrev(13), throwsRangeError);
    });
  });

  group('weekdayName', () {
    const List<String> expected = <String>[
      'понеділок',
      'вівторок',
      'середа',
      'четвер',
      'пʼятниця',
      'субота',
      'неділя',
    ];

    test('resolves all 7 weekdays, Monday-first, verbatim', () {
      final List<String> resolved = List<String>.generate(
        7,
        (int i) => weekdayName(i + 1),
      );
      expect(resolved, expected);
    });

    test('Friday is spelled with U+02BC (MODIFIER LETTER APOSTROPHE), not '
        'U+2019 (RIGHT SINGLE QUOTATION MARK) — verified by codepoint, not '
        'by eye, since the two glyphs are visually indistinguishable', () {
      final String friday = weekdayName(5);
      expect(friday, 'пʼятниця');
      // 'п', 'ʼ', 'я', 'т', 'н', 'и', 'ц', 'я'
      expect(friday.codeUnitAt(1), 0x02bc);
      expect(friday.runes.elementAt(1), 0x02bc);
    });

    test('index 0 throws RangeError', () {
      expect(() => weekdayName(0), throwsRangeError);
    });

    test('index 8 throws RangeError', () {
      expect(() => weekdayName(8), throwsRangeError);
    });
  });

  group('weekdayAbbrev', () {
    const List<String> expected = <String>[
      'пн',
      'вт',
      'ср',
      'чт',
      'пт',
      'сб',
      'нд',
    ];

    test('resolves all 7 weekdays, Monday-first, verbatim', () {
      final List<String> resolved = List<String>.generate(
        7,
        (int i) => weekdayAbbrev(i + 1),
      );
      expect(resolved, expected);
    });

    test('index 0 throws RangeError', () {
      expect(() => weekdayAbbrev(0), throwsRangeError);
    });

    test('index 8 throws RangeError', () {
      expect(() => weekdayAbbrev(8), throwsRangeError);
    });
  });

  group('ukUpper', () {
    // Pins the exact strings `schedule_model.dart`'s `_monthsShort` table
    // ('СІЧ'…'ГРУ') will migrate onto in 23.2.
    const List<String> expectedUpper = <String>[
      'СІЧ',
      'ЛЮТ',
      'БЕР',
      'КВІ',
      'ТРА',
      'ЧЕР',
      'ЛИП',
      'СЕР',
      'ВЕР',
      'ЖОВ',
      'ЛИС',
      'ГРУ',
    ];

    test('ukUpper(monthAbbrev(m)) matches the existing _monthsShort table '
        'for all 12 months', () {
      final List<String> resolved = List<String>.generate(
        12,
        (int i) => ukUpper(monthAbbrev(i + 1)),
      );
      expect(resolved, expectedUpper);
    });

    test('empty string is returned unchanged rather than throwing', () {
      expect(ukUpper(''), '');
    });
  });

  group('ukCapitalize', () {
    // Pins the exact strings `master_schedule_screen.dart`'s `_weekdayShort`
    // table ('Пн'…'Нд') will migrate onto in 23.2.
    const List<String> expectedCapitalized = <String>[
      'Пн',
      'Вт',
      'Ср',
      'Чт',
      'Пт',
      'Сб',
      'Нд',
    ];

    test('ukCapitalize(weekdayAbbrev(w)) matches the existing _weekdayShort '
        'table for all 7 weekdays', () {
      final List<String> resolved = List<String>.generate(
        7,
        (int i) => ukCapitalize(weekdayAbbrev(i + 1)),
      );
      expect(resolved, expectedCapitalized);
    });

    test('empty string is returned unchanged rather than throwing', () {
      expect(ukCapitalize(''), '');
    });
  });
}
