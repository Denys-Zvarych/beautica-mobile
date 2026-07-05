// Phase 14.16/14.17 — Widget tests for SalonTimeScreen (salon booking flow
// step 3, "Час").
//
// Covers the phase docs' acceptance criteria:
//   1. Slider shows exactly the masters assigned in step 2 (one slide each).
//   2. Dot-tap changes the active slide.
//   3. Selecting a date + a time slot for the (only) assigned master enables
//      the confirm bar and updates its scheduled-count.
//   4. "Підтвердити" navigates to the existing /booking/salon/coming-soon
//      placeholder with the correct salonId — and NEVER calls any
//      booking-creation repository method.
//
// Strategy: mounts the REAL production screen via a test-local GoRouter
// mirroring app_router.dart's shape, overriding [slotRepositoryProvider]
// with a hand-written fake so no real Dio request is ever made — mirrors
// `slot_picker_test.dart`'s established pattern for this feature.

import 'dart:async';

import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/slot_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking_slot.dart';
import 'package:beautica_mobile/features/booking/application/salon_master_coverage_notifier.dart';
import 'package:beautica_mobile/features/booking/domain/salon_booking_args.dart';
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
/// salonBookingComingSoon shape, capturing whatever `extra` reaches the
/// coming-soon stub so the "Підтвердити" hand-off can be asserted precisely.
GoRouter _router({
  required SalonBookingTimeArgs args,
  ValueChanged<String>? onReachedComingSoon,
}) => GoRouter(
  initialLocation: RouteNames.salonBookingTime,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.salonBookingTime,
      builder: (context, state) => SalonTimeScreen(args: args),
    ),
    GoRoute(
      path: RouteNames.salonBookingComingSoon,
      builder: (context, state) {
        onReachedComingSoon?.call(state.extra! as String);
        return const Scaffold(body: Text('coming-soon-reached'));
      },
    ),
  ],
);

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
}) => <Object>[
  publicSalonProfileProvider(
    _kSalonId,
  ).overrideWith((ref) => (_stubSalon, masters)),
  salonServiceCatalogProvider(_kSalonId).overrideWith((ref) => _stubCatalog),
  salonMasterServiceCoverageProvider(_kSalonId).overrideWith((ref) => coverage),
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
    'the confirm bar; confirming navigates to /booking/salon/coming-soon '
    'with the correct salonId and never touches a booking-creation repository',
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
      String? capturedSalonId;

      await tester.pumpRoutedApp(
        _router(
          args: args,
          onReachedComingSoon: (String id) => capturedSalonId = id,
        ),
        overrides: _baseOverrides(slotRepository: fake),
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

      // Pick the fetched 09:00 slot.
      final Finder slotChip = find.byKey(
        Key(
          'salon-slot-chip-${DateTime(today.year, today.month, today.day, 9).toIso8601String()}',
        ),
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

      expect(capturedSalonId, _kSalonId);
      expect(find.text('coming-soon-reached'), findsOneWidget);
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

      // Roster/catalog filtering resolved BOTH assigned service ids
      // (svc-1, svc-2) into their real `SalonCatalogService` entries — the
      // strip's services label lists both, not just the first assigned id.
      expect(find.textContaining('Манікюр з покриттям'), findsOneWidget);
      expect(find.textContaining('Стрижка'), findsOneWidget);

      // Summed duration across BOTH assigned services (90 + 60 = 150 min =
      // "2 год 30 хв"), not just svc-1's 90 minutes alone — proves
      // `summedDurationMinutes` folds the full assigned set. Rendered
      // TWICE at rest (the strip's duration pill AND the pinned
      // `ScheduleConfirmBar`'s "Разом" total), both independently sourced
      // from the same `summedDurationMinutes` getter.
      expect(find.textContaining('2 год 30 хв'), findsNWidgets(2));

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
              _kSalonId,
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
          overrides: _baseOverrides(slotRepository: fake),
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
              _kSalonId,
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
          overrides: _baseOverrides(slotRepository: fake),
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
        overrides: _baseOverrides(slotRepository: fake),
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
}
