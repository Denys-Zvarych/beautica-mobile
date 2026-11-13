// Phase 244 — BookingsDiscoveryView's DAY layout through the real
// composition (bookingsDayProvider + BookingsTimelineGrid).
//
// Phase 486 — the master's working-hours arm of the day layout was removed
// (every master mount is the week layout since phase 485; its window, «no
// working hours» state and EXPLICIT_TIMES list are pinned in the week
// tests). What stays pinned here is the salon board's day path:
//   * useScheduleWindow: false — state.totalElements count, every booking
//     rendered, effectiveScheduleProvider never watched;
//   * the timeline body's 12dp left inset;
//   * the boardWindowBuilder vacuity tripwire.

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
import 'package:beautica_mobile/features/booking/presentation/widgets/schedule_timeline_window.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/timeline_hour_ruler.dart';
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
    // Phase 335 / QA 2026-09-17 — the salon board's additive window seam.
    // `null` for every pre-existing call site above, which is byte-for-byte
    // the behaviour they had before this parameter existed.
    ScheduleTimelineWindow? Function(List<Booking>, DateTime)?
    boardWindowBuilder,
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
        boardWindowBuilder: boardWindowBuilder,
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

  // ══════════════════════════════════════════════════════════════════════
  // THE TIMELINE BRANCH'S LEFT SCREEN INSET — pinned on the REAL view
  // ══════════════════════════════════════════════════════════════════════
  //
  // WHY THIS LIVES HERE AND NOT IN `bookings_timeline_grid_test.dart`:
  // that file's ADDENDUM 3 group restates the inset as its own local
  // `kTimelineLeftInset` const and pumps a HAND-ROLLED `Padding` around a
  // bare `BookingsTimelineGrid`. It therefore proves the grid's arithmetic
  // given an inset — it cannot prove the SCREEN still supplies that inset.
  // Until this group existed, `bookings_discovery_view.dart`'s
  // `_kTimelineLeftInset` could be reverted to `VelvetSpacing.lg` and the
  // entire suite stayed green (mobile-security LOW, 2026-08-15).
  //
  // The assertion reads RENDERED GEOMETRY (`getRect(...).left`), never the
  // source expression, so it survives the constant being hoisted, renamed,
  // or folded into a file-level `EdgeInsets`.
  group('the timeline branch\'s left screen inset', () {
    testWidgets(
      'the day grid lays the hour ruler out 12dp from the screen edge — '
      'HALF the 24dp used elsewhere, so the lane area reclaims 12dp',
      (tester) async {
        await pump(
          tester,
          // Phase 486 — the day layout is the salon board's only; the inset
          // is pinned on its no-columns grid (no window).
          useScheduleWindow: false,
          bookings: <Booking>[_booking(id: 'inset', startAtUtc: _kyivAtUtc(9))],
        );

        // Fixture sanity: we are genuinely on the grid branch, not a
        // fallback state that would make the geometry below vacuous.
        expect(find.byType(BookingsTimelineGrid), findsOneWidget);

        // The grid is the direct child of the screen's body `Padding`, so
        // its rendered left edge IS that padding's left inset.
        expect(
          tester.getRect(find.byType(BookingsTimelineGrid)).left,
          closeTo(12, 0.01),
          reason:
              'the timeline body must keep the halved inset — reading ~24 '
              'means bookings_discovery_view.dart regressed to '
              'VelvetSpacing.lg, which re-clamps the leading card to 266dp '
              'on the 360dp Android baseline (see that file\'s '
              '_kTimelineLeftInset doc and the grid\'s ADDENDUM 3)',
        );

        // The ruler is flush at the grid's leading edge, so it inherits the
        // same offset — this is the pixel the user actually sees move.
        expect(
          tester.getRect(find.byType(TimelineHourRuler)).left,
          closeTo(12, 0.01),
          reason: 'the hour ruler must sit 12dp from the screen edge',
        );
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════
  // PHASE 335 QA — THE VACUITY TRIPWIRE IS ARMED.
  //
  // `_Loaded.build` runs the host-supplied `boardWindowBuilder`'s window
  // through the SAME `bookingsInsideScheduleWindow` the master path uses, and
  // then asserts — by `identical()`, in debug builds — that the filter
  // excluded NOTHING. On a manager's board a dropped booking is data loss, so
  // that assert is the only thing standing between a future builder that
  // stops satisfying `salonBoardWindow`'s proof and a silently truncated
  // board.
  //
  // Nothing exercised it: today's one builder
  // (`SalonBookingsScreen.boardWindowFor`) is provably vacuous, so every test
  // in the suite walks past the assert without touching it, and DELETING the
  // assert would change no result anywhere. This group is the negative
  // control for the tripwire itself — a deliberately too-narrow window, fed
  // through the real composition.
  // ═══════════════════════════════════════════════════════════════════════
  group('the boardWindowBuilder vacuity assert', () {
    testWidgets(
      'a builder whose window EXCLUDES a booking trips the debug assert — the '
      'guard that stops a future window silently truncating a salon board',
      (tester) async {
        await pump(
          tester,
          useScheduleWindow: false,
          bookings: <Booking>[
            _booking(id: 'in', startAtUtc: _kyivAtUtc(9)),
            // 20:00 — outside the hostile window below, so the shared filter
            // genuinely drops it and hands back a DIFFERENT list instance.
            _booking(id: 'out', startAtUtc: _kyivAtUtc(20)),
          ],
          // 09:00–10:00: narrower than the day's own bookings, which is
          // exactly the shape `salonBoardWindow` exists to make impossible.
          boardWindowBuilder: (List<Booking> _, DateTime _) =>
              const ScheduleTimelineWindow(
                firstMinute: 9 * 60,
                windowEndMinute: 10 * 60,
                isExplicitTimes: false,
              ),
        );

        expect(
          tester.takeException(),
          isA<AssertionError>().having(
            (AssertionError e) => e.message.toString(),
            'message',
            contains('EXCLUDES bookings'),
          ),
          reason:
              'the vacuity assert did not fire on a window that drops a '
              'booking — deleting it would let a future boardWindowBuilder '
              'truncate a manager\'s board with no test turning red',
        );
      },
    );

    testWidgets(
      'and a VACUOUS window passes straight through — the assert is a '
      'tripwire, not a blanket ban on the parameter',
      (tester) async {
        await pump(
          tester,
          useScheduleWindow: false,
          bookings: <Booking>[
            _booking(id: 'in', startAtUtc: _kyivAtUtc(9)),
            _booking(id: 'out', startAtUtc: _kyivAtUtc(20)),
          ],
          // Wide enough to admit both starts — the shape today's real builder
          // always produces.
          boardWindowBuilder: (List<Booking> _, DateTime _) =>
              const ScheduleTimelineWindow(
                firstMinute: 8 * 60,
                windowEndMinute: 22 * 60,
                isExplicitTimes: false,
              ),
        );

        expect(tester.takeException(), isNull);
        // …and BOTH bookings are on the board, which is the outcome the
        // assert exists to protect.
        expect(find.byType(BookingsTimelineGrid), findsOneWidget);
        // The ruler was bound by the SUPPLIED window, not by the bookings:
        // 08:00 comes from neither booking (the earliest starts at 09:00).
        final List<String> labels = tester
            .widgetList<Text>(
              find.descendant(
                of: find.byType(TimelineHourRuler),
                matching: find.byType(Text),
              ),
            )
            .map((Text t) => t.data ?? '')
            .toList(growable: false);
        expect(labels.first, '08:00');
      },
    );
  });
}
