// Track 27.x/MO-6 — regression: the PROVIDER footer on «Деталі запису» for a
// booking that is part of a multi-service VISIT (`Booking.appointmentId !=
// null`).
//
// BUG (original, now fixed): `_confirmComplete`/`_confirmDecline` always
// called the per-booking `BookingRepository.completeBooking`/`declineBooking`,
// regardless of `appointmentId`. The backend's `assertNotAppointmentChild`
// guard 409s EVERY per-booking provider transition once
// `booking.appointment != null` (`"This booking is part of a multi-service
// visit; use /appointments/{id} to change it"`) — every master's card tap
// still lands each service of a visit on ITS OWN single-booking detail screen
// (`master_bookings_screen.dart`), so this screen legitimately shows an
// appointment-child booking and must route its writes to the whole-visit
// endpoints instead.
//
// Track 27.x/MO-6 follow-up, cut over to per-item by track 30.x: the backend
// gained `PATCH /appointments/{id}/services/{bookingId}/reschedule`, so
// «Перенести» is RE-ENABLED here too (previously hidden — see the git history
// of this file for the old guard) — tapping it now routes through the SAME
// `startBookingReschedule` (`reschedule_navigation.dart`) the plain
// single-booking case uses, just with `appointmentId` also passed through, so
// the confirm-step submit calls the per-item endpoint instead of the
// per-booking one.
//
// This suite pins:
//   • complete on an appointment-child booking calls
//     `AppointmentRepository.completeAppointmentService(appointmentId,
//     bookingId)` — the PER-SERVICE visit endpoint
//     (`PATCH /appointments/{id}/services/{bookingId}/complete`), completing
//     ONLY the tapped service and leaving the visit's siblings CONFIRMED —
//     NEVER the whole-visit `completeAppointment` (which completed every
//     service at once, guarding only the VISIT's `startsAt` so not-yet-started
//     siblings were closed too — the CRITICAL bug this fixes) and NEVER
//     `BookingRepository.completeBooking`;
//   • decline on an appointment-child booking calls
//     `AppointmentRepository.declineAppointmentService(appointmentId,
//     bookingId, comment: ...)` — the PER-SERVICE visit endpoint
//     (`PATCH /appointments/{id}/services/{bookingId}/decline`), declining
//     ONLY the tapped service and leaving the visit's siblings CONFIRMED —
//     NEVER the whole-visit `declineAppointment` (which used to decline every
//     service at once — the CRITICAL bug this fixes) and NEVER
//     `BookingRepository.declineBooking`, on BOTH a not-yet-started and an
//     elapsed (`hasStarted`) booking, since the backend allows a provider
//     decline at any time;
//   • «Перенести» (reschedule) is SHOWN on an appointment-child booking, same
//     key as the single-booking case, and routes through
//     `startBookingReschedule` WITHOUT ever calling
//     `AppointmentRepository.getAppointment` (track 30.x retired the earlier
//     whole-visit `startAppointmentReschedule` flow that used to resolve the
//     visit that way);
//   • REGRESSION GUARD — a plain single-service booking (`appointmentId ==
//     null`) is UNCHANGED: it still calls the per-booking endpoints and still
//     offers «Перенести» (mirrors `booking_detail_provider_footer_test.dart`,
//     kept here too so this file alone proves the branch both ways).
//
// Finders are key-first; all copy is asserted through l10n, never a raw
// Cyrillic literal (CI no-raw-string gate).

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/application/booking_detail_notifier.dart';
import 'package:beautica_mobile/features/booking/data/appointment_repository.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_slot_picker_args.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/master/application/public_master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/booking_fixture_dates.dart';
import '../../../helpers/pump_app.dart';

class _MockBookingRepository extends Mock implements BookingRepository {}

class _MockAppointmentRepository extends Mock
    implements AppointmentRepository {}

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
}

class _StubAuth extends AuthNotifier {
  _StubAuth(this._session);

  final AuthSession _session;

  @override
  Future<AuthSession> build() async => _session;
}

User _providerUser() => const User(
  id: 'u1',
  email: 'master@e.com',
  role: UserRole.independentMaster,
);

/// A CONFIRMED, not-yet-started booking. [appointmentId] non-null marks it as
/// one service of a multi-service visit — the exact condition
/// `assertNotAppointmentChild` guards against on the backend.
Booking _booking({String? appointmentId, String id = 'b1'}) {
  final DateTime start = futureBookingStart();
  const int durationMinutes = 90;
  return Booking(
    id: id,
    masterId: 'm1',
    masterFirstName: 'Марія',
    masterLastName: 'Іванюк',
    masterType: 'INDEPENDENT_MASTER',
    clientId: 'c1',
    clientFirstName: 'Олена',
    clientLastName: 'Ковальчук',
    serviceId: 's1',
    serviceName: 'Манікюр з покриттям',
    durationMinutes: durationMinutes,
    price: 650,
    startAt: start,
    endAt: start.add(const Duration(minutes: durationMinutes)),
    status: BookingStatus.confirmed,
    canReview: false,
    masterProfessionalTitle: 'Майстриня манікюру',
    appointmentId: appointmentId,
  );
}

List<Object> _overrides(
  Booking booking,
  _MockBookingRepository bookingRepo,
  _MockAppointmentRepository appointmentRepo,
) => <Object>[
  screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
  bookingRepositoryProvider.overrideWithValue(bookingRepo),
  appointmentRepositoryProvider.overrideWithValue(appointmentRepo),
  bookingDetailProvider(booking.id).overrideWith((ref) async => booking),
  authProvider.overrideWith(
    () => _StubAuth(
      AuthSession.authenticated(user: _providerUser(), accessToken: 't'),
    ),
  ),
];

Future<void> _pumpDetail(
  WidgetTester tester,
  Booking booking, {
  required _MockBookingRepository bookingRepo,
  required _MockAppointmentRepository appointmentRepo,
}) async {
  await tester.pumpApp(
    BookingDetailScreen(bookingId: booking.id),
    overrides: _overrides(booking, bookingRepo, appointmentRepo),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    registerFallbackValue(BookingStatus.confirmed);
    registerFallbackValue(<BookingStatus>{});
    registerFallbackValue(BookingSort.oldest);
  });

  // -------------------------------------------------------------------------
  // Footer content — «Перенести» now SHOWN on an appointment-child booking too
  // (track 27.x/MO-6 — previously hidden, see this file's header)
  // -------------------------------------------------------------------------

  group('footer content', () {
    testWidgets(
      'appointment-child booking: reschedule + decline both offered',
      (tester) async {
        final Booking booking = _booking(appointmentId: 'appt-1');
        final bookingRepo = _MockBookingRepository();
        final appointmentRepo = _MockAppointmentRepository();

        await _pumpDetail(
          tester,
          booking,
          bookingRepo: bookingRepo,
          appointmentRepo: appointmentRepo,
        );

        expect(find.byKey(const Key('booking-detail-decline')), findsOneWidget);
        expect(
          find.byKey(const Key('booking-detail-provider-reschedule')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'REGRESSION GUARD — a plain single-service booking still offers '
      'reschedule + decline',
      (tester) async {
        final Booking booking = _booking();
        final bookingRepo = _MockBookingRepository();
        final appointmentRepo = _MockAppointmentRepository();

        await _pumpDetail(
          tester,
          booking,
          bookingRepo: bookingRepo,
          appointmentRepo: appointmentRepo,
        );

        expect(
          find.byKey(const Key('booking-detail-provider-reschedule')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('booking-detail-decline')), findsOneWidget);
      },
    );
  });

  // -------------------------------------------------------------------------
  // Reschedule routing (track 30.x — cut over from the whole-VISIT flow) —
  // tapping «Перенести» on an appointment-child booking routes through the
  // SAME `startBookingReschedule` a plain single-service booking uses, in
  // BOTH cases resolving via `bookingDetailProvider` +
  // `publicMasterProfileProvider` — never `AppointmentRepository
  // .getAppointment`, which only the retired whole-visit flow ever called.
  // -------------------------------------------------------------------------

  group('reschedule routing', () {
    const Master master = Master(
      id: 'm1',
      firstName: 'Марія',
      lastName: 'Іванюк',
      avgRating: 4.9,
      reviewCount: 12,
      type: MasterType.independentMaster,
    );

    const MasterService service = MasterService(
      id: 's1',
      serviceDefId: 'def-s1',
      name: 'Манікюр з покриттям',
      durationMinutes: 90,
      priceMin: 650,
      priceDisplay: '650 ₴',
      category: 'NAILS',
    );

    /// Pumps [BookingDetailScreen] inside a real `GoRouter` (required for
    /// `context.push` inside `startBookingReschedule`) whose
    /// `RouteNames.bookingSlots` route is a probe — reaching it proves the
    /// reschedule flow navigated. The 2nd element of the returned record
    /// captures the pushed [BookingSlotPickerArgs] (`state.extra`) so a
    /// caller can assert on the exact `(rescheduleAppointmentId,
    /// rescheduleBookingId)` pair `context.push` carried — merely proving
    /// navigation happened would pass even if `_onReschedule` silently
    /// dropped `appointmentId`, degrading a visit-item move to a plain
    /// single-booking reschedule (mobile-qa F3 regression guard).
    Future<(bool Function(), BookingSlotPickerArgs? Function())> pumpRouted(
      WidgetTester tester,
      Booking booking, {
      required _MockBookingRepository bookingRepo,
      required _MockAppointmentRepository appointmentRepo,
    }) async {
      bool navigated = false;
      BookingSlotPickerArgs? lastArgs;
      final GoRouter router = GoRouter(
        initialLocation: '/detail',
        routes: <RouteBase>[
          GoRoute(
            path: '/detail',
            builder: (_, _) => BookingDetailScreen(bookingId: booking.id),
          ),
          GoRoute(
            path: RouteNames.bookingSlots,
            builder: (_, GoRouterState state) {
              navigated = true;
              lastArgs = state.extra as BookingSlotPickerArgs?;
              return const Scaffold(key: Key('slots_stub'));
            },
          ),
        ],
      );
      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[
          ..._overrides(booking, bookingRepo, appointmentRepo),
          publicMasterProfileProvider(
            booking.masterId,
          ).overrideWith((ref) async => (master, <MasterService>[service])),
        ],
      );
      await tester.pumpAndSettle();
      return (() => navigated, () => lastArgs);
    }

    testWidgets(
      'appointment-child booking: reschedule tap navigates to the slot '
      'picker WITHOUT calling AppointmentRepository.getAppointment — the '
      'per-item endpoint is resolved at CONFIRM time, not seed time',
      (tester) async {
        final Booking booking = _booking(appointmentId: 'appt-1');
        final bookingRepo = _MockBookingRepository();
        final appointmentRepo = _MockAppointmentRepository();

        final (
          bool Function() navigated,
          BookingSlotPickerArgs? Function() lastArgs,
        ) = await pumpRouted(
          tester,
          booking,
          bookingRepo: bookingRepo,
          appointmentRepo: appointmentRepo,
        );

        await tester.tap(
          find.byKey(const Key('booking-detail-provider-reschedule')),
        );
        await tester.pumpAndSettle();

        expect(navigated(), isTrue);
        expect(find.byKey(const Key('slots_stub')), findsOneWidget);
        verifyNever(() => appointmentRepo.getAppointment(any()));

        // mobile-qa F3 — the regression this guards: a dropped
        // `appointmentId: booking.appointmentId` in `_onReschedule` would
        // still navigate (so `navigated()`/`slots_stub` alone can't catch
        // it) but would silently degrade this to a plain single-booking
        // reschedule. Assert the exact pushed pair instead.
        final BookingSlotPickerArgs? args = lastArgs();
        expect(args, isNotNull);
        expect(args!.rescheduleAppointmentId, 'appt-1');
        expect(args.rescheduleBookingId, booking.id);
      },
    );

    testWidgets(
      'REGRESSION GUARD — a plain single-service booking still routes '
      'through the per-booking reschedule flow, never '
      'AppointmentRepository.getAppointment',
      (tester) async {
        final Booking booking = _booking();
        final bookingRepo = _MockBookingRepository();
        final appointmentRepo = _MockAppointmentRepository();

        final (
          bool Function() navigated,
          BookingSlotPickerArgs? Function() lastArgs,
        ) = await pumpRouted(
          tester,
          booking,
          bookingRepo: bookingRepo,
          appointmentRepo: appointmentRepo,
        );

        await tester.tap(
          find.byKey(const Key('booking-detail-provider-reschedule')),
        );
        await tester.pumpAndSettle();

        expect(navigated(), isTrue);
        verifyNever(() => appointmentRepo.getAppointment(any()));

        // A plain single-service booking must carry a NULL
        // rescheduleAppointmentId — this is what discriminates it from the
        // per-item visit path above.
        final BookingSlotPickerArgs? args = lastArgs();
        expect(args, isNotNull);
        expect(args!.rescheduleAppointmentId, isNull);
        expect(args.rescheduleBookingId, booking.id);
      },
    );
  });

  // -------------------------------------------------------------------------
  // Decline routing
  // -------------------------------------------------------------------------

  group('decline routing', () {
    testWidgets('appointment-child booking: decline calls '
        'AppointmentRepository.declineAppointmentService(appointmentId, '
        'bookingId) — only THIS service — never the whole-visit '
        'declineAppointment nor BookingRepository.declineBooking', (
      tester,
    ) async {
      final Booking booking = _booking(appointmentId: 'appt-1');
      final bookingRepo = _MockBookingRepository();
      final appointmentRepo = _MockAppointmentRepository();
      when(
        () => appointmentRepo.declineAppointmentService(
          any(),
          any(),
          comment: any(named: 'comment'),
        ),
      ).thenAnswer((_) async {});

      await _pumpDetail(
        tester,
        booking,
        bookingRepo: bookingRepo,
        appointmentRepo: appointmentRepo,
      );

      await tester.tap(find.byKey(const Key('booking-detail-decline')));
      await tester.pumpAndSettle();
      // The dialog reads as a single-service action (only this booking is
      // declined; the visit's siblings stay CONFIRMED).
      expect(find.byKey(const Key('decline-booking-dialog')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('cancel-booking-note-field')),
        'Майстер захворів.',
      );
      await tester.tap(find.byKey(const Key('decline-booking-confirm')));
      await tester.pumpAndSettle();

      verify(
        () => appointmentRepo.declineAppointmentService(
          'appt-1',
          'b1',
          comment: 'Майстер захворів.',
        ),
      ).called(1);
      verifyNever(
        () => appointmentRepo.declineAppointment(
          any(),
          comment: any(named: 'comment'),
        ),
      );
      verifyNever(
        () => bookingRepo.declineBooking(any(), comment: any(named: 'comment')),
      );
    });

    testWidgets('REGRESSION GUARD — a plain single-service booking still calls '
        'BookingRepository.declineBooking, never the appointment endpoint', (
      tester,
    ) async {
      final Booking booking = _booking();
      final bookingRepo = _MockBookingRepository();
      final appointmentRepo = _MockAppointmentRepository();
      when(
        () => bookingRepo.declineBooking(any(), comment: any(named: 'comment')),
      ).thenAnswer((_) async {});

      await _pumpDetail(
        tester,
        booking,
        bookingRepo: bookingRepo,
        appointmentRepo: appointmentRepo,
      );

      await tester.tap(find.byKey(const Key('booking-detail-decline')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('decline-booking-confirm')));
      await tester.pumpAndSettle();

      verify(
        () => bookingRepo.declineBooking(booking.id, comment: null),
      ).called(1);
      verifyNever(
        () => appointmentRepo.declineAppointmentService(
          any(),
          any(),
          comment: any(named: 'comment'),
        ),
      );
    });
  });

  // -------------------------------------------------------------------------
  // Complete routing
  // -------------------------------------------------------------------------

  group('complete routing', () {
    /// A CONFIRMED booking that has started (so «Завершити» is offered).
    Booking startedBooking({String? appointmentId}) {
      final DateTime start = DateTime.now().toUtc().subtract(
        const Duration(minutes: 5),
      );
      return Booking(
        id: 'b1',
        masterId: 'm1',
        masterFirstName: 'Марія',
        masterLastName: 'Іванюк',
        masterType: 'INDEPENDENT_MASTER',
        clientId: 'c1',
        clientFirstName: 'Олена',
        clientLastName: 'Ковальчук',
        serviceId: 's1',
        serviceName: 'Манікюр з покриттям',
        durationMinutes: 90,
        price: 650,
        startAt: start,
        endAt: start.add(const Duration(minutes: 90)),
        status: BookingStatus.confirmed,
        canReview: false,
        masterProfessionalTitle: 'Майстриня манікюру',
        appointmentId: appointmentId,
      );
    }

    // 2026-08-17 CRITICAL fix — this assertion was INVERTED on purpose. It
    // used to pin the WHOLE-VISIT `completeAppointment(appointmentId)`, which
    // is exactly the bug: that endpoint completes every sibling of the visit
    // in lockstep and evaluates its temporal guard against the VISIT's
    // `startsAt` (the FIRST service), so completing from this screen also
    // completed siblings whose own start had not arrived. Complete now routes
    // per-item like decline (`declineAppointmentService`) and reschedule
    // (`rescheduleAppointmentItem`) already did.
    testWidgets('appointment-child booking: complete calls '
        'AppointmentRepository.completeAppointmentService(appointmentId, '
        'bookingId) — never the whole-visit completeAppointment, never '
        'BookingRepository.completeBooking', (tester) async {
      final Booking booking = startedBooking(appointmentId: 'appt-1');
      final bookingRepo = _MockBookingRepository();
      final appointmentRepo = _MockAppointmentRepository();
      when(
        () => appointmentRepo.completeAppointmentService(any(), any()),
      ).thenAnswer((_) async {});

      await _pumpDetail(
        tester,
        booking,
        bookingRepo: bookingRepo,
        appointmentRepo: appointmentRepo,
      );

      await tester.tap(find.byKey(const Key('booking-detail-complete')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('complete-booking-dialog')), findsOneWidget);

      await tester.tap(find.byKey(const Key('complete-booking-confirm')));
      await tester.pumpAndSettle();

      verify(
        () => appointmentRepo.completeAppointmentService('appt-1', booking.id),
      ).called(1);
      // The lockstep endpoint must never be reached again from this screen.
      verifyNever(() => appointmentRepo.completeAppointment(any()));
      verifyNever(() => bookingRepo.completeBooking(any()));
    });

    testWidgets('REGRESSION GUARD — a plain single-service booking still calls '
        'BookingRepository.completeBooking, never the appointment endpoint', (
      tester,
    ) async {
      final Booking booking = startedBooking();
      final bookingRepo = _MockBookingRepository();
      final appointmentRepo = _MockAppointmentRepository();
      when(
        () => bookingRepo.completeBooking(booking.id),
      ).thenAnswer((_) async {});

      await _pumpDetail(
        tester,
        booking,
        bookingRepo: bookingRepo,
        appointmentRepo: appointmentRepo,
      );

      await tester.tap(find.byKey(const Key('booking-detail-complete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('complete-booking-confirm')));
      await tester.pumpAndSettle();

      verify(() => bookingRepo.completeBooking(booking.id)).called(1);
      verifyNever(() => appointmentRepo.completeAppointment(any()));
      verifyNever(
        () => appointmentRepo.completeAppointmentService(any(), any()),
      );
    });
  });

  // -------------------------------------------------------------------------
  // Decline routing on an ELAPSED appointment-child booking — the backend
  // allows a provider decline at any time, so «Скасувати» stays offered (and
  // routes the same way) once Booking.hasStarted, not just before.
  // -------------------------------------------------------------------------

  group('decline routing on an elapsed booking', () {
    /// A CONFIRMED booking that has started (so «Завершити»/«Скасувати» are
    /// offered).
    Booking startedBooking({String? appointmentId}) {
      final DateTime start = DateTime.now().toUtc().subtract(
        const Duration(minutes: 5),
      );
      return Booking(
        id: 'b1',
        masterId: 'm1',
        masterFirstName: 'Марія',
        masterLastName: 'Іванюк',
        masterType: 'INDEPENDENT_MASTER',
        clientId: 'c1',
        clientFirstName: 'Олена',
        clientLastName: 'Ковальчук',
        serviceId: 's1',
        serviceName: 'Манікюр з покриттям',
        durationMinutes: 90,
        price: 650,
        startAt: start,
        endAt: start.add(const Duration(minutes: 90)),
        status: BookingStatus.confirmed,
        canReview: false,
        masterProfessionalTitle: 'Майстриня манікюру',
        appointmentId: appointmentId,
      );
    }

    testWidgets('appointment-child booking: decline on an elapsed booking '
        'calls AppointmentRepository.declineAppointmentService(appointmentId, '
        'bookingId) — only THIS service — never the whole-visit '
        'declineAppointment nor BookingRepository.declineBooking', (
      tester,
    ) async {
      final Booking booking = startedBooking(appointmentId: 'appt-1');
      final bookingRepo = _MockBookingRepository();
      final appointmentRepo = _MockAppointmentRepository();
      when(
        () => appointmentRepo.declineAppointmentService(
          any(),
          any(),
          comment: any(named: 'comment'),
        ),
      ).thenAnswer((_) async {});

      await _pumpDetail(
        tester,
        booking,
        bookingRepo: bookingRepo,
        appointmentRepo: appointmentRepo,
      );

      // Both actions are offered on an elapsed CONFIRMED visit.
      expect(find.byKey(const Key('booking-detail-complete')), findsOneWidget);
      expect(find.byKey(const Key('booking-detail-decline')), findsOneWidget);
      // «Перенести» is OMITTED on an elapsed appointment-child booking too
      // — `_providerActions`' `hasStartedAt(now)` branch gates on the
      // booking alone, never on `appointmentId`, mirroring the
      // plain-booking underway/past case asserted in
      // `booking_detail_provider_footer_test.dart`. USER-LOCKED REVERSAL
      // (this session) of the previously-pinned visible-but-inert shape.
      expect(
        find.byKey(const Key('booking-detail-provider-reschedule')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('booking-detail-reschedule-unavailable-reason')),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('booking-detail-decline')));
      await tester.pumpAndSettle();
      // The dialog reads as a single-service action (only this booking is
      // declined; the visit's siblings stay CONFIRMED).
      expect(find.byKey(const Key('decline-booking-dialog')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('cancel-booking-note-field')),
        'Клієнт не прийшов.',
      );
      await tester.tap(find.byKey(const Key('decline-booking-confirm')));
      await tester.pumpAndSettle();

      verify(
        () => appointmentRepo.declineAppointmentService(
          'appt-1',
          'b1',
          comment: 'Клієнт не прийшов.',
        ),
      ).called(1);
      verifyNever(
        () => appointmentRepo.declineAppointment(
          any(),
          comment: any(named: 'comment'),
        ),
      );
      verifyNever(
        () => bookingRepo.declineBooking(any(), comment: any(named: 'comment')),
      );
    });

    testWidgets('REGRESSION GUARD — a plain single-service elapsed booking '
        'still calls BookingRepository.declineBooking, never the appointment '
        'endpoint', (tester) async {
      final Booking booking = startedBooking();
      final bookingRepo = _MockBookingRepository();
      final appointmentRepo = _MockAppointmentRepository();
      when(
        () => bookingRepo.declineBooking(any(), comment: any(named: 'comment')),
      ).thenAnswer((_) async {});

      await _pumpDetail(
        tester,
        booking,
        bookingRepo: bookingRepo,
        appointmentRepo: appointmentRepo,
      );

      await tester.tap(find.byKey(const Key('booking-detail-decline')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('decline-booking-confirm')));
      await tester.pumpAndSettle();

      verify(
        () => bookingRepo.declineBooking(booking.id, comment: null),
      ).called(1);
      verifyNever(
        () => appointmentRepo.declineAppointmentService(
          any(),
          any(),
          comment: any(named: 'comment'),
        ),
      );
    });
  });
}
