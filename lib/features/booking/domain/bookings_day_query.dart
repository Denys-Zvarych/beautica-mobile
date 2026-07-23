// Phase 7.9 — BookingsDayQuery: the family key for [bookingsDayProvider].
//
// Retires `MasterBookingsQuery` (Phase 7.1–7.8), whose paged `from`/`to`
// window this replaces with a single Kyiv calendar `day`. A timeline cannot
// render page 0 — see `bookings_day_notifier.dart`'s header for why the whole
// day is fetched in one request instead.
//
// ## A freezed SEALED union — ahead of need, deliberately
//
// This is the salon-reuse seam Phase 7.11 (D11) lands: a `.salon({salonId,
// masterIds, ...})` member joins this one when the multi-master salon day
// view ships. Do NOT add it now — only the independent master's OWN day
// ships in this phase. `masterId` is implicit on [BookingsDayQuery.masterOwn]
// — the server derives it from the bearer token.
//
// ## `.masterOwn` is the raw, un-normalised pass-through
//
// It is public only because freezed derives `map`/`when` parameter names
// from the factory name, and a leading underscore is illegal there — same
// reason `MasterBookingsQuery.raw` / `WorkingDaysQuery.raw` were public.
// [BookingsDayQuery.of] is the ONLY normalising entry point; every caller —
// including tests — must go through it.
// `scripts/forbid_raw_bookings_query.sh` enforces this: zero
// `BookingsDayQuery.masterOwn(` calls outside this file, `.freezed.dart`
// codegen, and `.of()`'s own call below.
//
// ## Why `List`, not `Set` [carried from `MasterBookingsQuery`'s header]
//
// The obvious shape for `statuses`/`serviceIds` is a `Set`, and freezed's
// generated `==` would handle it correctly (it emits `DeepCollectionEquality`,
// which compares sets by membership). Equality is not the problem —
// **iteration order** is. A `Set`'s order is insertion-dependent, so
// `{confirmed, completed}` and `{completed, confirmed}` are `==`-equal yet
// serialise to two DIFFERENT query strings:
//
//   ?status=CONFIRMED&status=COMPLETED
//   ?status=COMPLETED&status=CONFIRMED
//
// Both are accepted by the backend, so nothing breaks on the wire.
//
// What breaks is this class's ONE JOB. A freezed `List` field compares
// order-sensitively, so `[confirmed, completed]` and `[completed, confirmed]`
// are two DIFFERENT values — and therefore two different family keys, two
// members, two fetches, for one user-visible filter. Sorting in
// [BookingsDayQuery.of] is what collapses them to one. That is the reason the
// sort exists; it is not a wire-format concern. (The emitted URL is
// canonicalised separately, at the serialisation boundary in
// `BookingRepository.getMyBookings` — see that file for why both sorts agree
// by ordering on enum `index`.)
//
// ## The real family-leak vector: an un-normalised `DateTime`
//
// `Set` ordering is a test-quality problem. The genuine bug is `day`: it is a
// *date*, but a `DateTime` is an *instant*. A rail tap or a date picker hands
// back `DateTime.now()`-derived (or otherwise time-bearing) values, so two
// taps on the same calendar day at 09:14 and 09:15 would otherwise be two
// DIFFERENT keys — two family members, two network fetches, for one
// user-visible day. Where `MasterBookingsQuery` truncated a `from`/`to`
// PAIR, [BookingsDayQuery.of] truncates the single [day] field
// ([dateOnly]) — the leak vector shrank from two fields to one, not away.
//
// This is why [BookingsDayQuery.masterOwn] is not the intended entry point:
// [BookingsDayQuery.of] is the ONLY normalising path.
//
// ## The day token is a KYIV calendar day, not a host-local one
//
// [day] is a date-only `DateTime` with NO ZONE MEANING — a plain `(y, m, d)`
// token, exactly what [dateOnly] produces, that the caller is responsible for
// having already derived from Kyiv time (`dateOnly(toBeauticaTime(...))`).
// This class does not — and cannot — enforce that; see
// `bookings_day_notifier.dart`'s header for the full reasoning (the backend
// already interprets `from`/`to` as `LocalDate` in `Europe/Kyiv`).

import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:beautica_mobile/shared/formatters/api_date.dart';

import 'booking_status.dart';

part 'bookings_day_query.freezed.dart';

/// An immutable, canonically-normalised filter for the master's day-scoped
/// booking timeline. Build with [BookingsDayQuery.of].
@freezed
sealed class BookingsDayQuery with _$BookingsDayQuery {
  /// The independent master's own day. `masterId` is implicit — the server
  /// derives it from the bearer token.
  ///
  /// Pass-through freezed constructor. Assumes [statuses]/[serviceIds] are
  /// already canonically sorted and [day] is already date-only — build
  /// through [BookingsDayQuery.of] instead, which guarantees both. See the
  /// file header for why this is public despite that.
  const factory BookingsDayQuery.masterOwn({
    required DateTime day,
    required List<BookingStatus> statuses,
    required List<String> serviceIds,
  }) = MasterOwnDayQuery;

  // A `.salon({salonId, masterIds, ...})` member lands with the salon screen.
  // Do NOT add it now.

  const BookingsDayQuery._();

  /// The normalising constructor — the only one callers should use.
  ///
  /// Takes `Set`s (the natural shape for a multi-select filter) and
  /// canonicalises them into sorted, unmodifiable `List`s: [statuses] by
  /// enum declaration order, [serviceIds] lexicographically. Truncates [day]
  /// to date-only via [dateOnly]. The result is that two independently-built
  /// queries describing the same day+filters are always `==`-equal and
  /// always serialise to the same request — see the file header for why each
  /// half of that matters.
  factory BookingsDayQuery.of({
    required DateTime day,
    Set<BookingStatus> statuses = const <BookingStatus>{},
    Set<String> serviceIds = const <String>{},
  }) {
    final List<BookingStatus> sortedStatuses = statuses.toList(growable: false)
      ..sort((BookingStatus a, BookingStatus b) => a.index.compareTo(b.index));
    final List<String> sortedServiceIds = serviceIds.toList(growable: false)
      ..sort();

    return BookingsDayQuery.masterOwn(
      day: dateOnly(day),
      statuses: List<BookingStatus>.unmodifiable(sortedStatuses),
      serviceIds: List<String>.unmodifiable(sortedServiceIds),
    );
  }

  /// Whether any filter narrows the list — [day] is navigation, not a
  /// filter, so it never counts.
  bool get hasFilters => statuses.isNotEmpty || serviceIds.isNotEmpty;
}
