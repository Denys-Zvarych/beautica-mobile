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

  /// [statuses] is the MASTER's RAW selection (what the filter sheet would
  /// resolve with), seeded through `widget.query` exactly as the screen's own
  /// `initState` reads it — never a pre-resolved wire set (`dayListWireStatuses`
  /// is not idempotent). Empty = the untouched screen.
  ///
  /// [serviceIds] is the same thing for the SERVICE half of the filter, seeded
  /// the same way (`bookings_discovery_view.dart:378` reads it off
  /// `widget.query` verbatim — there is no wire mapping on this half).
  ///
  /// [bookingsWhenServiceFiltered] models the SERVER doing its job: the rows a
  /// service-narrowed request comes back with. Defaults to [bookings], i.e. a
  /// server that ignored the filter. The stub reads the real `serviceIds`
  /// argument off the invocation rather than being keyed on the seed, so the
  /// answer changes when the SCREEN changes the query — which is what makes
  /// the «Скинути фільтри» round-trip below a real assertion.
  Future<void> pump(
    WidgetTester tester, {
    required List<Booking> bookings,
    required List<EffectiveDay> scheduleDays,
    Set<BookingStatus> statuses = const <BookingStatus>{},
    Set<String> serviceIds = const <String>{},
    List<Booking>? bookingsWhenServiceFiltered,
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
    ).thenAnswer((Invocation i) async {
      final Iterable<String> requested =
          (i.namedArguments[#serviceIds] as Iterable<String>?) ??
          const <String>[];
      final List<Booking> rows = requested.isEmpty
          ? bookings
          : (bookingsWhenServiceFiltered ?? bookings);
      return PageResponse<Booking>(
        items: rows,
        page: 0,
        totalPages: 1,
        totalElements: rows.length,
      );
    });

    await tester.pumpApp(
      BookingsDiscoveryView(
        query: BookingsDayQuery.of(
          day: _day,
          statuses: statuses,
          serviceIds: serviceIds,
        ),
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

  // ═══════════════════════════════════════════════════════════════════════
  // THE FALSE-«ВІЛЬНО» BUG, at the COMPOSITION tier (user-reported, fixed
  // 2026-08-13). `declared_time_cards_test.dart` pins what the widget does
  // with `showsAllOccupancy`; `bookings_day_query_test.dart` pins which
  // selections set it. Only this file can prove the screen actually READS
  // the live query (not the raw selection, not a hard-coded `true`) and
  // threads the answer down — the exact wiring the bug was missing.
  //
  // «Завершені» only is the fixture: it resolves to the wire set
  // `{COMPLETED}`, which cannot see an upcoming CONFIRMED booking — the
  // worst practical case in the reported blast radius.
  // ═══════════════════════════════════════════════════════════════════════
  group('an EXPLICIT_TIMES day under a filter that hides occupancy', () {
    const List<TimeOfDay> declared = <TimeOfDay>[
      TimeOfDay(hour: 11, minute: 0),
      TimeOfDay(hour: 16, minute: 0),
    ];

    List<EffectiveDay> explicitDay() => <EffectiveDay>[
      EffectiveDay(
        date: _day,
        source: EffectiveSource.overrideCustom,
        intervals: const <WorkInterval>[],
        times: declared,
      ),
    ];

    testWidgets('renders NO free cards — the returned booking still shows, the '
        'unmatched declared time does not claim to be free', (tester) async {
      // The filter returned one row; the OTHER declared time's occupancy is
      // unknowable from this list, so it must render nothing at all.
      final Booking returned = _booking(
        id: 'filtered-hit',
        startAtUtc: _kyivAtUtc(11, 0),
      );

      await pump(
        tester,
        bookings: <Booking>[returned],
        scheduleDays: explicitDay(),
        statuses: const <BookingStatus>{BookingStatus.completed},
      );

      expect(find.byType(DeclaredTimeCards), findsOneWidget);
      expect(
        find.byKey(const Key('master-booking-card-filtered-hit')),
        findsOneWidget,
        reason: 'the booking the filter DID return must still render',
      );
      expect(
        find.byKey(const Key('declared-time-card-free-1600')),
        findsNothing,
        reason:
            '16:00 may well be booked by a CONFIRMED booking «Завершені» '
            'hid — the screen must not claim it is free '
            '(MUTATION-VERIFIED: hard-coding showsAllOccupancy: true in '
            '_body turns this RED)',
      );
      // The header counts BOOKINGS, and now equals the rendered card count
      // exactly (free cards were the only uncounted rows).
      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(BookingsDiscoveryView)),
      );
      expect(find.text(l10n.masterBookingsCount(1)), findsOneWidget);
    });

    testWidgets(
      'with NO matching booking it shows the filter-aware empty state, not a '
      'blank column',
      (tester) async {
        await pump(
          tester,
          bookings: const <Booking>[],
          scheduleDays: explicitDay(),
          statuses: const <BookingStatus>{BookingStatus.completed},
        );

        expect(
          find.byType(MasterBookingsNoResultsState),
          findsOneWidget,
          reason:
              'this state was UNREACHABLE on an explicit-times day (it was '
              'gated on `window == null`, and a resolved explicit-times day '
              'always has a window) — suppressing the free cards would have '
              'left the day blank without re-enabling it',
        );
        expect(
          find.byType(MasterBookingsEmptyState),
          findsNothing,
          reason:
              'the two empties must not be conflated — the master DID filter',
        );
        expect(find.byType(DeclaredTimeCards), findsNothing);
      },
    );

    testWidgets(
      'the UNFILTERED day with the same empty result is untouched — free '
      'cards still render, no empty state',
      (tester) async {
        // The negative control for both tests above: the default view is
        // occupancy-COMPLETE, so «Вільно» is a claim it may still make.
        await pump(
          tester,
          bookings: const <Booking>[],
          scheduleDays: explicitDay(),
        );

        expect(find.byType(DeclaredTimeCards), findsOneWidget);
        expect(
          find.byKey(const Key('declared-time-card-free-1100')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('declared-time-card-free-1600')),
          findsOneWidget,
        );
        expect(find.byType(MasterBookingsNoResultsState), findsNothing);
        expect(find.byType(MasterBookingsEmptyState), findsNothing);
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════
  // THE SERVICE HALF — the SECOND, INDEPENDENT instance of the same bug.
  //
  // `serviceIds` goes on the wire too (`bookings_day_notifier.dart:369`), so
  // narrowing to one service hides every booking of ANOTHER service. It
  // falsified `showsAllOccupancy` even with NO status filter — i.e. on the
  // otherwise-correct DEFAULT view, the one place the status half could never
  // reach. `bookings_day_query_test.dart` pins the predicate for it; only a
  // RENDERED case proves the screen actually threads THAT term down, rather
  // than threading a status-only answer that happens to agree.
  //
  // Both tests below therefore leave `statuses` at the default (untouched)
  // selection on purpose: with a status filter present, a screen that read
  // only the status half would still pass.
  // ═══════════════════════════════════════════════════════════════════════
  group('an EXPLICIT_TIMES day under a SERVICE filter only', () {
    const List<TimeOfDay> declared = <TimeOfDay>[
      TimeOfDay(hour: 11, minute: 0),
      TimeOfDay(hour: 16, minute: 0),
    ];

    List<EffectiveDay> explicitDay() => <EffectiveDay>[
      EffectiveDay(
        date: _day,
        source: EffectiveSource.overrideCustom,
        intervals: const <WorkInterval>[],
        times: declared,
      ),
    ];

    testWidgets(
      'renders NO free cards even with the DEFAULT status selection — the '
      'returned booking still shows',
      (tester) async {
        // 16:00 may be booked by a booking of a DIFFERENT service, which this
        // request could never have returned. The status wire set here is the
        // occupancy-COMPLETE default, so only the service term can suppress.
        final Booking returned = _booking(
          id: 'svc-hit',
          startAtUtc: _kyivAtUtc(11, 0),
        );

        await pump(
          tester,
          bookings: const <Booking>[],
          bookingsWhenServiceFiltered: <Booking>[returned],
          scheduleDays: explicitDay(),
          serviceIds: const <String>{'svc-1'},
        );

        expect(find.byType(DeclaredTimeCards), findsOneWidget);
        expect(
          find.byKey(const Key('master-booking-card-svc-hit')),
          findsOneWidget,
          reason: 'the booking the service filter DID return must still render',
        );
        expect(
          find.byKey(const Key('declared-time-card-free-1600')),
          findsNothing,
          reason:
              'a service filter alone falsifies occupancy completeness — the '
              'screen must not claim 16:00 is «Вільно» while holding a list '
              'that could not contain another service\'s booking '
              '(MUTATION-VERIFIED: dropping the `serviceIds.isEmpty` term '
              'from showsAllOccupancy turns this RED)',
        );
      },
    );

    testWidgets(
      'with no matching booking it offers «Скинути фільтри», and the CTA '
      'actually restores the free cards',
      (tester) async {
        // Lead 4 + lead 2 in one round trip. The empty gate must pick the
        // filter-aware copy (a service filter is a user filter, so the
        // `assert(showsAllOccupancy || hasFilters)` above it holds), and the
        // CTA must be wired to `_clearAllFilters` — which clears `_serviceIds`
        // too, not only `_statuses`.
        await pump(
          tester,
          bookings: const <Booking>[],
          bookingsWhenServiceFiltered: const <Booking>[],
          scheduleDays: explicitDay(),
          serviceIds: const <String>{'svc-1'},
        );

        expect(find.byType(MasterBookingsNoResultsState), findsOneWidget);
        expect(
          find.byType(MasterBookingsEmptyState),
          findsNothing,
          reason:
              'the master DID filter — offering no escape hatch would strand '
              'them on a blank explicit-times day',
        );

        await tester.tap(
          find.byKey(const Key('master-bookings-clear-filters')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byType(MasterBookingsNoResultsState),
          findsNothing,
          reason: 'the CTA must clear the SERVICE filter, not just statuses',
        );
        expect(
          find.byKey(const Key('declared-time-card-free-1100')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('declared-time-card-free-1600')),
          findsOneWidget,
          reason:
              'clearing restores occupancy completeness, so the free cards '
              'come back — suppression is reversible, never a deletion',
        );
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
