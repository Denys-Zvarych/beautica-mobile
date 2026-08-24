// Phase 14.16/14.17 — Widget tests for SalonTimeScreen (salon booking flow
// step 3, "Час").
//
// Covers the phase docs' acceptance criteria:
//   1. Slider shows exactly the masters assigned in step 2 (one slide each).
//   2. Dot-tap changes the active slide.
//   3. Selecting a date + a time slot for the (only) assigned master enables
//      the confirm bar and updates its scheduled-count.
//   4. "Підтвердити" (Phase 14.18) navigates to /booking/salon/confirm with a
//      fully-resolved `SalonBookingConfirmArgs` (correct salonId + one
//      appointment per scheduled master, each carrying a stable idempotency
//      key) — and NEVER calls any booking-creation repository method (the
//      N-booking submit happens on the confirm screen, off this screen).
//   5. The time phase's left-edge swipe-back affordance (key
//      `salon-schedule-time-edge-back-swipe`) is present in the time phase —
//      it replaced the inline «Змінити» change-date button (Phase 14.18's
//      `_ChangeDateButton`, itself a replacement for the removed
//      `_DayHeaderChip`/`_WindowLine`), which is now redundant with it plus
//      the top-bar back arrow / system back gesture.
//
// Strategy: mounts the REAL production screen via a test-local GoRouter
// mirroring app_router.dart's shape, overriding [slotRepositoryProvider]
// with a hand-written fake so no real Dio request is ever made — mirrors
// `slot_picker_test.dart`'s established pattern for this feature.

import 'dart:async';

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/booking/application/salon_booking_schedule_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/slot_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking_slot.dart';
import 'package:beautica_mobile/features/booking/application/salon_master_coverage_notifier.dart';
import 'package:beautica_mobile/features/booking/domain/salon_booking_args.dart';
import 'package:beautica_mobile/features/booking/domain/salon_booking_confirm_args.dart';
import 'package:beautica_mobile/features/booking/domain/working_day.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_time_screen.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/salon/application/public_salon_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_service_catalog_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_master_summary.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/pump_app.dart';

/// Tall test surface so the slot chip grid (below the calendar/day-header,
/// only reachable after the date phase swaps to the time phase) is fully
/// on-screen without scrolling — mirrors
/// `salon_master_selection_screen_test.dart`'s identical `_pumpTall` helper.
Future<void> _pumpTall(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Taps the pinned step-3 CTA (`schedule-confirm-cta`) and settles — the
/// user-facing behaviour change this file's tests were rewritten for:
/// forward navigation (date pick → TIME phase; slot pick → next unscheduled
/// master or confirm) is CTA-driven now, never automatic off a date/slot
/// tap. Acts on whichever slide is CURRENTLY ACTIVE in the pager — there is
/// only one shared bottom bar, so a caller must ensure the intended master's
/// slide is the active one first (`tapCalendarDay(..., within: slideOf(id))`
/// already requires that master to be on-screen/tappable, which in every
/// test below only holds for the active ± 1 slide anyway). Mirrors
/// `SalonTimeScreen._handleNext`/`ScheduleConfirmBar.onNext`'s real trigger.
Future<void> _tapNextCta(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('schedule-confirm-cta')));
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const String _kSalonId = 'salon-1';
const _stubSalon = Salon(id: _kSalonId, name: 'Салон «Вельвет»');

const _m1 = SalonMasterSummary(
  masterId: 'm1',
  firstName: 'Олена',
  lastName: 'Ковальчук',
  avgRating: 4.9,
  reviewCount: 12,
  type: MasterType.independentMaster,
);
const _m2 = SalonMasterSummary(
  masterId: 'm2',
  firstName: 'Софія',
  lastName: 'Мельник',
  avgRating: 5.0,
  reviewCount: 3,
  type: MasterType.salonMaster,
);

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
  name: 'Стрижка',
  durationLabel: '1 год',
  priceDisplay: '450 ₴',
  durationMinutes: 60,
  priceType: ServicePriceType.fixed,
  priceMin: 450,
);

const _stubCatalog = <SalonServiceCategoryEntry>[
  SalonServiceCategoryEntry(
    category: 'MANICURE',
    displayName: 'Манікюр',
    count: 1,
    services: <SalonCatalogService>[_svc1],
  ),
  SalonServiceCategoryEntry(
    category: 'HAIRCUT',
    displayName: 'Стрижка',
    count: 1,
    services: <SalonCatalogService>[_svc2],
  ),
];

/// A hand-written fake, mirroring `slot_picker_test.dart`'s `_FakeSlotRepository`:
/// every requested day is "working" by default and [slotsToReturn] is handed
/// back for every `getMasterSlots` call, so no real Dio request is ever made.
class _FakeSlotRepository implements SlotRepository {
  _FakeSlotRepository(
    this.slotsToReturn, {
    this.unavailableWhenServiceAware = const <DateTime>{},
  });

  final List<BookingSlot> slotsToReturn;

  /// Date-only keys that resolve to `working: false`, but ONLY when the
  /// caller's [getWorkingDays] request carries a non-empty `serviceIds` (the
  /// availability-aware mode). When `serviceIds` is null/empty (the older
  /// schedule-shape mode) every day still resolves `working: true` — i.e.
  /// this simulates a master who nominally WORKS the day but has no single
  /// free block long enough for the requested service(s), the exact
  /// disagreement `master_schedule_page.dart`'s `_workingDaysQuery` used to
  /// paper over before it started threading `serviceIds` (see the
  /// regression test below). Defaults to empty so every existing caller of
  /// this fake keeps returning `working: true` for every day, unchanged.
  final Set<DateTime> unavailableWhenServiceAware;

  int getMasterSlotsCallCount = 0;

  /// The FIRST `serviceId` the MOST RECENT `getMasterSlots` call carried.
  /// Kept for the single-service tests in this file, which only ever pass a
  /// one-element list, so `.first` reads the whole thing. For a multi-
  /// service assertion use [lastServiceIds] instead — see its own doc
  /// comment for why this field alone would silently miss a Phase 270 D3
  /// regression.
  String? lastServiceId;

  /// The FULL ordered `serviceIds` list the MOST RECENT `getMasterSlots`
  /// call carried (Phase 270 D3: every assigned service's own assignment
  /// id, not just the first). [lastServiceId] alone cannot tell "queried
  /// the whole list" from "queried only the first element" — both leave
  /// `.first` identical — so a test pinning the multi-service case must
  /// assert against this field's LENGTH/contents, not [lastServiceId].
  List<String>? lastServiceIds;

  /// Whether [getWorkingDays] was ever called, and the FULL ordered
  /// `serviceIds` list its most recent call carried. Until the dead-end fix
  /// (`master_schedule_page.dart:155-159`), the salon step-3 per-master
  /// calendar queried `getWorkingDays` in the duration-blind SCHEDULE-SHAPE
  /// mode (`serviceIds` omitted) while its own slot grid queried the
  /// availability-aware mode — the two could disagree, and a user could tap
  /// a calendar day that then offered zero bookable slots. The fix threads
  /// `widget.schedule.orderedMasterServiceIds` into the same query, so this
  /// must now carry the full ordered list, mirroring HEAD's
  /// `lastWorkingDaysServiceIds` (MO-4) — the singular `.first`-only field
  /// this replaces could not tell "queried the whole list" from "queried
  /// only the first element".
  bool getWorkingDaysCalled = false;
  List<String>? lastWorkingDaysServiceIds;

  @override
  Future<List<BookingSlot>> getMasterSlots({
    required String masterId,
    required List<String> serviceIds,
    required DateTime date,
    CancelToken? cancelToken,
  }) async {
    getMasterSlotsCallCount++;
    lastServiceId = serviceIds.isEmpty ? null : serviceIds.first;
    lastServiceIds = serviceIds;
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
    getWorkingDaysCalled = true;
    lastWorkingDaysServiceIds = serviceIds;
    final bool serviceAware = serviceIds != null && serviceIds.isNotEmpty;
    final List<WorkingDay> days = <WorkingDay>[];
    for (
      DateTime d = from;
      !d.isAfter(to);
      d = d.add(const Duration(days: 1))
    ) {
      final DateTime dateOnly = DateTime(d.year, d.month, d.day);
      final bool working =
          !(serviceAware && unavailableWhenServiceAware.contains(dateOnly));
      days.add(WorkingDay(date: dateOnly, working: working));
    }
    return days;
  }
}

/// A second fake, keying its returned slots by masterId (unlike
/// `_FakeSlotRepository`'s single shared list) so two masters scheduled in
/// the same test never end up with colliding `salon-slot-chip-<iso>` keys —
/// needed by the rebuild-scoping regression test below, which keeps two
/// masters' slides mounted at once.
class _PerMasterFakeSlotRepository implements SlotRepository {
  _PerMasterFakeSlotRepository(this.slotsByMaster);

  final Map<String, List<BookingSlot>> slotsByMaster;

  @override
  Future<List<BookingSlot>> getMasterSlots({
    required String masterId,
    required List<String> serviceIds,
    required DateTime date,
    CancelToken? cancelToken,
  }) async => slotsByMaster[masterId] ?? const <BookingSlot>[];

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

/// mobile-qa gap-fix (Phase 14.16/14.17 audit): [getWorkingDays] throws on
/// its FIRST call then succeeds — mirrors
/// `salon_service_selection_screen_test.dart`'s established throw-once
/// error/retry pattern, letting a test drive `MasterSchedulePage`'s date-phase
/// `_WorkingDaysErrorBody` + its real `salon-schedule-calendar-retry` button
/// (previously untested — every other fake in this file always succeeds).
class _ThrowOnceWorkingDaysSlotRepository implements SlotRepository {
  int getWorkingDaysCalls = 0;

  @override
  Future<List<WorkingDay>> getWorkingDays({
    required String masterId,
    required DateTime from,
    required DateTime to,
    List<String>? serviceIds,
    CancelToken? cancelToken,
  }) async {
    getWorkingDaysCalls++;
    if (getWorkingDaysCalls == 1) throw Exception('boom');
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
  }) async => const <BookingSlot>[];
}

/// mobile-qa gap-fix (Phase 14.16/14.17 audit): [getMasterSlots] always
/// throws (working-days always succeeds) — drives the TIME phase's own
/// error message (`l10n.bookingDayUnavailableState`), the second of
/// `MasterSchedulePage`'s two independent error sources. Unlike the
/// working-days error body, the approved design gives this branch no retry
/// button (mirrors the identical, pre-existing pattern in the
/// independent-master flow's `SlotTimeScreen` — not a gap introduced here);
/// the test only asserts the message renders instead of a stuck spinner.
class _ThrowingMasterSlotsSlotRepository implements SlotRepository {
  @override
  Future<List<BookingSlot>> getMasterSlots({
    required String masterId,
    required List<String> serviceIds,
    required DateTime date,
    CancelToken? cancelToken,
  }) async => throw Exception('boom');

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

/// Test-local router mirroring `app_router.dart`'s salonBookingTime →
/// salonBookingConfirm shape (Phase 14.18 — the «Підтвердити» hand-off now
/// targets the real confirmation screen, no longer the retired coming-soon
/// placeholder), capturing the `SalonBookingConfirmArgs` that reaches the
/// confirm stub so the hand-off payload can be asserted precisely. The stub
/// renders plain text (not the real `SalonBookingConfirmScreen`) so no
/// booking-creation provider is ever touched by this screen's tests.
GoRouter _router({
  required SalonBookingTimeArgs args,
  ValueChanged<SalonBookingConfirmArgs>? onReachedConfirm,
}) => GoRouter(
  initialLocation: RouteNames.salonBookingTime,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.salonBookingTime,
      builder: (context, state) => SalonTimeScreen(args: args),
    ),
    GoRoute(
      path: RouteNames.salonBookingConfirm,
      builder: (context, state) {
        onReachedConfirm?.call(state.extra! as SalonBookingConfirmArgs);
        return const Scaffold(body: Text('confirm-reached'));
      },
    ),
  ],
);

/// A router with a placeholder initial route + this screen pushed onto it —
/// needed (unlike [_router], which starts ON this screen) so tapping the
/// screen's own back button actually POPS it (and therefore disposes it),
/// letting a test observe `ScreenProtectionManager.release()` firing. Mirrors
/// `salon_master_selection_screen_test.dart`'s identical push-then-pop
/// approach for the same ScreenProtectionManager lifecycle group.
GoRouter _pushableRouter({required SalonBookingTimeArgs args}) => GoRouter(
  initialLocation: '/start',
  routes: <RouteBase>[
    GoRoute(
      path: '/start',
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text('start'))),
    ),
    GoRoute(
      path: RouteNames.salonBookingTime,
      builder: (context, state) => SalonTimeScreen(args: args),
    ),
  ],
);

/// Counts acquire()/release() calls — mirrors
/// `salon_master_selection_screen_test.dart`'s identical
/// `_CountingScreenProtection` (the established pattern for pinning a PII
/// screen's FLAG_SECURE lifecycle).
class _CountingScreenProtection extends ScreenProtectionManager {
  int acquireCount = 0;
  int releaseCount = 0;

  @override
  void acquire() => acquireCount++;

  @override
  void release() => releaseCount++;
}

// Phase 14.16/14.17 bugfix — `salonMasterServiceCoverageProvider` now
// resolves `SalonMasterSchedule.orderedMasterServiceIds` (the master's
// OWN service-ASSIGNMENT ids, distinct from the salon-wide CATALOG id
// `SalonCatalogService.id`) via `_resolveSchedule`; every test below MUST
// override it or every schedule fails to resolve and the screen self-pops
// (`schedules.isEmpty` guard). Identity-mapped (assignment id == catalog id)
// so every pre-existing assertion below (which predates the id-space split
// and was written when the catalog id WAS what reached the slots query)
// keeps holding without redesign — the dedicated regression test further
// down deliberately breaks this identity to prove the fix.
const Map<String, Map<String, String>> _kIdentityCoverage =
    <String, Map<String, String>>{
      'm1': <String, String>{'svc-1': 'svc-1', 'svc-2': 'svc-2'},
      'm2': <String, String>{'svc-1': 'svc-1', 'svc-2': 'svc-2'},
    };

List<Object> _baseOverrides({
  List<SalonMasterSummary> masters = const <SalonMasterSummary>[_m1],
  SlotRepository? slotRepository,
  Map<String, Map<String, String>> coverage = _kIdentityCoverage,
  // Must match whichever `SalonBookingTimeArgs.selectedServiceIds` the test's
  // own `args` literal carries — `SalonTimeScreen` rebuilds
  // `SalonBookingMasterSelectionArgs(salonId, selectedServiceIds)` from
  // `widget.args.selectedServiceIds` to key the coverage family, so an
  // override keyed on a mismatched list would simply never be hit and the
  // coverage provider would fall through to the (unmocked) real repository.
  List<String> selectedServiceIds = const <String>['svc-1', 'svc-2'],
}) => <Object>[
  publicSalonProfileProvider(
    _kSalonId,
  ).overrideWith((ref) => (_stubSalon, masters)),
  salonServiceCatalogProvider(_kSalonId).overrideWith((ref) => _stubCatalog),
  salonMasterServiceCoverageProvider(
    SalonBookingMasterSelectionArgs(
      salonId: _kSalonId,
      selectedServiceIds: selectedServiceIds,
    ),
  ).overrideWith((ref) => coverage),
  if (slotRepository != null)
    slotRepositoryProvider.overrideWith((_) => slotRepository),
];

void main() {
  testWidgets('renders exactly one slide per assigned master', (tester) async {
    const args = SalonBookingTimeArgs(
      salonId: _kSalonId,
      selectedServiceIds: <String>['svc-1', 'svc-2'],
      assignedServiceIdsByMaster: <String, List<String>>{
        'm1': <String>['svc-1'],
        'm2': <String>['svc-2'],
      },
    );
    final fake = _FakeSlotRepository(const <BookingSlot>[]);
    await tester.pumpRoutedApp(
      _router(args: args),
      overrides: _baseOverrides(
        masters: const <SalonMasterSummary>[_m1, _m2],
        slotRepository: fake,
      ),
    );
    await tester.pumpAndSettle();

    // The first (unscheduled) master's slide is current; the pager reports
    // both masters.
    expect(find.byKey(const Key('salon-schedule-page-m1')), findsOneWidget);
    expect(find.byKey(const Key('salon-time-pager-dot-0')), findsOneWidget);
    expect(find.byKey(const Key('salon-time-pager-dot-1')), findsOneWidget);
  });

  // MO-4 reversed the Phase 14.20 boundary guard this test used to pin: the
  // salon step-3 per-master calendar (`MasterSchedulePage`) no longer stays
  // on the duration-blind schedule-shape working-days mode. It now threads
  // `widget.schedule.orderedMasterServiceIds` into `_workingDaysQuery`
  // (`master_schedule_page.dart:155-159`), the SAME ordered assignment ids
  // its own slot grid (`salonMasterDaySlotsProvider`) already used — because
  // staying on schedule-shape was a live dead-end bug, not a deliberate
  // boundary: the calendar's day-enabled gate could disagree with the time
  // grid's real availability, so a user could tap a day the master nominally
  // "works" that then resolved to zero bookable slots (verified against a
  // real backend window: 19 of 61 days disagreed between the two modes).
  // This test now pins the CORRECT behaviour — the fix — and the dedicated
  // regression test right below proves what breaks without it.
  testWidgets('the salon per-master schedule calendar requests working-days '
      'availability-aware, with ALL ordered assigned-service ids', (
    tester,
  ) async {
    const args = SalonBookingTimeArgs(
      salonId: _kSalonId,
      selectedServiceIds: <String>['svc-1'],
      assignedServiceIdsByMaster: <String, List<String>>{
        'm1': <String>['svc-1'],
      },
    );
    final fake = _FakeSlotRepository(const <BookingSlot>[]);
    await tester.pumpRoutedApp(
      _router(args: args),
      overrides: _baseOverrides(
        slotRepository: fake,
        selectedServiceIds: const <String>['svc-1'],
      ),
    );
    await tester.pumpAndSettle();

    expect(
      fake.getWorkingDaysCalled,
      isTrue,
      reason:
          'MasterSchedulePage resolves its calendar gate via getWorkingDays',
    );
    expect(
      fake.lastWorkingDaysServiceIds,
      <String>['svc-1'],
      reason:
          'the calendar gate must agree with the slot grid — both query '
          'the same ordered assigned-service ids — or the calendar can '
          'offer a day the slot grid then reports as having no slots',
    );
  });

  // Regression test for the live dead-end this fix closes: a day the master
  // WORKS at all (the old schedule-shape signal would say `working: true`)
  // but which has NO free block long enough for the requested service(s)
  // (the availability-aware signal says `working: false`) must render on
  // the calendar as NON-TAPPABLE — never as a selectable day that then
  // drops the user on the zero-slots empty state.
  //
  // Falsified per the task's mutation-check protocol: reverting
  // `master_schedule_page.dart:155-159` to omit `serviceIds` from
  // `_workingDaysQuery` (the pre-fix form) turns this RED — the fake then
  // sees `serviceIds == null`, stays in schedule-shape mode, reports the day
  // `working: true`, the calendar renders it tappable, and the tap lands the
  // user on `_NoSlotsEmptyState` exactly as it did for the real user who hit
  // this dead-end.
  testWidgets(
    'a day the master works but with no long-enough free block renders '
    'non-tappable — never lands on the no-slots empty state',
    (tester) async {
      await _pumpTall(tester);
      const args = SalonBookingTimeArgs(
        salonId: _kSalonId,
        selectedServiceIds: <String>['svc-1'],
        assignedServiceIdsByMaster: <String, List<String>>{
          'm1': <String>['svc-1'],
        },
      );
      final DateTime today = kyivToday(DateTime.now);
      final fake = _FakeSlotRepository(
        const <BookingSlot>[],
        unavailableWhenServiceAware: <DateTime>{today},
      );
      await tester.pumpRoutedApp(
        _router(args: args),
        overrides: _baseOverrides(
          slotRepository: fake,
          selectedServiceIds: const <String>['svc-1'],
        ),
      );
      await tester.pumpAndSettle();

      final Finder todayCell = find.byKey(
        Key('booking-calendar-day-${today.day}'),
      );
      expect(todayCell, findsOneWidget);

      // Non-tappable per `MonthCalendar`'s own contract (`month_calendar.dart`
      // `_classify`): an unavailable day renders with NO `GestureDetector`
      // descendant at all — this is the same handler-presence check
      // `PumpApp.tapCalendarDay` runs before every tap, surfaced directly
      // here per that helper's own doc comment, since proving the cell is
      // INERT is exactly this test's point.
      expect(
        find.descendant(of: todayCell, matching: find.byType(GestureDetector)),
        findsNothing,
        reason:
            'an availability-aware working day with no long-enough free '
            'block must render with no tap handler',
      );

      // The no-op tap (warnIfMissed: false — deliberately proving inertness,
      // per tapCalendarDay's own doc comment) must never advance the slide
      // to the time phase.
      await tester.tap(todayCell, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('salon-schedule-no-slots-empty-state')),
        findsNothing,
        reason:
            'the dead-end this regression test guards against: a day shown '
            'as available that then resolves to zero bookable slots',
      );
      expect(
        find.byKey(const Key('booking-month-calendar')),
        findsOneWidget,
        reason: 'still on the date phase — the tap must not have registered',
      );
      expect(
        fake.getMasterSlotsCallCount,
        0,
        reason: 'no slot fetch fires for a day the tap never selected',
      );
    },
  );

  testWidgets('tapping a pager dot changes the active slide', (tester) async {
    const args = SalonBookingTimeArgs(
      salonId: _kSalonId,
      selectedServiceIds: <String>['svc-1', 'svc-2'],
      assignedServiceIdsByMaster: <String, List<String>>{
        'm1': <String>['svc-1'],
        'm2': <String>['svc-2'],
      },
    );
    final fake = _FakeSlotRepository(const <BookingSlot>[]);
    await tester.pumpRoutedApp(
      _router(args: args),
      overrides: _baseOverrides(
        masters: const <SalonMasterSummary>[_m1, _m2],
        slotRepository: fake,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('salon-time-pager-dot-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('salon-schedule-page-m2')), findsOneWidget);
  });

  // Regression guard for the user-reported bug this file was rewritten for:
  // date/time picks used to auto-advance the slider on their own (a slot
  // pick jumped straight to the next unscheduled master); forward navigation
  // is CTA-driven now — see `master_schedule_page.dart`'s file header and
  // `_handleNext`. Proven falsifiable per the task's mutation-check
  // protocol: temporarily restoring `onCompleted: () =>
  // _handleCompleted(i, masterIds)` at `salon_time_screen.dart`'s
  // `MasterSchedulePage(...)` call site (with `_handleCompleted` itself
  // restored too) turns this RED — the tapped slot fires the old auto
  // advance and the "slide unchanged" assertion below fails.
  testWidgets('tapping a slot does NOT change the visible master slide — only '
      'pressing the CTA advances the pager to the next unscheduled master', (
    tester,
  ) async {
    await _pumpTall(tester);
    const args = SalonBookingTimeArgs(
      salonId: _kSalonId,
      selectedServiceIds: <String>['svc-1', 'svc-2'],
      assignedServiceIdsByMaster: <String, List<String>>{
        'm1': <String>['svc-1'],
        'm2': <String>['svc-2'],
      },
    );
    final DateTime today = kyivToday(DateTime.now);
    final DateTime slotStart = DateTime(today.year, today.month, today.day, 9);
    final fake = _FakeSlotRepository(<BookingSlot>[
      BookingSlot(
        startAt: slotStart,
        endAt: DateTime(today.year, today.month, today.day, 10, 30),
        available: true,
      ),
    ]);

    await tester.pumpRoutedApp(
      _router(args: args),
      overrides: _baseOverrides(
        masters: const <SalonMasterSummary>[_m1, _m2],
        slotRepository: fake,
      ),
    );
    await tester.pumpAndSettle();

    // m1 is the active slide from the fresh mount.
    expect(find.byKey(const Key('salon-schedule-page-m1')), findsOneWidget);

    await tester.tapCalendarDay(today.day);
    await tester.pumpAndSettle();
    // Date pick alone: still m1, still on the calendar.
    expect(find.byKey(const Key('salon-schedule-page-m1')), findsOneWidget);
    expect(find.byKey(const Key('booking-month-calendar')), findsOneWidget);

    await _tapNextCta(tester); // m1: DATE phase → TIME phase.
    expect(find.byKey(const Key('salon-schedule-page-m1')), findsOneWidget);

    final Finder slotChip = find.byKey(
      Key('salon-slot-chip-${slotStart.toIso8601String()}'),
    );
    expect(slotChip, findsOneWidget);
    await tester.tap(slotChip);
    await tester.pumpAndSettle();

    // THE ASSERTION UNDER TEST: picking the slot must NOT move the pager
    // off m1, even though m1 is now fully scheduled (isScheduled == true)
    // — the pre-fix behaviour auto-advanced to m2 right here.
    expect(
      find.byKey(const Key('salon-schedule-page-m1')),
      findsOneWidget,
      reason: 'a slot pick alone must never change the visible slide',
    );
    expect(
      find.byKey(const Key('salon-schedule-page-m2')),
      findsNothing,
      reason: 'the pager must still be showing m1, not m2',
    );

    // Only the CTA press moves the pager — to the next unscheduled master.
    await _tapNextCta(tester);

    expect(
      find.byKey(const Key('salon-schedule-page-m2')),
      findsOneWidget,
      reason: 'the CTA press is what advances the pager to m2',
    );
  });

  testWidgets(
    'picking a date then a time slot for the only assigned master enables '
    'the confirm bar; confirming navigates to /booking/salon/confirm with a '
    'fully-resolved SalonBookingConfirmArgs (correct salonId + one '
    'appointment carrying a stable idempotency key) and never touches a '
    'booking-creation repository',
    (tester) async {
      await _pumpTall(tester);
      const args = SalonBookingTimeArgs(
        salonId: _kSalonId,
        selectedServiceIds: <String>['svc-1'],
        assignedServiceIdsByMaster: <String, List<String>>{
          'm1': <String>['svc-1'],
        },
      );
      final DateTime today = kyivToday(DateTime.now);
      final DateTime slotStart = DateTime(
        today.year,
        today.month,
        today.day,
        9,
      );
      final fake = _FakeSlotRepository(<BookingSlot>[
        BookingSlot(
          startAt: slotStart,
          endAt: DateTime(today.year, today.month, today.day, 10, 30),
          available: true,
        ),
      ]);
      SalonBookingConfirmArgs? capturedArgs;

      await tester.pumpRoutedApp(
        _router(
          args: args,
          onReachedConfirm: (SalonBookingConfirmArgs a) => capturedArgs = a,
        ),
        overrides: _baseOverrides(
          slotRepository: fake,
          selectedServiceIds: const <String>['svc-1'],
        ),
      );
      await tester.pumpAndSettle();

      // Confirm bar starts disabled — nothing scheduled yet.
      NeumorphicButton cta = tester.widget<NeumorphicButton>(
        find.byKey(const Key('schedule-confirm-cta')),
      );
      expect(cta.onPressed, isNull);

      // Pick today's date.
      final Finder todayCell = find.byKey(
        Key('booking-calendar-day-${today.day}'),
      );
      expect(todayCell, findsOneWidget);
      await tester.tapCalendarDay(today.day);
      await tester.pumpAndSettle();

      // The date pick alone must NOT advance to the TIME phase any more —
      // no slot fetch fires, and the calendar is still on-screen.
      expect(fake.getMasterSlotsCallCount, 0);
      expect(find.byKey(const Key('booking-month-calendar')), findsOneWidget);

      // Instead, the CTA is now enabled and reads «Далі» — pressing it is
      // what commits the pick into the TIME phase.
      final l10n = AppLocalizations.of(
        tester.element(find.byType(SalonTimeScreen)),
      );
      cta = tester.widget<NeumorphicButton>(
        find.byKey(const Key('schedule-confirm-cta')),
      );
      expect(cta.onPressed, isNotNull);
      expect(cta.label, l10n.bookingNextCta);

      await _tapNextCta(tester);

      expect(fake.getMasterSlotsCallCount, greaterThan(0));

      // The date re-selection affordance now lives as this left-edge
      // swipe-back detector (replacing the removed `_ChangeDateButton`,
      // itself the removed `_DayHeaderChip`/`_WindowLine`'s successor) — it
      // must render in the time phase.
      expect(
        find.byKey(const Key('salon-schedule-time-edge-back-swipe')),
        findsOneWidget,
      );

      // Pick the fetched 09:00 slot.
      final Finder slotChip = find.byKey(
        Key('salon-slot-chip-${slotStart.toIso8601String()}'),
      );
      expect(slotChip, findsOneWidget);
      await tester.tap(slotChip);
      await tester.pumpAndSettle();

      // Every assigned master (just m1) is now scheduled — the tap alone
      // (no CTA press yet) already flips the CTA to «Підтвердити», enabled —
      // `ScheduleConfirmBar`'s own `_allScheduled` branch reacts to
      // `scheduledCount` directly, it doesn't wait for another CTA press.
      cta = tester.widget<NeumorphicButton>(
        find.byKey(const Key('schedule-confirm-cta')),
      );
      expect(cta.onPressed, isNotNull);
      expect(cta.label, l10n.bookingConfirmCta);

      await tester.tap(find.byKey(const Key('schedule-confirm-cta')));
      await tester.pumpAndSettle();

      // Landed on the confirm stub with a fully-resolved payload — never the
      // retired coming-soon placeholder.
      expect(find.text('confirm-reached'), findsOneWidget);
      expect(capturedArgs, isNotNull);
      expect(capturedArgs!.salonId, _kSalonId);
      expect(
        capturedArgs!.appointments,
        hasLength(1),
        reason: 'exactly one appointment for the single assigned master',
      );
      final SalonBookingAppointment appt = capturedArgs!.appointments.single;
      expect(appt.schedule.masterId, 'm1');
      expect(
        appt.startAt,
        slotStart,
        reason: "the appointment carries the chosen slot's start",
      );
      expect(
        appt.idempotencyKey,
        isNotEmpty,
        reason: 'each appointment gets a stable idempotency key at confirm',
      );
    },
  );

  // mobile-perf audit follow-up (Phase 14.16/14.17, Finding A — HIGH):
  // `_SalonTimeScreenState.build()` used to `ref.watch` the whole
  // `salonBookingScheduleProvider` map at the screen's top level, so ANY
  // master's date/slot pick anywhere in the flow re-ran the entire
  // `build()` — reconstructing `PageView.builder` with a brand-new
  // `SliverChildBuilderDelegate` (whose `shouldRebuild` always returns
  // `true`), forcing every currently-mounted slide (including
  // already-completed, kept-alive earlier masters) to rebuild too. Fixed
  // by moving the schedule-state reads into `Consumer`s scoped to
  // `_MasterPager`/`ScheduleConfirmBar` only.
  //
  // TECHNIQUE — mirrors `salon_master_selection_screen_test.dart`'s
  // identical Phase 14.13 rebuild-scoping regression test: Flutter's own
  // `debugPrintRebuildDirtyWidgets` framework flag prints
  // `'Rebuilding $this'` for every dirty Element rebuilt in a frame;
  // `Element.toStringShort()` renders as `'$runtimeType-$key'` for a keyed
  // widget, and every slide carries `ValueKey('salon-schedule-page-<id>')`
  // (see `SalonTimeScreen`'s `itemBuilder`), so the rebuild log names each
  // slide's Element unambiguously. One single-frame `tester.pump()` (never
  // `pumpAndSettle`, which would blur multiple frames together) is
  // captured right after the triggering tap.
  testWidgets(
    "picking master 2's slot does not rebuild master 1's already-completed "
    'slide — mobile-perf Finding A regression guard',
    (tester) async {
      await _pumpTall(tester);
      const args = SalonBookingTimeArgs(
        salonId: _kSalonId,
        selectedServiceIds: <String>['svc-1', 'svc-2'],
        assignedServiceIdsByMaster: <String, List<String>>{
          'm1': <String>['svc-1'],
          'm2': <String>['svc-2'],
        },
      );
      final DateTime today = kyivToday(DateTime.now);
      DateTime at(int hour) =>
          DateTime(today.year, today.month, today.day, hour);
      final fake = _PerMasterFakeSlotRepository(<String, List<BookingSlot>>{
        'm1': <BookingSlot>[
          BookingSlot(
            startAt: at(9),
            endAt: at(9).add(const Duration(minutes: 90)),
            available: true,
          ),
        ],
        'm2': <BookingSlot>[
          BookingSlot(
            startAt: at(11),
            endAt: at(11).add(const Duration(minutes: 60)),
            available: true,
          ),
        ],
      });

      // Scopes an interaction to one master's slide, so a duplicate
      // `booking-calendar-day-N` / `salon-slot-chip-<iso>` key mounted
      // simultaneously in a sibling (kept-alive) slide can never make the
      // Finder ambiguous. `skipOffstage: false` throughout: the sibling
      // slide this scopes AWAY from is deliberately kept mounted-but-
      // scrolled-off (Finding B's current ± 1 retention bound), and
      // Flutter's default `Finder` treats an off-screen, keep-alive-only
      // sliver child as "offstage" — the default `skipOffstage: true`
      // would make even a present widget invisible to `find.byKey`.
      Finder slideOf(String masterId) =>
          find.byKey(Key('salon-schedule-page-$masterId'), skipOffstage: false);
      Finder withinSlide(String masterId, Finder matching) => find.descendant(
        of: slideOf(masterId),
        matching: matching,
        skipOffstage: false,
      );

      await tester.pumpRoutedApp(
        _router(args: args),
        overrides: _baseOverrides(
          masters: const <SalonMasterSummary>[_m1, _m2],
          slotRepository: fake,
        ),
      );
      await tester.pumpAndSettle();

      // Complete m1 first (date → CTA into the TIME phase → its 09:00 slot
      // → CTA again to advance the pager) — forward navigation is CTA-driven
      // now (no more auto-advance off a date/slot tap alone), so each step
      // that used to happen automatically is now an explicit `_tapNextCta`
      // press, fully settled so the pager lands on m2 before the capture
      // below.
      await tester.tapCalendarDay(today.day, within: slideOf('m1'));
      await tester.pumpAndSettle();
      await _tapNextCta(tester); // m1: DATE phase → TIME phase.
      await tester.tap(
        withinSlide(
          'm1',
          find.byKey(Key('salon-slot-chip-${at(9).toIso8601String()}')),
        ),
      );
      await tester.pumpAndSettle();
      await _tapNextCta(tester); // m1 scheduled → pager advances to m2.

      // The pager advanced to m2; m1 is current ± 1 from m2, so
      // Finding B's retention bound keeps its slide mounted — required for
      // the "m1 never rebuilds" assertion below to be non-vacuous.
      // `skipOffstage: false` — see `withinSlide`'s doc comment above.
      expect(
        find.byKey(const Key('salon-schedule-page-m1'), skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('salon-schedule-page-m2'), skipOffstage: false),
        findsOneWidget,
      );

      // Pick m2's date, then CTA into its TIME phase so its slot chips are
      // on-screen — both happen BEFORE the rebuild capture below, since the
      // trigger this test isolates is specifically the SLOT pick, not the
      // date pick or the CTA press.
      await tester.tapCalendarDay(today.day, within: slideOf('m2'));
      await tester.pumpAndSettle();
      await _tapNextCta(tester); // m2: DATE phase → TIME phase.

      final List<String> rebuiltLines = <String>[];
      final DebugPrintCallback previousDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) rebuiltLines.add(message);
      };
      debugPrintRebuildDirtyWidgets = true;
      addTearDown(() {
        debugPrintRebuildDirtyWidgets = false;
        debugPrint = previousDebugPrint;
      });

      // The trigger: picking the LATER master's (m2) slot.
      await tester.tap(
        withinSlide(
          'm2',
          find.byKey(Key('salon-slot-chip-${at(11).toIso8601String()}')),
        ),
      );
      // Exactly ONE frame — the frame the tap's Riverpod state change
      // schedules.
      await tester.pump();

      debugPrintRebuildDirtyWidgets = false;
      debugPrint = previousDebugPrint;

      final bool m2SlideRebuilt = rebuiltLines.any(
        (String l) => l.contains('salon-schedule-page-m2'),
      );
      final bool m1SlideRebuilt = rebuiltLines.any(
        (String l) => l.contains('salon-schedule-page-m1'),
      );

      expect(
        m2SlideRebuilt,
        isTrue,
        reason:
            "the TAPPED slide (m2)'s own scoped `.select` watcher must "
            'rebuild it to show the newly-selected slot — if this is '
            'false the proxy technique itself is broken, not proving '
            'isolation',
      );
      expect(
        m1SlideRebuilt,
        isFalse,
        reason:
            "the EARLIER, already-completed master's slide (m1) must "
            'never rebuild from picking a LATER master\'s slot — a '
            'regression back to watching the raw '
            '`salonBookingScheduleProvider` at the top of '
            "`SalonTimeScreen.build()` (mobile-perf Finding A) would "
            'reconstruct the whole `PageView.builder` and rebuild every '
            'currently-mounted slide, failing this assertion',
      );

      await tester.pumpAndSettle();
    },
  );

  // mobile-qa gap-fix (Phase 14.16/14.17 audit): every prior scenario above
  // assigns exactly ONE service per master, so `_resolveSchedule`'s
  // multi-service resolution (roster/catalog id lookup for
  // `assignedServiceIdsByMaster`, verified safe by mobile-security but never
  // asserted CORRECT by any test) and the full-list slot-query convention
  // (`SalonMasterSchedule.orderedMasterServiceIds` — EVERY assigned
  // service's own assignment id, per Phase 270 D3) were both completely
  // unexercised. A regression that queried slots by only the first assigned
  // service, or that silently dropped a second assigned service from the
  // strip/window math, would have passed every existing test in this file.
  testWidgets(
    'a master with 2 assigned services resolves BOTH from the real catalog '
    '(strip + summed window), and the slot query keys on BOTH assigned '
    "services' own assignment ids, in order (Phase 270 D3)",
    (tester) async {
      await _pumpTall(tester);
      const args = SalonBookingTimeArgs(
        salonId: _kSalonId,
        selectedServiceIds: <String>['svc-1', 'svc-2'],
        assignedServiceIdsByMaster: <String, List<String>>{
          'm1': <String>['svc-1', 'svc-2'],
        },
      );
      final DateTime today = kyivToday(DateTime.now);
      final fake = _FakeSlotRepository(<BookingSlot>[
        BookingSlot(
          startAt: DateTime(today.year, today.month, today.day, 9),
          endAt: DateTime(today.year, today.month, today.day, 10, 30),
          available: true,
        ),
      ]);

      await tester.pumpRoutedApp(
        _router(args: args),
        overrides: _baseOverrides(slotRepository: fake),
      );
      await tester.pumpAndSettle();

      // CARD-UNIFICATION CHANGE (2026-07): the per-master identity card is now
      // the SHARED `MasterStrip` (name · title/role · ★ rating), which — unlike
      // the deleted `SalonMasterStrip` fork — does NOT list this master's
      // service names, so there is no per-master services label on this screen
      // any more. That both assigned ids still resolve into real
      // `SalonCatalogService` entries is proven instead by the summed total
      // below, which can only be right if BOTH were resolved.
      //
      // Summed duration across BOTH assigned services (90 + 60 = 150 min =
      // "2 год 30 хв"), not just svc-1's 90 minutes alone — proves
      // `summedDurationMinutes` folds the full assigned set. Rendered ONCE now
      // (the pinned `ScheduleConfirmBar`'s "Разом" total); the card's
      // duration pill went with the fork.
      expect(find.textContaining('2 год 30 хв'), findsOneWidget);

      // Pick today's date, then the CTA («Далі») to commit into the TIME
      // phase — the date pick alone no longer fires the slot query (forward
      // navigation is CTA-driven now).
      final Finder todayCell = find.byKey(
        Key('booking-calendar-day-${today.day}'),
      );
      expect(todayCell, findsOneWidget);
      await tester.tapCalendarDay(today.day);
      await tester.pumpAndSettle();
      await _tapNextCta(tester);

      expect(
        fake.getMasterSlotsCallCount,
        greaterThan(0),
        reason: 'entering the TIME phase must fetch this master\'s slots',
      );
      expect(
        fake.lastServiceIds,
        <String>['svc-1', 'svc-2'],
        reason:
            'SlotRepository.getMasterSlots must be keyed on EVERY assigned '
            "service's own assignment id, in order (Phase 270 D3) — never "
            'just the first. Under the identity-mapped coverage fixture '
            'this file uses, the assignment ids equal the catalog ids, so '
            "this list is exactly this master's `selectedServiceIds`. A "
            'regression back to `.first` would still pass a `lastServiceId '
            "== 'svc-1'` check (both leave `.first` identical) — this "
            'asserts the LENGTH/full list instead so it can actually catch '
            'that regression.',
      );
    },
  );

  // Phase 14.16/14.17 BUGFIX REGRESSION GUARD (mobile-qa) — reproduces the
  // real production bug: booking a SALON master's service threw a backend
  // `NotFoundException: masterService not found` because this screen sent
  // the salon-wide CATALOG id (`ServiceDefinitionResponse.id`,
  // `SalonCatalogService.id`) as the `serviceId` param to
  // `GET /masters/{masterId}/slots`, which actually requires the master's
  // OWN per-master ASSIGNMENT id (`MasterServiceResponse.id`,
  // `master_services` junction-row id) — a DIFFERENT id space, always a
  // different UUID in production.
  //
  // Every OTHER test in this file uses `_kIdentityCoverage` (assignment id
  // == catalog id) so its pre-existing assertions — several of which
  // literally assert `lastServiceId == 'svc-1'` — keep holding without a
  // redesign. That identity choice makes those tests blind to exactly this
  // bug class: a regression that silently reverted to sending
  // `services.first.id` (the catalog id) instead of resolving
  // `coverage[masterId]?[services.first.id]` (the assignment id) would
  // still produce `lastServiceId == 'svc-1'` under an identity-mapped
  // coverage fixture and pass every other test in this file.
  //
  // This test breaks that identity on purpose — the fixture's assignment id
  // is a DIFFERENT string from the catalog id it maps from, exactly like a
  // real `master_services.id` vs `service_definitions.id` pair — so only a
  // genuinely-correct resolution passes.
  testWidgets(
    "resolves the master's own service-ASSIGNMENT id for the slots query, "
    'never the salon-wide catalog id (regression guard for the '
    'masterService-not-found production bug)',
    (tester) async {
      await _pumpTall(tester);
      const args = SalonBookingTimeArgs(
        salonId: _kSalonId,
        selectedServiceIds: <String>['svc-1'],
        assignedServiceIdsByMaster: <String, List<String>>{
          'm1': <String>['svc-1'],
        },
      );
      final DateTime today = kyivToday(DateTime.now);
      final fake = _FakeSlotRepository(<BookingSlot>[
        BookingSlot(
          startAt: DateTime(today.year, today.month, today.day, 9),
          endAt: DateTime(today.year, today.month, today.day, 10, 30),
          available: true,
        ),
      ]);

      await tester.pumpRoutedApp(
        _router(args: args),
        overrides: _baseOverrides(
          slotRepository: fake,
          selectedServiceIds: const <String>['svc-1'],
          // Deliberately DIFFERENT from the catalog id 'svc-1' — this is
          // what makes the test capable of catching the original bug (see
          // this test's header comment).
          coverage: const <String, Map<String, String>>{
            'm1': <String, String>{'svc-1': 'assignment-m1-svc-1'},
          },
        ),
      );
      await tester.pumpAndSettle();

      final Finder todayCell = find.byKey(
        Key('booking-calendar-day-${today.day}'),
      );
      expect(todayCell, findsOneWidget);
      await tester.tapCalendarDay(today.day);
      await tester.pumpAndSettle();
      // CTA («Далі») commits the date pick into the TIME phase — the tap
      // alone no longer fires the slot query.
      await _tapNextCta(tester);

      expect(fake.getMasterSlotsCallCount, greaterThan(0));
      expect(
        fake.lastServiceId,
        'assignment-m1-svc-1',
        reason:
            'the slots query MUST use the master\'s own service-assignment '
            'id (MasterServiceResponse.id, resolved via '
            'salonMasterServiceCoverageProvider), never the salon-wide '
            'catalog id (ServiceDefinitionResponse.id / '
            'SalonCatalogService.id) — sending the catalog id 404s on the '
            'real backend with "masterService not found", the exact Phase '
            '14.16/14.17 production bug this test guards against.',
      );
      expect(
        fake.lastServiceId,
        isNot('svc-1'),
        reason:
            'must never fall back to the catalog id, even though it is '
            'the id `assignedServiceIdsByMaster` carries into this screen',
      );
    },
  );

  // mobile-qa gap-fix (Phase 14.16/14.17 audit): no test in this file
  // previously exercised the screen's top-level LOADING state (every
  // scenario above resolves `publicSalonProfileProvider`/
  // `salonServiceCatalogProvider` before the first assertion) — the
  // mandatory loading/loaded/empty/error quartet was only 2-of-4 covered.
  group('loading state', () {
    testWidgets(
      'shows a skeleton before the salon profile resolves, then the real '
      'slide once it does',
      (tester) async {
        const args = SalonBookingTimeArgs(
          salonId: _kSalonId,
          selectedServiceIds: <String>['svc-1'],
          assignedServiceIdsByMaster: <String, List<String>>{
            'm1': <String>['svc-1'],
          },
        );
        final completer = Completer<PublicSalonProfileData>();

        await tester.pumpRoutedApp(
          _router(args: args),
          overrides: <Object>[
            publicSalonProfileProvider(
              _kSalonId,
            ).overrideWith((ref) => completer.future),
            salonServiceCatalogProvider(
              _kSalonId,
            ).overrideWith((ref) => _stubCatalog),
            salonMasterServiceCoverageProvider(
              const SalonBookingMasterSelectionArgs(
                salonId: _kSalonId,
                selectedServiceIds: <String>['svc-1'],
              ),
            ).overrideWith((ref) => _kIdentityCoverage),
          ],
        );
        await tester.pump();

        expect(find.byType(SkeletonShimmerScope), findsOneWidget);
        expect(find.byKey(const Key('salon-schedule-page-m1')), findsNothing);

        completer.complete((_stubSalon, const <SalonMasterSummary>[_m1]));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('salon-schedule-page-m1')), findsOneWidget);
      },
    );
  });

  // mobile-qa gap-fix (Phase 14.16/14.17 audit): the time phase's
  // zero-slots-for-this-date empty state (`_NoSlotsEmptyState`, with its
  // own "change date" affordance back to the date phase) was likewise
  // never reached by any existing test — every fake either returned ≥1
  // slot or was never navigated into the time phase at all.
  group('empty state', () {
    testWidgets(
      'shows the no-slots empty state for a date with zero available slots, '
      'and its change-date action returns to the date phase',
      (tester) async {
        await _pumpTall(tester);
        const args = SalonBookingTimeArgs(
          salonId: _kSalonId,
          selectedServiceIds: <String>['svc-1'],
          assignedServiceIdsByMaster: <String, List<String>>{
            'm1': <String>['svc-1'],
          },
        );
        final fake = _FakeSlotRepository(const <BookingSlot>[]);
        final DateTime today = kyivToday(DateTime.now);

        await tester.pumpRoutedApp(
          _router(args: args),
          overrides: _baseOverrides(
            slotRepository: fake,
            selectedServiceIds: const <String>['svc-1'],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tapCalendarDay(today.day);
        await tester.pumpAndSettle();
        // CTA («Далі») commits the date pick into the TIME phase — the tap
        // alone no longer swaps the slide.
        await _tapNextCta(tester);

        expect(
          find.byKey(const Key('salon-schedule-no-slots-empty-state')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('booking-month-calendar')), findsNothing);

        // mobile-perf regression guard (HIGH): before the `_timePhase`
        // `content` fix, the phase's `Column` used `crossAxisAlignment
        // .start`, which — being a descendant of `AnimatedSwitcher`'s
        // `Stack(alignment: .center, fit: StackFit.loose)` — sized itself
        // to its narrowest branch instead of the full slide width,
        // shrinking the phase's own `Semantics(container: true)` node (the
        // bounding box TalkBack uses for the "scrub"/Z-gesture `onDismiss`
        // action) down to a sliver. With `content`'s `Column` forced to
        // `.stretch`, the phase container must always span the full slide
        // width, matching `_datePhase`'s sibling phase exactly.
        expect(
          tester.getSize(find.byKey(const ValueKey<String>('time'))).width,
          tester.getSize(find.byKey(const Key('salon-schedule-page-m1'))).width,
          reason:
              'the time phase container (and therefore its accessible '
              'Semantics bounding box) must span the full slide width even '
              'when the empty-state content is narrower',
        );

        await tester.tap(
          find.byKey(const Key('salon-schedule-no-slots-change-date')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('salon-schedule-no-slots-empty-state')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('booking-month-calendar')),
          findsOneWidget,
          reason: 'the change-date action must return to the date phase',
        );
      },
    );
  });

  // mobile-qa gap-fix (Phase 14.16/14.17 audit): no test in this file
  // previously exercised EITHER of `SalonTimeScreen`'s two real error
  // states — the mandate ("never accept a screen test that omits the error
  // state with retry interaction") applies to BOTH: the screen-level
  // salon/catalog load failure, and each slide's working-days fetch
  // failure. Every fixture used above always succeeds, so a regression that
  // broke either retry wire (e.g. `onRetry` invalidating the wrong
  // provider) would have shipped silently.
  group('error states', () {
    testWidgets(
      'shows the top-level error state when the salon profile/catalog fails '
      'to load, and its retry button re-fetches successfully',
      (tester) async {
        const args = SalonBookingTimeArgs(
          salonId: _kSalonId,
          selectedServiceIds: <String>['svc-1'],
          assignedServiceIdsByMaster: <String, List<String>>{
            'm1': <String>['svc-1'],
          },
        );
        int profileCalls = 0;

        await tester.pumpRoutedApp(
          _router(args: args),
          // Disables Riverpod's default exponential-backoff retry so the
          // error state stays put through pumpAndSettle instead of
          // silently auto-recovering before the assertion runs — mirrors
          // `salon_service_selection_screen_test.dart`'s identical need.
          retry: (_, _) => null,
          overrides: <Object>[
            publicSalonProfileProvider(_kSalonId).overrideWith((ref) async {
              profileCalls++;
              if (profileCalls == 1) throw Exception('boom');
              return (_stubSalon, const <SalonMasterSummary>[_m1]);
            }),
            salonServiceCatalogProvider(
              _kSalonId,
            ).overrideWith((ref) => _stubCatalog),
            salonMasterServiceCoverageProvider(
              const SalonBookingMasterSelectionArgs(
                salonId: _kSalonId,
                selectedServiceIds: <String>['svc-1'],
              ),
            ).overrideWith((ref) => _kIdentityCoverage),
          ],
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('salon-time-error-state')), findsOneWidget);
        expect(find.byKey(const Key('salon-schedule-page-m1')), findsNothing);

        await tester.tap(find.byKey(const Key('error_state_retry_button')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('salon-time-error-state')), findsNothing);
        expect(find.byKey(const Key('salon-schedule-page-m1')), findsOneWidget);
      },
    );

    testWidgets(
      "a master's date-phase working-days fetch failure shows the real "
      'error body with a working retry button',
      (tester) async {
        await _pumpTall(tester);
        const args = SalonBookingTimeArgs(
          salonId: _kSalonId,
          selectedServiceIds: <String>['svc-1'],
          assignedServiceIdsByMaster: <String, List<String>>{
            'm1': <String>['svc-1'],
          },
        );
        final fake = _ThrowOnceWorkingDaysSlotRepository();

        await tester.pumpRoutedApp(
          _router(args: args),
          retry: (_, _) => null,
          overrides: _baseOverrides(
            slotRepository: fake,
            selectedServiceIds: const <String>['svc-1'],
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('salon-schedule-calendar-retry')),
          findsOneWidget,
          reason:
              'the first working-days fetch throws — the date phase must '
              'show the error body, not a stuck spinner or a blank '
              'calendar',
        );
        expect(find.byKey(const Key('booking-month-calendar')), findsNothing);

        await tester.tap(
          find.byKey(const Key('salon-schedule-calendar-retry')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('salon-schedule-calendar-retry')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('booking-month-calendar')),
          findsOneWidget,
          reason: 'retry must re-fetch and render the real calendar',
        );
        expect(fake.getWorkingDaysCalls, 2);
      },
    );

    testWidgets("a master's time-phase slot fetch failure shows the "
        '"немає вільних слотів" message instead of a stuck spinner', (
      tester,
    ) async {
      await _pumpTall(tester);
      const args = SalonBookingTimeArgs(
        salonId: _kSalonId,
        selectedServiceIds: <String>['svc-1'],
        assignedServiceIdsByMaster: <String, List<String>>{
          'm1': <String>['svc-1'],
        },
      );
      final fake = _ThrowingMasterSlotsSlotRepository();
      final DateTime today = kyivToday(DateTime.now);

      await tester.pumpRoutedApp(
        _router(args: args),
        overrides: _baseOverrides(
          slotRepository: fake,
          selectedServiceIds: const <String>['svc-1'],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tapCalendarDay(today.day);
      await tester.pumpAndSettle();
      // CTA («Далі») commits the date pick into the TIME phase.
      await _tapNextCta(tester);

      final l10n = AppLocalizations.of(
        tester.element(find.byType(SalonTimeScreen)),
      );
      expect(find.text(l10n.bookingDayUnavailableState), findsOneWidget);
      expect(
        find.byKey(const Key('salon-schedule-no-slots-empty-state')),
        findsNothing,
      );

      // mobile-perf regression guard (HIGH): the error branch is a bare,
      // SINGLE-LINE `Text` in a `Padding` — not wrapped in
      // `Center`/`Expanded` — so it never claims full width on its own.
      // Before the `_timePhase` `content` fix (`crossAxisAlignment.start`,
      // a descendant of `AnimatedSwitcher`'s loose-fit `Stack`), this phase
      // container rendered at only the error text's own narrow natural
      // width (165px in this test's 800-wide viewport) instead of the full
      // slide — shrinking the accessible `Semantics(container: true)`
      // bounding box TalkBack uses for the "scrub"/Z-gesture `onDismiss`
      // action down to a sliver in the corner. `.stretch` restores the
      // full-width container regardless of branch content.
      expect(
        tester.getSize(find.byKey(const ValueKey<String>('time'))).width,
        tester.getSize(find.byKey(const Key('salon-schedule-page-m1'))).width,
        reason:
            'the time phase container (and therefore its accessible '
            'Semantics bounding box) must span the full slide width even '
            'when the error-state content is narrower',
      );
    });
  });

  // ===========================================================================
  // mobile-qa gap (card-unification audit): the schedule page's identity
  // header is the SHARED `MasterStrip(showRole: true, showRating: true)`
  // card, but no test asserted the ACTUAL rating digits render here, nor
  // that this call site is one of the "everywhere else" screens where the
  // "Запис до майстра" caption (showLabel) stays ON — only the picker
  // (`salon_master_selection_screen_test.dart`) opts it off.
  // ===========================================================================
  testWidgets(
    "the schedule page's MasterStrip renders the assigned master's own "
    '★rating(reviewCount), and (unlike the picker) the "Запис до майстра" '
    'caption',
    (tester) async {
      const args = SalonBookingTimeArgs(
        salonId: _kSalonId,
        selectedServiceIds: <String>['svc-1', 'svc-2'],
        assignedServiceIdsByMaster: <String, List<String>>{
          'm1': <String>['svc-1'],
        },
      );
      final fake = _FakeSlotRepository(const <BookingSlot>[]);
      await tester.pumpRoutedApp(
        _router(args: args),
        overrides: _baseOverrides(slotRepository: fake),
      );
      await tester.pumpAndSettle();

      final Finder slide = find.byKey(const Key('salon-schedule-page-m1'));
      expect(
        find.descendant(of: slide, matching: find.text('4.9')),
        findsOneWidget,
        reason:
            "MasterStrip(showRating: true) must render m1's "
            'avgRating.toStringAsFixed(1) (4.9) on the calendar/time slide.',
      );
      expect(
        find.descendant(of: slide, matching: find.text('(12)')),
        findsOneWidget,
      );

      final l10n = AppLocalizations.of(
        tester.element(find.byType(SalonTimeScreen)),
      );
      expect(
        find.descendant(
          of: slide,
          matching: find.text(l10n.bookingMasterStripLabel),
        ),
        findsOneWidget,
        reason:
            'unlike the master picker (showLabel: false), every other '
            'salon booking screen — including this one — must still show '
            'the "Запис до майстра" caption above the shared identity card',
      );
    },
  );

  // mobile-qa gap-fix — `ScheduleConfirmBar`'s shelf composition is pinned in
  // `schedule_confirm_bar_test.dart` at the widget level, but this screen's
  // OWN `selectedServices` flattening (every assigned master's
  // `schedule.services`, back into the client's full original selection — see
  // this file's header comment on `selectedServices`) had no coverage from
  // the real screen at all. This drives the actual `SalonTimeScreen` with two
  // masters assigned DIFFERENT services and asserts BOTH show up in the
  // expanded shelf, while the pre-existing progress counter + CTA survive.
  group('selected-services shelf composition (mobile-qa gap-fix)', () {
    const Key toggleKey = Key('booking-summary-expand-toggle');
    const Key expandedListKey = Key('booking-summary-expanded-list');

    // Every shelf assertion is scoped to the shelf's OWN `expanded-list`
    // subtree rather than searching the whole screen. `MasterSchedulePage`
    // does not currently render the service name anywhere else, so an
    // unscoped `find.text(_svc1.name)` happens to pass today — but that is
    // exactly the latent trap that DID bite on
    // `salon_master_selection_screen_test.dart`, where each eligible master
    // row's "covers: <service names>" subtitle draws from the SAME fixture
    // names and made an unscoped finder match two widgets. Scoping here keeps
    // the assertion proving the SHELF's content specifically, so a future
    // slide that happens to echo a service name can never silently satisfy
    // (or falsely break) this test.
    Finder inShelf(Finder matching) =>
        find.descendant(of: find.byKey(expandedListKey), matching: matching);

    testWidgets('expanding the shelf shows every assigned master\'s services '
        '(flattened across masters), while the schedule progress counter and '
        'CTA stay in place', (tester) async {
      const args = SalonBookingTimeArgs(
        salonId: _kSalonId,
        selectedServiceIds: <String>['svc-1', 'svc-2'],
        assignedServiceIdsByMaster: <String, List<String>>{
          'm1': <String>['svc-1'],
          'm2': <String>['svc-2'],
        },
      );
      final fake = _FakeSlotRepository(const <BookingSlot>[]);
      await tester.pumpRoutedApp(
        _router(args: args),
        overrides: _baseOverrides(
          masters: const <SalonMasterSummary>[_m1, _m2],
          slotRepository: fake,
        ),
      );
      await tester.pumpAndSettle();

      // Collapsed: the shelf's own itemized list is not built at all yet.
      expect(find.byKey(expandedListKey), findsNothing);

      await tester.tap(find.byKey(toggleKey));
      await tester.pumpAndSettle();

      // i18n-finder-ok: fixture service names (test data), not app UI copy.
      expect(inShelf(find.text(_svc1.name)), findsOneWidget);
      // i18n-finder-ok: fixture service names (test data), not app UI copy.
      expect(inShelf(find.text(_svc2.name)), findsOneWidget);

      // The pre-existing "X з Y заплановано" progress counter + CTA must
      // still be present once the shelf is expanded.
      final l10n = AppLocalizations.of(
        tester.element(find.byType(SalonTimeScreen)),
      );
      expect(find.text(l10n.salonScheduleProgress(0, 2)), findsOneWidget);
      final NeumorphicButton cta = tester.widget<NeumorphicButton>(
        find.byKey(const Key('schedule-confirm-cta')),
      );
      expect(cta.onPressed, isNull); // nothing scheduled yet
    });
  });

  // ===========================================================================
  // ScreenProtectionManager lifecycle (mobile-security MEDIUM fix — this
  // screen now renders the client's selected service names + prices via
  // `SelectedServicesShelf` inside the pinned `ScheduleConfirmBar`). Mirrors
  // `salon_master_selection_screen_test.dart`'s established acquire/release
  // pattern for the SAME class of fix on the previous step.
  // ===========================================================================
  group('ScreenProtectionManager lifecycle (mobile-security gap-fix)', () {
    const args = SalonBookingTimeArgs(
      salonId: _kSalonId,
      selectedServiceIds: <String>['svc-1'],
      assignedServiceIdsByMaster: <String, List<String>>{
        'm1': <String>['svc-1'],
      },
    );

    testWidgets(
      'acquire() is called exactly once when the time screen mounts',
      (tester) async {
        final fake = _FakeSlotRepository(const <BookingSlot>[]);
        final GoRouter router = _pushableRouter(args: args);
        final _CountingScreenProtection counting = _CountingScreenProtection();

        await tester.pumpRoutedApp(
          router,
          overrides: <Object>[
            ..._baseOverrides(
              slotRepository: fake,
              selectedServiceIds: const <String>['svc-1'],
            ),
            screenProtectionProvider.overrideWithValue(counting),
          ],
        );
        unawaited(router.push(RouteNames.salonBookingTime));
        await tester.pumpAndSettle();

        expect(
          counting.acquireCount,
          1,
          reason:
              'initState must call acquire() exactly once to enable '
              'FLAG_SECURE now that this screen renders selected service '
              'names + prices via SelectedServicesShelf',
        );
      },
    );

    testWidgets(
      'release() is called exactly once when the time screen is popped '
      '(disposed) — acquire/release stay symmetric',
      (tester) async {
        final fake = _FakeSlotRepository(const <BookingSlot>[]);
        final GoRouter router = _pushableRouter(args: args);
        final _CountingScreenProtection counting = _CountingScreenProtection();

        await tester.pumpRoutedApp(
          router,
          overrides: <Object>[
            ..._baseOverrides(
              slotRepository: fake,
              selectedServiceIds: const <String>['svc-1'],
            ),
            screenProtectionProvider.overrideWithValue(counting),
          ],
        );
        unawaited(router.push(RouteNames.salonBookingTime));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('salon-time-back')));
        await tester.pumpAndSettle();

        expect(
          counting.releaseCount,
          1,
          reason:
              'dispose() must call release() exactly once so FLAG_SECURE is '
              'cleared once the time screen is popped',
        );
        expect(counting.acquireCount, counting.releaseCount);
      },
    );

    // ── Back-navigation BUGFIX × FLAG_SECURE interaction (mobile-qa audit,
    // build-verifier gap) ──────────────────────────────────────────────────
    // The two tests above only cover a REAL pop (arrow from the DATE phase →
    // dispose → release). Neither wires `_CountingScreenProtection` into the
    // BLOCKED-back path the bugfix introduced: a back press while the ACTIVE
    // slide is in its TIME phase only calls `clearDate` and must keep the
    // screen MOUNTED.
    //
    // The back-navigation regression tests further down assert
    // `find.byType(SalonTimeScreen) findsOneWidget` afterwards, which
    // structurally IMPLIES dispose (and therefore `release()`) never fired —
    // but that is an inference, not an assertion. The whole point of the
    // `PopScope` is that a handled back does NOT unmount this screen, and a
    // premature `release()` here would silently drop FLAG_SECURE on a screen
    // still rendering the client's selected service names + prices (via the
    // pinned `SelectedServicesShelf`). That is a security-relevant invariant
    // and deserves a DIRECT assertion on the acquire/release counters, for
    // BOTH affordances the fix touches.
    //
    // `_pushableRouter` (not `_router`) is used deliberately: it puts a real
    // route BEHIND this screen, so a regression that let the back through
    // would genuinely pop + dispose it — making `releaseCount == 0` a
    // meaningful assertion rather than a vacuous one.

    /// Pushes the time screen and drives m1 into its TIME phase (date picked,
    /// no slot yet) — the state in which a back press must be HANDLED
    /// (clearDate) rather than popping the route.
    Future<_CountingScreenProtection> pushInTimePhase(
      WidgetTester tester,
    ) async {
      await _pumpTall(tester);
      final fake = _FakeSlotRepository(const <BookingSlot>[]);
      final GoRouter router = _pushableRouter(args: args);
      final _CountingScreenProtection counting = _CountingScreenProtection();

      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[
          ..._baseOverrides(
            slotRepository: fake,
            selectedServiceIds: const <String>['svc-1'],
          ),
          screenProtectionProvider.overrideWithValue(counting),
        ],
      );
      unawaited(router.push(RouteNames.salonBookingTime));
      await tester.pumpAndSettle();

      final DateTime today = kyivToday(DateTime.now);
      await tester.tapCalendarDay(today.day);
      await tester.pumpAndSettle();
      // CTA («Далі») commits the date pick into the TIME phase.
      await _tapNextCta(tester);

      // Sanity: m1 really is in the time phase before the back press.
      expect(
        find.descendant(
          of: find.byKey(const Key('salon-schedule-page-m1')),
          matching: find.byKey(const ValueKey<String>('time')),
        ),
        findsOneWidget,
      );
      return counting;
    }

    testWidgets(
      'a HANDLED back from the TIME phase via the in-app arrow keeps the '
      'screen mounted and does NOT release() — FLAG_SECURE must stay on '
      "while the client's service names + prices are still rendered",
      (tester) async {
        final _CountingScreenProtection counting = await pushInTimePhase(
          tester,
        );

        await tester.tap(find.byKey(const Key('salon-time-back')));
        await tester.pumpAndSettle();

        expect(find.byType(SalonTimeScreen), findsOneWidget);
        expect(
          counting.releaseCount,
          0,
          reason:
              'a back press the PopScope/arrow HANDLES (clearDate only) must '
              'never dispose the screen — a release() here would drop '
              'FLAG_SECURE on a screen still showing the selected service '
              'names + prices',
        );
        expect(
          counting.acquireCount,
          1,
          reason:
              'the screen never remounted either — acquire() stays at the '
              'single initState call',
        );
      },
    );

    testWidgets(
      'a HANDLED back from the TIME phase via the Android system back '
      '(PopScope) likewise keeps the screen mounted and does NOT release()',
      (tester) async {
        final _CountingScreenProtection counting = await pushInTimePhase(
          tester,
        );

        final bool handled = await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(
          handled,
          isTrue,
          reason:
              'PopScope must intercept the system back while the active '
              'slide is in the time phase',
        );
        expect(find.byType(SalonTimeScreen), findsOneWidget);
        expect(
          counting.releaseCount,
          0,
          reason:
              'the system-back affordance must honour the SAME FLAG_SECURE '
              'invariant as the in-app arrow — a handled back never '
              'disposes, so it never releases',
        );
        expect(counting.acquireCount, 1);
      },
    );
  });

  // ===========================================================================
  // BUGFIX REGRESSION GUARD — "Час" step back navigation (mobile-qa audit).
  //
  // THE BUG: once a master's date was picked, that master's slide swapped
  // in-widget from the calendar to the time-slot grid (no route behind that
  // transition). Pressing back — EITHER the in-app arrow (`onBack: () =>
  // context.pop()`) OR the Android system back gesture (no `PopScope`
  // existed at all) — popped the ENTIRE `SalonTimeScreen` route out to
  // master-selection instead of returning that one slide to its calendar.
  // The client lost their place, including any OTHER master's already-
  // completed date+time.
  //
  // THE FIX: `_exitActiveMasterTimePhase()` calls the SAME
  // `salonBookingScheduleProvider.notifier.clearDate(activeMasterId)`
  // `_ChangeDateButton` already uses, reached from BOTH `_handleTopBarBack`
  // (the arrow) and a `PopScope` wrapping the `Scaffold` (the system
  // gesture) — so both affordances now stay mounted and revert only the
  // ACTIVE slide while every other master's picks are untouched. On the
  // DATE phase (nothing to revert), both affordances fall through to a
  // real route pop — this file also guards against overcorrecting that
  // into "back never exits".
  //
  // `_router` (NOT `_pushableRouter`) is used for the two time-phase tests
  // below: it mounts `SalonTimeScreen` as the ONLY route (no route behind
  // it) — the exact shape that made the original bug's real pop land
  // somewhere wrong/nowhere. `tester.binding.handlePopRoute()` is the
  // established convention for driving the platform back gesture in this
  // codebase (mirrors `client_shell_back_to_home_test.dart`), distinct from
  // tapping the in-app arrow key.
  // ===========================================================================
  group('back navigation from the TIME phase reverts only the active master, '
      'never the whole screen (mobile-qa bugfix regression guard)', () {
    const args = SalonBookingTimeArgs(
      salonId: _kSalonId,
      selectedServiceIds: <String>['svc-1', 'svc-2'],
      assignedServiceIdsByMaster: <String, List<String>>{
        'm1': <String>['svc-1'],
        'm2': <String>['svc-2'],
      },
    );

    Finder slideOf(String masterId) =>
        find.byKey(Key('salon-schedule-page-$masterId'), skipOffstage: false);
    Finder withinSlide(String masterId, Finder matching) => find.descendant(
      of: slideOf(masterId),
      matching: matching,
      skipOffstage: false,
    );

    /// Completes m1 (date + slot, fully scheduled) then picks ONLY m2's
    /// date — the slider auto-advances onto m2, leaving its slide in the
    /// TIME phase with no slot chosen yet: the exact state the original
    /// bug lost. m1 stays mounted (current ± 1 keep-alive) so this file's
    /// "m1 untouched" assertions are non-vacuous.
    Future<void> setUpM1DoneM2TimePhase(WidgetTester tester) async {
      await _pumpTall(tester);
      final DateTime today = kyivToday(DateTime.now);
      DateTime at(int hour) =>
          DateTime(today.year, today.month, today.day, hour);
      final fake = _PerMasterFakeSlotRepository(<String, List<BookingSlot>>{
        'm1': <BookingSlot>[
          BookingSlot(
            startAt: at(9),
            endAt: at(9).add(const Duration(minutes: 90)),
            available: true,
          ),
        ],
        'm2': <BookingSlot>[
          BookingSlot(
            startAt: at(11),
            endAt: at(11).add(const Duration(minutes: 60)),
            available: true,
          ),
        ],
      });

      await tester.pumpRoutedApp(
        _router(args: args),
        overrides: _baseOverrides(
          masters: const <SalonMasterSummary>[_m1, _m2],
          slotRepository: fake,
        ),
      );
      await tester.pumpAndSettle();

      // Forward navigation is CTA-driven now — each step that used to
      // happen automatically off a date/slot tap is an explicit
      // `_tapNextCta` press.
      await tester.tapCalendarDay(today.day, within: slideOf('m1'));
      await tester.pumpAndSettle();
      await _tapNextCta(tester); // m1: DATE phase → TIME phase.
      await tester.tap(
        withinSlide(
          'm1',
          find.byKey(Key('salon-slot-chip-${at(9).toIso8601String()}')),
        ),
      );
      await tester.pumpAndSettle();
      await _tapNextCta(tester); // m1 scheduled → pager advances to m2.

      await tester.tapCalendarDay(today.day, within: slideOf('m2'));
      await tester.pumpAndSettle();
      await _tapNextCta(tester); // m2: DATE phase → TIME phase.

      // Sanity: m2 really is in the time phase before the back press.
      expect(
        withinSlide('m2', find.byKey(const ValueKey<String>('time'))),
        findsOneWidget,
      );
      expect(
        withinSlide('m2', find.byKey(const ValueKey<String>('date'))),
        findsNothing,
      );
    }

    testWidgets(
      "the in-app back arrow clears only the active master's (m2) date, "
      "reverting its slide to the calendar; m1's completed date+slot and "
      'the screen itself are untouched',
      (tester) async {
        await setUpM1DoneM2TimePhase(tester);

        final ProviderContainer container = ProviderScope.containerOf(
          tester.element(find.byType(SalonTimeScreen)),
        );
        final SalonScheduleEntry m1Before = container
            .read(salonBookingScheduleProvider)
            .entryFor('m1');
        expect(
          m1Before.isScheduled,
          isTrue,
          reason: 'sanity: m1 must be fully scheduled before the back press',
        );

        await tester.tap(find.byKey(const Key('salon-time-back')));
        await tester.pumpAndSettle();

        // Still mounted — a real pop would have removed this screen.
        expect(find.byType(SalonTimeScreen), findsOneWidget);

        // m2's slide reverted to the calendar; the time-phase subtree is
        // gone.
        expect(
          withinSlide('m2', find.byKey(const ValueKey<String>('date'))),
          findsOneWidget,
        );
        expect(
          withinSlide('m2', find.byKey(const ValueKey<String>('time'))),
          findsNothing,
        );

        final SalonBookingScheduleState after = container.read(
          salonBookingScheduleProvider,
        );
        expect(
          after.entryFor('m2').date,
          isNull,
          reason: "the back arrow must clear ONLY m2's date",
        );
        expect(after.entryFor('m2').slot, isNull);

        // m1's completed pick is untouched.
        expect(
          after.entryFor('m1').date,
          m1Before.date,
          reason: "m1's already-picked date must survive m2's back press",
        );
        expect(after.entryFor('m1').slot, m1Before.slot);
      },
    );

    testWidgets(
      'the Android system back gesture (PopScope) clears only the active '
      "master's (m2) date, reverting its slide to the calendar — the "
      'SECOND affordance the original bug broke identically',
      (tester) async {
        await setUpM1DoneM2TimePhase(tester);

        final ProviderContainer container = ProviderScope.containerOf(
          tester.element(find.byType(SalonTimeScreen)),
        );
        final SalonScheduleEntry m1Before = container
            .read(salonBookingScheduleProvider)
            .entryFor('m1');

        final bool handled = await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(
          handled,
          isTrue,
          reason:
              'PopScope must intercept the system back while the active '
              'slide is in the time phase (canPop: false) — `handled == '
              'false` would mean nothing intercepted it and the OS would '
              'have exited/popped past this screen, exactly the original '
              'bug',
        );
        expect(find.byType(SalonTimeScreen), findsOneWidget);
        expect(
          withinSlide('m2', find.byKey(const ValueKey<String>('date'))),
          findsOneWidget,
        );
        expect(
          withinSlide('m2', find.byKey(const ValueKey<String>('time'))),
          findsNothing,
        );

        final SalonBookingScheduleState after = container.read(
          salonBookingScheduleProvider,
        );
        expect(
          after.entryFor('m2').date,
          isNull,
          reason: 'the system back gesture must clear ONLY m2\'s date',
        );
        expect(after.entryFor('m2').slot, isNull);
        expect(after.entryFor('m1').date, m1Before.date);
        expect(after.entryFor('m1').slot, m1Before.slot);
      },
    );

    testWidgets(
      "a left-edge swipe-back gesture on the active slide's TIME phase "
      "clears only that master's (m2) date, reverting its slide to the "
      'calendar — the THIRD affordance, restoring what the route-level '
      '`PopScope(canPop: false)` silently disarmed (Cupertino never arms '
      'its own edge-drag recognizer while `canPop` is false)',
      (tester) async {
        await setUpM1DoneM2TimePhase(tester);

        final ProviderContainer container = ProviderScope.containerOf(
          tester.element(find.byType(SalonTimeScreen)),
        );
        final SalonScheduleEntry m1Before = container
            .read(salonBookingScheduleProvider)
            .entryFor('m1');

        // A left-edge drag toward the right, comfortably past the commit
        // distance threshold — `tester.drag` starts from the found widget's
        // own center, which sits inside the narrow edge strip by
        // construction, so this exercises the SAME hit-test path a real
        // user's swipe-back gesture would.
        await tester.drag(
          withinSlide(
            'm2',
            find.byKey(const Key('salon-schedule-time-edge-back-swipe')),
          ),
          const Offset(120, 0),
        );
        await tester.pumpAndSettle();

        // Still mounted — a slide-local gesture, never a route pop.
        expect(find.byType(SalonTimeScreen), findsOneWidget);

        expect(
          withinSlide('m2', find.byKey(const ValueKey<String>('date'))),
          findsOneWidget,
        );
        expect(
          withinSlide('m2', find.byKey(const ValueKey<String>('time'))),
          findsNothing,
        );

        final SalonBookingScheduleState after = container.read(
          salonBookingScheduleProvider,
        );
        expect(
          after.entryFor('m2').date,
          isNull,
          reason: "the edge swipe-back must clear ONLY m2's date",
        );
        expect(after.entryFor('m2').slot, isNull);
        expect(after.entryFor('m1').date, m1Before.date);
        expect(after.entryFor('m1').slot, m1Before.slot);
      },
    );
  });

  // ===========================================================================
  // Left-edge swipe-back gesture SCOPING (mobile-dev fix regression guards).
  // The reverting behaviour itself is covered above; these two tests instead
  // prove the two hard constraints the fix's PR description calls out:
  //   1. The detector must never be part of the DATE phase's hit-test path —
  //      proven here by its outright ABSENCE (`findsNothing`), so it can
  //      never steal the real Cupertino edge-swipe-to-master-selection that
  //      phase relies on.
  //   2. A drag that starts mid-slide (nowhere near the left-edge strip)
  //      must still page the `PageView` between masters, and must NOT clear
  //      the dragged-FROM master's already-picked date — proving the
  //      detector's narrow footprint never intercepts a normal
  //      master-to-master swipe.
  // ===========================================================================
  group('left-edge swipe-back gesture scoping (mobile-dev fix)', () {
    const args = SalonBookingTimeArgs(
      salonId: _kSalonId,
      selectedServiceIds: <String>['svc-1', 'svc-2'],
      assignedServiceIdsByMaster: <String, List<String>>{
        'm1': <String>['svc-1'],
        'm2': <String>['svc-2'],
      },
    );

    testWidgets(
      'the edge detector is absent on the DATE phase and only appears once '
      'the active slide reaches the TIME phase',
      (tester) async {
        await _pumpTall(tester);
        final fake = _FakeSlotRepository(const <BookingSlot>[]);

        await tester.pumpRoutedApp(
          _router(args: args),
          overrides: _baseOverrides(
            masters: const <SalonMasterSummary>[_m1, _m2],
            slotRepository: fake,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('salon-schedule-time-edge-back-swipe')),
          findsNothing,
          reason:
              'fresh mount — m1 starts on the DATE phase, where the real '
              'Cupertino edge-swipe (armed by `PopScope(canPop: true)`) '
              'must be the ONLY left-edge affordance; this detector must '
              'not exist yet to have any chance of competing with it',
        );

        final DateTime today = kyivToday(DateTime.now);
        await tester.tapCalendarDay(today.day);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('salon-schedule-time-edge-back-swipe')),
          findsNothing,
          reason:
              'the date pick alone must not swap the slide into the TIME '
              'phase — only the CTA does',
        );

        // CTA («Далі») commits the date pick into the TIME phase.
        await _tapNextCta(tester);

        expect(
          find.byKey(const Key('salon-schedule-time-edge-back-swipe')),
          findsOneWidget,
          reason: 'once m1 reaches the TIME phase the detector must mount',
        );
      },
    );

    testWidgets(
      'a drag starting mid-slide (away from the left edge) still pages the '
      "PageView to the next master and leaves the dragged-from master's "
      'picked date untouched — the detector\'s narrow footprint must never '
      "intercept the PageView's own master-to-master swipe",
      (tester) async {
        await _pumpTall(tester);
        final fake = _FakeSlotRepository(const <BookingSlot>[]);

        await tester.pumpRoutedApp(
          _router(args: args),
          overrides: _baseOverrides(
            masters: const <SalonMasterSummary>[_m1, _m2],
            slotRepository: fake,
          ),
        );
        await tester.pumpAndSettle();

        // Put m1 (current) on its TIME phase without completing it, so its
        // `date` is non-null and would reveal a false-positive phase-back if
        // the upcoming mid-slide drag wrongly reached the edge detector.
        final DateTime today = kyivToday(DateTime.now);
        await tester.tapCalendarDay(today.day);
        await tester.pumpAndSettle();

        final ProviderContainer container = ProviderScope.containerOf(
          tester.element(find.byType(SalonTimeScreen)),
        );
        final DateTime? m1DateBefore = container
            .read(salonBookingScheduleProvider)
            .entryFor('m1')
            .date;
        expect(
          m1DateBefore,
          isNotNull,
          reason: 'sanity: m1 must have a picked date before the drag',
        );

        // Starts from m1's slide's own CENTER — nowhere near the 20px-wide
        // left-edge strip — and drags leftward far enough (well over half
        // the 800-wide test viewport from `_pumpTall`) to page to m2.
        await tester.drag(
          find.byKey(const Key('salon-schedule-page-m1')),
          const Offset(-500, 0),
        );
        await tester.pumpAndSettle();

        final l10n = AppLocalizations.of(
          tester.element(find.byType(SalonTimeScreen)),
        );
        expect(
          find.text(l10n.salonSchedulePagerCounterLabel(2, 2)),
          findsOneWidget,
          reason: 'the mid-slide drag must page the PageView to master 2',
        );

        final DateTime? m1DateAfter = container
            .read(salonBookingScheduleProvider)
            .entryFor('m1')
            .date;
        expect(
          m1DateAfter,
          m1DateBefore,
          reason:
              "a mid-slide master-to-master swipe must NEVER clear the "
              "dragged-from master's date — if this fails, the edge "
              'detector is intercepting drags outside its intended '
              'narrow left-edge footprint',
        );
      },
    );
  });

  testWidgets(
    'back while the active master is still on the DATE phase performs a '
    'real route pop to master-selection — guards against overcorrecting '
    'into "back never exits" (mobile-qa bugfix regression guard)',
    (tester) async {
      const args = SalonBookingTimeArgs(
        salonId: _kSalonId,
        selectedServiceIds: <String>['svc-1'],
        assignedServiceIdsByMaster: <String, List<String>>{
          'm1': <String>['svc-1'],
        },
      );
      final fake = _FakeSlotRepository(const <BookingSlot>[]);
      final GoRouter router = _pushableRouter(args: args);

      await tester.pumpRoutedApp(
        router,
        overrides: _baseOverrides(
          slotRepository: fake,
          selectedServiceIds: const <String>['svc-1'],
        ),
      );
      unawaited(router.push(RouteNames.salonBookingTime));
      await tester.pumpAndSettle();

      // Fresh mount — m1 defaults to the date phase (no date picked yet).
      expect(find.byKey(const Key('salon-schedule-page-m1')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('date')), findsOneWidget);

      await tester.tap(find.byKey(const Key('salon-time-back')));
      await tester.pumpAndSettle();

      expect(
        find.byType(SalonTimeScreen),
        findsNothing,
        reason: 'a date-phase back must be a REAL pop out to master-selection',
      );
      // English sentinel text from `_pushableRouter`'s own placeholder route
      // — not app UI copy, so no i18n-finder-ok annotation is needed here.
      expect(find.text('start'), findsOneWidget);
    },
  );

  // ===========================================================================
  // PERMANENT PERF GUARD (mobile-perf) — the `PopScope`-wrapping `Consumer`
  // added by this bugfix (`build()`'s trailing `Consumer` around `PopScope`)
  // exists ONLY so a date pick on the active slide can keep `canPop` fresh
  // WITHOUT the outer `build()` re-running (which would reconstruct
  // `PageView.builder` and rebuild every mounted neighbour slide — the
  // original mobile-perf Finding A). `mobile-dev` proved this with a
  // throwaway probe during the fix, then deleted it; this recreates it as a
  // standing regression guard, mirroring the pre-existing slot-pick probe
  // above (`salon-schedule-page-m1`/`salon-schedule-page-m2` rebuild-scoping
  // test) with the SAME `debugPrintRebuildDirtyWidgets` proxy technique and
  // the SAME anti-vacuity canary shape: assert the thing that SHOULD
  // rebuild (PopScope itself) actually did, so a dead/disconnected hook
  // fails loudly instead of silently satisfying the negative assertions.
  // ===========================================================================
  testWidgets(
    "picking master 2's DATE (not a slot) rebuilds the PopScope-wrapping "
    "Consumer but never PageView.builder nor master 1's already-completed "
    'slide — standing perf guard for the back-navigation fix\'s Consumer '
    'hoist (was a throwaway mobile-perf probe)',
    (tester) async {
      await _pumpTall(tester);
      const args = SalonBookingTimeArgs(
        salonId: _kSalonId,
        selectedServiceIds: <String>['svc-1', 'svc-2'],
        assignedServiceIdsByMaster: <String, List<String>>{
          'm1': <String>['svc-1'],
          'm2': <String>['svc-2'],
        },
      );
      final DateTime today = kyivToday(DateTime.now);
      DateTime at(int hour) =>
          DateTime(today.year, today.month, today.day, hour);
      final fake = _PerMasterFakeSlotRepository(<String, List<BookingSlot>>{
        'm1': <BookingSlot>[
          BookingSlot(
            startAt: at(9),
            endAt: at(9).add(const Duration(minutes: 90)),
            available: true,
          ),
        ],
        'm2': <BookingSlot>[
          BookingSlot(
            startAt: at(11),
            endAt: at(11).add(const Duration(minutes: 60)),
            available: true,
          ),
        ],
      });

      Finder slideOf(String masterId) =>
          find.byKey(Key('salon-schedule-page-$masterId'), skipOffstage: false);
      Finder withinSlide(String masterId, Finder matching) => find.descendant(
        of: slideOf(masterId),
        matching: matching,
        skipOffstage: false,
      );

      await tester.pumpRoutedApp(
        _router(args: args),
        overrides: _baseOverrides(
          masters: const <SalonMasterSummary>[_m1, _m2],
          slotRepository: fake,
        ),
      );
      await tester.pumpAndSettle();

      // Complete m1 (date → CTA into TIME phase → its slot → CTA again to
      // advance the pager) so the pager lands on m2, current ± 1 from m1
      // (Finding B's retention bound keeps m1's slide mounted — required
      // for the "m1 never rebuilds" assertion below to be non-vacuous).
      // Forward navigation is CTA-driven now — see this file's `_tapNextCta`
      // doc comment.
      await tester.tapCalendarDay(today.day, within: slideOf('m1'));
      await tester.pumpAndSettle();
      await _tapNextCta(tester); // m1: DATE phase → TIME phase.
      await tester.tap(
        withinSlide(
          'm1',
          find.byKey(Key('salon-slot-chip-${at(9).toIso8601String()}')),
        ),
      );
      await tester.pumpAndSettle();
      await _tapNextCta(tester); // m1 scheduled → pager advances to m2.

      // m2 is now current, still on its DATE (calendar) phase. Pick its date
      // too — as SETUP, outside the rebuild capture below — leaving only the
      // CTA press (DATE phase → TIME phase, `entry.viewingTime` flipping
      // false → true) as the isolated trigger under test: that flip is
      // exactly what the `PopScope` Consumer's `select` watches now (the
      // slot-pick path is already covered by the pre-existing probe above;
      // this one isolates the phase-flip path specifically).
      await tester.tapCalendarDay(today.day, within: slideOf('m2'));
      await tester.pumpAndSettle();
      expect(
        withinSlide('m2', find.byKey(const ValueKey<String>('date'))),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('salon-schedule-page-m1'), skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('salon-schedule-page-m2'), skipOffstage: false),
        findsOneWidget,
      );

      final List<String> rebuiltLines = <String>[];
      final DebugPrintCallback previousDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) rebuiltLines.add(message);
      };
      debugPrintRebuildDirtyWidgets = true;
      addTearDown(() {
        debugPrintRebuildDirtyWidgets = false;
        debugPrint = previousDebugPrint;
      });

      // The trigger: the CTA press that commits m2 into its TIME phase
      // flips its schedule entry's `viewingTime` from `false` to `true`,
      // which is exactly what the `PopScope` Consumer's `select` watches
      // (not `tester.pumpAndSettle()`/`_tapNextCta` — this needs the SAME
      // single-frame `tester.pump()` the pre-existing slot-pick probe uses).
      await tester.tap(find.byKey(const Key('schedule-confirm-cta')));
      // Exactly ONE frame — the frame the tap's Riverpod state change
      // schedules.
      await tester.pump();

      debugPrintRebuildDirtyWidgets = false;
      debugPrint = previousDebugPrint;

      final bool popScopeRebuilt = rebuiltLines.any(
        (String l) => l.contains('PopScope'),
      );
      final bool pageViewRebuilt = rebuiltLines.any(
        (String l) => l.contains('PageView'),
      );
      final bool m1SlideRebuilt = rebuiltLines.any(
        (String l) => l.contains('salon-schedule-page-m1'),
      );

      expect(
        popScopeRebuilt,
        isTrue,
        reason:
            "the PopScope-wrapping Consumer's own scoped `select` must "
            "rebuild PopScope when the ACTIVE slide's date phase flips — "
            'if this is false the proxy technique itself is broken (or the '
            'Consumer/select was removed), not proving isolation',
      );
      expect(
        pageViewRebuilt,
        isFalse,
        reason:
            'a date pick on the active slide must never reconstruct '
            '`PageView.builder` — a regression that moved the `canPop` '
            'watch back into the outer `build()` (reopening mobile-perf '
            'Finding A) would rebuild it here',
      );
      expect(
        m1SlideRebuilt,
        isFalse,
        reason:
            "master 1's already-completed, merely-kept-alive slide must "
            "never rebuild from a DATE pick on master 2's slide",
      );

      await tester.pumpAndSettle();
    },
  );

  // ===========================================================================
  // mobile-security gap-fix: the visible «Змінити» change-date button (and
  // its `_ChangeDateButton`) are GONE from the TIME phase — the ONLY way an
  // assistive-tech user (TalkBack's Local Context Menu / Switch Access) can
  // still reach the SAME phase-back action is the
  // `Semantics(container: true, onDismiss: _clearDate, hint: ...)` node this
  // fix added, and the top-bar arrow's semantic LABEL must correctly name
  // its OWN destination on each phase. Neither had any test coverage before
  // this gap-fix — flagged by mobile-security as a HIGH finding (an
  // unlabelled/untested `onDismiss` is a real accessibility regression, not
  // a theoretical one, once the only visible affordance is deleted).
  // ===========================================================================
  group('assistive-tech phase-back coverage (mobile-security gap-fix)', () {
    const args = SalonBookingTimeArgs(
      salonId: _kSalonId,
      selectedServiceIds: <String>['svc-1'],
      assignedServiceIdsByMaster: <String, List<String>>{
        'm1': <String>['svc-1'],
      },
    );

    testWidgets(
      "the time phase's Semantics(onDismiss:) action clears the active "
      "master's date exactly like the edge swipe / arrow / system back — "
      'and carries a non-empty hint naming the action, so TalkBack\'s Local '
      "Context Menu / Switch Access never surface an anonymous 'Dismiss'",
      (tester) async {
        final SemanticsHandle handle = tester.ensureSemantics();

        await _pumpTall(tester);
        final DateTime today = kyivToday(DateTime.now);
        final fake = _FakeSlotRepository(<BookingSlot>[
          BookingSlot(
            startAt: DateTime(today.year, today.month, today.day, 9),
            endAt: DateTime(today.year, today.month, today.day, 10, 30),
            available: true,
          ),
        ]);

        await tester.pumpRoutedApp(
          _router(args: args),
          overrides: _baseOverrides(
            slotRepository: fake,
            selectedServiceIds: const <String>['svc-1'],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tapCalendarDay(today.day);
        await tester.pumpAndSettle();
        // CTA («Далі») commits the date pick into the TIME phase.
        await _tapNextCta(tester);

        final Finder timePhaseNode = find.descendant(
          of: find.byKey(const Key('salon-schedule-page-m1')),
          matching: find.byKey(const ValueKey<String>('time')),
        );
        final SemanticsNode node = tester.getSemantics(timePhaseNode);
        final SemanticsData data = node.getSemanticsData();

        expect(
          data.hasAction(SemanticsAction.dismiss),
          isTrue,
          reason:
              'the time phase must expose ACTION_DISMISS so TalkBack\'s '
              'Local Context Menu / Switch Access can reach the phase-back '
              'action now that the inline «Змінити» button is gone',
        );
        final l10n = AppLocalizations.of(
          tester.element(find.byType(SalonTimeScreen)),
        );
        expect(
          data.hint,
          isNotEmpty,
          reason:
              'an unlabelled onDismiss action was the original finding — '
              'the hint must name the action, never present an anonymous '
              '"Dismiss"',
        );
        expect(
          data.hint,
          l10n.bookingChangeDateCta,
          reason:
              'the hint reuses the still-live bookingChangeDateCta copy '
              '("Змінити") — the same action name the deleted button used '
              'to carry',
        );

        final ProviderContainer container = ProviderScope.containerOf(
          tester.element(find.byType(SalonTimeScreen)),
        );
        expect(
          container.read(salonBookingScheduleProvider).entryFor('m1').date,
          isNotNull,
          reason: 'sanity: m1 must have a picked date before the dismiss',
        );

        // `node.owner` (not `tester.binding.rootPipelineOwner.semanticsOwner`
        // — a multi-view app may root several `PipelineOwner`s, and guessing
        // wrong silently no-ops the action instead of failing loudly) is the
        // ACTUAL `SemanticsOwner` this node is attached to; dispatching
        // through it is the same path `SemanticsController.performAction`
        // (the `tester.semantics.*` helpers) uses internally, and delivers
        // to the SAME place a real TalkBack/Switch-Access ACTION_DISMISS
        // would.
        node.owner!.performAction(node.id, SemanticsAction.dismiss);
        await tester.pumpAndSettle();

        expect(
          container.read(salonBookingScheduleProvider).entryFor('m1').date,
          isNull,
          reason:
              'invoking the onDismiss action must clear the active '
              "master's date exactly like the edge swipe / arrow / system "
              'back already do',
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('salon-schedule-page-m1')),
            matching: find.byKey(const ValueKey<String>('date')),
          ),
          findsOneWidget,
          reason: 'the slide must revert to the calendar/date phase',
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('salon-schedule-page-m1')),
            matching: find.byKey(const ValueKey<String>('time')),
          ),
          findsNothing,
        );

        handle.dispose();
      },
    );

    testWidgets("the top-bar back arrow's semantics label is phase-aware: the "
        'master-selection string on the DATE phase, and the calendar string '
        'once the active slide reaches the TIME phase — pins the exact '
        'defect this fix corrected (a stale label that lied about the '
        'destination once the arrow started returning to the calendar '
        'instead of exiting to master-selection)', (tester) async {
      await _pumpTall(tester);
      final DateTime today = kyivToday(DateTime.now);
      final fake = _FakeSlotRepository(<BookingSlot>[
        BookingSlot(
          startAt: DateTime(today.year, today.month, today.day, 9),
          endAt: DateTime(today.year, today.month, today.day, 10, 30),
          available: true,
        ),
      ]);

      await tester.pumpRoutedApp(
        _router(args: args),
        overrides: _baseOverrides(
          slotRepository: fake,
          selectedServiceIds: const <String>['svc-1'],
        ),
      );
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(
        tester.element(find.byType(SalonTimeScreen)),
      );
      expect(
        l10n.salonBookingTimeBackToCalendarSemantics,
        isNot(l10n.salonBookingTimeBackSemantics),
        reason:
            'sanity: the two labels must actually differ, or this test '
            'would pass even against a static (non-phase-aware) label',
      );

      // DATE phase (fresh mount): the arrow must announce the
      // master-selection destination — a real route pop, not a phase
      // revert.
      SemanticsData backData = tester
          .getSemantics(find.byKey(const Key('salon-time-back')))
          .getSemanticsData();
      expect(backData.label, l10n.salonBookingTimeBackSemantics);
      expect(backData.flagsCollection.isButton, isTrue);

      await tester.tapCalendarDay(today.day);
      await tester.pumpAndSettle();
      // CTA («Далі») commits the date pick into the TIME phase.
      await _tapNextCta(tester);

      // TIME phase: the SAME arrow must now announce the calendar
      // destination — a phase revert, not a route pop.
      backData = tester
          .getSemantics(find.byKey(const Key('salon-time-back')))
          .getSemanticsData();
      expect(backData.label, l10n.salonBookingTimeBackToCalendarSemantics);
      expect(backData.flagsCollection.isButton, isTrue);
    });
  });
}
