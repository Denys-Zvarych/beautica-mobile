// MO-4 — unit tests for the reworked single-state SalonBookingSchedule notifier.
//
// The salon flow now books ONE visit (ONE date + ONE slot), so the notifier
// holds a single {date, slot} pair (not the pre-MO-4 per-master map).

import 'package:beautica_mobile/features/booking/application/salon_booking_schedule_notifier.dart';
import 'package:beautica_mobile/features/booking/domain/booking_slot.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

BookingSlot _slot(int hour) => BookingSlot(
  startAt: DateTime(2026, 7, 20, hour),
  endAt: DateTime(2026, 7, 20, hour + 1),
  available: true,
);

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(retry: beauticaProviderRetry);
    addTearDown(container.dispose);
  });

  SalonBookingSchedule notifier() =>
      container.read(salonBookingScheduleProvider.notifier);
  SalonBookingScheduleState state() =>
      container.read(salonBookingScheduleProvider);

  test('initial state has no date and no slot', () {
    expect(state().date, isNull);
    expect(state().slot, isNull);
    expect(state().isScheduled, isFalse);
  });

  test('selectDate truncates to date-only and clears any slot', () {
    notifier().selectDate(DateTime(2026, 7, 20, 14, 30));
    expect(state().date, DateTime(2026, 7, 20));
    expect(state().slot, isNull);

    notifier().selectSlot(_slot(10));
    expect(state().slot, isNotNull);

    // Re-selecting a date re-opens the time choice (drops the slot).
    notifier().selectDate(DateTime(2026, 7, 21, 9));
    expect(state().date, DateTime(2026, 7, 21));
    expect(state().slot, isNull);
  });

  test('selectSlot sets the visit slot; isScheduled once both are set', () {
    expect(state().isScheduled, isFalse);
    notifier().selectDate(DateTime(2026, 7, 20));
    expect(state().isScheduled, isFalse);
    notifier().selectSlot(_slot(11));
    expect(state().isScheduled, isTrue);
    expect(state().slot, _slot(11));
  });

  test('clearDate wipes both date and slot', () {
    notifier()
      ..selectDate(DateTime(2026, 7, 20))
      ..selectSlot(_slot(12));
    expect(state().isScheduled, isTrue);

    notifier().clearDate();
    expect(state().date, isNull);
    expect(state().slot, isNull);
    expect(state().isScheduled, isFalse);
  });
}
