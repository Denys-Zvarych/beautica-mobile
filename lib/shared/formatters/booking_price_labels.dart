// Shared booking "Разом" total label formatter.
//
// Extracts the identical price-band + duration string building duplicated in
// `_BookingTotals.from` (`booking_summary_bar.dart`, independent flow) and
// `ScheduleConfirmBar._totals` (`schedule_confirm_bar.dart`, salon flow).
// Each caller keeps its own per-model summation (they sum different types —
// `MasterService` vs `SalonCatalogService`) and passes the summed
// (minSum, maxSum, minutes) in; only the "X ₴ / X–Y ₴" + duration
// formatting lives here.
//
// Pure Dart — no Flutter imports.

import 'package:beautica_mobile/shared/formatters/duration_minutes.dart';

/// Currency suffix appended to the "Разом" price band ("₴"). Public so
/// callers (and tests) reference this single source of truth instead of
/// hardcoding the literal — this file is pure Dart with no BuildContext/l10n
/// access, so it cannot resolve `AppLocalizations.pricingCurrencySuffix`
/// directly.
const String bookingPriceCurrencySuffix = '₴';

/// Builds the "Разом" price label + optional duration label from pre-summed
/// totals.
///
/// - `priceLabel`: a degenerate band ([minSum] == [maxSum]) collapses to
///   "`<sum> ₴`"; otherwise "`<min>–<max> ₴`".
/// - `durationLabel`: `null` when [minutes] is 0, else `DurationMinutes.format`.
({String priceLabel, String? durationLabel}) formatBookingTotals({
  required double minSum,
  required double maxSum,
  required int minutes,
}) {
  final String priceLabel = minSum == maxSum
      ? '${minSum.toStringAsFixed(0)} $bookingPriceCurrencySuffix'
      : '${minSum.toStringAsFixed(0)}–${maxSum.toStringAsFixed(0)} $bookingPriceCurrencySuffix';
  return (
    priceLabel: priceLabel,
    durationLabel: minutes > 0 ? DurationMinutes.format(minutes) : null,
  );
}
