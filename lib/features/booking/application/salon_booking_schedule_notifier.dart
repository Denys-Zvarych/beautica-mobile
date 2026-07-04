// Phase 14.16/14.17 — SalonBookingSchedule: per-master {date, time} state for
// the salon booking flow's step-3 "Час" screen.
//
// A single, non-family `@riverpod` notifier watched by BOTH `SalonTimeScreen`
// (the `PageView` host) and every `MasterSchedulePage` slide — mirrors
// `SlotPickerNotifier`'s "one shared, non-family, autoDispose provider for
// the whole flow" shape, except the state here is a MAP keyed by masterId
// (one entry per assigned master) rather than a single date/slot pair, since
// the salon flow schedules N appointments (one per master) on the same
// screen instead of the independent-master flow's single appointment.
//
// ARCHITECTURE DECISION (locked, carried from the Phase 14.16 phase doc) —
// primary-service convention for slot queries: a master here may have 2+
// assigned services (summed into ONE appointment per the approved design),
// but `SlotRepository.getMasterSlots(masterId, serviceId, date)` takes
// exactly one `serviceId`. [SalonMasterSchedule.primaryServiceAssignmentId]
// (that master's OWN assignment id for the FIRST service in their assigned
// set) keys the slot-availability query — mirroring the exact precedent
// already documented in `booking_slot_picker_args.dart` (`services.first` as
// "the PRIMARY (operative) service") for WHICH service is primary. Note this
// is an ASSIGNMENT id (`MasterServiceResponse.id`), not the salon catalog id
// `SalonCatalogService.id` carries — an earlier version of this code passed
// the catalog id here, which 404s backend-side ("masterService not found");
// see `salon_master_schedule.dart`'s file header for the full id-space fix.
// The appointment WINDOW LABEL still sums ALL assigned services' durations
// (display-only, via `SalonMasterSchedule.summedDurationMinutes`). This is a
// deliberate, documented MVP approximation: a slot may show available based
// on the primary service's duration alone, while the true multi-service
// block might not fit — flagged here, not silently assumed away.
//
// NO booking submission happens anywhere in this file or anywhere in the
// salon booking flow: `POST /bookings`/`CreateBookingRequest` still only
// support one `masterServiceId` per booking, backend-side (verified, no
// `booking_services` join table exists). This notifier only ever tracks
// LOCAL client-side picks; "Підтвердити" (`ScheduleConfirmBar`) navigates to
// `RouteNames.salonBookingComingSoon`, never a repository call.

import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/booking_providers.dart';
import '../domain/booking_slot.dart';
import '../domain/salon_master_day_slots_query.dart';

part 'salon_booking_schedule_notifier.g.dart';

/// One master's chosen date/time, if any.
class SalonScheduleEntry {
  const SalonScheduleEntry({this.date, this.slot});

  /// The chosen day (date-only), or `null` before any pick.
  final DateTime? date;

  /// The chosen slot, or `null`. Cleared whenever [date] changes (picking a
  /// new date re-opens the time choice) — mirrors the preview's
  /// `_selectDay` resetting `_time[id]`.
  final BookingSlot? slot;

  bool get isScheduled => date != null && slot != null;

  SalonScheduleEntry copyWith({DateTime? date, BookingSlot? slot}) =>
      SalonScheduleEntry(date: date ?? this.date, slot: slot ?? this.slot);
}

/// Immutable state: one [SalonScheduleEntry] per assigned masterId.
class SalonBookingScheduleState {
  const SalonBookingScheduleState({
    this.entries = const <String, SalonScheduleEntry>{},
  });

  final Map<String, SalonScheduleEntry> entries;

  SalonScheduleEntry entryFor(String masterId) =>
      entries[masterId] ?? const SalonScheduleEntry();

  bool isScheduled(String masterId) => entryFor(masterId).isScheduled;

  /// How many of [masterIds] have both a date AND a time chosen.
  int scheduledCount(List<String> masterIds) =>
      masterIds.where(isScheduled).length;

  /// Whether EVERY one of [masterIds] has both a date and a time chosen.
  /// `false` for an empty [masterIds] (nothing to schedule is never "done").
  bool allScheduled(List<String> masterIds) =>
      masterIds.isNotEmpty && masterIds.every(isScheduled);

  /// The first unscheduled master's index in [masterIds] at or after [from]
  /// (wrapping once), or `null` if every master is scheduled — drives the
  /// slider's auto-advance. Ported verbatim from the approved preview's
  /// `_SalonTimeScreenState._nextUnscheduled`.
  int? nextUnscheduledIndex(List<String> masterIds, int from) {
    if (masterIds.isEmpty) return null;
    for (int i = 1; i <= masterIds.length; i++) {
      final int idx = (from + i) % masterIds.length;
      if (!isScheduled(masterIds[idx])) return idx;
    }
    return null;
  }

  SalonBookingScheduleState _withEntry(
    String masterId,
    SalonScheduleEntry entry,
  ) {
    return SalonBookingScheduleState(
      entries: <String, SalonScheduleEntry>{...entries, masterId: entry},
    );
  }
}

/// Drives the per-master date/time picks on `SalonTimeScreen`. Never issues a
/// booking-creation call — see this file's header.
///
/// Generated provider name: `salonBookingScheduleProvider`.
@riverpod
class SalonBookingSchedule extends _$SalonBookingSchedule {
  @override
  SalonBookingScheduleState build() => const SalonBookingScheduleState();

  /// Selects [date] for [masterId], clearing any previously-chosen slot —
  /// picking a new date re-opens the time choice (mirrors the preview's
  /// `_selectDay`).
  void selectDate(String masterId, DateTime date) {
    final DateTime dateOnly = DateTime(date.year, date.month, date.day);
    state = state._withEntry(masterId, SalonScheduleEntry(date: dateOnly));
  }

  /// Clears [masterId]'s date (and therefore its slot too) — the day-header
  /// chip's «Змінити» hook, returning that slide to the date phase.
  void clearDate(String masterId) {
    state = state._withEntry(masterId, const SalonScheduleEntry());
  }

  /// Selects [slot] as [masterId]'s chosen appointment time. The caller
  /// (`MasterSchedulePage`) is responsible for reading whether [masterId]
  /// was ALREADY scheduled before this call, to decide whether the slider
  /// should auto-advance — this notifier only tracks state, never triggers
  /// navigation/animation itself.
  void selectSlot(String masterId, BookingSlot slot) {
    final SalonScheduleEntry current = state.entryFor(masterId);
    state = state._withEntry(masterId, current.copyWith(slot: slot));
  }
}

/// Fetches the bookable time slots for [query.masterId] +
/// [query.serviceId] (the master's PRIMARY assigned service — see this
/// file's header) on [query.date].
///
/// Generated provider name: `salonMasterDaySlotsProvider` — a family, call
/// it with a [SalonMasterDaySlotsQuery].
@riverpod
Future<List<BookingSlot>> salonMasterDaySlots(
  Ref ref,
  SalonMasterDaySlotsQuery query,
) async {
  // Cancel-on-supersede, mirroring `WorkingDaysNotifier.build` — a family
  // member superseded by a different day/master selection stops competing
  // for bandwidth with the query the client actually landed on.
  final CancelToken cancelToken = CancelToken();
  ref.onDispose(cancelToken.cancel);
  return ref
      .watch(slotRepositoryProvider)
      .getMasterSlots(
        masterId: query.masterId,
        serviceId: query.serviceId,
        date: query.date,
        cancelToken: cancelToken,
      );
}
