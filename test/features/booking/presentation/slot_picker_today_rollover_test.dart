// Regression — `_today` was a `late final` captured ONCE in `initState`, so a
// booking picker left open across KYIV midnight kept greying out the day that
// had just become today (and kept yesterday tappable).
//
// THE FIX UNDER TEST
// ------------------
// Both pickers now re-derive it on every read:
//
//     DateTime get _today => kyivToday(ref.read(clockProvider));
//
//   • `slot_picker_screen.dart`            `_SlotDateScreenState._today`
//   • `widgets/master_schedule_page.dart`  `_MasterSchedulePageState._today`
//
// `_today` gates the calendar's past-day cells (`_availabilityFrom`: a day
// before it is never tappable) and anchors the 3-month booking horizon, so a
// frozen capture is not cosmetic — the client cannot book the current day at
// all until the screen is rebuilt from scratch.
//
// WHY THE ROLLOVER FIXTURE IS SHAPED LIKE THIS
// ---------------------------------------------
// Both pinned instants sit on the SAME UTC calendar day (2026-08-01) and
// straddle only the KYIV midnight:
//
//     20:30Z  →  Kyiv 23:30 on Aug 1   →  today = Aug 1
//     21:30Z  →  Kyiv 00:30 on Aug 2   →  today = Aug 2
//
// So the day that flips is Kyiv's, not UTC's — a `_today` derived from the
// device/UTC calendar day would not move at all here, and a `_today` frozen in
// `initState` would not move regardless of zone. The two failure modes are
// distinguished, not conflated.
//
// `clockProvider` is overridden with a MUTABLE closure (`() => now`) rather
// than a fixed instant: the whole contract is that a LATER read sees a later
// value, which a `overrideWithValue(() => someFixedInstant)` cannot express.
// The clock the fixture reasons about and the clock the widget reads are the
// same object throughout (M15) — nothing here touches the host clock.
//
// The rebuild is driven by a REAL user interaction (a day tap / a month page),
// never `markNeedsBuild`: the claim is that the next repaint a user causes
// already sees the live Kyiv day.

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/slot_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking_slot.dart';
import 'package:beautica_mobile/features/booking/domain/booking_slot_picker_args.dart';
import 'package:beautica_mobile/features/booking/domain/salon_booking_args.dart';
import 'package:beautica_mobile/features/booking/domain/salon_master_schedule.dart';
import 'package:beautica_mobile/features/booking/domain/working_day.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_time_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/slot_picker_screen.dart';
import 'package:beautica_mobile/features/booking/application/salon_master_coverage_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/salon/application/public_salon_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_service_catalog_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_master_summary.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/pump_app.dart';

/// 2026-08-01T20:30Z — Kyiv 23:30 on Aug 1. "Today" is Aug 1.
// A now-relative offset cannot express "just before Kyiv midnight, still the
// previous UTC day". Nothing here reads `isPast`.
// future-date-ok: a pinned instant straddling the KYIV day boundary IS the fixture.
final DateTime kBeforeKyivMidnight = DateTime.utc(2026, 8, 1, 20, 30);

/// 2026-08-01T21:30Z — Kyiv 00:30 on Aug 2, still the SAME UTC day.
/// "Today" is now Aug 2.
// future-date-ok: the other half of the pinned Kyiv-midnight pair above.
final DateTime kAfterKyivMidnight = DateTime.utc(2026, 8, 1, 21, 30);

class _FakeSlotRepository implements SlotRepository {
  int slotCallCount = 0;

  @override
  Future<List<BookingSlot>> getMasterSlots({
    required String masterId,
    required List<String> serviceIds,
    required DateTime date,
    CancelToken? cancelToken,
  }) async {
    slotCallCount++;
    return const <BookingSlot>[];
  }

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
}

/// Whether the calendar cell for [day] carries a tap handler.
///
/// `MonthCalendar._DayCell` renders an unavailable day (past / out of range /
/// non-working) as a bare `Semantics` with NO `GestureDetector` at all, so
/// handler PRESENCE is the honest read of "is this day bookable" — a tap on an
/// inert cell lands on the scroll view behind it and silently no-ops
/// (`month_calendar.dart:449-455`), which is why `warnIfMissed` cannot see it.
bool cellIsTappable(int day) => find
    .descendant(
      of: find.byKey(Key('booking-calendar-day-$day')),
      matching: find.byType(GestureDetector),
    )
    .evaluate()
    .isNotEmpty;

const Master kMaster = Master(
  id: 'master-1',
  firstName: 'Olena',
  lastName: 'Kovalchuk',
  avgRating: 4.8,
  reviewCount: 12,
  type: MasterType.independentMaster,
);

const MasterService kService = MasterService(
  id: 'svc-1',
  serviceDefId: 'def-1',
  name: 'Manicure',
  durationMinutes: 60,
  priceMin: 500,
  priceDisplay: '500',
  category: 'MANICURE',
);

const SalonCatalogService kSalonService = SalonCatalogService(
  id: 'svc-1',
  name: 'Manicure',
  durationLabel: '1h',
  priceDisplay: '500',
  durationMinutes: 60,
  priceType: ServicePriceType.fixed,
  priceMin: 500,
);

const SalonMasterSchedule kVisit = SalonMasterSchedule(
  masterId: 'm2',
  firstName: 'Sofia',
  lastName: 'Melnyk',
  type: MasterType.salonMaster,
  avgRating: 5.0,
  reviewCount: 3,
  services: <SalonCatalogService>[kSalonService],
  orderedMasterServiceIds: <String>['assign-m2-svc1'],
);

// `SalonTimeScreen` also `ref.watch`es `publicSalonProfileProvider`,
// `salonServiceCatalogProvider` and `salonMasterServiceCoverageProvider`
// before it can resolve a schedule and render `MasterSchedulePage` — mirrors
// `salon_time_screen_test.dart`'s `_baseOverrides` fixtures, narrowed to the
// single master ('m2') / single service ('svc-1') this file's salon route
// carries.
const String _kSalonId = 'salon-1';
const Salon _stubSalon = Salon(id: _kSalonId, name: 'Salon');

const SalonMasterSummary _stubM2 = SalonMasterSummary(
  masterId: 'm2',
  firstName: 'Sofia',
  lastName: 'Melnyk',
  avgRating: 5.0,
  reviewCount: 3,
  type: MasterType.salonMaster,
);

const List<SalonServiceCategoryEntry> _stubCatalog =
    <SalonServiceCategoryEntry>[
      SalonServiceCategoryEntry(
        category: 'MANICURE',
        displayName: 'Manicure',
        count: 1,
        services: <SalonCatalogService>[kSalonService],
      ),
    ];

// masterId -> {catalogServiceId: assignmentId} — must match exactly what
// `SalonTimeScreen` requests: `salonMasterServiceCoverageProvider` is a
// family keyed on `SalonBookingMasterSelectionArgs(salonId, selectedServiceIds)`
// rebuilt from this file's own `SalonBookingTimeArgs` (salonId 'salon-1',
// selectedServiceIds ['svc-1']) — an override keyed on anything else is
// silently never hit.
const Map<String, Map<String, String>> _stubCoverage =
    <String, Map<String, String>>{
      'm2': <String, String>{'svc-1': 'assign-m2-svc1'},
    };

void main() {
  testWidgets(
    'SlotDateScreen — crossing KYIV midnight moves the greyed-out past day: '
    'Aug 1 is tappable at 23:30 Kyiv and inert at 00:30, without remounting '
    'the screen',
    (WidgetTester tester) async {
      DateTime now = kBeforeKyivMidnight;
      final _FakeSlotRepository fake = _FakeSlotRepository();

      await tester.pumpRoutedApp(
        GoRouter(
          initialLocation: RouteNames.bookingSlots,
          routes: <RouteBase>[
            GoRoute(
              path: RouteNames.bookingSlots,
              builder: (BuildContext context, GoRouterState state) =>
                  const SlotDateScreen(
                    args: BookingSlotPickerArgs(
                      masterId: 'master-1',
                      master: kMaster,
                      services: <MasterService>[kService],
                    ),
                  ),
            ),
          ],
        ),
        overrides: <Object>[
          slotRepositoryProvider.overrideWith((_) => fake),
          // Mutable closure — a later read must see the later instant.
          clockProvider.overrideWithValue(() => now),
        ],
      );
      await tester.pumpAndSettle();

      // CONTROL — before the rollover Aug 1 IS today, so it is bookable. This
      // half matters: without it, the post-rollover assertion below could pass
      // because the cell was inert all along for some unrelated reason
      // (mobile-qa M14 — a negative assertion needs its positive twin).
      expect(
        cellIsTappable(1),
        isTrue,
        reason: 'at 23:30 Kyiv on Aug 1, Aug 1 is today and must be bookable',
      );
      expect(cellIsTappable(2), isTrue);

      // ── Kyiv midnight passes. Same UTC calendar day. ────────────────────
      now = kAfterKyivMidnight;

      // A real user interaction drives the repaint — tapping Aug 2, which is
      // bookable on both sides of the rollover.
      await tester.tapCalendarDay(2);
      await tester.pumpAndSettle();
      expect(fake.slotCallCount, 1);

      expect(
        cellIsTappable(1),
        isFalse,
        reason:
            'Aug 1 became YESTERDAY at Kyiv midnight. A `late final _today` '
            'captured in initState leaves it bookable for the life of the '
            'screen — the shipped bug.',
      );
      expect(
        cellIsTappable(2),
        isTrue,
        reason: 'Aug 2 is the new today and must stay bookable',
      );

      // Behavioural half: the now-past cell fetches nothing when tapped.
      // Tapped directly (NOT via `tapCalendarDay`, which asserts a handler is
      // present) precisely because proving the ABSENCE of a handler is the
      // point — see that helper's doc comment.
      await tester.tap(
        find.byKey(const Key('booking-calendar-day-1')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(
        fake.slotCallCount,
        1,
        reason: 'tapping the now-past Aug 1 must not fetch slots',
      );
    },
  );

  testWidgets(
    'MasterSchedulePage — crossing KYIV midnight moves the greyed-out past '
    'day on the salon step-3 picker too',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      DateTime now = kBeforeKyivMidnight;
      final _FakeSlotRepository fake = _FakeSlotRepository();

      await tester.pumpRoutedApp(
        GoRouter(
          initialLocation: RouteNames.salonBookingTime,
          routes: <RouteBase>[
            GoRoute(
              path: RouteNames.salonBookingTime,
              builder: (BuildContext context, GoRouterState state) =>
                  const SalonTimeScreen(
                    args: SalonBookingTimeArgs(
                      salonId: 'salon-1',
                      // kVisit (retired `visit:` shape) was master 'm2'
                      // assigned kSalonService ('svc-1') — expressed
                      // directly in the current shape.
                      selectedServiceIds: <String>['svc-1'],
                      assignedServiceIdsByMaster: <String, List<String>>{
                        'm2': <String>['svc-1'],
                      },
                    ),
                  ),
            ),
          ],
        ),
        overrides: <Object>[
          screenProtectionProvider.overrideWithValue(ScreenProtectionManager()),
          slotRepositoryProvider.overrideWith((_) => fake),
          clockProvider.overrideWithValue(() => now),
          publicSalonProfileProvider(_kSalonId).overrideWith(
            (ref) => (_stubSalon, const <SalonMasterSummary>[_stubM2]),
          ),
          salonServiceCatalogProvider(
            _kSalonId,
          ).overrideWith((ref) => _stubCatalog),
          salonMasterServiceCoverageProvider(
            const SalonBookingMasterSelectionArgs(
              salonId: _kSalonId,
              selectedServiceIds: <String>['svc-1'],
            ),
          ).overrideWith((ref) => _stubCoverage),
        ],
      );
      await tester.pumpAndSettle();

      expect(
        cellIsTappable(1),
        isTrue,
        reason: 'at 23:30 Kyiv on Aug 1, Aug 1 is today and must be bookable',
      );

      // ── Kyiv midnight passes. ──────────────────────────────────────────
      now = kAfterKyivMidnight;

      // Tapping a day here swaps the whole body to the TIME phase (the
      // calendar unmounts), so the repaint is driven by a month page-turn
      // instead — a real user interaction that lands back on the same month.
      await tester.tap(find.byKey(const Key('booking-calendar-next-month')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('booking-calendar-prev-month')));
      await tester.pumpAndSettle();

      expect(
        cellIsTappable(1),
        isFalse,
        reason:
            'Aug 1 became YESTERDAY at Kyiv midnight — a frozen initState '
            'capture leaves it bookable',
      );
      expect(cellIsTappable(2), isTrue);

      await tester.tap(
        find.byKey(const Key('booking-calendar-day-1')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(
        fake.slotCallCount,
        0,
        reason: 'tapping the now-past Aug 1 must not enter the time phase',
      );
    },
  );
}
