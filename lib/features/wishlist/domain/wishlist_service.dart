// Phase 237 — BEAUTY WISH LIST domain model.
// Phase F extends it with a real discriminated union over [sourceType].
//
// One saved favourite service, as returned by `GET /favorites/services`
// (backend 247). Hydrated by [WishlistMapper.fromDto]; the generated DTO types
// never escape the data layer. Two SHAPES ride the one model:
//
//   • MASTER — a service chosen from a specific master's assignment. Carries
//     `masterServiceId` / `masterId` / `masterName` / `masterAvatarUrl`; the
//     salon fields are null. This is the ORIGINAL (and, until Phase F, only)
//     shape — every pre-existing fixture in this feature's tests constructs
//     one WITHOUT setting [sourceType] at all, relying on its
//     `@Default(WishlistSourceType.master)` to keep them compiling and
//     behaving identically. That default is deliberate, not an oversight: it
//     is what makes this a zero-regression addition for every MASTER row
//     already shipped, rather than a ripple through every existing test file.
//   • SALON — a service favourited straight off a salon's public catalogue,
//     with no master chosen yet. Carries `salonId` / `salonName` /
//     `salonAvatarUrl` / `serviceDefId`; the master fields are null.
//
// [WishlistMapper] enforces a PER-ARM null-guard: a MASTER row still requires
// `masterServiceId` + `masterId`, a SALON row requires `salonId` +
// `serviceDefId` — see that file's header for the guard itself and the
// drop-the-row-not-the-list policy it applies on either arm's failure.
//
// `masterInitials` / `displayMasterName` (`wishlist_entry_labels.dart`) are
// MASTER-only and assert against being called on a SALON row — use
// `displayTitle` / `attributionIcon` / `avatarImageUrl` /
// `avatarFallbackIcon` for anything that must render correctly on both arms.
//
// ## FIXED passes the wire string through; RANGE is formatted BY THE CLIENT —
// MASTER ROWS ONLY. A SALON row's [priceLabel] is [priceDisplay] VERBATIM on
// every price shape, FIXED or RANGE, with no exception:
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
// ## Why a SALON row skips the RANGE reformat entirely
//
// The MASTER-row reformat above trades wire-string parity for a shorter
// render. A SALON row cannot make that trade: the client saves a SALON
// favourite from that salon's catalogue TILE, and the catalogue tile prints
// the backend's own `PriceDisplayFormatter` output — including the
// `price_max == base_price` case, which the backend renders as «від X до X
// ₴» while this app's own [formatBookingPrice] COLLAPSES an equal-bounds pair
// to the single figure. Re-deriving a SALON row's band here would make the
// passport row disagree with the exact tile the client favourited it from,
// and a backend integration test pins that the two strings are equal. So
// [priceLabel] short-circuits to [priceDisplay] for [WishlistSourceType.salon]
// BEFORE looking at [isRangePrice] at all — verbatim on every price shape,
// not just FIXED.
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

/// Which favourite arm a [WishlistService] row came from — see the file
/// header for the shape each carries.
enum WishlistSourceType {
  /// A service chosen from a specific master's assignment.
  master,

  /// A service favourited straight off a salon's public catalogue, with no
  /// master chosen yet.
  salon,
}

/// One entry in the client's beauty wish list: either a service saved against
/// the specific master who performs it (MASTER), or a service saved straight
/// off a salon's catalogue (SALON) — see [WishlistSourceType] and the file
/// header.
@freezed
abstract class WishlistService with _$WishlistService {
  const factory WishlistService({
    /// Which arm this row is. Defaults to [WishlistSourceType.master] so
    /// every pre-existing MASTER-row fixture across this feature's tests
    /// keeps compiling and behaving identically without being touched — see
    /// the file header.
    @Default(WishlistSourceType.master) WishlistSourceType sourceType,

    /// The `master_services` row id — the favorite's own `target_id` for a
    /// MASTER row, AND one of the two ids a rebook needs. Null for a SALON
    /// row.
    ///
    /// NOT the catalogue service-type id: two masters offering "the same"
    /// service are two distinct wish-list entries at two distinct prices.
    String? masterServiceId,

    /// The performing master's id — the other half of the rebook pair. Null
    /// for a SALON row.
    String? masterId,

    /// The master's display name: first and last, joined in the mapper. Null
    /// for a SALON row.
    ///
    /// Non-null but possibly EMPTY when the wire carries neither part — the
    /// presentation layer decides what an unnamed master looks like, because
    /// that is a copy decision, not a data one.
    String? masterName,

    /// The performing master's avatar URL, or null when unset OR for a SALON
    /// row.
    String? masterAvatarUrl,

    /// `salons.id` — the favourited salon's backend UUID. Null for a MASTER
    /// row.
    String? salonId,

    /// `salons.name`. Null for a MASTER row; possibly empty for a SALON row
    /// whose wire payload carried no name — [displayTitle] owns that
    /// fallback, mirroring [masterName]'s policy.
    String? salonName,

    /// `salons.avatar_url`, or null when unset OR for a MASTER row.
    String? salonAvatarUrl,

    /// `service_definitions.id` — the favorite's own `target_id` for a SALON
    /// row (`favoriteTargetId`). Null for a MASTER row: a MASTER row's
    /// favourite key is its `master_services.id` ([masterServiceId]), not
    /// this.
    String? serviceDefId,

    /// The service's display name, as the master (or the salon's catalogue)
    /// named it.
    required String serviceName,

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
  ///
  /// A SALON row never reaches the RANGE branch below — see the file header's
  /// "Why a SALON row skips the RANGE reformat entirely".
  String get priceLabel {
    if (sourceType == WishlistSourceType.salon) return priceDisplay;
    if (!isRangePrice) return priceDisplay;
    final double? min = priceMin;
    if (min == null) return priceDisplay;
    return formatBookingPrice(price: min, priceMax: priceMax);
  }

  /// The favorite key for this entry — `masterServiceId` for a MASTER row,
  /// `serviceDefId` for a SALON row.
  ///
  /// Exposed as a getter rather than rebuilt at each call site so the
  /// un-favourite path can never key the toggle on `masterId` (or, for a
  /// SALON row, `salonId`) by accident, which would remove the wrong favorite
  /// and still return 204.
  ///
  /// Falls back to '' rather than throwing on a malformed row that somehow
  /// reached the domain layer without its arm's required id — the mapper's
  /// per-arm null-guard is what is actually supposed to keep that from
  /// happening (see `wishlist_mapper.dart`); this is a defensive floor, not
  /// the enforcement point.
  String get favoriteTargetId => switch (sourceType) {
    WishlistSourceType.master => masterServiceId ?? '',
    WishlistSourceType.salon => serviceDefId ?? '',
  };
}
