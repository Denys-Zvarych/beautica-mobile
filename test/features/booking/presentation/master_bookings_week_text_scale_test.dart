// Phase 485 (closes backlog INFO 111) — the WHOLE master «Записи» week screen
// at `TextScaler.linear(1.3)` on a 360×640 phone: no overflow anywhere
// (header, week nav bar, strip, grid, bottom bar — `pumpRoutedApp` installs
// the overflow guard), still three columns, and a 30-minute block still
// shows its time range AND the client's name (the hour band grows with the
// text scale — `WeekTimeGrid.hourHeightFor`).

import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/booking/application/booked_days_notifier.dart';
import 'package:beautica_mobile/features/booking/application/bookings_capability.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/master_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/week_time_grid.dart';
import 'package:beautica_mobile/features/booking_links/presentation/booking_link_setup_hints_provider.dart';
import 'package:beautica_mobile/features/booking_links/presentation/master_nav_setup_hints_provider.dart';
import 'package:beautica_mobile/features/services/data/master_service_catalog_provider.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/pump_app.dart';

class _MockBookingRepository extends Mock implements BookingRepository {}

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
}

/// Fixture client name — not app copy.
const String _kFirst = 'Олена';

Booking _thirtyMinutes() {
  final DateTime d = kyivToday(DateTime.now);
  final DateTime start = DateTime.utc(d.year, d.month, d.day, 9);
  return Booking(
    id: 'b30',
    masterId: 'm1',
    masterFirstName: 'Марія',
    masterLastName: 'Іванюк',
    masterType: 'INDEPENDENT_MASTER',
    clientId: 'c1',
    clientFirstName: _kFirst,
    clientLastName: 'Ковальчук',
    serviceId: 's1',
    serviceName: 'Манікюр',
    durationMinutes: 30,
    price: 300,
    startAt: start,
    endAt: start.add(const Duration(minutes: 30)),
    status: BookingStatus.confirmed,
    canReview: false,
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(BookingStatus.confirmed);
    registerFallbackValue(BookingSort.oldest);
    registerFallbackValue(<BookingStatus>[]);
  });

  testWidgets('360×640 @ 1.3: no overflow, three columns, a 30-min block '
      'shows range + name', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final _MockBookingRepository repo = _MockBookingRepository();
    final Booking booking = _thirtyMinutes();
    when(
      () => repo.getMyBookings(
        statuses: any(named: 'statuses'),
        page: any(named: 'page'),
        size: any(named: 'size'),
        cancelToken: any(named: 'cancelToken'),
        sort: any(named: 'sort'),
        serviceIds: any(named: 'serviceIds'),
        from: any(named: 'from'),
        to: any(named: 'to'),
        partition: any(named: 'partition'),
        asMaster: any(named: 'asMaster'),
      ),
    ).thenAnswer(
      (_) async => PageResponse<Booking>(
        items: <Booking>[booking],
        page: 0,
        totalPages: 1,
        totalElements: 1,
      ),
    );

    await tester.pumpRoutedApp(
      GoRouter(
        initialLocation: '/',
        routes: <RouteBase>[
          GoRoute(
            path: '/',
            builder: (BuildContext context, GoRouterState state) =>
                const MasterBookingsScreen(),
          ),
        ],
      ),
      overrides: <Object>[
        masterNavSetupHintsProvider.overrideWithValue(
          BookingLinkSetupHints.none,
        ),
        screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
        bookingRepositoryProvider.overrideWithValue(repo),
        bookedDaysProvider.overrideWith((ref) async => <DateTime>{}),
        bookingCreationEnabledProvider.overrideWithValue(true),
        masterServiceCatalogProvider.overrideWith(
          (ref) async => const <MasterService>[],
        ),
      ],
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final WeekTimeGrid grid = tester.widget<WeekTimeGrid>(
      find.byType(WeekTimeGrid),
    );
    expect(grid.visibleColumns, 3);

    final Finder card = find.byKey(WeekTimeGrid.cardKey(booking.id));
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: card,
        matching: find.textContaining(
          formatSlotTimeRange(booking.startAt, booking.endAt),
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: card,
        // i18n-finder-ok: fixture client name, not app copy
        matching: find.textContaining(_kFirst),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
