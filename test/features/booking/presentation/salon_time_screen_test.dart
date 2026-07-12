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
//   5. The compact inline «Змінити» change-date button (key
//      `salon-schedule-change-date`, Phase 14.18 — replaced the removed
//      `_DayHeaderChip`/`_WindowLine`) is present in the time phase.
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
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
  priceDisplay: '500 грн',
  durationMinutes: 90,
  priceType: ServicePriceType.fixed,
  priceMin: 500,
);
const _svc2 = SalonCatalogService(
  id: 'svc-2',
  name: 'Стрижка',
  durationLabel: '1 год',
  priceDisplay: '450 грн',
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
  _FakeSlotRepository(this.slotsToReturn);

  final List<BookingSlot> slotsToReturn;
  int getMasterSlotsCallCount = 0;

  /// The `serviceId` the MOST RECENT `getMasterSlots` call carried — lets a
  /// test assert the primary-service convention (`SalonMasterSchedule.
  /// primaryService`, the FIRST assigned service) actually keys the slot
  /// query when a master has 2+ assigned services, instead of only
  /// asserting the call happened at all.
  String? lastServiceId;

  @override
  Future<List<BookingSlot>> getMasterSlots({
    required String masterId,
    required String serviceId,
    required DateTime date,
    CancelToken? cancelToken,
  }) async {
    getMasterSlotsCallCount++;
    lastServiceId = serviceId;
    return slotsToReturn;
  }

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
    required String serviceId,
    required DateTime date,
    CancelToken? cancelToken,
  }) async => slotsByMaster[masterId] ?? const <BookingSlot>[];

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
    required String serviceId,
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
    required String serviceId,
    required DateTime date,
    CancelToken? cancelToken,
  }) async => throw Exception('boom');

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
// resolves `SalonMasterSchedule.primaryServiceAssignmentId` (the master's
// OWN service-ASSIGNMENT id, distinct from the salon-wide CATALOG id
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
      final DateTime today = DateTime.now();
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
      await tester.tap(todayCell);
      await tester.pumpAndSettle();

      expect(fake.getMasterSlotsCallCount, greaterThan(0));

      // Phase 14.18 — the removed `_DayHeaderChip`/`_WindowLine`'s only
      // still-needed affordance now lives as this compact inline change-date
      // button beside the "Вільний час" heading; it must render in the time
      // phase.
      expect(
        find.byKey(const Key('salon-schedule-change-date')),
        findsOneWidget,
      );

      // Pick the fetched 09:00 slot.
      final Finder slotChip = find.byKey(
        Key('salon-slot-chip-${slotStart.toIso8601String()}'),
      );
      expect(slotChip, findsOneWidget);
      await tester.tap(slotChip);
      await tester.pumpAndSettle();

      // Every assigned master (just m1) is now scheduled — CTA enables.
      cta = tester.widget<NeumorphicButton>(
        find.byKey(const Key('schedule-confirm-cta')),
      );
      expect(cta.onPressed, isNotNull);

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
      final DateTime today = DateTime.now();
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
      Finder withinSlide(String masterId, Finder matching) => find.descendant(
        of: find.byKey(
          Key('salon-schedule-page-$masterId'),
          skipOffstage: false,
        ),
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

      // Complete m1 first (date, then its 09:00 slot) — fully settled so
      // the slider's auto-advance to m2 lands before the capture below.
      await tester.tap(
        withinSlide('m1', find.byKey(Key('booking-calendar-day-${today.day}'))),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        withinSlide(
          'm1',
          find.byKey(Key('salon-slot-chip-${at(9).toIso8601String()}')),
        ),
      );
      await tester.pumpAndSettle();

      // The slider auto-advanced to m2; m1 is current ± 1 from m2, so
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

      // Pick m2's date so its slot chips are on-screen.
      await tester.tap(
        withinSlide('m2', find.byKey(Key('booking-calendar-day-${today.day}'))),
      );
      await tester.pumpAndSettle();

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
  // assigns exactly ONE service per master, so `_buildSchedule`'s
  // multi-service resolution (roster/catalog id lookup for
  // `assignedServiceIdsByMaster`, verified safe by mobile-security but never
  // asserted CORRECT by any test) and the primary-service slot-query
  // convention (`SalonMasterSchedule.primaryService` — the FIRST assigned
  // service, per the locked Phase 14.17 architecture decision) were both
  // completely unexercised. A regression that queried slots by the LAST
  // assigned service instead of the first, or that silently dropped a
  // second assigned service from the strip/window math, would have passed
  // every existing test in this file.
  testWidgets(
    'a master with 2 assigned services resolves BOTH from the real catalog '
    '(strip + summed window), and the slot query keys on the FIRST '
    '(primary) assigned service, never the second',
    (tester) async {
      await _pumpTall(tester);
      const args = SalonBookingTimeArgs(
        salonId: _kSalonId,
        selectedServiceIds: <String>['svc-1', 'svc-2'],
        assignedServiceIdsByMaster: <String, List<String>>{
          'm1': <String>['svc-1', 'svc-2'],
        },
      );
      final DateTime today = DateTime.now();
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

      // Pick today's date so the time phase's slot query fires.
      final Finder todayCell = find.byKey(
        Key('booking-calendar-day-${today.day}'),
      );
      expect(todayCell, findsOneWidget);
      await tester.tap(todayCell);
      await tester.pumpAndSettle();

      expect(
        fake.getMasterSlotsCallCount,
        greaterThan(0),
        reason: 'picking the date must fetch this master\'s slots',
      );
      expect(
        fake.lastServiceId,
        'svc-1',
        reason:
            'SlotRepository.getMasterSlots must be keyed on the FIRST '
            '(primary) assigned service — svc-1 — per the locked Phase '
            '14.17 architecture decision. A regression that queried by '
            'svc-2 (the second/non-primary assigned service) instead would '
            'silently show availability for the wrong service.',
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
      final DateTime today = DateTime.now();
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
      await tester.tap(todayCell);
      await tester.pumpAndSettle();

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
        final DateTime today = DateTime.now();

        await tester.pumpRoutedApp(
          _router(args: args),
          overrides: _baseOverrides(
            slotRepository: fake,
            selectedServiceIds: const <String>['svc-1'],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(Key('booking-calendar-day-${today.day}')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('salon-schedule-no-slots-empty-state')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('booking-month-calendar')), findsNothing);

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
      final DateTime today = DateTime.now();

      await tester.pumpRoutedApp(
        _router(args: args),
        overrides: _baseOverrides(
          slotRepository: fake,
          selectedServiceIds: const <String>['svc-1'],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(Key('booking-calendar-day-${today.day}')));
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(
        tester.element(find.byType(SalonTimeScreen)),
      );
      expect(find.text(l10n.bookingDayUnavailableState), findsOneWidget);
      expect(
        find.byKey(const Key('salon-schedule-no-slots-empty-state')),
        findsNothing,
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

      final DateTime today = DateTime.now();
      await tester.tap(find.byKey(Key('booking-calendar-day-${today.day}')));
      await tester.pumpAndSettle();

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

    Finder withinSlide(String masterId, Finder matching) => find.descendant(
      of: find.byKey(Key('salon-schedule-page-$masterId'), skipOffstage: false),
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
      final DateTime today = DateTime.now();
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

      await tester.tap(
        withinSlide('m1', find.byKey(Key('booking-calendar-day-${today.day}'))),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        withinSlide(
          'm1',
          find.byKey(Key('salon-slot-chip-${at(9).toIso8601String()}')),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        withinSlide('m2', find.byKey(Key('booking-calendar-day-${today.day}'))),
      );
      await tester.pumpAndSettle();

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
      final DateTime today = DateTime.now();
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

      Finder withinSlide(String masterId, Finder matching) => find.descendant(
        of: find.byKey(
          Key('salon-schedule-page-$masterId'),
          skipOffstage: false,
        ),
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

      // Complete m1 (date + slot) so the slider auto-advances onto m2,
      // landing it current ± 1 from m1 (Finding B's retention bound keeps
      // m1's slide mounted — required for the "m1 never rebuilds"
      // assertion below to be non-vacuous).
      await tester.tap(
        withinSlide('m1', find.byKey(Key('booking-calendar-day-${today.day}'))),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        withinSlide(
          'm1',
          find.byKey(Key('salon-slot-chip-${at(9).toIso8601String()}')),
        ),
      );
      await tester.pumpAndSettle();

      // m2 is now current, still on its DATE (calendar) phase — the trigger
      // below picks its date, NOT a slot (the slot-pick path is already
      // covered by the pre-existing probe above; this one isolates the
      // DATE-pick path specifically, since that's what flips
      // `PopScope.canPop`).
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

      // The trigger: picking m2's DATE flips its schedule entry from
      // date==null to non-null, which is exactly what the `PopScope`
      // Consumer's `select` watches.
      await tester.tap(
        withinSlide('m2', find.byKey(Key('booking-calendar-day-${today.day}'))),
      );
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
}
