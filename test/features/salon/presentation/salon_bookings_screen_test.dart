// Phase 21.12 QA — [SalonBookingsScreen], the salon owner/admin «Записи»
// board.
//
// WHY THIS FILE EXISTS
// --------------------
// The phase shipped with `grep -arln "SalonBookingsScreen" test/
// integration_test/` returning NOTHING. `salon_bookings_board_test.dart`
// covers the GRID widget and the density token; the SCREEN — the seed query's
// scope, the roster→columns seam, the four async states, the inert (+)
// placeholder and the drill-in target — had zero coverage. Every one of those
// is a behaviour only this composition owns.
//
// HOW IT IS ISOLATED
// ------------------
// One override boundary, at the two REPOSITORIES, not at the providers above
// them: `bookingRepositoryProvider` + `salonRepositoryProvider`. That keeps
// `salonMastersRosterProvider`, `salonManagementProfileProvider`,
// `bookingsDayProvider` and `BookingsDayNotifier._narrowSalonDay` all REAL, so
// these tests exercise the wiring the screen actually ships instead of a
// hand-stubbed echo of it. `authProvider` is stubbed and SETTLED before the
// first read — `BookingsDayNotifier.build` watches
// `authProvider.select(authUserIdOrNull)`, and reading it mid-`AsyncLoading`
// would fire a second, logout-unrelated fetch (the same reasoning
// `bookings_day_notifier_test.dart`'s own `_containerWithAuth` states).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/application/booked_days_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_day_rail.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_filter_sheet.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_timeline_grid.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_booking_card.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_column_strip.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/salon/data/salon_repository.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_master_summary.dart';
import 'package:beautica_mobile/features/salon/domain/salon_staff_member.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/timeline_hour_ruler.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_bookings_screen.dart';
import 'package:beautica_mobile/features/schedule/data/schedule_repository.dart';
import 'package:beautica_mobile/features/schedule/data/schedule_repository_provider.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/l10n/app_localizations_uk.dart';

import '../../../helpers/pump_app.dart';

class _MockBookingRepository extends Mock implements BookingRepository {}

class _MockSalonRepository extends Mock implements SalonRepository {}

/// Phase 335 — the board's roster-wide working-hours read
/// (`GET /salons/{id}/masters/effective-schedule`).
///
/// Mocked at the REPOSITORY, like the two above and for the same reason: it
/// keeps `salonEffectiveScheduleProvider` — the family key, its 5-minute TTL
/// pin, and `SalonBookingsScreen`'s own month derivation — REAL, so these tests
/// exercise the wiring the screen ships rather than a hand-stubbed echo of it.
///
/// It MUST be overridden in every test that mounts this screen, stub or not:
/// unoverridden it is the real `HttpSalonRosterScheduleRepository` over the
/// real Dio, whose failure is then RETRIED by `beauticaProviderRetry` and
/// leaves a pending timer behind — which surfaces as "A Timer is still pending
/// even after the widget tree was disposed" in whichever test disposes first,
/// not in the one that caused it.
class _MockSalonRosterScheduleRepository extends Mock
    implements SalonRosterScheduleRepository {}

const String _salonId = 'salon-1';

const User _owner = User(
  id: 'user-owner-1',
  email: 'owner@beautica.ua',
  role: UserRole.salonOwner,
  firstName: 'Настя',
  lastName: 'Салон',
);

class _SettledAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async =>
      const AuthSession.authenticated(user: _owner, accessToken: 'token');
}

/// Kyiv 2026-06-15 10:00 — the clock the screen's seed query is anchored to.
///
/// FIXED, and the SAME clock the fixtures below are built from: the test-clock
/// coherence invariant is about MIXING a pinned `clockProvider` with a
/// host-clock fixture, never about pinning as such. Both halves here are
/// pinned to this one instant, so the board's `kyivToday(clock)` day and the
/// bookings' `startAt` describe the same calendar day on any host timezone.
// future-date-ok: fixed PAST Kyiv instant; both the clock and every fixture
final DateTime _now = DateTime.utc(2026, 6, 15, 7);

DateTime _kyiv(int hour) => DateTime.utc(2026, 6, 15, hour - 3);

Booking _booking({
  required String id,
  required String masterId,
  required int hour,
  BookingStatus status = BookingStatus.confirmed,
  String serviceId = 'service-1',
}) {
  final DateTime start = _kyiv(hour);
  return Booking(
    id: id,
    masterId: masterId,
    masterFirstName: 'Оля',
    masterLastName: 'Коваль',
    masterType: 'SALON_MASTER',
    clientFirstName: 'Марія',
    clientLastName: 'Іванюк',
    serviceId: serviceId,
    serviceName: 'Манікюр',
    durationMinutes: 60,
    price: 500,
    startAt: start,
    endAt: start.add(const Duration(hours: 1)),
    status: status,
    canReview: false,
  );
}

SalonMasterSummary _rosterMaster(String id, String first, String last) =>
    SalonMasterSummary(
      masterId: id,
      firstName: first,
      lastName: last,
      type: MasterType.salonMaster,
      professionalTitle: 'Стиліст',
      avgRating: 4.8,
      reviewCount: 12,
    );

PageResponse<Booking> _page(List<Booking> items) => PageResponse<Booking>(
  items: items,
  page: 0,
  totalPages: 1,
  totalElements: items.length,
);

void main() {
  setUpAll(() {
    registerFallbackValue(BookingSort.oldest);
    registerFallbackValue(DateTime.utc(2026));
  });

  late _MockBookingRepository bookingRepo;
  late _MockSalonRepository salonRepo;
  late _MockSalonRosterScheduleRepository rosterScheduleRepo;

  setUp(() {
    bookingRepo = _MockBookingRepository();
    salonRepo = _MockSalonRepository();
    rosterScheduleRepo = _MockSalonRosterScheduleRepository();
  });

  /// Phase 335 — seeds `GET /salons/{id}/masters/effective-schedule`.
  ///
  /// EMPTY by default (registered as a `setUp` below), which is the board's
  /// DEGRADED shape: no master contributes a window, `boardWindowFor` returns
  /// `null`, and every pre-existing expectation in this file sees the
  /// booking-derived timeline it always saw. That is the whole
  /// backwards-compatibility argument, executed rather than asserted in prose.
  void stubRosterSchedule([
    Map<String, List<EffectiveDay>> byMaster =
        const <String, List<EffectiveDay>>{},
  ]) {
    when(
      () =>
          rosterScheduleRepo.salonRosterEffectiveSchedule(any(), any(), any()),
    ).thenAnswer((_) async => byMaster);
  }

  /// An INTERVAL working day on the fixture date `[startHour:00, endHour:00)`.
  EffectiveDay working(int startHour, int endHour) => EffectiveDay(
    date: DateTime(2026, 6, 15),
    source: EffectiveSource.template,
    intervals: <WorkInterval>[
      WorkInterval(
        start: TimeOfDay(hour: startHour, minute: 0),
        end: TimeOfDay(hour: endHour, minute: 0),
      ),
    ],
  );

  setUp(() => stubRosterSchedule());

  /// Stubs `GET /bookings/salon/{salonId}` with STRICT argument matching on
  /// every field the screen is responsible for putting on the wire (M4): the
  /// salon id from the route, a WHOLE Kyiv day (`from == to == day`), no
  /// `masterId` narrowing, and the ascending sort `assignLanes` requires. A
  /// permissive `any()` here would pass on a board that fetched the wrong
  /// salon, the wrong day, or a descending page.
  void stubSalonDay(List<Booking> items) {
    when(
      () => bookingRepo.getSalonBookings(
        salonId: _salonId,
        masterId: null,
        from: DateTime(2026, 6, 15),
        to: DateTime(2026, 6, 15),
        sort: BookingSort.oldest,
        page: 0,
        size: 100,
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) async => _page(items));
  }

  void stubRoster(List<SalonMasterSummary> roster) {
    when(
      () => salonRepo.getSalonMasters(_salonId),
    ).thenAnswer((_) async => roster);
  }

  /// The salon's own name + staff, the subtitle's source. Stubbed on the
  /// REPOSITORY so `salonManagementProfileProvider` — which `.wait`s the two
  /// reads in parallel — resolves for real rather than being replaced.
  void stubSalonProfile({String name = 'Салон «Велвет»'}) {
    when(
      () => salonRepo.getSalonById(_salonId),
    ).thenAnswer((_) async => Salon(id: _salonId, name: name));
    when(
      () => salonRepo.getSalonStaff(_salonId),
    ).thenAnswer((_) async => const <SalonStaffMember>[]);
  }

  /// `GET /salons/mine` — what `canManageSalonProvider` resolves the owner's
  /// ownership of [_salonId] against (audit M3). Stubbed on the REPOSITORY,
  /// like every other fetch in this file, so `mySalonsProvider` and the
  /// capability predicate above it both stay REAL.
  ///
  /// [owns] `false` serves a list that does NOT contain [_salonId] — a
  /// resolved, genuinely-foreign salon, which is the case the fail-closed
  /// predicate exists for.
  void stubMySalons({bool owns = true}) {
    when(() => salonRepo.getMySalons()).thenAnswer(
      (_) async => <Salon>[
        if (owns) const Salon(id: _salonId, name: 'Салон «Велвет»'),
        const Salon(id: 'salon-someone-else', name: 'Інший салон'),
      ],
    );
  }

  // Registered AFTER the mock-construction `setUp` above, so it runs second
  // and stubs the freshly-built `salonRepo`. Every widget test in this file
  // needs it: without a resolved `GET /salons/mine` the fail-closed
  // `canManageSalonProvider` (audit M3) renders the denied state instead of
  // the board. The one test that WANTS the denied state re-stubs it.
  setUp(() => stubMySalons());

  /// `GET /bookings/salon/{salonId}/booked-days` — the rail's dot set (backend
  /// Phase 319). Registered for EVERY test in this file, like [stubMySalons]
  /// above: the board issues it on mount, and an unstubbed mocktail call there
  /// lands inside an `AsyncValue` the rail silently reads as "no dots", so a
  /// missing stub would never surface as a failure — it would just make every
  /// dot assertion in this file vacuous.
  ///
  /// Answers with the fixture day itself, so the rail's dot and the board's
  /// cards describe the same Kyiv day.
  setUp(() {
    when(
      () => bookingRepo.getSalonBookedDays(
        salonId: any(named: 'salonId'),
        from: any(named: 'from'),
        to: any(named: 'to'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) async => <DateTime>[DateTime(2026, 6, 15)]);
  });

  List<Object> overrides() => <Object>[
    bookingRepositoryProvider.overrideWithValue(bookingRepo),
    salonRepositoryProvider.overrideWithValue(salonRepo),
    salonRosterScheduleRepositoryProvider.overrideWithValue(rosterScheduleRepo),
    authProvider.overrideWith(_SettledAuthNotifier.new),
    clockProvider.overrideWithValue(() => _now),
  ];

  Future<void> pumpScreen(
    WidgetTester tester, {
    double? textScaleFactor,
    Duration? Function(int, Object)? retry = beauticaProviderRetry,
    // Phase 335 — the viewport HEIGHT, 720 by default (unchanged for every
    // pre-existing test in this file). One test overrides it: a 22:00 card
    // sits ~1100dp down a 09:00-anchored salon-density timeline, past
    // `_LaneColumn`'s viewport-culling edge, so at 720 it is replaced by a
    // placeholder and `find.byKey('timeline-card-…')` misses it — which is
    // indistinguishable from the booking having been FILTERED AWAY, the very
    // thing that test exists to rule out. A taller viewport removes the
    // ambiguity at the source instead of papering over it with a scroll
    // gesture.
    double height = 720,
  }) => tester.pumpApp(
    const SalonBookingsScreen(salonId: _salonId),
    overrides: overrides(),
    width: 360,
    height: height,
    textScaleFactor: textScaleFactor,
    retry: retry,
  );

  // ═════════════════════════════════════════════════════════════════════════
  // 1. columnsFor — the roster→column seam, as a pure function.
  // ═════════════════════════════════════════════════════════════════════════
  group('SalonBookingsScreen.columnsFor', () {
    test('emits ONE column per roster master, in roster order', () {
      final List<TimelineBoardColumn> columns = SalonBookingsScreen.columnsFor(
        <Booking>[
          _booking(id: 'a1', masterId: 'm2', hour: 10),
          _booking(id: 'a2', masterId: 'm1', hour: 11),
        ],
        <SalonMasterSummary>[
          _rosterMaster('m1', 'Оля', 'Коваль'),
          _rosterMaster('m2', 'Ніна', 'Бойко'),
        ],
      );

      expect(columns, hasLength(2));
      expect(columns[0].header.masterId, 'm1');
      expect(columns[1].header.masterId, 'm2');
      // Order is the ROSTER's, never the bookings' — m2 booked first and is
      // still second.
      expect(columns[0].bookings.single.id, 'a2');
      expect(columns[1].bookings.single.id, 'a1');
    });

    test('partitions: every booking lands in exactly one column, and the '
        'column ORDER within a master is the incoming order', () {
      final List<TimelineBoardColumn> columns = SalonBookingsScreen.columnsFor(
        <Booking>[
          _booking(id: 'a1', masterId: 'm1', hour: 9),
          _booking(id: 'a2', masterId: 'm1', hour: 10),
          _booking(id: 'a3', masterId: 'm1', hour: 11),
        ],
        <SalonMasterSummary>[_rosterMaster('m1', 'Оля', 'Коваль')],
      );

      expect(
        columns.single.bookings.map((Booking b) => b.id),
        <String>['a1', 'a2', 'a3'],
        reason:
            'columnsFor PARTITIONS, it must never re-sort — assignLanes walks '
            'its input once and is correct only on an ascending stream',
      );
    });

    test('a master with NOTHING booked still gets a column', () {
      final List<TimelineBoardColumn> columns = SalonBookingsScreen.columnsFor(
        <Booking>[_booking(id: 'a1', masterId: 'm1', hour: 10)],
        <SalonMasterSummary>[
          _rosterMaster('m1', 'Оля', 'Коваль'),
          _rosterMaster('m2', 'Ніна', 'Бойко'),
          _rosterMaster('m3', 'Іра', 'Ткач'),
        ],
      );

      expect(columns, hasLength(3));
      expect(columns[1].bookings, isEmpty);
      expect(columns[2].bookings, isEmpty);
      expect(columns[1].header.bookingCount, 0);
    });

    test('the single-master case is ONE column carrying everything', () {
      final List<TimelineBoardColumn> columns = SalonBookingsScreen.columnsFor(
        <Booking>[
          _booking(id: 'a1', masterId: 'm1', hour: 10),
          _booking(id: 'a2', masterId: 'm1', hour: 12),
        ],
        <SalonMasterSummary>[_rosterMaster('m1', 'Оля', 'Коваль')],
      );

      expect(columns, hasLength(1));
      expect(columns.single.bookings, hasLength(2));
      expect(columns.single.header.bookingCount, 2);
    });

    test('an EMPTY roster produces NO columns — never a synthetic one', () {
      expect(
        SalonBookingsScreen.columnsFor(<Booking>[
          _booking(id: 'a1', masterId: 'm1', hour: 10),
        ], const <SalonMasterSummary>[]),
        isEmpty,
      );
    });

    test('a booking whose master left the roster is DROPPED, and the header '
        'count drops with it', () {
      final List<TimelineBoardColumn> columns = SalonBookingsScreen.columnsFor(
        <Booking>[
          _booking(id: 'a1', masterId: 'm1', hour: 10),
          // `ghost` is not in the roster — a master removed after the booking
          // was placed. Dropping it is the documented contract; what must NOT
          // happen is it landing in someone else's column.
          _booking(id: 'ghost', masterId: 'gone', hour: 11),
        ],
        <SalonMasterSummary>[_rosterMaster('m1', 'Оля', 'Коваль')],
      );

      expect(columns.single.bookings.map((Booking b) => b.id), <String>['a1']);
      expect(columns.single.header.bookingCount, 1);
    });

    test('bookingCount equals the column it describes, for every column', () {
      final List<TimelineBoardColumn> columns = SalonBookingsScreen.columnsFor(
        <Booking>[
          _booking(id: 'a1', masterId: 'm1', hour: 9),
          _booking(id: 'a2', masterId: 'm1', hour: 10),
          _booking(id: 'b1', masterId: 'm2', hour: 11),
        ],
        <SalonMasterSummary>[
          _rosterMaster('m1', 'Оля', 'Коваль'),
          _rosterMaster('m2', 'Ніна', 'Бойко'),
          _rosterMaster('m3', 'Іра', 'Ткач'),
        ],
      );

      for (final TimelineBoardColumn c in columns) {
        expect(
          c.header.bookingCount,
          c.bookings.length,
          reason: 'chip count vs cards for ${c.header.masterId}',
        );
      }
    });

    test('the roster unrated convention is carried through untouched', () {
      final List<TimelineBoardColumn> columns = SalonBookingsScreen.columnsFor(
        const <Booking>[],
        <SalonMasterSummary>[
          const SalonMasterSummary(
            masterId: 'm1',
            firstName: 'Оля',
            lastName: 'Коваль',
            type: MasterType.salonMaster,
            reviewCount: 0,
          ),
        ],
      );

      expect(
        columns.single.header.avgRating,
        isNull,
        reason:
            'an unreviewed master must reach the chip as null so it renders '
            'MasterStrip.noRatingLabel, never a damning 0.0',
      );
      expect(columns.single.header.name, 'Оля Коваль');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // 2. The four async states.
  // ═════════════════════════════════════════════════════════════════════════
  group('SalonBookingsScreen — async states', () {
    testWidgets('LOADED: renders the board with one chip per roster master, '
        'and the cards the salon day returned', (WidgetTester tester) async {
      stubRoster(<SalonMasterSummary>[
        _rosterMaster('m1', 'Оля', 'Коваль'),
        _rosterMaster('m2', 'Ніна', 'Бойко'),
      ]);
      stubSalonProfile();
      stubSalonDay(<Booking>[
        _booking(id: 'a1', masterId: 'm1', hour: 10),
        _booking(id: 'b1', masterId: 'm2', hour: 11),
      ]);

      await pumpScreen(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('salon-bookings-screen')), findsOneWidget);
      expect(find.byType(MasterColumnStrip), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('salon-bookings-column-chip-m1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('salon-bookings-column-chip-m2')),
        findsOneWidget,
      );
      // Data binding, not a smoke test: the specific cards, by id.
      expect(
        find.byKey(const ValueKey<String>('timeline-card-a1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('timeline-card-b1')),
        findsOneWidget,
      );
    });

    // ═══════════════════════════════════════════════════════════════════
    // PHASE 335 — the timeline spans the ROSTER'S HOURS, not the bookings.
    //
    // Asserted on RENDERED OUTPUT — the hour labels [TimelineHourRuler]
    // actually painted — never on `BookingsTimelineGrid.scheduleFirstMinute`.
    // Reading that field would prove the screen PASSED a number, not that the
    // number produced a taller ruler; a widget-field assertion is vacuous
    // about layout by construction.
    //
    // Each test pumps ONCE. Two passes inside one `testWidgets` would NOT
    // work: `pumpApp` reuses the same `ProviderScope` element and therefore
    // the same container, and `SalonEffectiveScheduleNotifier` pins itself
    // with a 5-minute `keepAlive`, so the second pass would be served the
    // FIRST pass's cached map and both renders would come out identical —
    // a silently vacuous "no change detected".
    // ═══════════════════════════════════════════════════════════════════

    /// The wall-clock labels [TimelineHourRuler] painted, top to bottom.
    List<String> rulerLabels(WidgetTester tester) => tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(TimelineHourRuler),
            matching: find.byType(Text),
          ),
        )
        .map((Text t) => t.data ?? '')
        .toList(growable: false);

    testWidgets(
      'the timeline spans the UNION of every master\'s hours — the ruler runs '
      '09:00→20:00 even though the only booking is 10:00–11:00',
      (WidgetTester tester) async {
        stubRoster(<SalonMasterSummary>[
          _rosterMaster('m1', 'Оля', 'Коваль'),
          _rosterMaster('m2', 'Ніна', 'Бойко'),
        ]);
        stubSalonProfile();
        stubRosterSchedule(<String, List<EffectiveDay>>{
          'm1': <EffectiveDay>[working(9, 18)],
          // The 20:00 close comes from the SECOND master. Neither master's own
          // window is 09:00–20:00 — that pair only exists as a UNION, which is
          // exactly what makes this assertion about the union and not about
          // whichever master happens to be first.
          'm2': <EffectiveDay>[working(11, 20)],
        });
        stubSalonDay(<Booking>[_booking(id: 'a1', masterId: 'm1', hour: 10)]);

        await pumpScreen(tester);
        await tester.pumpAndSettle();

        // Twelve labels, 09:00 … 20:00 inclusive. Without the union this same
        // fixture renders the booking-derived window — 10:00 → 11:00, two
        // labels — so every one of these three expectations MOVES.
        expect(rulerLabels(tester).first, '09:00');
        expect(rulerLabels(tester).last, '20:00');
        expect(rulerLabels(tester).length, 12);

        // …and the one booking still renders on it.
        expect(
          find.byKey(const ValueKey<String>('timeline-card-a1')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'a day nobody works falls back to the booking-derived window — the '
      'roster-complete response says "off", not "not loaded", and the board '
      'still renders every booking',
      (WidgetTester tester) async {
        stubRoster(<SalonMasterSummary>[_rosterMaster('m1', 'Оля', 'Коваль')]);
        stubSalonProfile();
        stubRosterSchedule(<String, List<EffectiveDay>>{
          'm1': <EffectiveDay>[
            // Present in the map (roster-complete) but resolving to a settled
            // day off — contributes no window.
            EffectiveDay(
              date: DateTime(2026, 6, 15),
              source: EffectiveSource.overrideDayOff,
              intervals: const <WorkInterval>[],
            ),
          ],
        });
        stubSalonDay(<Booking>[_booking(id: 'a1', masterId: 'm1', hour: 10)]);

        await pumpScreen(tester);
        await tester.pumpAndSettle();

        // The booking-derived window, exactly as before this phase — and
        // CRUCIALLY not `MasterBookingsNoWorkingHoursState`, which is the
        // master board's response to an hours-less day and would hide the
        // whole timeline here.
        expect(rulerLabels(tester).first, '10:00');
        expect(
          find.byKey(const ValueKey<String>('timeline-card-a1')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'a 22:00 walk-in past every master\'s closing time is STILL LAID OUT and '
      'still reachable — the data-loss regression this phase exists to make '
      'impossible',
      (WidgetTester tester) async {
        stubRoster(<SalonMasterSummary>[_rosterMaster('m1', 'Оля', 'Коваль')]);
        stubSalonProfile();
        stubRosterSchedule(<String, List<EffectiveDay>>{
          'm1': <EffectiveDay>[working(9, 20)],
        });
        stubSalonDay(<Booking>[
          _booking(id: 'a1', masterId: 'm1', hour: 10),
          // 22:00 — two hours past the close. On the MASTER board
          // (`useScheduleWindow: true`, phase 244) this card is DROPPED
          // outright. On a manager's board that is data loss.
          _booking(id: 'walkin', masterId: 'm1', hour: 22),
        ]);

        await pumpScreen(tester, height: 2400);
        await tester.pumpAndSettle();

        // The ruler was WIDENED to reach it — 09:00 (roster) → 23:00 (the
        // walk-in's own END). A dropped booking could not have moved this.
        expect(rulerLabels(tester).first, '09:00');
        expect(rulerLabels(tester).last, '23:00');

        // AND THE CARD ITSELF. The viewport is tall enough (see
        // [pumpScreen]'s `height`) that `_LaneColumn`'s culling does not
        // reach it, so this finder distinguishes "rendered" from "dropped"
        // rather than from "scrolled out of view".
        expect(
          find.byKey(const ValueKey<String>('timeline-card-walkin')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('timeline-card-a1')),
          findsOneWidget,
        );
        // The header count and the cards come off ONE list — a walk-in that
        // rendered but was not counted would be the header-vs-cards
        // divergence `bookingsInsideScheduleWindow` was extracted to close.
        //
        // The VALUE, not merely the widget's existence (mobile-qa, this
        // audit): `tester.widget<Text>(finder)` throws when the finder misses,
        // so the `isNotNull` this line used to carry could not fail under any
        // circumstance. `contains('2')` reads the rendered number out of the
        // localised plural without coupling the test to the Ukrainian string
        // (M2) — and 2 is BOTH cards, so a board that counted only the
        // in-hours one would print «1 запис» and fail here.
        expect(
          tester
              .widget<Text>(find.byKey(const Key('master-bookings-count')))
              .data,
          contains('2'),
        );
      },
    );

    // ─────────────────────────────────────────────────────────────────
    // QA 2026-09-17 — THE DEFAULT BOARD, END TO END, with the roster's hours
    // actually seeded so `boardWindowFor` returns a real window and
    // `_Loaded.build`'s debug vacuity assert is REACHED. Every pre-existing
    // test in this file walked past that assert because the default
    // `stubRosterSchedule()` is EMPTY — `boardWindowFor` returns `null` and
    // the whole branch is skipped.
    //
    // WHAT IT GUARDS. Freezed's generated `BookingsDayState.items` getter
    // allocates a FRESH `EqualUnmodifiableListView` on every access whenever
    // the stored list is raw, so two reads yield two different objects over
    // the same rows and an `identical` assert fires on wrapper identity
    // rather than on the window — "0 of N would be dropped" on a perfectly
    // ordinary board.
    //
    // THE CAUSE IS NOT THE NARROWING. An earlier reading of this bug blamed
    // `_narrowSalonDay`'s `items.sublist(0, i)` branch — the one a day
    // carrying a CANCELLED or DECLINED row takes, since an untouched
    // `SalonDayQuery` resolves to {CONFIRMED, COMPLETED, NOT_COMPLETED}. That
    // was falsified: `PageResponse` is hand-written, not freezed, so
    // `page.items` is a plain `List` and the UNNARROWED branch stored a raw
    // list too. Every route was affected, and the vacuity group's own "a
    // VACUOUS window passes straight through" case — a plain
    // `MyBookingsQuery`, no narrowing at all — reproduced it.
    //
    // Fixed at the root by `stableBookingList` (`bookings_day_state.dart`),
    // pinned directly in `salon_day_narrowing_test.dart` and
    // `bookings_day_notifier_test.dart`; `_Loaded.build` additionally hoists
    // the getter into a local. This test is the end-to-end guard over both:
    // it keeps a CANCELLED row precisely because that is the branch the
    // original report named, so the composition stays covered on it.
    // ─────────────────────────────────────────────────────────────────
    testWidgets('a day carrying a CANCELLED row — hidden by the DEFAULT status '
        'narrowing, no owner input — still renders the union window and must '
        'NOT trip the board\'s own debug vacuity assert', (
      WidgetTester tester,
    ) async {
      stubRoster(<SalonMasterSummary>[_rosterMaster('m1', 'Оля', 'Коваль')]);
      stubSalonProfile();
      stubRosterSchedule(<String, List<EffectiveDay>>{
        'm1': <EffectiveDay>[working(9, 18)],
      });
      stubSalonDay(<Booking>[
        _booking(id: 'conf', masterId: 'm1', hour: 10),
        // Hidden by `BookingStatus.visibleInDayListByDefault` (locked
        // 2026-08-13) — the narrowing that reshapes the state's list.
        _booking(
          id: 'canc',
          masterId: 'm1',
          hour: 12,
          status: BookingStatus.cancelled,
        ),
      ]);

      await pumpScreen(tester);
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason:
            'the board threw on a perfectly ordinary day. The union window '
            'excludes NOTHING here — the assert is comparing two '
            'freshly-allocated EqualUnmodifiableListView wrappers over the '
            'same rows, so it fires on list IDENTITY rather than on the '
            'window it claims to police',
      );

      // And the board is genuinely intact: roster-bounded ruler, the
      // visible row rendered, the hidden one still hidden.
      expect(rulerLabels(tester).first, '09:00');
      expect(rulerLabels(tester).last, '18:00');
      expect(
        find.byKey(const ValueKey<String>('timeline-card-conf')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('timeline-card-canc')),
        findsNothing,
      );
    });

    testWidgets('LOADING: the skeleton renders and NO board is built', (
      WidgetTester tester,
    ) async {
      stubRoster(const <SalonMasterSummary>[]);
      stubSalonProfile();
      // A future that never completes — the state under test IS the pending
      // one, so it must not be allowed to resolve.
      when(
        () => bookingRepo.getSalonBookings(
          salonId: any(named: 'salonId'),
          masterId: any(named: 'masterId'),
          from: any(named: 'from'),
          to: any(named: 'to'),
          sort: any(named: 'sort'),
          page: any(named: 'page'),
          size: any(named: 'size'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((_) => Completer<PageResponse<Booking>>().future);

      await pumpScreen(tester);
      // TWO pumps, not one (audit M3). Frame 1 builds the screen, which is
      // when `canManageSalonProvider` first reads `mySalonsProvider` — still
      // `AsyncLoading`, so the fail-closed predicate is `false` and the denied
      // state renders. Frame 2 is the first frame with ownership RESOLVED, and
      // is therefore the first frame at which the state under test here — the
      // DAY FETCH's pending state — is the one on screen. The extra pump is
      // about the capability's own resolution, not about the day fetch, which
      // is still deliberately never allowed to complete.
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('master-bookings-skeleton')), findsOneWidget);
      expect(find.byType(BookingsTimelineGrid), findsNothing);
    });

    testWidgets('ERROR — FAILS CLOSED on a 403 from GET /bookings/salon/{id}: '
        'the error state with a retry renders and NOT ONE booking card is '
        'drawn', (WidgetTester tester) async {
      stubRoster(<SalonMasterSummary>[_rosterMaster('m1', 'Оля', 'Коваль')]);
      stubSalonProfile();
      when(
        () => bookingRepo.getSalonBookings(
          salonId: any(named: 'salonId'),
          masterId: any(named: 'masterId'),
          from: any(named: 'from'),
          to: any(named: 'to'),
          sort: any(named: 'sort'),
          page: any(named: 'page'),
          size: any(named: 'size'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer(
        // ASYNC throw, never `thenThrow`: a Dio-backed repository always fails
        // asynchronously, and a synchronous throw during provider build
        // short-circuits Riverpod's retry machinery entirely — the error state
        // would then be one a real 403 never reaches this way.
        (_) async => throw const ServerFailure(statusCode: 403),
      );

      await pumpScreen(tester, retry: (_, _) => null);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('my_bookings_error')), findsOneWidget);
      expect(find.byKey(const Key('my_bookings_error_retry')), findsOneWidget);
      // FAIL CLOSED — this is a multi-tenant PII surface. A forbidden salon
      // day must render NOTHING, not a partial board.
      expect(find.byType(MasterBookingCard), findsNothing);
      expect(find.byType(BookingsTimelineGrid), findsNothing);
    });

    testWidgets('ERROR: tapping retry RE-ISSUES the salon-day fetch', (
      WidgetTester tester,
    ) async {
      stubRoster(<SalonMasterSummary>[_rosterMaster('m1', 'Оля', 'Коваль')]);
      stubSalonProfile();
      int calls = 0;
      when(
        () => bookingRepo.getSalonBookings(
          salonId: any(named: 'salonId'),
          masterId: any(named: 'masterId'),
          from: any(named: 'from'),
          to: any(named: 'to'),
          sort: any(named: 'sort'),
          page: any(named: 'page'),
          size: any(named: 'size'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((_) async {
        calls++;
        throw const ServerFailure(statusCode: 403);
      });

      // The PRODUCTION retry policy treats a 403 as retryable, so leaving it
      // in force would let Riverpod's own automatic re-attempts advance the
      // counter on their own — a test that could not fail. Disabled so the
      // ONLY thing that can advance it is the tap below.
      await pumpScreen(tester, retry: (_, _) => null);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('my_bookings_error')), findsOneWidget);
      final int before = calls;
      expect(before, greaterThan(0));

      await tester.tap(find.byKey(const Key('my_bookings_error_retry')));
      await tester.pumpAndSettle();

      expect(
        calls,
        before + 1,
        reason:
            'the retry button must invalidate bookingsDayProvider for the '
            'LIVE query and hit the salon endpoint exactly once more',
      );
      // Still failing, so still the error state — and still no cards.
      expect(find.byKey(const Key('my_bookings_error')), findsOneWidget);
      expect(find.byType(MasterBookingCard), findsNothing);
    });

    testWidgets('EMPTY: a salon day with no bookings still draws the ROSTER '
        'and a ruled, card-less grid — NOT the illustrated empty state', (
      WidgetTester tester,
    ) async {
      stubRoster(<SalonMasterSummary>[
        _rosterMaster('m1', 'Оля', 'Коваль'),
        _rosterMaster('m2', 'Ніна', 'Бойко'),
      ]);
      stubSalonProfile();
      stubSalonDay(const <Booking>[]);

      await pumpScreen(tester);
      await tester.pumpAndSettle();

      // The locked decision (`bookings_discovery_view.dart`'s `columns ==
      // null` gate): an owner must be able to see WHICH masters are free,
      // which an illustration cannot say. So the illustrated empty state is
      // the WRONG answer here and its absence is the assertion.
      expect(find.byKey(const Key('master-bookings-empty')), findsNothing);
      expect(find.byKey(const Key('master-bookings-no-results')), findsNothing);
      expect(find.byKey(const Key('my_bookings_error')), findsNothing);
      expect(find.byType(MasterBookingCard), findsNothing);

      // …and what IS drawn: the roster, with a chip for every master.
      expect(find.byType(MasterColumnStrip), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('salon-bookings-column-chip-m1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('salon-bookings-column-chip-m2')),
        findsOneWidget,
      );
      expect(find.byType(BookingsTimelineGrid), findsOneWidget);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // 3. The roster fetch is not allowed to masquerade as "a salon with no
  //    masters".
  // ═════════════════════════════════════════════════════════════════════════
  group('SalonBookingsScreen — the roster fetch', () {
    testWidgets('a FAILED roster fetch must not render the no-masters state — '
        'that state means "this salon employs nobody", which is a different '
        'and much worse thing to tell an owner', (WidgetTester tester) async {
      when(
        () => salonRepo.getSalonMasters(_salonId),
      ).thenAnswer((_) async => throw const ServerFailure(statusCode: 403));
      stubSalonProfile();
      stubSalonDay(<Booking>[_booking(id: 'a1', masterId: 'm1', hour: 10)]);

      await pumpScreen(tester);
      await tester.pumpAndSettle();

      // FLIPPED (audit M4, 2026-09-16). This assertion used to PIN the defect
      // — `.value ?? const []` folded an `AsyncError` into "no masters", so a
      // 403 on the roster told the owner their salon employs nobody. The
      // screen now matches on the concrete `AsyncError` subtype and surfaces
      // the failure through the SAME `MyBookingsErrorState` the day fetch
      // already uses, so the observable this test was written against has
      // changed exactly as its old `reason:` said it should.
      expect(
        find.byKey(const Key('salon-bookings-no-masters')),
        findsNothing,
        reason:
            'a roster ERROR must never render the "this salon employs nobody" '
            'copy',
      );
      expect(
        find.byKey(const Key('my_bookings_error')),
        findsOneWidget,
        reason: 'the failure is surfaced, with the shared error panel',
      );
      expect(
        find.byKey(const Key('my_bookings_error_retry')),
        findsOneWidget,
        reason: 'and it carries a retry affordance',
      );
      expect(find.byType(MasterColumnStrip), findsNothing);
    });

    testWidgets('a FAILED salon-profile fetch surfaces too — the subtitle is '
        'the second ownership-sensitive read on this screen and a 403 on it '
        'used to render as a missing line', (WidgetTester tester) async {
      stubRoster(<SalonMasterSummary>[_rosterMaster('m1', 'Оля', 'Коваль')]);
      when(
        () => salonRepo.getSalonById(_salonId),
      ).thenAnswer((_) async => throw const ServerFailure(statusCode: 403));
      when(
        () => salonRepo.getSalonStaff(_salonId),
      ).thenAnswer((_) async => const <SalonStaffMember>[]);
      stubSalonDay(const <Booking>[]);

      await pumpScreen(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('my_bookings_error')), findsOneWidget);
      expect(find.byType(MasterColumnStrip), findsNothing);
    });

    testWidgets('a foreign salonId renders the DENIED state and mounts NO '
        'roster strip — GET /salons/{id}/masters is public, so the router '
        'guard admitting an unresolved owner is not enough on its own', (
      WidgetTester tester,
    ) async {
      // A RESOLVED `GET /salons/mine` that does not contain this salon.
      stubMySalons(owns: false);
      stubRoster(<SalonMasterSummary>[_rosterMaster('m1', 'Оля', 'Коваль')]);
      stubSalonProfile();
      stubSalonDay(const <Booking>[]);

      await pumpScreen(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('salon-bookings-denied')), findsOneWidget);
      expect(find.byType(MasterColumnStrip), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('salon-bookings-column-chip-m1')),
        findsNothing,
        reason: 'a foreign salon\'s roster must never render',
      );
      // ⚠ THE LOAD-BEARING HALF (audit M2, 2026-09-17). Everything above is a
      // UI assertion, and UI assertions alone do NOT pin this behaviour:
      // mobile-security mutation-proved it by HOISTING the
      // `salonEffectiveScheduleProvider` watch ABOVE the
      // `canManageSalonProvider` gate in `salon_bookings_screen.dart` — the
      // denied state still rendered, this whole file stayed green (25/25),
      // and the board had quietly issued a roster-wide schedule fan-out for an
      // attacker-supplied `salonId` on an authenticated Dio carrying the
      // bearer token. The denied render is what the user sees; THIS is what
      // the wire sees, and only this can catch a future watch-hoisting
      // refactor. `any()` on all three params on purpose: the assertion is
      // "not at all", not "not with these arguments".
      verifyNever(
        () => rosterScheduleRepo.salonRosterEffectiveSchedule(
          any(),
          any(),
          any(),
        ),
      );
    });

    testWidgets('a FAILED roster-schedule fetch DEGRADES silently — the board '
        'still renders its booking-derived timeline and NO error panel, '
        'because the schedule is adornment and the bookings are not', (
      WidgetTester tester,
    ) async {
      stubRoster(<SalonMasterSummary>[_rosterMaster('m1', 'Оля', 'Коваль')]);
      stubSalonProfile();
      stubSalonDay(<Booking>[_booking(id: 'a1', masterId: 'm1', hour: 10)]);
      // A 403 on the batch route — the shape a stale/foreign membership
      // produces server-side. Replaces the empty-map `setUp` stub.
      when(
        () => rosterScheduleRepo.salonRosterEffectiveSchedule(
          any(),
          any(),
          any(),
        ),
      ).thenAnswer((_) async => throw const ServerFailure(statusCode: 403));

      await pumpScreen(tester);
      await tester.pumpAndSettle();

      // NOT folded into the `fetchError` gate the roster and salon-profile
      // reads share — see `salon_bookings_screen.dart`'s "WHY THIS FETCH IS
      // NOT IN THE `fetchError` GATE ABOVE". A board showing today's real
      // bookings against a booking-derived window is completely usable; an
      // error panel in its place is not.
      expect(
        find.byKey(const Key('my_bookings_error')),
        findsNothing,
        reason:
            'a schedule failure is ADORNMENT — surfacing it would replace a '
            'usable board with an error panel over a cosmetic window',
      );
      expect(
        find.byKey(const Key('salon-bookings-denied')),
        findsNothing,
        reason: 'and it is certainly not an ownership failure',
      );
      // The board is fully alive: columns mounted, and the day's booking is
      // still on the timeline. `boardWindowFor` simply returned `null` and the
      // grid fell back to its booking-derived bounds — the identical
      // degradation an empty schedule produces (the default `setUp` stub), so
      // a dropped booking here could only come from the failure path itself.
      expect(find.byType(MasterColumnStrip), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('timeline-card-a1')),
        findsOneWidget,
        reason:
            'the degraded window must never exclude a booking — that is the '
            'one thing a wrong window could actually cost the owner',
      );
    });

    testWidgets('a genuinely empty roster renders the no-masters state', (
      WidgetTester tester,
    ) async {
      stubRoster(const <SalonMasterSummary>[]);
      stubSalonProfile();
      stubSalonDay(const <Booking>[]);

      await pumpScreen(tester);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('salon-bookings-no-masters')),
        findsOneWidget,
      );
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // 4. PHASE 340 — the (+) opens the approved salon wizard.
  // ═════════════════════════════════════════════════════════════════════════
  group('SalonBookingsScreen — the create-booking entry point', () {
    testWidgets('tapping (+) pushes RouteNames.salonStaffBookingNew with the '
        'board\'s own salonId as extra, as a fullscreen dialog', (
      WidgetTester tester,
    ) async {
      stubRoster(<SalonMasterSummary>[_rosterMaster('m1', 'Оля', 'Коваль')]);
      stubSalonProfile();
      stubSalonDay(<Booking>[_booking(id: 'a1', masterId: 'm1', hour: 10)]);

      String? capturedExtra;
      final GoRouter router = GoRouter(
        initialLocation: '/board',
        routes: <RouteBase>[
          GoRoute(
            path: '/board',
            builder: (_, _) => const SalonBookingsScreen(salonId: _salonId),
          ),
          // Registered at the SAME path shape production uses
          // (`RouteNames.salonStaffBookingNew` = `/salon/bookings/new`) —
          // no new route constant, mirroring production's own D1 (nothing
          // is registered by this phase, only pushed).
          GoRoute(
            path: RouteNames.salonStaffBookingNew,
            pageBuilder: (_, GoRouterState s) {
              capturedExtra = s.extra as String?;
              return const MaterialPage<void>(
                fullscreenDialog: true,
                child: Scaffold(key: Key('sentinel-salon-wizard')),
              );
            },
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpRoutedApp(router, overrides: overrides());
      await tester.pumpAndSettle();

      final Finder add = find.byKey(const Key('master-bookings-add'));
      expect(
        add,
        findsOneWidget,
        reason: 'the (+) affordance renders for an owner/admin',
      );

      await tester.tap(add);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('sentinel-salon-wizard')),
        findsOneWidget,
        reason:
            'tapping (+) must open the approved salon wizard, not a '
            'no-op — phase 340 is the fill-in for the phase-21.12 '
            'placeholder',
      );
      expect(
        capturedExtra,
        _salonId,
        reason:
            'the wizard is scoped to THIS board\'s salon — the extra is '
            'the salonId the board itself was constructed with',
      );
      // A PUSH, not a `context.go` — production reads `context.push(...)`
      // (`salon_bookings_screen.dart:_openCreateBooking`). `capturedExtra`/
      // the sentinel widget above only prove the destination was reached;
      // they pass identically under a `context.go`, which would ALSO
      // rebuild the same registered route with the same extra. The board
      // still being mounted underneath is what a push-not-go actually buys
      // (a `go` tears the current page out of the stack), so it is asserted
      // directly below.
      // `skipOffstage: false` — the board is still mounted underneath the
      // fullscreen-dialog route, but a `Navigator`-pushed non-topmost route
      // is offstage (kept alive, not painted), which the default finder
      // filters out (`CommonFinders.byKey`'s `skipOffstage: true` default) —
      // see `flutter_test/finders.dart`.
      expect(
        find.byKey(const Key('salon-bookings-screen'), skipOffstage: false),
        findsOneWidget,
        reason:
            'a context.push (not context.go) must leave the board '
            'mounted underneath',
      );
      //
      // The SALON_MASTER absence of this button (`canCreateBooking:
      // ref.watch(bookingCreationEnabledProvider)`, unedited by this phase —
      // D3) is covered by `bookings_capability_test.dart`'s own role-matrix,
      // not re-derived here with a second session fixture.
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // 5. THE DRILL-IN TARGET.
  // ═════════════════════════════════════════════════════════════════════════
  group('SalonBookingsScreen — the drill-in target', () {
    testWidgets('tapping a card pushes /salon/bookings/:id — the OWNER-gated '
        'path — and NOT the CLIENT-gated /bookings/:id', (
      WidgetTester tester,
    ) async {
      stubRoster(<SalonMasterSummary>[_rosterMaster('m1', 'Оля', 'Коваль')]);
      stubSalonProfile();
      stubSalonDay(<Booking>[_booking(id: 'bk-1', masterId: 'm1', hour: 10)]);

      final List<String> visited = <String>[];
      final GoRouter router = GoRouter(
        initialLocation: '/board',
        routes: <RouteBase>[
          GoRoute(
            path: '/board',
            builder: (_, _) => const SalonBookingsScreen(salonId: _salonId),
          ),
          // BOTH candidate destinations are registered, each with a DISTINCT
          // sentinel. A test that registered only the expected one could pass
          // on a 404/no-op just as well as on a correct push.
          GoRoute(
            path: '${RouteNames.salonStaffBookings}/:bookingId',
            builder: (_, GoRouterState s) {
              visited.add('salon:${s.pathParameters['bookingId']}');
              return const Scaffold(key: Key('sentinel-salon-detail'));
            },
          ),
          GoRoute(
            path: '/bookings/:bookingId',
            builder: (_, GoRouterState s) {
              visited.add('client:${s.pathParameters['bookingId']}');
              return const Scaffold(key: Key('sentinel-client-detail'));
            },
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpRoutedApp(router, overrides: overrides());
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('timeline-card-bk-1')),
      );
      await tester.pumpAndSettle();

      expect(
        visited,
        <String>['salon:bk-1'],
        reason:
            'RouteNames.bookingDetail resolves to /bookings/:id, and /bookings '
            'is a CLIENT branch prefix in auth_redirect.dart — an owner who '
            'reaches it is redirected to roleHomePath(role), i.e. bounced out '
            'of the salon shell entirely',
      );
      expect(find.byKey(const Key('sentinel-salon-detail')), findsOneWidget);
      expect(find.byKey(const Key('sentinel-client-detail')), findsNothing);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // 5. The UNTOUCHED board — what the owner sees before they filter anything.
  // ═════════════════════════════════════════════════════════════════════════
  //
  // The bug these pin (user report, 2026-09-17): the screen seeded the view
  // with `BookingsDayQuery.salonDayList(...)`, which RESOLVES an empty
  // selection through `BookingStatus.dayListWireStatuses` — so the seed came
  // back carrying {CONFIRMED, COMPLETED, NOT_COMPLETED} and
  // `BookingsDiscoveryView.initState` read that WIRE set into `_statuses` as
  // though the owner had chosen it. The sheet opened pre-ticked and the funnel
  // wore a badge on a board nobody had filtered.
  //
  // The seed is now `.salonOf(...)` — the raw member, the exact twin of the
  // master board's `BookingsDayQuery.of(...)`. The two halves below are
  // deliberately in ONE group: the fix is PRESENTATIONAL, and the first test
  // is the proof that it is (the resolved wire set, and therefore every row
  // the board renders, is byte-identical either way).
  group('SalonBookingsScreen — the untouched board', () {
    /// Every filterable status on one master, on the fixture day.
    List<Booking> allFiveStatuses() => <Booking>[
      _booking(id: 'conf', masterId: 'm1', hour: 9),
      _booking(
        id: 'comp',
        masterId: 'm1',
        hour: 10,
        status: BookingStatus.completed,
      ),
      _booking(
        id: 'noshow',
        masterId: 'm1',
        hour: 11,
        status: BookingStatus.notCompleted,
      ),
      _booking(
        id: 'canc',
        masterId: 'm1',
        hour: 12,
        status: BookingStatus.cancelled,
      ),
      _booking(
        id: 'decl',
        masterId: 'm1',
        hour: 13,
        status: BookingStatus.declined,
      ),
    ];

    testWidgets('renders EXACTLY the locked default row set — CANCELLED and '
        'DECLINED hidden, NOT_COMPLETED kept (this is the regression pin for '
        'the .salonDayList → .salonOf seed change: it must move no row)', (
      WidgetTester tester,
    ) async {
      stubRoster(<SalonMasterSummary>[_rosterMaster('m1', 'Оля', 'Коваль')]);
      stubSalonProfile();
      stubSalonDay(allFiveStatuses());

      await pumpScreen(tester);
      await tester.pumpAndSettle();

      for (final String id in <String>['conf', 'comp', 'noshow']) {
        expect(
          find.byKey(ValueKey<String>('timeline-card-$id')),
          findsOneWidget,
          reason:
              'BookingStatus.visibleInDayListByDefault keeps $id on an '
              'untouched provider board (locked 2026-08-13)',
        );
      }
      for (final String id in <String>['canc', 'decl']) {
        expect(
          find.byKey(ValueKey<String>('timeline-card-$id')),
          findsNothing,
          reason:
              'CANCELLED/DECLINED stay hidden until the owner ticks '
              '«Скасовані» — they live on «Архів»',
        );
      }
    });

    testWidgets('shows NO funnel badge and opens the filter sheet with NOTHING '
        'ticked — an unfiltered board must not read as a filtered one', (
      WidgetTester tester,
    ) async {
      stubRoster(<SalonMasterSummary>[_rosterMaster('m1', 'Оля', 'Коваль')]);
      stubSalonProfile();
      stubSalonDay(allFiveStatuses());

      await pumpScreen(tester);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('master-bookings-filter-badge')),
        findsNothing,
        reason:
            'the badge counts the OWNER\'s selection, which is empty until '
            'they tick a group',
      );

      await tester.tap(find.byKey(const Key('master-bookings-filter-button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('master-bookings-filter-sheet')),
        findsOneWidget,
      );
      for (final BookingStatusFilterGroup g
          in BookingStatusFilterGroup.values) {
        final Finder row = find.byKey(
          Key('master-bookings-filter-status-${g.name}'),
        );
        expect(row, findsOneWidget);
        // The RENDERED glyph, not a widget field: a ticked row draws
        // `check_circle_rounded`, an unticked one `circle_outlined`.
        expect(
          find.descendant(
            of: row,
            matching: find.byIcon(Icons.check_circle_rounded),
          ),
          findsNothing,
          reason: '«${g.name}» must open UNTICKED on an untouched board',
        );
        expect(
          find.descendant(
            of: row,
            matching: find.byIcon(Icons.circle_outlined),
          ),
          findsOneWidget,
        );
      }
    });

    testWidgets('the rail dots come from GET /bookings/salon/{id}/booked-days '
        'over the rail\'s own ±kBookedDaysSpanDays Kyiv window — NEVER the '
        'caller\'s /me/booked-days', (WidgetTester tester) async {
      stubRoster(<SalonMasterSummary>[_rosterMaster('m1', 'Оля', 'Коваль')]);
      stubSalonProfile();
      stubSalonDay(<Booking>[_booking(id: 'conf', masterId: 'm1', hour: 9)]);

      await pumpScreen(tester);
      await tester.pumpAndSettle();

      verify(
        () => bookingRepo.getSalonBookedDays(
          salonId: _salonId,
          from: DateTime(2026, 6, 15 - kBookedDaysSpanDays),
          to: DateTime(2026, 6, 15 + kBookedDaysSpanDays),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).called(1);
      verifyNever(
        () => bookingRepo.getMyBookedDays(
          from: any(named: 'from'),
          to: any(named: 'to'),
          cancelToken: any(named: 'cancelToken'),
        ),
      );

      // Rendered, not merely fetched: the dot key only exists on a day the
      // set actually contains (`bookings_day_rail.dart`'s `hasBookings`).
      expect(find.byKey(dayDotKey(DateTime(2026, 6, 15))), findsOneWidget);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // 8. THE TWO RE-ARMED CACHES (mobile-perf MEDIUM ×2, 2026-09-17)
  //
  // `BookingsTimelineGrid` and its `_BoardStack` each memoise expensive work
  // behind an `identical(...)` gate in `didUpdateWidget`. Both were DEAD on
  // this route since they shipped, for two independent reasons that are
  // AND-gated — fixing either alone left the board at 4/4 cards rebuilt:
  //
  //   * `columnsBuilder:` was an inline closure, so `_Loaded._body`'s
  //     `columnsBuilder?.call(items, day)` allocated a fresh `List` on every
  //     rebuild → `!identical(widget.columns, oldWidget.columns)`, always true;
  //   * `onBookingTap:` was an inline closure, so `_BoardStack`'s
  //     `oldWidget.onBookingTap != widget.onBookingTap` was always true too.
  //
  // ── WHY THE ASSERTION IS WIDGET-INSTANCE IDENTITY ────────────────────────
  // NOT a widget-FIELD read (`grid.columns`, `boardStack.onBookingTap`), which
  // would only prove the screen PASSED something and is vacuous about what the
  // framework then did with it. `_BoardStack._cachedColumn` returns the SAME
  // `Widget` instance for an unchanged column, and `Element.updateChild`
  // skipping a subtree on an identical widget is a documented framework
  // guarantee — so "the card widget instance survived a rebuild" IS the
  // observation that the subtree was not rebuilt. A rebuilt column allocates
  // fresh `MasterBookingCard`s and the identity necessarily moves.
  //
  // ── WHY markNeedsBuild AND NOT A PROVIDER NUDGE ──────────────────────────
  // Every provider this screen watches feeds the columns, so re-emitting any
  // of them would change a real input and the cache SHOULD miss. What is being
  // pinned is "this screen rebuilt for any reason at all, with nothing
  // relevant changed" — which is exactly what `markNeedsBuild` expresses, and
  // what a parent rebuild (the salon shell swapping tabs, an ancestor
  // `InheritedWidget` notifying) does in production.
  // ═════════════════════════════════════════════════════════════════════════
  group('SalonBookingsScreen — the board survives a no-op rebuild', () {
    /// Every rendered card, by the key the timeline gives it.
    List<Widget> cards(WidgetTester tester, List<String> ids) => <Widget>[
      for (final String id in ids)
        tester.widget(find.byKey(ValueKey<String>('timeline-card-$id'))),
    ];

    testWidgets('a rebuild that changes NOTHING rebuilds ZERO of the four '
        'cards — both the column-list memo and the stable onBookingTap '
        'tear-off are required, and either one missing takes it to 4/4', (
      WidgetTester tester,
    ) async {
      stubRoster(<SalonMasterSummary>[
        _rosterMaster('m1', 'Оля', 'Коваль'),
        _rosterMaster('m2', 'Ніна', 'Бойко'),
      ]);
      stubSalonProfile();
      stubSalonDay(<Booking>[
        _booking(id: 'a1', masterId: 'm1', hour: 10),
        _booking(id: 'a2', masterId: 'm1', hour: 12),
        _booking(id: 'b1', masterId: 'm2', hour: 11),
        _booking(id: 'b2', masterId: 'm2', hour: 13),
      ]);

      await pumpScreen(tester);
      await tester.pumpAndSettle();

      const List<String> ids = <String>['a1', 'a2', 'b1', 'b2'];
      // The board is genuinely showing all four before anything is measured —
      // otherwise "nothing rebuilt" would be satisfied by nothing existing.
      for (final String id in ids) {
        expect(
          find.byKey(ValueKey<String>('timeline-card-$id')),
          findsOneWidget,
          reason: 'card $id must be on the board before the no-op rebuild',
        );
      }

      final List<Widget> before = cards(tester, ids);

      // One no-op rebuild of the screen — same roster, same schedule, same
      // day, same bookings.
      tester.element(find.byType(SalonBookingsScreen)).markNeedsBuild();
      await tester.pump();

      final List<Widget> after = cards(tester, ids);

      final List<String> rebuilt = <String>[
        for (int i = 0; i < ids.length; i++)
          if (!identical(before[i], after[i])) ids[i],
      ];
      expect(
        rebuilt,
        isEmpty,
        reason:
            'a rebuild that changed no input must not rebuild a single card: '
            "_BoardStack's built-column cache returns the same Widget "
            'instance and Element.updateChild skips the subtree. Cards that '
            'moved: $rebuilt (${rebuilt.length}/${ids.length})',
      );
    });
  });
  // ═════════════════════════════════════════════════════════════════════════
  // 9. THE DAY-OFF MARK FOLLOWS THE SELECTED DAY (mobile-qa, 2026-09-18)
  //
  // The 16 predicate tests answer `masterDayOff(id, day, schedule)` for one
  // day at a time, and the 7 column tests pump one board. Neither pumps the
  // SAME board TWICE across a rail tap, which is the only place the mark's
  // day-dependence is observable — and the place where two separate
  // mechanisms can silently pin it to the first day rendered:
  //   • `masterDayOff`'s date match (a comparison that dropped `.day` still
  //     resolves, just always against the first entry for that month), and
  //   • `_SalonBookingsScreenState._columnsFor`'s memo, whose `day` key is
  //     the only one that is compared BY VALUE.
  //
  // ANTI-VACUITY: BOTH days are EMPTY for the marked master. `bookings`,
  // `roster` and `rosterSchedule` are byte-identical either side of the tap,
  // so nothing except the selected date can move this assertion, in either
  // direction.
  // ═════════════════════════════════════════════════════════════════════════
  group('SalonBookingsScreen — the day-off mark tracks the rail', () {
    testWidgets('a master OFF on the selected day is greyed, and un-greys when '
        'the rail moves to a day they WORK — both days empty', (
      WidgetTester tester,
    ) async {
      // Read from the ARB, never spelled here: a locale retune must move
      // this test with the app (M2/M11), not silently break it.
      final AppLocalizationsUk uk = AppLocalizationsUk();
      final String off = uk.salonBookingsColumnDayOff;
      final String freeDay = uk.salonBookingsColumnFreeDay;
      expect(off, isNot(freeDay));

      stubRoster(<SalonMasterSummary>[
        _rosterMaster('m1', 'Оля', 'Коваль'),
        _rosterMaster('m2', 'Ніна', 'Бойко'),
      ]);
      stubSalonProfile();
      // m1: OFF on the 15th, WORKING on the 16th. m2: working both days, so
      // the board always has a window and the timeline never collapses.
      stubRosterSchedule(<String, List<EffectiveDay>>{
        'm1': <EffectiveDay>[
          EffectiveDay(
            date: DateTime(2026, 6, 15),
            source: EffectiveSource.overrideDayOff,
            intervals: const <WorkInterval>[],
          ),
          EffectiveDay(
            date: DateTime(2026, 6, 16),
            source: EffectiveSource.template,
            intervals: <WorkInterval>[
              WorkInterval(
                start: const TimeOfDay(hour: 9, minute: 0),
                end: const TimeOfDay(hour: 18, minute: 0),
              ),
            ],
          ),
        ],
        'm2': <EffectiveDay>[
          working(9, 18),
          EffectiveDay(
            date: DateTime(2026, 6, 16),
            source: EffectiveSource.template,
            intervals: <WorkInterval>[
              WorkInterval(
                start: const TimeOfDay(hour: 9, minute: 0),
                end: const TimeOfDay(hour: 18, minute: 0),
              ),
            ],
          ),
        ],
      });
      // BOTH days empty — the whole point. `stubSalonDay` pins the 15th; the
      // 16th needs its own equally-strict stub.
      stubSalonDay(const <Booking>[]);
      when(
        () => bookingRepo.getSalonBookings(
          salonId: _salonId,
          masterId: null,
          from: DateTime(2026, 6, 16),
          to: DateTime(2026, 6, 16),
          sort: BookingSort.oldest,
          page: 0,
          size: 100,
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((_) async => _page(const <Booking>[]));

      await pumpScreen(tester);
      await tester.pumpAndSettle();

      // ── The 15th: m1 is off, m2 is merely free ───────────────────────────
      expect(
        find.byKey(const ValueKey<String>('timeline-column-day-off-wash-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('timeline-column-day-off-wash-1')),
        findsNothing,
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey<String>('timeline-column-marker-0')),
            )
            .data,
        off,
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey<String>('timeline-column-marker-1')),
            )
            .data,
        freeDay,
      );

      // ── Tap the rail to the 16th ─────────────────────────────────────────
      final Finder nextDay = find.byKey(dayChipKey(DateTime(2026, 6, 16)));
      expect(nextDay, findsOneWidget);
      await tester.tap(nextDay);
      // fixed-wait-ok: waits out the REAL 220ms rail-tap debounce timer in
      // `_BookingsDiscoveryViewState._selectDay`. `pumpAndSettle` alone never
      // fires it — a pending Timer schedules no frame, so the settle returns
      // with the selection unchanged and every assertion below would be
      // measuring the FIRST day twice.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // ── The 16th: m1 WORKS, so the grey is gone and the word changed ─────
      expect(
        find.byKey(const ValueKey<String>('timeline-column-day-off-wash-0')),
        findsNothing,
        reason:
            'the wash must follow the SELECTED day — a mark pinned to the '
            'first day rendered leaves this column greyed forever',
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey<String>('timeline-column-marker-0')),
            )
            .data,
        freeDay,
      );
      expect(find.text(off), findsNothing);
    });
  });
}
