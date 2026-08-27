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
// ── `categories` (MULTI) AND `salonName` ARE LIVE ───────────────────────────
//
// Backend commit `b0c924f` reversed the category axis: both
// `FavoriteMasterResponse` and `FavoriteSalonResponse` now carry `categories`
// — every distinct platform category the provider offers — instead of the
// single `categoryCode`/`categoryLabel` scalar pair the field used to mirror
// (that scalar came from the client's most recently BOOKED service with the
// provider, which meant a freshly-favourited-but-never-booked row carried
// nothing at all). Mapped onto [categories] below via `FavoriteMapper`;
// `FavoriteMasterResponse` additionally carries `salonId`/`salonName`
// (mapped onto [salonName]) — verified against the regenerated client,
// 2026-08-25.
//
//   * [categories] is what the category filter unions over — a provider with
//     several categories appears under each of them. See
//     `FavoriteChoice.from` in `favorites_filter.dart`.
//   * `salonName` draws the accentDeep affiliation line on a salon-affiliated
//     master (see [isAffiliated]). Since backend commit `ca2c98a`, a
//     salon-affiliated master's `street`/`buildingNo`/`locationNote` are the
//     EMPLOYING SALON's, not nulled — the address block renders them
//     unconditionally now (see `FavoriteMasterCard` in `favorite_cards.dart`),
//     with the affiliation line naming the place one register above.

import 'package:flutter/foundation.dart';

import 'favorite_target.dart';

/// One category a favourite is filed under — a `(code, label)` pair mirroring
/// the backend's `FavoriteCategoryView`.
///
/// A tiny value type rather than two parallel lists on [FavoriteItem]: the id
/// and label travel together everywhere they are used (equality, the chip
/// `Key`, the chip label), and parallel lists invite index-skew bugs the
/// moment one side is filtered or reordered independently of the other.
@immutable
class FavoriteCategory {
  const FavoriteCategory({required this.id, required this.label});

  /// Server enum-ish token (`MANICURE`), compared for equality/selection
  /// only — never rendered. Mirrors `FavoriteCategoryView.code`.
  final String id;

  /// Ukrainian display text, rendered on the filter chip. Mirrors
  /// `FavoriteCategoryView.label`.
  final String label;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FavoriteCategory && other.id == id && other.label == label;

  @override
  int get hashCode => Object.hash(id, label);

  @override
  String toString() => 'FavoriteCategory($id, $label)';
}

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
    this.categories = const <FavoriteCategory>[],
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
  /// `null` for an independent master by design: the absence is the answer to
  /// "where do they work" (nowhere in particular), which is why no «Приватний
  /// майстер» label exists. Mapped from `FavoriteMasterResponse.salonName`,
  /// sanitized — see the file header and `FavoriteMapper`.
  final String? salonName;

  /// Every distinct platform category this provider offers — what the
  /// category filter unions over. A provider offering both manicure and
  /// pedicure carries both, and shows up under either chip.
  ///
  /// Carried on the ITEM rather than resolved against a hardcoded vocabulary:
  /// the design preview used a const `kFavCategories` list, but production
  /// categories are server-owned and admin-editable, so the filter derives its
  /// chips from the data it actually has. Mapped from the DTO's `categories`
  /// (backend commit `b0c924f` — every distinct category the provider offers,
  /// not the client's most-recently-booked one), both-or-neither per pair and
  /// deduped by id — see `FavoriteMapper`.
  ///
  /// Non-null and defaults to empty — never null-check this before iterating.
  /// Empty means "reachable only under «Всі»", not "unknown".
  final List<FavoriteCategory> categories;

  /// Resolved city display string (`cityLabel`). Sanitized by the mapper.
  final String? cityLabel;

  /// Resolved district display string (`districtLabel`). Often null — plenty of
  /// towns have no district subdivision at all. Sanitized by the mapper.
  final String? districtLabel;

  /// Street name — for a salon, a master who owns their premises, OR (since
  /// backend `ca2c98a`) a salon-affiliated master, in which case this is their
  /// EMPLOYING SALON's street. The client renders it unconditionally — see
  /// `FavoriteMasterCard` in `favorite_cards.dart`.
  final String? street;

  /// Building number. Rides on [street] or is dropped — `buildStreetLine`
  /// never renders one on its own.
  final String? buildingNo;

  /// The provider's free-text arrival note (backend `@Size(max = 1000)`).
  /// Rendered whenever present, alongside [street] — for a salon-affiliated
  /// master this is the salon's own note. The one line on the card allowed to
  /// wrap (to exactly 2 lines).
  final String? locationNote;

  /// True when this row is a master.
  bool get isMaster => kind == FavoriteKind.master;

  /// True when this master works at a salon — the only thing that draws the
  /// affiliation line.
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
          // `List`'s own `==` is identity, not element-wise — a plain
          // `other.categories == categories` here would silently break
          // `_FavoritesScreenState._viewModelFor`'s memoisation the moment two
          // distinct-but-equal lists were compared. `listEquals` (already
          // imported via `package:flutter/foundation.dart` for `@immutable`)
          // does deep, order-sensitive element equality via [FavoriteCategory]
          // above.
          listEquals(other.categories, categories) &&
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
    // Combine the list's element hashes into one int first — Object.hash
    // takes discrete arguments, not a nested Iterable.
    Object.hashAll(categories),
    cityLabel,
    districtLabel,
    street,
    buildingNo,
    locationNote,
  );
}
