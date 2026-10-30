// Phase 424 (security LOW-1) — Utf16LengthLimitingFormatter counts what the
// backend's `@Size(max = …)` counts (UTF-16 code units) and never splits a
// grapheme cluster.

import 'package:beautica_mobile/shared/formatters/utf16_length_limiting_formatter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

TextEditingValue _v(String text, {int? caret}) => TextEditingValue(
  text: text,
  selection: TextSelection.collapsed(offset: caret ?? text.length),
);

void main() {
  const Utf16LengthLimitingFormatter f = Utf16LengthLimitingFormatter(5);

  test('within budget → passes through untouched', () {
    final TextEditingValue next = _v('abcde');
    expect(f.formatEditUpdate(_v('abcd'), next), same(next));
  });

  test('budget is UTF-16 units, not graphemes: 3 emoji (6 units) → 2', () {
    final TextEditingValue out = f.formatEditUpdate(
      _v(''),
      _v('\u{1F600}\u{1F600}\u{1F600}'),
    );
    expect(out.text, '\u{1F600}\u{1F600}');
    expect(out.text.length, 4);
    expect(out.selection, const TextSelection.collapsed(offset: 4));
  });

  test('never splits a cluster: a ZWJ family straddling the cut is dropped '
      'whole', () {
    const String family = '\u{1F468}\u200D\u{1F469}\u200D\u{1F467}'; // 8 units
    final TextEditingValue out = f.formatEditUpdate(_v(''), _v('ab$family'));
    expect(out.text, 'ab');
  });

  test('field full + collapsed caret → a typed key is a no-op (no tail '
      'truncation)', () {
    final TextEditingValue old = _v('abcde', caret: 1);
    expect(f.formatEditUpdate(old, _v('aXbcde', caret: 2)), same(old));
  });
}
