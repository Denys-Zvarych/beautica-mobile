// Phase 250 — Widget tests for SalonCreateBookingScreen.
//
// Mirrors `master_create_booking_screen_test.dart`'s conventions (test-local
// GoRouter, hand-written fakes, no mocktail) but exercises the SALON-only
// surface: the `masters` step (the crux of this phase — time selection lives
// there), the one-active-master collapse rule, the salon-catalogue service
// source, and the `salonId`-not-sent contract.
//
// `client`/`service`(picker-mode chrome)/`confirm`/`done` internals that are
// UNCHANGED reuses of the promoted `widgets/booking_wizard_steps.dart` widgets
// are exercised only enough to prove this screen wires them correctly — their
// OWN exhaustive behaviour (phone normalization edge cases, service-picker
// laziness, etc.) is already covered by `master_create_booking_screen_test
// .dart` against the SAME widgets and is not re-proven here.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
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
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_top_bar.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_wizard_steps.dart'
    show StepIndicator;
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/salon/application/salon_service_catalog_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon_master_summary.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_category_list.dart'
    show ServiceCard;
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_cta_footer.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/slot_chip.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/pump_app.dart';
import '../../../helpers/velvet_snack_matchers.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const String _kSalonId = 'salon-1';

const SalonMasterSummary _kMasterA = SalonMasterSummary(
  masterId: 'master-a',
  firstName: 'Олена',
  lastName: 'Ковальчук',
  type: MasterType.salonMaster,
  reviewCount: 0,
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

// PHASE 253 — multi-select fixtures: two more catalogue services in the
// SAME category (three services marked / deselect / order-preservation), and
// an 11-service catalogue (visit-selection cap).
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

List<SalonServiceCategoryEntry> _manySalonServicesCatalog(int n) =>
    <SalonServiceCategoryEntry>[
      SalonServiceCategoryEntry(
        category: 'NAILS',
        displayName: 'Манікюр',
        count: n,
        services: <SalonCatalogService>[
          for (int i = 0; i < n; i++)
            SalonCatalogService(
              id: 'salon-svc-cap-$i',
              name: 'Послуга $i',
              durationLabel: '30 хв',
              priceDisplay: '100 ₴',
              durationMinutes: 30,
              priceType: ServicePriceType.fixed,
              priceMin: 100,
            ),
        ],
      ),
    ];

/// Master A offers the catalogue service (assignment id `assignment-a`);
/// master B does not appear in the map at all — mirrors
/// `salonMasterServiceCoverageProvider`'s real "absent == not covered"
/// contract.
Map<String, Map<String, String>> _coverageAOnly() =>
    <String, Map<String, String>>{
      _kMasterA.masterId: <String, String>{_kCatalogService.id: 'assignment-a'},
    };

// future-date-ok: fixed clock-override instant; the exact day is the fixture's identity, never now-relative.
final DateTime _kNow = DateTime.utc(2026, 8, 10, 9); // 12:00 Kyiv, Aug 10.
// future-date-ok: fixed twin of _kNow — the same clock-override day, see above.
final DateTime _kSlotStart = DateTime.utc(2026, 8, 10, 10); // 13:00 Kyiv.
final BookingSlot _kSlot = BookingSlot(
  startAt: _kSlotStart,
  endAt: _kSlotStart.add(const Duration(minutes: 60)),
  available: true,
);

// Phase 250 QA gap-fill — a SECOND, LATER slot on the SAME master/day, used
// to prove a picked slot's own time (not merely "a" time) reaches confirm.
// future-date-ok: fixed twin of _kSlotStart, +2h — same fixture identity.
final DateTime _kSlot2Start = _kSlotStart.add(const Duration(hours: 2));
final BookingSlot _kSlot2 = BookingSlot(
  startAt: _kSlot2Start,
  endAt: _kSlot2Start.add(const Duration(minutes: 60)),
  available: true,
);

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeSlotRepository implements SlotRepository {
  _FakeSlotRepository({
    this.slotsByMaster = const <String, List<BookingSlot>>{},
  });

  /// Keyed by masterId — different masters can return different slot lists.
  Map<String, List<BookingSlot>> slotsByMaster;

  final List<String> getMasterSlotsCalls = <String>[];

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
  }) async {
    getMasterSlotsCalls.add(masterId);
    return slotsByMaster[masterId] ?? const <BookingSlot>[];
  }
}

class _FakeBookingRepository implements BookingRepository {
  _FakeBookingRepository({this.errorToThrow, this.hold, this.responseOverride});

  Object? errorToThrow;

  /// PHASE 256 — mirrors `master_create_booking_screen_test.dart`'s
  /// identical field (own doc there): when set, [createMasterBooking] awaits
  /// it before resolving, so a test can observe the CTA's disabled state
  /// mid-flight. `null` (every pre-256 call site) resolves immediately.
  final Completer<void>? hold;

  /// PHASE 256 mobile-qa — mirrors `master_create_booking_screen_test.dart`'s
  /// identical field (own doc there): a full-response override for the
  /// `should_renderServerWindow_when_visitCreated` test, whose whole point is
  /// a response `endAt` that genuinely DIFFERS from `request.startsAt + the
  /// local service duration` — the default fixture below cannot prove that
  /// distinction because it derives `endAt` FROM the local duration. `null`
  /// (every other call site) keeps the default fixture unchanged.
  final Appointment Function(
    String masterId,
    CreateMasterBookingRequest request,
  )?
  responseOverride;

  final List<(String, CreateMasterBookingRequest)> calls =
      <(String, CreateMasterBookingRequest)>[];

  @override
  Future<Appointment> createMasterBooking(
    String masterId,
    CreateMasterBookingRequest request,
  ) async {
    calls.add((masterId, request));
    final Completer<void>? h = hold;
    if (h != null) await h.future;
    final Object? err = errorToThrow;
    if (err != null) throw err;
    final Appointment Function(String, CreateMasterBookingRequest)? override =
        responseOverride;
    if (override != null) return override(masterId, request);
    return Appointment(
      id: 'appt-1',
      status: BookingStatus.confirmed,
      masterId: masterId,
      masterFirstName: _kMasterA.firstName,
      masterLastName: _kMasterA.lastName,
      masterType: 'SALON_MASTER',
      startAt: request.startsAt,
      endAt: request.startsAt.add(
        Duration(minutes: _kCatalogService.durationMinutes!),
      ),
      totalDurationMinutes: _kCatalogService.durationMinutes!,
      totalPrice: _kCatalogService.priceMin!,
      items: <AppointmentItem>[
        AppointmentItem(
          bookingId: 'booking-1',
          masterServiceId: request.masterServiceIds.first,
          serviceName: _kCatalogService.name,
          startAt: request.startsAt,
          endAt: request.startsAt.add(
            Duration(minutes: _kCatalogService.durationMinutes!),
          ),
          durationMinutes: _kCatalogService.durationMinutes!,
          price: _kCatalogService.priceMin!,
        ),
      ],
    );
  }

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
// Router + pump helper
// ---------------------------------------------------------------------------

GoRouter _router() => GoRouter(
  initialLocation: '/root',
  routes: <RouteBase>[
    GoRoute(
      path: '/root',
      builder: (context, state) => const SizedBox.shrink(),
    ),
    GoRoute(
      path: '/salon-test-target',
      builder: (context, state) =>
          const SalonCreateBookingScreen(salonId: _kSalonId),
    ),
  ],
);

Future<GoRouter> _pump(
  WidgetTester tester, {
  List<SalonMasterSummary> roster = const <SalonMasterSummary>[
    _kMasterA,
    _kMasterB,
  ],
  Map<String, Map<String, String>>? coverage,
  List<SalonServiceCategoryEntry> catalog = _kCatalog,
  _FakeSlotRepository? slotRepository,
  _FakeBookingRepository? bookingRepository,
}) async {
  final GoRouter router = _router();
  await tester.pumpRoutedApp(
    router,
    overrides: <Object>[
      salonMastersRosterProvider.overrideWith(
        (ref, String salonId) async => roster,
      ),
      salonMasterServiceCoverageProvider.overrideWith(
        (ref, args) async => coverage ?? _coverageAOnly(),
      ),
      salonServiceCatalogProvider.overrideWith(
        (ref, String salonId) async => catalog,
      ),
      slotRepositoryProvider.overrideWith(
        (_) => slotRepository ?? _FakeSlotRepository(),
      ),
      bookingRepositoryProvider.overrideWith(
        (_) => bookingRepository ?? _FakeBookingRepository(),
      ),
      clockProvider.overrideWithValue(() => _kNow),
    ],
  );
  unawaited(router.push('/salon-test-target'));
  await tester.pumpAndSettle();
  return router;
}

Future<void> _fillClientStepAndAdvance(WidgetTester tester) async {
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

/// PHASE 253 — `service` is now multi-select, SELECT ONLY (no more
/// auto-navigate on tap — see `salon_create_booking_screen.dart`'s file
/// header). The card tap only marks the service selected; the pinned
/// [BookingSummaryBar] CTA (key `booking-summary-cta`) is what advances.
Future<void> _pickService(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('mcb_service_card_salon-svc-1')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('booking-summary-cta')));
  await tester.pumpAndSettle();
}

/// Picks Aug 10 (== [_kNow]'s Kyiv "today") and taps «Далі — Майстри».
Future<void> _pickDateAndAdvance(WidgetTester tester) async {
  await tester.tapCalendarDay(10);
  await tester.pump();
  await tester.tap(find.byKey(const Key('salon-create-booking-date-next')));
  await tester.pumpAndSettle();
}

/// Drives client → service → dateTime, landing on `masters`.
Future<void> _driveToMasters(WidgetTester tester) async {
  await _fillClientStepAndAdvance(tester);
  await _pickService(tester);
  await _pickDateAndAdvance(tester);
}

void main() {
  group('SalonCreateBookingScreen — client/service wiring', () {
    testWidgets('client step advances to the salon-catalogue service picker', (
      tester,
    ) async {
      await _pump(tester);
      await _fillClientStepAndAdvance(tester);

      expect(
        find.byKey(const Key('mcb_service_card_salon-svc-1')),
        findsOneWidget,
      );
    });

    testWidgets(
      'a malformed phone blocks «Далі» and the booking repository is never '
      'called',
      (tester) async {
        final fakeBookings = _FakeBookingRepository();
        await _pump(tester, bookingRepository: fakeBookings);

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
          '12345',
        );
        await tester.pump();

        final NeumorphicButton nextButton = tester.widget<NeumorphicButton>(
          find.byKey(const Key('master-create-booking-client-next')),
        );
        expect(nextButton.onPressed, isNull);
        expect(fakeBookings.calls, isEmpty);
      },
    );

    testWidgets(
      'the service picker is fed the SALON aggregate catalogue, not "my own '
      'services" — an empty salon catalogue renders the salon-specific empty '
      'state copy',
      (tester) async {
        await _pump(tester, catalog: const <SalonServiceCategoryEntry>[]);
        await _fillClientStepAndAdvance(tester);

        expect(
          find.byKey(const Key('master-create-booking-service-empty')),
          findsOneWidget,
        );
        final l10n = AppLocalizations.of(
          tester.element(find.byType(SalonCreateBookingScreen)),
        );
        expect(
          find.text(l10n.salonCreateBookingServiceEmptyTitle),
          findsOneWidget,
        );
      },
    );
  });

  // PHASE 253 — the salon wizard shares [ServiceStep]'s widened multi-select
  // path with the master wizard (`master_create_booking_screen_test.dart`
  // proves the exhaustive behaviour against the SAME shared widget). This
  // group proves the SAME four cases wire correctly on this screen too.
  group('SalonCreateBookingScreen — service step (PHASE 253 multi-select)', () {
    testWidgets(
      'tapping three services marks three cards; tapping one again unmarks '
      'it; the CTA is disabled at zero selections',
      (tester) async {
        await _pump(tester, catalog: _kMultiCatalog);
        await _fillClientStepAndAdvance(tester);

        final Finder next = find.byKey(const Key('booking-summary-cta'));
        expect(tester.widget<NeumorphicButton>(next).onPressed, isNull);

        for (final String id in <String>[
          'salon-svc-1',
          'salon-svc-2',
          'salon-svc-3',
        ]) {
          await tester.tap(find.byKey(Key('mcb_service_card_$id')));
          await tester.pump();
        }
        for (final String id in <String>[
          'salon-svc-1',
          'salon-svc-2',
          'salon-svc-3',
        ]) {
          expect(
            tester
                .widget<ServiceCard>(find.byKey(Key('mcb_service_card_$id')))
                .selected,
            isTrue,
          );
        }
        expect(tester.widget<NeumorphicButton>(next).onPressed, isNotNull);

        await tester.tap(find.byKey(const Key('mcb_service_card_salon-svc-2')));
        await tester.pump();
        expect(
          tester
              .widget<ServiceCard>(
                find.byKey(const Key('mcb_service_card_salon-svc-2')),
              )
              .selected,
          isFalse,
        );

        await tester.tap(find.byKey(const Key('mcb_service_card_salon-svc-1')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('mcb_service_card_salon-svc-3')));
        await tester.pump();
        expect(tester.widget<NeumorphicButton>(next).onPressed, isNull);
      },
    );

    testWidgets(
      'the visit-selection cap: an 11th add is refused with a friendly '
      'VelvetSnack and the selection stays at maxServicesPerVisit',
      (tester) async {
        tester.view.physicalSize = const Size(800, 8000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await _pump(tester, catalog: _manySalonServicesCatalog(11));
        await _fillClientStepAndAdvance(tester);

        for (int i = 0; i < 11; i++) {
          await tester.tap(
            find.byKey(Key('mcb_service_card_salon-svc-cap-$i')),
          );
          await tester.pump();
        }

        final l10n = AppLocalizations.of(
          tester.element(find.byType(SalonCreateBookingScreen)),
        );
        expectVelvetSnack(
          l10n.bookingMaxServicesReached(maxServicesPerVisit),
          variant: VelvetSnackVariant.warning,
        );
        await pumpPastVelvetSnack(tester);

        int selectedCount = 0;
        for (int i = 0; i < 11; i++) {
          if (tester
              .widget<ServiceCard>(
                find.byKey(Key('mcb_service_card_salon-svc-cap-$i')),
              )
              .selected) {
            selectedCount++;
          }
        }
        expect(selectedCount, maxServicesPerVisit);
      },
    );

    testWidgets(
      'de-selecting still works while at the cap (the guard only fires on '
      'an ADD)',
      (tester) async {
        tester.view.physicalSize = const Size(800, 8000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await _pump(tester, catalog: _manySalonServicesCatalog(11));
        await _fillClientStepAndAdvance(tester);

        for (int i = 0; i < 10; i++) {
          await tester.tap(
            find.byKey(Key('mcb_service_card_salon-svc-cap-$i')),
          );
          await tester.pump();
        }
        await tester.tap(
          find.byKey(const Key('mcb_service_card_salon-svc-cap-0')),
        );
        await tester.pump();

        expect(
          tester
              .widget<ServiceCard>(
                find.byKey(const Key('mcb_service_card_salon-svc-cap-0')),
              )
              .selected,
          isFalse,
        );
        expect(find.byType(VelvetSnack), findsNothing);
      },
    );

    testWidgets(
      'selection order is TAP order, not catalogue order, and survives into '
      'the BookingSummaryBar itemized shelf',
      (tester) async {
        await _pump(tester, catalog: _kMultiCatalog);
        await _fillClientStepAndAdvance(tester);

        for (final String id in <String>[
          'salon-svc-3',
          'salon-svc-1',
          'salon-svc-2',
        ]) {
          await tester.tap(find.byKey(Key('mcb_service_card_$id')));
          await tester.pump();
        }

        await tester.tap(
          find.byKey(const Key('booking-summary-expand-toggle')),
        );
        await tester.pumpAndSettle();

        final double y3 = tester
            .getTopLeft(find.byKey(const ValueKey<String>('salon-svc-3')))
            .dy;
        final double y1 = tester
            .getTopLeft(find.byKey(const ValueKey<String>('salon-svc-1')))
            .dy;
        final double y2 = tester
            .getTopLeft(find.byKey(const ValueKey<String>('salon-svc-2')))
            .dy;
        expect(
          y3 < y1 && y1 < y2,
          isTrue,
          reason:
              'the itemized shelf must render in TAP order (3, 1, 2), got '
              'y3=$y3 y1=$y1 y2=$y2',
        );
      },
    );
  });

  group('SalonCreateBookingScreen — dateTime step (date-only)', () {
    testWidgets('«Далі — Майстри» is disabled until a date is picked', (
      tester,
    ) async {
      await _pump(tester);
      await _fillClientStepAndAdvance(tester);
      await _pickService(tester);

      NeumorphicButton nextButton() => tester.widget<NeumorphicButton>(
        find.byKey(const Key('salon-create-booking-date-next')),
      );
      expect(nextButton().onPressed, isNull);

      await tester.tapCalendarDay(10);
      await tester.pump();
      expect(nextButton().onPressed, isNotNull);
    });

    testWidgets('picking a date does NOT auto-advance — time selection lives '
        'in the masters step, not here', (tester) async {
      await _pump(tester);
      await _fillClientStepAndAdvance(tester);
      await _pickService(tester);

      await tester.tapCalendarDay(10);
      await tester.pump();

      expect(
        find.byKey(const Key('salon-create-booking-date-calendar')),
        findsOneWidget,
        reason: 'still on dateTime — a date pick alone must not advance',
      );
    });
  });

  group('SalonCreateBookingScreen — masters step (multi-master)', () {
    testWidgets(
      'renders a tile per master; a non-covering master shows «Не виконує» '
      'and is not expandable',
      (tester) async {
        await _pump(tester);
        await _driveToMasters(tester);

        expect(
          find.byKey(const Key('salon-master-tile-master-a')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('salon-master-tile-master-b')),
          findsOneWidget,
        );

        final l10n = AppLocalizations.of(
          tester.element(find.byType(SalonCreateBookingScreen)),
        );
        expect(
          find.text(l10n.salonCreateBookingMasterNotOffered),
          findsOneWidget,
        );

        // Tapping the non-covering tile is a no-op — no slot section appears.
        await tester.tap(find.byKey(const Key('salon-master-tile-master-b')));
        await tester.pumpAndSettle();
        expect(find.byType(ErrorState), findsNothing);
        expect(
          find.byKey(const Key('salon-master-tile-slots-loading')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'expanding a covering master lazily fetches ONLY that master\'s slots '
      '— the other master is never queried',
      (tester) async {
        final fakeSlots = _FakeSlotRepository(
          slotsByMaster: <String, List<BookingSlot>>{
            _kMasterA.masterId: <BookingSlot>[_kSlot],
          },
        );
        await _pump(tester, slotRepository: fakeSlots);
        await _driveToMasters(tester);

        expect(fakeSlots.getMasterSlotsCalls, isEmpty);

        await tester.tap(find.byKey(const Key('salon-master-tile-master-a')));
        await tester.pumpAndSettle();

        expect(fakeSlots.getMasterSlotsCalls, <String>['master-a']);
        expect(
          find.byKey(
            Key(
              'salon-tile-slot-chip-master-a-${_kSlot.startAt.toIso8601String()}',
            ),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'an empty slot list on an expanded tile renders the empty state, never '
      'an infinite spinner',
      (tester) async {
        final fakeSlots = _FakeSlotRepository(
          slotsByMaster: const <String, List<BookingSlot>>{},
        );
        await _pump(tester, slotRepository: fakeSlots);
        await _driveToMasters(tester);

        await tester.tap(find.byKey(const Key('salon-master-tile-master-a')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('salon-master-tile-slots-empty')),
          findsOneWidget,
        );
        expect(find.byType(CircularProgressIndicator), findsNothing);
      },
    );

    testWidgets(
      'picking a slot inside a master tile advances to confirm — this IS the '
      'crux of the phase: time selection lives inside the master tile',
      (tester) async {
        final fakeSlots = _FakeSlotRepository(
          slotsByMaster: <String, List<BookingSlot>>{
            _kMasterA.masterId: <BookingSlot>[_kSlot],
          },
        );
        await _pump(tester, slotRepository: fakeSlots);
        await _driveToMasters(tester);

        await tester.tap(find.byKey(const Key('salon-master-tile-master-a')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            Key(
              'salon-tile-slot-chip-master-a-${_kSlot.startAt.toIso8601String()}',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('master-create-booking-confirm-card')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('salon-create-booking-master-card')),
          findsOneWidget,
          reason:
              'the confirm step shows a master identity card — the '
              'reason this step exists in the SALON variant at all',
        );
      },
    );

    testWidgets('no covering master at all renders the empty state', (
      tester,
    ) async {
      await _pump(tester, coverage: const <String, Map<String, String>>{});
      await _driveToMasters(tester);

      expect(
        find.byKey(const Key('salon-create-booking-no-covering-master')),
        findsOneWidget,
      );
    });
  });

  group('SalonCreateBookingScreen — masters step picks BOTH master AND time', () {
    testWidgets(
      'picking the SECOND (later) slot inside a tile carries THAT slot\'s '
      'own time to confirm, not the first slot offered — proves the picked '
      'time is read from the tapped chip, not defaulted to slot #0',
      (tester) async {
        final fakeSlots = _FakeSlotRepository(
          slotsByMaster: <String, List<BookingSlot>>{
            _kMasterA.masterId: <BookingSlot>[_kSlot, _kSlot2],
          },
        );
        await _pump(tester, slotRepository: fakeSlots);
        await _driveToMasters(tester);

        await tester.tap(find.byKey(const Key('salon-master-tile-master-a')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            Key(
              'salon-tile-slot-chip-master-a-${_kSlot2.startAt.toIso8601String()}',
            ),
          ),
        );
        await tester.pumpAndSettle();

        final String pickedTime = formatTimeRange(
          _kSlot2.startAt,
          _kCatalogService.durationMinutes!,
        );
        final String firstSlotTime = formatTimeRange(
          _kSlot.startAt,
          _kCatalogService.durationMinutes!,
        );
        expect(
          find.byKey(const Key('master-create-booking-confirm-card')),
          findsOneWidget,
        );
        expect(
          find.text(pickedTime),
          findsOneWidget,
          reason: 'confirm must show the SECOND slot\'s own time',
        );
        expect(
          find.text(firstSlotTime),
          findsNothing,
          reason:
              'confirm must NOT show the first slot\'s time — that would '
              'mean the pick silently defaulted to slot #0',
        );
      },
    );

    testWidgets(
      'the masters step renders no CTA/footer of its own — reaching confirm '
      'is possible ONLY by picking a slot inside a tile, never by simply '
      'advancing',
      (tester) async {
        await _pump(tester);
        await _driveToMasters(tester);

        // No tile expanded, no slot picked — assert there is no skip path.
        expect(find.byType(BookingCtaFooter), findsNothing);
        expect(
          find.byKey(const Key('salon-create-booking-submit-cta')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('master-create-booking-confirm-card')),
          findsNothing,
        );
      },
    );
  });

  group('SalonCreateBookingScreen — non-covering tile is NOT merely dimmed, it '
      'is structurally non-interactive', () {
    testWidgets(
      'a non-covering master tile is reported disabled/non-button via '
      'Semantics, and tapping it never renders a slot chip',
      (tester) async {
        await _pump(tester);
        await _driveToMasters(tester);

        final Finder tile = find.byKey(const Key('salon-master-tile-master-b'));
        final Finder disabledSemantics = find.descendant(
          of: tile,
          matching: find.byWidgetPredicate(
            (Widget w) =>
                w is Semantics &&
                w.properties.button == false &&
                w.properties.enabled == false,
          ),
        );
        expect(
          disabledSemantics,
          findsOneWidget,
          reason:
              'a non-covering tile must report itself as a disabled '
              'non-button to assistive tech, not just render faded',
        );

        await tester.tap(tile);
        await tester.pumpAndSettle();

        expect(
          find.descendant(of: tile, matching: find.byType(SlotChip)),
          findsNothing,
          reason:
              'tapping a non-covering tile must never expand a slot '
              'section',
        );
      },
    );
  });

  group('SalonCreateBookingScreen — one-active-master COLLAPSE rule', () {
    testWidgets('a salon with exactly ONE active master renders the slot grid '
        'directly — no one-row picker chrome', (tester) async {
      final fakeSlots = _FakeSlotRepository(
        slotsByMaster: <String, List<BookingSlot>>{
          _kMasterA.masterId: <BookingSlot>[_kSlot],
        },
      );
      await _pump(
        tester,
        roster: const <SalonMasterSummary>[_kMasterA],
        coverage: _coverageAOnly(),
        slotRepository: fakeSlots,
      );
      await _driveToMasters(tester);

      expect(
        find.byKey(const Key('salon-create-booking-masters-collapsed')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('salon-master-tile-master-a')), findsNothing);

      await tester.tap(
        find.byKey(
          Key('salon-collapsed-slot-chip-${_kSlot.startAt.toIso8601String()}'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('master-create-booking-confirm-card')),
        findsOneWidget,
      );
    });

    testWidgets('the collapsed one-master body renders the empty state, not a '
        'spinner, when there are no free slots that day', (tester) async {
      final fakeSlots = _FakeSlotRepository(
        slotsByMaster: const <String, List<BookingSlot>>{},
      );
      await _pump(
        tester,
        roster: const <SalonMasterSummary>[_kMasterA],
        coverage: _coverageAOnly(),
        slotRepository: fakeSlots,
      );
      await _driveToMasters(tester);

      expect(
        find.byKey(const Key('salon-create-booking-collapsed-empty')),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('SalonCreateBookingScreen — confirm step', () {
    Future<void> driveToConfirm(
      WidgetTester tester, {
      _FakeSlotRepository? slotRepository,
      _FakeBookingRepository? bookingRepository,
    }) async {
      await _pump(
        tester,
        slotRepository: slotRepository,
        bookingRepository: bookingRepository,
      );
      await _driveToMasters(tester);
      await tester.tap(find.byKey(const Key('salon-master-tile-master-a')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          Key(
            'salon-tile-slot-chip-master-a-${_kSlot.startAt.toIso8601String()}',
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'a 422 (genuine slot-unavailable) keeps the user on confirm with the '
      'GENERIC conflict message and does NOT advance to done',
      (tester) async {
        final fakeSlots = _FakeSlotRepository(
          slotsByMaster: <String, List<BookingSlot>>{
            _kMasterA.masterId: <BookingSlot>[_kSlot],
          },
        );
        final fakeBookings = _FakeBookingRepository(
          errorToThrow: const ConflictFailure(),
        );
        await driveToConfirm(
          tester,
          slotRepository: fakeSlots,
          bookingRepository: fakeBookings,
        );

        await tester.tap(
          find.byKey(const Key('salon-create-booking-submit-cta')),
        );
        await tester.pumpAndSettle();

        expect(fakeBookings.calls, hasLength(1));
        expect(
          find.byKey(const Key('master-create-booking-confirm-card')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('salon-create-booking-done-cta')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('master-create-booking-submit-error')),
          findsOneWidget,
        );
        expect(find.byType(VelvetSnack), findsNothing);
      },
    );

    // PHASE 256 — mirrors `master_create_booking_screen_test.dart`'s
    // `should_showAlreadyCreatedMessage_when_409` (own doc there).
    testWidgets(
      'should_showAlreadyCreatedMessage_when_409 — a duplicate-409 keeps the '
      'user on confirm with the "already created" message AND a recoverable '
      'snack, and does NOT advance to done',
      (tester) async {
        final fakeSlots = _FakeSlotRepository(
          slotsByMaster: <String, List<BookingSlot>>{
            _kMasterA.masterId: <BookingSlot>[_kSlot],
          },
        );
        final fakeBookings = _FakeBookingRepository(
          errorToThrow: const MasterBookingDuplicateFailure(),
        );
        await driveToConfirm(
          tester,
          slotRepository: fakeSlots,
          bookingRepository: fakeBookings,
        );

        await tester.tap(
          find.byKey(const Key('salon-create-booking-submit-cta')),
        );
        await pumpVelvetSnackIn(tester);

        expect(fakeBookings.calls, hasLength(1));
        expect(
          find.byKey(const Key('master-create-booking-confirm-card')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('salon-create-booking-done-cta')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('master-create-booking-submit-error')),
          findsOneWidget,
        );
        final l10n = AppLocalizations.of(
          tester.element(find.byType(SalonCreateBookingScreen)),
        );
        // Two renders of the SAME message: the inline banner (ConfirmStep)
        // AND the recovery snack. `expectVelvetSnack`'s unscoped `find.text`
        // assumes exactly ONE render app-wide, so it cannot be used as-is
        // here — assert the snack's own subtree directly instead.
        expect(find.text(l10n.errMasterBookingDuplicate), findsNWidgets(2));
        final Finder snackFinder = find.byType(VelvetSnack);
        expect(snackFinder, findsOneWidget);
        expect(
          (snackFinder.evaluate().single.widget as VelvetSnack).variant,
          VelvetSnackVariant.error,
        );
        expect(
          find.descendant(
            of: snackFinder,
            matching: find.text(l10n.errMasterBookingDuplicate),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: snackFinder,
            matching: find.text(l10n.masterCreateBookingDuplicateRefreshAction),
          ),
          findsOneWidget,
        );

        await pumpPastVelvetSnack(tester, hasAction: true);
      },
    );

    // PHASE 256 — mirrors the master wizard's identical test, EXCEPT the
    // recovery step: THIS wizard's slot picker is `masters` (date-only
    // `dateTime` never fetches a slot), so «Оновити» returns there — see
    // `salon_create_booking_screen.dart`'s `_handleDuplicateRefresh` doc.
    testWidgets(
      'should_returnToDateTimeStep_when_refreshTappedOnConflictSnack — the '
      "409 snack's «Оновити» returns to `masters` and genuinely re-fetches "
      'the slot list on re-pick, not a cached hit',
      (tester) async {
        final fakeSlots = _FakeSlotRepository(
          slotsByMaster: <String, List<BookingSlot>>{
            _kMasterA.masterId: <BookingSlot>[_kSlot],
          },
        );
        final fakeBookings = _FakeBookingRepository(
          errorToThrow: const MasterBookingDuplicateFailure(),
        );
        await driveToConfirm(
          tester,
          slotRepository: fakeSlots,
          bookingRepository: fakeBookings,
        );
        final int slotFetchesBeforeSubmit =
            fakeSlots.getMasterSlotsCalls.length;

        await tester.tap(
          find.byKey(const Key('salon-create-booking-submit-cta')),
        );
        await pumpVelvetSnackIn(tester);

        await tester.tap(
          find.byKey(const ValueKey<String>('velvet_snack_action')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('master-create-booking-confirm-card')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('salon-master-tile-master-a')),
          findsOneWidget,
          reason: 'must land back on the `masters` step, the slot picker',
        );

        await tester.tap(find.byKey(const Key('salon-master-tile-master-a')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            Key(
              'salon-tile-slot-chip-master-a-${_kSlot.startAt.toIso8601String()}',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          fakeSlots.getMasterSlotsCalls.length,
          greaterThan(slotFetchesBeforeSubmit),
          reason:
              '«Оновити» must drop the cached slot fetch, not just navigate '
              'back to a stale one',
        );
      },
    );

    // PHASE 256 — mirrors the master wizard's identical mobile-debugger
    // regression test (own doc there). This screen has NO `PopScope` at all
    // (file header: "No `PopScope` needed here"), so the system back gesture
    // pops `confirm` even more directly.
    testWidgets('should_notCrash_when_snackActionTappedAfterWizardPopped — the '
        'duplicate-409 snack survives a system-back pop of the wizard, and '
        'tapping «Оновити» afterwards is a silent no-op, not a crash', (
      tester,
    ) async {
      final fakeSlots = _FakeSlotRepository(
        slotsByMaster: <String, List<BookingSlot>>{
          _kMasterA.masterId: <BookingSlot>[_kSlot],
        },
      );
      final fakeBookings = _FakeBookingRepository(
        errorToThrow: const MasterBookingDuplicateFailure(),
      );
      await driveToConfirm(
        tester,
        slotRepository: fakeSlots,
        bookingRepository: fakeBookings,
      );

      await tester.tap(
        find.byKey(const Key('salon-create-booking-submit-cta')),
      );
      await pumpVelvetSnackIn(tester);
      expect(find.byType(VelvetSnack), findsOneWidget);

      final bool handled = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(handled, isTrue);
      expect(find.byType(SalonCreateBookingScreen), findsNothing);

      expect(find.byType(VelvetSnack), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('velvet_snack_action')),
      );
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason:
            'a disposed State must not receive ref.invalidate/setState '
            'from the late snack-action tap',
      );

      await pumpPastVelvetSnack(tester, hasAction: true);
    });

    // PHASE 256 D1 — mirrors the master wizard's identical mutation-checked
    // test.
    testWidgets(
      'should_disableCta_when_submitInFlight — the CTA is disabled for the '
      'WHOLE outstanding submit',
      (tester) async {
        final fakeSlots = _FakeSlotRepository(
          slotsByMaster: <String, List<BookingSlot>>{
            _kMasterA.masterId: <BookingSlot>[_kSlot],
          },
        );
        final hold = Completer<void>();
        final fakeBookings = _FakeBookingRepository(hold: hold);
        await driveToConfirm(
          tester,
          slotRepository: fakeSlots,
          bookingRepository: fakeBookings,
        );

        final Finder cta = find.byKey(
          const Key('salon-create-booking-submit-cta'),
        );
        expect(tester.widget<NeumorphicButton>(cta).onPressed, isNotNull);

        await tester.tap(cta);
        await tester.pump();

        expect(tester.widget<NeumorphicButton>(cta).onPressed, isNull);

        hold.complete();
        await tester.pumpAndSettle();

        expect(fakeBookings.calls, hasLength(1));
      },
    );

    // PHASE 256 — mirrors the master wizard's identical empirically-proven
    // test (own doc there).
    testWidgets(
      'should_submitOnce_when_ctaDoubleTapped — two fast taps with no pump '
      'between them issue exactly ONE createMasterBooking call',
      (tester) async {
        final fakeSlots = _FakeSlotRepository(
          slotsByMaster: <String, List<BookingSlot>>{
            _kMasterA.masterId: <BookingSlot>[_kSlot],
          },
        );
        final fakeBookings = _FakeBookingRepository();
        await driveToConfirm(
          tester,
          slotRepository: fakeSlots,
          bookingRepository: fakeBookings,
        );

        final Finder cta = find.byKey(
          const Key('salon-create-booking-submit-cta'),
        );
        await tester.tap(cta);
        await tester.tap(cta);
        await tester.pumpAndSettle();

        expect(fakeBookings.calls, hasLength(1));
        expect(
          find.byKey(const Key('salon-create-booking-done-cta')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'a 403 (MasterBookingNotPermittedFailure) keeps the user on confirm, '
      'renders the permission-denied copy, and never anything resembling '
      '«майстра не знайдено»',
      (tester) async {
        final fakeSlots = _FakeSlotRepository(
          slotsByMaster: <String, List<BookingSlot>>{
            _kMasterA.masterId: <BookingSlot>[_kSlot],
          },
        );
        final fakeBookings = _FakeBookingRepository(
          errorToThrow: const MasterBookingNotPermittedFailure(),
        );
        await driveToConfirm(
          tester,
          slotRepository: fakeSlots,
          bookingRepository: fakeBookings,
        );

        await tester.tap(
          find.byKey(const Key('salon-create-booking-submit-cta')),
        );
        await tester.pumpAndSettle();

        expect(fakeBookings.calls, hasLength(1));
        expect(
          find.byKey(const Key('master-create-booking-confirm-card')),
          findsOneWidget,
          reason: 'a 403 must NOT advance the wizard to done',
        );
        expect(
          find.byKey(const Key('salon-create-booking-done-cta')),
          findsNothing,
        );

        final l10n = AppLocalizations.of(
          tester.element(find.byType(SalonCreateBookingScreen)),
        );
        expect(find.text(l10n.bookingErrMasterNotPermitted), findsOneWidget);
        expect(
          find.textContaining('знайдено'),
          findsNothing,
          reason:
              'MasterBookingNotPermittedFailure.userMessage must never leak '
              '"master not found" — see failures.dart\'s own doc on this '
              'class (a 403 also covers an unknown/inactive masterId, and '
              'distinguishing that via copy would be the exact probe leak '
              'the backend collapses into one status code to prevent)',
        );
      },
    );

    testWidgets('«salonId» is never sent — the write carries the master\'s OWN '
        'assignment id (assignment-a), never the salon-catalogue service id '
        '(salon-svc-1), and CreateMasterBookingRequest structurally has no '
        'salonId field to put one in', (tester) async {
      final fakeSlots = _FakeSlotRepository(
        slotsByMaster: <String, List<BookingSlot>>{
          _kMasterA.masterId: <BookingSlot>[_kSlot],
        },
      );
      final fakeBookings = _FakeBookingRepository();
      await driveToConfirm(
        tester,
        slotRepository: fakeSlots,
        bookingRepository: fakeBookings,
      );

      await tester.tap(
        find.byKey(const Key('salon-create-booking-submit-cta')),
      );
      await tester.pumpAndSettle();

      expect(fakeBookings.calls, hasLength(1));
      final (String masterId, CreateMasterBookingRequest sent) =
          fakeBookings.calls.single;
      expect(masterId, 'master-a');
      expect(sent.masterServiceIds, ['assignment-a']);
      expect(sent.masterServiceIds, isNot(contains('salon-svc-1')));
      expect(sent.startsAt, _kSlot.startAt);
      expect(sent.guest.name, 'Марина');
      expect(sent.guest.surname, 'Кравчук');
      expect(sent.guest.phone, '+380501234567');
    });
  });

  group('SalonCreateBookingScreen — done step', () {
    Future<void> reachDone(WidgetTester tester) async {
      final fakeSlots = _FakeSlotRepository(
        slotsByMaster: <String, List<BookingSlot>>{
          _kMasterA.masterId: <BookingSlot>[_kSlot],
        },
      );
      await _pump(tester, slotRepository: fakeSlots);
      await _driveToMasters(tester);
      await tester.tap(find.byKey(const Key('salon-master-tile-master-a')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          Key(
            'salon-tile-slot-chip-master-a-${_kSlot.startAt.toIso8601String()}',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('salon-create-booking-submit-cta')),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'blocks a real system back-button press (PopScope canPop: false), not '
      'just the property',
      (tester) async {
        await reachDone(tester);

        expect(
          find.byKey(const Key('salon-create-booking-done-cta')),
          findsOneWidget,
        );

        final bool handled = await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(handled, isTrue);
        expect(
          find.byKey(const Key('salon-create-booking-done-cta')),
          findsOneWidget,
          reason: 'done step must still be on screen after a refused pop',
        );
      },
    );

    testWidgets('hides the header AND the 5-dot step indicator', (
      tester,
    ) async {
      await reachDone(tester);

      expect(find.byType(BookingTopBar), findsNothing);
      expect(find.byType(StepIndicator), findsNothing);
      expect(find.byKey(const Key('salon-create-booking-back')), findsNothing);
    });

    testWidgets('the done-step copy makes no SMS/notification claim', (
      tester,
    ) async {
      await reachDone(tester);

      final l10n = AppLocalizations.of(
        tester.element(find.byType(SalonCreateBookingScreen)),
      );
      expect(find.text(l10n.salonCreateBookingDoneSubline), findsOneWidget);
      expect(find.textContaining('SMS'), findsNothing);
      expect(find.textContaining('Сповіщення'), findsNothing);
    });

    // PHASE 256 mobile-qa gap-fill — `_SalonDoneStep` (mirrors the master
    // wizard's `_DoneStep`, own doc there) switched to `formatSlotTimeRange
    // (appointment.startAt, appointment.endAt)` — the SERVER's window — but
    // no test here proved it: the default `reachDone` fixture derives
    // `endAt` FROM `request.startsAt + _kCatalogService.durationMinutes`, so
    // it renders IDENTICALLY whether the done step reads the response or
    // re-derives locally. This test uses [_FakeBookingRepository
    // .responseOverride] to make the response's window genuinely diverge
    // (+20 minutes) from the local duration alone — MUTATION-CHECK RED by
    // reverting `_SalonDoneStep` to a local-derived render, same as the
    // master wizard's own `should_renderServerVisitWindow_when
    // _multiServiceVisitCreated`.
    testWidgets(
      'should_renderServerWindow_when_visitCreated — the done step\'s time '
      'range comes from the SERVER endAt, not a local re-derivation of the '
      'picked service\'s duration',
      (tester) async {
        // The ITEM keeps its own real service duration (60 min, matching
        // `_kCatalogService`) — a local re-derivation reads exactly this
        // field (`item.durationMinutes`). The VISIT-level `endAt` carries a
        // 20-minute post-service buffer on top of it (the same "chained
        // window ≠ naive local sum" shape the master wizard's buffered
        // multi-service fixtures use), so the two renders are only
        // distinguishable if the done step reads `appointment.endAt` rather
        // than re-deriving from the item's own duration.
        const int itemDurationMinutes = 60;
        const int bufferedTotalMinutes = itemDurationMinutes + 20;
        final fakeSlots = _FakeSlotRepository(
          slotsByMaster: <String, List<BookingSlot>>{
            _kMasterA.masterId: <BookingSlot>[_kSlot],
          },
        );
        final fakeBookings = _FakeBookingRepository(
          responseOverride:
              (String masterId, CreateMasterBookingRequest request) =>
                  Appointment(
                    id: 'appt-buffered',
                    status: BookingStatus.confirmed,
                    masterId: masterId,
                    masterFirstName: _kMasterA.firstName,
                    masterLastName: _kMasterA.lastName,
                    masterType: 'SALON_MASTER',
                    startAt: request.startsAt,
                    endAt: request.startsAt.add(
                      const Duration(minutes: bufferedTotalMinutes),
                    ),
                    totalDurationMinutes: bufferedTotalMinutes,
                    totalPrice: _kCatalogService.priceMin!,
                    items: <AppointmentItem>[
                      AppointmentItem(
                        bookingId: 'booking-1',
                        masterServiceId: request.masterServiceIds.first,
                        serviceName: _kCatalogService.name,
                        startAt: request.startsAt,
                        endAt: request.startsAt.add(
                          const Duration(minutes: itemDurationMinutes),
                        ),
                        durationMinutes: itemDurationMinutes,
                        price: _kCatalogService.priceMin!,
                      ),
                    ],
                  ),
        );
        await _pump(
          tester,
          slotRepository: fakeSlots,
          bookingRepository: fakeBookings,
        );
        await _driveToMasters(tester);
        await tester.tap(find.byKey(const Key('salon-master-tile-master-a')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            Key(
              'salon-tile-slot-chip-master-a-${_kSlot.startAt.toIso8601String()}',
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('salon-create-booking-submit-cta')),
        );
        await tester.pumpAndSettle();

        expect(
          find.text(
            formatSlotTimeRange(
              _kSlot.startAt,
              _kSlot.startAt.add(const Duration(minutes: bufferedTotalMinutes)),
            ),
          ),
          findsOneWidget,
          reason:
              'must render the SERVER endAt (with the +20 buffer), not '
              "the local re-derivation from the picked service's own "
              'duration',
        );
      },
    );

    testWidgets('«Готово» pops back to the previous screen', (tester) async {
      final router = await () async {
        final fakeSlots = _FakeSlotRepository(
          slotsByMaster: <String, List<BookingSlot>>{
            _kMasterA.masterId: <BookingSlot>[_kSlot],
          },
        );
        return _pump(tester, slotRepository: fakeSlots);
      }();
      await _driveToMasters(tester);
      await tester.tap(find.byKey(const Key('salon-master-tile-master-a')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          Key(
            'salon-tile-slot-chip-master-a-${_kSlot.startAt.toIso8601String()}',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('salon-create-booking-submit-cta')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('salon-create-booking-done-cta')));
      await tester.pumpAndSettle();

      expect(find.byType(SalonCreateBookingScreen), findsNothing);
      expect(
        router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
        '/root',
      );
    });
  });
}
