// Track 27.x/MO-6 — regression: the PROVIDER footer on «Деталі запису» for a
// booking that is part of a multi-service VISIT (`Booking.appointmentId !=
// null`).
//
// BUG: `_confirmComplete`/`_confirmDecline` always called the per-booking
// `BookingRepository.completeBooking`/`declineBooking`, regardless of
// `appointmentId`. The backend's `assertNotAppointmentChild` guard 409s EVERY
// per-booking provider transition once `booking.appointment != null`
// (`"This booking is part of a multi-service visit; use /appointments/{id}
// to change it"`) — every master's card tap still lands each service of a
// visit on ITS OWN single-booking detail screen (`master_bookings_screen
// .dart`), so this screen legitimately shows an appointment-child booking and
// must route its writes to the whole-visit endpoints instead.
//
// This suite pins:
//   • complete on an appointment-child booking calls
//     `AppointmentRepository.completeAppointment(appointmentId)`, NEVER
//     `BookingRepository.completeBooking`;
//   • decline on an appointment-child booking calls
//     `AppointmentRepository.declineAppointment(appointmentId, comment: ...)`,
//     NEVER `BookingRepository.declineBooking`;
//   • «Перенести» (reschedule) is HIDDEN on an appointment-child booking — no
//     provider-facing `/appointments/{id}/reschedule` endpoint exists;
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
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
  // Footer content — «Перенести» hidden on an appointment-child booking
  // -------------------------------------------------------------------------

  group('footer content', () {
    testWidgets('appointment-child booking: decline only, reschedule hidden', (
      tester,
    ) async {
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
        findsNothing,
      );
    });

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
  // Decline routing
  // -------------------------------------------------------------------------

  group('decline routing', () {
    testWidgets('appointment-child booking: decline calls '
        'AppointmentRepository.declineAppointment(appointmentId), never '
        'BookingRepository.declineBooking', (tester) async {
      final Booking booking = _booking(appointmentId: 'appt-1');
      final bookingRepo = _MockBookingRepository();
      final appointmentRepo = _MockAppointmentRepository();
      when(
        () => appointmentRepo.declineAppointment(
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
      // The dialog reads as a whole-visit action, not a single-booking one.
      expect(find.byKey(const Key('decline-booking-dialog')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('cancel-booking-note-field')),
        'Майстер захворів.',
      );
      await tester.tap(find.byKey(const Key('decline-booking-confirm')));
      await tester.pumpAndSettle();

      verify(
        () => appointmentRepo.declineAppointment(
          'appt-1',
          comment: 'Майстер захворів.',
        ),
      ).called(1);
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
        () => appointmentRepo.declineAppointment(
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

    testWidgets('appointment-child booking: complete calls '
        'AppointmentRepository.completeAppointment(appointmentId), never '
        'BookingRepository.completeBooking', (tester) async {
      final Booking booking = startedBooking(appointmentId: 'appt-1');
      final bookingRepo = _MockBookingRepository();
      final appointmentRepo = _MockAppointmentRepository();
      when(
        () => appointmentRepo.completeAppointment(any()),
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

      verify(() => appointmentRepo.completeAppointment('appt-1')).called(1);
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
    });
  });
}
