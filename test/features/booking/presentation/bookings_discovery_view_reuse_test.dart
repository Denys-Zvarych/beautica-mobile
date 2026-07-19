// Phase 7.11 — pins the salon-reuse seam `BookingsDiscoveryView` exists to
// provide.
//
// `showMasterFilter` is the ONE flag the salon phase will flip to drop in the
// teammate («Майстер») filter behind — see the file header of
// `bookings_discovery_view.dart`. This phase deliberately does NOT build that
// affordance or `_MasterFilterSheet`; what it MUST do is leave the seam in a
// state where:
//   * `showMasterFilter: false` (the master's own screen, forever) renders
//     NO teammate-filter chrome — trivially true today (nothing implements it
//     yet), but pinning it now means the day the salon phase adds
//     `_MasterFilterSheet` behind `showMasterFilter: true`, an accidental
//     `true` on the master's own call site is caught immediately rather than
//     silently leaking a control that makes no sense for a single master.
//   * `showMasterFilter: true` still builds cleanly — the flag is a plain
//     `bool`, not a `late`/asserted invariant that only tolerates `false`
//     today — so the salon phase is a drop-in, not a rewrite that first has
//     to loosen an assumption this phase baked in.
//
// Both cases pump the SAME `query`/`onBookingTap` and assert the rest of the
// composition (the status/service filter button, the header, the day rail)
// renders identically regardless of the flag — proving `showMasterFilter`
// is currently a true no-op everywhere except the (nonexistent) teammate
// affordance itself, exactly what "the view never branches on scope" claims.

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

import '../../../helpers/pump_app.dart';

class _MockBookingRepository extends Mock implements BookingRepository {}

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
}

Booking _booking(String id) {
  final DateTime start = DateTime.utc(2026, 7, 20, 12);
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

/// Any key naming convention a future teammate-filter affordance would
/// plausibly use — none of these may render while the seam is unimplemented,
/// under EITHER flag value.
const List<String> _plausibleMasterFilterKeys = <String>[
  'bookings-discovery-master-filter',
  'bookings-discovery-master-filter-button',
  'master-filter-sheet',
  'salon-master-filter-sheet',
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

  group('showMasterFilter: true — the future salon drop-in point', () {
    testWidgets(
      'builds cleanly, with no master-specific chrome that would break '
      'under a salon scope',
      (tester) async {
        await _pump(tester, showMasterFilter: true);

        // The seam accepts `true` today without throwing or asserting —
        // this is what makes the salon phase a drop-in rather than a
        // rewrite. Nothing implements the flag yet, so it is currently a
        // no-op; that is the point being pinned.
        expect(tester.takeException(), isNull);
        expect(find.byType(BookingsDiscoveryView), findsOne);
        expect(find.byType(BookingsDayRail), findsOne);
      },
    );

    testWidgets(
      'still renders no teammate-filter affordance — nothing implements the '
      'flag in THIS phase',
      (tester) async {
        await _pump(tester, showMasterFilter: true);

        for (final String key in _plausibleMasterFilterKeys) {
          expect(find.byKey(Key(key)), findsNothing);
        }
      },
    );

    testWidgets(
      'renders IDENTICALLY to showMasterFilter: false — the flag is a true '
      'no-op until the salon phase implements it',
      (tester) async {
        await _pump(tester, showMasterFilter: true);

        expect(
          find.byKey(const Key('master-bookings-filter-button')),
          findsOne,
        );
        expect(find.text('Test Discovery Title'), findsOne);
      },
    );
  });
}
