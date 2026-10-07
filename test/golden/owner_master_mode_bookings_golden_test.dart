// Phase 383 (24.1f) — pixel coverage for the SALON_OWNER's «master mode»
// «Записи» tab: [MasterBookingsScreen] mounted exactly as the
// `RouteNames.ownerMasterBookings` route mounts it — `asOwnerMaster: true`,
// the owner's OWN-row working-hours window, the owner tile-1
// [VelvetBottomNavBar] and the labelled «‹ Салон» back pill in the shared
// `BookingsDiscoveryView` header (phase 378's `NeumorphicIconButton.label`).
//
// The all-null default (every pre-existing mount) is unchanged: the header
// only grows the pill when `onBack` is non-null, which no pre-383 host
// passes, and the existing bookings goldens stay byte-identical.
//
// Matrix: {320, 360, 414} dp × {textScale 1.0, 1.3} = 6 golden PNGs. The
// 320 × 1.3 cell is the overflow canary for the pill + title + archive +
// filter + (+) header row.

import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/application/booked_days_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/master_bookings_screen.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_scope.dart';
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';
import 'package:beautica_mobile/features/schedule/presentation/effective_schedule_notifier.dart';
import 'package:beautica_mobile/features/schedule/presentation/schedule_range.dart';
import 'package:beautica_mobile/features/services/data/master_service_catalog_provider.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/velvet_bottom_nav_bar.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:mocktail/mocktail.dart';

import '../helpers/clock_instant.dart';
import 'helpers/golden_pump.dart';

const String _kSalonId = 'salon-owner-golden';
const String _kOwnerRowId = 'master-row-owner-golden';

/// Fixed Kyiv DATE TOKEN — a Saturday, so the visible week is Mon 8 .. Sun 14
/// June 2026 regardless of the run day.
final DateTime _today = DateTime(2026, 6, 13);

/// Visible label of the back pill — the l10n value of `ownerMasterModeBack`.
const String _kBackLabel = 'Салон';

class _OwnerAuth extends AuthNotifier {
  @override
  Future<AuthSession> build() async => const AuthSession.authenticated(
    user: User(id: 'u-owner', email: 'o@b.c', role: UserRole.salonOwner),
    accessToken: 'tkn',
  );
}

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
}

class _MockBookingRepository extends Mock implements BookingRepository {}

/// One own-row booking, 11:00–12:30 Kyiv (08:00Z, summer UTC+3).
Booking _ownRowBooking() {
  final DateTime start = DateTime.utc(2026, 6, 13, 8);
  return Booking(
    id: 'b-own',
    masterId: _kOwnerRowId,
    masterFirstName: 'Олена',
    masterLastName: 'Ковальчук',
    masterType: 'SALON_OWNER',
    clientId: 'c-1',
    clientFirstName: 'Ірина',
    clientLastName: 'Бондар',
    serviceId: 'svc-1',
    serviceName: 'Манікюр з покриттям',
    durationMinutes: 90,
    price: 650,
    startAt: start,
    endAt: start.add(const Duration(minutes: 90)),
    status: BookingStatus.confirmed,
    canReview: false,
  );
}

/// The owner's own row works 10:00–18:00 that day.
class _Days extends EffectiveScheduleNotifier {
  @override
  Future<List<EffectiveDay>> build(
    ScheduleScope scope,
    ScheduleRange range,
  ) async => <EffectiveDay>[
    EffectiveDay(
      date: _today,
      source: EffectiveSource.template,
      intervals: <WorkInterval>[
        WorkInterval(
          start: const TimeOfDay(hour: 10, minute: 0),
          end: const TimeOfDay(hour: 18, minute: 0),
        ),
      ],
    ),
  ];
}

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
    (_) async => PageResponse<Booking>(
      items: <Booking>[_ownRowBooking()],
      page: 0,
      totalPages: 1,
      totalElements: 1,
    ),
  );
  return <Object>[
    authProvider.overrideWith(_OwnerAuth.new),
    clockProvider.overrideWithValue(() => asClockInstant(_today)),
    screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
    bookingRepositoryProvider.overrideWithValue(repo),
    ownerMasterBookedDaysProvider.overrideWith(
      (ref) async => <DateTime>{_today},
    ),
    effectiveScheduleProvider.overrideWith(_Days.new),
    masterServiceCatalogProvider.overrideWith(
      (ref) async => const <MasterService>[],
    ),
  ];
}

void main() {
  for (final double width in kGoldenWidths) {
    for (final double scale in kGoldenTextScales) {
      final String suffix = widthScaleSuffix(width, scale);

      goldenTest(
        'owner_master_mode_bookings $suffix',
        fileName: 'owner_master_mode_bookings_$suffix',
        constraints: BoxConstraints.tight(Size(width, kGoldenHeight)),
        textScaleFactor: scale,
        pumpWidget: goldenPumpWidget(overrides: _overrides(), width: width),
        builder: () => MasterBookingsScreen(
          asOwnerMaster: true,
          scheduleScope: const ScheduleScope.salonMaster(
            salonId: _kSalonId,
            masterId: _kOwnerRowId,
          ),
          detailRouteBuilder: RouteNames.salonStaffBookingDetail,
          archiveRoute: RouteNames.ownerMasterBookingsArchive,
          navScheduleRoute: RouteNames.ownerMasterSchedule,
          // Mirrors `app_router.dart`'s private `_kOwnerMasterNavBars[1]`.
          bottomNavBar: const VelvetBottomNavBar(
            activeIndex: 1,
            servicesRoute: RouteNames.ownerMasterServices,
            scheduleRoute: RouteNames.ownerMasterSchedule,
            profileRoute: RouteNames.ownerMasterProfile,
            bookingsRoute: RouteNames.ownerMasterBookings,
          ),
          backLabel: _kBackLabel,
          onBack: () {},
          onCreateBooking: () {},
        ),
      );
    }
  }
}
