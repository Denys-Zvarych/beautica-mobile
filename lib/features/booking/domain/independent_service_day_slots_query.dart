// IndependentServiceDaySlotsQuery: family key for the independent-master
// booking flow's per-service, per-day slot fetch
// (`independentServiceDaySlotsProvider`,
// `application/independent_booking_schedule_notifier.dart`).
//
// The independent analogue of `salon_master_day_slots_query.dart`. Mirrors
// `working_days_query.dart`'s normalise-at-construction shape (the date is
// truncated to date-only at construction) so re-selecting the same calendar
// day for the same master+service selection resolves to the SAME family
// instance instead of re-fetching. Keyed on [serviceIds] because slot
// AVAILABILITY genuinely depends on which services (and therefore the summed
// duration) are being booked.
//
// [serviceIds] (MO-2) is an ORDERED, non-empty list of the master's OWN
// service ids (`MasterService.id`) directly — the independent-master flow has
// no salon-catalog / per-master-assignment id split, so `SlotRepository
// .getMasterSlots(masterId, serviceIds, date)` takes them as-is. Order is the
// back-to-back running order. Because [serviceIds] is a freezed collection
// field it participates in value `==`/`hashCode` (deep equality), so a
// single-element `['x']` list keys the SAME family member across
// re-selections — single-service cache behaviour is unchanged. Multi-service
// selection is wired in MO-3/MO-4; today callers pass a one-element list.
//
// Pure Dart: no Flutter imports anywhere in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

part 'independent_service_day_slots_query.freezed.dart';

/// A date-only day + the (masterId, ordered serviceIds) it is scoped to.
@freezed
abstract class IndependentServiceDaySlotsQuery
    with _$IndependentServiceDaySlotsQuery {
  /// Builds a date-only query, truncating any time-of-day from [date] so the
  /// family key is stable by construction. [serviceIds] is the ordered visit
  /// selection (non-empty; one element in the single-service path).
  factory IndependentServiceDaySlotsQuery({
    required String masterId,
    required List<String> serviceIds,
    required DateTime date,
  }) => IndependentServiceDaySlotsQuery.raw(
    masterId: masterId,
    serviceIds: serviceIds,
    date: DateTime(date.year, date.month, date.day),
  );

  /// Pass-through freezed constructor for an already-date-only [date]. Not
  /// underscore-prefixed for the same reason as `WorkingDaysQuery.raw`:
  /// freezed derives its `map`/`when` parameter names from the factory name,
  /// and a leading underscore is illegal there.
  const factory IndependentServiceDaySlotsQuery.raw({
    required String masterId,
    required List<String> serviceIds,
    required DateTime date,
  }) = _IndependentServiceDaySlotsQuery;
}
