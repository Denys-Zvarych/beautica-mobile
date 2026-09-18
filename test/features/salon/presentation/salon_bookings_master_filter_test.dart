// 2026-09-18 — the «Майстер» filter section on the salon «Записи» board.
//
// WHAT THIS FILE OWNS
// -------------------
// The user reversed a documented decision: `BookingsDiscoveryView
// .showMasterFilter` used to be `false` at every call site because
// `GET /bookings/salon/{salonId}` takes exactly ONE `masterId` while every
// section of `BookingsFilterSheet` is multi-select. The resolution is
// MULTI-SELECT + CLIENT-SIDE, which dissolves that argument: no request
// changes, the board keeps its side-by-side shape, and it simply draws fewer
// columns.
//
// THE CASE THE REST OF THE SUITE CANNOT CATCH
// -------------------------------------------
// `_SalonBookingsScreenState._columnsFor` memoises the column list. Before this
// feature its `_cachedColumnsDay == day` half was UNREACHABLE — `dayItems`
// identity always moved with the day, so a stale hit could not occur and a
// mobile-qa audit said so. The «Майстер» filter breaks that: the selection
// changes while the day, the items, the roster AND the schedule all stay
// identical. So the memo grew `masterIds` as a fifth key, and the group
// "changing the filter WITHOUT changing the day" below is the only thing that
// can observe its absence — any test that changes the day between assertions
// would pass regardless.
//
// FIXTURE DISCRIMINATION
// ----------------------
// The three roster masters carry 2 / 1 / 0 bookings. A fixture where every
// master looked the same would let a filter test pass without filtering
// anything (`fixture values can defang assertions`), so every assertion below
// keys off a number or an id that MOVES when the filter is applied.
//
// NO Cyrillic ever reaches a `find.text(...)` argument
// (`scripts/forbid_cyrillic_finder.sh`): rows are located by KEY, and the one
// string assertion reads the rendered `Text.data` and compares it against
// `AppLocalizationsUk()`'s own output.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

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
import 'package:beautica_mobile/features/booking/presentation/widgets/master_column_strip.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/salon/data/salon_repository.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_master_summary.dart';
import 'package:beautica_mobile/features/salon/domain/salon_staff_member.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_bookings_screen.dart';
import 'package:beautica_mobile/features/schedule/data/schedule_repository.dart';
import 'package:beautica_mobile/features/schedule/data/schedule_repository_provider.dart';
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';
import 'package:beautica_mobile/l10n/app_localizations_uk.dart';

import '../../../helpers/pump_app.dart';

class _MockBookingRepository extends Mock implements BookingRepository {}

class _MockSalonRepository extends Mock implements SalonRepository {}

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

/// Kyiv 2026-06-15 10:00 — the clock AND every fixture below are pinned to this
/// one instant, so the board's `kyivToday(clock)` day and the bookings'
/// `startAt` describe the same calendar day on any host timezone (the
/// test-clock coherence invariant is about MIXING, not about pinning).
// future-date-ok: fixed PAST Kyiv instant; both the clock and every fixture
final DateTime _now = DateTime.utc(2026, 6, 15, 7);

DateTime _kyiv(int hour) => DateTime.utc(2026, 6, 15, hour - 3);

Booking _booking({
  required String id,
  required String masterId,
  required int hour,
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
    serviceId: 'service-1',
    serviceName: 'Манікюр',
    durationMinutes: 60,
    price: 500,
    startAt: start,
    endAt: start.add(const Duration(hours: 1)),
    status: BookingStatus.confirmed,
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

/// The roster, in board order. `m3` is deliberately booking-less — a column the
/// filter must be able to KEEP as well as drop.
final List<SalonMasterSummary> _roster = <SalonMasterSummary>[
  _rosterMaster('m1', 'Оля', 'Коваль'),
  _rosterMaster('m2', 'Ніна', 'Гнатюк'),
  _rosterMaster('m3', 'Дарія', 'Мельник'),
];

/// 2 / 1 / 0 — see the file header's "fixture discrimination".
final List<Booking> _day = <Booking>[
  _booking(id: 'a1', masterId: 'm1', hour: 10),
  _booking(id: 'a2', masterId: 'm1', hour: 12),
  _booking(id: 'b1', masterId: 'm2', hour: 11),
];

Finder _chip(String masterId) =>
    find.byKey(ValueKey<String>('salon-bookings-column-chip-$masterId'));

Finder _sheetRow(String masterId) =>
    find.byKey(Key('master-bookings-filter-master-$masterId'));

/// Whether the roster chip for [masterId] renders in its SELECTED (highlighted)
/// form, read off the semantics tree the chip actually publishes — not off a
/// widget field the screen happened to pass down. `Semantics(selected: …)` and
/// the camel ring on `_MasterColumnChip`'s decoration are set from the same
/// expression, so this is the highlight as a user perceives it.
bool? _chipSelected(WidgetTester tester, String masterId) => tester
    .getSemantics(_chip(masterId))
    .getSemanticsData()
    .flagsCollection
    .isSelected
    .toBoolOrNull();

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

    when(
      () =>
          rosterScheduleRepo.salonRosterEffectiveSchedule(any(), any(), any()),
    ).thenAnswer((_) async => const <String, List<EffectiveDay>>{});

    // STRICT on `masterId: null` — the whole point of the client-side decision
    // is that the «Майстер» filter never reaches the wire. If a future change
    // routed the selection onto `SalonDayQuery.masterId`, this stub stops
    // matching and every test in the file goes red rather than silently
    // passing on a narrower fetch.
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
    ).thenAnswer(
      (_) async => PageResponse<Booking>(
        items: _day,
        page: 0,
        totalPages: 1,
        totalElements: _day.length,
      ),
    );
    when(
      () => bookingRepo.getSalonBookedDays(
        salonId: any(named: 'salonId'),
        from: any(named: 'from'),
        to: any(named: 'to'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) async => <DateTime>[DateTime(2026, 6, 15)]);

    when(
      () => salonRepo.getSalonMasters(_salonId),
    ).thenAnswer((_) async => _roster);
    when(
      () => salonRepo.getSalonById(_salonId),
    ).thenAnswer((_) async => const Salon(id: _salonId, name: 'Салон'));
    when(
      () => salonRepo.getSalonStaff(_salonId),
    ).thenAnswer((_) async => const <SalonStaffMember>[]);
    when(() => salonRepo.getMySalons()).thenAnswer(
      (_) async => <Salon>[const Salon(id: _salonId, name: 'Салон')],
    );
  });

  List<Object> overrides() => <Object>[
    bookingRepositoryProvider.overrideWithValue(bookingRepo),
    salonRepositoryProvider.overrideWithValue(salonRepo),
    salonRosterScheduleRepositoryProvider.overrideWithValue(rosterScheduleRepo),
    authProvider.overrideWith(_SettledAuthNotifier.new),
    clockProvider.overrideWithValue(() => _now),
  ];

  /// Pumps the board under a REAL GoRouter — `BookingsFilterSheet` closes with
  /// the go_router `context.pop(value)` extension (raw `Navigator.pop` is
  /// banned in `lib/features`), which throws "No GoRouter found in context"
  /// under a plain `MaterialApp`.
  Future<void> pumpBoard(WidgetTester tester) async {
    final GoRouter router = GoRouter(
      initialLocation: '/board',
      routes: <RouteBase>[
        GoRoute(
          path: '/board',
          builder: (_, _) => const SalonBookingsScreen(salonId: _salonId),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpRoutedApp(router, overrides: overrides());
    await tester.pumpAndSettle();
  }

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('master-bookings-filter-button')));
    await tester.pumpAndSettle();
  }

  Future<void> apply(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('master-bookings-filter-apply')));
    await tester.pumpAndSettle();
  }

  /// Ticks [masterIds] in the open sheet and applies.
  Future<void> filterTo(WidgetTester tester, List<String> masterIds) async {
    await openSheet(tester);
    for (final String id in masterIds) {
      await tester.ensureVisible(_sheetRow(id));
      await tester.tap(_sheetRow(id));
      await tester.pumpAndSettle();
    }
    await apply(tester);
  }

  /// The masters the board is actually DRAWING, read off the roster strip the
  /// grid built — not off a widget field the screen happened to pass down.
  List<String> renderedMasterIds(WidgetTester tester) => <String>[
    for (final MasterColumnEntry e
        in tester
            .widget<MasterColumnStrip>(find.byType(MasterColumnStrip))
            .entries)
      e.masterId,
  ];

  String renderedCount(WidgetTester tester) =>
      tester
          .widget<Text>(find.byKey(const Key('master-bookings-count')))
          .data ??
      '';

  // ═══════════════════════════════════════════════════════════════════════
  // 1. columnsFor — the narrowing, as a pure function.
  // ═══════════════════════════════════════════════════════════════════════
  group('SalonBookingsScreen.columnsFor — masterIds', () {
    List<String> ids(Set<String> masterIds) => <String>[
      for (final TimelineBoardColumn c in SalonBookingsScreen.columnsFor(
        _day,
        _roster,
        masterIds: masterIds,
      ))
        c.header.masterId,
    ];

    test('EMPTY means every master — the default and every legacy call', () {
      expect(ids(const <String>{}), <String>['m1', 'm2', 'm3']);
      // The pre-existing two-argument call, unchanged.
      expect(
        SalonBookingsScreen.columnsFor(_day, _roster).length,
        3,
        reason: 'the new parameter must default to "no narrowing"',
      );
    });

    test('a subset emits exactly those columns, in ROSTER order', () {
      // Ticked out of order on purpose: the board's column order is the
      // roster's, never the order the owner happened to tick.
      expect(ids(<String>{'m3', 'm1'}), <String>['m1', 'm3']);
    });

    test('a booking-less master is kept when ticked — the filter narrows the '
        'ROSTER, not "who has work today"', () {
      final List<TimelineBoardColumn> columns = SalonBookingsScreen.columnsFor(
        _day,
        _roster,
        masterIds: <String>{'m3'},
      );
      expect(columns.single.header.masterId, 'm3');
      expect(columns.single.bookings, isEmpty);
    });

    test('the partition drops a filtered-out master\'s bookings entirely — '
        'they are not re-homed into a surviving column', () {
      final List<TimelineBoardColumn> columns = SalonBookingsScreen.columnsFor(
        _day,
        _roster,
        masterIds: <String>{'m2'},
      );
      expect(
        <String>[for (final Booking b in columns.single.bookings) b.id],
        <String>['b1'],
        reason:
            'm1\'s two bookings must vanish with m1\'s column — the header '
            'count is recomputed FROM the columns, so a re-homed booking '
            'would be counted and drawn under the wrong master',
      );
    });

    test('a selection that matches NO roster master renders the FULL roster, '
        'never an empty board', () {
      // Only reachable when every ticked master left the salon mid-session.
      // An empty column list makes `BookingsTimelineGrid._buildBoard` render
      // «salon-bookings-no-masters» — a claim that the SALON has no masters,
      // which would be flatly false. See `columnsFor`'s `_narrowRoster`.
      expect(ids(<String>{'ghost-1', 'ghost-2'}), <String>['m1', 'm2', 'm3']);
    });

    test('unknown ids alongside known ones are simply ignored', () {
      expect(ids(<String>{'m2', 'ghost-1'}), <String>['m2']);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 2. The sheet section itself.
  // ═══════════════════════════════════════════════════════════════════════
  group('the «Майстер» section', () {
    testWidgets('renders one row per roster master, with the heading', (
      WidgetTester tester,
    ) async {
      await pumpBoard(tester);
      await openSheet(tester);

      expect(
        find.byKey(const Key('master-bookings-filter-section-master')),
        findsOneWidget,
      );
      for (final SalonMasterSummary m in _roster) {
        expect(
          _sheetRow(m.masterId),
          findsOneWidget,
          reason: 'every roster master must be tickable',
        );
      }
      // …and the owner has no master catalogue of their own, so «Послуга»
      // stays absent. The two sections are independent.
      expect(
        find.byKey(const Key('master-bookings-filter-section-service')),
        findsNothing,
      );
    });

    testWidgets('the funnel badge counts «Майстер» as ONE active group', (
      WidgetTester tester,
    ) async {
      await pumpBoard(tester);
      expect(
        find.byKey(const Key('master-bookings-filter-badge')),
        findsNothing,
        reason: 'an untouched board shows no badge',
      );

      await filterTo(tester, <String>['m1', 'm2']);

      final Finder badge = find.byKey(
        const Key('master-bookings-filter-badge'),
      );
      expect(badge, findsOneWidget);
      expect(
        tester
            .widget<Text>(
              find.descendant(of: badge, matching: find.byType(Text)),
            )
            .data,
        '1',
        reason:
            'GROUPS, not values — two ticked masters is one active filter, '
            'exactly as two ticked statuses is',
      );
    });

    testWidgets('«Скинути фільтри» clears the master selection too', (
      WidgetTester tester,
    ) async {
      await pumpBoard(tester);
      await filterTo(tester, <String>['m2']);
      expect(renderedMasterIds(tester), <String>['m2']);

      await openSheet(tester);
      await tester.tap(find.byKey(const Key('master-bookings-filter-reset')));
      await tester.pumpAndSettle();
      await apply(tester);

      expect(
        renderedMasterIds(tester),
        <String>['m1', 'm2', 'm3'],
        reason:
            'a client-side filter is invisible to `_rebuildQuery`, so it must '
            'be cleared explicitly or the board stays narrowed after the owner '
            'was told the filter was reset',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 3. THE MEMO TRAP — the filter changes, the DAY DOES NOT.
  // ═══════════════════════════════════════════════════════════════════════
  //
  // RED/GREEN: drop `setEquals(_cachedColumnsMasterIds, masterIds)` from
  // `_SalonBookingsScreenState._columnsFor`'s gate and every test in this
  // group fails — the board keeps serving the pre-filter columns because
  // `dayItems`, `day`, `_roster` and `_rosterSchedule` are all still identical
  // across the apply. Restored, all pass. No day is touched anywhere in this
  // group, deliberately: a test that taps a rail chip between assertions
  // invalidates the memo on the `day` key and passes either way.
  group('changing the filter WITHOUT changing the day', () {
    testWidgets('the rendered COLUMNS actually change', (
      WidgetTester tester,
    ) async {
      await pumpBoard(tester);
      expect(
        renderedMasterIds(tester),
        <String>['m1', 'm2', 'm3'],
        reason: 'fixture sanity: the unfiltered board draws the whole roster',
      );

      await filterTo(tester, <String>['m2']);

      expect(
        renderedMasterIds(tester),
        <String>['m2'],
        reason:
            'the column memo must invalidate on the SELECTION, not only on '
            'the day — see this group\'s header',
      );
      expect(_chip('m1'), findsNothing);
      expect(_chip('m3'), findsNothing);
      expect(_chip('m2'), findsOneWidget);
    });

    testWidgets('the header count follows the columns', (
      WidgetTester tester,
    ) async {
      final AppLocalizationsUk uk = AppLocalizationsUk();
      await pumpBoard(tester);
      expect(
        renderedCount(tester),
        uk.masterBookingsCount(3),
        reason: 'fixture sanity: 2 + 1 + 0 bookings across the roster',
      );

      await filterTo(tester, <String>['m2']);

      expect(
        renderedCount(tester),
        uk.masterBookingsCount(1),
        reason:
            'the count is recomputed FROM the columns, so it narrows with the '
            'filter and can never disagree with the cards on screen',
      );
    });

    testWidgets('the cards of a filtered-out master leave the board', (
      WidgetTester tester,
    ) async {
      await pumpBoard(tester);
      expect(find.byKey(const Key('master-booking-card-a1')), findsOneWidget);

      await filterTo(tester, <String>['m2']);

      expect(
        find.byKey(const Key('master-booking-card-a1')),
        findsNothing,
        reason: 'm1 has no column left to sit in',
      );
      expect(find.byKey(const Key('master-booking-card-a2')), findsNothing);
      expect(find.byKey(const Key('master-booking-card-b1')), findsOneWidget);
    });

    testWidgets('multi-select keeps the board SIDE BY SIDE — two ticks, two '
        'columns, not a collapse to one', (WidgetTester tester) async {
      await pumpBoard(tester);
      await filterTo(tester, <String>['m1', 'm3']);

      expect(
        renderedMasterIds(tester),
        <String>['m1', 'm3'],
        reason:
            'the locked user decision: tick any number, the board keeps its '
            'shape and draws exactly the ticked columns',
      );
      expect(
        renderedCount(tester),
        AppLocalizationsUk().masterBookingsCount(2),
      );
    });

    testWidgets('un-ticking restores the full board, same day throughout', (
      WidgetTester tester,
    ) async {
      await pumpBoard(tester);
      await filterTo(tester, <String>['m2']);
      expect(renderedMasterIds(tester), <String>['m2']);

      // Tick m2 OFF again — back to the empty selection, which means ALL.
      await filterTo(tester, <String>['m2']);

      expect(
        renderedMasterIds(tester),
        <String>['m1', 'm2', 'm3'],
        reason: 'empty means every master, never an empty board',
      );
      expect(
        find.byKey(const Key('master-bookings-filter-badge')),
        findsNothing,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 4. The HIGHLIGHT is not the filter.
  // ═══════════════════════════════════════════════════════════════════════
  group('the roster-chip highlight stays independent', () {
    testWidgets('a chip tap highlights and does NOT narrow the board', (
      WidgetTester tester,
    ) async {
      await pumpBoard(tester);
      await tester.tap(_chip('m1'));
      await tester.pumpAndSettle();

      expect(
        renderedMasterIds(tester),
        <String>['m1', 'm2', 'm3'],
        reason: 'a highlight must never collapse the board',
      );
      expect(_chipSelected(tester, 'm1'), isTrue);
      expect(
        find.byKey(const Key('master-bookings-filter-badge')),
        findsNothing,
        reason: 'a highlight is not a filter and must not light the funnel',
      );
    });

    testWidgets('filtering the highlighted master AWAY is inert, and the '
        'highlight survives to be restored', (WidgetTester tester) async {
      await pumpBoard(tester);
      await tester.tap(_chip('m1'));
      await tester.pumpAndSettle();

      await filterTo(tester, <String>['m2']);

      expect(tester.takeException(), isNull);
      expect(renderedMasterIds(tester), <String>['m2']);
      expect(
        _chipSelected(tester, 'm2'),
        isFalse,
        reason:
            'the surviving column must render in its ORDINARY state — '
            '`MasterColumnStrip` marks the selected chip alone and dims no '
            'other, so an absent highlight cannot leave the board looking '
            'wholly deselected',
      );

      // Un-tick: m1 comes back, still highlighted. The filter never touched it.
      await filterTo(tester, <String>['m2']);
      expect(_chipSelected(tester, 'm1'), isTrue);
    });

    testWidgets('highlighting inside a narrowed board still works', (
      WidgetTester tester,
    ) async {
      await pumpBoard(tester);
      await filterTo(tester, <String>['m1', 'm2']);

      await tester.tap(_chip('m2'));
      await tester.pumpAndSettle();

      expect(_chipSelected(tester, 'm2'), isTrue);
      expect(
        renderedMasterIds(tester),
        <String>['m1', 'm2'],
        reason: 'the highlight must not narrow the already-narrowed board',
      );
    });
  });
}
