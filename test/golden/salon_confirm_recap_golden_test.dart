// Phase 341 D6 — Visual regression golden for the SALON wizard's `confirm`
// step (`SalonCreateBookingScreen`'s `_BookingStep.confirm`, built from the
// SHARED, promoted [ConfirmStep] — `salon_create_booking_screen.dart:481`).
//
// GAP THIS FILE CLOSES — no existing golden reached this rendering AT ALL.
// `salon_master_tile_golden_test.dart` drives `SalonCreateBookingScreen` only
// as far as the `masters` step (never picks a slot, never reaches
// `confirm`). `booking_slot_flow_golden_test.dart` looks adjacent by name but
// goldens an entirely different screen/widget tree — the CLIENT-facing
// `BookingConfirmScreen` (`booking_confirm_screen.dart`'s own private
// `_ConfirmBody`), which does NOT use [ConfirmStep]/[BookingRecap] at all
// (confirmed by grep: no `priceMax`/`selections:`/`BookingSelection(` hit in
// that file). So [ConfirmStep]'s MULTI-service path — [BookingRecap]'s
// «Разом» total via `formatBookingTotalsFromTerms`, reached through
// `BookingSummaryCards(selections: ...)` — had zero golden coverage from
// EITHER wizard before this file, staff or master. This file is therefore a
// NEW sibling, not an extension of `booking_slot_flow_golden_test.dart` —
// putting a different screen class into a file whose whole existing header
// enumerates 15 CLIENT-flow cells would misrepresent that file's own scope.
//
// TWO CELLS (phase 341 D6's own wording — "all-FIXED and mixed FIXED+RANGE
// shapes"), one screenshot per cell per matrix entry:
//   • `confirm-multi-fixed` — three services, all FIXED price
//     (500 + 400 + 300 ₴ / 60 + 45 + 30 хв) — [formatBookingTotalsFromTerms]
//     collapses a degenerate min==max band to a single "1200 ₴" figure
//     (`booking_price_labels.dart:79-82`).
//   • `confirm-multi-mixed` — two FIXED + one RANGE (300–600 ₴) — the SAME
//     three-service visit, but the RANGE term widens the total to an
//     en-dash band: "1200–1500 ₴" (500+400+300 .. 500+400+600).
//
// Both cells land on `confirm` via the SAME collapsed-single-master path
// (`_SalonCollapsedSlots` — roster length 1, the "collapse rule", D6's own
// scope is the confirm recap, not the masters-step picker already covered by
// `salon_master_tile_golden_test.dart`), so the drive never touches
// `_SalonMasterTile` at all.
//
// Fixture parity — the FIXED-only catalogue mirrors
// `salon_master_tile_golden_test.dart`'s PHASE 341 multi-service fixtures
// (`salon-svc-1`/`-2`/`-3`) exactly; deliberate duplication, not drift — see
// that file's own header for why each golden file owns private fixture
// mirrors rather than importing another test file's `_`-private consts.
//
// Clock: pinned to the SAME `_kNow` (Aug 10, 2026 Kyiv midday) as every
// sibling salon-wizard golden, for the same reason (the calendar's "today"
// cell must agree with the date advanced to).
//
// Matrix: 2 cells x {320, 360, 414} dp x {textScale 1.0, 1.3} = 12 PNGs.
//
// The file must still pass WITHOUT `--update-goldens`; a failure is a
// reportable visual delta, not a baseline to refresh.

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
// Fixtures
// ---------------------------------------------------------------------------

const String _kSalonId = 'salon-1';

/// Sole roster entry — the "one active master" collapse rule
/// (`salon_booking_wizard_steps.dart:493-507`) skips the tile picker
// entirely, landing straight on the slot grid; this file's own scope is
/// `confirm`, not the tile (covered by `salon_master_tile_golden_test.dart`).
const SalonMasterSummary _kMaster = SalonMasterSummary(
  masterId: 'master-a',
  firstName: 'Олена',
  lastName: 'Ковальчук',
  type: MasterType.salonMaster,
  reviewCount: 12,
  avgRating: 4.8,
);

const SalonCatalogService _kSvc1 = SalonCatalogService(
  id: 'salon-svc-1',
  name: 'Манікюр',
  durationLabel: '60 хв',
  priceDisplay: '500 ₴',
  durationMinutes: 60,
  priceType: ServicePriceType.fixed,
  priceMin: 500,
);
const SalonCatalogService _kSvc2 = SalonCatalogService(
  id: 'salon-svc-2',
  name: 'Педикюр',
  durationLabel: '45 хв',
  priceDisplay: '400 ₴',
  durationMinutes: 45,
  priceType: ServicePriceType.fixed,
  priceMin: 400,
);
const SalonCatalogService _kSvc3Fixed = SalonCatalogService(
  id: 'salon-svc-3',
  name: 'Покриття гель-лак',
  durationLabel: '30 хв',
  priceDisplay: '300 ₴',
  durationMinutes: 30,
  priceType: ServicePriceType.fixed,
  priceMin: 300,
);

/// The RANGE term for the mixed-shape cell — same id slot as [_kSvc3Fixed]
/// (`salon-svc-3`) so both catalogues select via the identical three
/// `mcb_service_card_salon-svc-*` keys; only the THIRD service's pricing
/// shape differs between the two cells.
const SalonCatalogService _kSvc3Range = SalonCatalogService(
  id: 'salon-svc-3',
  name: 'Нарощення вій',
  durationLabel: '1 год 30 хв',
  priceDisplay: '300–600 ₴',
  durationMinutes: 90,
  priceType: ServicePriceType.range,
  priceMin: 300,
  priceMax: 600,
);

const List<SalonServiceCategoryEntry> _kFixedCatalog =
    <SalonServiceCategoryEntry>[
      SalonServiceCategoryEntry(
        category: 'NAILS',
        displayName: 'Манікюр',
        count: 3,
        services: <SalonCatalogService>[_kSvc1, _kSvc2, _kSvc3Fixed],
      ),
    ];

const List<SalonServiceCategoryEntry> _kMixedCatalog =
    <SalonServiceCategoryEntry>[
      SalonServiceCategoryEntry(
        category: 'NAILS',
        displayName: 'Манікюр',
        count: 3,
        services: <SalonCatalogService>[_kSvc1, _kSvc2, _kSvc3Range],
      ),
    ];

/// The sole master covers every service in whichever catalogue is active —
/// assignment ids distinct from every `serviceDefId` (D3's id-space note).
Map<String, Map<String, String>> _coverageAll() =>
    <String, Map<String, String>>{
      _kMaster.masterId: <String, String>{
        'salon-svc-1': 'assignment-1',
        'salon-svc-2': 'assignment-2',
        'salon-svc-3': 'assignment-3',
      },
    };

// future-date-ok: fixed clock-override instant; the exact day is the
// fixture's identity, never now-relative.
final DateTime _kNow = DateTime.utc(2026, 8, 10, 9); // 12:00 Kyiv, Aug 10.
// future-date-ok: fixed twin of _kNow — the same clock-override day.
final DateTime _kSlotStart = DateTime.utc(2026, 8, 10, 10); // 13:00 Kyiv.
final BookingSlot _kSlot = BookingSlot(
  startAt: _kSlotStart,
  endAt: _kSlotStart.add(const Duration(minutes: 60)),
  available: true,
);

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeSlotRepository implements SlotRepository {
  // 2026-09-18 — `SalonDateStep`'s fan-out gate (own doc:
  // `salon_booking_wizard_steps.dart`) now genuinely calls this while this
  // suite drives through the dateTime step (`_driveToConfirm`, which
  // `tapCalendarDay(10)`s). Every date in the requested range resolves
  // `working: true` — this suite never exercises the grey-out gate itself
  // (that is `salon_create_booking_screen_test.dart`'s job), it only needs
  // Aug 10 to stay tappable, exactly as before this fetch existed.
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

  @override
  Future<List<BookingSlot>> getMasterSlots({
    required String masterId,
    required List<String> serviceIds,
    required DateTime date,
    CancelToken? cancelToken,
  }) async => <BookingSlot>[_kSlot];
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

List<Object> _overrides(List<SalonServiceCategoryEntry> catalog) => <Object>[
  salonStaffMastersRosterProvider.overrideWith(
    () =>
        FakeSalonStaffMastersRoster(() => const <SalonMasterSummary>[_kMaster]),
  ),
  salonMasterServiceCoverageProvider.overrideWith(
    () => FakeSalonMasterServiceCoverage(() => salonCoverageOf(_coverageAll())),
  ),
  salonServiceCatalogProvider.overrideWith(
    (ref, String salonId) async => catalog,
  ),
  slotRepositoryProvider.overrideWith((_) => _FakeSlotRepository()),
  bookingRepositoryProvider.overrideWith((_) => _FakeBookingRepository()),
  clockProvider.overrideWithValue(() => _kNow),
];

// ---------------------------------------------------------------------------
// Drive sequence — client → three services → date → sole master (collapsed)
// → pick the only slot → confirm.
// ---------------------------------------------------------------------------

Future<void> _driveToConfirm(WidgetTester tester) async {
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

  // Roster length 1 -> collapse rule -> straight to the slot grid, no tile.
  await tester.tap(
    find.byKey(
      Key('salon-collapsed-slot-chip-${_kSlotStart.toIso8601String()}'),
    ),
  );
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// Custom pumpWidget — mirrors `salon_master_tile_golden_test.dart`'s
// `_wizardPump` exactly (router + ProviderScope + MaterialApp + drive).
// ---------------------------------------------------------------------------

PumpWidget _confirmPump({
  required double width,
  required List<SalonServiceCategoryEntry> catalog,
}) {
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
        overrides: _overrides(catalog).cast(),
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

    await _driveToConfirm(tester);
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
        'salon_confirm_recap multi-fixed ${width.toInt()}dp text-${scale}x',
        fileName: 'salon_confirm_recap_multi_fixed_$suffix',
        constraints: BoxConstraints.tight(Size(width, kGoldenHeight)),
        textScaleFactor: scale,
        pumpWidget: _confirmPump(width: width, catalog: _kFixedCatalog),
        builder: () => const SalonCreateBookingScreen(salonId: _kSalonId),
      );

      goldenTest(
        'salon_confirm_recap multi-mixed ${width.toInt()}dp text-${scale}x',
        fileName: 'salon_confirm_recap_multi_mixed_$suffix',
        constraints: BoxConstraints.tight(Size(width, kGoldenHeight)),
        textScaleFactor: scale,
        pumpWidget: _confirmPump(width: width, catalog: _kMixedCatalog),
        builder: () => const SalonCreateBookingScreen(salonId: _kSalonId),
      );
    }
  }
}
