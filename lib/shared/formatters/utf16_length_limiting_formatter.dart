// Phase 424 (security LOW-1) — cap a text field at a UTF-16 code-unit budget.
//
// Flutter's own `maxLength` / `LengthLimitingTextInputFormatter` count
// grapheme clusters, but the backend's `@Size(max = …)` counts Java
// `String.length()` — UTF-16 code units. One emoji is 1 grapheme yet 2+ units,
// so 300 emoji pass a 500-grapheme cap and earn a 400. This formatter counts
// what the server counts.
//
// The cut walks GRAPHEME CLUSTERS, so it never leaves a lone surrogate or half
// a ZWJ sequence in the field: a cluster that would straddle the budget is
// dropped whole.

import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:flutter/services.dart';

/// Rejects any edit past [maxUnits] UTF-16 code units (`String.length`),
/// truncating a long paste at the last whole grapheme cluster that fits.
class Utf16LengthLimitingFormatter extends TextInputFormatter {
  const Utf16LengthLimitingFormatter(this.maxUnits)
    : assert(maxUnits >= 0, 'maxUnits must be non-negative');

  /// The budget, in UTF-16 code units.
  final int maxUnits;

  /// [text] cut to at most [maxUnits] code units on a grapheme boundary.
  static String truncate(String text, int maxUnits) {
    if (text.length <= maxUnits) return text;
    final StringBuffer out = StringBuffer();
    int units = 0;
    for (final String cluster in text.characters) {
      if (units + cluster.length > maxUnits) break;
      out.write(cluster);
      units += cluster.length;
    }
    return out.toString();
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.length <= maxUnits) return newValue;
    // Mirrors `LengthLimitingTextInputFormatter`: once the field is full, a
    // typed key (collapsed caret) is a no-op rather than a tail-truncation
    // that would silently eat the end of the text.
    if (oldValue.text.length == maxUnits && oldValue.selection.isCollapsed) {
      return oldValue;
    }
    final String cut = truncate(newValue.text, maxUnits);
    return TextEditingValue(
      text: cut,
      selection: TextSelection.collapsed(offset: cut.length),
    );
  }
}
