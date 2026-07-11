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

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/create_booking_request.dart';
import 'package:beautica_mobile/features/booking/domain/salon_booking_confirm_args.dart';
import 'package:beautica_mobile/features/booking/domain/salon_master_schedule.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_booking_confirm_screen.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
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
    required BookingStatus? status,
    required int page,
    int size = kBookingsPageSize,
  }) => throw UnimplementedError();

  @override
  Future<Booking> getBookingById(String id) => throw UnimplementedError();

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
  status: BookingStatus.pending,
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
          priceDisplay: '500 грн',
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

      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[bookingRepositoryProvider.overrideWithValue(repo)],
      );
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

      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[bookingRepositoryProvider.overrideWithValue(repo)],
      );
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

      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[bookingRepositoryProvider.overrideWithValue(repo)],
      );
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

      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[bookingRepositoryProvider.overrideWithValue(repo)],
      );
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
      // assertion sees ONLY the back-blocked one (one SnackBar shows at a time).
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      // Tap the top-bar back arrow — must be intercepted.
      await tester.tap(find.byKey(const Key('salon-confirm-back')));
      await tester.pump(); // schedule the SnackBar
      await tester.pump(const Duration(milliseconds: 400)); // entry animation

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

      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[bookingRepositoryProvider.overrideWithValue(repo)],
      );
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
}
