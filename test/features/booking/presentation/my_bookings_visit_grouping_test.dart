// MO-5 — widget suite for the «Мої записи» VISIT grouping + routing.
//
// Proves the acceptance criteria:
//   • a 2-item visit (rows sharing an appointmentId) renders ONE grouped
//     `VisitCard` — services list, summed duration, price band, one time,
//     status — while a legacy standalone booking still renders its own
//     `BookingCard`;
//   • tapping the visit card pushes `/bookings/visit/:appointmentId` (the
//     appointment detail), tapping the legacy card pushes `/bookings/:bookingId`
//     (the single-booking detail).
//
// Finders are key-first / type-first; status copy is asserted through l10n.

import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/booking_tab.dart';
import 'package:beautica_mobile/features/booking/presentation/my_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_card.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_status_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/booking_fixture_dates.dart';
import '../../../helpers/pump_app.dart';

/// The visit's day, anchored to the real wall clock instead of written as an
/// absolute literal — see `test/helpers/booking_fixture_dates.dart` for the
/// time bomb this avoids.
///
/// These rows are stubbed into the **upcoming** tab. Nothing this suite asserts
/// today reads `BookingDisplayX.isPast` — neither `MyBookingsScreen` nor
/// `VisitCard` has a wall-clock branch, and the assertions here are card counts,
/// keys, the price band, service names and two `context.push` targets. So the
/// anchor is PRE-EMPTIVE, not load-bearing: it keeps the fixture honest to the
/// tab it is stubbed into, so the first upcoming-only affordance this list grows
/// later cannot quietly become a false negative on a DATE (the 2026-07-20
/// incident, exactly).
///
/// Normalised to a fixed 10:00 UTC on that future day so the three fixtures
/// keep the same relationship the pinned literals encoded — the visit's second
/// service an hour after its first, the legacy booking the next day —
/// regardless of what time of day the suite runs.
DateTime _atTenUtc(DateTime d) => DateTime.utc(d.year, d.month, d.day, 10);

final DateTime _visitStart = _atTenUtc(futureBookingStart());
final DateTime _visitSecondStart = _visitStart.add(const Duration(hours: 1));
final DateTime _legacyStart = _visitStart.add(const Duration(days: 1));

class _MockBookingRepository extends Mock implements BookingRepository {}

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

/// A router whose leaf routes are stubs recording their resolved location, so a
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
            path: 'visit/:appointmentId',
            builder: (BuildContext context, GoRouterState state) {
              onLocation(state.uri.toString());
              return const Scaffold(key: Key('visit_stub'));
            },
          ),
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
    'a 2-item visit renders one grouped card + legacy stays its own',
    (tester) async {
      final repo = _MockBookingRepository();
      _stubAllTabs(repo, upcoming: visitAndLegacy);

      await pumpScreen(tester, repo, onLocation: (_) {});

      // Exactly one grouped visit card, and one legacy single card.
      expect(find.byType(VisitCard), findsOneWidget);
      expect(find.byType(BookingCard), findsOneWidget);

      // Visit summary: count · summed duration line + total band + one time.
      expect(
        find.byKey(const ValueKey<String>('service-visit-appt-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('visit-time-appt-1')),
        findsOneWidget,
      );
      // Band: floor 300+200 = 500, ceiling 300+(400) = 700.
      expect(find.text('500–700 ₴'), findsOneWidget);

      // The ordered service names of the visit.
      expect(
        find.byKey(const ValueKey<String>('visit-service-appt-1-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('visit-service-appt-1-1')),
        findsOneWidget,
      );
      // i18n-finder-ok: service name is injected fixture data, locale-invariant
      expect(find.text('Манікюр'), findsOneWidget);
      // i18n-finder-ok: service name is injected fixture data, locale-invariant
      expect(find.text('Педикюр'), findsOneWidget);

      // A status badge on the grouped card.
      expect(find.byType(BookingStatusBadge), findsWidgets);
    },
  );

  testWidgets('tapping the visit card pushes /bookings/visit/:appointmentId', (
    tester,
  ) async {
    final repo = _MockBookingRepository();
    _stubAllTabs(repo, upcoming: visitAndLegacy);

    String? location;
    await pumpScreen(tester, repo, onLocation: (String l) => location = l);

    await tester.tap(find.byType(VisitCard));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('visit_stub')), findsOneWidget);
    expect(location, '/bookings/visit/appt-1');
  });

  testWidgets('tapping the legacy card pushes /bookings/:bookingId', (
    tester,
  ) async {
    final repo = _MockBookingRepository();
    _stubAllTabs(repo, upcoming: visitAndLegacy);

    String? location;
    await pumpScreen(tester, repo, onLocation: (String l) => location = l);

    await tester.tap(find.byType(BookingCard));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('booking_stub')), findsOneWidget);
    expect(location, '/bookings/legacy-1');
  });
}
