// Phase 13.8 — BEAUTY PASSPORT mapper.
//
// Maps the backend's derived passport aggregate (`GET /clients/me/passport`,
// backend 19.5) into the pure-Dart [Passport] domain model. The generated DTO
// types never escape the data layer.
//
// NULLABILITY POLICY — the generated [PassportResponse] / [BudgetBand] declare
// EVERY field nullable (SpringDoc emits no `required` list), so the mapper is
// the single place that decides the domain's non-null shape:
//   • favoriteDistricts / favoriteCities — absent ⇒ `const <String>[]` (an
//     omitted list means "nothing derived", never an error).
//   • budget — absent ⇒ null. Present but with a null `avg`/`min`/`max` ⇒ ALSO
//     null: a partially-filled band cannot be rendered as a spend envelope, and
//     defaulting a missing bound to 0 would fabricate a figure the client never
//     spent. Absent-or-incomplete both land on the screen's "budget not known"
//     label.
//   • bookingsConsidered — absent ⇒ 0, i.e. the empty-passport state. That is
//     the conservative read: no count means no derivable history.
//   • reviewsWritten — absent ⇒ 0. A client who has written no reviews and a
//     payload that omits the count are indistinguishable AND identical in
//     meaning ("no reviews to show"), so 0 invents nothing.
//   • currency — absent ⇒ 'UAH' (Ukrainian market default, same as the domain
//     model's own @Default).
//   • memberSinceYear — absent ⇒ THROW [ServerFailure]. It is the one field
//     with no honest default. The backend derives it from `users.created_at`
//     (NOT NULL), so an omission means a broken payload, and the alternative —
//     `DateTime.now().year` — is the exact fabrication Phase 235 removed from
//     `passport_screen.dart`. Same failure the repository raises for a null
//     `data` envelope, so the screen's existing error state already covers it.
//
// Flutter-free in spirit but NOT pure Dart any more: `core/errors/failures.dart`
// pulls in Flutter for `Failure.userMessage(BuildContext)`. That is fine here —
// this is the data layer, and `passport_repository.dart` already imports it.
// The DOMAIN layer stays pure.

import 'dart:developer';

import 'package:beautica_api/beautica_api.dart' as api;
import 'package:flutter/foundation.dart';

import '../../../core/errors/failures.dart';
import '../domain/passport.dart';

/// Maps the backend passport aggregate into the [Passport] domain model.
abstract final class PassportMapper {
  /// Maps `GET /clients/me/passport`'s [api.PassportResponse] onto [Passport].
  ///
  /// Every field on the DTO is nullable; see the file header for the per-field
  /// absent-value policy. Throws [ServerFailure] on exactly one omission —
  /// `memberSinceYear` — because that is the only field with no honest default.
  static Passport fromDto(api.PassportResponse dto) {
    final int? memberSinceYear = dto.memberSinceYear;
    if (memberSinceYear == null) {
      if (kDebugMode) {
        log(
          'fromDto: PassportResponse.memberSinceYear is null — refusing to '
          'fabricate a year',
          name: 'feature.passport.mapper',
          level: 1000,
        );
      }
      throw const ServerFailure(statusCode: null);
    }
    return Passport(
      favoriteDistricts: dto.favoriteDistricts?.toList() ?? const <String>[],
      favoriteCities: dto.favoriteCities?.toList() ?? const <String>[],
      budget: _budgetFromDto(dto.budget),
      bookingsConsidered: dto.bookingsConsidered ?? 0,
      reviewsWritten: dto.reviewsWritten ?? 0,
      memberSinceYear: memberSinceYear,
    );
  }

  /// Maps the DTO's spend band, or null when the band is absent OR any of its
  /// three bounds is missing (a partial envelope is not renderable — see the
  /// file header). The generated bounds are `num?`, so they are widened to
  /// `double` for the domain model.
  static BudgetBand? _budgetFromDto(api.BudgetBand? dto) {
    if (dto == null) return null;
    final num? avg = dto.avg;
    final num? min = dto.min;
    final num? max = dto.max;
    if (avg == null || min == null || max == null) return null;
    return BudgetBand(
      avg: avg.toDouble(),
      min: min.toDouble(),
      max: max.toDouble(),
      currency: dto.currency ?? 'UAH',
    );
  }
}
