// Phase 14.17 — SalonMasterDaySlotsQuery: family key for the salon booking
// flow's per-master, per-day slot fetch (`salonMasterDaySlotsProvider`,
// `application/salon_booking_schedule_notifier.dart`).
//
// Mirrors `working_days_query.dart`'s normalise-at-construction shape (the
// date is truncated to date-only at construction) so re-selecting the same
// calendar day for the same master+service selection resolves to the SAME
// family instance instead of re-fetching. Unlike [WorkingDaysQuery] this is
// also keyed on [serviceIds]: slot AVAILABILITY (unlike day-level working/
// non-working gating) genuinely depends on which services are being booked.
//
// [serviceIds] is an ORDERED, non-empty list of the master's OWN per-master
// assignment ids (`MasterServiceResponse.id`) — never the salon-wide catalog
// id, since `SlotRepository.getMasterSlots` keys on assignment ids (an
// earlier catalog-id version 404'd; see `salon_master_schedule.dart`'s file
// header). The salon flow passes EVERY one of the master's assigned
// services' assignment ids here (`SalonMasterSchedule.orderedMasterServiceIds`
// verbatim, Phase 270 D3) — the slot query reflects the master's full
// chained-visit duration, not just the first service's. Because [serviceIds]
// is a freezed collection field it participates in value `==`/`hashCode`
// (deep equality), so the SAME ordered list keys the SAME family member
// across re-selections.
//
// Pure Dart: no Flutter imports anywhere in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

part 'salon_master_day_slots_query.freezed.dart';

/// A date-only day + the (masterId, ordered serviceIds) it is scoped to.
@freezed
abstract class SalonMasterDaySlotsQuery with _$SalonMasterDaySlotsQuery {
  /// Builds a date-only query, truncating any time-of-day from [date] so the
  /// family key is stable by construction. [serviceIds] is the ordered visit
  /// selection (non-empty; one element in the single-service path).
  factory SalonMasterDaySlotsQuery({
    required String masterId,
    required List<String> serviceIds,
    required DateTime date,
  }) => SalonMasterDaySlotsQuery.raw(
    masterId: masterId,
    serviceIds: serviceIds,
    date: DateTime(date.year, date.month, date.day),
  );

  /// Pass-through freezed constructor for an already-date-only [date]. Not
  /// underscore-prefixed for the same reason as `WorkingDaysQuery.raw`:
  /// freezed derives its `map`/`when` parameter names from the factory name,
  /// and a leading underscore is illegal there. Callers normally go through
  /// the normalising [SalonMasterDaySlotsQuery] factory above.
  const factory SalonMasterDaySlotsQuery.raw({
    required String masterId,
    required List<String> serviceIds,
    required DateTime date,
  }) = _SalonMasterDaySlotsQuery;
}
