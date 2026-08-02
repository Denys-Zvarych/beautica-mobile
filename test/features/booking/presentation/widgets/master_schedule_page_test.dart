// Widget test — MasterSchedulePage Kyiv-anchored "today" (mobile-qa,
// 2026-08-03, backlog :226 follow-up).
//
// `MasterSchedulePage._today` (`master_schedule_page.dart:123`) derives via
// `kyivToday(ref.read(clockProvider))` — the SAME Kyiv-day derivation
// `SlotDateScreen` uses (`slot_picker_screen.dart:102`; see
// `slot_picker_test.dart`'s own "Kyiv-anchored today" group), which this
// widget mirrors closely: same `_today`/`_firstMonth`/`_lastMonth` shape in
// `initState`, same past-day gate (`day.isBefore(_today)` inside
// `_availabilityFrom`), same shared `MonthCalendar` rendering the calendar
// grid. Before this test the migration had ZERO coverage — the only existing
// test file that touches this widget
// (`booking_calendar_width_parity_test.dart`) is a pure layout-geometry
// regression guard (calendar width parity between the two booking flows) and
// never exercises a clock boundary at all.
//
// Anchored at the IDENTICAL Kyiv-boundary instant `slot_picker_test.dart`
// uses — 2026-08-01T22:30Z: UTC (and any bare host-local reading of it)
// calendar day = Aug 1; Kyiv calendar day (EEST, +3) = Aug 2 (01:30 local,
// already rolled over) — so a reversion of `_today` from `kyivToday` back to
// a bare device/UTC-day derivation is caught the same way on both flows.

import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/slot_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking_slot.dart';
import 'package:beautica_mobile/features/booking/domain/salon_master_schedule.dart';
import 'package:beautica_mobile/features/booking/domain/working_day.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_schedule_page.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

/// Reports every requested date as a working day (so `MonthCalendar`'s
/// day-gate ONLY reflects `MasterSchedulePage`'s own client-side `_today`
/// past-day check, never the fake's data) and records every
/// `getMasterSlots` call so the test can assert exactly which date the
/// screen resolved "today" to.
class _AlwaysWorkingCountingSlotRepository implements SlotRepository {
  int getMasterSlotsCallCount = 0;
  DateTime? lastSlotsDate;

  @override
  Future<List<WorkingDay>> getWorkingDays({
    required String masterId,
    required DateTime from,
    required DateTime to,
    List<String>? serviceIds,
    CancelToken? cancelToken,
  }) async {
    final List<WorkingDay> days = <WorkingDay>[];
    for (
      DateTime d = from;
      !d.isAfter(to);
      d = d.add(const Duration(days: 1))
    ) {
      days.add(WorkingDay(date: d, working: true));
    }
    return days;
  }

  @override
  Future<List<BookingSlot>> getMasterSlots({
    required String masterId,
    required List<String> serviceIds,
    required DateTime date,
    CancelToken? cancelToken,
  }) async {
    getMasterSlotsCallCount++;
    lastSlotsDate = date;
    return const <BookingSlot>[];
  }
}

const _kCatalogService = SalonCatalogService(
  id: 'svc-1',
  name: 'Манікюр з покриттям',
  durationLabel: '1 год',
  priceDisplay: '500 ₴',
  durationMinutes: 60,
  priceType: ServicePriceType.fixed,
  priceMin: 500,
);

const _kSchedule = SalonMasterSchedule(
  masterId: 'm1',
  firstName: 'Софія',
  lastName: 'Мельник',
  type: MasterType.salonMaster,
  services: <SalonCatalogService>[_kCatalogService],
  orderedMasterServiceIds: <String>['svc-1'],
);

void main() {
  group('MasterSchedulePage — Kyiv-anchored "today" (mobile-qa, 2026-08-03, '
      'backlog :226)', () {
    testWidgets(
      'the day before Kyiv "today" renders PAST (untappable) even though it '
      'is still the SAME calendar day in UTC — a UTC/device-day _today would '
      'wrongly leave it selectable',
      (tester) async {
        final clockInstant = DateTime.utc(2026, 8, 1, 22, 30);
        final fake = _AlwaysWorkingCountingSlotRepository();

        await tester.pumpApp(
          const Scaffold(
            body: MasterSchedulePage(
              schedule: _kSchedule,
              avatarGradient: <Color>[Color(0xFFB89A7A), Color(0xFF6A4A28)],
            ),
          ),
          overrides: <Object>[
            slotRepositoryProvider.overrideWith((_) => fake),
            clockProvider.overrideWithValue(() => clockInstant),
          ],
        );
        await tester.pumpAndSettle();

        // Still on the date phase, calendar rendered.
        expect(find.byKey(const Key('booking-month-calendar')), findsOneWidget);

        // Aug 1 is already YESTERDAY once "today" correctly resolves to Aug 2
        // in Kyiv — no GestureDetector (the disabled-cell shape), and tapping
        // it triggers no slot fetch / phase change.
        final Finder aug1Cell = find.byKey(const Key('booking-calendar-day-1'));
        expect(aug1Cell, findsOneWidget);
        expect(
          find.descendant(of: aug1Cell, matching: find.byType(GestureDetector)),
          findsNothing,
          reason:
              'Aug 1 is already YESTERDAY in Kyiv (today=Aug 2) even though '
              'it is still the SAME calendar day in UTC — a device/UTC-day '
              '_today would wrongly leave this cell tappable',
        );
        await tester.tap(aug1Cell, warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(fake.getMasterSlotsCallCount, 0);
        expect(
          find.byKey(const Key('booking-month-calendar')),
          findsOneWidget,
          reason: 'tapping the disabled past cell must not advance the phase',
        );

        // Aug 2 — the correct Kyiv "today" — is tappable and advances to the
        // time phase, fetching slots for exactly that date.
        final Finder aug2Cell = find.byKey(const Key('booking-calendar-day-2'));
        expect(aug2Cell, findsOneWidget);
        await tester.tap(aug2Cell);
        await tester.pumpAndSettle();

        expect(fake.getMasterSlotsCallCount, 1);
        expect(fake.lastSlotsDate, DateTime(2026, 8, 2));
        expect(
          find.byKey(const Key('booking-month-calendar')),
          findsNothing,
          reason: 'selecting the correct Kyiv "today" must advance the phase',
        );
        expect(
          find.byKey(const Key('salon-schedule-no-slots-empty-state')),
          findsOneWidget,
          reason:
              'the fake returns zero slots for Aug 2 — the time phase must '
              'render the no-slots empty state, confirming the fetch resolved '
              'for the date the tap actually selected',
        );
      },
    );
  });
}
