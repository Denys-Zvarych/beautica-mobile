// Service price label formatter.
//
// The backend supplies a server-formatted [MasterService.priceDisplay] string
// ("750 грн" for FIXED, "від 500 до 800 грн" for RANGE). The Beautica design
// renders the RANGE band as a simple hyphenated range ("500 - 800 грн")
// instead of the "від … до …" phrasing. This helper rebuilds the RANGE label
// client-side from the typed domain fields while leaving the FIXED label as the
// server string.
//
// Pure Dart — no Flutter imports.

import 'package:beautica_mobile/features/services/domain/master_service.dart';

/// Builds the price label shown on a service card / detail row.
///
/// - FIXED: returns the server-formatted [MasterService.priceDisplay]
///   (e.g. `"750 грн"`); falls back to `"<priceMin> грн"` when the server
///   string is empty (pre-V67 data / broken contract).
/// - RANGE: returns a hyphenated band built from the typed fields,
///   `"<priceMin> - <priceMax> грн"` (e.g. `"200 - 600 грн"`), ignoring the
///   server's "від … до …" phrasing. Falls back to the FIXED behaviour when
///   [MasterService.priceMax] is somehow null.
abstract final class ServicePriceDisplay {
  static const String _suffix = 'грн';

  static String format(MasterService service) {
    if (service.priceType == ServicePriceType.range) {
      final double? max = service.priceMax;
      if (max != null) {
        return '${_amount(service.priceMin)} - ${_amount(max)} $_suffix';
      }
    }
    if (service.priceDisplay.isNotEmpty) return service.priceDisplay;
    return '${_amount(service.priceMin)} $_suffix';
  }

  /// Formats a whole-UAH amount without decimals (all service prices are whole
  /// hryvnia in the domain).
  static String _amount(double value) => value.toStringAsFixed(0);
}
