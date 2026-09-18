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
    show PhotoThumbnail, ServiceInfo;
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_cta_footer.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/slot_chip.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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

/// Both masters cover the catalogue service — used by the "covering but no
/// free time" disabled-tile tests, which need TWO rendered (non-hidden)
/// tiles to compare a bookable one against a slotless one.
Map<String, Map<String, String>> _coverageBoth() =>
    <String, Map<String, String>>{
      _kMasterA.masterId: <String, String>{_kCatalogService.id: 'assignment-a'},
      _kMasterB.masterId: <String, String>{_kCatalogService.id: 'assignment-b'},
    };

/// Phase 341 audit — an N-master roster, all covering `_kCatalogService`,
/// used to prove `SalonDateStep`'s fan-out ceiling actually truncates
/// (mirrors `_manySalonServicesCatalog`'s identical "generate N fixtures"
/// shape, for the master axis instead of the service axis).
List<SalonMasterSummary> _manySalonMasters(int n) => <SalonMasterSummary>[
  for (int i = 0; i < n; i++)
    SalonMasterSummary(
      masterId: 'master-cap-$i',
      firstName: 'Майстер',
      lastName: '$i',
      type: MasterType.salonMaster,
      reviewCount: 0,
    ),
];

/// Every master in [roster] covers `_kCatalogService` — pairs with
/// [_manySalonMasters].
Map<String, Map<String, String>> _coverageAllOf(
  List<SalonMasterSummary> roster,
) => <String, Map<String, String>>{
  for (final SalonMasterSummary m in roster)
    m.masterId: <String, String>{
      _kCatalogService.id: 'assignment-${m.masterId}',
    },
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
    this.workingDaysByMaster,
    this.workingDaysHold,
    this.workingDaysErrorMasterIds = const <String>{},
  });

  /// Keyed by masterId — different masters can return different slot lists.
  Map<String, List<BookingSlot>> slotsByMaster;

  /// 2026-09-18 — `SalonDateStep`'s per-covering-master fan-out gate (own
  /// doc: `salon_booking_wizard_steps.dart`). Keyed by masterId; `null` (the
  /// default, every pre-existing call site in this file) means "always
  /// working" for every requested date — preserves this fixture's
  /// long-standing assumption that `_kNow`'s Kyiv day (Aug 10) and every
  /// other future date in the visible month is tappable. A test proving the
  /// union/grey-out gate supplies an explicit predicate per master.
  final Map<String, bool Function(DateTime day)>? workingDaysByMaster;

  /// When set, EVERY `getWorkingDays` call awaits this before resolving (or
  /// throwing) — lets a test observe the date step's fan-out gate mid-flight
  /// (requirement 3: fail OPEN while loading).
  final Completer<void>? workingDaysHold;

  /// Master ids whose `getWorkingDays` call throws instead of resolving —
  /// proves the fail-OPEN contract on a genuine error, not merely "loading".
  final Set<String> workingDaysErrorMasterIds;

  final List<String> getMasterSlotsCalls = <String>[];

  /// One entry per `getWorkingDays` call, in call order — lets a test assert
  /// the exact per-master request COUNT the date step's fan-out issues.
  final List<String> getWorkingDaysCalls = <String>[];

  @override
  Future<List<WorkingDay>> getWorkingDays({
    required String masterId,
    required DateTime from,
    required DateTime to,
    List<String>? serviceIds,
    CancelToken? cancelToken,
  }) async {
    getWorkingDaysCalls.add(masterId);
    if (workingDaysHold != null) await workingDaysHold!.future;
    if (workingDaysErrorMasterIds.contains(masterId)) {
      throw DioException(
        requestOptions: RequestOptions(path: '/masters/$masterId/working-days'),
      );
    }
    final bool Function(DateTime)? rule = workingDaysByMaster?[masterId];
    final List<WorkingDay> days = <WorkingDay>[];
    for (
      DateTime d = from;
      !d.isAfter(to);
      d = d.add(const Duration(days: 1))
    ) {
      days.add(WorkingDay(date: d, working: rule?.call(d) ?? true));
    }
    return days;
  }

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
    required DateTime from,
    required DateTime to,
    String? masterId,
    BookingStatus? status,
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

/// Picks Aug 10 (== [_kNow]'s Kyiv "today") and taps «Далі».
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

// ---------------------------------------------------------------------------
// Rendered-selection helpers (2026-09-14 audit, QA LOW)
// ---------------------------------------------------------------------------
//
// These replace four `tester.widget<ServiceCard>(...).selected` reads. That
// read is a CONSTRUCTOR ARGUMENT: it proves the notifier handed a bool to a
// widget, never that anything on screen changed
// (`project_widget_field_assertion_is_vacuous`). Both helpers below read the
// LAID-OUT result instead:
//
//   • the painted affordance — `_SelectIndicator` swaps a hollow ring for a
//     filled `check_circle_rounded`, so the glyph's presence inside the card's
//     subtree is what the operator actually sees;
//   • the semantics tree — `ServiceCard` publishes `Semantics(selected: ...)`,
//     so a screen-reader user is told the same thing.
//
// Deliberately NOT a size assertion: the selected glyph's 26 dp box vs the
// ring's 22 is set by `_SelectIndicator` itself and would be a fair target,
// but the sibling trap this file already hit — an `AppBar.leading` tap-target
// assertion that survived mutating `NeumorphicIconButton.extent` 48 -> 40
// because the PARENT hands the slot a tight box — is the reason dimensions are
// avoided here in favour of two independent, widget-owned signals.

Finder _cardFinder(String id) => find.byKey(Key('mcb_service_card_$id'));

/// Asserts what the card RENDERS for [id], on both the paint and the
/// accessibility surface. Requires semantics to be enabled by the caller
/// (`tester.ensureSemantics()`).
void _expectRenderedSelection(
  WidgetTester tester,
  String id, {
  required bool selected,
}) {
  final Finder card = _cardFinder(id);
  expect(card, findsOneWidget, reason: 'card $id must be mounted');

  expect(
    find.descendant(
      of: card,
      matching: find.byIcon(Icons.check_circle_rounded),
    ),
    selected ? findsOneWidget : findsNothing,
    reason: selected
        ? 'card $id must PAINT the filled check glyph when selected — a '
              'hollow ring here means nothing visible changed on the tap'
        : 'card $id must paint NO check glyph when unselected',
  );

  // `ServiceCard`'s own `Semantics(selected: ...)` is `container: false`, so
  // it annotates the nearest enclosing node rather than minting one on the
  // card's key. Addressing the card key directly resolves to the ROUTE node
  // (flags: [scopesRoute]), which never carries the flag — hence the
  // descendant hop.
  //
  // `isSelected` is a `Tristate`, and `toBoolOrNull()` keeps the three states
  // apart: dropping `Semantics(selected:)` altogether yields `null`, which
  // fails against BOTH `true` and `false` instead of masquerading as
  // "unselected".
  final SemanticsNode node = tester.getSemantics(
    find.descendant(of: card, matching: find.byType(Semantics)).first,
  );
  expect(
    node.getSemanticsData().flagsCollection.isSelected.toBoolOrNull(),
    selected,
    reason:
        'card $id must publish selected=$selected into the SEMANTICS tree so '
        'a screen-reader user hears the same state the glyph shows',
  );
}

/// Counts the cards among [ids] that actually PAINT the selected check glyph.
int _renderedSelectedCount(WidgetTester tester, Iterable<String> ids) {
  int n = 0;
  for (final String id in ids) {
    if (find
        .descendant(
          of: _cardFinder(id),
          matching: find.byIcon(Icons.check_circle_rounded),
        )
        .evaluate()
        .isNotEmpty) {
      n++;
    }
  }
  return n;
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
        // _expectRenderedSelection reads the semantics tree, which is only
        // compiled while a handle is held. Disposed INSIDE the body, not via
        // addTearDown: `_endOfTestVerifications` runs before tearDowns and
        // fails the test on a still-live handle.
        final SemanticsHandle sem = tester.ensureSemantics();

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
          _expectRenderedSelection(tester, id, selected: true);
        }
        expect(tester.widget<NeumorphicButton>(next).onPressed, isNotNull);

        await tester.tap(find.byKey(const Key('mcb_service_card_salon-svc-2')));
        await tester.pump();
        _expectRenderedSelection(tester, 'salon-svc-2', selected: false);

        await tester.tap(find.byKey(const Key('mcb_service_card_salon-svc-1')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('mcb_service_card_salon-svc-3')));
        await tester.pump();
        expect(tester.widget<NeumorphicButton>(next).onPressed, isNull);

        sem.dispose();
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

        expect(
          _renderedSelectedCount(tester, <String>[
            for (int i = 0; i < 11; i++) 'salon-svc-cap-$i',
          ]),
          maxServicesPerVisit,
          reason:
              'exactly maxServicesPerVisit cards may PAINT the check glyph — '
              'the 11th add is refused, so the screen must still show ten',
        );
      },
    );

    testWidgets(
      'de-selecting still works while at the cap (the guard only fires on '
      'an ADD)',
      (tester) async {
        final SemanticsHandle sem = tester.ensureSemantics();

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

        _expectRenderedSelection(tester, 'salon-svc-cap-0', selected: false);
        expect(find.byType(VelvetSnack), findsNothing);

        sem.dispose();
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
    testWidgets('«Далі» (dateTime step) is disabled until a date is picked', (
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

    // 2026-09-18 — SalonDateStep day-level gating (fan-out + union). See
    // `salon_booking_wizard_steps.dart`'s `SalonDateStep` header for the
    // full contract this proves.
    group('day-level gating (fan-out + union)', () {
      testWidgets(
        'UNION: a day is ENABLED the moment ANY covering master confirms '
        'working it, even while the other covering master is confirmed off',
        (tester) async {
          final fakeSlots = _FakeSlotRepository(
            workingDaysByMaster: <String, bool Function(DateTime)>{
              _kMasterA.masterId: (DateTime d) => false,
              _kMasterB.masterId: (DateTime d) => d.day == 20,
            },
          );
          await _pump(
            tester,
            coverage: _coverageBoth(),
            slotRepository: fakeSlots,
          );
          await _fillClientStepAndAdvance(tester);
          await _pickService(tester);

          // Master B alone confirms working Aug 20 — the union must enable
          // it despite master A being confirmed off every day.
          // `tapCalendarDay` itself already fails loudly if the cell has no
          // tap handler (its own "HANDLER PRESENCE CHECK") — reaching the
          // `onPressed` check below proves the tap both landed AND
          // registered the selection.
          await tester.tapCalendarDay(20);
          await tester.pump();
          final NeumorphicButton nextButton = tester.widget<NeumorphicButton>(
            find.byKey(const Key('salon-create-booking-date-next')),
          );
          expect(
            nextButton.onPressed,
            isNotNull,
            reason:
                'day 20 is enabled (master B confirms working it) and '
                'must have registered as the selected date',
          );
        },
      );

      testWidgets(
        'greys out a day ONLY once EVERY covering master is CONFIRMED off '
        'it — the inverse (any-off greys it) would be backwards',
        (tester) async {
          final fakeSlots = _FakeSlotRepository(
            workingDaysByMaster: <String, bool Function(DateTime)>{
              _kMasterA.masterId: (DateTime d) => false,
              _kMasterB.masterId: (DateTime d) => false,
            },
          );
          await _pump(
            tester,
            coverage: _coverageBoth(),
            slotRepository: fakeSlots,
          );
          await _fillClientStepAndAdvance(tester);
          await _pickService(tester);
          await tester.pumpAndSettle();

          expect(
            find.descendant(
              of: find.byKey(const Key('booking-calendar-day-21')),
              matching: find.byType(GestureDetector),
            ),
            findsNothing,
            reason:
                'both covering masters are confirmed off Aug 21 — the '
                'cell must render with NO tap handler at all',
          );
        },
      );

      testWidgets(
        'zero covering masters: the calendar stays fully tappable, never an '
        'unexplained all-grey month — SalonMastersStep\'s empty state '
        'explains the "no covering master" case one step later',
        (tester) async {
          await _pump(tester, coverage: const <String, Map<String, String>>{});
          await _fillClientStepAndAdvance(tester);
          await _pickService(tester);
          await tester.pumpAndSettle();

          expect(
            find.descendant(
              of: find.byKey(const Key('booking-calendar-day-21')),
              matching: find.byType(GestureDetector),
            ),
            findsOneWidget,
            reason:
                'no master covers the whole selection — this step must '
                'stay ungated, not render an all-grey month',
          );
        },
      );

      testWidgets(
        'FAIL OPEN — while the working-days fetch is in flight every future '
        'day stays tappable; it only greys out once the fetch actually '
        'resolves all-off',
        (tester) async {
          final Completer<void> hold = Completer<void>();
          final fakeSlots = _FakeSlotRepository(
            workingDaysByMaster: <String, bool Function(DateTime)>{
              _kMasterA.masterId: (DateTime d) => false,
            },
            workingDaysHold: hold,
          );
          await _pump(tester, slotRepository: fakeSlots);
          await _fillClientStepAndAdvance(tester);
          await _pickService(tester);
          await tester.pump();

          expect(
            find.descendant(
              of: find.byKey(const Key('booking-calendar-day-21')),
              matching: find.byType(GestureDetector),
            ),
            findsOneWidget,
            reason:
                'the fetch has not resolved yet — must fail OPEN, not '
                'grey the day while data is missing',
          );

          hold.complete();
          await tester.pumpAndSettle();

          expect(
            find.descendant(
              of: find.byKey(const Key('booking-calendar-day-21')),
              matching: find.byType(GestureDetector),
            ),
            findsNothing,
            reason: 'now resolved all-off — the day may grey out',
          );
        },
      );

      testWidgets('FAIL OPEN on a genuine error — a permanently-failing '
          'getWorkingDays call never greys any day', (tester) async {
        final fakeSlots = _FakeSlotRepository(
          workingDaysErrorMasterIds: <String>{_kMasterA.masterId},
        );
        await _pump(tester, slotRepository: fakeSlots);
        await _fillClientStepAndAdvance(tester);
        await _pickService(tester);
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byKey(const Key('booking-calendar-day-21')),
            matching: find.byType(GestureDetector),
          ),
          findsOneWidget,
          reason: 'an errored covering master must never cause a grey day',
        );
      });

      testWidgets(
        'issues exactly ONE getWorkingDays request per COVERING master — '
        'never per roster entry, never duplicated on a re-render',
        (tester) async {
          final fakeSlots = _FakeSlotRepository();
          await _pump(
            tester,
            coverage: _coverageAOnly(),
            slotRepository: fakeSlots,
          );
          await _fillClientStepAndAdvance(tester);
          await _pickService(tester);
          await tester.pumpAndSettle();

          expect(
            fakeSlots.getWorkingDaysCalls,
            <String>[_kMasterA.masterId],
            reason:
                'roster has master A and B; only master A COVERS the '
                'selected service (`_coverageAOnly`) — master B must never '
                'be queried',
          );
        },
      );

      testWidgets(
        'month navigation refetches for the newly visible month without '
        'thrashing — one request per covering master per chevron tap',
        (tester) async {
          final fakeSlots2 = _FakeSlotRepository();
          await _pump(
            tester,
            coverage: _coverageAOnly(),
            slotRepository: fakeSlots2,
          );
          await _fillClientStepAndAdvance(tester);
          await _pickService(tester);
          await tester.pumpAndSettle();

          final int initialCalls = fakeSlots2.getWorkingDaysCalls.length;
          expect(initialCalls, 1, reason: 'one covering master, one request');

          await tester.tap(
            find.byKey(const Key('booking-calendar-next-month')),
          );
          await tester.pumpAndSettle();

          expect(
            fakeSlots2.getWorkingDaysCalls.length,
            initialCalls + 1,
            reason:
                'exactly one NEW request for the newly-visible month — '
                'no storm of duplicates on a single chevron tap',
          );

          // Re-tapping the SAME chevron target repeatedly (e.g. a double
          // tap landing as two gestures) must not re-fire beyond the bound
          // — `_nextMonth` no-ops past the 3-month horizon, so driving past
          // it proves no thrash rather than exercising the same month twice.
          await tester.tap(
            find.byKey(const Key('booking-calendar-next-month')),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const Key('booking-calendar-next-month')),
          );
          await tester.pumpAndSettle();
          final int afterHorizon = fakeSlots2.getWorkingDaysCalls.length;

          await tester.tap(
            find.byKey(const Key('booking-calendar-next-month')),
          );
          await tester.pumpAndSettle();
          expect(
            fakeSlots2.getWorkingDaysCalls.length,
            afterHorizon,
            reason:
                'past the 3-month horizon the chevron is disabled — no '
                'further requests fire',
          );
        },
      );

      testWidgets(
        'mobile-security MEDIUM fix (phase 341) — an uncapped covering '
        'roster is TRUNCATED to the fan-out ceiling; masters past it are '
        'never queried and the gate stays fail-open on the partial data',
        (tester) async {
          final List<SalonMasterSummary> bigRoster = _manySalonMasters(10);
          final fakeSlots = _FakeSlotRepository(
            workingDaysByMaster: <String, bool Function(DateTime)>{
              for (final SalonMasterSummary m in bigRoster)
                m.masterId: (DateTime d) => false,
            },
          );
          await _pump(
            tester,
            roster: bigRoster,
            coverage: _coverageAllOf(bigRoster),
            slotRepository: fakeSlots,
          );
          await _fillClientStepAndAdvance(tester);
          await _pickService(tester);
          await tester.pumpAndSettle();

          expect(
            fakeSlots.getWorkingDaysCalls.length,
            8,
            reason:
                '10 covering masters exceed the fan-out ceiling (8, same '
                'value as salonMasterServiceCoverageProvider\'s '
                '_kFetchChunkSize) — only the first 8 in roster order are '
                'ever queried, never all 10',
          );

          expect(
            find.descendant(
              of: find.byKey(const Key('booking-calendar-day-21')),
              matching: find.byType(GestureDetector),
            ),
            findsOneWidget,
            reason:
                'every queried covering master confirms OFF, but exceeding '
                'the cap means the subset can never prove EVERY covering '
                'master is off — the day must stay tappable, not grey on '
                'partial data',
          );
        },
      );

      testWidgets('mobile-perf LOW fix (phase 341) — a masters -> back -> date '
          'revisit within the 5-minute TTL reuses the cached working-days '
          'fetch instead of re-issuing it per covering master', (tester) async {
        final fakeSlots = _FakeSlotRepository();
        await _pump(
          tester,
          coverage: _coverageBoth(),
          slotRepository: fakeSlots,
        );
        await _driveToMasters(tester);

        expect(
          fakeSlots.getWorkingDaysCalls.length,
          2,
          reason:
              'first date-step mount: one request per covering master '
              '(N=2)',
        );

        await tester.tap(find.byKey(const Key('salon-create-booking-back')));
        await tester.pumpAndSettle();

        expect(
          fakeSlots.getWorkingDaysCalls.length,
          2,
          reason:
              'back on the date step within the TTL window must reuse '
              'the cached family members, not refetch (would be 4 '
              'without the keepAlive TTL)',
        );
      });
    });
  });

  group('SalonCreateBookingScreen — masters step (multi-master)', () {
    testWidgets(
      // 2026-09-18 real-device fix — REPLACES the old "non-covering master
      // shows «Не виконує» and is not expandable" test. Non-covering
      // masters are HIDDEN now (`SalonMastersStep` drops them before ever
      // building a tile), so there is no dimmed row left to assert on; this
      // proves the hide instead — master B's tile (and the old
      // `salonCreateBookingMasterNotOffered` copy) is entirely absent.
      'renders a tile per COVERING master only — a non-covering master is '
      'hidden entirely, not shown dimmed',
      (tester) async {
        final fakeSlots = _FakeSlotRepository(
          slotsByMaster: <String, List<BookingSlot>>{
            _kMasterA.masterId: <BookingSlot>[_kSlot],
          },
        );
        await _pump(tester, slotRepository: fakeSlots);
        await _driveToMasters(tester);

        expect(
          find.byKey(const Key('salon-master-tile-master-a')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('salon-master-tile-master-b')),
          findsNothing,
          reason:
              'master B does not cover the selected service and must '
              'not render at all, not even dimmed',
        );

        final l10n = AppLocalizations.of(
          tester.element(find.byType(SalonCreateBookingScreen)),
        );
        expect(
          find.text(l10n.salonCreateBookingMasterNotOffered),
          findsNothing,
        );
        expect(
          find.text(l10n.salonCreateBookingMasterOffers),
          findsNothing,
          reason:
              '«Виконує» is gone too — a covering, bookable master carries '
              'no pill at all now',
        );
      },
    );

    testWidgets(
      // 2026-09-18 real-device fix — was "lazily fetches ONLY on expand";
      // `_SalonMasterTile` now watches `salonMasterDaySlotsProvider`
      // EAGERLY for every covering tile (so the disabled/no-free-time face
      // is known without a tap — see `salon_booking_wizard_steps.dart`'s
      // header). What is still true, and still worth pinning: the fetch is
      // scoped to COVERING masters only (master B, non-covering, is never
      // queried — it is not even rendered), and expanding a tile never
      // re-fetches — it reads the SAME cached family entry.
      'a covering master\'s slots are fetched eagerly on mount — the other '
      '(non-covering, hidden) master is never queried, and expanding does '
      'not re-fetch',
      (tester) async {
        final fakeSlots = _FakeSlotRepository(
          slotsByMaster: <String, List<BookingSlot>>{
            _kMasterA.masterId: <BookingSlot>[_kSlot],
          },
        );
        await _pump(tester, slotRepository: fakeSlots);
        await _driveToMasters(tester);

        expect(fakeSlots.getMasterSlotsCalls, <String>['master-a']);

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
      // 2026-09-18 real-device fix — was "an empty slot list on an EXPANDED
      // tile renders the empty state" (tap first, then see the empty
      // section). A covering master with zero free time is now known
      // eagerly and renders DISABLED/collapsed with the empty-state copy
      // on its own pill; tapping it is a no-op (it can no longer be
      // expanded at all) rather than something that has to be expanded to
      // reveal the same information. "never an infinite spinner" still
      // holds — pinned the same way.
      'a covering master with zero free time renders disabled with «Немає '
      'вільного часу», never an infinite spinner, and is not tappable',
      (tester) async {
        final fakeSlots = _FakeSlotRepository(
          slotsByMaster: const <String, List<BookingSlot>>{},
        );
        await _pump(tester, slotRepository: fakeSlots);
        await _driveToMasters(tester);

        final l10n = AppLocalizations.of(
          tester.element(find.byType(SalonCreateBookingScreen)),
        );
        expect(find.text(l10n.bookingNoSlotsTitle), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);

        await tester.tap(find.byKey(const Key('salon-master-tile-master-a')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('salon-master-tile-slots-empty')),
          findsNothing,
          reason:
              'a disabled tile must never expand, so its slot section '
              'never mounts',
        );
        expect(find.byType(SlotChip), findsNothing);
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

  group(
    // 2026-09-18 real-device fix — REPLACES the old "non-covering tile is
    // NOT merely dimmed" group. A non-covering tile no longer renders at
    // all (item 4: hidden outright), so there is nothing left to assert
    // "structurally non-interactive" about — that premise is gone. The
    // disabled/non-button Semantics contract this group proved didn't go
    // away though: it moved to the tile state that inherited the dim
    // treatment (item 6, a COVERING master with no free time today), so
    // this group is repurposed to prove it there instead of being quietly
    // deleted.
    'SalonCreateBookingScreen — a covering-but-slotless tile is disabled, '
    'not merely dimmed, it is structurally non-interactive',
    () {
      testWidgets(
        'a covering master with zero free time is reported disabled/'
        'non-button via Semantics, and tapping it never renders a slot chip',
        (tester) async {
          final fakeSlots = _FakeSlotRepository(
            slotsByMaster: <String, List<BookingSlot>>{
              _kMasterA.masterId: <BookingSlot>[_kSlot],
              // master B deliberately absent — empty slots, same as the
              // real salon's reported masters with no free time left.
            },
          );
          await _pump(
            tester,
            coverage: _coverageBoth(),
            slotRepository: fakeSlots,
          );
          await _driveToMasters(tester);

          final Finder tile = find.byKey(
            const Key('salon-master-tile-master-b'),
          );
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
                'a covering-but-slotless tile must report itself as a '
                'disabled non-button to assistive tech, not just render '
                'faded',
          );

          await tester.tap(tile);
          await tester.pumpAndSettle();

          expect(
            find.descendant(of: tile, matching: find.byType(SlotChip)),
            findsNothing,
            reason:
                'tapping a covering-but-slotless tile must never expand a '
                'slot section',
          );

          // Control — master A (has a free slot) stays a normal enabled
          // button, proving the disabled state above is genuinely keyed on
          // free-time, not a blanket effect from the fixture.
          final Finder tileA = find.byKey(
            const Key('salon-master-tile-master-a'),
          );
          expect(
            find.descendant(
              of: tileA,
              matching: find.byWidgetPredicate(
                (Widget w) =>
                    w is Semantics &&
                    w.properties.button == true &&
                    w.properties.enabled == true,
              ),
            ),
            findsOneWidget,
          );
        },
      );
    },
  );

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

  // ── Phase 323 — THE OTHER ServiceCard CONSUMER KEEPS ITS PHOTO WELL ───────
  //
  // `ServiceCard.showPhoto` is additive and defaults to `true`, and
  // `services_list_screen.dart` is the ONE caller that opts out. This wizard's
  // picker (`booking_wizard_steps.dart:629`) is the only other real consumer
  // in `lib/`, and nothing pinned its side of that contract.
  //
  // Why the default-value test in
  // `test/features/services/presentation/widgets/service_category_list_test.dart`
  // is NOT enough: that case constructs a bare [ServiceCard] itself, so it
  // catches a flipped DEFAULT and nothing else. Adding `showPhoto: false` at
  // the wizard's own call site — a one-token edit, and the obvious one for
  // anyone copying the services page's reclaim across — leaves it green.
  //
  // Asserted from the LAID-OUT render tree, never from
  // `.widget<ServiceCard>(...).showPhoto`
  // (`project_widget_field_assertion_is_vacuous`): a field read passes even if
  // the Row drops the well.
  group('Phase 323 — the wizard picker keeps the leading photo well', () {
    testWidgets(
      'a salon-catalogue service card renders a 40 dp PhotoThumbnail and its '
      'name column starts 58 dp inside the card (8 inset + 40 well + 10 gap)',
      (tester) async {
        await _pump(tester);
        await _fillClientStepAndAdvance(tester);

        final Finder card = find.byKey(
          const Key('mcb_service_card_salon-svc-1'),
        );
        expect(
          card,
          findsOneWidget,
          reason:
              'anti-vacuity — nothing below means anything if the picker '
              'card never rendered',
        );

        final Finder well = find.descendant(
          of: card,
          matching: find.byType(PhotoThumbnail),
        );
        expect(
          well,
          findsOneWidget,
          reason:
              'the picker is SCANNED rather than read, and the leading well '
              'anchors the selectable row against its trailing check '
              'indicator — this consumer must never inherit the services '
              "page's `showPhoto: false`",
        );
        expect(
          tester.getSize(well),
          const Size(40, 40),
          reason:
              'present-but-collapsed is the failure mode a findsOneWidget '
              'check alone cannot see',
        );

        // The gap is the other half of the 50 dp the services page reclaims,
        // so a half-applied opt-out here (well dropped, gap kept, or vice
        // versa) has to fail too.
        final double indent =
            tester
                .getTopLeft(
                  find.descendant(of: card, matching: find.byType(ServiceInfo)),
                )
                .dx -
            tester.getTopLeft(card).dx;
        expect(
          indent,
          58.0,
          reason:
              "8 dp card inset + 40 dp well + 10 dp gap. The services page's "
              'opt-out drops the last two together (50 dp); this consumer '
              'keeps both.',
        );
      },
    );
  });
}
