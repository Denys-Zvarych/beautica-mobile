// Phase 2.21 — Unit tests for [UaPhoneInputFormatter].
//
// Covers the full subscriber-digit boundary matrix, normalisation of common
// paste variants, clamping, and cursor placement.
//
// Space positions in the formatted output (0-indexed into the 9-digit
// subscriber string):
//   before i==2 → after 2-digit operator code  (+380 XX)
//   before i==5 → after 3-digit mid block      (+380 XX XXX)
//   before i==7 → after 2-digit hi block       (+380 XX XXX XX)
//
// Full 9-digit example:
//   subscriber '671234567' → '+380 67 123 45 67'

import 'package:beautica_mobile/shared/formatters/ua_phone_input_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

TextEditingValue _format(String input) => const UaPhoneInputFormatter()
    .formatEditUpdate(const TextEditingValue(), TextEditingValue(text: input));

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('UaPhoneInputFormatter', () {
    // ── Empty / no-digit inputs ─────────────────────────────────────────────

    test('1. empty string → empty output', () {
      final result = _format('');
      expect(result.text, isEmpty);
      // The formatter returns const TextEditingValue() which has
      // TextSelection.invalid (offset -1). Just verify the text is empty.
      expect(result.selection.baseOffset, equals(-1));
    });

    test('2. "+" alone (no digits) → empty output', () {
      expect(_format('+').text, isEmpty);
    });

    test('3. whitespace only → empty output', () {
      expect(_format('   ').text, isEmpty);
    });

    // ── Normalisation: leading prefix variants ──────────────────────────────

    test('4. local format "0671234567" → "+380 67 123 45 67"', () {
      expect(_format('0671234567').text, equals('+380 67 123 45 67'));
    });

    test('5. no-plus format "380671234567" → "+380 67 123 45 67"', () {
      expect(_format('380671234567').text, equals('+380 67 123 45 67'));
    });

    test('6. full "+380671234567" paste → "+380 67 123 45 67"', () {
      expect(_format('+380671234567').text, equals('+380 67 123 45 67'));
    });

    test('7. formatted paste "+380 67 123 45 67" → "+380 67 123 45 67"', () {
      expect(_format('+380 67 123 45 67').text, equals('+380 67 123 45 67'));
    });

    test('8. bare 9 subscriber digits "671234567" → "+380 67 123 45 67"', () {
      // No leading prefix — treated as bare subscriber digits.
      expect(_format('671234567').text, equals('+380 67 123 45 67'));
    });

    // ── Clamping ────────────────────────────────────────────────────────────

    test('9. over-long input clamps to 9 subscriber digits', () {
      // '380671234567890' → subscriber '671234567890' (12) → clamped to '671234567'
      expect(_format('380671234567890').text, equals('+380 67 123 45 67'));
    });

    test('10. over-long with + clamps to 9 subscriber digits', () {
      expect(_format('+380671234567890').text, equals('+380 67 123 45 67'));
    });

    // ── Non-digit character stripping ───────────────────────────────────────

    test('11. non-digit chars stripped "+380 67 (123) 45-67"', () {
      expect(_format('+380 67 (123) 45-67').text, equals('+380 67 123 45 67'));
    });

    test('12. alphabetic chars stripped "abc067def1234567"', () {
      // digits = '0671234567' → subscriber = '671234567' (local format)
      expect(_format('abc067def1234567').text, equals('+380 67 123 45 67'));
    });

    // ── Subscriber digit count boundary matrix ──────────────────────────────
    //
    // Space positions: before index 2, 5, 7.
    // 0 digits: empty (handled above)
    // 1 digit:  '+380 6'
    // 2 digits: '+380 67'
    // 3 digits: '+380 67 1'          (space inserted before i==2)
    // 4 digits: '+380 67 12'
    // 5 digits: '+380 67 123'
    // 6 digits: '+380 67 123 4'      (space inserted before i==5)
    // 7 digits: '+380 67 123 45'
    // 8 digits: '+380 67 123 45 6'   (space inserted before i==7)
    // 9 digits: '+380 67 123 45 67'

    test('13. 1 subscriber digit → "+380 6"', () {
      // '06' → digits='06' → subscriber='6' (starts with '0', strip it → '6')
      // But '06' length=2 and local format requires length==10. So subscriber='6'
      // only if we treat '06' as digits starting with '0' → subscriber='6'.
      // Wait: '06' → starts with '0' → subscriber = digits.substring(1) = '6'.
      expect(_format('06').text, equals('+380 6'));
    });

    test('14. 2 subscriber digits → "+380 67"', () {
      // '067' → starts with '0' → subscriber = '67'
      expect(_format('067').text, equals('+380 67'));
    });

    test('15. 3 subscriber digits → "+380 67 1"', () {
      // '0671' → subscriber = '671' → space at i==2 → '+380 67 1'
      expect(_format('0671').text, equals('+380 67 1'));
    });

    test('16. 4 subscriber digits → "+380 67 12"', () {
      expect(_format('06712').text, equals('+380 67 12'));
    });

    test('17. 5 subscriber digits → "+380 67 123"', () {
      expect(_format('067123').text, equals('+380 67 123'));
    });

    test('18. 6 subscriber digits → "+380 67 123 4"', () {
      // '0671234' → subscriber='671234' → space at i==2 and i==5
      // i=0:'6', i=1:'7', i=2:' '+'1', i=3:'2', i=4:'3', i=5:' '+'4'
      // → '+380 67 123 4'
      expect(_format('0671234').text, equals('+380 67 123 4'));
    });

    test('19. 7 subscriber digits → "+380 67 123 45"', () {
      expect(_format('06712345').text, equals('+380 67 123 45'));
    });

    test('20. 8 subscriber digits → "+380 67 123 45 6"', () {
      // space at i==7
      expect(_format('067123456').text, equals('+380 67 123 45 6'));
    });

    test('21. 9 subscriber digits → "+380 67 123 45 67"', () {
      expect(_format('0671234567').text, equals('+380 67 123 45 67'));
    });

    // ── Cursor placement ────────────────────────────────────────────────────

    test('22. cursor placed at end of formatted string', () {
      final result = _format('+380671234567');
      expect(result.selection.baseOffset, equals(result.text.length));
      expect(result.selection.extentOffset, equals(result.text.length));
      expect(result.selection.isCollapsed, isTrue);
    });

    test('23. cursor at end for partial input', () {
      final result = _format('067');
      expect(result.text, equals('+380 67'));
      expect(result.selection.baseOffset, equals(7));
      expect(result.selection.isCollapsed, isTrue);
    });

    // ── Other operator codes ────────────────────────────────────────────────

    test('24. Kyivstar +380 96 → formats correctly', () {
      expect(_format('+380961234567').text, equals('+380 96 123 45 67'));
    });

    test('25. Lifecell +380 73 → formats correctly', () {
      expect(_format('+380731234567').text, equals('+380 73 123 45 67'));
    });
  });
}
