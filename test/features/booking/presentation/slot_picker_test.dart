// Phase 14.1 — Widget tests for SlotDateScreen + SlotTimeScreen.
//
// Covers the phase doc's acceptance criteria:
//   1. Day selection loads that day's slots via SlotRepository.
//   2. "Далі" only advances once a day is selected.
//   3. Unavailable slots are not tappable (selection stays unset).
//   4. Selecting an available slot navigates to /booking/confirm with the
//      correct (masterId, serviceId, startAt) extras, threading a non-null
//      rescheduleBookingId through when present (the Phase 14.8 extension
//      point).
//
// Strategy: mounts the REAL production routes/screens via a test-local
// GoRouter mirroring app_router.dart's shape (bookingSlots → nested "time" →
// bookingConfirm), overriding [slotRepositoryProvider] with a hand-written
// fake so no real Dio request is ever made.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/slot_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking_confirm_args.dart';
import 'package:beautica_mobile/features/booking/domain/booking_slot.dart';
import 'package:beautica_mobile/features/booking/domain/booking_slot_picker_args.dart';
import 'package:beautica_mobile/features/booking/domain/working_day.dart';
import 'package:beautica_mobile/features/booking/presentation/slot_picker_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_strip.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/slot_chip.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/pump_app.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

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
  priceDisplay: '500 ₴',
  category: 'MANICURE',
);

BookingSlotPickerArgs _args({String? rescheduleBookingId}) =>
    BookingSlotPickerArgs(
      masterId: _kMaster.id,
      master: _kMaster,
      services: const <MasterService>[_kService],
      rescheduleBookingId: rescheduleBookingId,
    );

/// Records every call so the "loads slots on date change" criterion can be
/// asserted directly, and returns whatever [slotsToReturn] is configured —
/// or throws [errorToThrow] when set (mobile-qa M3: every screen's data
/// fetch needs a failure-path test, not just happy-path fixtures).
///
/// [getWorkingDays] defaults to "every requested day is working" (via
/// [workingDaysOverride] returning `null`), so day-tap fixtures written
/// before the Phase 14.14 calendar gate keep behaving exactly as before
/// without every test needing to configure it explicitly. Pass
/// [workingDaysOverride] to test the gate itself, or [workingDaysErrorToThrow]
/// to test its failure path.
class _FakeSlotRepository implements SlotRepository {
  _FakeSlotRepository(
    this.slotsToReturn, {
    this.errorToThrow,
    this.workingDaysOverride,
    this.workingDaysErrorToThrow,
  });

  List<BookingSlot> slotsToReturn;
  Object? errorToThrow;
  int callCount = 0;
  String? lastMasterId;
  String? lastServiceId;
  DateTime? lastDate;

  /// Per-date override for [getWorkingDays]; `null` (the default) means
  /// every requested date resolves `working: true`. The callback also receives
  /// the `serviceId` the request carried, so a test can model the backend's
  /// two MODES (Phase 14.20): availability-aware when non-null vs the older
  /// schedule-shape signal when null — the exact discriminator the
  /// calendar-vs-slots regression pivots on.
  bool? Function(DateTime day, String? serviceId)? workingDaysOverride;
  Object? workingDaysErrorToThrow;
  int workingDaysCallCount = 0;
  String? lastWorkingDaysMasterId;
  DateTime? lastWorkingDaysFrom;
  DateTime? lastWorkingDaysTo;

  /// The `serviceId` the MOST RECENT [getWorkingDays] call carried. Phase
  /// 14.20 fix pins that the booking calendar threads
  /// `args.services.first.id` into the working-days query (so its `working`
  /// flags become availability-aware); `null` here would mean the calendar
  /// silently fell back to the duration-blind schedule-shape mode — the
  /// pre-fix bug.
  String? lastWorkingDaysServiceId;

  /// When set, [getWorkingDays] awaits this [Completer]'s future before
  /// resolving — lets a test hold a fetch "in flight" to assert the
  /// loading/reload UX (full-screen spinner on genuine first load; stale
  /// grid + thin top progress line on a month-step reload) instead of only
  /// ever observing the settled end state. Consumed once per call (the test
  /// re-assigns a fresh [Completer] before triggering the next gated fetch).
  Completer<void>? workingDaysGate;

  /// Dates to silently DROP from the [getWorkingDays] response (the
  /// requested `[from, to]` window still nominally covers them). Exercises
  /// `_availabilityFrom`'s "a day absent from the resolved set defaults to
  /// non-working" conservative fallback — distinct from
  /// [workingDaysOverride], which always returns an entry (explicitly
  /// `working: false`) for every requested day.
  Set<DateTime> omitFromWorkingDaysResponse = <DateTime>{};

  @override
  Future<List<BookingSlot>> getMasterSlots({
    required String masterId,
    required List<String> serviceIds,
    required DateTime date,
    CancelToken? cancelToken,
  }) async {
    callCount++;
    lastMasterId = masterId;
    // MO-2: these widget tests drive the single-service path (N=1), so the
    // first (only) id is captured into the existing single-String? field —
    // every assertion (`expect(fake.lastServiceId, _kService.id)`) is unchanged.
    lastServiceId = serviceIds.isEmpty ? null : serviceIds.first;
    lastDate = date;
    final Object? err = errorToThrow;
    if (err != null) throw err;
    return slotsToReturn;
  }

  @override
  Future<List<WorkingDay>> getWorkingDays({
    required String masterId,
    required DateTime from,
    required DateTime to,
    List<String>? serviceIds,
    CancelToken? cancelToken,
  }) async {
    workingDaysCallCount++;
    lastWorkingDaysMasterId = masterId;
    lastWorkingDaysFrom = from;
    lastWorkingDaysTo = to;
    // MO-2: single-service path — collapse the one-element list back to the
    // String? discriminator these tests key the two working-days modes on.
    final String? serviceId = serviceIds == null || serviceIds.isEmpty
        ? null
        : serviceIds.first;
    lastWorkingDaysServiceId = serviceId;
    final Completer<void>? gate = workingDaysGate;
    if (gate != null) await gate.future;
    final Object? err = workingDaysErrorToThrow;
    if (err != null) throw err;
    final List<WorkingDay> days = <WorkingDay>[];
    for (
      DateTime d = from;
      !d.isAfter(to);
      d = d.add(const Duration(days: 1))
    ) {
      if (omitFromWorkingDaysResponse.contains(d)) continue;
      days.add(
        WorkingDay(
          date: d,
          working: workingDaysOverride?.call(d, serviceId) ?? true,
        ),
      );
    }
    return days;
  }
}

/// Builds the test-local router mirroring `app_router.dart`'s bookingSlots /
/// bookingSlots/time / bookingConfirm shape, with the confirm route rendering
/// the received [BookingConfirmArgs] as plain text so tests can assert the
/// exact extras that arrived.
GoRouter _router({required Widget dateScreen}) => GoRouter(
  initialLocation: RouteNames.bookingSlots,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.bookingSlots,
      builder: (context, state) => dateScreen,
      routes: <RouteBase>[
        GoRoute(
          path: 'time',
          builder: (context, state) =>
              SlotTimeScreen(args: state.extra! as BookingSlotPickerArgs),
        ),
      ],
    ),
    GoRoute(
      path: RouteNames.bookingConfirm,
      builder: (context, state) {
        final BookingConfirmArgs args = state.extra! as BookingConfirmArgs;
        return Scaffold(
          body: Text(
            'confirm-stub:${args.masterId}:${args.services.first.id}:'
            '${args.startAt.toIso8601String()}:${args.rescheduleBookingId}',
          ),
        );
      },
    ),
  ],
);

void main() {
  group('SlotDateScreen', () {
    testWidgets('tapping an available day loads that day\'s slots', (
      tester,
    ) async {
      final fake = _FakeSlotRepository(const <BookingSlot>[]);
      final router = _router(dateScreen: SlotDateScreen(args: _args()));

      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[slotRepositoryProvider.overrideWith((_) => fake)],
      );
      await tester.pumpAndSettle();

      final DateTime today = DateTime.now();
      final Finder todayCell = find.byKey(
        Key('booking-calendar-day-${today.day}'),
      );
      expect(todayCell, findsOneWidget);

      await tester.tapCalendarDay(today.day);
      await tester.pumpAndSettle();

      expect(fake.callCount, 1);
      expect(fake.lastMasterId, _kMaster.id);
      expect(fake.lastServiceId, _kService.id);
      expect(fake.lastDate, DateTime(today.year, today.month, today.day));
    });

    // Phase 14.14 — real end-to-end wiring test: a day the WORKING-DAYS
    // provider marks non-working must be untappable, distinct from
    // `month_calendar_test.dart`'s isolated widget-level coverage of the
    // same contract.
    testWidgets(
      'a day the working-days fetch marks working:false cannot be selected '
      'and never loads slots',
      (tester) async {
        final DateTime today = DateTime.now();
        final DateTime todayDateOnly = DateTime(
          today.year,
          today.month,
          today.day,
        );
        final fake = _FakeSlotRepository(
          const <BookingSlot>[],
          workingDaysOverride: (DateTime day, String? serviceId) =>
              day != todayDateOnly,
        );
        final router = _router(dateScreen: SlotDateScreen(args: _args()));

        await tester.pumpRoutedApp(
          router,
          overrides: <Object>[slotRepositoryProvider.overrideWith((_) => fake)],
        );
        await tester.pumpAndSettle();

        final Finder todayCell = find.byKey(
          Key('booking-calendar-day-${today.day}'),
        );
        expect(todayCell, findsOneWidget);
        expect(
          find.descendant(
            of: todayCell,
            matching: find.byType(GestureDetector),
          ),
          findsNothing,
        );

        await tester.tap(todayCell, warnIfMissed: false);
        await tester.pumpAndSettle();

        // No slots fetch was ever triggered, and «Далі» stays disabled since
        // no date was selected.
        expect(fake.callCount, 0);
        await tester.tap(find.byKey(const Key('booking-summary-cta')));
        await tester.pumpAndSettle();
        expect(find.byType(SlotTimeScreen), findsNothing);
      },
    );

    // Phase 14.20 REGRESSION — the calendar-vs-slots availability bug. Before
    // the fix, `SlotDateScreen` requested working-days in SCHEDULE-SHAPE mode
    // (no serviceId): a day the master had intervals on rendered selectable
    // even when the chosen service's duration left zero bookable slots on it,
    // so tapping it dead-ended on «Немає вільного часу». The fix threads
    // `args.services.first.id` into the query so the `working` flag becomes
    // AVAILABILITY-AWARE.
    //
    // This test discriminates the two modes: the fake returns `working:false`
    // for TODAY ONLY when a serviceId rode along (availability-aware), and
    // `working:true` when it did not (the pre-fix schedule-shape path). So it
    // FAILS against the old behaviour — old code sends no serviceId → today
    // resolves working:true → the cell is tappable → it loads slots and the
    // flow advances to the dead-end — and PASSES now: the fix sends the
    // serviceId → today resolves working:false → the cell is inert.
    testWidgets(
      'a day bookable in schedule-shape mode but with no slot for the chosen '
      'service is disabled once the calendar is service-scoped (Phase 14.20 '
      'availability-aware gate) — never tappable, never loads slots',
      (tester) async {
        final DateTime today = DateTime.now();
        final DateTime todayDateOnly = DateTime(
          today.year,
          today.month,
          today.day,
        );
        final fake = _FakeSlotRepository(
          const <BookingSlot>[],
          // Availability-aware mode (serviceId present): TODAY has no bookable
          // slot for this service → working:false. Schedule-shape mode
          // (serviceId null — the pre-fix request) is duration-blind and would
          // wrongly report it working:true. Discriminating on serviceId is
          // what makes this test catch the original bug rather than merely
          // re-proving the Phase 14.14 gate.
          workingDaysOverride: (DateTime day, String? serviceId) {
            if (serviceId == null) return true;
            return day != todayDateOnly;
          },
        );
        final router = _router(dateScreen: SlotDateScreen(args: _args()));

        await tester.pumpRoutedApp(
          router,
          overrides: <Object>[slotRepositoryProvider.overrideWith((_) => fake)],
        );
        await tester.pumpAndSettle();

        // Sanity: the calendar really asked in availability-aware mode.
        expect(
          fake.lastWorkingDaysServiceId,
          _kService.id,
          reason:
              'the booking calendar must thread the primary service id into '
              'the working-days query — this is the Phase 14.20 fix under test',
        );

        final Finder todayCell = find.byKey(
          Key('booking-calendar-day-${today.day}'),
        );
        expect(todayCell, findsOneWidget);
        expect(
          find.descendant(
            of: todayCell,
            matching: find.byType(GestureDetector),
          ),
          findsNothing,
          reason:
              'a day the service-scoped endpoint marks working:false must '
              'render without a tap handler (old, schedule-shape code left it '
              'tappable — that IS the bug)',
        );

        await tester.tap(todayCell, warnIfMissed: false);
        await tester.pumpAndSettle();

        // No slots fetch fired, and «Далі» stays disabled (no date selected),
        // so the client can never reach the «Немає вільного часу» dead-end.
        expect(fake.callCount, 0);
        await tester.tap(find.byKey(const Key('booking-summary-cta')));
        await tester.pumpAndSettle();
        expect(find.byType(SlotTimeScreen), findsNothing);
      },
    );

    // Phase 14.20 positive counterpart — guards against OVER-disabling: a day
    // the availability-aware endpoint marks working:true must stay tappable
    // and still load its slots. Without this, a fix that disabled every day
    // would also make the regression above pass while breaking the app.
    testWidgets(
      'a day the service-scoped working-days query marks working:true stays '
      'enabled and loads its slots on tap',
      (tester) async {
        final DateTime today = DateTime.now();
        final fake = _FakeSlotRepository(
          const <BookingSlot>[],
          // Availability-aware mode reports EVERY day working:true here.
          workingDaysOverride: (DateTime day, String? serviceId) => true,
        );
        final router = _router(dateScreen: SlotDateScreen(args: _args()));

        await tester.pumpRoutedApp(
          router,
          overrides: <Object>[slotRepositoryProvider.overrideWith((_) => fake)],
        );
        await tester.pumpAndSettle();

        final Finder todayCell = find.byKey(
          Key('booking-calendar-day-${today.day}'),
        );
        expect(todayCell, findsOneWidget);
        expect(
          find.descendant(
            of: todayCell,
            matching: find.byType(GestureDetector),
          ),
          findsOneWidget,
          reason:
              'a working:true day must keep its tap handler — the gate must '
              'not over-disable available days',
        );

        await tester.tapCalendarDay(today.day);
        await tester.pumpAndSettle();

        expect(fake.callCount, 1);
        expect(fake.lastServiceId, _kService.id);
        expect(fake.lastDate, DateTime(today.year, today.month, today.day));
      },
    );

    // Phase 14.20 wiring pin — the working-days request the calendar issues
    // must carry `serviceId == args.services.first.id`. A future refactor that
    // dropped the serviceId (reverting to schedule-shape) would silently
    // reintroduce the calendar-vs-slots disagreement; this catches it directly
    // at the query boundary, independent of any particular day's verdict.
    testWidgets(
      'the booking calendar issues its working-days query with the primary '
      'service id (services.first.id), never schedule-shape (null)',
      (tester) async {
        final fake = _FakeSlotRepository(const <BookingSlot>[]);
        final router = _router(dateScreen: SlotDateScreen(args: _args()));

        await tester.pumpRoutedApp(
          router,
          overrides: <Object>[slotRepositoryProvider.overrideWith((_) => fake)],
        );
        await tester.pumpAndSettle();

        expect(fake.workingDaysCallCount, greaterThanOrEqualTo(1));
        expect(
          fake.lastWorkingDaysServiceId,
          isNotNull,
          reason:
              'the calendar must NOT fall back to schedule-shape mode — a null '
              'serviceId here is the pre-fix (Phase 14.20) bug',
        );
        expect(fake.lastWorkingDaysServiceId, _kService.id);
        expect(fake.lastWorkingDaysMasterId, _kMaster.id);
      },
    );

    // Phase 14.20 — the serviceId must survive a MONTH STEP. `_workingDaysQuery`
    // rebuilds per visible month; a regression that recomputed it without
    // `services.first.id` on the month-nav path would silently revert the
    // stepped-to month to schedule-shape mode (duration-blind) while the first
    // month stayed availability-aware — an inconsistency this pins directly at
    // the query boundary.
    testWidgets(
      'stepping to the next month re-issues the working-days query with the '
      'primary service id still attached (never drops to schedule-shape)',
      (tester) async {
        final fake = _FakeSlotRepository(const <BookingSlot>[]);
        final router = _router(dateScreen: SlotDateScreen(args: _args()));

        await tester.pumpRoutedApp(
          router,
          overrides: <Object>[slotRepositoryProvider.overrideWith((_) => fake)],
        );
        await tester.pumpAndSettle();

        expect(fake.workingDaysCallCount, 1);
        expect(fake.lastWorkingDaysServiceId, _kService.id);
        final DateTime firstMonthFrom = fake.lastWorkingDaysFrom!;

        await tester.tap(find.byKey(const Key('booking-calendar-next-month')));
        await tester.pumpAndSettle();

        expect(
          fake.workingDaysCallCount,
          2,
          reason: 'a month step must trigger a fresh working-days fetch',
        );
        expect(
          fake.lastWorkingDaysFrom!.isAfter(firstMonthFrom),
          isTrue,
          reason: 'the second fetch must be for the (later) stepped-to month',
        );
        expect(
          fake.lastWorkingDaysServiceId,
          _kService.id,
          reason:
              'the month-nav reload must keep threading services.first.id — '
              'dropping it here re-introduces the calendar-vs-slots '
              'disagreement for every month past the first',
        );
      },
    );

    // Phase 14.20 — proves the availability gate is NOT a today-only client
    // guard: a genuinely FUTURE day the service-scoped endpoint marks
    // working:false (fully booked / duration doesn't fit) is disabled just the
    // same, while a sibling future working:true day stays tappable.
    testWidgets(
      'a FUTURE day (not today) the service-scoped query marks working:false is '
      'disabled and untappable, while a sibling working:true future day is not',
      (tester) async {
        final DateTime now = DateTime.now();
        // The 15th of NEXT month is unconditionally in the future regardless
        // of when this test runs; the 16th is its always-working sibling.
        final DateTime nextMonth = DateTime(now.year, now.month + 1, 1);
        final DateTime disabledDay = DateTime(
          nextMonth.year,
          nextMonth.month,
          15,
        );
        final fake = _FakeSlotRepository(
          const <BookingSlot>[],
          // Availability-aware mode: only the 15th of next month is fully
          // booked for this service; every other day fits.
          workingDaysOverride: (DateTime day, String? serviceId) =>
              day != disabledDay,
        );
        final router = _router(dateScreen: SlotDateScreen(args: _args()));

        await tester.pumpRoutedApp(
          router,
          overrides: <Object>[slotRepositoryProvider.overrideWith((_) => fake)],
        );
        await tester.pumpAndSettle();

        // Step onto the future month (every day there is > today).
        await tester.tap(find.byKey(const Key('booking-calendar-next-month')));
        await tester.pumpAndSettle();

        final Finder disabledCell = find.byKey(
          const Key('booking-calendar-day-15'),
        );
        expect(disabledCell, findsOneWidget);
        expect(
          find.descendant(
            of: disabledCell,
            matching: find.byType(GestureDetector),
          ),
          findsNothing,
          reason:
              'a future working:false day must be inert — the gate is '
              'availability-driven, not a today-only cutoff',
        );

        await tester.tap(disabledCell, warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(fake.callCount, 0);

        // The sibling future day (working:true) keeps its tap handler — the
        // gate does not over-disable the whole future month.
        final Finder enabledCell = find.byKey(
          const Key('booking-calendar-day-16'),
        );
        expect(enabledCell, findsOneWidget);
        expect(
          find.descendant(
            of: enabledCell,
            matching: find.byType(GestureDetector),
          ),
          findsOneWidget,
          reason: 'a working:true future day must stay tappable',
        );
      },
    );

    // Regression guard (chrome-height clipping fix) — `MonthCalendar` sits
    // inside a `SingleChildScrollView`; on the default flutter_test surface
    // the surrounding chrome (top bar + master strip) can leave less
    // viewport than the 5-row grid needs, scrolling the last row or two out
    // of view. `tapCalendarDay` (test/helpers/pump_app.dart) fixes this with
    // `ensureVisible`, mirroring what a real user does by scrolling. This
    // test deliberately targets a day GUARANTEED to land in the grid's LAST
    // (5th) row — unlike "today" (whose row drifts with the calendar date
    // and would make a regression guard silently stop testing anything once
    // "today" happened to land in an earlier row) — so it keeps exercising
    // the scrolled-offscreen path no matter what date the suite runs on.
    testWidgets('a day in the calendar\'s guaranteed LAST row is reachable via '
        'ensureVisible and drives the same navigation as any other tappable '
        'day', (tester) async {
      // Day 29 always falls in the grid's 5th row (0-indexed row 4) for
      // any month with >=29 days: the grid is Monday-first, so the
      // leading-blank count before day 1 ranges 0..6, putting day 29's
      // flat cell index (leadingBlanks + 28) somewhere in 28..34 — and
      // every value in that range floor-divides by 7 to exactly 4. The
      // sole month without a day 29 is February in a non-leap year (28
      // days), so this walks forward from "today" to the first
      // >=29-day month, guaranteeing both a real day-29 cell AND that
      // it's strictly in the future (so the default "not in the past"
      // availability check never disqualifies it).
      final DateTime now = DateTime.now();
      DateTime target = DateTime(now.year, now.month + 1, 1);
      int monthsAhead = 1;
      while (DateTime(target.year, target.month + 1, 0).day < 29) {
        target = DateTime(target.year, target.month + 1, 1);
        monthsAhead++;
      }

      final fake = _FakeSlotRepository(const <BookingSlot>[]);
      final router = _router(dateScreen: SlotDateScreen(args: _args()));

      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[slotRepositoryProvider.overrideWith((_) => fake)],
      );
      await tester.pumpAndSettle();

      for (int i = 0; i < monthsAhead; i++) {
        await tester.tap(find.byKey(const Key('booking-calendar-next-month')));
        await tester.pumpAndSettle();
      }

      final Finder day29Cell = find.byKey(const Key('booking-calendar-day-29'));
      expect(day29Cell, findsOneWidget);

      await tester.tapCalendarDay(29);
      await tester.pumpAndSettle();

      expect(fake.callCount, 1);
      expect(fake.lastDate, DateTime(target.year, target.month, 29));

      await tester.tap(find.byKey(const Key('booking-summary-cta')));
      await tester.pumpAndSettle();
      expect(find.byType(SlotTimeScreen), findsOneWidget);
    });

    // Phase 14.14 QA gap-fix — the acceptance criterion "a day absent from
    // the resolved set defaults to non-working, never tappable" was
    // previously unverified: every existing fixture (including the test
    // above) always returns an explicit `working` entry for every requested
    // day, so `_availabilityFrom`'s `workingByDay[_dayKey(day)] ?? false`
    // fallback branch was never actually exercised.
    testWidgets(
      'a day silently absent from the working-days response defaults to '
      'non-working (conservative fallback), never tappable',
      (tester) async {
        final DateTime today = DateTime.now();
        final DateTime todayDateOnly = DateTime(
          today.year,
          today.month,
          today.day,
        );
        final fake = _FakeSlotRepository(const <BookingSlot>[])
          ..omitFromWorkingDaysResponse = <DateTime>{todayDateOnly};
        final router = _router(dateScreen: SlotDateScreen(args: _args()));

        await tester.pumpRoutedApp(
          router,
          overrides: <Object>[slotRepositoryProvider.overrideWith((_) => fake)],
        );
        await tester.pumpAndSettle();

        final Finder todayCell = find.byKey(
          Key('booking-calendar-day-${today.day}'),
        );
        expect(todayCell, findsOneWidget);
        expect(
          find.descendant(
            of: todayCell,
            matching: find.byType(GestureDetector),
          ),
          findsNothing,
          reason:
              'a day with no entry at all in the response must render as '
              'non-working, the same as an explicit working:false',
        );

        await tester.tap(todayCell, warnIfMissed: false);
        await tester.pumpAndSettle();

        expect(fake.callCount, 0);
      },
    );

    // Phase 14.14 — the working-days fetch itself can fail (distinct from a
    // day resolving working:false): the calendar must show the retry state,
    // never a stuck spinner or a falsely-tappable grid.
    testWidgets(
      'when the working-days fetch fails, the calendar shows a retry state '
      'instead of the grid, and retry re-fetches successfully',
      (tester) async {
        final fake = _FakeSlotRepository(
          const <BookingSlot>[],
          workingDaysErrorToThrow: const NetworkFailure(),
        );
        final router = _router(dateScreen: SlotDateScreen(args: _args()));

        await tester.pumpRoutedApp(
          router,
          overrides: <Object>[slotRepositoryProvider.overrideWith((_) => fake)],
          // Disable Riverpod's default retry-on-build-failure: otherwise an
          // automatic retry can fire mid-`pumpAndSettle` (still failing,
          // since `workingDaysErrorToThrow` isn't cleared yet) and inflate
          // the call count asserted below non-deterministically.
          retry: (int _, Object _) => null,
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('booking-calendar-retry')), findsOneWidget);
        expect(find.byKey(const Key('booking-month-calendar')), findsNothing);
        expect(fake.workingDaysCallCount, 1);

        // Retry succeeds this time → the grid replaces the retry state.
        fake.workingDaysErrorToThrow = null;
        await tester.tap(find.byKey(const Key('booking-calendar-retry')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('booking-calendar-retry')), findsNothing);
        expect(find.byKey(const Key('booking-month-calendar')), findsOneWidget);
        expect(fake.workingDaysCallCount, 2);
      },
    );

    // The working-days retry state is SCROLLABLE (so it cannot
    // RenderFlex-overflow and hide the retry button on a short viewport) AND
    // vertically CENTRED (so it does not look broken on a roomy one). Those
    // two requirements fight each other, and the naive way to satisfy the
    // first silently breaks the second: this body renders into an `Expanded`,
    // so a bare `SingleChildScrollView(child: Center(…))` hands its child
    // UNBOUNDED height, `Center` collapses to the child's own size, and the
    // content pins to the TOP. The fix is `LayoutBuilder` +
    // `ConstrainedBox(minHeight: constraints.maxHeight)`.
    //
    // Both halves are asserted, because each is invisible to the other's test.
    testWidgets(
      'the working-days retry state is vertically CENTRED in the calendar '
      'area when there is room — not pinned to the top',
      (tester) async {
        final fake = _FakeSlotRepository(
          const <BookingSlot>[],
          workingDaysErrorToThrow: const NetworkFailure(),
        );
        final router = _router(dateScreen: SlotDateScreen(args: _args()));

        await tester.pumpRoutedApp(
          router,
          overrides: <Object>[slotRepositoryProvider.overrideWith((_) => fake)],
          retry: (int _, Object _) => null,
        );
        await tester.pumpAndSettle();

        final Finder retry = find.byKey(const Key('booking-calendar-retry'));
        expect(retry, findsOneWidget);

        // The scroll viewport IS the calendar area (`_calendarBody`'s
        // `Expanded` slot), so its centre is what the content must line up on.
        final Rect viewport = tester.getRect(
          find
              .ancestor(of: retry, matching: find.byType(SingleChildScrollView))
              .first,
        );
        final Rect content = tester.getRect(
          find.ancestor(of: retry, matching: find.byType(Column)).first,
        );

        expect(
          viewport.height,
          greaterThan(content.height + 40),
          reason:
              'this assertion is only meaningful with slack to centre INTO — '
              'if the viewport ever shrinks to the content size, top-aligned '
              'and centred become indistinguishable and this test goes '
              'vacuously green',
        );
        expect(
          content.center.dy,
          closeTo(viewport.center.dy, 1.0),
          reason:
              'content top ${content.top} vs viewport top ${viewport.top}: a '
              'top-pinned body (the unbounded-height Center collapse) puts '
              'these two within a pixel of each other instead',
        );
      },
    );

    testWidgets(
      'the working-days retry state still scrolls — and does not overflow — '
      'when the calendar area is too short to fit it',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 460));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final fake = _FakeSlotRepository(
          const <BookingSlot>[],
          workingDaysErrorToThrow: const NetworkFailure(),
        );
        final router = _router(dateScreen: SlotDateScreen(args: _args()));

        await tester.pumpRoutedApp(
          router,
          overrides: <Object>[slotRepositoryProvider.overrideWith((_) => fake)],
          retry: (int _, Object _) => null,
        );
        await tester.pumpAndSettle();

        // `pumpAndSettle` would already have thrown on a RenderFlex overflow
        // (see `helpers/overflow_guard.dart`); reaching here is half the
        // assertion. The other half is that the retry button — the only way
        // out of this state — is actually reachable rather than clipped
        // outside the viewport.
        final Finder retry = find.byKey(const Key('booking-calendar-retry'));
        expect(retry, findsOneWidget);

        // Non-vacuity guard. At a surface where the content already fits, a
        // top-pinned body and a scrolling one behave identically and this test
        // would prove nothing — so assert the body genuinely has to scroll.
        // (`minHeight: constraints.maxHeight` never CREATES scroll extent; it
        // only stops the content collapsing above the fold.)
        final ScrollPosition position = tester
            .state<ScrollableState>(
              find.ancestor(of: retry, matching: find.byType(Scrollable)).first,
            )
            .position;
        expect(
          position.maxScrollExtent,
          greaterThan(0),
          reason:
              'the calendar slot must be SHORTER than the error body here, or '
              'this test is not exercising the overflow path at all',
        );

        await tester.ensureVisible(retry);
        await tester.tap(retry);
        await tester.pumpAndSettle();

        expect(fake.workingDaysCallCount, 2);
      },
    );

    // Phase 14.14 QA gap-fix — Decisions locked ("Loading/reload UX mirrors
    // MasterScheduleScreen's visual pattern: full-screen spinner on a
    // genuine first load ... cached-stale grid + thin top
    // LinearProgressIndicator on a month-step reload") and its matching
    // acceptance criterion were both previously unverified by any test —
    // only the settled end states (grid / retry state) were ever asserted,
    // never the in-flight loading UX itself.
    testWidgets(
      'the genuine first working-days load shows a full-screen spinner, '
      'not the grid, until the fetch resolves',
      (tester) async {
        final gate = Completer<void>();
        final fake = _FakeSlotRepository(const <BookingSlot>[])
          ..workingDaysGate = gate;
        final router = _router(dateScreen: SlotDateScreen(args: _args()));

        await tester.pumpRoutedApp(
          router,
          overrides: <Object>[slotRepositoryProvider.overrideWith((_) => fake)],
        );
        // Single pump: the fetch is gated in-flight, nothing settled yet.
        await tester.pump();

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.byKey(const Key('booking-month-calendar')), findsNothing);
        expect(
          find.byType(LinearProgressIndicator),
          findsNothing,
          reason:
              'a genuine first load is a full-screen spinner, never the '
              'thin reload progress line (that is reload-only)',
        );

        gate.complete();
        await tester.pumpAndSettle();

        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byKey(const Key('booking-month-calendar')), findsOneWidget);
      },
    );

    testWidgets(
      'a month-navigation reload keeps the stale grid visible with a thin '
      'top progress line, instead of a jarring full-screen spinner',
      (tester) async {
        final fake = _FakeSlotRepository(const <BookingSlot>[]);
        final router = _router(dateScreen: SlotDateScreen(args: _args()));

        await tester.pumpRoutedApp(
          router,
          overrides: <Object>[slotRepositoryProvider.overrideWith((_) => fake)],
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('booking-month-calendar')), findsOneWidget);
        expect(fake.workingDaysCallCount, 1);

        // Gate the NEXT fetch (the month-nav reload) and step forward.
        final gate = Completer<void>();
        fake.workingDaysGate = gate;
        await tester.tap(find.byKey(const Key('booking-calendar-next-month')));
        await tester.pump();

        expect(
          find.byKey(const Key('booking-month-calendar')),
          findsOneWidget,
          reason:
              'the (stale, previous-month) grid must stay mounted during a '
              'month-nav reload, not be replaced by a spinner',
        );
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(
          find.byType(LinearProgressIndicator),
          findsOneWidget,
          reason: 'a mid-flight reload shows the thin top progress line',
        );
        expect(fake.workingDaysCallCount, 2);

        gate.complete();
        await tester.pumpAndSettle();

        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(find.byKey(const Key('booking-month-calendar')), findsOneWidget);
      },
    );

    // mobile-qa Part 1 — the unified MasterStrip (`showRole: true,
    // showRating: true`) is now live on this screen, but no test asserted the
    // actual role/rating CONTENT ever rendered — only its presence via the
    // master's name (see `SlotTimeScreen`'s sibling test below). Locks in the
    // role label (via the shared `masterRoleLabel` helper, never a hardcoded
    // string — mobile-qa M2) and the "★4.8 (12)" rating readout, both scoped
    // to the MasterStrip descendant so a coincidental match elsewhere on
    // screen can't false-pass this.
    testWidgets(
      'shows the master\'s role label and ★rating(reviewCount) inside '
      'MasterStrip',
      (tester) async {
        final fake = _FakeSlotRepository(const <BookingSlot>[]);
        final router = _router(dateScreen: SlotDateScreen(args: _args()));

        await tester.pumpRoutedApp(
          router,
          overrides: <Object>[slotRepositoryProvider.overrideWith((_) => fake)],
        );
        await tester.pumpAndSettle();

        final Finder masterStrip = find.byType(MasterStrip);
        expect(masterStrip, findsOneWidget);

        final l10n = AppLocalizations.of(tester.element(masterStrip));
        final String roleLabel = masterRoleLabel(_kMaster.type, l10n);
        expect(
          find.descendant(of: masterStrip, matching: find.text(roleLabel)),
          findsOneWidget,
          reason:
              'showRole:true must render masterRoleLabel(type, l10n) — for '
              'this fixture (independentMaster) that is '
              'l10n.masterRoleIndependent',
        );

        final String ratingLabel = _kMaster.avgRating.toStringAsFixed(1);
        expect(
          find.descendant(of: masterStrip, matching: find.text(ratingLabel)),
          findsOneWidget,
          reason: 'showRating:true must render avgRating.toStringAsFixed(1)',
        );

        expect(
          find.descendant(
            of: masterStrip,
            matching: find.text('(${_kMaster.reviewCount})'),
          ),
          findsOneWidget,
          reason:
              'reviewCount (12) is > 0 for this fixture, so the parenthetical '
              'review-count suffix must render alongside the rating',
        );
      },
    );

    testWidgets('«Далі» does not advance before a day is selected, and '
        'advances to the time screen once one is', (tester) async {
      final fake = _FakeSlotRepository(const <BookingSlot>[]);
      final router = _router(dateScreen: SlotDateScreen(args: _args()));

      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[slotRepositoryProvider.overrideWith((_) => fake)],
      );
      await tester.pumpAndSettle();

      final Finder cta = find.byKey(const Key('booking-summary-cta'));
      expect(cta, findsOneWidget);

      // No day selected yet: tapping "Далі" must not navigate.
      await tester.tap(cta);
      await tester.pumpAndSettle();
      expect(find.byType(SlotTimeScreen), findsNothing);

      // Select today, then advance.
      final DateTime today = DateTime.now();
      await tester.tapCalendarDay(today.day);
      await tester.pumpAndSettle();
      await tester.tap(cta);
      await tester.pumpAndSettle();

      expect(find.byType(SlotTimeScreen), findsOneWidget);
    });
  });

  // ── mobile-qa (2026-08-02, backlog :226) — Kyiv-anchored `_today` ──────────
  //
  // `SlotDateScreen.initState` derives `_today` via `kyivToday(ref.read
  // (clockProvider))` (`slot_picker_screen.dart:102`), which gates both the
  // "past day, untappable" rule (`day.isBefore(_today)`) and the calendar's
  // "today" ring. Every OTHER test in this file reads the REAL device clock
  // (`DateTime.now()`) with no `clockProvider` override, so none of them can
  // disagree with a reverted `dateOnly(DateTime.now())` — this is the one
  // fixture that pins the Kyiv-vs-UTC derivation itself, mirroring
  // `booked_days_notifier_test.dart`'s identical pattern for the "reaches the
  // wire" notifier.
  group('SlotDateScreen — Kyiv-anchored "today" (mobile-qa, 2026-08-02, '
      'backlog :226)', () {
    testWidgets(
      'the day before Kyiv "today" renders PAST (untappable, no fetch) even '
      'though it is still the SAME calendar day in UTC — a UTC/device-day '
      '_today would wrongly leave it selectable',
      (tester) async {
        // 2026-08-01T22:30Z: UTC calendar day = Aug 1; Kyiv calendar day
        // (EEST, +3) = Aug 2 (01:30 local, already rolled over) — the same
        // fixture `kyiv_day_test.dart` uses for `kyivDayOf` itself.
        // future-date-ok: this IS the fake clockProvider "now" — a fixed instant straddling the Kyiv/UTC day boundary is the whole point; a now-relative offset cannot express "an instant that crosses the Kyiv day boundary".
        final DateTime clockInstant = DateTime.utc(2026, 8, 1, 22, 30);
        final fake = _FakeSlotRepository(const <BookingSlot>[]);
        final router = _router(dateScreen: SlotDateScreen(args: _args()));

        await tester.pumpRoutedApp(
          router,
          overrides: <Object>[
            slotRepositoryProvider.overrideWith((_) => fake),
            clockProvider.overrideWithValue(() => clockInstant),
          ],
        );
        await tester.pumpAndSettle();

        // Aug 1 is YESTERDAY once "today" correctly resolves to Aug 2 in
        // Kyiv — no GestureDetector (the same "disabled cell" shape the
        // working-days gate above uses), and tapping it triggers no fetch.
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
        expect(fake.callCount, 0);

        // Aug 2 — the correct Kyiv "today" — is tappable and loads slots.
        final Finder aug2Cell = find.byKey(const Key('booking-calendar-day-2'));
        expect(aug2Cell, findsOneWidget);
        await tester.tapCalendarDay(2);
        await tester.pumpAndSettle();
        expect(fake.callCount, 1);
        expect(fake.lastDate, DateTime(2026, 8, 2));
      },
    );
  });

  group('SlotTimeScreen', () {
    // `.utc` (mobile-qa 2026-08-03): these are genuine instants — a slot's
    // start/end — read only via `.hour` (bucketing) and `formatSlotTime`
    // (display), never compared against a Kyiv-derived date token, so `.utc`
    // is the correct anchor, not merely a gate-suppression. Previously bare
    // `DateTime(...)` — harmless while this file had no `clockProvider`
    // reference (Rule 1's zone-critical Stage-1 filter never looked at it),
    // but the "SlotDateScreen — Kyiv-anchored ..." group above now imports
    // `clockProvider`, so the WHOLE file is zone-critical and Rule 1 rightly
    // flags any bare arity>=4 `DateTime(` in it, this pair included.
    final BookingSlot available = BookingSlot(
      // future-date-ok: fixed instant read only via `.hour`/formatSlotTime (bucketing/display), never compared against isPast — see the group comment above.
      startAt: DateTime.utc(2026, 7, 20, 10),
      // future-date-ok: same as startAt above — bucketing/display only.
      endAt: DateTime.utc(2026, 7, 20, 11),
      available: true,
    );
    final BookingSlot unavailable = BookingSlot(
      // future-date-ok: fixed instant read only via `.hour`/formatSlotTime (bucketing/display), never compared against isPast — see the group comment above.
      startAt: DateTime.utc(2026, 7, 20, 12),
      // future-date-ok: same as startAt above — bucketing/display only.
      endAt: DateTime.utc(2026, 7, 20, 13),
      available: false,
    );

    /// Pumps the date screen (so its notifier stays mounted underneath), then
    /// pushes straight to the time screen with a FIXED [SlotPickerState] —
    /// avoids re-deriving the fixture through a real `loadSlots` round-trip.
    Future<GoRouter> pumpTimeScreen(
      WidgetTester tester, {
      required BookingSlotPickerArgs args,
    }) async {
      final fake = _FakeSlotRepository(<BookingSlot>[available, unavailable]);
      final router = _router(dateScreen: SlotDateScreen(args: args));

      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[slotRepositoryProvider.overrideWith((_) => fake)],
      );
      await tester.pumpAndSettle();

      // Tap "today" — always available regardless of which real-world date
      // the test runs on. The fake repository returns the SAME pre-seeded
      // fixture list ([available], [unavailable]) no matter which date is
      // requested, so the exact tapped day-of-month is irrelevant to the
      // fixture that ends up in `slotPickerProvider.slots`.
      final DateTime today = DateTime.now();
      await tester.tapCalendarDay(today.day);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('booking-summary-cta')));
      await tester.pumpAndSettle();

      return router;
    }

    // Regression test (feature addition, updated for the Phase 14.1
    // follow-up that deleted `_DayHeaderChip` — see `slot_picker_screen.dart`
    // `SlotTimeScreen.build`'s comment): `MasterStrip` now renders at the
    // top of `SlotTimeScreen` too, mirroring `SlotDateScreen`'s and
    // `master_schedule_page.dart`'s persistent-strip pattern — before this
    // change, the "who you're booking with" card was visible on the date
    // step but disappeared once the client advanced to the time step.
    // `SlotTimeScreen` used to ALSO render a `_DayHeaderChip` directly below
    // `MasterStrip`; that chip was later deleted outright because its
    // master-identity subtitle duplicated `MasterStrip`'s own content, so
    // this test now locks in BOTH halves of the current contract: MasterStrip
    // present and topmost, day-header text gone for good (not just
    // accidentally missing).
    testWidgets(
      'shows MasterStrip as the sole top-of-screen card on SlotTimeScreen — '
      'the day header chip was intentionally removed, not merely absent',
      (tester) async {
        await pumpTimeScreen(tester, args: _args());

        final Finder timeScreen = find.byType(SlotTimeScreen);
        expect(timeScreen, findsOneWidget);

        final Finder masterStrip = find.descendant(
          of: timeScreen,
          matching: find.byType(MasterStrip),
        );
        expect(
          masterStrip,
          findsOneWidget,
          reason:
              'MasterStrip was NOT rendered on SlotTimeScreen before this '
              'change — it must appear exactly once now',
        );

        // The master's name must render INSIDE MasterStrip itself, not just
        // somewhere on screen.
        final String masterName = '${_kMaster.firstName} ${_kMaster.lastName}'
            .trim();
        expect(
          find.descendant(of: masterStrip, matching: find.text(masterName)),
          findsOneWidget,
        );

        // `_DayHeaderChip` is gone: its day-label text must be ABSENT, not
        // just unlocated. Using the real formatter (not a hardcoded string)
        // keeps this assertion locale-agnostic per mobile-qa M2.
        final DateTime today = DateTime.now();
        final DateTime todayDateOnly = DateTime(
          today.year,
          today.month,
          today.day,
        );
        expect(
          find.descendant(
            of: timeScreen,
            matching: find.text(formatBookingDayHeader(todayDateOnly)),
          ),
          findsNothing,
          reason:
              '_DayHeaderChip was intentionally deleted — its day-label '
              'text reappearing would mean it (or a duplicate) crept back',
        );

        // MasterStrip is the topmost card in the scrollable body: it must
        // render above the free-time section heading that now follows it
        // directly (no second card in between since the chip's removal).
        final l10n = AppLocalizations.of(tester.element(timeScreen));
        final Finder freeTimeHeading = find.descendant(
          of: timeScreen,
          matching: find.text(l10n.bookingFreeTimeHeading),
        );
        expect(freeTimeHeading, findsOneWidget);
        expect(
          tester.getTopLeft(masterStrip).dy,
          lessThan(tester.getTopLeft(freeTimeHeading).dy),
          reason:
              'MasterStrip must be the first thing rendered in the body, '
              'above the "Вільний час" heading',
        );
      },
    );

    // mobile-qa Part 1 — mirrors the SlotDateScreen test above: the same
    // MasterStrip flags (`showRole: true, showRating: true`) are also live on
    // this screen, so its rendered role/rating content needs its own
    // assertion rather than assuming it matches SlotDateScreen's coverage.
    testWidgets(
      'shows the master\'s role label and ★rating(reviewCount) inside '
      'MasterStrip on SlotTimeScreen',
      (tester) async {
        await pumpTimeScreen(tester, args: _args());

        final Finder timeScreen = find.byType(SlotTimeScreen);
        final Finder masterStrip = find.descendant(
          of: timeScreen,
          matching: find.byType(MasterStrip),
        );
        expect(masterStrip, findsOneWidget);

        final l10n = AppLocalizations.of(tester.element(timeScreen));
        final String roleLabel = masterRoleLabel(_kMaster.type, l10n);
        expect(
          find.descendant(of: masterStrip, matching: find.text(roleLabel)),
          findsOneWidget,
        );

        final String ratingLabel = _kMaster.avgRating.toStringAsFixed(1);
        expect(
          find.descendant(of: masterStrip, matching: find.text(ratingLabel)),
          findsOneWidget,
        );

        expect(
          find.descendant(
            of: masterStrip,
            matching: find.text('(${_kMaster.reviewCount})'),
          ),
          findsOneWidget,
        );
      },
    );

    // Jump-fix regression test (debugger-recommended): `SlotDateScreen` and
    // `SlotTimeScreen` are nested `go_router` routes co-mounted on the SAME
    // Navigator during a real `CupertinoPageTransitionsBuilder` push (see
    // `slot_picker_screen.dart`'s file header + the `Hero` comments on both
    // `MasterStrip` usages). A prior 8dp top-padding mismatch between the two
    // screens' `MasterStrip` wrappers made the shared-`Hero` card visibly
    // "jump" the instant the push transition settled, even though the `Hero`
    // itself was wired correctly. This pins the padding half of that fix:
    // `MasterStrip` must land at the IDENTICAL vertical offset on both
    // screens, independent of navigation, so nothing hops when the `Hero`
    // flight ends.
    //
    // mobile-qa Part 2 re-verification (unified-card follow-up): both
    // `SlotDateScreen` and `SlotTimeScreen` now pass the SAME
    // `showRole: true, showRating: true` flags (they did not when this test
    // was first written), so `MasterStrip`'s intrinsic height grew on BOTH
    // sides by the same amount — the top-left `dy` this test reads is
    // unaffected by the card growing TALLER (that only pushes content below
    // it down, never the card's own top edge), so the offset-parity
    // assertion below is still measuring exactly what it always measured and
    // still holds. Confirmed by re-running this test after the flags were
    // enabled — not just assumed from the reasoning above.
    testWidgets(
      'MasterStrip renders at the identical vertical offset on SlotDateScreen '
      'and SlotTimeScreen, so the shared Hero never visibly jumps once the '
      'push transition settles',
      (tester) async {
        // SlotDateScreen — freshly pumped, no navigation involved yet.
        final fakeDate = _FakeSlotRepository(const <BookingSlot>[]);
        final dateRouter = _router(dateScreen: SlotDateScreen(args: _args()));
        await tester.pumpRoutedApp(
          dateRouter,
          overrides: <Object>[
            slotRepositoryProvider.overrideWith((_) => fakeDate),
          ],
        );
        await tester.pumpAndSettle();

        final Finder dateScreen = find.byType(SlotDateScreen);
        expect(dateScreen, findsOneWidget);
        final double dateScreenMasterStripTop = tester
            .getTopLeft(
              find.descendant(
                of: dateScreen,
                matching: find.byType(MasterStrip),
              ),
            )
            .dy;

        // SlotTimeScreen — reached via the SAME push navigation production
        // code takes, using the existing harness so the real transition
        // settles exactly as it does in the app.
        await pumpTimeScreen(tester, args: _args());

        final Finder timeScreen = find.byType(SlotTimeScreen);
        expect(timeScreen, findsOneWidget);
        final double timeScreenMasterStripTop = tester
            .getTopLeft(
              find.descendant(
                of: timeScreen,
                matching: find.byType(MasterStrip),
              ),
            )
            .dy;

        expect(
          timeScreenMasterStripTop,
          closeTo(dateScreenMasterStripTop, 0.5),
          reason:
              'SlotDateScreen and SlotTimeScreen must pad MasterStrip to the '
              'exact same vertical offset below the shared _BookingTopBar — '
              'a mismatch here IS the 8dp jump this test guards against '
              '(regression would be SlotTimeScreen using VelvetSpacing.sm '
              'instead of VelvetSpacing.md for its scroll-view top inset)',
        );
      },
    );

    // mobile-qa M3 / coverage gap closed 2026-07-02: neither this file nor
    // any prior QA pass exercised `SlotRepository.getMasterSlots` FAILING —
    // only empty/available/unavailable happy-path fixtures. `_SlotsSection`
    // renders the generic "no slots" copy for a genuine FETCH ERROR (no
    // scary error banner — see `slot_picker_screen.dart`'s
    // `_SlotsSection.build`), so this pins that a failure never crashes the
    // screen or leaves a stuck spinner, and that «Підтвердити» stays disabled
    // (no slot can ever be selected). Phase 14.15 note: a SUCCESSFUL fetch
    // that resolves to an empty list is a DIFFERENT, dedicated empty state
    // (`_NoSlotsEmptyState` — the fully-booked-day case) — see the separate
    // test below.
    testWidgets(
      'when the slots fetch fails, the day-unavailable message renders '
      'instead of crashing or leaving a spinner, and «Підтвердити» stays '
      'disabled',
      (tester) async {
        final fake = _FakeSlotRepository(
          const <BookingSlot>[],
          errorToThrow: const NetworkFailure(),
        );
        final router = _router(dateScreen: SlotDateScreen(args: _args()));

        await tester.pumpRoutedApp(
          router,
          overrides: <Object>[slotRepositoryProvider.overrideWith((_) => fake)],
        );
        await tester.pumpAndSettle();

        final DateTime today = DateTime.now();
        await tester.tapCalendarDay(today.day);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('booking-summary-cta')));
        await tester.pumpAndSettle();

        expect(find.byType(SlotTimeScreen), findsOneWidget);
        expect(fake.callCount, 1);

        final l10n = AppLocalizations.of(
          tester.element(find.byType(SlotTimeScreen)),
        );
        expect(find.text(l10n.bookingDayUnavailableState), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byType(SlotChip), findsNothing);

        // No slot can be selected from an empty/failed render — the CTA
        // must never fire a navigation.
        await tester.tap(find.byKey(const Key('booking-summary-cta')));
        await tester.pumpAndSettle();
        expect(find.textContaining('confirm-stub:'), findsNothing);
      },
    );

    // Phase 14.15 — a WORKING day (it passed the Phase 14.14 calendar gate)
    // that resolves to zero bookable slots is fully booked, not errored.
    // Distinct dedicated empty state from the fetch-error test above.
    testWidgets(
      'a working day with zero slots renders the fully-booked empty state, '
      'and its CTA returns to the date screen',
      (tester) async {
        final fake = _FakeSlotRepository(const <BookingSlot>[]);
        final router = _router(dateScreen: SlotDateScreen(args: _args()));

        await tester.pumpRoutedApp(
          router,
          overrides: <Object>[slotRepositoryProvider.overrideWith((_) => fake)],
        );
        await tester.pumpAndSettle();

        final DateTime today = DateTime.now();
        await tester.tapCalendarDay(today.day);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('booking-summary-cta')));
        await tester.pumpAndSettle();

        expect(find.byType(SlotTimeScreen), findsOneWidget);
        expect(fake.callCount, 1);

        expect(
          find.byKey(const Key('booking-no-slots-empty-state')),
          findsOneWidget,
        );
        final l10n = AppLocalizations.of(
          tester.element(find.byType(SlotTimeScreen)),
        );
        expect(find.text(l10n.bookingNoSlotsTitle), findsOneWidget);
        expect(find.text(l10n.bookingNoSlotsMessage), findsOneWidget);
        // The generic fetch-error copy must NOT also render here — the two
        // empty states are mutually exclusive.
        expect(find.text(l10n.bookingDayUnavailableState), findsNothing);
        expect(find.byType(SlotChip), findsNothing);

        // The empty state's own CTA pops back to the date screen (mirrors
        // `_DayHeaderChip`'s «Змінити» affordance). `ensureVisible` first —
        // the empty-state block can render below the fold inside the
        // scrollable body.
        final Finder changeDateCta = find.byKey(
          const Key('booking-no-slots-change-date'),
        );
        await tester.ensureVisible(changeDateCta);
        await tester.pumpAndSettle();
        await tester.tap(changeDateCta);
        await tester.pumpAndSettle();
        expect(find.byType(SlotTimeScreen), findsNothing);
        expect(find.byType(SlotDateScreen), findsOneWidget);
      },
    );

    testWidgets('unavailable slot chips are not tappable — selecting one '
        'does not enable «Підтвердити»', (tester) async {
      await pumpTimeScreen(tester, args: _args());

      expect(find.byType(SlotTimeScreen), findsOneWidget);

      final Finder unavailableChip = find.byWidgetPredicate(
        (Widget w) => w is SlotChip && !w.available,
      );
      expect(unavailableChip, findsOneWidget);

      await tester.tap(unavailableChip, warnIfMissed: false);
      await tester.pumpAndSettle();

      // Still on the time screen: the disabled CTA never fired a push.
      await tester.tap(find.byKey(const Key('booking-summary-cta')));
      await tester.pumpAndSettle();
      expect(find.textContaining('confirm-stub:'), findsNothing);
    });

    testWidgets('selecting an available slot enables «Підтвердити» and '
        'navigates to /booking/confirm with the correct extras', (
      tester,
    ) async {
      await pumpTimeScreen(
        tester,
        args: _args(rescheduleBookingId: 'booking-99'),
      );

      final Finder availableChip = find.byWidgetPredicate(
        (Widget w) => w is SlotChip && w.available,
      );
      expect(availableChip, findsOneWidget);

      await tester.tap(availableChip);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('booking-summary-cta')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('confirm-stub:${_kMaster.id}:${_kService.id}:'),
        findsOneWidget,
      );
      expect(find.textContaining(':booking-99'), findsOneWidget);
    });
  });
}
