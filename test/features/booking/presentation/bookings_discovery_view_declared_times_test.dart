// Phase 244 follow-up — the REAL `BookingsDiscoveryView` composition wiring
// for an EXPLICIT_TIMES resolved day: `_Loaded.build` must route to
// `DeclaredTimeCards` (never `BookingsTimelineGrid`) and must hand it
// `state.items` UNFILTERED — see `declared_time_cards.dart`'s header and
// `bookings_discovery_view.dart:895-919`.
//
// `bookings_discovery_view_schedule_window_test.dart` already proves the
// INTERVAL-day composition exhaustively (loading/error/day-off/no-schedule/
// empty-window fallbacks) — this file adds ONLY the two things that file
// cannot: the EXPLICIT_TIMES branch selection itself, and the regression
// guard that an INTERVAL day is completely unaffected by this feature
// (mirrors that file's own "isolation guarantee" pattern, one level up).
//
// SIGNAL (2026-08, the MasterBookingCard swap): this file's booked-slot key
// assertions moved from `declared-time-card-<id>` to `master-booking-card-
// <id>` — `DeclaredTimeCards` now renders a booked entry as the shipped
// `MasterBookingCard` verbatim (`declared_time_cards.dart`'s header), and
// that card carries its OWN key rather than one this composition test used
// to be able to assume was minted locally. Flagged rather than silently
// patched: the brief that drove this swap explicitly expected this file to
// "survive untouched" and it did not — a real coupling between this file and
// `declared_time_cards.dart`'s booked-card implementation, worth knowing
// about the next time that file's card choice changes.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:timezone/timezone.dart' as tz;

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
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_timeline_grid.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/declared_time_cards.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';
import 'package:beautica_mobile/features/schedule/presentation/effective_schedule_notifier.dart';
import 'package:beautica_mobile/features/schedule/presentation/schedule_range.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/api_date.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';

import '../../../helpers/booking_fixture_dates.dart';
import '../../../helpers/pump_app.dart';

final DateTime _day = dateOnly(toBeauticaTime(futureBookingStart()));
final DateTime _fixedNow = futureBookingStart();

DateTime _kyivAtUtc(int hour, [int minute = 0]) => tz.TZDateTime(
  beauticaZone,
  _day.year,
  _day.month,
  _day.day,
  hour,
  minute,
).toUtc();

class _MockBookingRepository extends Mock implements BookingRepository {}

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
}

Booking _booking({required String id, required DateTime startAtUtc}) => Booking(
  id: id,
  masterId: 'm1',
  masterFirstName: 'Марія',
  masterLastName: 'Іванюк',
  masterType: 'INDEPENDENT_MASTER',
  clientId: 'c-$id',
  clientFirstName: 'Олена',
  clientLastName: 'Ковальчук',
  serviceId: 's1',
  serviceName: 'Манікюр',
  durationMinutes: 30,
  price: 500,
  startAt: startAtUtc,
  endAt: startAtUtc.add(const Duration(minutes: 30)),
  status: BookingStatus.confirmed,
  canReview: false,
);

WorkInterval _interval(int sh, int sm, int eh, int em) => WorkInterval(
  start: TimeOfDay(hour: sh, minute: sm),
  end: TimeOfDay(hour: eh, minute: em),
);

class _DataSchedule extends EffectiveScheduleNotifier {
  _DataSchedule(this._days);
  final List<EffectiveDay> _days;
  @override
  Future<List<EffectiveDay>> build(ScheduleRange range) async => _days;
}

void main() {
  setUpAll(() {
    initBeauticaTimeZones();
    registerFallbackValue(BookingStatus.confirmed);
    registerFallbackValue(<BookingStatus>[]);
  });

  Future<void> pump(
    WidgetTester tester, {
    required List<Booking> bookings,
    required List<EffectiveDay> scheduleDays,
  }) async {
    final repo = _MockBookingRepository();
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
      ),
    ).thenAnswer(
      (_) async => PageResponse<Booking>(
        items: bookings,
        page: 0,
        totalPages: 1,
        totalElements: bookings.length,
      ),
    );

    await tester.pumpApp(
      BookingsDiscoveryView(
        query: BookingsDayQuery.of(day: _day),
        title: 'Test',
        useScheduleWindow: true,
        onAddWorkingHours: (DateTime _) {},
        onBookingTap: (Booking _) {},
      ),
      overrides: <Object>[
        screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
        bookingRepositoryProvider.overrideWithValue(repo),
        bookedDaysProvider.overrideWith((ref) async => <DateTime>{}),
        clockProvider.overrideWithValue(() => _fixedNow),
        effectiveScheduleProvider.overrideWith(
          () => _DataSchedule(scheduleDays),
        ),
      ],
    );
    await tester.pumpAndSettle();
  }

  group('an EXPLICIT_TIMES resolved day', () {
    testWidgets(
      'routes to DeclaredTimeCards (never BookingsTimelineGrid), and hands '
      'it EVERY booking unfiltered — including one matching no declared time',
      (tester) async {
        final Booking matched = _booking(
          id: 'matched',
          startAtUtc: _kyivAtUtc(11, 0),
        );
        final Booking stray = _booking(
          id: 'stray',
          // Matches NO declared time, and falls OUTSIDE [11:00, 16:00] (the
          // declared-times span) so a filter creeping back in
          // (`visibleBookingsFor`, a GRID concept) would actually drop it —
          // see the "MUTATION-VERIFIED" note on the assertion below.
          startAtUtc: _kyivAtUtc(20, 0),
        );

        await pump(
          tester,
          bookings: <Booking>[matched, stray],
          scheduleDays: <EffectiveDay>[
            EffectiveDay(
              date: _day,
              source: EffectiveSource.overrideCustom,
              intervals: const <WorkInterval>[],
              times: const <TimeOfDay>[
                TimeOfDay(hour: 11, minute: 0),
                TimeOfDay(hour: 16, minute: 0),
              ],
            ),
          ],
        );

        expect(find.byType(DeclaredTimeCards), findsOneWidget);
        expect(
          find.byType(BookingsTimelineGrid),
          findsNothing,
          reason: 'an EXPLICIT_TIMES day must never render the grid',
        );
        expect(
          find.byKey(const Key('master-booking-card-matched')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('master-booking-card-stray')),
          findsOneWidget,
          reason:
              'the stray booking must render too — proves state.items is '
              'handed through UNFILTERED (never bookingsInsideScheduleWindow) '
              'on this branch',
        );

        // Header count == the number of BOOKINGS (2), free entries excluded.
        final AppLocalizations l10n = AppLocalizations.of(
          tester.element(find.byType(BookingsDiscoveryView)),
        );
        expect(find.text(l10n.masterBookingsCount(2)), findsOneWidget);
      },
    );
  });

  group('an INTERVAL resolved day — regression guard', () {
    testWidgets(
      'still routes to BookingsTimelineGrid, never DeclaredTimeCards — '
      '"don\'t touch other time grids"',
      (tester) async {
        final Booking b = _booking(
          id: 'interval-1',
          startAtUtc: _kyivAtUtc(10),
        );

        await pump(
          tester,
          bookings: <Booking>[b],
          scheduleDays: <EffectiveDay>[
            EffectiveDay(
              date: _day,
              source: EffectiveSource.template,
              intervals: <WorkInterval>[_interval(9, 0, 18, 0)],
            ),
          ],
        );

        expect(find.byType(BookingsTimelineGrid), findsOneWidget);
        expect(
          find.byType(DeclaredTimeCards),
          findsNothing,
          reason:
              'an INTERVAL day (times empty) must keep rendering the grid '
              'byte-for-byte as before this feature '
              '(MUTATION-VERIFIED: see the QA report)',
        );
      },
    );
  });
}
