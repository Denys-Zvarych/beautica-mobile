// mobile-qa (multi-service booking rework) — the SIBLING-OVERLAP slot
// pre-disable matrix for `ServiceSchedulePage`, the independent-master flow's
// per-service time slide.
//
// `booking_time_screen_test.dart` proves ONE end-to-end sibling case through
// the full pager (schedule A, then B's overlapping chip is unreachable). This
// suite owns the exhaustive disable-logic MATRIX the dev deliberately handed to
// QA — driven by mounting a single slide with a pre-seeded schedule so every
// window / boundary / buffer / calendar-day permutation is exercised in
// isolation, asserting only the OBSERVABLE outcome (a chip's `available` flag,
// the fully-blocked empty state) — never internal call counts, so the known
// double-evaluation perf INFO is free to be fixed without touching this suite.
//
// Occupancy window per sibling = `[siblingSlot.startAt, startAt + duration +
// bufferAfter)`; overlap is HALF-OPEN. Matrix:
//   • a candidate slot overlapping a sibling window → disabled;
//   • a candidate slot clear of every sibling window → available;
//   • half-open END — a slot starting exactly at a sibling window's end → NOT
//     disabled (end is exclusive);
//   • half-open START — a slot ending exactly at a sibling window's start → NOT
//     disabled;
//   • buffer — `bufferMinutesAfter > 0` extends the occupied tail, so a slot
//     inside that tail is disabled (it would be free without the buffer);
//   • a sibling on a DIFFERENT calendar day disables nothing here;
//   • every slot blocked by siblings → `_SiblingBlockedEmptyState` (title +
//     message + change-date CTA) instead of an all-disabled grid;
//   • mutating a sibling's slot/date re-computes THIS slide's disables (the
//     whole-provider watch).

import 'package:beautica_mobile/features/booking/application/independent_booking_schedule_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/slot_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking_slot.dart';
import 'package:beautica_mobile/features/booking/domain/working_day.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/service_schedule_page.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/slot_chip.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const String _curId = 'svc-cur';
const String _sibId = 'svc-sib';

const _kMaster = Master(
  id: 'master-1',
  firstName: 'Олена',
  lastName: 'Ковальчук',
  city: 'Київ',
  street: 'вул. Хрещатик',
  buildingNo: '22',
  avgRating: 4.8,
  reviewCount: 47,
  type: MasterType.independentMaster,
);

// The slide's OWN service. Its real duration/buffer are irrelevant to the
// matrix — occupancy reaches the widget purely through the explicit
// `occupancyMinutesByServiceId` map, so every window/buffer permutation is set
// there, decoupled from `MasterService`'s own fields.
const _curService = MasterService(
  id: _curId,
  serviceDefId: 'def-cur',
  name: 'Манікюр з покриттям',
  durationMinutes: 60,
  priceMin: 500,
  priceDisplay: '500 ₴',
  category: 'NAILS',
);

final AppLocalizations _l10n = lookupAppLocalizations(const Locale('uk'));

/// A [SlotRepository] fake that returns a fixed slot list for the current
/// service's day and reports every day as working (needed once the empty-state
/// CTA returns the slide to its date phase).
class _FakeSlotRepository implements SlotRepository {
  _FakeSlotRepository(this.daySlots);

  final List<BookingSlot> daySlots;

  @override
  Future<List<BookingSlot>> getMasterSlots({
    required String masterId,
    required String serviceId,
    required DateTime date,
    CancelToken? cancelToken,
  }) async => daySlots;

  @override
  Future<List<WorkingDay>> getWorkingDays({
    required String masterId,
    required DateTime from,
    required DateTime to,
    String? serviceId,
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

/// A schedule notifier pre-seeded with a fixed state, retaining the real
/// `selectDate`/`selectSlot`/`clearDate` methods so the reactive test can
/// mutate a sibling after mount and the whole-schedule watch re-runs.
class _SeededSchedule extends IndependentBookingSchedule {
  _SeededSchedule(this._seed);

  final IndependentBookingScheduleState _seed;

  @override
  IndependentBookingScheduleState build() => _seed;
}

void main() {
  // A fixed "today" inside the 3-month calendar horizon; date-only D and D+1.
  final DateTime now = DateTime.now();
  final DateTime dayD = DateTime(now.year, now.month, now.day);
  final DateTime dayNext = dayD.add(const Duration(days: 1));

  DateTime on(DateTime day, int hour, [int minute = 0]) =>
      DateTime(day.year, day.month, day.day, hour, minute);

  BookingSlot slot(DateTime day, int hour, [int minute = 0]) => BookingSlot(
    startAt: on(day, hour, minute),
    endAt: on(day, hour, minute).add(const Duration(hours: 1)),
    available: true,
  );

  /// Seed: the CURRENT service sits in the time phase on [curDate] (date, no
  /// slot); each sibling entry in [siblings] is fully scheduled.
  IndependentBookingScheduleState seed({
    required DateTime curDate,
    Map<String, BookingSlot> siblings = const <String, BookingSlot>{},
  }) => IndependentBookingScheduleState(
    entries: <String, IndependentScheduleEntry>{
      _curId: IndependentScheduleEntry(date: curDate),
      for (final MapEntry<String, BookingSlot> e in siblings.entries)
        e.key: IndependentScheduleEntry(
          date: DateTime(
            e.value.startAt.year,
            e.value.startAt.month,
            e.value.startAt.day,
          ),
          slot: e.value,
        ),
    },
  );

  /// Mounts the single slide and returns the tree's [ProviderContainer] (so the
  /// reactive test can drive the notifier post-mount).
  Future<ProviderContainer> pumpSlide(
    WidgetTester tester, {
    required IndependentBookingScheduleState initial,
    required List<BookingSlot> daySlots,
    required Map<String, int> occupancy,
  }) async {
    // Tall surface so the whole slot grid is on-screen without scrolling.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpApp(
      ServiceSchedulePage(
        master: _kMaster,
        service: _curService,
        occupancyMinutesByServiceId: occupancy,
        onCompleted: () {},
        keepAlive: true,
      ),
      overrides: <Object>[
        slotRepositoryProvider.overrideWith(
          (_) => _FakeSlotRepository(daySlots),
        ),
        independentBookingScheduleProvider.overrideWith(
          () => _SeededSchedule(initial),
        ),
      ],
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(ServiceSchedulePage)),
    );
  }

  Finder chip(DateTime start) =>
      find.byKey(Key('independent-slot-chip-${start.toIso8601String()}'));

  bool available(WidgetTester tester, DateTime start) =>
      tester.widget<SlotChip>(chip(start)).available;

  // -------------------------------------------------------------------------

  testWidgets(
    'a candidate slot overlapping a sibling window is disabled; a slot clear of '
    'every sibling window stays available',
    (tester) async {
      // Sibling scheduled 10:00 (60 min → occupies [10:00, 11:00)). Current
      // service offers 10:30 (→ [10:30, 11:30), overlaps) and 14:00 (clear).
      await pumpSlide(
        tester,
        initial: seed(
          curDate: dayD,
          siblings: <String, BookingSlot>{_sibId: slot(dayD, 10)},
        ),
        daySlots: <BookingSlot>[slot(dayD, 10, 30), slot(dayD, 14)],
        occupancy: const <String, int>{_curId: 60, _sibId: 60},
      );

      expect(
        available(tester, on(dayD, 10, 30)),
        isFalse,
        reason: '10:30–11:30 overlaps the sibling window [10:00,11:00)',
      );
      expect(
        available(tester, on(dayD, 14)),
        isTrue,
        reason: '14:00–15:00 is clear of every sibling window',
      );
    },
  );

  testWidgets(
    'half-open END: a slot STARTING exactly at a sibling window end is NOT '
    'disabled (end is exclusive)',
    (tester) async {
      // Sibling window [10:00, 11:00). Current slot starts exactly at 11:00.
      await pumpSlide(
        tester,
        initial: seed(
          curDate: dayD,
          siblings: <String, BookingSlot>{_sibId: slot(dayD, 10)},
        ),
        daySlots: <BookingSlot>[slot(dayD, 11)],
        occupancy: const <String, int>{_curId: 60, _sibId: 60},
      );

      expect(
        available(tester, on(dayD, 11)),
        isTrue,
        reason: 'startAt == window end → half-open interval leaves it free',
      );
    },
  );

  testWidgets(
    'half-open START: a slot ENDING exactly at a sibling window start is NOT '
    'disabled',
    (tester) async {
      // Sibling window [11:00, 12:00). Current slot 10:00–11:00 ends exactly at
      // the sibling start.
      await pumpSlide(
        tester,
        initial: seed(
          curDate: dayD,
          siblings: <String, BookingSlot>{_sibId: slot(dayD, 11)},
        ),
        daySlots: <BookingSlot>[slot(dayD, 10)],
        occupancy: const <String, int>{_curId: 60, _sibId: 60},
      );

      expect(
        available(tester, on(dayD, 10)),
        isTrue,
        reason: 'slotEnd == window start → touching but not overlapping',
      );
    },
  );

  testWidgets(
    'bufferMinutesAfter extends the occupied window, disabling a slot that would '
    'be free at the bare-duration boundary',
    (tester) async {
      // Sibling occupancy 90 (60 duration + 30 buffer) → window [10:00, 11:30).
      // The 11:00 slot would be exactly at the 11:00 bare-duration boundary
      // (free), but the buffer tail to 11:30 pulls it inside → disabled. A clear
      // 14:00 slot keeps the grid rendered (so this isn't the all-blocked case).
      await pumpSlide(
        tester,
        initial: seed(
          curDate: dayD,
          siblings: <String, BookingSlot>{_sibId: slot(dayD, 10)},
        ),
        daySlots: <BookingSlot>[slot(dayD, 11), slot(dayD, 14)],
        occupancy: const <String, int>{_curId: 60, _sibId: 90},
      );

      expect(
        available(tester, on(dayD, 11)),
        isFalse,
        reason: 'the 30-min buffer tail [11:00,11:30) captures the 11:00 slot',
      );
      expect(
        available(tester, on(dayD, 14)),
        isTrue,
        reason: 'the 14:00 slot sits well past the buffer tail → still free',
      );
    },
  );

  testWidgets('a sibling on a DIFFERENT calendar day disables nothing here', (
    tester,
  ) async {
    // Sibling scheduled at 10:00 on D+1; current service on D also offers
    // 10:00. Same clock time, different day → no exclusion.
    await pumpSlide(
      tester,
      initial: seed(
        curDate: dayD,
        siblings: <String, BookingSlot>{_sibId: slot(dayNext, 10)},
      ),
      daySlots: <BookingSlot>[slot(dayD, 10)],
      occupancy: const <String, int>{_curId: 60, _sibId: 60},
    );

    expect(
      available(tester, on(dayD, 10)),
      isTrue,
      reason: 'the sibling window lives on D+1 — it never groups onto D',
    );
  });

  testWidgets(
    'every slot blocked by a sibling → the sibling-blocked empty state (title + '
    'message + change-date CTA) instead of an all-disabled grid',
    (tester) async {
      // Sibling occupancy 600 min from 09:00 → window [09:00, 19:00) swallows
      // both offered slots (10:00 and 14:00).
      final ProviderContainer container = await pumpSlide(
        tester,
        initial: seed(
          curDate: dayD,
          siblings: <String, BookingSlot>{_sibId: slot(dayD, 9)},
        ),
        daySlots: <BookingSlot>[slot(dayD, 10), slot(dayD, 14)],
        occupancy: const <String, int>{_curId: 60, _sibId: 600},
      );

      expect(
        find.byKey(const Key('service-schedule-sibling-blocked-empty-state')),
        findsOneWidget,
      );
      expect(find.text(_l10n.bookingSiblingBlockedTitle), findsOneWidget);
      expect(find.text(_l10n.bookingSiblingBlockedMessage), findsOneWidget);
      // No grid of disabled chips is rendered in the blocked state.
      expect(chip(on(dayD, 10)), findsNothing);
      expect(chip(on(dayD, 14)), findsNothing);

      // The change-date CTA clears the current service's date → back to the
      // date phase (calendar), never trapping the client on the blocked day.
      await tester.tap(
        find.byKey(const Key('service-schedule-sibling-blocked-change-date')),
      );
      await tester.pumpAndSettle();

      expect(
        container
            .read(independentBookingScheduleProvider)
            .entryFor(_curId)
            .date,
        isNull,
        reason:
            'the CTA clears the date, returning the slide to date selection',
      );
      expect(
        find.byKey(const Key('service-schedule-sibling-blocked-empty-state')),
        findsNothing,
      );
      expect(find.byKey(const Key('booking-month-calendar')), findsOneWidget);
    },
  );

  testWidgets(
    'mutating a sibling from a different day onto THIS day re-computes the '
    'disables (whole-provider watch)',
    (tester) async {
      // Start with the sibling on D+1 → the current 10:00 slot is free. A clear
      // 14:00 slot always stays free, so once 10:00 disables the grid still
      // renders (never collapsing to the all-blocked empty state).
      final ProviderContainer container = await pumpSlide(
        tester,
        initial: seed(
          curDate: dayD,
          siblings: <String, BookingSlot>{_sibId: slot(dayNext, 10)},
        ),
        daySlots: <BookingSlot>[slot(dayD, 10), slot(dayD, 14)],
        occupancy: const <String, int>{_curId: 60, _sibId: 60},
      );
      expect(
        available(tester, on(dayD, 10)),
        isTrue,
        reason: 'sibling on D+1 leaves the D 10:00 slot free at first',
      );

      // Move the sibling onto D at 10:00 — the slide must re-disable the now
      // overlapping chip without any interaction on this slide.
      container
          .read(independentBookingScheduleProvider.notifier)
          .selectSlot(_sibId, slot(dayD, 10));
      // selectSlot preserves the sibling's existing date (D+1); re-point it to D
      // so the window groups onto this slide's day.
      container
          .read(independentBookingScheduleProvider.notifier)
          .selectDate(_sibId, dayD);
      container
          .read(independentBookingScheduleProvider.notifier)
          .selectSlot(_sibId, slot(dayD, 10));
      await tester.pumpAndSettle();

      expect(
        available(tester, on(dayD, 10)),
        isFalse,
        reason: 'the moved sibling now overlaps → the chip re-disables live',
      );
    },
  );
}
