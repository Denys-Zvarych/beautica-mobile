// Phase 13.6 — Salon domain model (public, client-facing).
//
// Immutable value object representing a salon as returned by the PUBLIC
// `GET /salons/{salonId}` endpoint. Uses `freezed` for value equality,
// copyWith, and pattern matching.
//
// [avgRating] is `null` when [reviewCount] is 0 (no reviews yet) — render a
// muted "—" placeholder rather than "0.0" (mirrors the [Master] domain
// convention).
//
// Pure Dart: no Flutter imports anywhere in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

part 'salon.freezed.dart';

/// A Beautica salon — the canonical domain entity returned by the public
/// salon-read path (`GET /salons/{salonId}`).
@freezed
abstract class Salon with _$Salon {
  const factory Salon({
    required String id,
    required String name,
    String? description,

    /// Legacy free-text city name — kept for backward compat, but no longer
    /// written by the backend since Phase 10.6 (taxonomy fields took over).
    /// Null for any salon created/edited after that.
    String? city,
    String? region,

    /// Legacy free-text address — same backward-compat caveat as [city].
    String? address,

    /// UUID of the taxonomy city the salon is located in (Phase 10.6+).
    /// Raw id only — Beautica's `/locations/*` city lookup is oblast-scoped
    /// and [Salon] carries no `oblastId`, so this cannot be resolved to a
    /// display name client-side; it is not rendered directly.
    String? cityId,

    /// UUID of the taxonomy city district, or `null` when the city has no
    /// districts or none was selected. Same resolution caveat as [cityId].
    String? districtId,

    /// Street name where the salon operates (Phase 10.6+ taxonomy field).
    String? street,

    /// Building number (e.g. "22").
    String? buildingNo,

    /// Apartment/floor/office note (e.g. "2 поверх, офіс 5").
    String? locationNote,

    /// Salon contact phone number.
    ///
    /// Phase 21.2 gap: `GET /salons/{salonId}` returns `PublicSalonResponse`,
    /// which carries NO `phone` field (confirmed against the committed
    /// `tool/openapi/api-spec.json` snapshot — `PublicSalonResponse`'s
    /// property list has no `phone`, unlike the owner/admin-facing
    /// `SalonResponse` returned by `PATCH /salons/{salonId}`, which does).
    /// So this is ALWAYS `null` when [Salon] is built from the public read
    /// path ([SalonMapper.fromDto]) — never a real "salon has no phone on
    /// file" signal. It is populated only after a successful
    /// `PATCH /salons/{salonId}` ([SalonMapper.fromUpdateDto], merged in by
    /// `SalonManagementProfile.save`). The owner/admin edit form seeds this
    /// field as empty-but-editable rather than fabricating a placeholder, and
    /// omits `phone` from the PATCH body entirely unless the viewer actually
    /// typed into it — see `salon_management_profile_notifier.dart` — so an
    /// untouched field can never silently overwrite a real phone number the
    /// mobile client was never told about.
    String? phone,
    String? instagramUrl,
    String? avatarUrl,

    /// Owner-uploadable cover photo. Null renders the gradient placeholder.
    String? coverImageUrl,

    /// Null when [reviewCount] is 0 — no reviews yet.
    double? avgRating,
    @Default(0) int reviewCount,

    /// Whether this is the owner's designated primary salon (Phase 21.1 «Мої
    /// салони» hub — carries the "Основний" badge).
    ///
    /// Additive + nullable so every pre-existing construction site is
    /// unaffected. Only ever populated from `SalonResponse.isPrimary`
    /// ([SalonMapper.fromUpdateDto], which backs both `PATCH
    /// /salons/{salonId}` and `GET /salons/mine`) — the PUBLIC
    /// `PublicSalonResponse` ([SalonMapper.fromDto]) carries no such field
    /// (a client has no business knowing which of a stranger's salons is
    /// "primary"), so it is always `null` on that path, mirroring [phone]'s
    /// own public/private split.
    bool? isPrimary,
  }) = _Salon;
}
