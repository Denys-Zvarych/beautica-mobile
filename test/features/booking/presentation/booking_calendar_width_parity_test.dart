// Regression guard — MonthCalendar width parity between the two booking
// flows.
//
// BUG: `MasterSchedulePage` (salon flow, `widgets/master_schedule_page.dart`)
// used to wrap its whole slide in a `SingleChildScrollView` with a horizontal
// `EdgeInsets.symmetric(horizontal: VelvetSpacing.lg)` padding — but the
// shared `MonthCalendar` widget it renders (see `month_calendar.dart`'s
// `build()`) ALREADY self-pads horizontally by `VelvetSpacing.lg`. That
// stacked a SECOND 24px inset on top of the calendar's own, so
// `MasterSchedulePage`'s calendar rendered ~96px narrower overall (48px per
// side) than `SlotDateScreen`'s (`slot_picker_screen.dart`, independent-master
// flow) — the correct reference, which only ever applies MonthCalendar's own
// single lg inset (`SlotDateScreen`'s `Expanded(child: _calendarBody(...))`
// is a sibling of the horizontally-padded header `Padding`, not wrapped by
// it — see that file's `build()`).
//
// `MonthCalendar` is Phase 14.16/14.17's ONE widget shared VERBATIM between
// the independent-master and salon flows (see both screens' file headers) —
// a deliberate architecture decision, not two parallel implementations. This
// test encodes that invariant directly: pump both screens at the SAME fixed
// width with equivalent fixtures, locate the shared `Key('booking-month-
// calendar')` in each, and assert their rendered widths are equal — and
// equal to the FULL pumped viewport width (see `_pumpSlotDateScreenCalendarWidth`'s
// call site comment for why an extra outer horizontal inset shrinks this
// number instead of just "wasting" space invisibly).
//
// Reuses the repo-wide `pumpApp` harness (`test/helpers/pump_app.dart`) for
// its `width:` stress knob rather than hand-rolling a `MediaQuery` — mirrors
// `month_calendar_test.dart`'s direct-pump style for `MonthCalendar`'s own
// widget tests, applied here to its two REAL callers instead of the widget
// in isolation.

import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/slot_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking_slot.dart';
import 'package:beautica_mobile/features/booking/domain/booking_slot_picker_args.dart';
import 'package:beautica_mobile/features/booking/domain/salon_master_schedule.dart';
import 'package:beautica_mobile/features/booking/domain/working_day.dart';
import 'package:beautica_mobile/features/booking/presentation/slot_picker_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_schedule_page.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/pump_app.dart';

/// Fixed test-surface width both screens are pumped at. Any value works for
/// the PARITY assertion (both screens equal each other), but a concrete
/// number also lets this test assert the exact expected value (both equal
/// the full viewport width) — see the `expectedWidth` comment in the test
/// body below for why.
const double _kScreenWidth = 400;

/// Every requested day resolves `working: true` and no slots are ever
/// fetched in this test (both pumped screens stay on the DATE phase, never
/// advancing to a time phase) — so `getMasterSlots` is never even called.
/// Shared between both pumps since both screens read the SAME
/// `slotRepositoryProvider`-backed `workingDaysProvider` family.
class _AlwaysWorkingSlotRepository implements SlotRepository {
  @override
  Future<List<WorkingDay>> getWorkingDays({
    required String masterId,
    required DateTime from,
    required DateTime to,
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
    required String serviceId,
    required DateTime date,
    CancelToken? cancelToken,
  }) async => const <BookingSlot>[];
}

const _kMaster = Master(
  id: 'master-1',
  firstName: 'Олена',
  lastName: 'Ковальчук',
  avgRating: 4.8,
  reviewCount: 12,
  type: MasterType.independentMaster,
);

const _kService = MasterService(
  id: 'svc-1',
  serviceDefId: 'def-1',
  name: 'Манікюр з покриттям',
  durationMinutes: 60,
  priceMin: 500,
  priceDisplay: '500 грн',
  category: 'MANICURE',
);

const _kCatalogService = SalonCatalogService(
  id: 'svc-1',
  name: 'Манікюр з покриттям',
  durationLabel: '1 год',
  priceDisplay: '500 грн',
  durationMinutes: 60,
  priceType: ServicePriceType.fixed,
  priceMin: 500,
);

const _kSalonSchedule = SalonMasterSchedule(
  masterId: 'm1',
  firstName: 'Софія',
  lastName: 'Мельник',
  type: MasterType.salonMaster,
  services: <SalonCatalogService>[_kCatalogService],
  primaryServiceAssignmentId: 'svc-1',
);

Future<double> _pumpSlotDateScreenCalendarWidth(WidgetTester tester) async {
  await tester.pumpApp(
    SlotDateScreen(
      args: BookingSlotPickerArgs(
        masterId: _kMaster.id,
        master: _kMaster,
        services: const <MasterService>[_kService],
      ),
    ),
    overrides: <Object>[
      slotRepositoryProvider.overrideWith(
        (_) => _AlwaysWorkingSlotRepository(),
      ),
    ],
    width: _kScreenWidth,
  );
  await tester.pumpAndSettle();

  final Finder calendar = find.byKey(const Key('booking-month-calendar'));
  expect(
    calendar,
    findsOneWidget,
    reason:
        'SlotDateScreen must render the shared MonthCalendar once its '
        'working-days fetch resolves',
  );
  return tester.getSize(calendar).width;
}

Future<double> _pumpMasterSchedulePageCalendarWidth(WidgetTester tester) async {
  await tester.pumpApp(
    Scaffold(
      body: MasterSchedulePage(
        schedule: _kSalonSchedule,
        avatarGradient: const <Color>[Color(0xFFB89A7A), Color(0xFF6A4A28)],
        onCompleted: () {},
        keepAlive: true,
      ),
    ),
    overrides: <Object>[
      slotRepositoryProvider.overrideWith(
        (_) => _AlwaysWorkingSlotRepository(),
      ),
    ],
    width: _kScreenWidth,
  );
  await tester.pumpAndSettle();

  final Finder calendar = find.byKey(const Key('booking-month-calendar'));
  expect(
    calendar,
    findsOneWidget,
    reason:
        'MasterSchedulePage must render the shared MonthCalendar once '
        'its working-days fetch resolves (date phase, before any date is '
        'picked)',
  );
  return tester.getSize(calendar).width;
}

void main() {
  testWidgets('the shared MonthCalendar renders at the SAME width on both the '
      'independent-master (SlotDateScreen) and salon (MasterSchedulePage) '
      'booking screens — regression guard for the double-padding bug that '
      'made the salon flow render it ~96px narrower', (tester) async {
    final double slotDateScreenWidth = await _pumpSlotDateScreenCalendarWidth(
      tester,
    );

    final double masterSchedulePageWidth =
        await _pumpMasterSchedulePageCalendarWidth(tester);

    // The shared `MonthCalendar`'s own outer `Padding` box always reports
    // back the FULL cross-axis width it was handed (its self-inset is
    // absorbed internally by its stretch-aligned content, not subtracted
    // from its own reported size) — so the correct value on BOTH screens
    // is the full pumped viewport width, `_kScreenWidth`, PROVIDED neither
    // screen wraps it in any extra horizontal inset upstream. Verified
    // empirically against the double-padded pre-fix `MasterSchedulePage`
    // (temporarily reintroducing its old `horizontal: VelvetSpacing.lg`
    // outer `SingleChildScrollView` padding): that extra inset shrinks the
    // AVAILABLE cross-axis width one level up, so `MonthCalendar` itself
    // then only ever gets handed `_kScreenWidth - 2 * VelvetSpacing.lg`
    // (352 at this test's 400 width) — reproducing exactly the ~96px
    // narrower rendering (48px per side) this test guards against.
    const double expectedWidth = _kScreenWidth;

    expect(
      masterSchedulePageWidth,
      slotDateScreenWidth,
      reason:
          'MonthCalendar must be exactly as wide on the salon booking '
          'screen as on the independent-master booking screen at the '
          'same viewport width — a regression to the double-padded '
          '`MasterSchedulePage` outer SingleChildScrollView would make '
          'this narrower by 2 * VelvetSpacing.lg (48px) at this width',
    );
    expect(
      slotDateScreenWidth,
      expectedWidth,
      reason:
          'SlotDateScreen is the correct reference: MonthCalendar must be '
          'handed the full viewport width, never reduced by an extra '
          'outer horizontal inset upstream of its own self-padding',
    );
    expect(
      masterSchedulePageWidth,
      expectedWidth,
      reason:
          'MasterSchedulePage must uphold the same contract as '
          'SlotDateScreen, never stacking an extra horizontal inset on '
          'its outer SingleChildScrollView on top of `MonthCalendar`\'s '
          'own self-padding',
    );
  });
}
