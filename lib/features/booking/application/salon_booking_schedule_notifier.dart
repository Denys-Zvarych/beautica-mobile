// MO-4 (single-master single-visit rework) — SalonBookingSchedule: the single
// {date, time} pick for the salon booking flow's step-3 "Час" screen.
//
// A single, non-family `@riverpod` notifier watched by `SalonTimeScreen` — the
// salon flow now books ONE visit against ONE chosen master, so this holds a
// single date/slot pair (mirroring the independent-master flow's
// `SlotPickerState`) instead of the pre-MO-4 per-master map. No `POST` happens
// here — this only tracks LOCAL client picks; «Далі» snapshots the pick into
// `SalonBookingConfirmArgs` and pushes `RouteNames.salonBookingConfirm`, where
// the shared `AppointmentSubmit.submitVisit` runs the single
// `POST /appointments`.
//
// Slot availability is fetched via [salonMasterDaySlotsProvider] against ALL of
// the chosen master's ordered per-master assignment ids (a summed block, MO-2),
// NOT the primary service alone.

import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/booking_providers.dart';
import '../domain/booking_slot.dart';
import '../domain/salon_master_day_slots_query.dart';

part 'salon_booking_schedule_notifier.g.dart';

/// Immutable state: the visit's chosen date + slot, if any.
class SalonBookingScheduleState {
  const SalonBookingScheduleState({this.date, this.slot});

  /// The chosen day (date-only), or `null` before any pick.
  final DateTime? date;

  /// The chosen slot, or `null`. Cleared whenever [date] changes (picking a
  /// new date re-opens the time choice).
  final BookingSlot? slot;

  bool get isScheduled => date != null && slot != null;

  SalonBookingScheduleState copyWith({DateTime? date, BookingSlot? slot}) =>
      SalonBookingScheduleState(
        date: date ?? this.date,
        slot: slot ?? this.slot,
      );
}

/// Drives the single date/time pick on `SalonTimeScreen`. Never issues a
/// booking-creation call — see this file's header.
///
/// Generated provider name: `salonBookingScheduleProvider`.
@riverpod
class SalonBookingSchedule extends _$SalonBookingSchedule {
  @override
  SalonBookingScheduleState build() => const SalonBookingScheduleState();

  /// Selects [date] for the visit, clearing any previously-chosen slot —
  /// picking a new date re-opens the time choice.
  void selectDate(DateTime date) {
    final DateTime dateOnly = DateTime(date.year, date.month, date.day);
    state = SalonBookingScheduleState(date: dateOnly);
  }

  /// Clears the chosen date (and therefore its slot too) — returns the screen
  /// to its date/calendar phase.
  void clearDate() {
    state = const SalonBookingScheduleState();
  }

  /// Selects [slot] as the visit's chosen appointment time.
  void selectSlot(BookingSlot slot) {
    state = state.copyWith(slot: slot);
  }
}

/// Fetches the bookable time slots for [query.masterId] + [query.serviceIds]
/// (the chosen master's ordered per-master assignment ids — a summed block) on
/// [query.date].
///
/// Generated provider name: `salonMasterDaySlotsProvider` — a family, call it
/// with a [SalonMasterDaySlotsQuery].
@riverpod
Future<List<BookingSlot>> salonMasterDaySlots(
  Ref ref,
  SalonMasterDaySlotsQuery query,
) async {
  // Cancel-on-supersede, mirroring `WorkingDaysNotifier.build` — a family
  // member superseded by a different day selection stops competing for
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
