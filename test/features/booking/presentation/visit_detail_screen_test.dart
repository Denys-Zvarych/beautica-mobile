// MO-5 — behavioural suite for [VisitDetailScreen].
//
// Proves the acceptance criteria:
//   • the screen loads via the REAL `appointmentDetail` provider over a fake
//     `getAppointment` and renders the multi-service recap (ordered items, one
//     window, one summed total);
//   • «Скасувати запис» → dialog → confirm calls
//     `AppointmentRepository.cancelAppointment` (the visit path) and NEVER the
//     per-booking `BookingRepository.cancelBooking`;
//   • the review CTA on a COMPLETED + canReview visit routes to the APPOINTMENT
//     review path `/bookings/visit/:appointmentId/review` carrying the
//     appointmentId (MO-6 completes the screen).
//
// Finders are key-first; copy is asserted through l10n where it is app copy.

import 'dart:async';

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/booking/data/appointment_repository.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/appointment.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/visit_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_summary_cards.dart';
import 'package:beautica_mobile/features/home/application/home_hub_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/booking_fixture_dates.dart';
import '../../../helpers/pump_app.dart';

class _MockAppointmentRepository extends Mock
    implements AppointmentRepository {}

class _MockBookingRepository extends Mock implements BookingRepository {}

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
}

AppointmentItem _item({
  required String bookingId,
  required String serviceName,
  int durationMinutes = 60,
  double price = 300,
  double? priceMax,
  DateTime? startAt,
}) {
  final DateTime start = startAt ?? futureBookingStart();
  return AppointmentItem(
    bookingId: bookingId,
    masterServiceId: 'ms-$bookingId',
    serviceName: serviceName,
    startAt: start,
    endAt: start.add(Duration(minutes: durationMinutes)),
    durationMinutes: durationMinutes,
    price: price,
    priceMax: priceMax,
  );
}

Appointment _appointment({
  String id = 'appt-1',
  BookingStatus status = BookingStatus.confirmed,
  bool canReview = false,
  List<AppointmentItem>? items,
  DateTime? start,
}) {
  final DateTime visitStart = start ?? futureBookingStart();
  final List<AppointmentItem> visitItems =
      items ??
      <AppointmentItem>[
        _item(
          bookingId: 'b1',
          serviceName: 'Манікюр',
          durationMinutes: 60,
          price: 300,
          startAt: visitStart,
        ),
        _item(
          bookingId: 'b2',
          serviceName: 'Педикюр',
          durationMinutes: 90,
          price: 350,
          startAt: visitStart.add(const Duration(minutes: 60)),
        ),
      ];
  return Appointment(
    id: id,
    status: status,
    masterId: 'm1',
    masterFirstName: 'Марія',
    masterLastName: 'Іванюк',
    masterProfessionalTitle: 'Майстриня манікюру',
    masterAvatarUrl: null,
    masterType: 'INDEPENDENT_MASTER',
    salonName: null,
    startAt: visitItems.first.startAt,
    endAt: visitItems.last.endAt,
    totalDurationMinutes: visitItems.fold<int>(
      0,
      (int s, AppointmentItem i) => s + i.durationMinutes,
    ),
    totalPrice: visitItems.fold<double>(
      0,
      (double s, AppointmentItem i) => s + i.price,
    ),
    totalPriceMax: null,
    items: visitItems,
    canReview: canReview,
    clientComment: null,
    providerComment: null,
    clientCancellationNote: null,
    cityLabel: 'Львів',
    districtLabel: null,
    street: 'вул. Городоцька',
    buildingNo: '12',
    locationNote: null,
    createdAt: null,
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(BookingStatus.confirmed);
  });

  testWidgets('loads via fake getAppointment and renders the visit recap', (
    tester,
  ) async {
    final repo = _MockAppointmentRepository();
    when(
      () => repo.getAppointment('appt-1'),
    ).thenAnswer((_) async => _appointment());

    await tester.pumpApp(
      const VisitDetailScreen(appointmentId: 'appt-1'),
      overrides: <Object>[
        screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
        appointmentRepositoryProvider.overrideWithValue(repo),
      ],
    );
    await tester.pumpAndSettle();

    // The real `appointmentDetail` provider fetched via the fake.
    verify(() => repo.getAppointment('appt-1')).called(1);

    // The multi-service recap: both ordered items + one summed total.
    expect(find.byType(BookingSummaryCards), findsOneWidget);
    // i18n-finder-ok: service name is injected fixture data, locale-invariant
    expect(find.text('Манікюр'), findsOneWidget);
    // i18n-finder-ok: service name is injected fixture data, locale-invariant
    expect(find.text('Педикюр'), findsOneWidget);
    // Summed total 300 + 350 = 650 (single price, no band).
    expect(find.text('650 ₴'), findsWidgets);
  });

  testWidgets('shows a loading indicator while getAppointment is pending', (
    tester,
  ) async {
    final repo = _MockAppointmentRepository();
    final Completer<Appointment> pending = Completer<Appointment>();
    when(() => repo.getAppointment('appt-1')).thenAnswer((_) => pending.future);

    await tester.pumpApp(
      const VisitDetailScreen(appointmentId: 'appt-1'),
      overrides: <Object>[
        screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
        appointmentRepositoryProvider.overrideWithValue(repo),
      ],
    );
    // A single frame — the fetch is still in flight, so the async is loading.
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(BookingSummaryCards), findsNothing);

    // Let it complete so the pending timer/future does not leak past the test.
    pending.complete(_appointment());
    await tester.pumpAndSettle();
    expect(find.byType(BookingSummaryCards), findsOneWidget);
  });

  testWidgets('error state renders a retry button; retry reloads the visit', (
    tester,
  ) async {
    final repo = _MockAppointmentRepository();
    when(() => repo.getAppointment('appt-1')).thenThrow(Exception('boom'));

    await tester.pumpApp(
      const VisitDetailScreen(appointmentId: 'appt-1'),
      overrides: <Object>[
        screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
        appointmentRepositoryProvider.overrideWithValue(repo),
      ],
    );
    await tester.pumpAndSettle();

    // The fetch failed → the error state with its retry affordance, no recap.
    expect(find.byKey(const Key('visit-detail-error-retry')), findsOneWidget);
    expect(find.byType(BookingSummaryCards), findsNothing);

    // The backend recovers; retry re-invalidates the provider → a fresh fetch.
    when(
      () => repo.getAppointment('appt-1'),
    ).thenAnswer((_) async => _appointment());

    await tester.tap(find.byKey(const Key('visit-detail-error-retry')));
    await tester.pumpAndSettle();

    // The retry re-fetched and the recap now renders in place of the error.
    expect(find.byType(BookingSummaryCards), findsOneWidget);
    expect(find.byKey(const Key('visit-detail-error-retry')), findsNothing);
  });

  testWidgets('visit cancel calls cancelAppointment, never cancelBooking, and '
      'invalidates nextAppointmentProvider', (tester) async {
    // mobile-qa (Phase 225 fix pass, mobile-perf MEDIUM #4) —
    // nextAppointmentProvider is overridden with its OWN fetch counter (a
    // FutureProvider override, independent of either repository) so the
    // assertion is a direct proof the invalidation at
    // `visit_detail_screen.dart:153` actually fires, not an inference from
    // a repository call count. This visit's first service may have been
    // the client's soonest upcoming appointment.
    int nextApptFetches = 0;
    final apptRepo = _MockAppointmentRepository();
    final bookingRepo = _MockBookingRepository();
    when(
      () => apptRepo.getAppointment('appt-1'),
    ).thenAnswer((_) async => _appointment());
    when(
      () => apptRepo.cancelAppointment(any(), note: any(named: 'note')),
    ).thenAnswer((_) async {});

    await tester.pumpApp(
      const VisitDetailScreen(appointmentId: 'appt-1'),
      overrides: <Object>[
        screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
        appointmentRepositoryProvider.overrideWithValue(apptRepo),
        bookingRepositoryProvider.overrideWithValue(bookingRepo),
        nextAppointmentProvider.overrideWith((ref) async {
          nextApptFetches++;
          return null;
        }),
      ],
    );
    await tester.pumpAndSettle();

    // Hold a LIVE subscription so the invalidate below triggers a genuine
    // refetch instead of Riverpod simply dropping an unwatched autoDispose
    // member.
    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(VisitDetailScreen)),
      listen: false,
    );
    final ProviderSubscription<AsyncValue<Booking?>> subNextAppt = container
        .listen(nextAppointmentProvider, (_, _) {}, fireImmediately: true);
    addTearDown(subNextAppt.close);
    await container.read(nextAppointmentProvider.future);
    expect(nextApptFetches, 1);

    // Open the destructive confirmation.
    await tester.tap(find.byKey(const Key('visit-detail-cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cancel-visit-dialog')), findsOneWidget);

    // Confirm (the shared destructive button key).
    await tester.tap(find.byKey(const Key('cancel-booking-confirm')));
    await tester.pumpAndSettle();

    // The visit path — cancelAppointment with the (blank → null) note.
    verify(() => apptRepo.cancelAppointment('appt-1', note: null)).called(1);
    // NEVER the single-booking cancel on a child.
    verifyNever(
      () => bookingRepo.cancelBooking(any(), reason: any(named: 'reason')),
    );

    await container.read(nextAppointmentProvider.future);
    expect(
      nextApptFetches,
      2,
      reason:
          'a successful visit cancel must invalidate nextAppointmentProvider '
          '— the Home Hub card must never show a stale booking after this '
          'write',
    );
  });

  // ---------------------------------------------------------------------
  // canReview gates the review CTA independently of status — mirrors
  // `booking_detail_screen_test.dart`'s identical group.
  //
  // Regression guard for the fix: a CONFIRMED visit that aged into «Минулі»
  // purely by elapsed time (never marked COMPLETED by the provider — there
  // is no auto-complete job) must still offer «Залишити відгук» the moment
  // the server says `canReview: true`. Before the fix, the review CTA lived
  // only inside `case BookingStatus.completed`, so this exact scenario
  // silently dropped the button. `canReview` alone decides — never `status`
  // — per `Appointment.canReview`'s doc.
  // ---------------------------------------------------------------------

  group('canReview gates the review CTA independently of status', () {
    testWidgets(
      'an ELAPSED CONFIRMED visit with canReview:true shows review + rebook '
      '(the bug this fix closes — an unclosed provider-side visit must '
      'still be reviewable)',
      (tester) async {
        final repo = _MockAppointmentRepository();
        when(() => repo.getAppointment('appt-1')).thenAnswer(
          (_) async => _appointment(
            status: BookingStatus.confirmed,
            canReview: true,
            // A fixed firmly-past instant — deterministic, never becomes
            // "upcoming" again. Mirrors the booking-side elapsed fixture.
            start: DateTime.utc(2000, 1, 1),
          ),
        );

        await tester.pumpApp(
          const VisitDetailScreen(appointmentId: 'appt-1'),
          overrides: <Object>[
            screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
            appointmentRepositoryProvider.overrideWithValue(repo),
          ],
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('visit-detail-leave-review')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('visit-detail-rebook')), findsOneWidget);
      },
    );

    testWidgets(
      'an ELAPSED CONFIRMED visit with canReview:false shows rebook ONLY '
      '(unchanged behaviour — e.g. already reviewed)',
      (tester) async {
        final repo = _MockAppointmentRepository();
        when(() => repo.getAppointment('appt-1')).thenAnswer(
          (_) async => _appointment(
            status: BookingStatus.confirmed,
            canReview: false,
            start: DateTime.utc(2000, 1, 1),
          ),
        );

        await tester.pumpApp(
          const VisitDetailScreen(appointmentId: 'appt-1'),
          overrides: <Object>[
            screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
            appointmentRepositoryProvider.overrideWithValue(repo),
          ],
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('visit-detail-leave-review')),
          findsNothing,
        );
        expect(find.byKey(const Key('visit-detail-rebook')), findsOneWidget);
      },
    );

    testWidgets(
      'a FUTURE CONFIRMED visit shows cancel and NO review CTA — guards '
      'against the hoist leaking a CTA into the upcoming state',
      (tester) async {
        final repo = _MockAppointmentRepository();
        when(() => repo.getAppointment('appt-1')).thenAnswer(
          (_) async => _appointment(
            status: BookingStatus.confirmed,
            // canReview is deliberately NOT set true here — the server never
            // sends it true for an upcoming visit — but this test must still
            // hold even if that contract were violated, since the hoist must
            // not be the thing enforcing it.
            // future-date-ok: fixed far-future instant, deliberate — the
            // "not elapsed" twin of the fixed firmly-past instant above.
            start: DateTime.utc(2999, 1, 1),
          ),
        );

        await tester.pumpApp(
          const VisitDetailScreen(appointmentId: 'appt-1'),
          overrides: <Object>[
            screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
            appointmentRepositoryProvider.overrideWithValue(repo),
          ],
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('visit-detail-cancel')), findsOneWidget);
        expect(
          find.byKey(const Key('visit-detail-leave-review')),
          findsNothing,
        );
      },
    );
  });

  testWidgets(
    'review CTA on a completed visit routes to the appointment review path',
    (tester) async {
      final repo = _MockAppointmentRepository();
      when(() => repo.getAppointment('appt-1')).thenAnswer(
        (_) async =>
            _appointment(status: BookingStatus.completed, canReview: true),
      );

      String? reviewLocation;
      final router = GoRouter(
        initialLocation: '/bookings/visit/appt-1',
        routes: <RouteBase>[
          GoRoute(
            path: '/bookings/visit/:appointmentId',
            builder: (BuildContext context, GoRouterState state) =>
                VisitDetailScreen(
                  appointmentId: state.pathParameters['appointmentId']!,
                ),
            routes: <RouteBase>[
              GoRoute(
                path: 'review',
                builder: (BuildContext context, GoRouterState state) {
                  reviewLocation = state.uri.toString();
                  return const Scaffold(key: Key('visit_review_stub'));
                },
              ),
            ],
          ),
        ],
      );

      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[
          screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
          appointmentRepositoryProvider.overrideWithValue(repo),
        ],
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('visit-detail-leave-review')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('visit_review_stub')), findsOneWidget);
      expect(reviewLocation, '/bookings/visit/appt-1/review');
    },
  );
}
