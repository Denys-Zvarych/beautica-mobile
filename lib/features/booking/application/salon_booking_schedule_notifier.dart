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
// ARCHITECTURE DECISION (Phase 270 supersedes the Phase 14.16 primary-
// service convention) — a master here may have 2+ assigned services
// (summed into ONE appointment per the approved design), and
// `SlotRepository.getMasterSlots(masterId, serviceIds, date)` takes the
// FULL ordered list. [SalonMasterSchedule.orderedMasterServiceIds] (every
// assigned service's own assignment id, in chained-visit order) keys the
// slot-availability query — see `master_schedule_page.dart`'s slot-fetch
// call site. Note these are ASSIGNMENT ids (`MasterServiceResponse.id`),
// not the salon catalog id `SalonCatalogService.id` carries — an earlier
// version of this code passed the catalog id here, which 404s backend-side
// ("masterService not found"); see `salon_master_schedule.dart`'s file
// header for the full id-space fix.
// The appointment WINDOW LABEL sums ALL assigned services' durations
// (display-only, via `SalonMasterSchedule.summedDurationMinutes`) — the
// SAME set the slot query now checks availability against, so a shown slot
// genuinely fits the whole chained visit. (An earlier revision queried
// availability against only the primary service's duration while the
// window label summed all of them — a slot could show available for a
// block it did not actually fit. Phase 270 D3 fixed the query to match the
// label.)
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
  const SalonScheduleEntry({this.date, this.slot, this.viewingTime = false});

  /// The chosen day (date-only), or `null` before any pick.
  final DateTime? date;

  /// The chosen slot, or `null`. Cleared whenever [date] changes (picking a
  /// new date re-opens the time choice) — mirrors the preview's
  /// `_selectDay` resetting `_time[id]`.
  final BookingSlot? slot;

  /// Whether this master's `MasterSchedulePage` slide is showing the TIME
  /// phase (slot chips) rather than the DATE phase (calendar) — deliberately
  /// decoupled from [date] itself: picking a day only records [date], it no
  /// longer auto-advances the visible phase. Only [SalonBookingSchedule
  /// .enterTimePhase] (fired by the step-3 CTA's «Далі» press,
  /// `SalonTimeScreen._handleNext`) flips this to `true`. Reset to `false`
  /// by [SalonBookingSchedule.clearDate] and by [SalonBookingSchedule
  /// .selectDate] constructing a fresh entry — both existing "go back to the
  /// calendar" paths, unchanged by this field's addition.
  final bool viewingTime;

  bool get isScheduled => date != null && slot != null;

  SalonScheduleEntry copyWith({
    DateTime? date,
    BookingSlot? slot,
    bool? viewingTime,
  }) => SalonScheduleEntry(
    date: date ?? this.date,
    slot: slot ?? this.slot,
    viewingTime: viewingTime ?? this.viewingTime,
  );
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

  /// Clears [masterId]'s date (and therefore its slot too, and its
  /// [SalonScheduleEntry.viewingTime]) — the day-header chip's «Змінити»
  /// hook, returning that slide to the date phase.
  void clearDate(String masterId) {
    state = state._withEntry(masterId, const SalonScheduleEntry());
  }

  /// Selects [slot] as [masterId]'s chosen appointment time. Pure state —
  /// this notifier never triggers navigation/animation itself; the step-3
  /// CTA (`SalonTimeScreen._handleNext`) is what advances to the next
  /// unscheduled master (or confirms), driven by [scheduledCount]/
  /// [nextUnscheduledIndex] once the client presses «Далі»/«Підтвердити».
  void selectSlot(String masterId, BookingSlot slot) {
    final SalonScheduleEntry current = state.entryFor(masterId);
    state = state._withEntry(masterId, current.copyWith(slot: slot));
  }

  /// Commits [masterId]'s DATE phase into its TIME phase — the step-3 CTA's
  /// «Далі» action while the active slide is still on the calendar (see
  /// `SalonTimeScreen._handleNext`). No-op if [masterId] has no picked date
  /// yet (defensive: the CTA is disabled in that state already, via
  /// `nextEnabled` in `SalonTimeScreen`'s bottom-bar `Consumer`).
  void enterTimePhase(String masterId) {
    final SalonScheduleEntry current = state.entryFor(masterId);
    if (current.date == null) return;
    state = state._withEntry(masterId, current.copyWith(viewingTime: true));
  }
}

/// Fetches the bookable time slots for [query.masterId] +
/// [query.serviceIds] (the master's PRIMARY assigned service as a one-element
/// list today — see this file's header) on [query.date].
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
        serviceIds: query.serviceIds,
        date: query.date,
        cancelToken: cancelToken,
      );
}
