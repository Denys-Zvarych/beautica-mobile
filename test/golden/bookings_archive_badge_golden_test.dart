// Phase 395 (24.7c) — pixel coverage for the red pending-actions badge on the
// «Записи» header's «Архів» icon: the shared `BookingsDiscoveryView` header
// with `archiveBadgeCount` 3 and 120 (-> «99+»). Counts of null / 0 are
// pinned by the pre-existing «Записи» goldens staying byte-identical.

import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/features/booking/application/booked_days_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/bookings_day_query.dart';
import 'package:beautica_mobile/features/booking/presentation/bookings_discovery_view.dart';
import 'package:beautica_mobile/features/services/data/master_service_catalog_provider.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/clock_instant.dart';
import 'helpers/golden_pump.dart';

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
}

class _MockBookingRepository extends Mock implements BookingRepository {}

List<Object> _overrides() {
  registerFallbackValue(<BookingStatus>[]);
  final _MockBookingRepository repo = _MockBookingRepository();
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
    (_) async => const PageResponse<Booking>(
      items: <Booking>[],
      page: 0,
      totalPages: 1,
      totalElements: 0,
    ),
  );
  return <Object>[
    screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
    // Pin the clock so the day rail's highlighted "today" cell is stable.
    clockProvider.overrideWithValue(
      () => asClockInstant(DateTime(2026, 6, 13)),
    ),
    bookingRepositoryProvider.overrideWithValue(repo),
    bookedDaysProvider.overrideWith((ref) async => <DateTime>{}),
    masterServiceCatalogProvider.overrideWith(
      (ref) async => const <MasterService>[],
    ),
  ];
}

void main() {
  const double width = 360;
  for (final int count in <int>[3, 120]) {
    goldenTest(
      'bookings archive badge $count',
      fileName: 'bookings_archive_badge_$count',
      constraints: BoxConstraints.tight(const Size(width, kGoldenHeight)),
      pumpWidget: goldenPumpWidget(overrides: _overrides(), width: width),
      builder: () => BookingsDiscoveryView(
        query: BookingsDayQuery.of(day: DateTime(2026, 6, 13)),
        title: 'Записи',
        onBookingTap: (Booking _) {},
        onOpenArchive: () {},
        archiveBadgeCount: count,
      ),
    );
  }
}
