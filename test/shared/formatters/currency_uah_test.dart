// Tests for CurrencyUah — the "₴ "-prefixed hryvnia label builder.
//
// Format: "₴ " (symbol + ASCII space, U+0020) followed by the integer digits
// grouped in thousands. The uk_UA NumberFormat groups with a NO-BREAK SPACE
// (U+00A0, code unit 160), NOT an ASCII space — so the separator between digit
// groups is U+00A0. Kopecks are suppressed (the value is rounded to a whole
// hryvnia by the underlying integer NumberFormat pattern).
//
// `nb` below is the exact thousands separator the formatter emits, so the
// expected strings are spelled literally rather than guessed.

import 'package:beautica_mobile/shared/formatters/currency_uah.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // U+00A0 NO-BREAK SPACE — the uk_UA thousands separator the formatter emits.
  const nb = ' ';

  group('CurrencyUah.format', () {
    test('renders a plain three-digit price without any grouping', () {
      expect(CurrencyUah.format(750), '₴ 750');
    });

    test('groups thousands with a no-break space, not an ASCII space', () {
      expect(CurrencyUah.format(1800), '₴ 1${nb}800');
    });

    test('the digit-group separator is U+00A0 (verified by code unit)', () {
      final out = CurrencyUah.format(1800);
      // Index 0 ₴, 1 ASCII space, 2 '1', 3 separator, 4 '8'...
      expect(out.codeUnitAt(1), 0x20, reason: 'space after ₴ is ASCII');
      expect(out.codeUnitAt(3), 0x00A0, reason: 'thousands separator is U+00A0');
    });

    test('groups every three digits for large values', () {
      expect(CurrencyUah.format(1234567), '₴ 1${nb}234${nb}567');
    });

    test('renders zero as "₴ 0"', () {
      expect(CurrencyUah.format(0), '₴ 0');
    });

    test('two-digit value stays ungrouped', () {
      expect(CurrencyUah.format(99), '₴ 99');
    });

    test('exactly one thousand gets a single separator', () {
      expect(CurrencyUah.format(1000), '₴ 1${nb}000');
    });

    test('the boundary at 1000 grows from ungrouped to grouped', () {
      expect(CurrencyUah.format(999), '₴ 999');
      expect(CurrencyUah.format(1000), '₴ 1${nb}000');
    });

    test('fractional input rounds half-up to the nearest whole hryvnia', () {
      expect(CurrencyUah.format(1500.5), '₴ 1${nb}501');
    });

    test('fractional input below the half rounds down', () {
      expect(CurrencyUah.format(1500.4), '₴ 1${nb}500');
    });

    test('always begins with the hryvnia symbol and an ASCII space', () {
      expect(CurrencyUah.format(42).startsWith('₴ '), isTrue);
    });
  });
}
