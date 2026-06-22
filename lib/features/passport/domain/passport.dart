// Phase 13.8 — BEAUTY PASSPORT domain model.
//
// Immutable value objects describing the CLIENT's auto-derived beauty passport
// (favourite procedures, favourite districts, budget band, completed-history
// count). All values are computed by the backend from the client's COMPLETED
// bookings and are READ-ONLY — there is no preferences entity and no edit path.
//
// Hydrated by [PassportMapper.fromDto] off `GET /clients/me/passport`
// (backend 19.5). That endpoint/DTO is NOT yet in the committed OpenAPI client,
// so the mapper + repository currently return a placeholder empty passport and
// carry a TODO(19.5). When the contract lands the mapper maps the generated DTO
// and the domain shape stays unchanged.
//
// Pure Dart: no Flutter imports in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

part 'passport.freezed.dart';

/// The CLIENT's auto-derived beauty passport.
///
/// [bookingsConsidered] is the number of COMPLETED bookings the derivation drew
/// from; `0` ⇒ the empty-passport state (no history yet). [favoriteProcedures]
/// and [favoriteDistricts] are rank-ordered (most-frequent first) and capped to
/// the top 3 by the backend. [budget] is null when there is no spend history.
@freezed
abstract class Passport with _$Passport {
  const factory Passport({
    /// Top-3 most-booked service-type names, rank-ordered (most-frequent first).
    required List<String> favoriteProcedures,

    /// Top-3 most-visited district names, rank-ordered (most-frequent first).
    required List<String> favoriteDistricts,

    /// The derived spend band (avg + min/max envelope), or null when there is no
    /// completed spend history.
    required BudgetBand? budget,

    /// How many COMPLETED bookings the derivation considered. `0` ⇒ empty state.
    required int bookingsConsidered,

    /// How many reviews the client has left (footer "standing" line). Defaults
    /// to 0 until the backend supplies it.
    @Default(0) int reviewsLeft,

    /// Member-since year (footer "issued" line). Null ⇒ omit the year token.
    int? memberSinceYear,
  }) = _Passport;

  const Passport._();

  /// The empty passport: no completed history considered yet. Equivalent to a
  /// passport with `bookingsConsidered == 0` and no derived data.
  factory Passport.empty() => const Passport(
    favoriteProcedures: <String>[],
    favoriteDistricts: <String>[],
    budget: null,
    bookingsConsidered: 0,
  );

  /// Whether the passport has no completed-booking history to derive from.
  /// Drives the encouraging empty-passport screen variant.
  bool get isEmpty => bookingsConsidered == 0;
}

/// The derived budget band: average spend plus the min–max envelope, all in
/// [currency] (UAH for the Ukrainian market).
@freezed
abstract class BudgetBand with _$BudgetBand {
  const factory BudgetBand({
    required double avg,
    required double min,
    required double max,
    @Default('UAH') String currency,
  }) = _BudgetBand;
}
