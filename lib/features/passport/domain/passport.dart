// Phase 13.8 — BEAUTY PASSPORT domain model.
//
// Immutable value objects describing the CLIENT's auto-derived beauty passport
// (favourite districts + cities, budget band, completed-history count, and the
// client's standing: reviews written + member-since year). All values are
// computed by the backend from the client's COMPLETED bookings and are
// READ-ONLY — there is no preferences entity and no edit path.
//
// Hydrated by [PassportMapper.fromDto] off `GET /clients/me/passport`
// (backend 19.5 + track 31), live via `HttpPassportRepository`.
//
// NOTHING ON THIS MODEL IS EVER FABRICATED. [memberSinceYear] is a required
// non-null `int` precisely so no call site can invent one: the backend derives
// it from `users.created_at` (a NOT NULL column), so the wire always carries
// it, and a payload that omits it is broken — the mapper throws rather than
// synthesising `DateTime.now().year` (Phase 235; that fabrication was live).
//
// Pure Dart: no Flutter imports in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

part 'passport.freezed.dart';

/// The CLIENT's auto-derived beauty passport.
///
/// [bookingsConsidered] is the number of COMPLETED bookings the derivation drew
/// from; `0` ⇒ the empty-passport state (no history yet). [favoriteProcedures],
/// [favoriteDistricts] and [favoriteCities] are rank-ordered (most-frequent
/// first) and capped to the top 3 by the backend. [budget] is null when there
/// is no spend history.
@freezed
abstract class Passport with _$Passport {
  const factory Passport({
    /// Top-3 most-booked service-type names, rank-ordered (most-frequent first).
    ///
    /// DEPRECATED BY DESIGN, NOT YET REMOVED: the approved page dropped the
    /// «Улюблені процедури» column. Backend 250 removes the wire field and the
    /// follow-up phase removes this one, together with the screen (238). Until
    /// then the wire still carries it, so the model still carries it.
    required List<String> favoriteProcedures,

    /// Top-3 most-visited district names, rank-ordered (most-frequent first).
    required List<String> favoriteDistricts,

    /// Top-3 most-visited city names, rank-ordered (most-frequent first).
    /// Never null on the wire; an omitted key maps to the empty list.
    required List<String> favoriteCities,

    /// The derived spend band (avg + min/max envelope), or null when there is no
    /// completed spend history. The page renders the AVERAGE, not the ceiling.
    required BudgetBand? budget,

    /// How many COMPLETED bookings the derivation considered. `0` ⇒ empty state.
    required int bookingsConsidered,

    /// How many reviews the client has WRITTEN (footer "standing" line).
    ///
    /// Named for «залишено» = "written/left behind". The previous name
    /// `reviewsLeft` read in English as "remaining to write" — the opposite of
    /// what the backend counts.
    required int reviewsWritten,

    /// The year the client joined, derived by the backend from `users.created_at`.
    ///
    /// Non-null on purpose: see the file header. No call site may substitute
    /// the current year for a missing one.
    required int memberSinceYear,
  }) = _Passport;

  const Passport._();

  /// The empty passport: no completed history considered yet. Equivalent to a
  /// passport with `bookingsConsidered == 0` and no derived data.
  ///
  /// [memberSinceYear] is still REQUIRED: an empty passport means "no bookings
  /// yet", not "no account yet" — the client's join year is known regardless,
  /// and this factory must not become a back door for a fabricated one.
  factory Passport.empty({required int memberSinceYear}) => Passport(
    favoriteProcedures: const <String>[],
    favoriteDistricts: const <String>[],
    favoriteCities: const <String>[],
    budget: null,
    bookingsConsidered: 0,
    reviewsWritten: 0,
    memberSinceYear: memberSinceYear,
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
