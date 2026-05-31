// Phase 5.3 — Numeric field validators.
//
// Pure functions — no side effects, no dependencies beyond AppLocalizations.
// Used by [ServiceForm] for duration and price fields.
//
// All rules mirror the backend `CreateServiceDefinitionRequest` constraints:
//   - durationMinutes: required, integer, 1–1440 (1 min to 24 h).
//   - price: required, integer UAH, non-negative.

import 'package:beautica_mobile/l10n/app_localizations.dart';

/// Returns null when [v] is a valid duration in minutes, or a localised error.
///
/// Validation rules:
///   - Not null and not blank (required field).
///   - Must parse as an integer.
///   - Must be > 0 (zero is rejected: no zero-length service).
///   - Must be ≤ 1440 (24 hours).
String? validateDurationMinutes(String? v, AppLocalizations l10n) {
  if (v == null || v.trim().isEmpty) return l10n.errRequired;
  final int? n = int.tryParse(v.trim());
  if (n == null || n <= 0) return l10n.errDurationPositive;
  if (n > 1440) return l10n.errDurationMax;
  return null;
}

/// Returns null when [v] is a valid price in UAH, or a localised error.
///
/// Validation rules:
///   - Not null and not blank (required field).
///   - Must parse as an integer (digits-only input formatter enforces this at
///     the field level, but validation is the authority for the Form submit).
///   - Must be ≥ 0 (negative prices are rejected).
String? validatePriceUah(String? v, AppLocalizations l10n) {
  if (v == null || v.trim().isEmpty) return l10n.errRequired;
  final int? n = int.tryParse(v.trim().replaceAll(' ', '').replaceAll('₴', ''));
  if (n == null || n < 0) return l10n.errPriceNonNegative;
  return null;
}
