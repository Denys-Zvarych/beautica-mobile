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
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_timeline_grid.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_booking_card.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_column_strip.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/salon/data/salon_repository.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_master_summary.dart';
import 'package:beautica_mobile/features/salon/domain/salon_staff_member.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_bookings_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';

import '../../../helpers/pump_app.dart';

class _MockBookingRepository extends Mock implements BookingRepository {}

class _MockSalonRepository extends Mock implements SalonRepository {}

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

  setUp(() {
    bookingRepo = _MockBookingRepository();
    salonRepo = _MockSalonRepository();
  });

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

  List<Object> overrides() => <Object>[
    bookingRepositoryProvider.overrideWithValue(bookingRepo),
    salonRepositoryProvider.overrideWithValue(salonRepo),
    authProvider.overrideWith(_SettledAuthNotifier.new),
    clockProvider.overrideWithValue(() => _now),
  ];

  Future<void> pumpScreen(
    WidgetTester tester, {
    double? textScaleFactor,
    Duration? Function(int, Object)? retry = beauticaProviderRetry,
  }) => tester.pumpApp(
    const SalonBookingsScreen(salonId: _salonId),
    overrides: overrides(),
    width: 360,
    height: 720,
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
  // 4. The deliberately inert (+) placeholder.
  // ═════════════════════════════════════════════════════════════════════════
  group('SalonBookingsScreen — the create-booking placeholder', () {
    testWidgets('the (+) control RENDERS (it reserves its final width so the '
        'header never reflows) and tapping it navigates NOWHERE', (
      WidgetTester tester,
    ) async {
      stubRoster(<SalonMasterSummary>[_rosterMaster('m1', 'Оля', 'Коваль')]);
      stubSalonProfile();
      stubSalonDay(<Booking>[_booking(id: 'a1', masterId: 'm1', hour: 10)]);

      final List<String> pushed = <String>[];
      final GoRouter router = GoRouter(
        initialLocation: '/board',
        routes: <RouteBase>[
          GoRoute(
            path: '/board',
            builder: (_, _) => const SalonBookingsScreen(salonId: _salonId),
          ),
          GoRoute(
            path: '/sink/:rest',
            builder: (_, GoRouterState s) {
              pushed.add(s.uri.toString());
              return const SizedBox.shrink();
            },
          ),
        ],
        observers: <NavigatorObserver>[_RecordingObserver(pushed)],
      );
      addTearDown(router.dispose);

      await tester.pumpRoutedApp(router, overrides: overrides());
      await tester.pumpAndSettle();

      final Finder add = find.byKey(const Key('master-bookings-add'));
      expect(
        add,
        findsOneWidget,
        reason:
            'the placeholder must RENDER — hiding it would narrow the header '
            'today and widen it when the wizard lands, which is the reflow '
            'the placeholder exists to avoid',
      );

      await tester.tap(add);
      await tester.pumpAndSettle();

      expect(
        pushed,
        isEmpty,
        reason: 'the (+) handler is a documented NO-OP for this phase',
      );
      // …and the board is still the page on screen.
      expect(find.byKey(const Key('salon-bookings-screen')), findsOneWidget);
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
}

/// Records every route PUSHED onto the navigator, so "tapping (+) navigated
/// nowhere" is asserted against the navigator itself rather than against the
/// absence of a particular screen (which an unregistered route would satisfy
/// vacuously).
class _RecordingObserver extends NavigatorObserver {
  _RecordingObserver(this.pushed);

  final List<String> pushed;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final String? name = route.settings.name;
    if (previousRoute != null) pushed.add(name ?? route.settings.toString());
  }
}
