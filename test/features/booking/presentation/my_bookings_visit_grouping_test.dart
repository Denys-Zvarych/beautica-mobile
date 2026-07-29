// MO-7 — widget suite for the «Мої записи» PER-SERVICE rendering.
//
// Product decision (locked 2026-07-26): «Мої записи» no longer collapses a
// multi-service visit's rows into one grouped card. A 2-service visit now
// renders as TWO ordinary `BookingCard`s — indistinguishable from any other
// single-service booking, no «Візит · 1 з 2» badge, no shared header — each
// acting on its OWN booking. This file replaces the old MO-5 grouping suite
// (`groupBookingsByAppointment` / `VisitBookingEntry` / `VisitCard` are all
// deleted).
//
// Proves the acceptance criteria:
//   • a visit's rows (sharing an `appointmentId`) each render their OWN
//     `BookingCard`, in the server's `startAt` order — no grouping, no visit
//     chrome;
//   • tapping ANY row — visit leg or legacy standalone — pushes the SAME
//     single-booking detail route, `/bookings/:bookingId`, keyed off that
//     row's own id;
//   • cancelling a visit leg from «Деталі запису» calls
//     `BookingRepository.cancelBooking(leg.id, ...)` — the per-booking
//     endpoint — never any appointment-level cancel; the ONLY thing that
//     used to stand between an appointment-child booking and
//     `BookingDetailScreen` was the grouped `VisitCard` indirection, and that
//     indirection is gone by design (see `my_bookings_screen.dart`'s file
//     header).
//
// Finders are key-first / type-first; status copy is asserted through l10n.

import 'package:beautica_mobile/core/network/page_response.dart';
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
import 'package:beautica_mobile/features/booking/domain/booking_display_x.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/booking_tab.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/my_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_card.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/booking_fixture_dates.dart';
import '../../../helpers/pump_app.dart';

class _StubAuth extends AuthNotifier {
  _StubAuth(this._session);

  final AuthSession _session;

  @override
  Future<AuthSession> build() async => _session;
}

/// The visit's day, anchored to the real wall clock — see
/// `test/helpers/booking_fixture_dates.dart` for the time-bomb this avoids.
DateTime _atTenUtc(DateTime d) => DateTime.utc(d.year, d.month, d.day, 10);

final DateTime _visitStart = _atTenUtc(futureBookingStart());
final DateTime _visitSecondStart = _visitStart.add(const Duration(hours: 1));
final DateTime _legacyStart = _visitStart.add(const Duration(days: 1));

class _MockBookingRepository extends Mock implements BookingRepository {}

class _MockAppointmentRepository extends Mock
    implements AppointmentRepository {}

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
}

Booking _b({
  required String id,
  String? appointmentId,
  String serviceName = 'Манікюр',
  int durationMinutes = 60,
  double price = 300,
  double? priceMax,
  DateTime? startAt,
}) {
  final DateTime start = startAt ?? _visitStart;
  return Booking(
    id: id,
    masterId: 'm1',
    masterFirstName: 'Марія',
    masterLastName: 'Іванюк',
    masterAvatarUrl: null,
    masterType: 'INDEPENDENT_MASTER',
    salonName: null,
    serviceId: 's-$id',
    serviceName: serviceName,
    categoryName: 'Манікюр',
    cityLabel: 'Львів',
    districtLabel: null,
    street: null,
    buildingNo: null,
    durationMinutes: durationMinutes,
    price: price,
    priceMax: priceMax,
    startAt: start,
    endAt: start.add(Duration(minutes: durationMinutes)),
    status: BookingStatus.confirmed,
    canReview: false,
    clientComment: null,
    providerComment: null,
    clientCancellationNote: null,
    masterProfessionalTitle: null,
    locationNote: null,
    appointmentId: appointmentId,
  );
}

PageResponse<Booking> _page(List<Booking> items) => PageResponse<Booking>(
  items: items,
  page: 0,
  totalPages: 1,
  totalElements: items.length,
);

void _stubAllTabs(
  _MockBookingRepository repo, {
  List<Booking> upcoming = const <Booking>[],
}) {
  when(
    () => repo.getMyBookings(
      statuses: BookingTab.upcoming.statuses,
      sort: BookingSort.oldest,
      page: any(named: 'page'),
      size: any(named: 'size'),
    ),
  ).thenAnswer((_) async => _page(upcoming));
  for (final BookingTab tab in <BookingTab>[
    BookingTab.past,
    BookingTab.cancelled,
  ]) {
    when(
      () => repo.getMyBookings(
        statuses: tab.statuses,
        sort: BookingSort.newest,
        page: any(named: 'page'),
        size: any(named: 'size'),
      ),
    ).thenAnswer((_) async => _page(const <Booking>[]));
  }
}

/// A router whose leaf route is a stub recording its resolved location, so a
/// card tap's `context.push` target is observable.
GoRouter _router(
  _MockBookingRepository repo, {
  required void Function(String) onLocation,
}) {
  return GoRouter(
    initialLocation: '/bookings',
    routes: <RouteBase>[
      GoRoute(
        path: '/bookings',
        builder: (_, _) => const MyBookingsScreen(),
        routes: <RouteBase>[
          GoRoute(
            path: ':bookingId',
            builder: (BuildContext context, GoRouterState state) {
              onLocation(state.uri.toString());
              return const Scaffold(key: Key('booking_stub'));
            },
          ),
        ],
      ),
    ],
  );
}

void main() {
  // Two rows of the SAME visit (sharing appt-1) + one legacy standalone row —
  // the exact dataset the old grouping suite used, now asserting NO grouping.
  final List<Booking> visitAndLegacy = <Booking>[
    _b(
      id: 'v1',
      appointmentId: 'appt-1',
      serviceName: 'Манікюр',
      durationMinutes: 60,
      price: 300,
      startAt: _visitStart,
    ),
    _b(
      id: 'v2',
      appointmentId: 'appt-1',
      serviceName: 'Педикюр',
      durationMinutes: 90,
      price: 200,
      priceMax: 400,
      startAt: _visitSecondStart,
    ),
    _b(id: 'legacy-1', serviceName: 'Стрижка', startAt: _legacyStart),
  ];

  Future<void> pumpScreen(
    WidgetTester tester,
    _MockBookingRepository repo, {
    required void Function(String) onLocation,
  }) async {
    await tester.pumpRoutedApp(
      _router(repo, onLocation: onLocation),
      overrides: <Object>[
        bookingRepositoryProvider.overrideWithValue(repo),
        screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
      ],
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'a 2-service visit renders TWO plain BookingCards — no grouping, no '
    'visit chrome — alongside the legacy card',
    (tester) async {
      final repo = _MockBookingRepository();
      _stubAllTabs(repo, upcoming: visitAndLegacy);

      await pumpScreen(tester, repo, onLocation: (_) {});

      // Three rows in, three ordinary BookingCards out — the visit's two legs
      // are NOT collapsed into one.
      expect(find.byType(BookingCard), findsNWidgets(3));
      expect(find.byKey(const ValueKey<String>('v1')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('v2')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('legacy-1')), findsOneWidget);

      // Each leg shows its OWN service name and price — no summed "N послуг"
      // count, no shared visit total.
      // i18n-finder-ok: service name is injected fixture data, locale-invariant
      expect(find.text('Манікюр'), findsOneWidget);
      // i18n-finder-ok: service name is injected fixture data, locale-invariant
      expect(find.text('Педикюр'), findsOneWidget);
      // i18n-finder-ok: service name is injected fixture data, locale-invariant
      expect(find.text('Стрижка'), findsOneWidget);

      // Each leg's PRICE and TIME anchors carry its OWN figures — v2's price
      // is a genuine RANGE (300 was never its price), v1's is a flat figure,
      // and the two legs start an hour apart. Nothing here is a sum or a
      // shared visit total — `BookingCard` has no such concept. Scoped by
      // KEY (not a bare `find.text`) because `legacy-1` deliberately shares
      // v1's flat "300 ₴" figure in this fixture — a global text finder would
      // be ambiguous; reading the keyed widget's own `data` proves THIS
      // card's anchor, regardless of what any other card happens to show.
      for (final Booking b in visitAndLegacy) {
        final Text priceText = tester.widget<Text>(
          find.byKey(ValueKey<String>('price-${b.id}')),
        );
        expect(
          priceText.data,
          b.priceLabel,
          reason: '${b.id} must render its OWN priceLabel (${b.priceLabel})',
        );
        final Text timeText = tester.widget<Text>(
          find.byKey(ValueKey<String>('time-${b.id}')),
        );
        expect(
          timeText.data,
          formatSlotTime(b.startAt),
          reason: '${b.id} must render its OWN start time',
        );
      }
      // v1 and v2 do NOT share a price — proves neither leg is showing the
      // other's (or a summed) figure.
      expect(visitAndLegacy[0].priceLabel, isNot(visitAndLegacy[1].priceLabel));
    },
  );

  testWidgets(
    'the visit legs render in startAt order, correctly interleaved among '
    'other bookings — the server sort alone does the work',
    (tester) async {
      final repo = _MockBookingRepository();
      _stubAllTabs(repo, upcoming: visitAndLegacy);

      await pumpScreen(tester, repo, onLocation: (_) {});

      final List<Element> cards = tester
          .elementList(find.byType(BookingCard))
          .toList();
      final List<String> renderedOrder = <String>[
        for (final Element e in cards) (e.widget as BookingCard).booking.id,
      ];
      expect(renderedOrder, <String>['v1', 'v2', 'legacy-1']);
    },
  );

  testWidgets(
    'tapping a visit leg pushes /bookings/:bookingId keyed off ITS OWN id, '
    'exactly like a legacy card',
    (tester) async {
      final repo = _MockBookingRepository();
      _stubAllTabs(repo, upcoming: visitAndLegacy);

      String? location;
      await pumpScreen(tester, repo, onLocation: (String l) => location = l);

      await tester.tap(find.byKey(const ValueKey<String>('v2')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('booking_stub')), findsOneWidget);
      expect(location, '/bookings/v2');
    },
  );

  // ===========================================================================
  // MO-7 — cancelling a visit leg from «Деталі запису» routes to the
  // PER-BOOKING `cancelBooking`, never an appointment-level cancel, and never
  // touches the visit's sibling. The backend's old `assertNotAppointmentChild`
  // 409 guard on `PATCH /bookings/{id}/cancel` is gone (backend `1d1d524`) —
  // the endpoint now cancels ONLY the targeted leg and recomputes the
  // appointment header server-side.
  // ===========================================================================

  List<Object> clientOverrides(
    _MockBookingRepository repo,
    _MockAppointmentRepository appointmentRepo,
  ) => <Object>[
    bookingRepositoryProvider.overrideWithValue(repo),
    appointmentRepositoryProvider.overrideWithValue(appointmentRepo),
    screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
    authProvider.overrideWith(
      () => _StubAuth(
        const AuthSession.authenticated(
          user: User(id: 'c1', email: 'c@e.com', role: UserRole.client),
          accessToken: 't',
        ),
      ),
    ),
  ];

  testWidgets(
    'CLIENT cancels ONE visit leg — routes to BookingRepository.cancelBooking '
    '(the per-booking endpoint), never AppointmentRepository.cancelAppointment, '
    'and never touches the sibling leg\'s own id',
    (tester) async {
      final Booking leg = _b(id: 'v1', appointmentId: 'appt-1');
      final repo = _MockBookingRepository();
      final appointmentRepo = _MockAppointmentRepository();
      when(
        () => repo.cancelBooking(any(), reason: any(named: 'reason')),
      ).thenAnswer((_) async {});

      await tester.pumpApp(
        const BookingDetailScreen(bookingId: 'v1'),
        overrides: <Object>[
          ...clientOverrides(repo, appointmentRepo),
          bookingDetailProvider('v1').overrideWith((ref) async => leg),
        ],
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('booking-detail-cancel')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('cancel-booking-note-field')),
        'Захворіла, вибачте.',
      );
      await tester.tap(find.byKey(const Key('cancel-booking-confirm')));
      await tester.pumpAndSettle();

      verify(
        () => repo.cancelBooking('v1', reason: 'Захворіла, вибачте.'),
      ).called(1);
      verifyNever(
        () =>
            appointmentRepo.cancelAppointment(any(), note: any(named: 'note')),
      );
      // The sibling leg ('v2') is never a party to this write — a per-card
      // cancel must act on exactly the ONE id it was opened for, proving the
      // visit's other service stays untouched (and, by extension, CONFIRMED).
      verifyNever(() => repo.cancelBooking('v2', reason: any(named: 'reason')));
    },
  );
}
