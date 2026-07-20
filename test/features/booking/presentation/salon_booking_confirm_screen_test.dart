// Phase 14.18 — Widget tests for SalonBookingConfirmScreen (salon booking
// flow step 4: review + N-booking submit).
//
// Covers the phase's confirm-screen contract:
//   1. Lists exactly ONE SalonAppointmentCard per assigned master
//      (`ValueKey('salon-confirm-appt-<masterId>')`).
//   2. The «Записатись» CTA submits every appointment; an ALL-succeed pass
//      `pushReplacement`s to the salon success route (asserted via a router
//      sentinel, not Navigator) and issues exactly one createBooking per
//      master.
//   3. A PARTIAL failure keeps the screen mounted, renders the failed
//      appointment's error inline, and flips the CTA to «Повторити»; a retry
//      re-submits only the failed one and then reaches success.
//
// Strategy: real `SalonBookingConfirmScreen` mounted under a test-local
// GoRouter that stubs the success route (capturing its `SalonBookingSuccessArgs`
// as the nav sentinel), overriding `bookingRepositoryProvider` with a
// hand-written recording fake — mirrors `booking_confirm_test.dart`.

import 'dart:async';

import 'package:dio/dio.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/create_booking_request.dart';
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
  Future<PageResponse<Booking>> getMyBookings({
    required Iterable<BookingStatus> statuses,
    BookingSort? sort,
    required int page,
    int size = kBookingsPageSize,
    Iterable<String>? serviceIds,
    DateTime? from,
    DateTime? to,
    CancelToken? cancelToken,
  }) => throw UnimplementedError();

  @override
  Future<List<DateTime>> getMyBookedDays({
    required DateTime from,
    required DateTime to,
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
}

// ---------------------------------------------------------------------------
// mobile-qa regression coverage — showSucceededStatus gate (Phase 14.18
// bugfix follow-up, see `salon_appointment_card_test.dart`'s file header for
// the full bug narrative).
//
// `_FakeBookingRepository` above resolves every call INSTANTLY (an `async`
// function with no real await), so it can never observe a mid-submit or
// mid-retry frame — every `createBooking` future is already resolved by the
// time `pumpAndSettle` (or even a single `pump`) gets a chance to look. This
// gated fake queues a `Completer` per call instead, so a test can hold a
// master's request open exactly as long as it needs to inspect the in-flight
// UI, then resolve it explicitly and only then let the pass continue.
// ---------------------------------------------------------------------------
class _GatedBookingRepository implements BookingRepository {
  final Map<String, List<Completer<Booking>>> _queue =
      <String, List<Completer<Booking>>>{};
  final List<CreateBookingRequest> requests = <CreateBookingRequest>[];

  int callsFor(String masterId) =>
      requests.where((CreateBookingRequest r) => r.masterId == masterId).length;

  @override
  Future<Booking> createBooking(CreateBookingRequest req) {
    requests.add(req);
    final Completer<Booking> completer = Completer<Booking>();
    _queue
        .putIfAbsent(req.masterId, () => <Completer<Booking>>[])
        .add(completer);
    return completer.future;
  }

  /// Resolves the OLDEST not-yet-resolved call for [masterId] as a success.
  void succeed(String masterId) {
    final Completer<Booking> completer = _queue[masterId]!.removeAt(0);
    completer.complete(
      _bookingFor(
        CreateBookingRequest(
          masterId: masterId,
          serviceId: 'assign-$masterId',
          startAt: _kStart,
          idempotencyKey: 'key-$masterId',
        ),
      ),
    );
  }

  /// Rejects the OLDEST not-yet-resolved call for [masterId] as [failure].
  void fail(String masterId, Failure failure) {
    final Completer<Booking> completer = _queue[masterId]!.removeAt(0);
    completer.completeError(failure);
  }

  @override
  Future<PageResponse<Booking>> getMyBookings({
    required Iterable<BookingStatus> statuses,
    BookingSort? sort,
    required int page,
    int size = kBookingsPageSize,
    Iterable<String>? serviceIds,
    DateTime? from,
    DateTime? to,
    CancelToken? cancelToken,
  }) => throw UnimplementedError();

  @override
  Future<List<DateTime>> getMyBookedDays({
    required DateTime from,
    required DateTime to,
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
      primaryServiceAssignmentId: 'assign-$masterId',
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
  primaryServiceAssignmentId: 'assign-$masterId',
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

/// The confirm SCREEN's own [PopScope] (the back-guard). go_router injects its
/// own PopScope as an ANCESTOR of the screen (shell-route gesture guard), so
/// scoping the finder to descendants of [SalonBookingConfirmScreen] targets
/// exactly the one the fix added — never go_router's. A widget-predicate
/// (`is PopScope`) is used rather than `byType` because the screen's PopScope
/// is a `PopScope<Object>` (T inferred from its `Object? result` callback),
/// which byType's exact-runtimeType match would miss.
PopScope<Object?> _screenPopScope(WidgetTester tester) =>
    tester.widget<PopScope<Object?>>(
      find
          .descendant(
            of: find.byType(SalonBookingConfirmScreen),
            matching: find.byWidgetPredicate((Widget w) => w is PopScope),
          )
          .first,
    );

void main() {
  testWidgets(
    'lists one appointment card per assigned master; the «Записатись» CTA '
    'submits all, pushes to the success route, and issues one createBooking '
    'per master',
    (tester) async {
      await _pumpTall(tester);
      final _FakeBookingRepository repo = _FakeBookingRepository();
      SalonBookingSuccessArgs? successArgs;
      final GoRouter router = _router(
        onReachedSuccess: (SalonBookingSuccessArgs a) => successArgs = a,
      );

      await tester.pumpRoutedApp(router, overrides: _baseOverrides(repo));
      unawaited(router.push(RouteNames.salonBookingConfirm, extra: _args()));
      await tester.pumpAndSettle();

      // One card per master.
      expect(
        find.byKey(const ValueKey<String>('salon-confirm-appt-m1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('salon-confirm-appt-m2')),
        findsOneWidget,
      );

      // Submit.
      await tester.tap(find.byKey(const Key('salon-confirm-submit-cta')));
      await tester.pumpAndSettle();

      // Reached the success route (sentinel) with both appointments.
      expect(find.text('salon-success-reached'), findsOneWidget);
      expect(successArgs, isNotNull);
      expect(successArgs!.salonId, _kSalonId);
      expect(successArgs!.appointments, hasLength(2));

      // Exactly one createBooking per master.
      expect(repo.callsFor('m1'), 1);
      expect(repo.callsFor('m2'), 1);
    },
  );

  testWidgets('a partial failure keeps the confirm screen, renders the failed '
      "appointment's error inline, flips the CTA to «Повторити», and a retry "
      'reaches success', (tester) async {
    await _pumpTall(tester);
    // m2 fails once (409); m1 succeeds.
    final _FakeBookingRepository repo = _FakeBookingRepository(
      failOnce: const <String>{'m2'},
    );
    bool reachedSuccess = false;
    final GoRouter router = _router(
      onReachedSuccess: (_) => reachedSuccess = true,
    );

    await tester.pumpRoutedApp(
      router,
      overrides: <Object>[bookingRepositoryProvider.overrideWithValue(repo)],
    );
    unawaited(router.push(RouteNames.salonBookingConfirm, extra: _args()));
    await tester.pumpAndSettle();

    final AppLocalizations l10n = AppLocalizations.of(
      tester.element(find.byType(SalonBookingConfirmScreen)),
    );

    // First submit → partial failure.
    await tester.tap(find.byKey(const Key('salon-confirm-submit-cta')));
    await tester.pumpAndSettle();

    // Stayed on the confirm screen (never claimed success).
    expect(find.byType(SalonBookingConfirmScreen), findsOneWidget);
    expect(reachedSuccess, isFalse);
    expect(find.text('salon-success-reached'), findsNothing);

    // The failed appointment surfaces its ConflictFailure copy inline.
    expect(find.text(l10n.errConflict), findsOneWidget);

    // CTA flipped to the retry label.
    final NeumorphicButton cta = tester.widget<NeumorphicButton>(
      find.byKey(const Key('salon-confirm-submit-cta')),
    );
    expect(cta.label, l10n.salonBookingRetryCta);

    // Retry: m2 now succeeds (fail-once consumed) → success.
    await tester.tap(find.byKey(const Key('salon-confirm-submit-cta')));
    await tester.pumpAndSettle();

    expect(reachedSuccess, isTrue);
    expect(find.text('salon-success-reached'), findsOneWidget);
    // m1 booked once (never re-sent); m2 booked twice (fail + retry).
    expect(repo.callsFor('m1'), 1);
    expect(repo.callsFor('m2'), 2);
  });

  // ===========================================================================
  // Back-navigation guard (security fix): once >=1 appointment's POST /bookings
  // has succeeded, both the top-bar back arrow AND OS/gesture back are BLOCKED
  // (PopScope.canPop == !hasSucceeded) and surface the l10n back-blocked
  // SnackBar. While nothing has succeeded, back is free. Asserted via the
  // router (screen present ⇒ not popped) + the screen's own PopScope, never
  // internals.
  // ===========================================================================

  testWidgets(
    'BEFORE any submit the back arrow pops the confirm screen — nothing has '
    'succeeded so PopScope.canPop is true',
    (tester) async {
      await _pumpTall(tester);
      final _FakeBookingRepository repo = _FakeBookingRepository();
      final GoRouter router = _router();

      await tester.pumpRoutedApp(router, overrides: _baseOverrides(repo));
      unawaited(router.push(RouteNames.salonBookingConfirm, extra: _args()));
      await tester.pumpAndSettle();

      // Nothing submitted → back is free.
      expect(_screenPopScope(tester).canPop, isTrue);

      await tester.tap(find.byKey(const Key('salon-confirm-back')));
      await tester.pumpAndSettle();

      // Popped back off the confirm route.
      expect(find.byType(SalonBookingConfirmScreen), findsNothing);
      // No booking was ever attempted.
      expect(repo.requests, isEmpty);
    },
  );

  testWidgets(
    'an ALL-FAILED submit (no appointment succeeded) still lets the back arrow '
    'pop — PopScope.canPop stays true',
    (tester) async {
      await _pumpTall(tester);
      // Both masters fail (once is enough — we never retry here).
      final _FakeBookingRepository repo = _FakeBookingRepository(
        failOnce: const <String>{'m1', 'm2'},
      );
      final GoRouter router = _router();

      await tester.pumpRoutedApp(router, overrides: _baseOverrides(repo));
      unawaited(router.push(RouteNames.salonBookingConfirm, extra: _args()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('salon-confirm-submit-cta')));
      await tester.pumpAndSettle();

      // Both failed → nothing succeeded → back guard stays open.
      expect(_screenPopScope(tester).canPop, isTrue);

      await tester.tap(find.byKey(const Key('salon-confirm-back')));
      await tester.pumpAndSettle();

      expect(find.byType(SalonBookingConfirmScreen), findsNothing);
    },
  );

  testWidgets(
    'after a PARTIAL SUCCESS the back arrow is blocked: it does NOT pop, shows '
    'the l10n back-blocked SnackBar, and PopScope.canPop is false',
    (tester) async {
      await _pumpTall(tester);
      // m1 succeeds, m2 fails once → hasSucceeded becomes true, screen stays.
      final _FakeBookingRepository repo = _FakeBookingRepository(
        failOnce: const <String>{'m2'},
      );
      final GoRouter router = _router();

      await tester.pumpRoutedApp(router, overrides: _baseOverrides(repo));
      unawaited(router.push(RouteNames.salonBookingConfirm, extra: _args()));
      await tester.pumpAndSettle();

      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(SalonBookingConfirmScreen)),
      );

      await tester.tap(find.byKey(const Key('salon-confirm-submit-cta')));
      await tester.pumpAndSettle();

      // One booking landed (m1) → OS/gesture back is now closed.
      expect(_screenPopScope(tester).canPop, isFalse);

      // Clear the partial-failure SnackBar the submit surfaced so the next
      // assertion sees ONLY the back-blocked one (one SnackBar shows at a
      // time). Pump until it's actually gone instead of guessing its
      // auto-dismiss duration.
      await tester.pumpUntilGone(find.byType(SnackBar));

      // Tap the top-bar back arrow — must be intercepted.
      await tester.tap(find.byKey(const Key('salon-confirm-back')));
      await tester.pumpAndSettle();

      // Did NOT pop, and the localized back-blocked SnackBar is shown.
      expect(find.byType(SalonBookingConfirmScreen), findsOneWidget);
      expect(find.text(l10n.salonBookingBackBlockedMessage), findsOneWidget);

      // The already-created m1 booking was NOT re-POSTed by the blocked back.
      expect(repo.callsFor('m1'), 1);
    },
  );

  // ===========================================================================
  // Counter isolation (perf fix): the `x / 500` counter lives in a
  // ValueListenableBuilder inside _CommentField, so typing updates ONLY the
  // counter — no screen-level setState, and the appointment cards stay put.
  // ===========================================================================

  testWidgets(
    'typing in the comment field updates the x / 500 counter while the '
    'appointment cards remain rendered (counter isolated from the card list)',
    (tester) async {
      await _pumpTall(tester);
      final _FakeBookingRepository repo = _FakeBookingRepository();
      final GoRouter router = _router();

      await tester.pumpRoutedApp(router, overrides: _baseOverrides(repo));
      unawaited(router.push(RouteNames.salonBookingConfirm, extra: _args()));
      await tester.pumpAndSettle();

      // Counter starts at zero and the counter lives in its own listenable
      // builder (the isolation boundary the fix introduced).
      expect(find.text('0 / 500'), findsOneWidget);
      expect(
        find.byType(ValueListenableBuilder<TextEditingValue>),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const Key('salon-confirm-comment-field')),
        'Дякую', // 5 characters
      );
      await tester.pump();

      // Counter reflects the input …
      expect(find.text('5 / 500'), findsOneWidget);
      expect(find.text('0 / 500'), findsNothing);
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
  // mobile-qa regression coverage (Phase 14.18 bugfix follow-up) —
  // `showSucceededStatus` gate: `_AppointmentCardSlot` must pass
  // `inFlight || hasFailures`, NOT live `hasFailures` alone. The FIRST attempt
  // gated on `hasFailures` alone, which both mobile-perf and mobile-security
  // caught as WRONG: it hid an already-succeeded master's «Заплановано» line
  // for the whole mid-submit window (nothing has failed YET partway through a
  // multi-master submit) AND for the whole mid-retry window (the retry's
  // pre-loop reset clears `hasFailures` before any network call even starts).
  //
  // These tests use `_GatedBookingRepository` (not the instant
  // `_FakeBookingRepository` every other test in this file uses) specifically
  // so the in-flight frames are actually observable — pins tests 1+2 from the
  // mobile-qa audit, which are the ones that would have FAILED against the
  // old `hasFailures`-only gate (see this session's self-check).
  // ===========================================================================
  group('showSucceededStatus gate (Phase 14.18 regression guard)', () {
    testWidgets(
      'MID-SUBMIT (N=2): once master m1\'s POST resolves but m2 is still '
      'in flight, m1\'s card shows «Заплановано» immediately — it must not '
      'wait for the whole pass to settle',
      (tester) async {
        await _pumpTall(tester);
        final _GatedBookingRepository repo = _GatedBookingRepository();
        SalonBookingSuccessArgs? successArgs;
        final GoRouter router = _router(
          onReachedSuccess: (SalonBookingSuccessArgs a) => successArgs = a,
        );

        await tester.pumpRoutedApp(router, overrides: _baseOverrides(repo));
        unawaited(router.push(RouteNames.salonBookingConfirm, extra: _args()));
        await tester.pumpAndSettle();

        final AppLocalizations l10n = AppLocalizations.of(
          tester.element(find.byType(SalonBookingConfirmScreen)),
        );
        final Finder m1Card = find.byKey(
          const ValueKey<String>('salon-confirm-appt-m1'),
        );
        final Finder m2Card = find.byKey(
          const ValueKey<String>('salon-confirm-appt-m2'),
        );

        await tester.tap(find.byKey(const Key('salon-confirm-submit-cta')));
        // One frame: the pre-loop reset marks BOTH m1/m2 `submitting` and
        // flips `inFlight` true; the loop then calls createBooking(m1), which
        // is gated (pending) — nothing has resolved yet.
        await tester.pump();

        // Resolve ONLY m1 — the loop's `await` on m1 unblocks, `_mark`s it
        // succeeded, and moves on to call createBooking(m2) (gated, pending).
        repo.succeed('m1');
        await tester.pump();
        await tester.pump();

        // The heart of the regression: m1 succeeded but the PASS has not
        // settled (m2 is still submitting) — m1's checkmark must be visible
        // NOW, not only once the whole pass finishes.
        expect(
          find.descendant(
            of: m1Card,
            matching: find.text(l10n.salonBookingAppointmentSucceeded),
          ),
          findsOneWidget,
          reason:
              'm1 already succeeded — its «Заплановано» line must render '
              'while m2 is still in flight (inFlight=true), not only once '
              'the whole submit pass settles',
        );
        expect(
          find.descendant(
            of: m2Card,
            matching: find.text(l10n.salonBookingAppointmentSubmitting),
          ),
          findsOneWidget,
          reason: 'm2 is still awaiting its own createBooking call',
        );

        // Resolve m2 too so the pass settles and the pending Completer does
        // not leak past the test.
        repo.succeed('m2');
        await tester.pumpAndSettle();

        expect(successArgs, isNotNull);
        expect(repo.callsFor('m1'), 1);
        expect(repo.callsFor('m2'), 1);
      },
    );

    testWidgets(
      'SETTLED PARTIAL FAILURE then MID-RETRY: after the first pass settles '
      'with m1 succeeded + m2 failed, m1 still shows «Заплановано» and m2 '
      'shows its error; then — the worst window — while the retry\'s POST '
      'for m2 is in flight, m1\'s «Заплановано» line MUST STAY visible '
      '(the pre-loop reset clears hasFailures atomically with inFlight=true, '
      'so the misleading hasFailures=false/inFlight=false gap is never '
      'emitted)',
      (tester) async {
        await _pumpTall(tester);
        final _GatedBookingRepository repo = _GatedBookingRepository();
        SalonBookingSuccessArgs? successArgs;
        final GoRouter router = _router(
          onReachedSuccess: (SalonBookingSuccessArgs a) => successArgs = a,
        );

        await tester.pumpRoutedApp(router, overrides: _baseOverrides(repo));
        unawaited(router.push(RouteNames.salonBookingConfirm, extra: _args()));
        await tester.pumpAndSettle();

        final AppLocalizations l10n = AppLocalizations.of(
          tester.element(find.byType(SalonBookingConfirmScreen)),
        );
        final Finder m1Card = find.byKey(
          const ValueKey<String>('salon-confirm-appt-m1'),
        );
        final Finder m2Card = find.byKey(
          const ValueKey<String>('salon-confirm-appt-m2'),
        );

        // First submit pass: m1 succeeds, m2 fails (409) — both settled.
        await tester.tap(find.byKey(const Key('salon-confirm-submit-cta')));
        await tester.pump();
        repo.succeed('m1');
        await tester.pump();
        repo.fail('m2', const ConflictFailure());
        await tester.pumpAndSettle();

        // SETTLED, PARTIAL FAILURE (item 4 of the mobile-qa audit): m1's
        // checkmark is visible AND m2's error is visible, at rest.
        expect(
          find.descendant(
            of: m1Card,
            matching: find.text(l10n.salonBookingAppointmentSucceeded),
          ),
          findsOneWidget,
          reason:
              'settled with a partial failure: hasFailures=true keeps m1\'s '
              'already-succeeded checkmark visible',
        );
        expect(
          find.descendant(of: m2Card, matching: find.text(l10n.errConflict)),
          findsOneWidget,
        );
        expect(find.byType(SalonBookingConfirmScreen), findsOneWidget);
        expect(successArgs, isNull);

        // Retry: tap «Повторити». The pre-loop reset marks m2 `submitting`
        // (clearing its failure) and flips `inFlight` true IN THE SAME
        // `copyWith` — m1 is skipped by the submit loop (already succeeded)
        // and its status never changes.
        await tester.tap(find.byKey(const Key('salon-confirm-submit-cta')));
        await tester.pump();

        // MID-RETRY (item 2 — the worst window, and the one the buggy
        // `hasFailures`-only gate got wrong: hasFailures is reset to false
        // here, before m2's retry POST has resolved). m1's checkmark must
        // still be showing.
        expect(
          find.descendant(
            of: m1Card,
            matching: find.text(l10n.salonBookingAppointmentSucceeded),
          ),
          findsOneWidget,
          reason:
              'mid-retry: hasFailures has already been reset to false for '
              'the new pass, and m2\'s retry POST has not resolved yet — '
              'inFlight=true must be what keeps m1\'s checkmark visible '
              'here, exactly the window the hasFailures-only gate got wrong',
        );
        expect(
          find.descendant(
            of: m2Card,
            matching: find.text(l10n.salonBookingAppointmentSubmitting),
          ),
          findsOneWidget,
          reason: 'm2\'s retry POST is in flight',
        );

        // Resolve the retry → settles all-succeeded → navigates to success.
        repo.succeed('m2');
        await tester.pumpAndSettle();

        expect(successArgs, isNotNull);
        expect(repo.callsFor('m1'), 1);
        expect(repo.callsFor('m2'), 2);
      },
    );
  });
}
