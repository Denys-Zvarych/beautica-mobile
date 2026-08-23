// Phase 14.18 (submit coverage reworked Phase 271; per-master card + comment
// restored 2026-08-22) — Widget tests for SalonBookingConfirmScreen (salon
// booking flow step 4: review + submit).
//
// Phase 271 deleted the restored per-master `SalonBookingSubmit` notifier and
// its bespoke `SalonAppointmentCard` — see that phase's doc for the full
// narrative. This screen still submits each appointment via the SHARED
// `AppointmentSubmit.submitVisit` (no per-master status, no retry-only-the-
// failed-ones), so every case that exercised the deleted notifier's submit/
// retry/partial-failure/back-guard behaviour through this screen was removed
// here — that UI behaviour is re-harvested when a later phase rebuilds this
// surface per service (see Phase 271 D3/D4). The 2026-08-22 pass restored the
// dedicated `SalonAppointmentCard` (WITHOUT the deleted notifier coupling)
// and gave each card its OWN comment field — see below.
//
// What remains covers the parts of the confirm-screen contract that are
// independent of submission:
//   1. Lists exactly ONE `SalonAppointmentCard` per assigned master
//      (`ValueKey('salon-confirm-appt-<masterId>')`).
//   2. The shared salon address card + «Салон» identity row + grand-total
//      card render correctly and never block on the secondary
//      `publicSalonProfileProvider` read.
//   3. Each master's OWN comment field's counter is isolated from every
//      OTHER field and from the card list — see the "comment field
//      isolation" group.
//   4. `ScreenProtectionManager` acquire/release lifecycle (SEC).
//
// Submit-path coverage (client-self-overlap dialog, per-master comment
// reaching its OWN `CreateAppointmentRequest`, generic-409 fallback) lives in
// its own group below, against `appointmentRepositoryProvider` (the provider
// this screen's `AppointmentSubmit` notifier actually calls) — NOT
// `bookingRepositoryProvider`, which `_baseOverrides` only stubs so the
// secondary salon-address read never needs a live Dio call.
//
// Strategy: real `SalonBookingConfirmScreen` mounted under a test-local
// GoRouter, overriding `bookingRepositoryProvider` with a hand-written
// recording fake (unused by the surviving cases, kept so `_baseOverrides`
// never needs a live Dio call) — mirrors `booking_confirm_test.dart`.

import 'dart:async';

import 'package:dio/dio.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/booking/data/appointment_repository.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/appointment.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_partition.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/create_appointment_request.dart';
import 'package:beautica_mobile/features/booking/domain/create_booking_request.dart';
import 'package:beautica_mobile/features/booking/domain/create_master_booking_request.dart';
import 'package:beautica_mobile/features/booking/domain/salon_booking_confirm_args.dart';
import 'package:beautica_mobile/features/booking/domain/salon_master_schedule.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_booking_confirm_screen.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/salon/application/public_salon_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_master_summary.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/pump_app.dart';

// ---------------------------------------------------------------------------
// Tall surface so both appointment cards + the comment field lay out without
// vertical overflow (mirrors salon_time_screen_test's _pumpTall).
// ---------------------------------------------------------------------------
Future<void> _pumpTall(WidgetTester tester) async {
  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

// ---------------------------------------------------------------------------
// Recording fake — fails each configured master exactly ONCE (so a retry
// pass succeeds), otherwise returns a fixture Booking.
// ---------------------------------------------------------------------------
class _FakeBookingRepository implements BookingRepository {
  _FakeBookingRepository({Set<String> failOnce = const <String>{}})
    : _failOnce = <String>{...failOnce};

  final Set<String> _failOnce;
  final List<CreateBookingRequest> requests = <CreateBookingRequest>[];

  int callsFor(String masterId) =>
      requests.where((CreateBookingRequest r) => r.masterId == masterId).length;

  @override
  Future<Booking> createBooking(CreateBookingRequest req) async {
    requests.add(req);
    if (_failOnce.remove(req.masterId)) throw const ConflictFailure();
    return _bookingFor(req);
  }

  @override
  Future<Appointment> createMasterBooking(
    String masterId,
    CreateMasterBookingRequest request,
  ) => throw UnimplementedError();

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
  Future<List<DateTime>> getMyBookedDays({
    required DateTime from,
    required DateTime to,
    CancelToken? cancelToken,
  }) => throw UnimplementedError();

  @override
  Future<Booking> getBookingById(String id) => throw UnimplementedError();

  @override
  Future<void> createReview({
    required String bookingId,
    required int rating,
    String? comment,
  }) => throw UnimplementedError();

  @override
  Future<void> cancelBooking(String id, {String? reason}) =>
      throw UnimplementedError();

  @override
  Future<Booking> rescheduleBooking(String id, DateTime newStartAt) =>
      throw UnimplementedError();

  @override
  Future<void> declineBooking(String id, {String? comment}) =>
      throw UnimplementedError();

  @override
  Future<void> completeBooking(String id) => throw UnimplementedError();
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------
final DateTime _kStart = DateTime(2026, 7, 20, 14);
const String _kSalonId = 'salon-1';

const Salon _kSalon = Salon(
  id: _kSalonId,
  name: 'Салон «Вельвет»',
  street: 'вул. Хрещатик',
  buildingNo: '22',
  city: 'Київ',
);

/// Overrides shared by every test in this file — the confirm screen's
/// secondary salon-address read must never hit a real Dio network call.
List<Object> _baseOverrides(BookingRepository repo) => <Object>[
  bookingRepositoryProvider.overrideWithValue(repo),
  publicSalonProfileProvider(
    _kSalonId,
  ).overrideWith((ref) => (_kSalon, const <SalonMasterSummary>[])),
];

Booking _bookingFor(CreateBookingRequest req) => Booking(
  id: 'booking-${req.masterId}',
  masterId: req.masterId,
  masterFirstName: 'Олена',
  masterLastName: 'Ковальчук',
  masterType: 'INDEPENDENT_MASTER',
  serviceId: req.serviceId,
  serviceName: 'Манікюр',
  durationMinutes: 60,
  price: 500,
  startAt: req.startAt,
  endAt: req.startAt.add(const Duration(minutes: 60)),
  status: BookingStatus.confirmed,
  canReview: false,
);

SalonMasterSchedule _schedule(String masterId, String firstName) =>
    SalonMasterSchedule(
      masterId: masterId,
      firstName: firstName,
      lastName: 'Ковальчук',
      type: MasterType.independentMaster,
      services: <SalonCatalogService>[
        SalonCatalogService(
          id: 'svc-$masterId',
          name: 'Манікюр',
          durationLabel: '1 год',
          priceDisplay: '500 ₴',
          durationMinutes: 60,
          priceType: ServicePriceType.fixed,
          priceMin: 500,
        ),
      ],
      orderedMasterServiceIds: <String>['assign-$masterId'],
    );

SalonBookingAppointment _appt(String masterId, String firstName) =>
    SalonBookingAppointment(
      schedule: _schedule(masterId, firstName),
      startAt: _kStart,
      idempotencyKey: 'key-$masterId',
    );

SalonBookingConfirmArgs _args() => SalonBookingConfirmArgs(
  salonId: _kSalonId,
  appointments: <SalonBookingAppointment>[
    _appt('m1', 'Олена'),
    _appt('m2', 'Софія'),
  ],
);

/// A SINGLE-appointment args fixture — for pinning that the grand-total card
/// is SUPPRESSED at N == 1 (it would just repeat that one card's own
/// subtotal).
SalonBookingConfirmArgs _singleAppointmentArgs() => SalonBookingConfirmArgs(
  salonId: _kSalonId,
  appointments: <SalonBookingAppointment>[_appt('m1', 'Олена')],
);

/// mobile-qa gap fixture: [_schedule] above carries NO rating (avgRating
/// defaults null, reviewCount defaults 0) — never exercised the shared
/// `MasterStrip`'s rating readout on THIS screen. Local to the rating/
/// per-master-recap tests below; deliberately kept separate from [_schedule]
/// so no existing assertion in this file is touched.
SalonMasterSchedule _ratedSchedule(
  String masterId,
  String firstName, {
  required double avgRating,
  required int reviewCount,
}) => SalonMasterSchedule(
  masterId: masterId,
  firstName: firstName,
  lastName: 'Ковальчук',
  type: MasterType.independentMaster,
  avgRating: avgRating,
  reviewCount: reviewCount,
  services: <SalonCatalogService>[
    SalonCatalogService(
      id: 'svc-$masterId',
      name: 'Манікюр',
      durationLabel: '1 год',
      priceDisplay: '500 ₴',
      durationMinutes: 60,
      priceType: ServicePriceType.fixed,
      priceMin: 500,
    ),
  ],
  orderedMasterServiceIds: <String>['assign-$masterId'],
);

SalonBookingAppointment _ratedAppt(
  String masterId,
  String firstName, {
  required double avgRating,
  required int reviewCount,
}) => SalonBookingAppointment(
  schedule: _ratedSchedule(
    masterId,
    firstName,
    avgRating: avgRating,
    reviewCount: reviewCount,
  ),
  startAt: _kStart,
  idempotencyKey: 'key-$masterId',
);

SalonBookingConfirmArgs _ratedArgsTwoMasters() => SalonBookingConfirmArgs(
  salonId: _kSalonId,
  appointments: <SalonBookingAppointment>[
    _ratedAppt('m1', 'Олена', avgRating: 4.6, reviewCount: 9),
    _ratedAppt('m2', 'Софія', avgRating: 4.8, reviewCount: 15),
  ],
);

/// Counts acquire()/release() calls — mirrors
/// `home_hub_supplemental_test.dart`'s identical `_CountingScreenProtection`
/// (the established pattern for pinning a PII screen's FLAG_SECURE
/// lifecycle).
class _CountingScreenProtection extends ScreenProtectionManager {
  int acquireCount = 0;
  int releaseCount = 0;

  @override
  void acquire() => acquireCount++;

  @override
  void release() => releaseCount++;

  @override
  void reset() {}
}

/// Test-local router: `/root` → (pushed) confirm → (pushReplacement) success
/// stub. The success stub captures its args as the navigation sentinel.
GoRouter _router({ValueChanged<SalonBookingSuccessArgs>? onReachedSuccess}) =>
    GoRouter(
      initialLocation: '/root',
      routes: <RouteBase>[
        GoRoute(
          path: '/root',
          builder: (context, state) => const SizedBox.shrink(),
        ),
        GoRoute(
          path: RouteNames.salonBookingConfirm,
          builder: (context, state) => SalonBookingConfirmScreen(
            args: state.extra! as SalonBookingConfirmArgs,
          ),
        ),
        GoRoute(
          path: RouteNames.salonBookingSuccess,
          builder: (context, state) {
            onReachedSuccess?.call(state.extra! as SalonBookingSuccessArgs);
            return const Scaffold(body: Text('salon-success-reached'));
          },
        ),
      ],
    );

// ---------------------------------------------------------------------------
// Submit-path fixtures — the confirm screen submits via
// `appointmentSubmitProvider` -> `AppointmentRepository.createAppointment`,
// NOT `bookingRepositoryProvider` (that one is only stubbed above so the
// secondary salon-address read never needs a live Dio call). This recording
// fake lets each test script exactly what `createAppointment` does per call,
// via [responder] — defaults to a fixture success so a test that doesn't
// care about the return value doesn't have to build one.
// ---------------------------------------------------------------------------
Appointment _apptFixtureFor(CreateAppointmentRequest req) => Appointment(
  id: 'appt-${req.masterId}',
  status: BookingStatus.confirmed,
  masterId: req.masterId,
  masterFirstName: 'Олена',
  masterLastName: 'Ковальчук',
  masterType: 'INDEPENDENT_MASTER',
  startAt: req.startAt,
  endAt: req.startAt.add(const Duration(minutes: 60)),
  totalDurationMinutes: 60,
  totalPrice: 500,
  items: <AppointmentItem>[
    AppointmentItem(
      bookingId: 'booking-${req.masterId}',
      masterServiceId: req.masterServiceIds.first,
      serviceName: 'Манікюр',
      startAt: req.startAt,
      endAt: req.startAt.add(const Duration(minutes: 60)),
      durationMinutes: 60,
      price: 500,
    ),
  ],
);

class _RecordingAppointmentRepository implements AppointmentRepository {
  _RecordingAppointmentRepository({this.responder});

  /// Called for every `createAppointment` — returns the [Appointment] to
  /// resolve with, or throws to simulate a typed [Failure]. `null` (default)
  /// always succeeds via [_apptFixtureFor].
  final FutureOr<Appointment> Function(CreateAppointmentRequest req)? responder;

  final List<CreateAppointmentRequest> requests = <CreateAppointmentRequest>[];

  List<CreateAppointmentRequest> requestsFor(String masterId) => requests
      .where((CreateAppointmentRequest r) => r.masterId == masterId)
      .toList();

  @override
  Future<Appointment> createAppointment(CreateAppointmentRequest req) async {
    requests.add(req);
    final FutureOr<Appointment> Function(CreateAppointmentRequest)? fn =
        responder;
    if (fn != null) return fn(req);
    return _apptFixtureFor(req);
  }

  @override
  Future<Appointment> getAppointment(String id) => throw UnimplementedError();

  @override
  Future<void> cancelAppointment(String id, {String? note}) =>
      throw UnimplementedError();

  @override
  Future<void> completeAppointment(String id) => throw UnimplementedError();

  @override
  Future<void> completeAppointmentService(
    String appointmentId,
    String bookingId,
  ) => throw UnimplementedError();

  @override
  Future<Appointment> rescheduleAppointmentItem(
    String appointmentId,
    String bookingId,
    DateTime newStartAt,
  ) => throw UnimplementedError();

  @override
  Future<void> declineAppointment(String id, {String? comment}) =>
      throw UnimplementedError();

  @override
  Future<void> declineAppointmentService(
    String appointmentId,
    String bookingId, {
    String? comment,
  }) => throw UnimplementedError();
}

void main() {
  // ===========================================================================
  // Counter isolation, per master (2026-08-22 — "one field per master card"):
  // each `SalonAppointmentCard` owns its OWN comment controller/field, so
  // typing in one master's field must NOT move any other master's counter.
  //
  // SUPERSEDED: this file previously pinned a SINGLE shared comment field
  // (`Key('salon-confirm-comment-field')`) whose text was sent as
  // `clientComment` for EVERY appointment, and asserted
  //   `expect(find.text('0 / 500'), findsOneWidget);` /
  //   `expect(find.byKey(const Key('salon-confirm-comment-field')), …)`.
  // That assertion is now WRONG on purpose — there is no longer a single
  // shared field to find by that key, there are TWO
  // (`salon-confirm-comment-field-m1` / `-m2`), and the whole point of this
  // rework is that they must be independent, not shared. The new assertions
  // below pin exactly that: TWO isolated `0 / 500` counters, typing in ONE
  // moves ONLY that one, and both appointment cards stay put throughout
  // (still true — the counter lives in `BookingCommentField`'s own
  // `ValueListenableBuilder`, no screen-level `setState`).
  // ===========================================================================

  testWidgets(
    "typing in one master's comment field updates ONLY that field's x / 500 "
    "counter — the two masters' fields are isolated from each other and "
    'from the card list',
    (tester) async {
      await _pumpTall(tester);
      final _FakeBookingRepository repo = _FakeBookingRepository();
      final GoRouter router = _router();

      await tester.pumpRoutedApp(router, overrides: _baseOverrides(repo));
      unawaited(router.push(RouteNames.salonBookingConfirm, extra: _args()));
      await tester.pumpAndSettle();

      // Two masters -> two independent counters, both starting at zero, each
      // living in its own listenable builder (the isolation boundary).
      expect(find.text('0 / 500'), findsNWidgets(2));
      expect(
        find.byType(ValueListenableBuilder<TextEditingValue>),
        findsNWidgets(2),
      );

      await tester.enterText(
        find.byKey(const Key('salon-confirm-comment-field-m1')),
        'Дякую', // 5 characters
      );
      await tester.pump();

      // m1's counter reflects the input …
      expect(find.text('5 / 500'), findsOneWidget);
      // … m2's counter is untouched — still zero, not overwritten.
      expect(find.text('0 / 500'), findsOneWidget);
      // … and both appointment cards are still present (never torn down).
      expect(
        find.byKey(const ValueKey<String>('salon-confirm-appt-m1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('salon-confirm-appt-m2')),
        findsOneWidget,
      );
      // No booking was triggered by typing.
      expect(repo.requests, isEmpty);
    },
  );

  // ===========================================================================
  // mobile-qa gap (salon confirm/success rework, KNOWN COVERAGE GAPS):
  //   - the shared salon-address card's real value + its loading/error
  //     fallback (must never block the appointment list rendering);
  //   - the grand-total card (renders with N > 1, suppressed at N == 1);
  //   - the shared MasterStrip's ★rating on THIS screen;
  //   - per-master services/price/subtotal actually rendering.
  // ===========================================================================

  group('salon address card', () {
    testWidgets(
      'renders the REAL resolved salon address (street/buildingNo/city) '
      'once publicSalonProfileProvider resolves',
      (tester) async {
        await _pumpTall(tester);
        final _FakeBookingRepository repo = _FakeBookingRepository();
        final GoRouter router = _router();

        await tester.pumpRoutedApp(router, overrides: _baseOverrides(repo));
        unawaited(router.push(RouteNames.salonBookingConfirm, extra: _args()));
        await tester.pumpAndSettle();

        final Finder addressCard = find.byKey(
          const Key('salon-confirm-address-card'),
        );
        expect(addressCard, findsOneWidget);
        expect(
          find.descendant(
            of: addressCard,
            // i18n-finder-ok: address is fixture data (_kSalon), not translated UI copy.
            matching: find.text('вул. Хрещатик, 22, Київ'),
          ),
          findsOneWidget,
          reason:
              'must render the resolved Salon.street/buildingNo/city, not '
              'the l10n fallback, once the secondary read succeeds',
        );
      },
    );

    testWidgets('falls back to l10n.bookingAddressUnknown WHILE '
        'publicSalonProfileProvider is still loading, and the appointment '
        'cards render anyway — the address read is secondary and must never '
        'block the screen', (tester) async {
      await _pumpTall(tester);
      final _FakeBookingRepository repo = _FakeBookingRepository();
      final GoRouter router = _router();

      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[
          bookingRepositoryProvider.overrideWithValue(repo),
          // Never resolves -> the family instance stays in AsyncLoading.
          publicSalonProfileProvider(
            _kSalonId,
          ).overrideWith((ref) => Completer<PublicSalonProfileData>().future),
        ],
      );
      unawaited(router.push(RouteNames.salonBookingConfirm, extra: _args()));
      await tester.pump();
      await tester.pump();

      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(SalonBookingConfirmScreen)),
      );
      final Finder addressCard = find.byKey(
        const Key('salon-confirm-address-card'),
      );
      expect(addressCard, findsOneWidget);
      expect(
        find.descendant(
          of: addressCard,
          matching: find.text(l10n.bookingAddressUnknown),
        ),
        findsOneWidget,
      );
      // The appointments themselves are unaffected by the secondary read.
      expect(
        find.byKey(const ValueKey<String>('salon-confirm-appt-m1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('salon-confirm-appt-m2')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('falls back to l10n.bookingAddressUnknown when '
        'publicSalonProfileProvider ERRORS, and the appointment cards still '
        'render', (tester) async {
      await _pumpTall(tester);
      final _FakeBookingRepository repo = _FakeBookingRepository();
      final GoRouter router = _router();

      await tester.pumpRoutedApp(
        router,
        // Disables Riverpod's default retry so the error stays put through
        // pumpAndSettle and leaves no pending backoff Timer at test end.
        retry: (_, _) => null,
        overrides: <Object>[
          bookingRepositoryProvider.overrideWithValue(repo),
          publicSalonProfileProvider(
            _kSalonId,
          ).overrideWith((ref) async => throw Exception('boom')),
        ],
      );
      unawaited(router.push(RouteNames.salonBookingConfirm, extra: _args()));
      await tester.pumpAndSettle();

      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(SalonBookingConfirmScreen)),
      );
      final Finder addressCard = find.byKey(
        const Key('salon-confirm-address-card'),
      );
      expect(addressCard, findsOneWidget);
      expect(
        find.descendant(
          of: addressCard,
          matching: find.text(l10n.bookingAddressUnknown),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey<String>('salon-confirm-appt-m1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('salon-confirm-appt-m2')),
        findsOneWidget,
      );
    });
  });

  // ===========================================================================
  // FEATURE A — the «Салон» identity row (l10n key `bookingSalonLabel`) renders
  // the resolved salon.name ABOVE the address, INSIDE the shared address card;
  // and when the secondary salon profile read is still loading / absent the
  // row is suppressed and the screen still renders address-only (graceful
  // fallback, no crash). Sourced from
  // `publicSalonProfileProvider(salonId).select((v) => v.value?.$1)`.
  // ===========================================================================
  group('salon name row (Feature A)', () {
    testWidgets(
      'renders the «Салон» label + resolved salon.name INSIDE the address '
      'card, positioned ABOVE the address, once the profile resolves',
      (tester) async {
        await _pumpTall(tester);
        final _FakeBookingRepository repo = _FakeBookingRepository();
        final GoRouter router = _router();

        await tester.pumpRoutedApp(router, overrides: _baseOverrides(repo));
        unawaited(router.push(RouteNames.salonBookingConfirm, extra: _args()));
        await tester.pumpAndSettle();

        final AppLocalizations l10n = AppLocalizations.of(
          tester.element(find.byType(SalonBookingConfirmScreen)),
        );
        final Finder addressCard = find.byKey(
          const Key('salon-confirm-address-card'),
        );
        final Finder salonNameRow = find.byKey(
          const Key('salon-confirm-salon-name'),
        );

        // The row lives INSIDE the shared address card.
        expect(
          find.descendant(of: addressCard, matching: salonNameRow),
          findsOneWidget,
          reason: 'the «Салон» row must render inside the address card',
        );
        // Its label is the l10n key, its value the resolved fixture name.
        expect(
          find.descendant(
            of: salonNameRow,
            matching: find.text(l10n.bookingSalonLabel),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: salonNameRow,
            // i18n-finder-ok: salon name is fixture data (_kSalon), not translated UI copy.
            matching: find.text('Салон «Вельвет»'),
          ),
          findsOneWidget,
          reason: 'the row must bind salon.name, not a placeholder',
        );

        // Positioned ABOVE the address: the salon-name row's top is higher
        // (smaller dy) than the address label's top, within the same card.
        final double salonNameTop = tester.getTopLeft(salonNameRow).dy;
        final double addressLabelTop = tester
            .getTopLeft(
              find.descendant(
                of: addressCard,
                matching: find.text(l10n.bookingAddressLabel),
              ),
            )
            .dy;
        expect(
          salonNameTop,
          lessThan(addressLabelTop),
          reason: 'the «Салон» row must sit ABOVE the address inside the card',
        );
      },
    );

    testWidgets(
      'is SUPPRESSED while the salon profile is still loading, and the screen '
      'renders address-only (fallback) with the appointment cards — no crash',
      (tester) async {
        await _pumpTall(tester);
        final _FakeBookingRepository repo = _FakeBookingRepository();
        final GoRouter router = _router();

        await tester.pumpRoutedApp(
          router,
          overrides: <Object>[
            bookingRepositoryProvider.overrideWithValue(repo),
            // Never resolves -> the family instance stays in AsyncLoading, so
            // salon (and thus salonName) is null.
            publicSalonProfileProvider(
              _kSalonId,
            ).overrideWith((ref) => Completer<PublicSalonProfileData>().future),
          ],
        );
        unawaited(router.push(RouteNames.salonBookingConfirm, extra: _args()));
        await tester.pump();
        await tester.pump();

        final AppLocalizations l10n = AppLocalizations.of(
          tester.element(find.byType(SalonBookingConfirmScreen)),
        );

        // The salon-name row is absent (no name yet) — graceful, address-only.
        expect(
          find.byKey(const Key('salon-confirm-salon-name')),
          findsNothing,
          reason:
              'while the secondary salon read is loading the «Салон» row must '
              'be suppressed rather than showing an empty/placeholder value',
        );
        // The address card still renders (with its own fallback) …
        final Finder addressCard = find.byKey(
          const Key('salon-confirm-address-card'),
        );
        expect(addressCard, findsOneWidget);
        expect(
          find.descendant(
            of: addressCard,
            matching: find.text(l10n.bookingAddressUnknown),
          ),
          findsOneWidget,
        );
        // … and the appointment cards are unaffected by the secondary read.
        expect(
          find.byKey(const ValueKey<String>('salon-confirm-appt-m1')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('salon-confirm-appt-m2')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'is SUPPRESSED when the salon profile ERRORS — screen still renders '
      'address-only with the appointment cards (no crash)',
      (tester) async {
        await _pumpTall(tester);
        final _FakeBookingRepository repo = _FakeBookingRepository();
        final GoRouter router = _router();

        await tester.pumpRoutedApp(
          router,
          retry: (_, _) => null,
          overrides: <Object>[
            bookingRepositoryProvider.overrideWithValue(repo),
            publicSalonProfileProvider(
              _kSalonId,
            ).overrideWith((ref) async => throw Exception('boom')),
          ],
        );
        unawaited(router.push(RouteNames.salonBookingConfirm, extra: _args()));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('salon-confirm-salon-name')),
          findsNothing,
          reason:
              'a failed salon read must suppress the «Салон» row, not crash',
        );
        expect(
          find.byKey(const ValueKey<String>('salon-confirm-appt-m1')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('grand-total card', () {
    testWidgets(
      'renders with the correct summed price/duration across BOTH masters '
      'when N > 1',
      (tester) async {
        await _pumpTall(tester);
        final _FakeBookingRepository repo = _FakeBookingRepository();
        final GoRouter router = _router();

        await tester.pumpRoutedApp(router, overrides: _baseOverrides(repo));
        unawaited(router.push(RouteNames.salonBookingConfirm, extra: _args()));
        await tester.pumpAndSettle();

        final Finder grandTotal = find.byKey(
          const Key('salon-confirm-grand-total-card'),
        );
        expect(grandTotal, findsOneWidget);

        // Both m1 + m2 (`_schedule`) carry ONE 500 ₴ / 60 min service each
        // -> summed total is 1000 ₴ / 2 год.
        expect(
          // i18n-finder-ok: summed price is fixture-derived data, not translated UI copy.
          find.descendant(of: grandTotal, matching: find.text('1000 ₴')),
          findsOneWidget,
        );
        expect(
          // i18n-finder-ok: summed duration is fixture-derived data, not translated UI copy.
          find.descendant(of: grandTotal, matching: find.text('2 год')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'is suppressed entirely when there is only ONE appointment (N == 1) '
      '— it would just repeat that one card\'s own subtotal',
      (tester) async {
        await _pumpTall(tester);
        final _FakeBookingRepository repo = _FakeBookingRepository();
        final GoRouter router = _router();

        await tester.pumpRoutedApp(router, overrides: _baseOverrides(repo));
        unawaited(
          router.push(
            RouteNames.salonBookingConfirm,
            extra: _singleAppointmentArgs(),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('salon-confirm-appt-m1')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('salon-confirm-grand-total-card')),
          findsNothing,
        );
      },
    );
  });

  testWidgets(
    "each appointment card's shared MasterStrip renders that master's OWN "
    '★rating(reviewCount), and the card lists its own service name/price '
    'with a matching subtotal (card-unification + information-parity gap)',
    (tester) async {
      await _pumpTall(tester);
      final _FakeBookingRepository repo = _FakeBookingRepository();
      final GoRouter router = _router();

      await tester.pumpRoutedApp(router, overrides: _baseOverrides(repo));
      unawaited(
        router.push(
          RouteNames.salonBookingConfirm,
          extra: _ratedArgsTwoMasters(),
        ),
      );
      await tester.pumpAndSettle();

      final Finder m1Card = find.byKey(
        const ValueKey<String>('salon-confirm-appt-m1'),
      );
      final Finder m2Card = find.byKey(
        const ValueKey<String>('salon-confirm-appt-m2'),
      );

      // ★rating(reviewCount) — the whole point of the card-unification
      // change: the salon confirm screen's identity card now shows it too.
      expect(
        find.descendant(of: m1Card, matching: find.text('4.6')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: m1Card, matching: find.text('(9)')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: m2Card, matching: find.text('4.8')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: m2Card, matching: find.text('(15)')),
        findsOneWidget,
      );

      // Per-master service name + price, each with a matching subtotal —
      // one service each, so its own price ("500 ₴") renders TWICE inside
      // the card: once on the service row, once on the "Разом" subtotal.
      expect(
        // i18n-finder-ok: service name is fixture data (_ratedSchedule), not translated UI copy.
        find.descendant(of: m1Card, matching: find.text('Манікюр')),
        findsOneWidget,
      );
      expect(
        // i18n-finder-ok: price is fixture-derived data, not translated UI copy.
        find.descendant(of: m1Card, matching: find.text('500 ₴')),
        findsNWidgets(2),
      );
      expect(
        // i18n-finder-ok: service name is fixture data (_ratedSchedule), not translated UI copy.
        find.descendant(of: m2Card, matching: find.text('Манікюр')),
        findsOneWidget,
      );
      expect(
        // i18n-finder-ok: price is fixture-derived data, not translated UI copy.
        find.descendant(of: m2Card, matching: find.text('500 ₴')),
        findsNWidgets(2),
      );
    },
  );

  // ===========================================================================
  // ScreenProtectionManager lifecycle (SEC — this screen renders the salon's
  // address, PII). Mirrors `home_hub_supplemental_test.dart`'s established
  // acquire/release pattern; standing backlog row notes 11 auth screens lack
  // exactly this test — this pass must not extend that debt onto the two
  // NEW salon booking screens.
  // ===========================================================================
  group('ScreenProtectionManager lifecycle', () {
    testWidgets(
      'acquire() is called exactly once when the confirm screen mounts',
      (tester) async {
        await _pumpTall(tester);
        final _FakeBookingRepository repo = _FakeBookingRepository();
        final GoRouter router = _router();
        final _CountingScreenProtection counting = _CountingScreenProtection();

        await tester.pumpRoutedApp(
          router,
          overrides: <Object>[
            ..._baseOverrides(repo),
            screenProtectionProvider.overrideWithValue(counting),
          ],
        );
        unawaited(router.push(RouteNames.salonBookingConfirm, extra: _args()));
        await tester.pumpAndSettle();

        expect(
          counting.acquireCount,
          1,
          reason:
              'initState must call acquire() exactly once to enable '
              'FLAG_SECURE for the PII-bearing salon confirm screen',
        );
      },
    );

    testWidgets(
      'release() is called exactly once when the confirm screen is popped '
      '(disposed) — acquire/release stay symmetric',
      (tester) async {
        await _pumpTall(tester);
        final _FakeBookingRepository repo = _FakeBookingRepository();
        final GoRouter router = _router();
        final _CountingScreenProtection counting = _CountingScreenProtection();

        await tester.pumpRoutedApp(
          router,
          overrides: <Object>[
            ..._baseOverrides(repo),
            screenProtectionProvider.overrideWithValue(counting),
          ],
        );
        unawaited(router.push(RouteNames.salonBookingConfirm, extra: _args()));
        await tester.pumpAndSettle();

        // Nothing submitted yet -> back is free (see the back-guard group
        // above) -> tapping it pops and disposes the screen.
        await tester.tap(find.byKey(const Key('salon-confirm-back')));
        await tester.pumpAndSettle();

        expect(
          counting.releaseCount,
          1,
          reason:
              'dispose() must call release() exactly once so FLAG_SECURE '
              'is cleared once the confirm screen is popped',
        );
        expect(counting.acquireCount, counting.releaseCount);
      },
    );
  });

  // ===========================================================================
  // SUBMIT PATH (2026-08-22): per-master comment isolation (Change B), the
  // client-self-overlap dialog (Change C), and the generic-409 fallback that
  // proves the dialog's catch is not over-broad. Against
  // `appointmentRepositoryProvider` — the provider `AppointmentSubmit
  // .submitVisit` actually calls (NOT `bookingRepositoryProvider`).
  // ===========================================================================
  group('submit path', () {
    testWidgets(
      "each master's card sends its OWN comment on submit — two masters, "
      'two distinct comment texts, each '
      "CreateAppointmentRequest.clientComment matches its OWN card's text, "
      "never the other master's",
      (tester) async {
        await _pumpTall(tester);
        final _FakeBookingRepository bookingRepo = _FakeBookingRepository();
        final _RecordingAppointmentRepository appointmentRepo =
            _RecordingAppointmentRepository();
        final GoRouter router = _router();

        await tester.pumpRoutedApp(
          router,
          overrides: <Object>[
            ..._baseOverrides(bookingRepo),
            appointmentRepositoryProvider.overrideWithValue(appointmentRepo),
          ],
        );
        unawaited(router.push(RouteNames.salonBookingConfirm, extra: _args()));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('salon-confirm-comment-field-m1')),
          'Для Олени',
        );
        await tester.enterText(
          find.byKey(const Key('salon-confirm-comment-field-m2')),
          'Для Софії',
        );
        await tester.pump();

        await tester.tap(find.byKey(const Key('salon-confirm-submit-cta')));
        await tester.pumpAndSettle();

        expect(
          appointmentRepo.requestsFor('m1').single.clientComment,
          'Для Олени',
        );
        expect(
          appointmentRepo.requestsFor('m2').single.clientComment,
          'Для Софії',
        );
      },
    );

    testWidgets(
      'a client-conflict 409 (ClientBookingConflictFailure) opens the '
      'confirmation dialog and does NOT render the bottom error banner',
      (tester) async {
        await _pumpTall(tester);
        final _FakeBookingRepository bookingRepo = _FakeBookingRepository();
        final ClientBookingConflictFailure conflict =
            ClientBookingConflictFailure(
              conflictingBookingId: 'booking-existing',
              serviceName: 'Стрижка',
              masterName: 'Ірина Бондар',
              startsAt: _kStart,
              endsAt: _kStart.add(const Duration(minutes: 45)),
            );
        final _RecordingAppointmentRepository appointmentRepo =
            _RecordingAppointmentRepository(
              responder: (CreateAppointmentRequest req) => throw conflict,
            );
        final GoRouter router = _router();

        await tester.pumpRoutedApp(
          router,
          overrides: <Object>[
            ..._baseOverrides(bookingRepo),
            appointmentRepositoryProvider.overrideWithValue(appointmentRepo),
          ],
        );
        unawaited(
          router.push(
            RouteNames.salonBookingConfirm,
            extra: _singleAppointmentArgs(),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('salon-confirm-submit-cta')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('client-booking-conflict-dialog')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('salon-confirm-submit-error')),
          findsNothing,
          reason:
              'a client-conflict 409 must open the dialog INSTEAD of the '
              'bottom error banner, per the 2026-08-22 owner decision',
        );
      },
    );

    testWidgets('dialog "proceed" resubmits THAT SAME appointment with '
        'allowClientOverlap: true, and the flow reaches success', (
      tester,
    ) async {
      await _pumpTall(tester);
      final _FakeBookingRepository bookingRepo = _FakeBookingRepository();
      final ClientBookingConflictFailure conflict =
          ClientBookingConflictFailure(
            conflictingBookingId: 'booking-existing',
            serviceName: 'Стрижка',
            masterName: 'Ірина Бондар',
            startsAt: _kStart,
            endsAt: _kStart.add(const Duration(minutes: 45)),
          );
      bool thrown = false;
      final _RecordingAppointmentRepository appointmentRepo =
          _RecordingAppointmentRepository(
            responder: (CreateAppointmentRequest req) {
              if (!thrown) {
                thrown = true;
                throw conflict;
              }
              return _apptFixtureFor(req);
            },
          );
      final GoRouter router = _router();

      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[
          ..._baseOverrides(bookingRepo),
          appointmentRepositoryProvider.overrideWithValue(appointmentRepo),
        ],
      );
      unawaited(
        router.push(
          RouteNames.salonBookingConfirm,
          extra: _singleAppointmentArgs(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('salon-confirm-submit-cta')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('client-booking-conflict-dialog')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('client-booking-conflict-proceed')),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('salon-success-reached'),
        findsOneWidget,
        reason: 'confirming the dialog must reach the success screen',
      );
      final List<CreateAppointmentRequest> m1Requests = appointmentRepo
          .requestsFor('m1');
      expect(
        m1Requests,
        hasLength(2),
        reason:
            'the first (rejected) attempt PLUS the confirmed resubmit — '
            'never a third call',
      );
      expect(
        m1Requests[0].allowClientOverlap,
        isFalse,
        reason: 'the FIRST attempt must never set the flag',
      );
      expect(
        m1Requests[1].allowClientOverlap,
        isTrue,
        reason:
            'the resubmit triggered by "Все одно записатись" must carry '
            'allowClientOverlap: true',
      );
    });

    testWidgets(
      'dialog dismiss leaves the confirm screen unchanged and submits '
      'nothing further',
      (tester) async {
        await _pumpTall(tester);
        final _FakeBookingRepository bookingRepo = _FakeBookingRepository();
        final ClientBookingConflictFailure conflict =
            ClientBookingConflictFailure(
              conflictingBookingId: 'booking-existing',
              serviceName: 'Стрижка',
              masterName: 'Ірина Бондар',
              startsAt: _kStart,
              endsAt: _kStart.add(const Duration(minutes: 45)),
            );
        final _RecordingAppointmentRepository appointmentRepo =
            _RecordingAppointmentRepository(
              responder: (CreateAppointmentRequest req) => throw conflict,
            );
        final GoRouter router = _router();

        await tester.pumpRoutedApp(
          router,
          overrides: <Object>[
            ..._baseOverrides(bookingRepo),
            appointmentRepositoryProvider.overrideWithValue(appointmentRepo),
          ],
        );
        unawaited(
          router.push(
            RouteNames.salonBookingConfirm,
            extra: _singleAppointmentArgs(),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('salon-confirm-submit-cta')));
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const Key('client-booking-conflict-dismiss')),
        );
        await tester.pumpAndSettle();

        expect(find.byType(SalonBookingConfirmScreen), findsOneWidget);
        expect(find.text('salon-success-reached'), findsNothing);
        expect(
          find.byKey(const Key('salon-confirm-submit-error')),
          findsNothing,
          reason: 'a dismissed conflict dialog must show no error banner',
        );
        expect(
          appointmentRepo.requestsFor('m1'),
          hasLength(1),
          reason: 'a dismiss must not trigger any resubmit',
        );
      },
    );

    testWidgets(
      'a GENERIC "slot not available" 409 (ConflictFailure) still shows the '
      'normal error banner and does NOT open the client-conflict dialog — '
      'proves the dialog catch is scoped to ClientBookingConflictFailure only',
      (tester) async {
        await _pumpTall(tester);
        final _FakeBookingRepository bookingRepo = _FakeBookingRepository();
        final _RecordingAppointmentRepository appointmentRepo =
            _RecordingAppointmentRepository(
              responder: (CreateAppointmentRequest req) =>
                  throw const ConflictFailure(),
            );
        final GoRouter router = _router();

        await tester.pumpRoutedApp(
          router,
          overrides: <Object>[
            ..._baseOverrides(bookingRepo),
            appointmentRepositoryProvider.overrideWithValue(appointmentRepo),
          ],
        );
        unawaited(
          router.push(
            RouteNames.salonBookingConfirm,
            extra: _singleAppointmentArgs(),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('salon-confirm-submit-cta')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('salon-confirm-submit-error')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('client-booking-conflict-dialog')),
          findsNothing,
        );
      },
    );
  });
}
