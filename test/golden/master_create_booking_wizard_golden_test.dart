// Phase 249 — Visual regression golden for MasterCreateBookingScreen.
//
// AUTHORED BEFORE THE PROMOTION REFACTOR LANDS (per the phase brief): this
// file and its baseline PNGs are captured against the CURRENT, unmodified
// `_StepIndicator` / `_ClientStep` / `_ServiceStep` / `_ServiceStepEmpty` /
// `_DateTimeStep` / `_ConfirmStep` widgets, private to
// `master_create_booking_screen.dart`. After the promotion moves them
// (dropping the leading underscore) into
// `presentation/widgets/booking_wizard_steps.dart`, this test MUST pass
// unmodified and WITHOUT `--update-goldens` — that is the byte-identical
// proof the refactor is required to satisfy. No golden covered this screen
// before this file.
//
// FIVE steps goldened, one screenshot per step per matrix cell — driven by
// real user interaction through the SAME fakes `master_create_booking_
// screen_test.dart` already uses (fixture parity is deliberate: any drift
// between the two would be its own bug):
//   • `client`   — the freshly-opened form, all three fields empty.
//   • `service`  — after filling + advancing past `client`; the one-service
//                  picker (via the Phase 247 part-1 promoted category/card
//                  widgets).
//   • `dateTime` — after selecting the service and pressing the pinned «Далі»
//                  footer; the embedded `MasterSchedulePage` calendar
//                  sub-phase, with NO master strip and NO date intro (both are
//                  self-referential in this wizard) and its own «Далі» footer
//                  sitting disabled until a day is staged.
//   • `confirm`  — after staging the fixed date (Aug 10) + «Далі», then the
//                  one slot + «Далі»; guest card + booking summary card.
//   • `done`     — after tapping «Записати» and a successful submit; the
//                  standalone success scaffold (own Scaffold, header/step
//                  indicator hidden), guest recap card + booking summary card.
//
// BASELINES REGENERATED 2026-08-20 for the seven-defect UX fix (selection no
// longer auto-navigates; the dateTime step drops the master strip + intro; the
// submit CTA is «Записати»; the done step regains the guest card). The
// `client` step's six cells are byte-identical and were NOT regenerated —
// nothing on that step changed.
//
// Matrix: {320, 360, 414} dp x {textScale 1.0, 1.3} x 5 steps = 30 PNGs.
//
// Clock: `clockProvider` is pinned to `_kNow` (Aug 10, 2026 Kyiv midday) so
// the calendar's "today" cell and the fixed slot fixture agree deterministically
// — mirrors `master_create_booking_screen_test.dart`'s own anchoring.
//
// Router: `MasterCreateBookingScreen` calls `context.pop()` from its header
// back-chevron and the done step's «Готово» — neither is exercised by this
// file's drive sequences, but the widget still needs a `GoRouter` ancestor to
// build at all (`context.pop()`/`BookingTopBar` resolve `GoRouter.of`
// eagerly in some paths). Unlike every other file in this directory, this one
// supplies a dedicated `pumpWidget` override (`_wizardPump`, below) that
// wraps the alchemist-provided scene in `MaterialApp.router` with a
// single-route `GoRouter` at `RouteNames.masterBookingNew` instead of using
// the shared `goldenPumpWidget` (which only offers a router-less `MaterialApp`
// with `home:`) — then drives the interaction sequence for the target step
// with the SAME `tester` before alchemist captures the frame.

import 'package:alchemist/alchemist.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
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
import 'package:beautica_mobile/features/booking/presentation/master_create_booking_screen.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_notifier.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';

import '../helpers/pump_app.dart' show TapCalendarDay;
import 'helpers/golden_pump.dart';

// ---------------------------------------------------------------------------
// Fixtures — same values as `master_create_booking_screen_test.dart`.
// ---------------------------------------------------------------------------

const Master _kMaster = Master(
  id: 'master-1',
  firstName: 'Олена',
  lastName: 'Ковальчук',
  reviewCount: 0,
  type: MasterType.independentMaster,
);

const MasterService _kService = MasterService(
  id: 'svc-1',
  serviceDefId: 'def-1',
  name: 'Манікюр',
  durationMinutes: 60,
  priceMin: 500,
  priceDisplay: '500 ₴',
  category: 'NAILS',
);

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
// Fakes — mirror `master_create_booking_screen_test.dart`'s.
// ---------------------------------------------------------------------------

class _FakeMasterProfile extends MasterProfile {
  @override
  Future<Master> build() async => _kMaster;
}

class _FakeServicesList extends ServicesList {
  @override
  Future<List<MasterService>> build() async => const <MasterService>[_kService];
}

class _FakeSlotRepository implements SlotRepository {
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
  ) async => Appointment(
    id: 'appt-1',
    status: BookingStatus.confirmed,
    masterId: masterId,
    masterFirstName: _kMaster.firstName,
    masterLastName: _kMaster.lastName,
    masterType: 'INDEPENDENT_MASTER',
    startAt: request.startsAt,
    endAt: request.startsAt.add(Duration(minutes: _kService.durationMinutes)),
    totalDurationMinutes: _kService.durationMinutes,
    totalPrice: _kService.priceMin,
    items: <AppointmentItem>[
      AppointmentItem(
        bookingId: 'booking-1',
        masterServiceId: request.masterServiceIds.first,
        serviceName: _kService.name,
        startAt: request.startsAt,
        endAt: request.startsAt.add(
          Duration(minutes: _kService.durationMinutes),
        ),
        durationMinutes: _kService.durationMinutes,
        price: _kService.priceMin,
      ),
    ],
  );

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
  masterProfileProvider.overrideWith(_FakeMasterProfile.new),
  servicesListProvider.overrideWith(_FakeServicesList.new),
  approvedCategoriesProvider.overrideWith(
    (ref) async => const <ServiceCategoryOption>[],
  ),
  slotRepositoryProvider.overrideWith((_) => _FakeSlotRepository()),
  bookingRepositoryProvider.overrideWith((_) => _FakeBookingRepository()),
  clockProvider.overrideWithValue(() => _kNow),
];

// ---------------------------------------------------------------------------
// Drive sequences — one per goldened step.
// ---------------------------------------------------------------------------

Future<void> _fillClientAndAdvance(WidgetTester tester) async {
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
}

Future<void> _driveToService(WidgetTester tester) async {
  await _fillClientAndAdvance(tester);
}

// Selection never navigates on this wizard (2026-08-20 UX fix) — every step
// transition below is an explicit pinned-«Далі» press, matching
// `master_create_booking_screen_test.dart`'s own helpers.
//
// PHASE 253 — the service step's footer is now the shared
// [BookingSummaryBar] (key `booking-summary-cta`), not the bespoke
// `master-create-booking-service-next` footer this wizard used before
// multi-select.
Future<void> _driveToDateTime(WidgetTester tester) async {
  await _driveToService(tester);
  await tester.tap(find.byKey(const Key('mcb_service_card_svc-1')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('booking-summary-cta')));
  await tester.pumpAndSettle();
}

Future<void> _driveToConfirm(WidgetTester tester) async {
  await _driveToDateTime(tester);
  await tester.tapCalendarDay(10);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('master-create-booking-date-next')));
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(Key('salon-slot-chip-${_kSlot.startAt.toIso8601String()}')),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('master-create-booking-time-next')));
  await tester.pumpAndSettle();
}

Future<void> _driveToDone(WidgetTester tester) async {
  await _driveToConfirm(tester);
  await tester.tap(find.byKey(const Key('master-create-booking-submit-cta')));
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// Custom pumpWidget — MaterialApp.router (see file header for why the shared
// `goldenPumpWidget` router-less MaterialApp isn't used here) + the step's
// drive sequence, run with the SAME tester before alchemist captures.
// ---------------------------------------------------------------------------

PumpWidget _wizardPump({
  required double width,
  Future<void> Function(WidgetTester tester)? drive,
}) {
  return (WidgetTester tester, Widget alchemistWidget) async {
    tester.view.physicalSize = Size(width, kGoldenHeight);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final GoRouter router = GoRouter(
      initialLocation: RouteNames.masterBookingNew,
      routes: <RouteBase>[
        GoRoute(
          path: RouteNames.masterBookingNew,
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

    if (drive != null) {
      await drive(tester);
      await tester.pumpAndSettle();
    }
  };
}

// ---------------------------------------------------------------------------
// Step matrix
// ---------------------------------------------------------------------------

typedef _StepFixture = ({
  String name,
  Future<void> Function(WidgetTester tester)? drive,
});

const List<_StepFixture> _kSteps = <_StepFixture>[
  (name: 'client', drive: null),
  (name: 'service', drive: _driveToService),
  (name: 'dateTime', drive: _driveToDateTime),
  (name: 'confirm', drive: _driveToConfirm),
  (name: 'done', drive: _driveToDone),
];

// ---------------------------------------------------------------------------
// Goldens
// ---------------------------------------------------------------------------

void main() {
  for (final step in _kSteps) {
    for (final width in kGoldenWidths) {
      for (final scale in kGoldenTextScales) {
        final suffix = widthScaleSuffix(width, scale);

        goldenTest(
          'master_create_booking_wizard ${step.name} ${width.toInt()}dp '
          'text-${scale}x',
          fileName: 'master_create_booking_wizard_${step.name}_$suffix',
          constraints: BoxConstraints.tight(Size(width, kGoldenHeight)),
          textScaleFactor: scale,
          pumpWidget: _wizardPump(width: width, drive: step.drive),
          builder: () => const MasterCreateBookingScreen(),
        );
      }
    }
  }
}
