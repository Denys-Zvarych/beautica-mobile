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
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/booking/application/salon_booking_schedule_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/slot_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking_slot.dart';
import 'package:beautica_mobile/features/booking/domain/salon_master_schedule.dart';
import 'package:beautica_mobile/features/booking/domain/working_day.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_schedule_page.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'dart:ui' show Tristate;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

/// Drives [masterId] from the DATE phase into the TIME phase directly
/// through the shared `salonBookingScheduleProvider` — mirrors exactly what
/// `SalonTimeScreen._handleNext` does on a «Далі» press
/// (`enterTimePhase`/[SalonScheduleEntry.viewingTime]). Needed because
/// forward navigation is CTA-driven now (see `master_schedule_page.dart`'s
/// file header), and this file bare-pumps `MasterSchedulePage` with no host
/// screen/CTA above it — a picked date alone no longer swaps the slide.
void _enterTimePhase(WidgetTester tester, String masterId) {
  final ProviderContainer container = ProviderScope.containerOf(
    tester.element(find.byType(MasterSchedulePage)),
  );
  container
      .read(salonBookingScheduleProvider.notifier)
      .enterTimePhase(masterId);
}

/// Reports every requested date as a working day (so `MonthCalendar`'s
/// day-gate ONLY reflects `MasterSchedulePage`'s own client-side `_today`
/// past-day check, never the fake's data) and records every
/// `getMasterSlots` call — the DATE (for the pre-existing Kyiv-anchoring
/// group below) and the FULL ordered `serviceIds` it was called with (Phase
/// 270 D3 group) — so a test can assert exactly what the screen resolved
/// "today" to, and exactly which assignment ids it queried.
///
/// [slotsToReturn] is additive (defaults to empty, preserving every
/// pre-existing caller's behaviour): the D2 group below needs a REAL slot to
/// tap so `_selectSlot`'s `onCompleted?.call()` path actually runs.
class _AlwaysWorkingCountingSlotRepository implements SlotRepository {
  _AlwaysWorkingCountingSlotRepository({
    this.slotsToReturn = const <BookingSlot>[],
  });

  final List<BookingSlot> slotsToReturn;
  int getMasterSlotsCallCount = 0;
  DateTime? lastSlotsDate;
  List<String>? lastServiceIds;

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
    lastServiceIds = serviceIds;
    return slotsToReturn;
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

// Phase 270 D3/D5 fixtures — a master with TWO assigned services. A
// single-service fixture (like [_kSchedule] above) could never distinguish
// "queried the full ordered list" from "queried only the first element",
// since both would have length 1 — see the mutation check on the D3 group
// below.
const _kCatalogServiceB = SalonCatalogService(
  id: 'svc-2',
  name: 'Педикюр',
  durationLabel: '1 год 30 хв',
  priceDisplay: '700 ₴',
  durationMinutes: 90,
  priceType: ServicePriceType.fixed,
  priceMin: 700,
);

const _kMultiSchedule = SalonMasterSchedule(
  masterId: 'm1',
  firstName: 'Софія',
  lastName: 'Мельник',
  type: MasterType.salonMaster,
  services: <SalonCatalogService>[_kCatalogService, _kCatalogServiceB],
  orderedMasterServiceIds: <String>['assign-svc-1', 'assign-svc-2'],
);

// Straddles the Kyiv/UTC day boundary — IDENTICAL to the clock instant the
// "Kyiv-anchored today" group above pins, so Kyiv "today" resolves to Aug 2
// (see that group's own header) in every group in this file.
// future-date-ok: this IS the fake clockProvider "now" (mirrors the identical instant pinned inline in the group above) — the whole point is a fixed instant straddling the Kyiv/UTC day boundary, which a now-relative offset cannot express.
final DateTime _kClockInstant = DateTime.utc(2026, 8, 1, 22, 30);

void main() {
  group('MasterSchedulePage — Kyiv-anchored "today" (mobile-qa, 2026-08-03, '
      'backlog :226)', () {
    testWidgets(
      'the day before Kyiv "today" renders PAST (untappable) even though it '
      'is still the SAME calendar day in UTC — a UTC/device-day _today would '
      'wrongly leave it selectable',
      (tester) async {
        // future-date-ok: this IS the fake clockProvider "now" — a fixed instant straddling the Kyiv/UTC day boundary is the whole point; a now-relative offset cannot express "an instant that crosses the Kyiv day boundary".
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

        // Aug 2 — the correct Kyiv "today" — is tappable and records the
        // pick. Forward navigation into the TIME phase is CTA-driven now
        // (see `master_schedule_page.dart`'s file header) — there is no host
        // CTA on this bare-pumped page, so the picked date alone leaves the
        // slide on the calendar; drive `enterTimePhase` directly, mirroring
        // `SalonTimeScreen._handleNext`'s «Далі» action.
        final Finder aug2Cell = find.byKey(const Key('booking-calendar-day-2'));
        expect(aug2Cell, findsOneWidget);
        await tester.tapCalendarDay(2);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('booking-month-calendar')),
          findsOneWidget,
          reason:
              'picking a date no longer auto-advances the phase — the '
              'calendar must still be showing until the CTA commits it',
        );
        expect(
          fake.getMasterSlotsCallCount,
          0,
          reason: 'the TIME phase (and its slot fetch) has not opened yet',
        );

        _enterTimePhase(tester, 'm1');
        await tester.pumpAndSettle();

        expect(fake.getMasterSlotsCallCount, 1);
        expect(fake.lastSlotsDate, DateTime(2026, 8, 2));
        expect(
          find.byKey(const Key('booking-month-calendar')),
          findsNothing,
          reason: 'entering the TIME phase must swap away from the calendar',
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

  group('MasterSchedulePage — N1: tapping a date renders it SELECTED '
      '(regression, 2026-08-23)', () {
    testWidgets(
      'should_renderTappedCellSelected_when_aDateIsPicked — master_schedule_'
      'page.dart:364 must thread the picked date into MonthCalendar.selected',
      (tester) async {
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
            clockProvider.overrideWithValue(() => _kClockInstant),
          ],
        );
        await tester.pumpAndSettle();

        final Finder calendar = find.byKey(const Key('booking-month-calendar'));
        expect(calendar, findsOneWidget);

        // BEFORE any tap, no cell is selected — `MonthCalendar`'s
        // `_MonthGrid._weekRow` only paints a `NeumorphicInset` recessed
        // trough behind a `CalendarSelectedRun`
        // (`shared/widgets/calendar_grid.dart:215-233`), and
        // `computeSelectedRuns` never emits a run with no day marked
        // `_DayInfo.selected`. This pins the PRE-tap baseline so the
        // post-tap assertion below is a genuine delta, not a trough that
        // was already there for some unrelated reason (e.g. the today
        // ring, which is a `Border`, never a `NeumorphicInset`).
        expect(
          find.descendant(of: calendar, matching: find.byType(NeumorphicInset)),
          findsNothing,
          reason:
              'no date has been picked yet — the calendar must render with '
              'no selection trough at all',
        );

        // Kyiv "today" under `_kClockInstant` is Aug 2 (see the group
        // above) — tap a later, unambiguously-available day so the cell
        // is real and tappable regardless of the past-day gate.
        final Finder aug5Cell = find.byKey(const Key('booking-calendar-day-5'));
        expect(aug5Cell, findsOneWidget);
        await tester.tapCalendarDay(5);
        await tester.pumpAndSettle();

        // Still on the DATE phase — forward navigation is CTA-driven (see
        // this file's header), so the tap must be visible on-screen, not
        // have already swapped away to the TIME phase.
        expect(calendar, findsOneWidget);

        // RENDERED visual proof, not just notifier state: the tapped
        // cell's own week row now paints the `NeumorphicInset` trough
        // (`calendar_grid.dart:215-233`, reached only via
        // `MonthCalendar.selected` → `_DayInfo.selected` →
        // `computeSelectedRuns`) — this is the exact pixel difference a
        // user sees as "the day highlighted". The N1 bug (`selected:
        // null` hardcoded at `master_schedule_page.dart:364`) left this
        // permanently absent no matter what was tapped, while the
        // `AsyncNotifier`/route-level state still recorded the pick —
        // asserting only the latter would NOT have caught the regression.
        expect(
          find.descendant(of: calendar, matching: find.byType(NeumorphicInset)),
          findsOneWidget,
          reason:
              'tapping Aug 5 must paint the selection trough behind that '
              'cell — this is what "the date renders selected" means '
              'visually; N1 shipped with the CTA correctly enabled while '
              'the calendar showed no selection at all',
        );

        // Accessibility corroboration — the tapped cell's OWN semantics
        // node (not the calendar's, not the notifier's) must flip to
        // `selected`. Reached via the SAME `info.selected` that drives the
        // trough above (`month_calendar.dart` `_dayCell`'s
        // `semanticsSelected: info.selected`), so this is a second,
        // independent rendered signal of the same underlying wiring bug.
        final SemanticsData aug5Data = tester
            .getSemantics(aug5Cell)
            .getSemanticsData();
        expect(
          aug5Data.flagsCollection.isSelected,
          Tristate.isTrue,
          reason:
              'the tapped cell must announce itself as selected to a '
              'screen reader',
        );
      },
    );
  });

  group('MasterSchedulePage — D3: the slot query carries EVERY assigned '
      'service (Phase 270)', () {
    testWidgets(
      'should_querySlotsForEveryAssignedService_when_theMasterHasMoreThanOne',
      (tester) async {
        final fake = _AlwaysWorkingCountingSlotRepository();

        await tester.pumpApp(
          const Scaffold(
            body: MasterSchedulePage(
              schedule: _kMultiSchedule,
              avatarGradient: <Color>[Color(0xFFB89A7A), Color(0xFF6A4A28)],
            ),
          ),
          overrides: <Object>[
            slotRepositoryProvider.overrideWith((_) => fake),
            clockProvider.overrideWithValue(() => _kClockInstant),
          ],
        );
        await tester.pumpAndSettle();

        // Kyiv "today" (see the group above) is Aug 2. Picking the date no
        // longer opens the TIME phase by itself (forward navigation is
        // CTA-driven — see the file header); drive `enterTimePhase` directly,
        // as `SalonTimeScreen._handleNext` would on a «Далі» press.
        await tester.tapCalendarDay(2);
        await tester.pumpAndSettle();
        _enterTimePhase(tester, 'm1');
        await tester.pumpAndSettle();

        expect(fake.getMasterSlotsCallCount, 1);
        expect(
          fake.lastServiceIds,
          <String>['assign-svc-1', 'assign-svc-2'],
          reason:
              'the slot query must carry EVERY assigned service\'s own '
              'assignment id, in order — not just the first one '
              '(Phase 270 D3). A single-service fixture could never fail '
              'this assertion, since length 1 == length 1 either way.',
        );
      },
    );
  });

  group('MasterSchedulePage — D2: onCompleted/keepAlive are OPTIONAL '
      '(Phase 270)', () {
    testWidgets('should_renderWithoutOnCompleted_when_thePageIsPumpedStandalone', (
      tester,
    ) async {
      // Pinned instants (not a bare host-local literal, and not compared
      // against the real wall clock via `isPast` — only formatted into a
      // chip key and tapped) — this fixture exists to bridge D2's slot-tap
      // assertion, not to test date arithmetic, so the exact wall-clock
      // hour is irrelevant.
      final BookingSlot slot = BookingSlot(
        startAt: DateTime.utc(
          2026,
          8,
          2,
          9,
        ), // future-date-ok: fixed slot instant just after the pinned clockInstant "today" (Aug 2) — never compared against the real wall clock
        endAt: DateTime.utc(
          2026,
          8,
          2,
          9,
          30,
        ), // future-date-ok: fixed slot instant just after the pinned clockInstant "today" (Aug 2) — never compared against the real wall clock
        available: true,
      );
      final fake = _AlwaysWorkingCountingSlotRepository(
        slotsToReturn: <BookingSlot>[slot],
      );

      await tester.pumpApp(
        // `onCompleted` and `keepAlive` are both DELIBERATELY omitted — D2
        // makes them optional so a bare-pumped page (no host slider to
        // report to) costs nothing.
        const Scaffold(
          body: MasterSchedulePage(
            schedule: _kSchedule,
            avatarGradient: <Color>[Color(0xFFB89A7A), Color(0xFF6A4A28)],
          ),
        ),
        overrides: <Object>[
          slotRepositoryProvider.overrideWith((_) => fake),
          clockProvider.overrideWithValue(() => _kClockInstant),
        ],
      );
      await tester.pumpAndSettle();

      // Picking the date no longer opens the TIME phase by itself (forward
      // navigation is CTA-driven now — see the file header); drive
      // `enterTimePhase` directly, as `SalonTimeScreen._handleNext` would on
      // a «Далі» press.
      await tester.tapCalendarDay(2);
      await tester.pumpAndSettle();
      _enterTimePhase(tester, 'm1');
      await tester.pumpAndSettle();

      final Finder slotChip = find.byKey(
        Key('salon-slot-chip-${slot.startAt.toIso8601String()}'),
      );
      expect(slotChip, findsOneWidget);
      // `_selectSlot` is now a plain, synchronous state write — it no longer
      // calls `onCompleted` at all (see `master_schedule_page.dart`'s file
      // header: forward navigation moved entirely to the host CTA), so
      // there's no delayed callback left to bridge with a fixed wait. The
      // test's point survives unchanged: tapping the chip with no
      // `onCompleted` provided must not throw.
      await tester.tap(slotChip);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('SalonMasterSchedule.copyWith — D5: order is preserved verbatim '
      '(Phase 270)', () {
    test(
      'should_preserveAssignmentOrder_when_copyWithChangesAnUnrelatedField',
      () {
        final SalonMasterSchedule updated = _kMultiSchedule.copyWith(
          firstName: 'Оксана',
        );

        expect(
          updated.orderedMasterServiceIds,
          <String>['assign-svc-1', 'assign-svc-2'],
          reason:
              'copyWith must never reorder the chained-visit execution '
              'order (Phase 270 D5) — a reordered list silently '
              "reschedules the client's services.",
        );
      },
    );
  });
}
