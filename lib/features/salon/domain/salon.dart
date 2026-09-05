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
    /// Raw id only — Beautica's `/locations/*` city lookup is oblast-scoped,
    /// so resolving this to a display name client-side needs [oblastId] too
    /// (always populated together, backend `dbe27a5`).
    ///
    /// Non-nullable as of the RESUME §4 step D flip (backend `ec22d91`):
    /// `salons.city_id` is now a DB-level `NOT NULL` column (V150/V151) and
    /// `SalonService.updateSalon` can no longer 400 or null it out on a
    /// partial PATCH — every [Salon] built from a real backend read
    /// ([SalonMapper.fromDto]/[SalonMapper.fromUpdateDto]), including legacy
    /// pre-Phase-10.6 rows, is backend-guaranteed to carry a real city. It is
    /// not rendered directly.
    ///
    /// `@Default('')` rather than `required`: dozens of pre-existing test
    /// fixtures across unrelated features (booking/favorites/routing route
    /// guards) construct a bare `Salon(id: ..., name: ...)` with no interest
    /// in locality at all — making this `required` would force irrelevant
    /// edits to all of them. `''` is deliberately indistinguishable from the
    /// old `null` short-circuit to every consumer: [resolvedLocalityProvider]
    /// already treats an empty [cityId] as "nothing to resolve" (the SAME
    /// guard `null` used to trip), so this default is a no-op for every
    /// existing call site that never set the field. Every PRODUCTION
    /// construction site (the two [SalonMapper] factories above) always
    /// supplies the backend's real, non-empty value — this default only
    /// ever fires in a test fixture that doesn't care.
    @Default('') String cityId,

    /// UUID of the oblast (region) that owns [cityId], resolved server-side
    /// (backend, added alongside the [SalonAddressEditScreen] work — see that
    /// screen's own doc). Lets [SalonAddressEditScreen] pre-populate the
    /// locality cascade with a single targeted `oblastId -> cities ->
    /// districts` lookup chain instead of scanning every oblast's city list
    /// to find [cityId].
    ///
    /// Populated from both read paths: [SalonMapper.fromUpdateDto] (backs
    /// `PATCH /salons/{salonId}` and `GET /salons/mine`, both
    /// `SalonResponse`) and, as of backend `dbe27a5`, [SalonMapper.fromDto]
    /// (the PUBLIC `GET /salons/{salonId}` read path, `PublicSalonResponse`)
    /// — this field is not public/private-split (nor, since the gap-fix, is
    /// [phone]; [isPrimary] is now the only one that still is).
    ///
    /// Non-nullable for the same reason, and defaulted the same way, as
    /// [cityId] — see that field's doc for why `@Default('')` and not
    /// `required`. [resolvedLocalityProvider]'s guard treats a blank
    /// [oblastId] the same as the old `null` short-circuit too.
    @Default('') String oblastId,

    /// UUID of the taxonomy city district, or `null` when the city has no
    /// districts or none was selected. Same resolution caveat as [cityId].
    String? districtId,

    /// Street name where the salon operates (Phase 10.6+ taxonomy field).
    String? street,

    /// Building number (e.g. "22").
    String? buildingNo,

    /// Apartment/floor/office note (e.g. "2 поверх, офіс 5").
    String? locationNote,

    /// Salon contact phone number, or `null` when the salon has none on file.
    ///
    /// Populated from BOTH read paths: the public `GET /salons/{salonId}`
    /// (`PublicSalonResponse.phone`, [SalonMapper.fromDto]) and the
    /// owner/admin `PATCH /salons/{salonId}` (`SalonResponse.phone`,
    /// [SalonMapper.fromUpdateDto]). The Phase 21.2 gap this doc used to
    /// describe — `PublicSalonResponse` carrying no `phone` at all, so the
    /// value only ever appeared after an unrelated PATCH — is CLOSED: the
    /// backend now serves it on the public DTO and the generated client
    /// declares it (`api/lib/src/model/public_salon_response.dart`). `null`
    /// here is therefore a REAL "no phone on file" signal on either path, and
    /// the «Контакти» blocks may hide the row on it.
    ///
    /// WIRE CONTRACT — `""` vs `null`: the backend serves an empty STRING
    /// (not `null`) when an owner clears the field; that is deliberate and
    /// pinned by backend tests, so the mobile side must absorb it. Both
    /// mappers route this field through `SalonMapper._blankToNull`, which
    /// collapses `null` and whitespace-only alike to `null` — so a [Salon]
    /// built from a real backend read NEVER carries a blank-but-present
    /// phone, and consumers may treat `phone != null` as "renderable".
    ///
    /// `SalonManagementProfile.save` still omits `phone` from the PATCH body
    /// unless it differs from the loaded value; that dirty-diff is now a
    /// plain no-op-avoidance optimisation rather than the data-loss guard it
    /// was while the read path was blind to this field.
    String? phone,

    /// Salon Instagram handle/URL, or `null` when none is on file. Same
    /// `""`-vs-null wire contract and the same `SalonMapper._blankToNull`
    /// normalisation as [phone].
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
    /// "primary"), so it is always `null` on that path. This is now the ONLY
    /// remaining public/private field split on [Salon] — [phone] used to
    /// share it and no longer does.
    bool? isPrimary,
  }) = _Salon;
}
