// MO-4 — Widget tests for the reworked SalonTimeScreen (single date + time).
//
// Covers:
//   1. Availability (working-days + slots) is requested for the chosen master
//      with ALL ordered per-master assignment ids (summed block).
//   2. Tapping a day → time phase; picking a slot enables «Далі», which pushes
//      /booking/salon/confirm with the visit, the chosen start, and a minted
//      idempotency key.
//   3. Back from the time phase clears the date (returns to the calendar).
//   4. Fresh-on-re-pick: a second push after re-picking a time mints a NEW
//      idempotency key.

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/slot_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking_slot.dart';
import 'package:beautica_mobile/features/booking/domain/salon_booking_args.dart';
import 'package:beautica_mobile/features/booking/domain/salon_booking_confirm_args.dart';
import 'package:beautica_mobile/features/booking/domain/salon_master_schedule.dart';
import 'package:beautica_mobile/features/booking/domain/working_day.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_time_screen.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/pump_app.dart';

const _svc1 = SalonCatalogService(
  id: 'svc-1',
  name: 'Манікюр з покриттям',
  durationLabel: '1 год 30 хв',
  priceDisplay: '500 ₴',
  durationMinutes: 90,
  priceType: ServicePriceType.fixed,
  priceMin: 500,
);
const _svc2 = SalonCatalogService(
  id: 'svc-2',
  name: 'Педикюр',
  durationLabel: '2 год',
  priceDisplay: '800 ₴',
  durationMinutes: 120,
  priceType: ServicePriceType.fixed,
  priceMin: 800,
);

const _visit = SalonMasterSchedule(
  masterId: 'm2',
  firstName: 'Софія',
  lastName: 'Мельник',
  type: MasterType.salonMaster,
  avgRating: 5.0,
  reviewCount: 3,
  services: <SalonCatalogService>[_svc1, _svc2],
  orderedMasterServiceIds: <String>['assign-m2-svc1', 'assign-m2-svc2'],
);

SalonBookingTimeArgs _args() =>
    const SalonBookingTimeArgs(salonId: 'salon-1', visit: _visit);

class _FakeSlotRepository implements SlotRepository {
  _FakeSlotRepository(this._slotsFor);

  final List<BookingSlot> Function(DateTime date) _slotsFor;

  List<String>? lastSlotServiceIds;
  List<String>? lastWorkingDaysServiceIds;

  @override
  Future<List<BookingSlot>> getMasterSlots({
    required String masterId,
    required List<String> serviceIds,
    required DateTime date,
    CancelToken? cancelToken,
  }) async {
    lastSlotServiceIds = serviceIds;
    return _slotsFor(date);
  }

  @override
  Future<List<WorkingDay>> getWorkingDays({
    required String masterId,
    required DateTime from,
    required DateTime to,
    List<String>? serviceIds,
    CancelToken? cancelToken,
  }) async {
    lastWorkingDaysServiceIds = serviceIds;
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

/// Two bookable slots on [date], expressed as UTC INSTANTS — the shape the
/// wire actually delivers.
///
/// DO NOT COPY THE OLD FORM OF THIS HELPER. It built these with a bare local
/// `DateTime(date.year, date.month, date.day, 10)`, which made it a
/// FIXTURE TRAP for the whole slot-picker surface (fixed 2026-08-11):
///
///   • `.hour` on a host-local instant happens to equal the Kyiv wall-clock
///     hour on the Kyiv dev VM, so any bug that reads the raw `.hour` where it
///     should read the Kyiv hour is INVISIBLE to such a fixture — locally.
///     That is exactly how the Ранок/День/Вечір heading bug shipped: headings
///     bucketed on `startAt.hour` (UTC) while the chip beside them rendered
///     `formatSlotTime` (Kyiv), and every fixture in this file agreed with
///     both. See `slot_bucket_heading_tz_test.dart` for the tests that pin it.
///   • The instant itself moved with the host `TZ`, so what this file pinned
///     differed between the dev VM (Europe/Kyiv) and CI (UTC).
///
/// Nothing in THIS file asserts a rendered chip LABEL — it asserts chip `Key`s
/// (raw UTC ISO, identity only) and the `startAt` threaded onto the confirm
/// args — so the switch to `.utc` is assertion-neutral here. It exists so the
/// next fixture copied from this file is a real instant.
List<BookingSlot> _twoSlots(DateTime date) => <BookingSlot>[
  BookingSlot(
    startAt: DateTime.utc(date.year, date.month, date.day, 10),
    endAt: DateTime.utc(date.year, date.month, date.day, 13, 30),
    available: true,
  ),
  BookingSlot(
    startAt: DateTime.utc(date.year, date.month, date.day, 14),
    endAt: DateTime.utc(date.year, date.month, date.day, 17, 30),
    available: true,
  ),
];

GoRouter _router(
  _FakeSlotRepository fake, {
  ValueChanged<SalonBookingConfirmArgs>? onConfirm,
}) => GoRouter(
  initialLocation: RouteNames.salonBookingTime,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.salonBookingTime,
      builder: (context, state) => SalonTimeScreen(args: _args()),
    ),
    GoRoute(
      path: RouteNames.salonBookingConfirm,
      builder: (context, state) {
        onConfirm?.call(state.extra! as SalonBookingConfirmArgs);
        return Scaffold(
          body: Center(
            child: TextButton(
              key: const Key('confirm-back'),
              onPressed: () => context.pop(),
              child: const Text('salon-confirm-reached'),
            ),
          ),
        );
      },
    ),
  ],
);

List<Object> _overrides(_FakeSlotRepository fake) => <Object>[
  screenProtectionProvider.overrideWithValue(ScreenProtectionManager()),
  slotRepositoryProvider.overrideWith((_) => fake),
];

Future<void> _pumpTall(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('working-days availability requested with ALL ordered ids', (
    tester,
  ) async {
    await _pumpTall(tester);
    final fake = _FakeSlotRepository(_twoSlots);
    await tester.pumpRoutedApp(_router(fake), overrides: _overrides(fake));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('booking-month-calendar')), findsOneWidget);
    expect(fake.lastWorkingDaysServiceIds, <String>[
      'assign-m2-svc1',
      'assign-m2-svc2',
    ]);
  });

  testWidgets(
    'pick day → slots requested with ALL ordered ids; pick slot → «Далі» '
    'pushes confirm with the visit + start + a minted key',
    (tester) async {
      await _pumpTall(tester);
      final fake = _FakeSlotRepository(_twoSlots);
      SalonBookingConfirmArgs? confirmArgs;
      await tester.pumpRoutedApp(
        _router(fake, onConfirm: (a) => confirmArgs = a),
        overrides: _overrides(fake),
      );
      await tester.pumpAndSettle();

      final DateTime today = kyivToday(DateTime.now);
      await tester.tapCalendarDay(today.day);
      await tester.pumpAndSettle();

      // Time phase: slots fetched with ALL ordered ids.
      expect(fake.lastSlotServiceIds, <String>[
        'assign-m2-svc1',
        'assign-m2-svc2',
      ]);

      final DateTime slotStart = DateTime.utc(
        today.year,
        today.month,
        today.day,
        10,
      );
      final Finder chip = find.byKey(
        Key('salon-slot-chip-${slotStart.toIso8601String()}'),
      );
      expect(chip, findsOneWidget);
      await tester.tap(chip);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('booking-summary-cta')));
      await tester.pumpAndSettle();

      expect(find.text('salon-confirm-reached'), findsOneWidget);
      expect(confirmArgs, isNotNull);
      expect(confirmArgs!.visit.masterId, 'm2');
      expect(confirmArgs!.startAt, slotStart);
      expect(confirmArgs!.idempotencyKey, isNotEmpty);
    },
  );

  testWidgets('a fresh idempotency key is minted on each re-pick', (
    tester,
  ) async {
    await _pumpTall(tester);
    final fake = _FakeSlotRepository(_twoSlots);
    final List<String> keys = <String>[];
    await tester.pumpRoutedApp(
      _router(fake, onConfirm: (a) => keys.add(a.idempotencyKey)),
      overrides: _overrides(fake),
    );
    await tester.pumpAndSettle();

    final DateTime today = kyivToday(DateTime.now);
    await tester.tapCalendarDay(today.day);
    await tester.pumpAndSettle();

    final DateTime slotA = DateTime.utc(today.year, today.month, today.day, 10);
    await tester.tap(
      find.byKey(Key('salon-slot-chip-${slotA.toIso8601String()}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('booking-summary-cta')));
    await tester.pumpAndSettle();
    // Back to the time screen (confirm stub's back button).
    await tester.tap(find.byKey(const Key('confirm-back')));
    await tester.pumpAndSettle();

    // Re-pick another slot and confirm again → fresh key.
    final DateTime slotB = DateTime.utc(today.year, today.month, today.day, 14);
    await tester.tap(
      find.byKey(Key('salon-slot-chip-${slotB.toIso8601String()}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('booking-summary-cta')));
    await tester.pumpAndSettle();

    expect(keys, hasLength(2));
    expect(keys[0], isNot(keys[1]));
  });

  testWidgets('back from the time phase returns to the calendar', (
    tester,
  ) async {
    await _pumpTall(tester);
    final fake = _FakeSlotRepository(_twoSlots);
    await tester.pumpRoutedApp(_router(fake), overrides: _overrides(fake));
    await tester.pumpAndSettle();

    final DateTime today = kyivToday(DateTime.now);
    await tester.tapCalendarDay(today.day);
    await tester.pumpAndSettle();
    // In time phase now — the calendar is gone.
    expect(find.byKey(const Key('booking-month-calendar')), findsNothing);

    await tester.tap(find.byKey(const Key('salon-time-back')));
    await tester.pumpAndSettle();
    // Back to the date phase.
    expect(find.byKey(const Key('booking-month-calendar')), findsOneWidget);
  });
}
