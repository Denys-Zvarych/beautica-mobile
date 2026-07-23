// Shared booking price label formatters.
//
// Two callers, one set of conventions (en-dash band, «₴» suffix, no decimals):
//
//   * [formatBookingTotals] — the multi-service «Разом» total on the booking
//     CREATION flow, built from summed min/max across a selection.
//   * [formatBookingPrice]  — the single, already-BOOKED price frozen on one
//     `Booking` record, rendered on every surface that shows a booking's
//     money (client card, master timeline card, «Деталі запису» recap, the
//     add-to-calendar event description).
//
// NOTE — `ServicePriceDisplay.format` (`service_price_display.dart`) renders a
// SERVICE's range with `' - '` (hyphen-space). That difference is deliberate
// and must not be unified: bookings use the en-dash, services use the hyphen.
// What the three DO share is [isRenderablePrice] + [priceUnavailableLabel]:
// every money figure this app stringifies passes the same gate, so a hostile
// or merely buggy wire value cannot render as «Infinity ₴» / «-0 ₴» / «1e+21 ₴»
// on one surface just because it was hardened on another. The predicate lives
// here because this file is the family's documented home for the conventions;
// `service_price_display.dart` imports it rather than growing a second copy.
// The two discovery search cards (`master_result_card.dart`,
// `salon_result_card.dart`) build their labels from l10n rather than from these
// formatters — their ARB placeholders are `"type": "int"` — so they import
// [renderableWholePrice], the int-coercing sibling of the same gate, for the
// identical reason: one predicate, no second copy.
//
// Extracts the identical price-band + duration string building that was
// duplicated across all FOUR «Разом» surfaces: `_BookingTotals.from`
// (`booking_recap.dart`), `ScheduleConfirmBar._totals`
// (`schedule_confirm_bar.dart`, salon flow),
// `IndependentScheduleConfirmBar._totals` and `_AssignConfirmBar._totals`
// (`salon_master_selection_screen.dart`). Each caller keeps only its own
// per-model field access (they read different types — `MasterService` vs
// `SalonCatalogService` vs `BookingSelection`) and maps onto
// [BookingTotalTerm]; the summation, the per-term gate and the
// "X ₴ / X–Y ₴" + duration formatting all live here, in
// [formatBookingTotalsFromTerms].
//
// PREFER [formatBookingTotalsFromTerms] over calling [formatBookingTotals] on
// pre-summed figures. The latter can only re-check the SUMS, and `+` is not
// protective: two out-of-range terms that cancel (`1e30 + -1e30 == 0.0`) sail
// through a sum-level check and state a fictional «0 ₴». Summing in the caller
// and handing the totals over is exactly the shape that let «Infinity ₴» /
// «-0 ₴» / «1e+30 ₴» reach the salon assign-confirm bar.
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
///
/// Unrenderable sums follow [formatBookingPrice]'s rules exactly — see
/// [isRenderablePrice]. Summation is NOT protective here: `+` propagates
/// `Infinity` and lets one negative term drag [minSum] below zero, so a
/// per-service figure this app never rendered can still surface in the total.
/// The two formatters share one set of conventions by this file's own header;
/// hardening one and not the other is precisely the drift it exists to stop.
({String priceLabel, String? durationLabel}) formatBookingTotals({
  required double minSum,
  required double maxSum,
  required int minutes,
}) {
  final String priceLabel;
  if (!isRenderablePrice(minSum)) {
    // No floor left to fall back to — state nothing rather than a wrong figure.
    priceLabel = priceUnavailableLabel;
  } else if (!isRenderablePrice(maxSum) || maxSum == minSum) {
    // An unrenderable ceiling lands in the degenerate-band case the callers
    // already render correctly: "this selection has one price".
    priceLabel = '${minSum.toStringAsFixed(0)} $bookingPriceCurrencySuffix';
  } else {
    priceLabel =
        '${minSum.toStringAsFixed(0)}–${maxSum.toStringAsFixed(0)} '
        '$bookingPriceCurrencySuffix';
  }
  return (
    priceLabel: priceLabel,
    durationLabel: minutes > 0 ? DurationMinutes.format(minutes) : null,
  );
}

/// One service's contribution to a «Разом» total: its price floor, its price
/// ceiling (equal to [min] when the service is not a RANGE) and its duration.
///
/// Callers map their own model — `MasterService`, `SalonCatalogService`,
/// `BookingSelection` — onto this shape; the per-model field access is the only
/// part that legitimately differs between the four confirm/recap surfaces.
typedef BookingTotalTerm = ({double min, double max, int minutes});

/// [formatBookingTotals] with the PER-TERM [isRenderablePrice] gate applied.
///
/// ## Why summing first and checking the sum is not enough
///
/// `+` is not protective. Two out-of-range figures that cancel
/// (`1e30 + -1e30 == 0.0`, verified) clear any sum-level check and render a
/// confident, entirely fictional «0 ₴» — on the very screen where the client is
/// agreeing to a price. `Infinity` likewise propagates through the accumulator,
/// and one negative term silently drags [minSum] below zero.
///
/// So every TERM is gated on the way into the accumulator, and the sums are
/// re-checked by [formatBookingTotals] on the way out (an in-range set of terms
/// can still add up out of range). Both must hold for a figure to be stated.
///
/// ## An unstatable term poisons the WHOLE band
///
/// The bad term is not dropped. Dropping it would UNDERSTATE the price the
/// client is agreeing to, which is the harm — not a mitigation of it. The whole
/// price band therefore collapses to [priceUnavailableLabel]. The DURATION
/// label is unaffected: it is summed from ints, shares none of the failure
/// modes above, and staying silent about the time as well would degrade a
/// surface that is still perfectly able to state it.
({String priceLabel, String? durationLabel}) formatBookingTotalsFromTerms(
  Iterable<BookingTotalTerm> terms,
) {
  double minSum = 0;
  double maxSum = 0;
  int minutes = 0;
  bool renderable = true;
  for (final BookingTotalTerm term in terms) {
    if (!isRenderablePrice(term.min) || !isRenderablePrice(term.max)) {
      renderable = false;
    }
    minSum += term.min;
    maxSum += term.max;
    minutes += term.minutes;
  }
  final ({String priceLabel, String? durationLabel}) totals =
      formatBookingTotals(minSum: minSum, maxSum: maxSum, minutes: minutes);
  return (
    priceLabel: renderable ? totals.priceLabel : priceUnavailableLabel,
    durationLabel: totals.durationLabel,
  );
}

/// Builds ONE booking's price label from the pair frozen at booking time.
///
/// [price] is `Booking.price` — the floor (`priceAtBooking` on the wire).
/// [priceMax] is `Booking.priceMax` — the ceiling (`priceMaxAtBooking`).
///
/// ## `priceMax == null` is a SINGLE PRICE, not a missing value
///
/// The backend sets `priceMaxAtBooking` only when the master genuinely left
/// this service as a `RANGE` (no `priceOverride`) at the moment the booking was
/// made. A null ceiling therefore means "this booking has one price" — it is
/// not an error, not a degraded read, and not something to fill in. The
/// decision is made SERVER-side, once, and frozen; the client must never
/// re-derive a band from `priceType`/`priceOverride`/the service's current
/// catalogue state, because those describe the service TODAY, not what was
/// agreed then.
///
/// Output, matching [formatBookingTotals]'s conventions exactly (en-dash, no
/// decimals, trailing [bookingPriceCurrencySuffix]):
///
/// ```text
///   price 300, priceMax null  ->  "300 ₴"
///   price 300, priceMax 500   ->  "300–500 ₴"
///   price 300, priceMax 300   ->  "300 ₴"      (degenerate band collapses)
/// ```
///
/// A ceiling at or BELOW the floor collapses to the floor alone: a degenerate
/// band carries no more information than the single figure, and an inverted
/// one («500–300 ₴») would be worse than useless if a bad row ever reached the
/// client. Callers still gate on `BookingDisplayX.showsPrice` — this formatter
/// never decides WHETHER money should be shown, only how it reads.
///
/// ## Unrenderable inputs are treated as ABSENT, never stringified
///
/// Both figures arrive off the wire as JSON numbers, and `jsonDecode` is
/// permissive in ways that matter here: `jsonDecode('1e400')` returns
/// `double.infinity` WITHOUT throwing, so a hostile or merely buggy payload
/// can hand this function a value `toStringAsFixed(0)` will happily render as
/// «Infinity ₴» / «300–Infinity ₴». A negative pair renders «-500–-300 ₴»,
/// where the minus signs collide with the band's en-dash into something
/// unreadable, and anything at or above [_exponentNotationThreshold] degrades
/// to «1e+21–2e+21 ₴» because `toStringAsFixed` falls back to exponent
/// notation there. None of these are hypothetical UI blemishes: this exact
/// string is written into a device calendar event via `add_2_calendar`, i.e.
/// it LEAVES the app and lands in another vendor's data store.
///
/// So [isRenderablePrice] gates every figure before it is stringified, and an
/// unrenderable one is treated as ABSENT rather than printed:
///
///   * an unrenderable CEILING collapses to the floor alone — identical to the
///     `priceMax == null` and `priceMax <= price` paths above. This adds no new
///     state to the contract: "no usable ceiling" is already a first-class,
///     documented meaning here ("this booking has one price"), so a garbage
///     ceiling simply lands in a case the callers already render correctly.
///   * an unrenderable FLOOR has no floor left to fall back TO, so it returns
///     the neutral [priceUnavailableLabel] — with NO «₴» suffix,
///     because appending the currency would assert a hryvnia amount we do not
///     have. Better to show nothing than to show a wrong number, and this
///     branch is unreachable for every well-formed booking the backend emits.
///
/// This is display integrity, not DoS: there is no crash risk today either
/// way, because both cards cap the label's width and scale it down rather
/// than clipping it.
String formatBookingPrice({required double price, double? priceMax}) {
  if (!isRenderablePrice(price)) return priceUnavailableLabel;
  final double? max = priceMax;
  if (max == null || !isRenderablePrice(max) || max <= price) {
    return '${price.toStringAsFixed(0)} $bookingPriceCurrencySuffix';
  }
  return '${price.toStringAsFixed(0)}–${max.toStringAsFixed(0)} '
      '$bookingPriceCurrencySuffix';
}

/// Rendered in place of a figure that cannot be stated honestly — see
/// [formatBookingPrice]'s "Unrenderable inputs" section. A bare typographic
/// em-dash: identical in UA and EN (so it needs no ARB key, which this pure-
/// Dart file could not resolve anyway) and carrying no currency claim.
///
/// Shared by the whole formatter family (bookings AND `ServicePriceDisplay`),
/// hence the un-prefixed name.
const String priceUnavailableLabel = '—';

/// The magnitude at which `double.toStringAsFixed(0)` stops emitting plain
/// digits and falls back to exponent notation («1e+21»). Verified in Dart:
/// `(1e20).toStringAsFixed(0)` is `'100000000000000000000'` while
/// `(1e21).toStringAsFixed(0)` is `'1e+21'`.
const double _exponentNotationThreshold = 1e21;

/// 2^63 — the magnitude at which `double.round()` stops being faithful.
///
/// Dart's `int` is a fixed 64-bit signed integer on the VM, so `round()` does
/// not overflow and does not throw for a merely-large finite double: it
/// SATURATES to `9223372036854775807`. Verified: `(9.3e18).round()`,
/// `(1e20).round()` and `(1e30).round()` all return that same value.
const double _int64RoundThreshold = 9223372036854775808.0;

/// [value] as a whole-hryvnia `int`, or `null` when it cannot be stated
/// honestly.
///
/// The `int`-typed sibling of [isRenderablePrice], for the surfaces whose ARB
/// placeholders are declared `"type": "int"` — the two discovery search cards
/// («{price} ₴», «{min}–{max} ₴», «від {price} ₴») — and which therefore must
/// coerce the wire `double` before handing it to l10n. That coercion adds a
/// THIRD failure mode on top of the two [isRenderablePrice] documents, and the
/// first of them is worse in kind than anything on the booking surfaces:
///
///   * `round()` on `Infinity`/`NaN` THROWS `UnsupportedError: Infinity or NaN
///     toInt`. On a result card the call sits inside `build()`, so a malformed
///     payload does not merely misprint a figure — it replaces a row of the
///     search results list, one of the app's most-hit surfaces, with an error
///     widget. It is reachable from the wire: `jsonDecode('1e400')` yields
///     `double.infinity` WITHOUT throwing, and `search_mapper.dart` passes the
///     decoded `minEffectivePrice`/`priceMin`/`priceMax` straight through
///     unclamped.
///   * `round()` saturating (above) prints the flatly fabricated
///     «9223372036854775807 ₴».
///
/// ## Why [isRenderablePrice] alone does NOT close the second one
///
/// Its ceiling is calibrated for `toStringAsFixed(0)`, which keeps emitting
/// plain digits all the way to [_exponentNotationThreshold] (1e21). `round()`
/// saturates ~100× earlier, at [_int64RoundThreshold] (≈9.22e18). So `1e20`
/// passes [isRenderablePrice] and still saturates. The extra bound is applied
/// HERE, once, rather than being re-derived at each call site.
///
/// ## Unrenderable ⇒ `null` ⇒ ABSENT, never stringified
///
/// Same treatment [formatBookingPrice] gives an unrenderable ceiling, and it is
/// what lets the callers keep their existing branch structure: both search
/// cards already have a first-class, correct "this bound is not known"
/// rendering — hide the price line entirely, or collapse the band to the single
/// known bound. Routing a garbage figure into that existing path is better than
/// printing [priceUnavailableLabel] on a card that shows no «—» anywhere else.
int? renderableWholePrice(double? value) {
  if (value == null) return null;
  if (!isRenderablePrice(value) || value >= _int64RoundThreshold) return null;
  return value.round();
}

/// Whether [value] can be stated as an honest, plain-digit hryvnia figure.
///
/// One predicate for the whole family rather than scattered checks: a price is
/// renderable iff it is finite (excludes `Infinity`/`NaN`), not negative (a
/// booking never costs less than nothing, and a leading minus collides with
/// the band's en-dash), and below the point where `toStringAsFixed(0)` abandons
/// plain digits.
///
/// NEGATIVITY IS TESTED WITH [double.isNegative], NOT `value >= 0`
/// ----------------------------------------------------------------
/// IEEE-754 has two zeros and `-0.0 >= 0` is `true`, so the arithmetic
/// comparison waved negative zero straight through — and
/// `(-0.0).toStringAsFixed(0)` is `'-0'`, i.e. exactly the leading minus this
/// guard exists to keep out of the en-dash band («-0–500 ₴»). It is reachable
/// from the wire: `jsonDecode('-0.0')` yields `-0.0` and `booking_mapper.dart`
/// passes `priceAtBooking` through unclamped. `(-0.0).isNegative` is `true`,
/// which is the whole point of using it here. (`NaN.isNegative` is `false`,
/// but `isFinite` has already rejected NaN by then.)
bool isRenderablePrice(double value) =>
    value.isFinite && !value.isNegative && value < _exponentNotationThreshold;
