// Phase 244 — BookingsDiscoveryView.useScheduleWindow: the master «Мої
// записи» working-hours window wired end-to-end through the real composition
// (bookingsDayProvider + effectiveScheduleProvider + BookingsTimelineGrid),
// not just the pure helpers underneath it.
//
// Locked behaviour pinned here (see the orchestrator's brief):
//   * the header count reflects RENDERED bookings when the window is active,
//     `state.totalElements` when useScheduleWindow is false;
//   * a day with NO working hours replaces the whole body with
//     MasterBookingsNoWorkingHoursState, unconditionally;
//   * loading/error on the SCHEDULE fetch renders the legacy booking-derived
//     window — the gray state is reserved for a genuinely RESOLVED verdict;
//   * an out-of-window booking is dropped from the render entirely;
//   * useScheduleWindow: false is untouched — effectiveScheduleProvider is
//     never even watched, so every pre-existing call site is unaffected.

import 'dart:async';

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
import 'package:beautica_mobile/features/booking/presentation/widgets/master_bookings_states.dart';
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

/// Pinned "now" whose `kyivToday(...)` reading equals [_day] — see
/// `bookings_discovery_view.dart`'s `initState`, which derives its opening
/// day from `kyivToday(ref.read(clockProvider))`.
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

class _LoadingSchedule extends EffectiveScheduleNotifier {
  @override
  Future<List<EffectiveDay>> build(ScheduleRange range) {
    return Completer<List<EffectiveDay>>().future; // never completes
  }
}

class _ErrorSchedule extends EffectiveScheduleNotifier {
  @override
  Future<List<EffectiveDay>> build(ScheduleRange range) async =>
      throw Exception('schedule fetch boom');
}

void main() {
  setUpAll(() {
    initBeauticaTimeZones();
    registerFallbackValue(BookingStatus.confirmed);
    registerFallbackValue(<BookingStatus>[]);
  });

  /// Pumps [BookingsDiscoveryView] with [useScheduleWindow] true, [bookings]
  /// served for the pinned Kyiv "today" ([_day]), and [scheduleOverride]
  /// backing `effectiveScheduleProvider` (omit to leave it un-overridden,
  /// which is only safe for `useScheduleWindow: false`).
  Future<void> pump(
    WidgetTester tester, {
    required bool useScheduleWindow,
    required List<Booking> bookings,
    Object? scheduleOverride,
    ValueChanged<DateTime>? onAddWorkingHours,
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
        useScheduleWindow: useScheduleWindow,
        onAddWorkingHours: useScheduleWindow
            ? (onAddWorkingHours ?? (DateTime _) {})
            : null,
        onBookingTap: (Booking _) {},
      ),
      overrides: <Object>[
        screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
        bookingRepositoryProvider.overrideWithValue(repo),
        bookedDaysProvider.overrideWith((ref) async => <DateTime>{}),
        clockProvider.overrideWithValue(() => _fixedNow),
        ?scheduleOverride,
      ],
    );
    await tester.pumpAndSettle();
  }

  group('the header count', () {
    testWidgets(
      'with the window active, shows the number of RENDERED bookings, not '
      'the server total',
      (tester) async {
        final Booking inWindow = _booking(id: 'in', startAtUtc: _kyivAtUtc(9));
        final Booking outOfWindow = _booking(
          id: 'out',
          startAtUtc: _kyivAtUtc(20),
        );

        await pump(
          tester,
          useScheduleWindow: true,
          bookings: <Booking>[inWindow, outOfWindow],
          scheduleOverride: effectiveScheduleProvider.overrideWith(
            () => _DataSchedule(<EffectiveDay>[
              EffectiveDay(
                date: _day,
                source: EffectiveSource.template,
                intervals: <WorkInterval>[_interval(9, 0, 18, 0)],
              ),
            ]),
          ),
        );

        final AppLocalizations l10n = AppLocalizations.of(
          tester.element(find.byType(BookingsDiscoveryView)),
        );

        expect(find.text(l10n.masterBookingsCount(1)), findsOneWidget);
        expect(
          find.text(l10n.masterBookingsCount(2)),
          findsNothing,
          reason: 'the count must not read the server\'s unfiltered total',
        );
        expect(
          find.byKey(const ValueKey<String>('timeline-card-in')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('timeline-card-out')),
          findsNothing,
          reason:
              'a booking outside the working-hours window must render no card',
        );
      },
    );

    testWidgets(
      'with useScheduleWindow: false, shows state.totalElements and renders '
      'EVERY booking — the legacy path is untouched',
      (tester) async {
        final Booking a = _booking(id: 'legacy-a', startAtUtc: _kyivAtUtc(9));
        final Booking b = _booking(id: 'legacy-b', startAtUtc: _kyivAtUtc(20));

        await pump(
          tester,
          useScheduleWindow: false,
          bookings: <Booking>[a, b],
          // Deliberately NOT overriding effectiveScheduleProvider — proves
          // it is never watched on this path (an un-overridden family
          // provider needing network I/O would throw if it were).
        );

        expect(tester.takeException(), isNull);

        final AppLocalizations l10n = AppLocalizations.of(
          tester.element(find.byType(BookingsDiscoveryView)),
        );
        expect(find.text(l10n.masterBookingsCount(2)), findsOneWidget);
        expect(
          find.byKey(const ValueKey<String>('timeline-card-legacy-a')),
          findsOneWidget,
        );

        // legacy-b sits far enough down the legacy booking-derived window
        // (which spans from the earliest to the latest booking) to fall past
        // the grid's viewport-culling window at rest — scroll to it before
        // asserting on its real (non-placeholder) presence, exactly as the
        // "grid bottom widens" tests do.
        final ScrollableState scrollable = tester.state<ScrollableState>(
          find
              .descendant(
                of: find.byType(BookingsTimelineGrid),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
        await tester.pump();

        expect(
          find.byKey(const ValueKey<String>('timeline-card-legacy-b')),
          findsOneWidget,
          reason:
              'a booking that WOULD be outside a working-hours window must '
              'still render when useScheduleWindow is false',
        );
      },
    );
  });

  group('the gray "no working hours" state', () {
    testWidgets(
      'renders unconditionally on a settled day-off, even though bookings '
      'exist for the day',
      (tester) async {
        await pump(
          tester,
          useScheduleWindow: true,
          bookings: <Booking>[
            _booking(id: 'orphan', startAtUtc: _kyivAtUtc(9)),
          ],
          scheduleOverride: effectiveScheduleProvider.overrideWith(
            () => _DataSchedule(<EffectiveDay>[
              EffectiveDay(
                date: _day,
                source: EffectiveSource.overrideDayOff,
                intervals: const <WorkInterval>[],
              ),
            ]),
          ),
        );

        expect(
          find.byKey(const Key('master-bookings-no-schedule')),
          findsOneWidget,
        );
        expect(
          find.byType(BookingsTimelineGrid),
          findsNothing,
          reason:
              'the gray state must replace the WHOLE body, not sit alongside it',
        );
        expect(
          tester
              .widget<MasterBookingsNoWorkingHoursState>(
                find.byType(MasterBookingsNoWorkingHoursState),
              )
              .dayOff,
          isTrue,
        );
      },
    );

    testWidgets('renders with the NO_SCHEDULE copy variant for an unset day', (
      tester,
    ) async {
      await pump(
        tester,
        useScheduleWindow: true,
        bookings: const <Booking>[],
        scheduleOverride: effectiveScheduleProvider.overrideWith(
          () => _DataSchedule(<EffectiveDay>[
            EffectiveDay(
              date: _day,
              source: EffectiveSource.noSchedule,
              intervals: const <WorkInterval>[],
            ),
          ]),
        ),
      );

      expect(
        find.byKey(const Key('master-bookings-no-schedule')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<MasterBookingsNoWorkingHoursState>(
              find.byType(MasterBookingsNoWorkingHoursState),
            )
            .dayOff,
        isFalse,
      );
    });

    testWidgets(
      'does NOT render while the schedule fetch is still LOADING — the '
      'legacy booking-derived window renders instead',
      (tester) async {
        final Booking b = _booking(
          id: 'while-loading',
          startAtUtc: _kyivAtUtc(9),
        );

        await pump(
          tester,
          useScheduleWindow: true,
          bookings: <Booking>[b],
          scheduleOverride: effectiveScheduleProvider.overrideWith(
            () => _LoadingSchedule(),
          ),
        );

        expect(
          find.byKey(const Key('master-bookings-no-schedule')),
          findsNothing,
          reason:
              'a transient loading verdict must never flash the gray state '
              'on a day that genuinely has working hours',
        );
        expect(
          find.byKey(const ValueKey<String>('timeline-card-while-loading')),
          findsOneWidget,
          reason: 'the legacy booking-derived window must render meanwhile',
        );
      },
    );

    testWidgets(
      'does NOT render when the schedule fetch ERRORS — an unreachable '
      'schedule endpoint must not read as "no working hours"',
      (tester) async {
        final Booking b = _booking(
          id: 'while-error',
          startAtUtc: _kyivAtUtc(9),
        );

        await pump(
          tester,
          useScheduleWindow: true,
          bookings: <Booking>[b],
          scheduleOverride: effectiveScheduleProvider.overrideWith(
            () => _ErrorSchedule(),
          ),
        );

        expect(
          find.byKey(const Key('master-bookings-no-schedule')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey<String>('timeline-card-while-error')),
          findsOneWidget,
        );
      },
    );

    testWidgets('the CTA fires onAddWorkingHours with the day it was showing', (
      tester,
    ) async {
      DateTime? captured;
      await pump(
        tester,
        useScheduleWindow: true,
        bookings: const <Booking>[],
        scheduleOverride: effectiveScheduleProvider.overrideWith(
          () => _DataSchedule(<EffectiveDay>[
            EffectiveDay(
              date: _day,
              source: EffectiveSource.noSchedule,
              intervals: const <WorkInterval>[],
            ),
          ]),
        ),
        onAddWorkingHours: (DateTime d) => captured = d,
      );

      await tester.tap(
        find.byKey(const Key('master-bookings-no-schedule-cta')),
      );
      await tester.pump();

      expect(captured, _day);
    });
  });
}
