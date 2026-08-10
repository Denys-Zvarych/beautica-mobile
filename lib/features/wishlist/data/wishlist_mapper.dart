// Phase 237 — BEAUTY WISH LIST mapper.
// Phase F splits the null-guard per arm ([WishlistSourceType]) and makes a
// malformed row a DROP, not a list-wide failure.
//
// Maps `GET /favorites/services`' [api.FavoriteServiceResponse] onto the
// pure-Dart [WishlistService] domain model. The generated DTO types never
// escape the data layer.
//
// NULLABILITY POLICY — the generated DTO declares EVERY field nullable
// (SpringDoc emits no `required` list), so this mapper is the single place that
// decides the domain's non-null shape:
//
//   • `sourceType` — absent ⇒ read as MASTER. Every row shipped before
//     Phase F carried no `sourceType` at all and was unambiguously a MASTER
//     row, so an absent value preserves that reading rather than picking a
//     shape arbitrarily.
//   • MASTER row — `masterServiceId` / `masterId` — absent ⇒ THROW
//     [ServerFailure]. Both are NOT NULL columns the backend joins on, and
//     both are ids a rebook navigates with: a row missing either is a broken
//     payload, and the only alternatives (an empty string, silently
//     defaulting) would either navigate nowhere or hide a real contract
//     break.
//   • SALON row — `salonId` / `serviceDefId` — absent ⇒ THROW [ServerFailure],
//     for the identical reason: `salonId` is what a "go to this salon"
//     affordance would need, and `serviceDefId` is the SALON row's OWN
//     favourite key ([WishlistService.favoriteTargetId]) — losing it makes
//     the row un-un-favouritable.
//   • A THROW from either arm is caught by [fromDtoList] and DROPS the one
//     row rather than failing the whole page — see that method's doc for the
//     decision and why it reverses [fromDto]'s own behaviour when called
//     directly.
//   • serviceName — absent ⇒ '' (empty). A nameless service is renderable (the
//     attribution and price still identify the entry) and is not worth failing
//     the whole page for.
//   • masterFirstName / masterLastName — absent ⇒ omitted from the join. Both
//     absent ⇒ an empty [WishlistService.masterName]; the render site owns the
//     fallback copy. MASTER row only.
//   • masterAvatarUrl / salonAvatarUrl — absent ⇒ null. Genuinely optional on
//     the wire, on either arm.
//   • salonName — absent ⇒ null, carried straight through (not '' — the
//     mapper does not invent an empty string where the wire sent nothing).
//     `WishlistService.displayTitle`'s render site owns the fallback copy,
//     mirroring `masterName`'s policy.
//   • durationMinutes — absent ⇒ 0. Zero is displayable as "no duration known"
//     and invents nothing; fabricating e.g. 60 would put a wrong number in
//     front of a client about to book.
//   • priceDisplay — absent ⇒ '' (empty). The DTO documents null as "a legacy
//     definition with no price".
//   • priceType / priceMin / priceMax — carried through. THIS REVERSES PHASE
//     237's "deliberately not read here" note, by explicit user decision: the
//     backend renders a RANGE as «від 600 до 900 ₴» and the app's own frozen
//     convention is the en-dash band, which is also the only form that fits the
//     compact card (~138 dp needed vs 126 dp available at 360 dp). The mapper
//     does NOT format — it only carries the three inputs across, and
//     `WishlistService.priceLabel` does the resolution through the SHARED
//     `formatBookingPrice` — for a MASTER row only; a SALON row's `priceLabel`
//     ignores these three and renders `priceDisplay` verbatim on every shape
//     (see `wishlist_service.dart`'s header). Keeping the formatting out of
//     here is what stops a second money formatter existing.
//
//     `num` → `double` via `.toDouble()`: the generated DTO types these as
//     `num?`, and a JSON integer decodes to `int`. A bare `as double?` cast
//     would throw on «600» and pass on «600.0» — i.e. it would fail only
//     against the payloads a real backend actually sends.

import 'dart:developer';

import 'package:beautica_api/beautica_api.dart' as api;

import '../../../core/errors/failures.dart';
import '../domain/wishlist_service.dart';

/// Maps the backend's favourite-service rows into [WishlistService].
abstract final class WishlistMapper {
  static const String _tag = 'feature.wishlist.mapper';

  /// Maps one [api.FavoriteServiceResponse] onto [WishlistService].
  ///
  /// Dispatches to the MASTER or SALON arm by [api.FavoriteServiceResponse
  /// .sourceType] (absent ⇒ MASTER). Throws [ServerFailure] when that arm's
  /// required ids are missing — see the file header for the per-arm policy.
  /// Callers that can tolerate one bad row costing the WHOLE page should call
  /// [fromDtoList] instead, which catches this and drops just the row.
  static WishlistService fromDto(api.FavoriteServiceResponse dto) {
    return switch (_sourceTypeOf(dto)) {
      WishlistSourceType.master => _fromMasterDto(dto),
      WishlistSourceType.salon => _fromSalonDto(dto),
    };
  }

  static WishlistSourceType _sourceTypeOf(api.FavoriteServiceResponse dto) =>
      dto.sourceType == api.FavoriteServiceResponseSourceTypeEnum.SALON
      ? WishlistSourceType.salon
      : WishlistSourceType.master;

  static WishlistService _fromMasterDto(api.FavoriteServiceResponse dto) {
    final String? masterServiceId = dto.masterServiceId;
    final String? masterId = dto.masterId;
    if (masterServiceId == null || masterId == null) {
      // Unconditional — never gated on kDebugMode. A row of the user's own
      // saved data disappearing in a release build with zero telemetry would
      // make a systematic backend contract break invisible in production
      // (mobile-security finding). No PII: only the arm and the missing
      // field name, never the row id or any name. Mirrors
      // `salon_mapper.dart`'s unconditional drop-logging pattern.
      log(
        'fromDto(MASTER): missing '
        '${masterServiceId == null ? 'masterServiceId' : 'masterId'} — '
        'refusing to build an unrebookable entry',
        name: _tag,
        level: 1000,
      );
      throw const ServerFailure(statusCode: null);
    }
    return WishlistService(
      masterServiceId: masterServiceId,
      masterId: masterId,
      serviceName: dto.serviceName ?? '',
      masterName: _joinName(dto.masterFirstName, dto.masterLastName),
      masterAvatarUrl: dto.masterAvatarUrl,
      durationMinutes: dto.durationMinutes ?? 0,
      // The wire string, kept as sent. FIXED renders it verbatim; RANGE uses it
      // only as the fallback when the bounds are unusable.
      priceDisplay: dto.priceDisplay ?? '',
      // An ABSENT priceType reads as FIXED, not as RANGE: the fallback that
      // renders the backend's own string is always safe, whereas defaulting to
      // RANGE would send a FIXED row down the band path and print its single
      // price as a floor.
      isRangePrice:
          dto.priceType == api.FavoriteServiceResponsePriceTypeEnum.RANGE,
      priceMin: dto.priceMin?.toDouble(),
      priceMax: dto.priceMax?.toDouble(),
    );
  }

  static WishlistService _fromSalonDto(api.FavoriteServiceResponse dto) {
    final String? salonId = dto.salonId;
    final String? serviceDefId = dto.serviceDefId;
    if (salonId == null || serviceDefId == null) {
      // Unconditional for the same reason as the MASTER arm above — see that
      // comment. No PII: only the arm and the missing field name.
      log(
        'fromDto(SALON): missing '
        '${salonId == null ? 'salonId' : 'serviceDefId'} — refusing to '
        'build an un-un-favouritable entry',
        name: _tag,
        level: 1000,
      );
      throw const ServerFailure(statusCode: null);
    }
    return WishlistService(
      sourceType: WishlistSourceType.salon,
      salonId: salonId,
      salonName: dto.salonName,
      salonAvatarUrl: dto.salonAvatarUrl,
      serviceDefId: serviceDefId,
      serviceName: dto.serviceName ?? '',
      durationMinutes: dto.durationMinutes ?? 0,
      // Verbatim on every price shape for a SALON row — `priceLabel` never
      // reads `isRangePrice`/`priceMin`/`priceMax` for this arm, so they are
      // not carried across at all (see `wishlist_service.dart`'s header).
      priceDisplay: dto.priceDisplay ?? '',
    );
  }

  /// Maps a whole page of rows, in wire order (the backend ranks them).
  ///
  /// ## Drop the row, not the list
  ///
  /// [fromDto] THROWS on a malformed row so a direct, single-row call (as
  /// `wishlist_mapper_test.dart` makes) cannot silently swallow a contract
  /// break. A whole PAGE is different: before Phase F, that throw propagated
  /// out of `List.map` and killed every OTHER, perfectly good row on the
  /// page — one broken favourite blanked the client's entire Beauty Passport
  /// wish-list section. A page is a collection of independent facts ("this
  /// service is saved"), not a single value, so one bad fact should not cost
  /// the rest. This method therefore catches [Failure] PER ROW and drops
  /// only that row — the client simply sees one fewer favourite than the
  /// backend actually holds, which is a far smaller failure than an empty
  /// section. The drop itself is logged, unconditionally (never gated on
  /// `kDebugMode`), by [_fromMasterDto] / [_fromSalonDto] BEFORE they throw —
  /// no separate log is emitted here, as re-logging the same drop from the
  /// catch site would only duplicate the arm+field detail those two already
  /// record.
  static List<WishlistService> fromDtoList(
    Iterable<api.FavoriteServiceResponse> dtos,
  ) {
    final List<WishlistService> out = <WishlistService>[];
    for (final api.FavoriteServiceResponse dto in dtos) {
      try {
        out.add(fromDto(dto));
      } on Failure {
        // Already logged unconditionally at the throw site — see the doc
        // comment above.
      }
    }
    return List<WishlistService>.unmodifiable(out);
  }

  /// Joins the two name parts with a single space, tolerating either being
  /// absent or blank. Returns '' when neither part carries anything.
  ///
  /// Deliberately NOT '$first $last' with null coalescing: that yields a
  /// leading or trailing space whenever one half is missing, which then shows
  /// up as a mis-aligned name on a card and as a stray space in a semantics
  /// label.
  static String _joinName(String? first, String? last) {
    final List<String> parts = <String>[
      if (first != null && first.trim().isNotEmpty) first.trim(),
      if (last != null && last.trim().isNotEmpty) last.trim(),
    ];
    return parts.join(' ');
  }
}
