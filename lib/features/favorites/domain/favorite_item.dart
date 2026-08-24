// Phase 111 (old 13.10) — the domain shape of ONE saved provider on «Улюблені».
//
// Ported from the approved design preview's `FavoriteItem`
// (`docs/signup-designs/ClientFavorites/lib/widgets/favorites_data.dart`),
// which mirrors `GET /favorites/masters` + `GET /favorites/salons` field for
// field. Two API shapes collapse into ONE entity here because the screen is one
// flat list: the card kind is a [kind] discriminator, not a separate type.
//
// Pure Dart — no Flutter import. The presentation layer decides glyphs and
// colours; this layer only says what is known about the provider.
//
// ── TWO FIELDS THE SHIPPED CONTRACT DOES NOT YET CARRY ──────────────────────
//
// [categoryId] / [categoryLabel] and [salonName] are declared here and are
// ALWAYS null off the current mapper, because neither favourites DTO returns
// them (verified against the regenerated client, 2026-08-24 —
// `FavoriteMasterResponse` and `FavoriteSalonResponse` carry id, name, avatar,
// city/district labels, avgRating, street, buildingNo, locationNote and
// nothing else). They are modelled rather than omitted because both are
// REQUIRED by the approved design and the whole screen is built to consume
// them the day the server sends them:
//
//   * `categoryId` is what the category filter selects on. With every item
//     carrying null, [FavoritesFilter] finds zero non-empty categories and
//     hides itself (see its own header) — a control with nothing to offer is
//     not drawn.
//   * `salonName` is what draws the accentDeep affiliation line on a
//     salon-affiliated master. With it null, [isAffiliated] is false and the
//     line is simply absent — which is exactly how the design renders an
//     INDEPENDENT master, so nothing false is asserted. The address block
//     degrades correctly for free: the backend already nulls
//     street/buildingNo/locationNote for a `SALON_MASTER`/`SALON_OWNER` via
//     `MasterType.disclosesOwnAddress`, so an affiliated master renders as
//     "name + rating + locality" and never shows their employer's address.
//
// Wiring them is a one-line mapper change per field once the DTOs grow them.

import 'package:flutter/foundation.dart';

import 'favorite_target.dart';

/// What a favourite points at — a **person** or a **place**.
///
/// Every master type is favouritable (independent, salon-employed, and a salon
/// owner who takes clients personally, per the 2026-08-24 backend change to
/// `FavoriteService.validateMasterTarget`), and so is a salon itself. All
/// master types share ONE card: the client does not care about the employment
/// contract, only whether this person works somewhere and where.
enum FavoriteKind {
  /// A saved master — renders the raised camel portrait disc.
  master,

  /// A saved salon — renders the recessed storefront well.
  salon,
}

/// One saved provider on the «Улюблені» list.
@immutable
class FavoriteItem {
  const FavoriteItem({
    required this.id,
    required this.kind,
    required this.name,
    required this.initials,
    this.rating,
    this.salonName,
    this.categoryId,
    this.categoryLabel,
    this.cityLabel,
    this.districtLabel,
    this.street,
    this.buildingNo,
    this.locationNote,
  }) : assert(
         id.length > 0,
         'FavoriteItem.id must never be empty — an empty '
         'id builds a card that navigates to go_router\'s "page not found". '
         'The mapper DROPS a row with a blank id; it must never reach here.',
       );

  /// `masterId` or `salonId` — the target's own UUID, never a favourite-row id.
  ///
  /// Guaranteed non-empty: `FavoriteMapper` drops any row whose id is absent or
  /// blank rather than substituting `?? ''`. See `favorite_mapper.dart`.
  final String id;

  /// Person or place — decides which card renders and which route a tap pushes.
  final FavoriteKind kind;

  /// The provider's display name — «Марта Гончар» or «Crystal Room №1».
  /// Already run through `sanitizeDisplayText` by the mapper.
  final String name;

  /// Up to two initials for the master portrait disc. Empty when the name
  /// yields none; the salon card ignores this (it draws a storefront glyph).
  final String initials;

  /// `avgRating`, or null when never reviewed.
  ///
  /// A backend `0.00` means "no reviews yet", never "rated zero", so the mapper
  /// folds it to null and [hasRating] is the only thing the UI branches on.
  ///
  /// **Two arithmetic origins, one field, deliberately.** A master's value is
  /// the mean of scores their own clients gave them; a salon's is derived from
  /// its active masters' means scoped to work done at that salon — an average
  /// of averages. The UI does not distinguish them: the difference is
  /// arithmetic depth, not epistemic kind, and the client has no action to take
  /// on it. See `RatingReadout` for the full argument.
  final double? rating;

  /// Master only — the salon this person works at.
  ///
  /// **Always null today** — see the file header. `null` for an independent
  /// master by design: the absence is the answer to "where do they work"
  /// (nowhere in particular), which is why no «Приватний майстер» label exists.
  final String? salonName;

  /// The service category this favourite is filed under — what the category
  /// filter selects on. **Always null today** (see the file header).
  final String? categoryId;

  /// The category's Ukrainian display name, rendered on the filter chip.
  ///
  /// Carried on the ITEM rather than resolved against a hardcoded vocabulary:
  /// the design preview used a const `kFavCategories` list, but production
  /// categories are server-owned and admin-editable, so the filter derives its
  /// chips from the data it actually has. **Always null today.**
  final String? categoryLabel;

  /// Resolved city display string (`cityLabel`). Sanitized by the mapper.
  final String? cityLabel;

  /// Resolved district display string (`districtLabel`). Often null — plenty of
  /// towns have no district subdivision at all. Sanitized by the mapper.
  final String? districtLabel;

  /// Street name — for a salon, or a master who owns their premises.
  ///
  /// The backend suppresses this (and [buildingNo]/[locationNote]) server-side
  /// for a `SALON_MASTER`/`SALON_OWNER` via `MasterType.disclosesOwnAddress`,
  /// so an affiliated master arrives with all three null and the client never
  /// has to hide their employer's address itself.
  final String? street;

  /// Building number. Rides on [street] or is dropped — `buildStreetLine`
  /// never renders one on its own.
  final String? buildingNo;

  /// The provider's free-text arrival note (backend `@Size(max = 1000)`).
  /// Rendered when present, on the same owns-their-own-premises rule as
  /// [street]. The one line on the card allowed to wrap (to exactly 2 lines).
  final String? locationNote;

  /// True when this row is a master.
  bool get isMaster => kind == FavoriteKind.master;

  /// True when this master works at a salon — the only thing that draws the
  /// affiliation line. Always false today; see the file header.
  bool get isAffiliated => salonName != null;

  /// True only when someone has actually been rated. A `0.00` is not a rating.
  bool get hasRating => rating != null && rating! > 0;

  /// The unfavourite target for this row — `DELETE /favorites`.
  FavoriteTarget get target => FavoriteTarget(
    type: isMaster ? FavoriteTargetType.master : FavoriteTargetType.salon,
    id: id,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FavoriteItem &&
          other.id == id &&
          other.kind == kind &&
          other.name == name &&
          other.initials == initials &&
          other.rating == rating &&
          other.salonName == salonName &&
          other.categoryId == categoryId &&
          other.categoryLabel == categoryLabel &&
          other.cityLabel == cityLabel &&
          other.districtLabel == districtLabel &&
          other.street == street &&
          other.buildingNo == buildingNo &&
          other.locationNote == locationNote;

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    name,
    initials,
    rating,
    salonName,
    categoryId,
    categoryLabel,
    cityLabel,
    districtLabel,
    street,
    buildingNo,
    locationNote,
  );
}
