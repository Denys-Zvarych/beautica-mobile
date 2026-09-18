// Phase 7.11 — pins the salon-reuse seam `BookingsDiscoveryView` exists to
// provide.
//
// `showMasterFilter` is the flag the salon board flips to offer the teammate
// («Майстер») filter section — see the file header of
// `bookings_discovery_view.dart`. IT IS NO LONGER A NO-OP: the section shipped
// 2026-09-18, multi-select and client-side, and `SalonBookingsScreen` passes
// `true` alongside `masterFilterOptions` (its roster). What this file pins is
// that flipping it changes NOTHING on the master's own screen, in either
// direction:
//   * `showMasterFilter: false` (the master's own screen, forever) renders NO
//     teammate-filter chrome. An accidental `true` on the master's own call
//     site is caught here rather than silently leaking a control that makes no
//     sense for a single master.
//   * `showMasterFilter: true` WITH NO `masterFilterOptions` — which is what a
//     master-scope mount would be — still builds cleanly and still renders no
//     section, because the flag and the option universe are ANDed. An empty
//     universe never produces an empty heading.
//
// Both cases pump the SAME `query`/`onBookingTap` and assert the rest of the
// composition (the status/service filter button, the header, the day rail)
// renders identically regardless of the flag — which is what "the view never
// branches on scope" claims. The «Майстер» section's own behaviour, on a
// scope that actually has a roster, is owned by
// `bookings_filter_sheet_test.dart` and
// `salon_bookings_master_filter_test.dart`.

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/features/booking/application/booked_days_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/bookings_day_query.dart';
import 'package:beautica_mobile/features/booking/presentation/bookings_discovery_view.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_day_rail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/booking_fixture_dates.dart';
import '../../../helpers/pump_app.dart';

class _MockBookingRepository extends Mock implements BookingRepository {}

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
}

Booking _booking(String id) {
  // Now-relative, never an absolute literal — see
  // `test/helpers/booking_fixture_dates.dart` for the time bomb this avoids.
  final DateTime start = futureBookingStart();
  return Booking(
    id: id,
    masterId: 'm1',
    masterFirstName: 'Марія',
    masterLastName: 'Іванюк',
    masterType: 'INDEPENDENT_MASTER',
    clientId: 'c-$id',
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
  );
}

/// Any key a teammate-filter affordance would plausibly use, INCLUDING the
/// section that actually shipped — none of these may render on a master-scope
/// mount, under EITHER flag value.
const List<String> _plausibleMasterFilterKeys = <String>[
  'bookings-discovery-master-filter',
  'bookings-discovery-master-filter-button',
  'master-filter-sheet',
  'salon-master-filter-sheet',
  // The real one (`bookings_filter_sheet.dart`). Kept alongside the
  // speculative names above so this list still fails if either the section or
  // a future affordance leaks onto a single master's screen.
  'master-bookings-filter-section-master',
];

Future<void> _pump(
  WidgetTester tester, {
  required bool showMasterFilter,
}) async {
  final repo = _MockBookingRepository();
  when(
    () => repo.getMyBookings(
      statuses: any(named: 'statuses'),
      page: any(named: 'page'),
      size: any(named: 'size'),
      sort: any(named: 'sort'),
      serviceIds: any(named: 'serviceIds'),
      from: any(named: 'from'),
      to: any(named: 'to'),
    ),
  ).thenAnswer(
    (_) async => PageResponse<Booking>(
      items: <Booking>[_booking('b1')],
      page: 0,
      totalPages: 1,
      totalElements: 1,
    ),
  );

  await tester.pumpApp(
    BookingsDiscoveryView(
      query: BookingsDayQuery.of(day: DateTime(2026, 7, 20)),
      title: 'Test Discovery Title',
      showMasterFilter: showMasterFilter,
      onBookingTap: (Booking _) {},
    ),
    overrides: <Object>[
      screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
      bookingRepositoryProvider.overrideWithValue(repo),
      bookedDaysProvider.overrideWith((ref) async => <DateTime>{}),
    ],
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    registerFallbackValue(BookingStatus.confirmed);
    registerFallbackValue(<BookingStatus>[]);
  });

  group('showMasterFilter: false — the master\'s own screen, forever', () {
    testWidgets('renders no teammate-filter affordance', (tester) async {
      await _pump(tester, showMasterFilter: false);
      expect(tester.takeException(), isNull);

      for (final String key in _plausibleMasterFilterKeys) {
        expect(
          find.byKey(Key(key)),
          findsNothing,
          reason:
              '"$key" rendered under showMasterFilter: false — a single '
              'master\'s own list must never offer the teammate filter.',
        );
      }
    });

    testWidgets('the rest of the composition renders normally', (tester) async {
      await _pump(tester, showMasterFilter: false);

      expect(find.byType(BookingsDayRail), findsOne);
      expect(find.byKey(const Key('master-bookings-filter-button')), findsOne);
      expect(
        find.text('Test Discovery Title'),
        findsOne,
      ); // the passed-through title
    });
  });

  group('showMasterFilter: true — the salon drop-in point', () {
    testWidgets(
      'builds cleanly, with no master-specific chrome that would break '
      'under a salon scope',
      (tester) async {
        await _pump(tester, showMasterFilter: true);

        expect(tester.takeException(), isNull);
        expect(find.byType(BookingsDiscoveryView), findsOne);
        expect(find.byType(BookingsDayRail), findsOne);
      },
    );

    testWidgets(
      'renders no teammate-filter affordance WITHOUT masterFilterOptions — '
      'the flag and the option universe are ANDed',
      (tester) async {
        await _pump(tester, showMasterFilter: true);
        // The sheet is not open here; this pins the header chrome. The
        // section's own "empty universe hides the heading" rule is asserted
        // against an OPEN sheet in `bookings_filter_sheet_test.dart`.
        for (final String key in _plausibleMasterFilterKeys) {
          expect(find.byKey(Key(key)), findsNothing);
        }
      },
    );

    testWidgets(
      'renders IDENTICALLY to showMasterFilter: false on a master scope — '
      'the flag alone narrows nothing',
      (tester) async {
        await _pump(tester, showMasterFilter: true);

        expect(
          find.byKey(const Key('master-bookings-filter-button')),
          findsOne,
        );
        expect(find.text('Test Discovery Title'), findsOne);
        // No badge: an unoffered section can never light the funnel.
        expect(
          find.byKey(const Key('master-bookings-filter-badge')),
          findsNothing,
        );
      },
    );
  });
}
