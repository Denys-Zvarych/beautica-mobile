// Phase 480 — BookingsWeekQuery: the family key for [bookingsWeekProvider]
// (`application/bookings_week_notifier.dart`), the week view's one range read.
//
// The week twin of `bookings_day_query.dart`'s [BookingsDayQuery.masterOwn]:
// same `GET /bookings/me` filters (repeated `status` / `serviceId`, optional
// `asMaster`), keyed on a Kyiv MONDAY instead of a single day. Master variant
// only — the salon board stays day-scoped (phase 480 "Out of scope").
//
// ## `.masterOwn` is the raw pass-through; `.of` is the ONLY normalising path
//
// Same reasoning as [BookingsDayQuery.of], for the same two leak vectors:
//
//   1. Filter ORDER — statuses/serviceIds go through the SAME shared
//      normalisers ([canonicalBookingStatuses] / [canonicalServiceIds]), so
//      one user-visible filter is one family member.
//   2. The DATE — `.of` accepts ANY day of the week (or a time-bearing value)
//      and normalises it to that week's Monday date token via
//      [kyivWeekStart] ∘ [dateOnly]. "Tuesday 09:14" and "Sunday" of the same
//      week therefore key ONE member, one fetch. Calendar arithmetic only — a
//      DST week still resolves to its own Monday at host-local midnight.
//
// [weekStart] is a Kyiv date token (see `shared/time/kyiv_day.dart`): the
// caller derives the day from Kyiv time (`kyivToday` / `kyivDayOf`), exactly
// as for [BookingsDayQuery.day].

import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:beautica_mobile/shared/formatters/api_date.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';

import 'booking_status.dart';
import 'bookings_day_query.dart';

part 'bookings_week_query.freezed.dart';

/// An immutable, canonically-normalised filter for one Kyiv week (Mon–Sun) of
/// the master's own bookings. Build with [BookingsWeekQuery.of].
@freezed
sealed class BookingsWeekQuery with _$BookingsWeekQuery {
  /// The master's own week. `masterId` is implicit — the server derives it
  /// from the bearer token.
  ///
  /// Pass-through freezed constructor: assumes [weekStart] is already a
  /// Monday date token and the lists are already canonical. Public only
  /// because freezed derives `map`/`when` names from the factory name —
  /// build through [BookingsWeekQuery.of] instead.
  const factory BookingsWeekQuery.masterOwn({
    required DateTime weekStart,
    required List<BookingStatus> statuses,
    required List<String> serviceIds,

    /// `true` sends `asMaster=true` (a `SALON_OWNER`'s own master-row
    /// bookings) — same field, same wire meaning as
    /// [BookingsDayQuery.masterOwn]'s `asOwnerMaster`.
    @Default(false) bool asOwnerMaster,
  }) = MasterOwnWeekQuery;

  const BookingsWeekQuery._();

  /// The normalising constructor — the only one callers should use.
  ///
  /// [day] is ANY day of the wanted week; it is truncated ([dateOnly]) and
  /// moved to its Monday ([kyivWeekStart]). [statuses]/[serviceIds] are
  /// canonicalised by the SAME shared normalisers [BookingsDayQuery.of]
  /// uses.
  factory BookingsWeekQuery.of({
    required DateTime day,
    Set<BookingStatus> statuses = const <BookingStatus>{},
    Set<String> serviceIds = const <String>{},
    bool asOwnerMaster = false,
  }) => BookingsWeekQuery.masterOwn(
    weekStart: kyivWeekStart(dateOnly(day)),
    statuses: canonicalBookingStatuses(statuses),
    serviceIds: canonicalServiceIds(serviceIds),
    asOwnerMaster: asOwnerMaster,
  );

  /// The Sunday (date token) closing this week — the `to` of the range read.
  DateTime get weekEnd => kyivAddDays(weekStart, 6);

  /// Whether the Kyiv date token [day] falls inside this Mon–Sun week.
  bool covers(DateTime day) => kyivWeekStart(dateOnly(day)) == weekStart;
}
