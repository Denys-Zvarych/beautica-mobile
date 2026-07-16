// IndependentServiceDaySlotsQuery: family key for the independent-master
// booking flow's per-service, per-day slot fetch
// (`independentServiceDaySlotsProvider`,
// `application/independent_booking_schedule_notifier.dart`).
//
// The independent analogue of `salon_master_day_slots_query.dart`. Mirrors
// `working_days_query.dart`'s normalise-at-construction shape (the date is
// truncated to date-only at construction) so re-selecting the same calendar
// day for the same master+service resolves to the SAME family instance instead
// of re-fetching. Keyed on [serviceId] because slot AVAILABILITY genuinely
// depends on which service (and therefore which duration) is being booked.
//
// Unlike the salon flow's query, [serviceId] here is the master's OWN service
// id (`MasterService.id`) directly — the independent-master flow has no
// salon-catalog / per-master-assignment id split, so `SlotRepository
// .getMasterSlots(masterId, serviceId, date)` takes it as-is.
//
// Pure Dart: no Flutter imports anywhere in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

part 'independent_service_day_slots_query.freezed.dart';

/// A date-only day + the (masterId, serviceId) pair it is scoped to.
@freezed
abstract class IndependentServiceDaySlotsQuery
    with _$IndependentServiceDaySlotsQuery {
  /// Builds a date-only query, truncating any time-of-day from [date] so the
  /// family key is stable by construction.
  factory IndependentServiceDaySlotsQuery({
    required String masterId,
    required String serviceId,
    required DateTime date,
  }) => IndependentServiceDaySlotsQuery.raw(
    masterId: masterId,
    serviceId: serviceId,
    date: DateTime(date.year, date.month, date.day),
  );

  /// Pass-through freezed constructor for an already-date-only [date]. Not
  /// underscore-prefixed for the same reason as `WorkingDaysQuery.raw`:
  /// freezed derives its `map`/`when` parameter names from the factory name,
  /// and a leading underscore is illegal there.
  const factory IndependentServiceDaySlotsQuery.raw({
    required String masterId,
    required String serviceId,
    required DateTime date,
  }) = _IndependentServiceDaySlotsQuery;
}
