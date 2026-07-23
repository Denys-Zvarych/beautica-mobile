// IndependentBookingSchedule: per-service {date, time} state for the
// independent-master booking flow's per-service time screen
// (`BookingTimeScreen`).
//
// The independent analogue of `salon_booking_schedule_notifier.dart`. A
// single, non-family `@riverpod` notifier watched by BOTH `BookingTimeScreen`
// (the `PageView` host) and every `ServiceSchedulePage` slide — state is a MAP
// keyed by serviceId (one entry per selected service), since the independent
// flow now schedules N appointments (one per selected SERVICE) on the same
// screen, each with its OWN chosen date + time (the confirmed
// salon-parity UX: a separate time per service).
//
// NO booking submission happens in this file: it only ever tracks LOCAL
// client-side picks. `BookingTimeScreen._confirm` snapshots the picks into
// `BookingConfirmArgs.appointments` and pushes `/booking/confirm`, where the
// actual N-booking submit runs (`IndependentBookingSubmit`, one `POST
// /bookings` per service).

import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/booking_providers.dart';
import '../domain/booking_slot.dart';
import '../domain/independent_service_day_slots_query.dart';

part 'independent_booking_schedule_notifier.g.dart';

/// One service's chosen date/time, if any.
class IndependentScheduleEntry {
  const IndependentScheduleEntry({this.date, this.slot});

  /// The chosen day (date-only), or `null` before any pick.
  final DateTime? date;

  /// The chosen slot, or `null`. Cleared whenever [date] changes (picking a
  /// new date re-opens the time choice).
  final BookingSlot? slot;

  bool get isScheduled => date != null && slot != null;

  IndependentScheduleEntry copyWith({DateTime? date, BookingSlot? slot}) =>
      IndependentScheduleEntry(
        date: date ?? this.date,
        slot: slot ?? this.slot,
      );
}

/// Immutable state: one [IndependentScheduleEntry] per selected serviceId.
class IndependentBookingScheduleState {
  const IndependentBookingScheduleState({
    this.entries = const <String, IndependentScheduleEntry>{},
  });

  final Map<String, IndependentScheduleEntry> entries;

  IndependentScheduleEntry entryFor(String serviceId) =>
      entries[serviceId] ?? const IndependentScheduleEntry();

  bool isScheduled(String serviceId) => entryFor(serviceId).isScheduled;

  /// How many of [serviceIds] have both a date AND a time chosen.
  int scheduledCount(List<String> serviceIds) =>
      serviceIds.where(isScheduled).length;

  /// Whether EVERY one of [serviceIds] has both a date and a time chosen.
  /// `false` for an empty [serviceIds] (nothing to schedule is never "done").
  bool allScheduled(List<String> serviceIds) =>
      serviceIds.isNotEmpty && serviceIds.every(isScheduled);

  /// The first unscheduled service's index in [serviceIds] at or after [from]
  /// (wrapping once), or `null` if every service is scheduled — drives the
  /// slider's auto-advance. Mirrors the salon flow's `_nextUnscheduled`.
  int? nextUnscheduledIndex(List<String> serviceIds, int from) {
    if (serviceIds.isEmpty) return null;
    for (int i = 1; i <= serviceIds.length; i++) {
      final int idx = (from + i) % serviceIds.length;
      if (!isScheduled(serviceIds[idx])) return idx;
    }
    return null;
  }

  IndependentBookingScheduleState _withEntry(
    String serviceId,
    IndependentScheduleEntry entry,
  ) {
    return IndependentBookingScheduleState(
      entries: <String, IndependentScheduleEntry>{...entries, serviceId: entry},
    );
  }
}

/// Drives the per-service date/time picks on `BookingTimeScreen`. Never issues
/// a booking-creation call — see this file's header.
///
/// Generated provider name: `independentBookingScheduleProvider`.
@riverpod
class IndependentBookingSchedule extends _$IndependentBookingSchedule {
  @override
  IndependentBookingScheduleState build() =>
      const IndependentBookingScheduleState();

  /// Selects [date] for [serviceId], clearing any previously-chosen slot —
  /// picking a new date re-opens the time choice.
  void selectDate(String serviceId, DateTime date) {
    final DateTime dateOnly = DateTime(date.year, date.month, date.day);
    state = state._withEntry(
      serviceId,
      IndependentScheduleEntry(date: dateOnly),
    );
  }

  /// Clears [serviceId]'s date (and therefore its slot too) — returns that
  /// slide to the date phase.
  void clearDate(String serviceId) {
    state = state._withEntry(serviceId, const IndependentScheduleEntry());
  }

  /// Selects [slot] as [serviceId]'s chosen appointment time. The caller
  /// (`ServiceSchedulePage`) reads whether [serviceId] was ALREADY scheduled
  /// before this call to decide whether the slider should auto-advance — this
  /// notifier only tracks state.
  void selectSlot(String serviceId, BookingSlot slot) {
    final IndependentScheduleEntry current = state.entryFor(serviceId);
    state = state._withEntry(serviceId, current.copyWith(slot: slot));
  }
}

/// Fetches the bookable time slots for [query.masterId] + [query.serviceIds]
/// (the selected services' own ids — no assignment-id indirection in the
/// independent flow) on [query.date].
///
/// Generated provider name: `independentServiceDaySlotsProvider` — a family,
/// call it with an [IndependentServiceDaySlotsQuery].
@riverpod
Future<List<BookingSlot>> independentServiceDaySlots(
  Ref ref,
  IndependentServiceDaySlotsQuery query,
) async {
  // Cancel-on-supersede, mirroring `salonMasterDaySlots` — a family member
  // superseded by a different day/service selection stops competing for
  // bandwidth with the query the client actually landed on.
  final CancelToken cancelToken = CancelToken();
  ref.onDispose(cancelToken.cancel);
  return ref
      .watch(slotRepositoryProvider)
      .getMasterSlots(
        masterId: query.masterId,
        serviceIds: query.serviceIds,
        date: query.date,
        cancelToken: cancelToken,
      );
}
