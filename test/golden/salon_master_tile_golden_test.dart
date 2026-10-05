// Phase 250 perf-fix — Visual regression golden for the SALON masters step,
// specifically `_SalonMasterTile` (private to `salon_booking_wizard_steps
// .dart`, so goldened only reachable through the public `SalonCreateBooking
// Screen` — mirrors why `master_create_booking_wizard_golden_test.dart`
// goldens the whole screen rather than the private step widgets it covers).
//
// AUTHORED BEFORE the perf fix lands (mobile-perf P1 finding on
// `salon_booking_wizard_steps.dart:599-616`), against the then-current
// `Opacity(opacity: _offers ? 1.0 : 0.42, child: ...)` wrap.
//
// ── WHAT THIS FILE PROVED, AND WHAT IT DID NOT ────────────────────────────
//
// The original header claimed these baselines were "byte-identical proof the
// two renders are equivalent" across the Opacity -> per-element-alpha
// refactor. That claim was FALSE and is retracted (corrected 2026-08-31).
//
// This suite runs alchemist in CI-golden mode only (`obscureText: true`,
// `test/flutter_test_config.dart:193-204`), which captures through
// `BlockedTextPaintingContext.paintSingleChild`
// (`alchemist-0.14.0/lib/src/blocked_text_image.dart:47`) — a re-entrant
// paint into the render object's already-populated `debugLayer`, reusing the
// live `OpacityLayer`. A composited opacity does NOT survive it: measured
// 2026-08-31, a baseline generated at `Opacity(0.30)` compares GREEN against
// the same widget at `1.0`, for both `Opacity` and `AnimatedOpacity`.
//
// So the PRE-refactor baselines never contained the 0.42 dim at all. Half of
// the equivalence was unobservable when it was asserted.
//
// What these baselines DO gate is real and worth keeping: geometry, layout,
// copy, and PER-ELEMENT alpha — the post-refactor form. That half is load-
// bearing and mutation-proven: driving `_kNonOfferingDim` 0.42 -> 1.0 turns
// this file 6/6 RED.
//
// The file must still pass WITHOUT `--update-goldens`; a failure is a
// reportable visual delta, not a baseline to refresh.
//
// Tier contract: `docs/mobile-phases/phase-299-golden-tier-layer-opacity-
// contract.md`.
//
// One screenshot per (width, textScale) cell, single step: the masters list
// with ONE tile visible —
//   • `master-a` — COVERS the chosen service AND has a free slot
//     (full-opacity face: avatar, name, role, price/duration line, NO
//     pill, chevron).
//
// 2026-09-18 real-device fix — this scenario used to also render `master-b`
// (does NOT cover the service, dimmed) beside `master-a`, and the "Both
// tiles in ONE frame" comparison below was written against that pairing.
// Non-covering masters are HIDDEN outright now (see this file's header and
// `salon_booking_wizard_steps.dart`'s), so `master-b` — absent from
// `_coverageAOnly()` — no longer renders at all here; this scenario
// necessarily shrank to the one tile that's left. The «Виконує» pill is
// also gone — master A's no-pill face is the visible delta these 6 PNGs
// gate now. The two-face side-by-side comparison this scenario used to
// provide moved to the multi-service scenario below, which pins a covering
// tile against a covering-but-slotless one instead of a covering tile
// against a hidden one.
//
// Fixtures mirror `salon_create_booking_screen_test.dart`'s `_kMasterA` /
// `_kMasterB` / `_kCatalogService` / `_kCatalog` / `_coverageAOnly()` exactly
// (fixture-parity is deliberate — any drift would be its own bug), plus a
// three-review rating on master A so `MasterRatingReadout` also renders.
//
// Clock: pinned to the same `_kNow` (Aug 10, 2026 Kyiv midday) as the sibling
// widget-test file, for the same reason — the calendar's "today" cell must
// agree with the date advanced to deterministically.
//
// Matrix: {320, 360, 414} dp x {textScale 1.0, 1.3} = 6 PNGs.
//
// PHASE 341 D6 (2026-09-18) — second scenario, 6 more PNGs
// (`salon_master_tile_multi_masters_*`), proportional to the original run
// above rather than forked into a new file: THREE services picked, master A
// covering all three AND having a free slot (no price/duration line —
// `widget.services.length == 1` is false; no pill), master B ALSO covering
// all three but with NO free slot — disabled, «Немає вільного часу» (see
// this scenario's own fixtures section above for the 2026-09-18 rewrite —
// this used to be a 2-of-3 partial-coverage/dimmed pairing, phase 335 D2 /
// phase 341 D3, before non-covering masters were hidden outright). The
// original 6 `salon_master_tile_masters_*` baselines are NOT untouched
// this round — see the scenario-1 header above for what changed there too.

import 'package:alchemist/alchemist.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/features/booking/application/salon_master_coverage_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_staff_masters_roster.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/data/slot_repository.dart';
import 'package:beautica_mobile/features/booking/domain/appointment.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_partition.dart';
import 'package:beautica_mobile/features/booking/domain/booking_slot.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/create_booking_request.dart';
import 'package:beautica_mobile/features/booking/domain/create_master_booking_request.dart';
import 'package:beautica_mobile/features/booking/domain/working_day.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_create_booking_screen.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/salon/application/salon_service_catalog_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon_master_summary.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';

import '../helpers/fake_salon_master_coverage.dart';
import '../helpers/fake_salon_staff_masters_roster.dart';
import '../helpers/pump_app.dart' show TapCalendarDay;
import 'helpers/golden_pump.dart';

// ---------------------------------------------------------------------------
// Fixtures — mirror `salon_create_booking_screen_test.dart`'s.
// ---------------------------------------------------------------------------

const String _kSalonId = 'salon-1';

const SalonMasterSummary _kMasterA = SalonMasterSummary(
  masterId: 'master-a',
  firstName: 'Олена',
  lastName: 'Ковальчук',
  type: MasterType.salonMaster,
  reviewCount: 12,
  avgRating: 4.8,
);

const SalonMasterSummary _kMasterB = SalonMasterSummary(
  masterId: 'master-b',
  firstName: 'Ірина',
  lastName: 'Бондар',
  type: MasterType.salonMaster,
  reviewCount: 0,
);

const SalonCatalogService _kCatalogService = SalonCatalogService(
  id: 'salon-svc-1',
  name: 'Манікюр',
  durationLabel: '60 хв',
  priceDisplay: '500 ₴',
  durationMinutes: 60,
  priceType: ServicePriceType.fixed,
  priceMin: 500,
);

const List<SalonServiceCategoryEntry> _kCatalog = <SalonServiceCategoryEntry>[
  SalonServiceCategoryEntry(
    category: 'NAILS',
    displayName: 'Манікюр',
    count: 1,
    services: <SalonCatalogService>[_kCatalogService],
  ),
];

/// Master A covers the catalogue service (assignment id `assignment-a`);
/// master B is absent from the map entirely — mirrors
/// `salonMasterServiceCoverageProvider`'s real "absent == not covered"
/// contract, same as the sibling widget-test file.
Map<String, Map<String, String>> _coverageAOnly() =>
    <String, Map<String, String>>{
      _kMasterA.masterId: <String, String>{_kCatalogService.id: 'assignment-a'},
    };

// future-date-ok: fixed clock-override instant; the exact day is the
// fixture's identity, never now-relative.
final DateTime _kNow = DateTime.utc(2026, 8, 10, 9); // 12:00 Kyiv, Aug 10.

// future-date-ok: fixed twin of _kNow — the same clock-override day, see
// above. Master A's own free slot — see `_FakeSlotRepository` below.
final DateTime _kSlotStart = DateTime.utc(2026, 8, 10, 10); // 13:00 Kyiv.
final BookingSlot _kGoldenSlot = BookingSlot(
  startAt: _kSlotStart,
  endAt: _kSlotStart.add(const Duration(minutes: 60)),
  available: true,
);

// ---------------------------------------------------------------------------
// PHASE 341 D6 — multi-service (3-picked) fixtures for the SECOND scenario
// below.
//
// 2026-09-18 real-device fix — REWRITTEN premise. This scenario used to pin
// master B covering TWO of three selected services (D3's "every, not any"
// discriminating case) — dimmed, per the old non-covering face. That face no
// longer exists: a master who fails the "every" rule is HIDDEN outright now
// (see the file-level header), so a 2-of-3 miss would render NOTHING to
// golden, not a dimmed tile. This scenario is repurposed instead to pin the
// state that inherited the dim treatment: master B COVERS all three
// services (same as master A — see `_coverageBothFull` below) but has NO
// FREE TIME on the picked day (`_FakeSlotRepository` returns `[]` for
// master B specifically), rendering disabled with «Немає вільного часу».
// This still gives a reviewer two faces to diff side by side — a bookable
// covering tile (master A, no pill) against a covering-but-slotless one
// (master B, disabled) — same comparative value the old premise had, just
// keyed on free time instead of coverage.
//
// Fixtures mirror `salon_create_booking_screen_test.dart`'s `_kMultiCatalog`
// (PHASE 253) exactly. Master A covers all three (full face, no price
// line — `widget.services.length == 1` is false with 3 selected); master B
// also covers all three now, but is disabled for lack of free time.
// ---------------------------------------------------------------------------

const SalonCatalogService _kCatalogService2 = SalonCatalogService(
  id: 'salon-svc-2',
  name: 'Педикюр',
  durationLabel: '45 хв',
  priceDisplay: '400 ₴',
  durationMinutes: 45,
  priceType: ServicePriceType.fixed,
  priceMin: 400,
);

const SalonCatalogService _kCatalogService3 = SalonCatalogService(
  id: 'salon-svc-3',
  name: 'Покриття гель-лак',
  durationLabel: '30 хв',
  priceDisplay: '300 ₴',
  durationMinutes: 30,
  priceType: ServicePriceType.fixed,
  priceMin: 300,
);

const List<SalonServiceCategoryEntry> _kMultiCatalog =
    <SalonServiceCategoryEntry>[
      SalonServiceCategoryEntry(
        category: 'NAILS',
        displayName: 'Манікюр',
        count: 3,
        services: <SalonCatalogService>[
          _kCatalogService,
          _kCatalogService2,
          _kCatalogService3,
        ],
      ),
    ];

/// Both masters cover ALL three selected services (assignment ids distinct
/// from every `serviceDefId`, per D3's id-space note) — 2026-09-18: master B
/// used to cover only two of three here (the "every" rule's discriminating
/// case); it is now fully covering too, and disabled instead via
/// `_FakeSlotRepository` returning `[]` for its masterId — see this
/// section's header.
Map<String, Map<String, String>> _coverageBothFull() =>
    <String, Map<String, String>>{
      _kMasterA.masterId: <String, String>{
        _kCatalogService.id: 'assignment-a-1',
        _kCatalogService2.id: 'assignment-a-2',
        _kCatalogService3.id: 'assignment-a-3',
      },
      _kMasterB.masterId: <String, String>{
        _kCatalogService.id: 'assignment-b-1',
        _kCatalogService2.id: 'assignment-b-2',
        _kCatalogService3.id: 'assignment-b-3',
      },
    };

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeSlotRepository implements SlotRepository {
  // 2026-09-18 — `SalonDateStep`'s fan-out gate (own doc:
  // `salon_booking_wizard_steps.dart`) now genuinely calls this while this
  // suite drives through the dateTime step (`_driveToMasters`/
  // `_driveToMastersMulti`, both `tapCalendarDay(10)`). Every date in the
  // requested range resolves `working: true` — this suite never exercises
  // the grey-out gate itself (that is `salon_create_booking_screen_test
  // .dart`'s job), it only needs Aug 10 to stay tappable, exactly as before
  // this fetch existed.
  @override
  Future<List<WorkingDay>> getWorkingDays({
    required String masterId,
    required DateTime from,
    required DateTime to,
    List<String>? serviceIds,
    CancelToken? cancelToken,
  }) async => <WorkingDay>[
    for (DateTime d = from; !d.isAfter(to); d = d.add(const Duration(days: 1)))
      WorkingDay(date: d, working: true),
  ];

  // 2026-09-18 real-device fix — `_SalonMasterTile` now watches this
  // eagerly for every rendered (covering) tile, to know up front whether it
  // has free time. Master A always gets [_kGoldenSlot] (the bookable,
  // no-pill face); every other master — master B in the multi-service
  // scenario, the only OTHER master either scenario ever renders — gets
  // `[]` (the disabled, «Немає вільного часу» face).
  @override
  Future<List<BookingSlot>> getMasterSlots({
    required String masterId,
    required List<String> serviceIds,
    required DateTime date,
    CancelToken? cancelToken,
  }) async => masterId == _kMasterA.masterId
      ? <BookingSlot>[_kGoldenSlot]
      : const <BookingSlot>[];
}

class _FakeBookingRepository implements BookingRepository {
  @override
  Future<Appointment> createMasterBooking(
    String masterId,
    CreateMasterBookingRequest request,
  ) => throw UnimplementedError();

  @override
  Future<Booking> createBooking(CreateBookingRequest req) =>
      throw UnimplementedError();

  @override
  Future<List<DateTime>> getMyBookedDays({
    required DateTime from,
    required DateTime to,
    CancelToken? cancelToken,
  }) => throw UnimplementedError();

  @override
  Future<List<DateTime>> getSalonBookedDays({
    required String salonId,
    required DateTime from,
    required DateTime to,
    CancelToken? cancelToken,
  }) => throw UnimplementedError();

  @override
  Future<Booking> getBookingById(String id) => throw UnimplementedError();

  /// Phase 21.12 — the salon-wide board's endpoint. Unused by this fake's
  /// screen; present only because [BookingRepository] gained the method.
  @override
  Future<PageResponse<Booking>> getSalonBookings({
    required String salonId,
    DateTime? from,
    DateTime? to,
    String? masterId,
    Iterable<BookingStatus>? statuses,
    BookingPartition? partition,
    required int page,
    int size = kBookingsPageSize,
    BookingSort? sort,
    CancelToken? cancelToken,
  }) => throw UnimplementedError();

  @override
  Future<PageResponse<Booking>> getMyBookings({
    required Iterable<BookingStatus> statuses,
    BookingSort? sort,
    required int page,
    int size = kBookingsPageSize,
    Iterable<String>? serviceIds,
    DateTime? from,
    DateTime? to,
    BookingPartition? partition,
    CancelToken? cancelToken,
  }) => throw UnimplementedError();

  @override
  Future<void> cancelBooking(String id, {String? reason}) =>
      throw UnimplementedError();

  @override
  Future<void> declineBooking(String id, {String? comment}) =>
      throw UnimplementedError();

  @override
  Future<void> completeBooking(String id) => throw UnimplementedError();

  @override
  Future<Booking> rescheduleBooking(
    String id,
    DateTime newStartAt, {
    bool allowClientOverlap = false,
  }) => throw UnimplementedError();

  @override
  Future<void> createReview({
    required String bookingId,
    required int rating,
    String? comment,
  }) => throw UnimplementedError();
}

// ---------------------------------------------------------------------------
// Overrides
// ---------------------------------------------------------------------------

List<Object> _overrides() => <Object>[
  salonStaffMastersRosterProvider.overrideWith(
    () => FakeSalonStaffMastersRoster(
      () => const <SalonMasterSummary>[_kMasterA, _kMasterB],
    ),
  ),
  salonMasterServiceCoverageProvider.overrideWith(
    () =>
        FakeSalonMasterServiceCoverage(() => salonCoverageOf(_coverageAOnly())),
  ),
  salonServiceCatalogProvider.overrideWith(
    (ref, String salonId) async => _kCatalog,
  ),
  slotRepositoryProvider.overrideWith((_) => _FakeSlotRepository()),
  bookingRepositoryProvider.overrideWith((_) => _FakeBookingRepository()),
  clockProvider.overrideWithValue(() => _kNow),
];

/// PHASE 341 D6 — same shape as [_overrides], multi-service catalogue +
/// both-covering map (see the fixtures' own doc above).
List<Object> _overridesMulti() => <Object>[
  salonStaffMastersRosterProvider.overrideWith(
    () => FakeSalonStaffMastersRoster(
      () => const <SalonMasterSummary>[_kMasterA, _kMasterB],
    ),
  ),
  salonMasterServiceCoverageProvider.overrideWith(
    () => FakeSalonMasterServiceCoverage(
      () => salonCoverageOf(_coverageBothFull()),
    ),
  ),
  salonServiceCatalogProvider.overrideWith(
    (ref, String salonId) async => _kMultiCatalog,
  ),
  slotRepositoryProvider.overrideWith((_) => _FakeSlotRepository()),
  bookingRepositoryProvider.overrideWith((_) => _FakeBookingRepository()),
  clockProvider.overrideWithValue(() => _kNow),
];

// ---------------------------------------------------------------------------
// Drive sequence — client → service → dateTime → masters (every rendered
// tile visible, neither expanded — the exact frame the `Opacity` wrapped,
// back when a non-covering tile was dimmed rather than hidden).
// ---------------------------------------------------------------------------

Future<void> _driveToMasters(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('master-create-booking-first-name')),
    'Марина',
  );
  await tester.enterText(
    find.byKey(const Key('master-create-booking-last-name')),
    'Кравчук',
  );
  await tester.enterText(
    find.byKey(const Key('master-create-booking-phone')),
    '0501234567',
  );
  await tester.pump();
  await tester.tap(find.byKey(const Key('master-create-booking-client-next')));
  await tester.pumpAndSettle();

  // PHASE 253 — `service` is multi-select, SELECT ONLY: the card tap merely
  // marks the service, and the pinned `BookingSummaryBar` CTA is what
  // advances the wizard. Same two-tap sequence as
  // `salon_create_booking_screen_test.dart`'s `_pickService`; without the CTA
  // tap this drive stays parked on the service step and the date step's
  // calendar never mounts, so `tapCalendarDay` throws `Bad state: No element`.
  await tester.tap(find.byKey(const Key('mcb_service_card_salon-svc-1')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('booking-summary-cta')));
  await tester.pumpAndSettle();

  await tester.tapCalendarDay(10);
  await tester.pump();
  await tester.tap(find.byKey(const Key('salon-create-booking-date-next')));
  await tester.pumpAndSettle();
}

/// PHASE 341 D6 — same drive as [_driveToMasters], but marks THREE services
/// (select-only, per PHASE 253's multi-select — no per-card advance) before
/// hitting the pinned [BookingSummaryBar] CTA.
Future<void> _driveToMastersMulti(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('master-create-booking-first-name')),
    'Марина',
  );
  await tester.enterText(
    find.byKey(const Key('master-create-booking-last-name')),
    'Кравчук',
  );
  await tester.enterText(
    find.byKey(const Key('master-create-booking-phone')),
    '0501234567',
  );
  await tester.pump();
  await tester.tap(find.byKey(const Key('master-create-booking-client-next')));
  await tester.pumpAndSettle();

  for (final String id in <String>[
    'salon-svc-1',
    'salon-svc-2',
    'salon-svc-3',
  ]) {
    await tester.tap(find.byKey(Key('mcb_service_card_$id')));
    await tester.pump();
  }
  await tester.tap(find.byKey(const Key('booking-summary-cta')));
  await tester.pumpAndSettle();

  await tester.tapCalendarDay(10);
  await tester.pump();
  await tester.tap(find.byKey(const Key('salon-create-booking-date-next')));
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// Custom pumpWidget — MaterialApp.router (SalonCreateBookingScreen resolves
// GoRouter eagerly via its header back-chevron) + drive sequence, run with
// the SAME tester before alchemist captures. Mirrors
// `master_create_booking_wizard_golden_test.dart`'s `_wizardPump`.
// ---------------------------------------------------------------------------

PumpWidget _wizardPump({required double width}) {
  return (WidgetTester tester, Widget alchemistWidget) async {
    tester.view.physicalSize = Size(width, kGoldenHeight);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final GoRouter router = GoRouter(
      initialLocation: RouteNames.salonStaffBookingNew,
      routes: <RouteBase>[
        GoRoute(
          path: RouteNames.salonStaffBookingNew,
          builder: (BuildContext context, GoRouterState state) =>
              alchemistWidget,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        retry: beauticaProviderRetry,
        // ignore: avoid_dynamic_calls
        overrides: _overrides().cast(),
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('uk'),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _driveToMasters(tester);
    await tester.pumpAndSettle();
  };
}

/// PHASE 341 D6 — [_wizardPump] with [_overridesMulti] + [_driveToMastersMulti]
/// swapped in; otherwise byte-for-byte the same scaffolding (router, l10n,
/// viewport handling).
PumpWidget _wizardPumpMulti({required double width}) {
  return (WidgetTester tester, Widget alchemistWidget) async {
    tester.view.physicalSize = Size(width, kGoldenHeight);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final GoRouter router = GoRouter(
      initialLocation: RouteNames.salonStaffBookingNew,
      routes: <RouteBase>[
        GoRoute(
          path: RouteNames.salonStaffBookingNew,
          builder: (BuildContext context, GoRouterState state) =>
              alchemistWidget,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        retry: beauticaProviderRetry,
        // ignore: avoid_dynamic_calls
        overrides: _overridesMulti().cast(),
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('uk'),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _driveToMastersMulti(tester);
    await tester.pumpAndSettle();
  };
}

// ---------------------------------------------------------------------------
// Goldens
// ---------------------------------------------------------------------------

void main() {
  for (final width in kGoldenWidths) {
    for (final scale in kGoldenTextScales) {
      final suffix = widthScaleSuffix(width, scale);

      goldenTest(
        'salon_master_tile masters ${width.toInt()}dp text-${scale}x',
        fileName: 'salon_master_tile_masters_$suffix',
        constraints: BoxConstraints.tight(Size(width, kGoldenHeight)),
        textScaleFactor: scale,
        pumpWidget: _wizardPump(width: width),
        builder: () => const SalonCreateBookingScreen(salonId: _kSalonId),
      );

      // PHASE 341 D6 — multi-service (3-picked) world: master A covers all
      // three AND has a free slot (full face, no price line — 341's own
      // layout delta, no pill). Master B ALSO covers all three but has no
      // free slot — disabled, «Немає вільного часу» (2026-09-18: used to
      // be a 2-of-3 partial-coverage/dimmed case, D3 — see the fixtures'
      // own doc above for the rewrite).
      goldenTest(
        'salon_master_tile multi-service masters ${width.toInt()}dp '
        'text-${scale}x',
        fileName: 'salon_master_tile_multi_masters_$suffix',
        constraints: BoxConstraints.tight(Size(width, kGoldenHeight)),
        textScaleFactor: scale,
        pumpWidget: _wizardPumpMulti(width: width),
        builder: () => const SalonCreateBookingScreen(salonId: _kSalonId),
      );
    }
  }
}
