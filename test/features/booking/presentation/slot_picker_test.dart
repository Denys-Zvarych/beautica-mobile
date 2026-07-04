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
  priceDisplay: '500 грн',
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
  /// every requested date resolves `working: true`.
  bool? Function(DateTime day)? workingDaysOverride;
  Object? workingDaysErrorToThrow;
  int workingDaysCallCount = 0;
  String? lastWorkingDaysMasterId;
  DateTime? lastWorkingDaysFrom;
  DateTime? lastWorkingDaysTo;

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
    required String serviceId,
    required DateTime date,
    CancelToken? cancelToken,
  }) async {
    callCount++;
    lastMasterId = masterId;
    lastServiceId = serviceId;
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
    CancelToken? cancelToken,
  }) async {
    workingDaysCallCount++;
    lastWorkingDaysMasterId = masterId;
    lastWorkingDaysFrom = from;
    lastWorkingDaysTo = to;
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
        WorkingDay(date: d, working: workingDaysOverride?.call(d) ?? true),
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
            'confirm-stub:${args.masterId}:${args.serviceId}:'
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

      await tester.tap(todayCell);
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
          workingDaysOverride: (DateTime day) => day != todayDateOnly,
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
      await tester.tap(find.byKey(Key('booking-calendar-day-${today.day}')));
      await tester.pumpAndSettle();
      await tester.tap(cta);
      await tester.pumpAndSettle();

      expect(find.byType(SlotTimeScreen), findsOneWidget);
    });
  });

  group('SlotTimeScreen', () {
    final BookingSlot available = BookingSlot(
      startAt: DateTime(2026, 7, 20, 10),
      endAt: DateTime(2026, 7, 20, 11),
      available: true,
    );
    final BookingSlot unavailable = BookingSlot(
      startAt: DateTime(2026, 7, 20, 12),
      endAt: DateTime(2026, 7, 20, 13),
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
      await tester.tap(find.byKey(Key('booking-calendar-day-${today.day}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('booking-summary-cta')));
      await tester.pumpAndSettle();

      return router;
    }

    // Regression test (feature addition): `MasterStrip` now renders at the
    // top of `SlotTimeScreen` too, mirroring `SlotDateScreen`'s and
    // `master_schedule_page.dart`'s persistent-strip pattern — before this
    // change, the "who you're booking with" card was visible on the date
    // step but disappeared once the client advanced to the time step.
    testWidgets(
      'shows MasterStrip above the day header chip, so the "who you\'re '
      'booking with" context persists onto the time step too',
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
        // somewhere on screen — `_DayHeaderChip` already renders a
        // DIFFERENT string ('$masterName · $masterRole') as its own
        // subtitle, so a bare `find.text(name)` anywhere on screen would be
        // a false positive even before this change.
        final String masterName = '${_kMaster.firstName} ${_kMaster.lastName}'
            .trim();
        expect(
          find.descendant(of: masterStrip, matching: find.text(masterName)),
          findsOneWidget,
        );

        // Ordering: MasterStrip must render ABOVE (higher on screen than)
        // the day header chip. The chip itself is a private
        // `_DayHeaderChip`, not importable from this test file, so it's
        // located via its own day-label text instead.
        final DateTime today = DateTime.now();
        final DateTime todayDateOnly = DateTime(
          today.year,
          today.month,
          today.day,
        );
        final Finder dayHeaderLabel = find.descendant(
          of: timeScreen,
          matching: find.text(formatBookingDayHeader(todayDateOnly)),
        );
        expect(dayHeaderLabel, findsOneWidget);

        final double masterStripTop = tester.getTopLeft(masterStrip).dy;
        final double dayHeaderTop = tester.getTopLeft(dayHeaderLabel).dy;
        expect(
          masterStripTop,
          lessThan(dayHeaderTop),
          reason:
              'MasterStrip must render above the day header chip, matching '
              'SlotDateScreen\'s own MasterStrip-first layout',
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
        await tester.tap(find.byKey(Key('booking-calendar-day-${today.day}')));
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
        await tester.tap(find.byKey(Key('booking-calendar-day-${today.day}')));
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
