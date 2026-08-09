// Phase 237 — BEAUTY WISH LIST mapper.
//
// Maps `GET /favorites/services`' [api.FavoriteServiceResponse] onto the
// pure-Dart [WishlistService] domain model. The generated DTO types never
// escape the data layer.
//
// NULLABILITY POLICY — the generated DTO declares EVERY field nullable
// (SpringDoc emits no `required` list), so this mapper is the single place that
// decides the domain's non-null shape:
//
//   • masterServiceId / masterId — absent ⇒ THROW [ServerFailure]. Both are
//     NOT NULL columns the backend joins on, and both are ids a rebook
//     navigates with: a row missing either is a broken payload, and the only
//     alternatives (an empty string, dropping the row silently) would either
//     navigate nowhere or hide a real contract break. Same failure the
//     repository raises for a null `data` envelope, so the screen's error+retry
//     state already covers it. This mirrors `PassportMapper`'s treatment of
//     `memberSinceYear`.
//   • serviceName — absent ⇒ '' (empty). A nameless service is renderable (the
//     master name and price still identify the entry) and is not worth failing
//     the whole page for.
//   • masterFirstName / masterLastName — absent ⇒ omitted from the join. Both
//     absent ⇒ an empty [WishlistService.masterName]; the render site owns the
//     fallback copy.
//   • masterAvatarUrl — absent ⇒ null. Genuinely optional on the wire.
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
//     `formatBookingPrice`. Keeping the formatting out of here is what stops a
//     second money formatter existing; see `wishlist_service.dart`'s header.
//
//     `num` → `double` via `.toDouble()`: the generated DTO types these as
//     `num?`, and a JSON integer decodes to `int`. A bare `as double?` cast
//     would throw on «600» and pass on «600.0» — i.e. it would fail only
//     against the payloads a real backend actually sends.

import 'dart:developer';

import 'package:beautica_api/beautica_api.dart' as api;
import 'package:flutter/foundation.dart';

import '../../../core/errors/failures.dart';
import '../domain/wishlist_service.dart';

/// Maps the backend's favourite-service rows into [WishlistService].
abstract final class WishlistMapper {
  static const String _tag = 'feature.wishlist.mapper';

  /// Maps one [api.FavoriteServiceResponse] onto [WishlistService].
  ///
  /// Throws [ServerFailure] when either id is missing — see the file header for
  /// the per-field absent-value policy.
  static WishlistService fromDto(api.FavoriteServiceResponse dto) {
    final String? masterServiceId = dto.masterServiceId;
    final String? masterId = dto.masterId;
    if (masterServiceId == null || masterId == null) {
      if (kDebugMode) {
        log(
          'fromDto: FavoriteServiceResponse is missing '
          '${masterServiceId == null ? 'masterServiceId' : 'masterId'} — '
          'refusing to build an unrebookable entry',
          name: _tag,
          level: 1000,
        );
      }
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

  /// Maps a whole page of rows, in wire order (the backend ranks them).
  static List<WishlistService> fromDtoList(
    Iterable<api.FavoriteServiceResponse> dtos,
  ) => dtos.map(fromDto).toList(growable: false);

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
