// Phase 250 perf-fix — Visual regression golden for the SALON masters step,
// specifically `_SalonMasterTile` (private to `salon_booking_wizard_steps
// .dart`, so goldened only reachable through the public `SalonCreateBooking
// Screen` — mirrors why `master_create_booking_wizard_golden_test.dart`
// goldens the whole screen rather than the private step widgets it covers).
//
// AUTHORED BEFORE the perf fix lands (mobile-perf P1 finding on
// `salon_booking_wizard_steps.dart:599-616`): captured against the CURRENT,
// unmodified `Opacity(opacity: _offers ? 1.0 : 0.42, child: ...)` wrap. After
// the fix replaces the subtree `Opacity` with per-element alpha-multiplied
// colours, this file MUST pass unmodified and WITHOUT `--update-goldens` —
// that is the byte-identical proof the two renders are equivalent. If it does
// NOT pass, that is a reportable visual delta, not a baseline to refresh.
//
// One screenshot per (width, textScale) cell, single step: the masters list
// with TWO tiles visible —
//   • `master-a` — COVERS the chosen service (full-opacity face: avatar,
//     name, role, price/duration line, «Виконує» pill, chevron).
//   • `master-b` — does NOT cover it (dimmed face: avatar, name, role,
//     «Не виконує» pill, no price/duration line, no chevron, no border glow,
//     no shadow) — the exact subtree the audited `Opacity` wraps.
//
// Both tiles in ONE frame lets a reviewer diff the two faces side by side and
// checks the covering tile is untouched by the fix (it never enters the
// `Opacity`'s `0.42` branch, so it acts as a control).
//
// Fixtures mirror `salon_create_booking_screen_test.dart`'s `_kMasterA` /
// `_kMasterB` / `_kCatalogService` / `_kCatalog` / `_coverageAOnly()` exactly
// (fixture-parity is deliberate — any drift would be its own bug), plus a
// three-review rating on master A so `MasterRatingReadout` also renders in
// the covering (undimmed) tile for a fuller comparison.
//
// Clock: pinned to the same `_kNow` (Aug 10, 2026 Kyiv midday) as the sibling
// widget-test file, for the same reason — the calendar's "today" cell must
// agree with the date advanced to deterministically.
//
// Matrix: {320, 360, 414} dp x {textScale 1.0, 1.3} = 6 PNGs.

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
import 'package:beautica_mobile/features/booking/application/salon_masters_roster_notifier.dart';
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

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeSlotRepository implements SlotRepository {
  @override
  Future<List<WorkingDay>> getWorkingDays({
    required String masterId,
    required DateTime from,
    required DateTime to,
    List<String>? serviceIds,
    CancelToken? cancelToken,
  }) => throw UnimplementedError(
    'SalonDateStep never fetches working days — see its own doc.',
  );

  @override
  Future<List<BookingSlot>> getMasterSlots({
    required String masterId,
    required List<String> serviceIds,
    required DateTime date,
    CancelToken? cancelToken,
  }) async => const <BookingSlot>[];
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
  Future<Booking> getBookingById(String id) => throw UnimplementedError();

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
  Future<Booking> rescheduleBooking(String id, DateTime newStartAt) =>
      throw UnimplementedError();

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
  salonMastersRosterProvider.overrideWith(
    (ref, String salonId) async => const <SalonMasterSummary>[
      _kMasterA,
      _kMasterB,
    ],
  ),
  salonMasterServiceCoverageProvider.overrideWith(
    (ref, args) async => _coverageAOnly(),
  ),
  salonServiceCatalogProvider.overrideWith(
    (ref, String salonId) async => _kCatalog,
  ),
  slotRepositoryProvider.overrideWith((_) => _FakeSlotRepository()),
  bookingRepositoryProvider.overrideWith((_) => _FakeBookingRepository()),
  clockProvider.overrideWithValue(() => _kNow),
];

// ---------------------------------------------------------------------------
// Drive sequence — client → service → dateTime → masters (both tiles
// visible, neither expanded — the exact frame the `Opacity` wraps).
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

  await tester.tap(find.byKey(const Key('mcb_service_card_salon-svc-1')));
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
    }
  }
}
