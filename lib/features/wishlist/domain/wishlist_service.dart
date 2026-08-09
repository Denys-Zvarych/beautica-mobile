// Phase 237 — BEAUTY WISH LIST domain model.
//
// One saved (master, service) pair, as returned by `GET /favorites/services`
// (backend 247). Hydrated by [WishlistMapper.fromDto]; the generated DTO types
// never escape the data layer.
//
// ## FIXED passes the wire string through; RANGE is formatted BY THE CLIENT
//
// This reverses the rule Phase 237 shipped ("never re-derive a band"), by an
// explicit user decision, and only for RANGE. The reason is measurable rather
// than stylistic:
//
//   * the backend's `priceDisplay` renders a RANGE as «від 600 до 900 ₴»,
//   * the app's own frozen convention everywhere else is the en-dash band
//     «600–900 ₴» (`booking_price_labels.dart`, `BookingCard`, the master
//     timeline's price pill),
//   * and the passport page's COMPACT wish-list card has 126 dp of text at
//     360 dp while «від 600 до 900 ₴» measures ~138 dp. The long form does not
//     fit, and the one fix this redesign forbids is an ellipsis.
//
// So a RANGE entry is re-formatted from [priceMin] / [priceMax] through the
// SHARED [formatBookingPrice] — not a second formatter written here. Routing
// through it rather than around it is what carries its hardening across: the
// non-finite / negative / exponent-notation gate ([isRenderablePrice]), the
// «ceiling at or below the floor collapses to the floor» rule, and the
// degenerate-band collapse. A locally-written `'$min–$max ₴'` would have none
// of them and would happily print «Infinity ₴» off a `jsonDecode('1e400')`.
//
// A FIXED entry still renders [priceDisplay] VERBATIM. There is nothing to fix
// about «600 ₴», the backend already owns that string on every other surface,
// and re-deriving it here would fork the rounding for no gain.
//
// [priceLabel] is the ONLY thing a render site may draw. Do not read
// [priceDisplay] directly from presentation.
//
// ## What is derived in PRESENTATION rather than stored here
//
// `masterInitials` and a duration label are formatting concerns, not domain
// state. The preview's fixture carries them pre-baked because it has no
// formatter; the shipped app has one, so they are computed where they are
// rendered. Storing them here would freeze one locale's formatting into the
// domain.
//
// Pure Dart: no Flutter imports in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../shared/formatters/booking_price_labels.dart';

part 'wishlist_service.freezed.dart';

/// One entry in the client's beauty wish list: a service saved against the
/// specific master who performs it.
@freezed
abstract class WishlistService with _$WishlistService {
  const factory WishlistService({
    /// The `master_services` row id — the favorite's own `target_id`, AND one
    /// of the two ids a rebook needs.
    ///
    /// NOT the catalogue service-type id: two masters offering "the same"
    /// service are two distinct wish-list entries at two distinct prices.
    required String masterServiceId,

    /// The performing master's id — the other half of the rebook pair.
    required String masterId,

    /// The service's display name, as the master named it.
    required String serviceName,

    /// The master's display name: first and last, joined in the mapper.
    ///
    /// Non-null but possibly EMPTY when the wire carries neither part — the
    /// presentation layer decides what an unnamed master looks like, because
    /// that is a copy decision, not a data one.
    required String masterName,

    /// The performing master's avatar URL, or null when unset.
    String? masterAvatarUrl,

    /// The service's duration in minutes. Formatted at the render site.
    required int durationMinutes,

    /// The backend's PRE-FORMATTED price — «600 ₴» for FIXED, «від 600 до
    /// 900 ₴» for RANGE.
    ///
    /// Non-null but possibly EMPTY for a legacy definition that carries no
    /// price at all. Empty means "no price to show", which the render site
    /// handles; it never means zero.
    ///
    /// NOT the render string. Presentation draws [priceLabel] — see the file
    /// header for why RANGE diverges.
    required String priceDisplay,

    /// True when the master priced this service as a RANGE rather than FIXED.
    ///
    /// Carried EXPLICITLY rather than inferred from `priceMax != null`. The DTO
    /// happens to null the ceiling for FIXED today, but keying the band on that
    /// would silently turn a RANGE row whose ceiling failed to serialise into a
    /// FIXED one — i.e. it would state a floor as if it were the whole price.
    @Default(false) bool isRangePrice,

    /// The RANGE floor, straight off the wire and NOT pre-gated.
    ///
    /// [priceLabel] runs it through [isRenderablePrice] at the point of use, so
    /// this field stays a faithful record of what the server sent.
    double? priceMin,

    /// The RANGE ceiling, straight off the wire. Null for FIXED.
    double? priceMax,
  }) = _WishlistService;

  const WishlistService._();

  /// The price string BOTH wish-list surfaces render.
  ///
  /// FIXED (and anything without a usable pair of bounds) is [priceDisplay]
  /// verbatim. RANGE is re-formatted into the app's own en-dash band through
  /// the shared [formatBookingPrice] — see the file header for the decision and
  /// the measurement behind it.
  ///
  /// ## Why the fallback is [priceDisplay] and not «—»
  ///
  /// A RANGE row missing [priceMin] is a broken payload, but the backend still
  /// sent a human-readable long form for it. Falling back to that states
  /// something true in the wrong house style; falling back to «—» would throw
  /// away a price the client can actually read. The house style is a
  /// preference, the price is information.
  ///
  /// [formatBookingPrice] itself returns «—» when the FLOOR is unrenderable —
  /// that path is reached only when a floor exists and is garbage, which is the
  /// one case where there is genuinely nothing honest to print.
  String get priceLabel {
    if (!isRangePrice) return priceDisplay;
    final double? min = priceMin;
    if (min == null) return priceDisplay;
    return formatBookingPrice(price: min, priceMax: priceMax);
  }

  /// The favorite key for this entry — `(SERVICE, masterServiceId)`.
  ///
  /// Exposed as a getter rather than rebuilt at each call site so the un-favourite
  /// path can never key the toggle on `masterId` by accident, which would remove
  /// the wrong favorite and still return 204.
  String get favoriteTargetId => masterServiceId;
}
