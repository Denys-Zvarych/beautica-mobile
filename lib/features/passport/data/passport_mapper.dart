// Phase 13.8 — BEAUTY PASSPORT mapper.
//
// Maps the backend's derived passport aggregate (`GET /clients/me/passport`,
// backend 19.5) into the pure-Dart [Passport] domain model. The generated DTO
// types never escape the data layer.
//
// NULLABILITY POLICY — the generated [PassportResponse] / [BudgetBand] declare
// EVERY field nullable (SpringDoc emits no `required` list), so the mapper is
// the single place that decides the domain's non-null shape:
//   • favoriteProcedures / favoriteDistricts — absent ⇒ `const <String>[]`
//     (an omitted list means "nothing derived", never an error).
//   • budget — absent ⇒ null. Present but with a null `avg`/`min`/`max` ⇒ ALSO
//     null: a partially-filled band cannot be rendered as a spend envelope, and
//     defaulting a missing bound to 0 would fabricate a figure the client never
//     spent. Absent-or-incomplete both land on the screen's "budget not known"
//     label.
//   • bookingsConsidered — absent ⇒ 0, i.e. the empty-passport state. That is
//     the conservative read: no count means no derivable history.
//   • currency — absent ⇒ 'UAH' (Ukrainian market default, same as the domain
//     model's own @Default).
//
// NOT ON THE WIRE: the backend record carries no `reviewsLeft` and no
// `memberSinceYear`, so both keep their [Passport] defaults (0 / null). They are
// deliberately NOT synthesised here — the screen already has a fallback for an
// absent member-since year, and a fabricated review count would be a lie.
//
// Pure Dart: no Flutter imports in this file.

import 'package:beautica_api/beautica_api.dart' as api;

import '../domain/passport.dart';

/// Maps the backend passport aggregate into the [Passport] domain model.
abstract final class PassportMapper {
  /// Maps `GET /clients/me/passport`'s [api.PassportResponse] onto [Passport].
  ///
  /// Every field on the DTO is nullable; see the file header for the per-field
  /// absent-value policy. Never throws — a fully-empty payload maps to the
  /// equivalent of [Passport.empty].
  static Passport fromDto(api.PassportResponse dto) => Passport(
    favoriteProcedures: dto.favoriteProcedures?.toList() ?? const <String>[],
    favoriteDistricts: dto.favoriteDistricts?.toList() ?? const <String>[],
    budget: _budgetFromDto(dto.budget),
    bookingsConsidered: dto.bookingsConsidered ?? 0,
  );

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
