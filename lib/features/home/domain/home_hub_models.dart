// Phase 13.7 — Home Hub domain models (pure Dart, no Flutter import).
//
// Modelled on the preview's `home_hub_data.dart` shapes. All classes are
// plain immutable value objects until the backend 19.x endpoints land and
// freezed + json_serializable codegen is wired up (TODO 19.x).
//
// The `clientPhone` and `clientCity` fields on [ClientProfileSummary] are PII
// that trigger the ScreenProtectionManager in HomeHubScreen (§ CRITICAL-4).

/// The signed-in client's profile summary (hydrated from GET /users/me via
/// [AuthSession.user]).
class ClientProfileSummary {
  const ClientProfileSummary({
    required this.firstName,
    required this.lastName,
    required this.city,
    required this.phone,
    required this.clientRating,
    required this.memberSinceYear,
  });

  final String firstName;
  final String lastName;
  final String city;
  final String phone;

  /// The client's aggregate rating from masters/salons (two-sided ratings system).
  /// null = no rating yet (backend GET /clients/me/rating not yet shipped).
  /// When rated, shows ★ n.n. Never shows individual comments.
  /// TODO(backend): GET /clients/me/rating (two-sided client rating, excludes comments).
  final double? clientRating;

  final int memberSinceYear;

  String get fullName => '$firstName $lastName';

  String get initials {
    final f = firstName.isEmpty ? '' : firstName[0];
    final l = lastName.isEmpty ? '' : lastName[0];
    return '$f$l';
  }
}

/// A master in the favorites horizontal rail.
class FavoriteMasterItem {
  const FavoriteMasterItem({
    required this.masterId,
    required this.favoriteId,
    required this.name,
    required this.lastServiceName,
    required this.rating,
    required this.reviewCount,
    required this.initials,
  });

  final String masterId;

  /// The ID used for the DELETE /favorites/masters/:id call.
  final String favoriteId;

  final String name;
  final String lastServiceName;
  final double rating;
  final int reviewCount;
  final String initials;
}

/// One past procedure on the BEAUTY TIMELINE rail.
///
/// Phase 110 (13.9) wired this onto `GET /clients/me/timeline` and added
/// three OPTIONAL fields ([categoryKey], [bookingId], [serviceName]) —
/// additive-only, per the project's reuse/no-breaking-change rule: several
/// existing tests construct `TimelineEntry(category: ..., dateLabel: ...)`
/// directly, so none of the new fields may become required.
class TimelineEntry {
  const TimelineEntry({
    required this.category,
    required this.dateLabel,
    this.categoryKey,
    this.bookingId,
    this.serviceName,
  });

  final String category;
  final String dateLabel;

  /// The backend's stable machine key for the service category (e.g.
  /// `"NAIL_SERVICE"`), when the row carries one. Preferred over [category]
  /// for icon resolution via `categoryIconOrNullFor` in
  /// `lib/core/icons/category_icons.dart` — a row with no key (e.g. a
  /// pre-Phase-110 test fixture) falls back to matching [category] by
  /// keyword instead. Null, never `''`: an absent key must be
  /// distinguishable from a genuinely empty one. The literal `"UNKNOWN"`
  /// sentinel (the timeline endpoint's no-category marker) is a valid,
  /// non-null value of this field — normalised to null at the
  /// `beauty_timeline_section.dart` call site, not here.
  final String? categoryKey;

  /// The source booking's id, when the row carries one. Used to navigate to
  /// «Деталі запису» on tile tap; null/empty ⇒ the tile is not tappable.
  /// Never coerced with `?? ''` — see `data/timeline_mapper.dart`'s header.
  final String? bookingId;

  /// The booked service's name, when the row carries one. Not currently
  /// rendered by the compact rail tile; carried through for future use.
  final String? serviceName;
}
