// Phase 5.3 — Numeric field validators.
// Hardened (2026-06-03) — bounds now mirror the just-shipped backend
// `CreateServiceDefinitionRequest` contract EXACTLY so bad input is rejected
// client-side BEFORE submit, with a specific message per field:
//   - baseDurationMinutes: integer, required, > 0, max 480 (8 h).
//   - bufferMinutesAfter: integer, optional, 0–120.
//   - price / priceMin / priceMax: decimal, > 0 (min 0.01), max 99999999.99,
//     at most 2 decimal places.
//   - RANGE pricing: priceMax must be STRICTLY greater than priceMin.
//
// Pure functions — no side effects, no Flutter dependency beyond
// AppLocalizations (the l10n object is itself pure data). Each function is
// independently unit-testable (mobile-qa M-rule).

import 'package:beautica_mobile/l10n/app_localizations.dart';

// ---------------------------------------------------------------------------
// Backend-contract bounds (single source of truth for both the validators and
// the field input formatters). Kept as named constants so a future contract
// change is a one-line edit and the unit tests can import the same numbers.
// ---------------------------------------------------------------------------

/// Maximum service duration accepted by the backend: 480 minutes (8 hours).
///
/// This is the bound the originating bug violated (duration = 1123 sailed past
/// the old 1440 cap and only failed server-side).
const int kDurationMaxMinutes = 480;

/// Maximum after-appointment buffer accepted by the backend: 120 minutes.
const int kBufferMaxMinutes = 120;

/// Minimum positive price accepted by the backend: 0.01 (one kopeck).
const double kPriceMin = 0.01;

/// Maximum price accepted by the backend: 99 999 999.99.
const double kPriceMax = 99999999.99;

// Hoisted RegExp — a decimal with up to two fractional digits and no sign.
// Allocated once at class-load, never per keystroke.
//   123        ✓
//   123.4      ✓
//   123.45     ✓
//   123.456    ✗ (3 decimals)
//   12,5       ✗ (comma — caller must normalise first)
//   -5         ✗ (sign)
final RegExp _kDecimalUpToTwoDp = RegExp(r'^\d+(\.\d{1,2})?$');

// ---------------------------------------------------------------------------
// Duration
// ---------------------------------------------------------------------------

/// Returns `null` when [v] is a valid duration in minutes, or a localised error.
///
/// Validation rules (mirror `baseDurationMinutes`):
///   - Required: null / blank / whitespace-only → [AppLocalizations.errRequired].
///   - Must parse as an INTEGER (no decimals, no spaces inside).
///   - Must be > 0 → [AppLocalizations.errDurationPositive].
///   - Must be ≤ [kDurationMaxMinutes] → [AppLocalizations.errDurationMax].
String? validateDurationMinutes(String? v, AppLocalizations l10n) {
  final String t = (v ?? '').trim();
  if (t.isEmpty) return l10n.errRequired;
  // Reject any non-digit (a stray '.' / sign / space → non-integer input).
  final int? n = int.tryParse(t);
  if (n == null) return l10n.errDurationPositive;
  if (n <= 0) return l10n.errDurationPositive;
  if (n > kDurationMaxMinutes) return l10n.errDurationMax;
  return null;
}

// ---------------------------------------------------------------------------
// Buffer (optional)
// ---------------------------------------------------------------------------

/// Returns `null` when [v] is a valid buffer in minutes (or empty), or a
/// localised error.
///
/// Validation rules (mirror `bufferMinutesAfter`, optional 0–120):
///   - Empty / null / whitespace-only → null (optional field).
///   - Must parse as an INTEGER.
///   - Must be ≥ 0 and ≤ [kBufferMaxMinutes] → [AppLocalizations.errBufferRange].
String? validateBufferMinutes(String? v, AppLocalizations l10n) {
  final String t = (v ?? '').trim();
  if (t.isEmpty) return null; // optional
  final int? n = int.tryParse(t);
  if (n == null || n < 0 || n > kBufferMaxMinutes) {
    return l10n.errBufferRange;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Price (decimal, up to 2 dp)
// ---------------------------------------------------------------------------

/// Parses a user-entered price string into a double, normalising a comma
/// decimal separator (Ukrainian keyboards often emit ',') and stripping any
/// thin-space grouping or the '₴' glyph. Returns `null` when the cleaned
/// string is not a well-formed positive decimal with ≤ 2 fractional digits.
///
/// Exposed for the form's submit path so the parsed value is computed exactly
/// the same way the validator checked it (no drift between check and parse).
double? parsePrice(String? v) {
  final String cleaned = (v ?? '')
      .trim()
      .replaceAll(' ', '') // non-breaking space grouping
      .replaceAll(' ', '')
      .replaceAll('₴', '')
      .replaceAll(',', '.');
  if (cleaned.isEmpty) return null;
  if (!_kDecimalUpToTwoDp.hasMatch(cleaned)) return null;
  return double.tryParse(cleaned);
}

/// Returns `null` when [v] is a valid price, or a localised error.
///
/// Shared by the FIXED amount and the RANGE min/max fields. [requiredMessage]
/// lets the caller pick the right "this field is required" copy per field
/// (e.g. "вкажіть мінімальну ціну" for the range floor).
///
/// Validation rules (mirror `price` / `priceMin` / `priceMax`):
///   - Required: blank / whitespace-only → [requiredMessage].
///   - Must be numeric with at most 2 decimal places → [AppLocalizations.errPriceDecimals].
///   - Must be ≥ [kPriceMin] (0.01) → [AppLocalizations.errPricePositive].
///   - Must be ≤ [kPriceMax] → [AppLocalizations.errPriceMax].
String? validatePriceAmount(
  String? v,
  AppLocalizations l10n, {
  required String requiredMessage,
}) {
  final String t = (v ?? '').trim();
  if (t.isEmpty) return requiredMessage;
  final double? n = parsePrice(t);
  if (n == null) return l10n.errPriceDecimals;
  if (n < kPriceMin) return l10n.errPricePositive;
  if (n > kPriceMax) return l10n.errPriceMax;
  return null;
}

/// Cross-field validator for RANGE pricing: [maxRaw] must be present, valid,
/// and STRICTLY greater than [minRaw].
///
/// Returns `null` when the pair is valid. Checks, in order:
///   1. [maxRaw] required → [AppLocalizations.errPriceMaxRequired].
///   2. [maxRaw] well-formed decimal in-bounds (delegates to
///      [validatePriceAmount]); the returned message surfaces directly.
///   3. max > min (only when both parse) → [AppLocalizations.errPriceMaxGtMin].
///
/// [minRaw] is read but not re-validated for its own required/format errors —
/// those surface on the min field via its own [validatePriceAmount] call.
String? validatePriceMax(
  String? maxRaw,
  String? minRaw,
  AppLocalizations l10n, {
  required String requiredMessage,
}) {
  // Required + format + bounds first (reuse the shared amount validator).
  final String? amountErr = validatePriceAmount(
    maxRaw,
    l10n,
    requiredMessage: requiredMessage,
  );
  if (amountErr != null) return amountErr;

  final double? min = parsePrice(minRaw);
  final double? max = parsePrice(maxRaw);
  // Cross-field check only when both parse cleanly (the min field reports its
  // own format/required error otherwise).
  if (min != null && max != null && max <= min) {
    return l10n.errPriceMaxGtMin;
  }
  return null;
}
