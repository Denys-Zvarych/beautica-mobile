// Service price label formatter.
//
// The backend supplies a server-formatted [MasterService.priceDisplay] string
// ("750 ₴" for FIXED, "від 500 до 800 ₴" for RANGE). The Beautica design
// renders the RANGE band as a simple hyphenated range ("500 - 800 ₴")
// instead of the "від … до …" phrasing. This helper rebuilds the RANGE label
// client-side from the typed domain fields while leaving the FIXED label as the
// server string.
//
// Pure Dart — no Flutter imports.

import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/shared/formatters/booking_price_labels.dart';

/// Builds the price label shown on a service card / detail row.
///
/// - FIXED: returns the server-formatted [MasterService.priceDisplay]
///   (e.g. `"750 ₴"`); falls back to `"<priceMin> ₴"` when the server
///   string is empty (pre-V67 data / broken contract).
/// - RANGE: returns a hyphenated band built from the typed fields,
///   `"<priceMin> - <priceMax> ₴"` (e.g. `"200 - 600 ₴"`), ignoring the
///   server's "від … до …" phrasing. Falls back to the FIXED behaviour when
///   [MasterService.priceMax] is somehow null.
///
/// ## Client-BUILT figures pass [isRenderablePrice] first
///
/// The two amounts this helper stringifies itself arrive off the wire as JSON
/// numbers, and `jsonDecode` admits `Infinity` (`1e400`), `-0.0` and values
/// past `toStringAsFixed`'s exponent threshold without throwing — each of
/// which `toStringAsFixed(0)` renders as «Infinity»/«-0»/«1e+21». That is not
/// a contained UI blemish here: `booking_success_screen.dart` passes this
/// label straight into `buildCalendarDescription`, so the string LEAVES the
/// app into a device calendar event via `add_2_calendar`. Same guard, same
/// absent-not-stringified semantics as `formatBookingPrice`: an unrenderable
/// ceiling collapses to the FIXED path, an unrenderable floor with no server
/// string to fall back to yields [priceUnavailableLabel] and NO «₴» suffix.
///
/// The server's own [MasterService.priceDisplay] is passed through unchanged
/// and deliberately NOT sanitised — it crosses no trust boundary the service
/// name, master name and address on that same calendar description do not
/// already cross.
abstract final class ServicePriceDisplay {
  /// Currency suffix appended to client-built labels ("₴"). Public so callers
  /// (and tests) reference this single source of truth instead of hardcoding
  /// the literal — this file is pure Dart with no BuildContext/l10n access,
  /// so it cannot resolve `AppLocalizations.pricingCurrencySuffix` directly.
  static const String suffix = '₴';

  static String format(MasterService service) {
    final double min = service.priceMin;
    if (service.priceType == ServicePriceType.range) {
      final double? max = service.priceMax;
      if (max != null && isRenderablePrice(min) && isRenderablePrice(max)) {
        return '${_amount(min)} - ${_amount(max)} $suffix';
      }
    }
    if (service.priceDisplay.isNotEmpty) return service.priceDisplay;
    if (!isRenderablePrice(min)) return priceUnavailableLabel;
    return '${_amount(min)} $suffix';
  }

  /// Builds a price label straight from a raw min/max pair, with no
  /// [MasterService] to consult — for a caller holding typed figures with no
  /// service object behind them (e.g. `AppointmentItem`, the server VISIT
  /// response Phase 256 renders the master booking wizard's `done` step
  /// from). Mirrors [format]'s RANGE branch and its no-server-string FIXED
  /// fallback verbatim (same [_amount] / [isRenderablePrice] /
  /// [priceUnavailableLabel] / [suffix]) — [format] itself is unchanged and
  /// stays the right call for anything that has a real [MasterService].
  static String formatRange(double min, double? max) {
    if (max != null && isRenderablePrice(min) && isRenderablePrice(max)) {
      return '${_amount(min)} - ${_amount(max)} $suffix';
    }
    if (!isRenderablePrice(min)) return priceUnavailableLabel;
    return '${_amount(min)} $suffix';
  }

  /// Formats a whole-UAH amount without decimals (all service prices are whole
  /// hryvnia in the domain). Callers MUST have cleared [value] through
  /// [isRenderablePrice] first — see the class doc.
  static String _amount(double value) => value.toStringAsFixed(0);
}
