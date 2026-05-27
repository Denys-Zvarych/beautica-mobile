// Phase 2.21 — Ukrainian phone number input mask formatter.
//
// Formats in real-time as the user types: +380 XX XXX XX XX.
// No external package — pure Flutter TextInputFormatter.

import 'package:flutter/services.dart';

/// Real-time input mask for Ukrainian mobile numbers: +380 XX XXX XX XX.
///
/// Behaviour:
///   - Strips all non-digit characters from the raw input.
///   - Normalises common paste variants by removing the leading country/area
///     prefix and retaining only the 9 subscriber digits:
///       +380XXXXXXXXX / 380XXXXXXXXX → strip '380'
///       0XXXXXXXXX (local format)    → strip leading '0'
///   - Clamps to 9 subscriber digits (prevents over-typing).
///   - Returns an empty value when no subscriber digits remain — the user can
///     fully clear the field (no locked prefix).
///   - Cursor always placed at the end of the formatted string.
///
/// Output format: +380 OP1OP2 D1D2D3 D4D5 D6D7D8D9
///   blocks: [operator 2] [mid 3] [pair 2] [pair 2]  — total 9 subscriber digits.
///
/// Space positions (0-indexed into subscriber string):
///   before index 2 → after the 2-digit operator code
///   before index 5 → after the 3-digit mid block
///   before index 7 → after the 2-digit hi block
class UaPhoneInputFormatter extends TextInputFormatter {
  const UaPhoneInputFormatter();

  /// Maximum number of subscriber digits (after +380).
  static const int _kSubscriberLength = 9;

  /// Pre-compiled pattern — hoisted to avoid recompiling on every keystroke.
  static final RegExp _kNonDigit = RegExp(r'[^\d]');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // 1. Extract digits only.
    final String digits = newValue.text.replaceAll(_kNonDigit, '');

    // 2. Normalise: remove country/area prefix to get the 9 subscriber digits.
    final String subscriber;
    if (digits.startsWith('380')) {
      subscriber = digits.substring(3);
    } else if (digits.startsWith('0')) {
      // Local format: 0XXXXXXXXX (10 chars) — strip leading zero.
      subscriber = digits.substring(1);
    } else {
      subscriber = digits;
    }

    // 3. Clamp to max subscriber digits.
    final String clamped = subscriber.length > _kSubscriberLength
        ? subscriber.substring(0, _kSubscriberLength)
        : subscriber;

    // 4. Empty → return empty so the user can fully clear the field.
    if (clamped.isEmpty) {
      return const TextEditingValue();
    }

    // 5. Build: +380 XX XXX XX XX
    //    Spaces inserted before subscriber indices 2, 5, 7 (0-indexed):
    //      i == 2 → after operator code (2 digits)
    //      i == 5 → after mid block (3 digits)
    //      i == 7 → after hi block (2 digits)
    final StringBuffer buffer = StringBuffer('+380 ');
    for (int i = 0; i < clamped.length; i++) {
      if (i == 2 || i == 5 || i == 7) buffer.write(' ');
      buffer.write(clamped[i]);
    }

    final String text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
