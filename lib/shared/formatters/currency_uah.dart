// Phase 5.2 — Ukrainian hryvnia currency formatter.
//
// Single call site: CurrencyUah.format(price) → "₴ 750".
// Produces the Beautica design-system format: "₴ " prefix + space-grouped
// integer digits (e.g. "₴ 750", "₴ 1 800").
//
// `uk_UA` locale places the currency symbol *after* the number per ISO
// standard. Beautica's approved design (docs/signup-designs/ServiceListScreen,
// `ServiceItem.priceLabel`) uses symbol-first ("₴ 750"), so this formatter
// manually builds the string: "₴ " + thousands-separated integer.
//
// Pure Dart — no Flutter imports.

import 'package:intl/intl.dart';

/// Formats a [price] value as a Ukrainian hryvnia string with a leading
/// hryvnia symbol.
///
/// Examples:
/// ```dart
/// CurrencyUah.format(750)   // "₴ 750"
/// CurrencyUah.format(1800)  // "₴ 1 800"
/// ```
///
/// Kopecks are suppressed — all service prices in the domain are whole UAH.
abstract final class CurrencyUah {
  // Cached grouping formatter (plain thousands-separated integer, no symbol).
  static final NumberFormat _groupFmt = NumberFormat('#,##0', 'uk_UA');

  static String format(double price) {
    // uk_UA uses a narrow no-break space (U+202F) as its thousands separator.
    // Replace it with a regular space so the UI text is easier to match in
    // tests and more predictable across Flutter's text rendering stack.
    final grouped = _groupFmt.format(price).replaceAll(' ', ' ');
    return '₴ $grouped';
  }
}
