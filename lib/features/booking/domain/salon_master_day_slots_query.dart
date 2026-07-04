// Phase 14.17 — SalonMasterDaySlotsQuery: family key for the salon booking
// flow's per-master, per-day slot fetch (`salonMasterDaySlotsProvider`,
// `application/salon_booking_schedule_notifier.dart`).
//
// Mirrors `working_days_query.dart`'s normalise-at-construction shape (the
// date is truncated to date-only at construction) so re-selecting the same
// calendar day for the same master+service resolves to the SAME family
// instance instead of re-fetching. Unlike [WorkingDaysQuery] this is also
// keyed on [serviceId]: slot AVAILABILITY (unlike day-level working/
// non-working gating) genuinely depends on which service is being booked.
//
// [serviceId] is always the master's OWN per-master assignment id
// (`MasterServiceResponse.id`) for their PRIMARY assigned service (see
// `salon_master_schedule.dart`'s `primaryServiceAssignmentId` field and the
// architecture note in `salon_booking_schedule_notifier.dart`'s file
// header) — never the full assigned set, and never the salon-wide catalog
// id, since `SlotRepository.getMasterSlots` takes exactly one assignment
// `serviceId`.
//
// Pure Dart: no Flutter imports anywhere in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

part 'salon_master_day_slots_query.freezed.dart';

/// A date-only day + the (masterId, serviceId) pair it is scoped to.
@freezed
abstract class SalonMasterDaySlotsQuery with _$SalonMasterDaySlotsQuery {
  /// Builds a date-only query, truncating any time-of-day from [date] so the
  /// family key is stable by construction.
  factory SalonMasterDaySlotsQuery({
    required String masterId,
    required String serviceId,
    required DateTime date,
  }) => SalonMasterDaySlotsQuery.raw(
    masterId: masterId,
    serviceId: serviceId,
    date: DateTime(date.year, date.month, date.day),
  );

  /// Pass-through freezed constructor for an already-date-only [date]. Not
  /// underscore-prefixed for the same reason as `WorkingDaysQuery.raw`:
  /// freezed derives its `map`/`when` parameter names from the factory name,
  /// and a leading underscore is illegal there. Callers normally go through
  /// the normalising [SalonMasterDaySlotsQuery] factory above.
  const factory SalonMasterDaySlotsQuery.raw({
    required String masterId,
    required String serviceId,
    required DateTime date,
  }) = _SalonMasterDaySlotsQuery;
}
