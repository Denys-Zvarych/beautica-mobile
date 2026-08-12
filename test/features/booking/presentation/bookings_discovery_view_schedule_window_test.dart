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
import 'package:beautica_mobile/core/theme/brand_colors.dart';
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
import 'package:beautica_mobile/features/booking/presentation/widgets/timeline_hour_ruler.dart';
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

/// EVERY rendered gridline (`BookingsTimelineGrid`'s hour + half-hour
/// `ColoredBox` hairlines), sorted ascending by rendered top — mirrors
/// `bookings_timeline_grid_test.dart`'s identically-named helper. Used here
/// to prove the grid's REAL geometry (not merely `find.byType`'s tree
/// presence) survives the composition this file pumps through — see the
/// "cause 2" group below for why `find.byType` alone cannot guard the bug
/// this regresses.
List<Rect> _gridlineLadderAscending(WidgetTester tester) {
  final Color halfHour = BrandColors.faint.withValues(alpha: 0.4);
  final Iterable<Element> elements = find
      .byWidgetPredicate(
        (Widget w) =>
            w is ColoredBox &&
            (w.color == BrandColors.faint || w.color == halfHour),
      )
      .evaluate();
  return elements.map((Element e) {
    final RenderBox box = e.renderObject! as RenderBox;
    return box.localToGlobal(Offset.zero) & box.size;
  }).toList()..sort((Rect a, Rect b) => a.top.compareTo(b.top));
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
    // BUG FIX regression coverage (this session) — lets a caller pump with
    // an ACTIVE filter (`hasFilters == true`) so the "filter matches
    // nothing" case can be distinguished from the "genuinely no bookings"
    // one. Defaults to the pre-existing unfiltered query so every call site
    // above is unaffected.
    BookingsDayQuery? query,
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
        query: query ?? BookingsDayQuery.of(day: _day),
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

  // ══════════════════════════════════════════════════════════════════════
  // USER-REPORTED BUG REGRESSION — a day with WORKING HOURS but ZERO
  // (visible) bookings rendered no time grid at all.
  // ══════════════════════════════════════════════════════════════════════
  //
  // TWO causes, both pinned here:
  //   1. `_body` used to short-circuit on `items.isEmpty` alone and return
  //      an illustrated empty state BEFORE `BookingsTimelineGrid` was ever
  //      built — fixed by gating on `items.isEmpty && window == null`.
  //   2. Even once the grid IS built, a zero-lane day used to collapse the
  //      gridline `Stack` to `Size.zero` (its only non-`Positioned` child,
  //      the lane `Row`, emits no children at `lanesCount == 0`) — so
  //      `find.byType(BookingsTimelineGrid)` would have kept passing on the
  //      COLLAPSED widget throughout this whole regression. Every test below
  //      therefore asserts REAL rendered geometry (`getSize` on the grid's
  //      own `timeline-lane-stack`), never presence alone — see
  //      `bookings_timeline_grid_schedule_window_test.dart`'s "zero-lane
  //      grid geometry" group for the direct unit-level guard on the grid
  //      widget itself; this file's job is proving the fix survives the
  //      REAL `BookingsDiscoveryView` composition (the `items.isEmpty &&
  //      window == null` gate lives here, not in the grid).
  group('the grid on a RESOLVED window with an EMPTY visible result — cause 1 '
      '+ cause 2', () {
    /// Asserts the grid rendered with REAL (non-collapsed) geometry, tied
    /// to the 09:00–18:00 (9h) window every test in this group seeds —
    /// NOT merely `find.byType(...).findsOneWidget`, which the collapsed
    /// widget also satisfies (see the group header). The expected rung
    /// count (19: 18 half-hour steps + the origin rung) is derived from
    /// the SEEDED window bounds, independent of whatever the grid actually
    /// rendered, so a wrong window (e.g. an unfixed cause 1 leaving `items
    /// .isEmpty` un-gated, or a future regression that anchors the grid to
    /// the wrong hours) fails this BEFORE the height check even runs.
    void expectGridRenderedWithRealGeometry(WidgetTester tester) {
      expect(
        find.byType(MasterBookingsEmptyState),
        findsNothing,
        reason:
            'the locked product decision is NO accompanying empty-state '
            'text once a window has resolved — just the grid',
      );
      expect(find.byType(MasterBookingsNoResultsState), findsNothing);

      final List<Rect> ladder = _gridlineLadderAscending(tester);
      expect(
        ladder.length,
        19,
        reason:
            'the 09:00–18:00 seeded window is 9 hours = 18 half-hour '
            'rungs + the origin rung; a wrong count means the grid did '
            'not anchor to the resolved window',
      );
      final double rungBand = ladder[1].top - ladder[0].top;
      expect(
        rungBand,
        greaterThan(0),
        reason: 'gridline rungs must be strictly ascending',
      );
      final double expectedGridHeight = (ladder.length - 1) * rungBand + 1;

      final double gridHeight = tester
          .getSize(find.byKey(const ValueKey<String>('timeline-lane-stack')))
          .height;
      expect(
        gridHeight,
        closeTo(expectedGridHeight, 0.5),
        reason:
            'THE CAUSE-2 ASSERTION — on the collapsed-height bug this '
            'reads ~0 (the Stack sizes to its empty lane Row) while '
            'find.byType(BookingsTimelineGrid) keeps passing regardless',
      );

      // The ruler and the gridline `Stack` must stay pixel-registered
      // even with zero lanes — the fix's whole claim is that the floor is
      // DERIVED from the same firstHour/lastHour clock math the ruler
      // uses, not an independent guess.
      final Rect firstLabel = tester.getRect(
        find.descendant(
          of: find.byType(TimelineHourRuler),
          matching: find.text('09:00'),
        ),
      );
      expect(
        ladder.first.top - firstLabel.top,
        closeTo(TimelineHourRuler.labelCenteringNudge, 0.5),
        reason:
            'the first hour label must stay registered against the '
            'first gridline even with zero lanes',
      );
    }

    testWidgets(
      'hours resolved + genuinely ZERO bookings for the day — the exact '
      'user report',
      (tester) async {
        await pump(
          tester,
          useScheduleWindow: true,
          bookings: const <Booking>[],
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

        expectGridRenderedWithRealGeometry(tester);
      },
    );

    testWidgets(
      'bookings EXIST for the day but ALL fall outside the working-hours '
      'window',
      (tester) async {
        final Booking outOfWindow = _booking(
          id: 'all-outside',
          startAtUtc: _kyivAtUtc(20),
        );

        await pump(
          tester,
          useScheduleWindow: true,
          bookings: <Booking>[outOfWindow],
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

        expect(
          find.byKey(const ValueKey<String>('timeline-card-all-outside')),
          findsNothing,
          reason:
              'fixture sanity: the booking really is outside the '
              'window and must not render a card',
        );
        expectGridRenderedWithRealGeometry(tester);
      },
    );

    testWidgets(
      'a status filter is active and matches nothing on this day — the '
      'grid renders, not the filter-empty state',
      (tester) async {
        await pump(
          tester,
          useScheduleWindow: true,
          bookings: const <Booking>[],
          // A status filter makes `hasFilters == true` — before this fix,
          // `_body` chose between `MasterBookingsEmptyState` and
          // `MasterBookingsNoResultsState` purely on `hasFilters`. Once a
          // window has resolved, NEITHER may render — proving the
          // `window == null` gate, not `hasFilters`, is what decides this
          // now.
          query: BookingsDayQuery.of(
            day: _day,
            statuses: const <BookingStatus>{BookingStatus.cancelled},
          ),
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

        expectGridRenderedWithRealGeometry(tester);
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════
  // THE ISOLATION GUARANTEE — useScheduleWindow: false is UNTOUCHED
  // ══════════════════════════════════════════════════════════════════════
  group('useScheduleWindow: false with zero bookings', () {
    testWidgets(
      'still renders the legacy MasterBookingsEmptyState — the client '
      'booking screen (which never sets useScheduleWindow) must be '
      'completely unaffected by this fix',
      (tester) async {
        await pump(
          tester,
          useScheduleWindow: false,
          bookings: const <Booking>[],
          // Deliberately NOT overriding effectiveScheduleProvider — the
          // legacy path never watches it (see the "header count" group's
          // identically-reasoned test above).
        );

        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const Key('master-bookings-empty')),
          findsOneWidget,
          reason:
              'window is always null on this path, so the pre-existing '
              'items.isEmpty branch must still be reached exactly as '
              'before this feature',
        );
        expect(find.byType(BookingsTimelineGrid), findsNothing);
      },
    );
  });
}
