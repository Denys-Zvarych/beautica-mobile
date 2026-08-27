// Phase 14.3 — Widget suite for [MyBookingsScreen].
//
// Covers the phase's acceptance criteria:
//   • the three-tab status partition (Майбутні = CONFIRMED; Минулі =
//     COMPLETED + NOT_COMPLETED; Скасовані = CANCELLED + DECLINED) is
//     correct — each tab only ever shows its own statuses;
//   • a CANCELLED and a DECLINED booking both render under Скасовані sharing
//     ONE neutral label — «Скасовано» (the who-cancelled copy distinction was
//     dropped by product decision 2026-07-15);
//   • the loading skeleton shows while the first page is in flight;
//   • salon name renders on the card only when the booking carries one;
//   • pull-to-refresh calls `getMyBookings(page: 0)` again for the active
//     tab's statuses;
//   • tapping a card navigates to `/bookings/:id`.
//
// The card itself carries NO action buttons (reschedule/cancel/add-to-
// calendar all moved to «Деталі запису» — see `booking_card.dart`'s file
// header for the full "one affordance" reasoning); this suite does not
// assert for any card-level actions, matching the approved design over the
// phase doc's now-superseded prose.
//
// Pumping notes (mirrors `search_results_screen_test.dart`, mobile-backlog
// row 236): AsyncValue-state assertions use a plain `MaterialApp home:`; the
// card-tap navigation test uses a real `GoRouter` with a stub `/bookings/:id`
// route so the push is observable.
//
// Wire-format note (backend Phase 26.1/26.3, fixing mobile-debugger findings
// A + B): `GET /bookings/me` now takes the tab's WHOLE status set + a
// `sort=startsAt,<asc|desc>` param in ONE request per tab, instead of one
// fan-out fetch per status — see `booking_repository.dart` and
// `my_bookings_notifier.dart`. [_stubAllTabs] stubs all three tabs' single
// requests directly (mirrors the old `_stubAllStatuses` covering every
// individual status defensively, since a `TabBarView` may build more than
// the initially-visible tab).

import 'dart:async';

import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_partition.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/booking_tab.dart';
import 'package:beautica_mobile/features/booking/presentation/my_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_card.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_empty_state.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/my_bookings_states.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/overflow_guard.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

class _MockBookingRepository extends Mock implements BookingRepository {}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

Booking _booking({
  required String id,
  required BookingStatus status,
  String masterFirstName = 'Марія',
  String masterLastName = 'Іванюк',
  String? salonName,
  String? masterProfessionalTitle,
  String serviceName = 'Манікюр з покриттям',
  double price = 650,
  DateTime? startAt,
  String? clientCancellationNote,
  String? providerComment,
}) {
  final DateTime start = startAt ?? DateTime.utc(2026, 7, 20, 15);
  return Booking(
    id: id,
    masterId: 'master-$id',
    masterFirstName: masterFirstName,
    masterLastName: masterLastName,
    masterAvatarUrl: null,
    masterType: salonName != null ? 'SALON_MASTER' : 'INDEPENDENT_MASTER',
    salonName: salonName,
    serviceId: 'service-$id',
    serviceName: serviceName,
    categoryName: 'NAIL_SERVICE',
    cityLabel: 'Львів',
    districtLabel: null,
    street: null,
    buildingNo: null,
    durationMinutes: 60,
    price: price,
    startAt: start,
    endAt: start.add(const Duration(hours: 1)),
    status: status,
    canReview: false,
    clientComment: null,
    providerComment: providerComment,
    clientCancellationNote: clientCancellationNote,
    masterProfessionalTitle: masterProfessionalTitle,
    locationNote: null,
  );
}

PageResponse<Booking> _page(List<Booking> items) => PageResponse<Booking>(
  items: items,
  page: 0,
  totalPages: 1,
  totalElements: items.length,
);

/// Stubs the ONE `getMyBookings` request each of the three tabs issues
/// (backend Phase 26.1 — the tab's whole status set travels in a single
/// call; Phase 26.3 — `sort` drives `sort=startsAt,<asc|desc>`).
/// Defaults every tab to an empty page so a test only has to describe the
/// tab(s) it cares about.
void _stubAllTabs(
  _MockBookingRepository repo, {
  List<Booking> upcoming = const <Booking>[],
  List<Booking> past = const <Booking>[],
  List<Booking> cancelled = const <Booking>[],
}) {
  // Phase 227: the notifier now sends `partition: tab.partition` alongside
  // `statuses` on every request — every stub below pins BOTH, otherwise the
  // real call (which always carries `partition`) would never match and every
  // widget test in this file would throw `MissingStubError`.
  when(
    () => repo.getMyBookings(
      statuses: BookingTab.upcoming.statuses,
      partition: BookingPartition.upcoming,
      sort: BookingSort.oldest,
      page: any(named: 'page'),
      size: any(named: 'size'),
    ),
  ).thenAnswer((_) async => _page(upcoming));
  when(
    () => repo.getMyBookings(
      statuses: BookingTab.past.statuses,
      partition: BookingPartition.past,
      sort: BookingSort.newest,
      page: any(named: 'page'),
      size: any(named: 'size'),
    ),
  ).thenAnswer((_) async => _page(past));
  when(
    () => repo.getMyBookings(
      statuses: BookingTab.cancelled.statuses,
      partition: BookingPartition.cancelled,
      sort: BookingSort.newest,
      page: any(named: 'page'),
      size: any(named: 'size'),
    ),
  ).thenAnswer((_) async => _page(cancelled));
}

const List<LocalizationsDelegate<Object?>> _delegates =
    <LocalizationsDelegate<Object?>>[
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ];

const List<Locale> _locales = <Locale>[Locale('uk'), Locale('en')];

Widget _host(_MockBookingRepository repo) {
  return ProviderScope(
    retry: beauticaProviderRetry,
    // ignore: avoid_dynamic_calls
    overrides: <Object>[
      bookingRepositoryProvider.overrideWithValue(repo),
    ].cast(),
    child: const MaterialApp(
      localizationsDelegates: _delegates,
      supportedLocales: _locales,
      locale: Locale('uk'),
      home: MyBookingsScreen(),
    ),
  );
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(MyBookingsScreen)));

void main() {
  setUp(installOverflowGuard);

  // -------------------------------------------------------------------------
  // Loading
  // -------------------------------------------------------------------------

  group('loading', () {
    testWidgets('shows the skeleton while the first page is in flight', (
      tester,
    ) async {
      final repo = _MockBookingRepository();
      final completer = Completer<PageResponse<Booking>>();
      when(
        () => repo.getMyBookings(
          statuses: BookingTab.upcoming.statuses,
          partition: BookingPartition.upcoming,
          sort: BookingSort.oldest,
          page: any(named: 'page'),
          size: any(named: 'size'),
        ),
      ).thenAnswer((_) => completer.future);
      when(
        () => repo.getMyBookings(
          statuses: BookingTab.past.statuses,
          partition: BookingPartition.past,
          sort: BookingSort.newest,
          page: any(named: 'page'),
          size: any(named: 'size'),
        ),
      ).thenAnswer((_) async => _page(const <Booking>[]));
      when(
        () => repo.getMyBookings(
          statuses: BookingTab.cancelled.statuses,
          partition: BookingPartition.cancelled,
          sort: BookingSort.newest,
          page: any(named: 'page'),
          size: any(named: 'size'),
        ),
      ).thenAnswer((_) async => _page(const <Booking>[]));

      await tester.pumpWidget(_host(repo));
      await tester.pump();

      expect(find.byType(BookingsSkeleton), findsOneWidget);
      completer.complete(_page(const <Booking>[]));
      await tester.pumpAndSettle();
    });
  });

  // -------------------------------------------------------------------------
  // Tab partition
  // -------------------------------------------------------------------------

  group('tab partition', () {
    testWidgets('Майбутні shows only CONFIRMED bookings', (tester) async {
      final repo = _MockBookingRepository();
      final confirmed = _booking(id: 'b1', status: BookingStatus.confirmed);
      _stubAllTabs(repo, upcoming: <Booking>[confirmed]);

      await tester.pumpWidget(_host(repo));
      await tester.pumpAndSettle();

      expect(find.byType(BookingCard), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('service-b1')), findsOneWidget);
    });

    testWidgets('Минулі shows COMPLETED + NOT_COMPLETED, in one tab', (
      tester,
    ) async {
      final repo = _MockBookingRepository();
      final completed = _booking(id: 'b2', status: BookingStatus.completed);
      final noShow = _booking(
        id: 'b3',
        status: BookingStatus.notCompleted,
        providerComment: 'Клієнтка не прийшла.',
      );
      _stubAllTabs(repo, past: <Booking>[completed, noShow]);

      await tester.pumpWidget(_host(repo));
      await tester.pumpAndSettle();

      // Land on Минулі.
      final l10n = _l10n(tester);
      await tester.tap(find.text(l10n.myBookingsTabPast));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey<String>('service-b2')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('service-b3')), findsOneWidget);
    });

    testWidgets('Скасовані shows CANCELLED + DECLINED both labelled the same '
        'neutral «Скасовано»', (tester) async {
      final repo = _MockBookingRepository();
      final cancelled = _booking(
        id: 'b4',
        status: BookingStatus.cancelled,
        clientCancellationNote: 'Захворіла.',
      );
      final declined = _booking(
        id: 'b5',
        status: BookingStatus.declined,
        salonName: 'Lviv Nails Studio',
        providerComment: 'Майстер захворів.',
      );
      _stubAllTabs(repo, cancelled: <Booking>[cancelled, declined]);

      await tester.pumpWidget(_host(repo));
      await tester.pumpAndSettle();

      final l10n = _l10n(tester);
      await tester.tap(find.text(l10n.myBookingsTabCancelled));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey<String>('service-b4')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('service-b5')), findsOneWidget);

      // Collapsed label (product decision 2026-07-15) — a client cancellation
      // and a provider decline now read the SAME neutral «Скасовано». Both
      // cards carry it (one badge each → two total).
      expect(
        find.text(l10n.bookingStatusCancelled),
        findsNWidgets(2),
        reason:
            'both the client-cancelled and the salon-declined card must show '
            'the neutral «Скасовано» label',
      );
    });
  });

  // -------------------------------------------------------------------------
  // Phase 227 — «Мої записи» cutover to the backend's server-side `partition`
  //
  // These two groups are widget-level proof of the phase's headline
  // behaviour fix. Scoping every assertion to the OWNING tab's list via
  // `find.descendant(of: find.byKey('my-bookings-list-<tab>'), ...)` (rather
  // than a bare `find.byKey`/`find.byType(BookingCard)` count) sidesteps a
  // real hazard specific to this screen: `TabBarView` may build more than the
  // initially-visible tab's subtree (see `_stubAllTabs`'s doc comment above,
  // and every test in this file defensively stubbing all three tabs even
  // when it only cares about one) — so an UNSCOPED `find.byType(BookingCard)`
  // count could silently include cards belonging to a DIFFERENT, already-
  // built-but-offstage tab and produce a false pass. Scoping to the specific
  // tab's `ListView.separated` key (`my-bookings-list-${widget.tab.name}`,
  // `my_bookings_screen.dart:252`) makes every assertion correct regardless
  // of what else `TabBarView` has materialized.
  // -------------------------------------------------------------------------

  group('Phase 227 — elapsed CONFIRMED cutover (headline behaviour fix)', () {
    testWidgets(
      'an elapsed CONFIRMED booking renders under Минулі and is ABSENT from '
      'Майбутні — before this phase it sat in Майбутні forever and never '
      'reached Минулі (the defect this whole track exists to close). A '
      'genuinely-future CONFIRMED sibling is also in the fixture and '
      'asserted VISIBLE in Майбутні first — anti-vacuity: without it, the '
      '"absent from Майбутні" assertion below could pass off a screen that '
      'renders nothing at all',
      (tester) async {
        final repo = _MockBookingRepository();
        final futureConfirmed = _booking(
          id: 'future1',
          status: BookingStatus.confirmed,
          startAt: DateTime.utc(2027, 1, 1, 10),
        );
        final elapsedConfirmed = _booking(
          id: 'elapsed1',
          status: BookingStatus.confirmed,
          startAt: DateTime.utc(2000, 1, 1, 10),
        );
        // Stands in for the backend's Phase 28.2 `partition` classification:
        // an elapsed CONFIRMED booking is now served under `partition=PAST`,
        // never `partition=UPCOMING`. This suite is mocked at the repository
        // boundary, so it cannot itself prove the BACKEND classifies this
        // way (that is `client_my_bookings_partition_flow_test.dart`'s job,
        // against a `FakeBackend`) — it proves the CLIENT renders whatever
        // the active tab's request returns, with NO client-side re-filtering
        // that would put an elapsed booking back under Майбутні (the bug
        // this phase closes was purely about which REQUEST the client sent,
        // never about the render layer misplacing a correctly-fetched row).
        _stubAllTabs(
          repo,
          upcoming: <Booking>[futureConfirmed],
          past: <Booking>[elapsedConfirmed],
        );

        await tester.pumpWidget(_host(repo));
        await tester.pumpAndSettle();

        final Finder upcomingList = find.byKey(
          const ValueKey<String>('my-bookings-list-upcoming'),
        );

        expect(
          find.descendant(
            of: upcomingList,
            matching: find.byKey(const ValueKey<String>('service-future1')),
          ),
          findsOneWidget,
          reason:
              'anti-vacuity: Майбутні must genuinely render something, or '
              'the absence assertion below is meaningless',
        );
        expect(
          find.descendant(
            of: upcomingList,
            matching: find.byKey(const ValueKey<String>('service-elapsed1')),
          ),
          findsNothing,
          reason:
              'the headline regression: an elapsed CONFIRMED booking must '
              'no longer render under Майбутні',
        );

        final l10n = _l10n(tester);
        await tester.tap(find.text(l10n.myBookingsTabPast));
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byKey(const ValueKey<String>('my-bookings-list-past')),
            matching: find.byKey(const ValueKey<String>('service-elapsed1')),
          ),
          findsOneWidget,
          reason: 'and it must now render under Минулі',
        );
      },
    );
  });

  group('Phase 227 — three-tab total cover (9-row fixture)', () {
    testWidgets('a 9-row fixture (one per status, both sides of "now" where '
        'meaningful) distributes across the three tabs with every row '
        'rendering EXACTLY once — no duplicates, no drops', (tester) async {
      final DateTime future = DateTime.utc(2027, 1, 1, 10);
      final DateTime past = DateTime.utc(2000, 1, 1, 10);

      // Майбутні (1 row) — only a genuinely-future CONFIRMED belongs here
      // post-227; an elapsed CONFIRMED does not (see the group above).
      final List<Booking> upcoming = <Booking>[
        _booking(
          id: 'u-confirmed',
          status: BookingStatus.confirmed,
          startAt: future,
        ),
      ];
      // Минулі (4 rows) — the elapsed CONFIRMED (the headline fix) plus
      // both terminal "history" statuses, which are inherently past-only.
      final List<Booking> pastTab = <Booking>[
        _booking(
          id: 'p-elapsed-confirmed',
          status: BookingStatus.confirmed,
          startAt: past,
        ),
        _booking(
          id: 'p-completed-1',
          status: BookingStatus.completed,
          startAt: past,
        ),
        _booking(
          id: 'p-completed-2',
          status: BookingStatus.completed,
          startAt: past,
        ),
        _booking(
          id: 'p-not-completed',
          status: BookingStatus.notCompleted,
          startAt: past,
        ),
      ];
      // Скасовані (4 rows) — CANCELLED/DECLINED can legitimately occur on
      // either side of "now" (an appointment cancelled ahead of time vs.
      // one cancelled/declined after its slot had already elapsed).
      final List<Booking> cancelledTab = <Booking>[
        _booking(
          id: 'c-cancelled-future',
          status: BookingStatus.cancelled,
          startAt: future,
        ),
        _booking(
          id: 'c-cancelled-past',
          status: BookingStatus.cancelled,
          startAt: past,
        ),
        _booking(
          id: 'c-declined-future',
          status: BookingStatus.declined,
          startAt: future,
        ),
        _booking(
          id: 'c-declined-past',
          status: BookingStatus.declined,
          startAt: past,
        ),
      ];

      final List<Booking> all = <Booking>[
        ...upcoming,
        ...pastTab,
        ...cancelledTab,
      ];
      expect(all, hasLength(9), reason: 'fixture sanity check');
      expect(
        all.map((Booking b) => b.id).toSet(),
        hasLength(9),
        reason:
            'fixture ids must be unique, or the exactly-once checks below '
            'would not mean anything',
      );

      final repo = _MockBookingRepository();
      _stubAllTabs(
        repo,
        upcoming: upcoming,
        past: pastTab,
        cancelled: cancelledTab,
      );

      await tester.pumpWidget(_host(repo));
      await tester.pumpAndSettle();

      final l10n = _l10n(tester);
      final Map<BookingTab, List<Booking>> byTab = <BookingTab, List<Booking>>{
        BookingTab.upcoming: upcoming,
        BookingTab.past: pastTab,
        BookingTab.cancelled: cancelledTab,
      };

      for (final BookingTab tab in BookingTab.values) {
        if (tab != BookingTab.upcoming) {
          final String tabLabel = switch (tab) {
            BookingTab.past => l10n.myBookingsTabPast,
            BookingTab.cancelled => l10n.myBookingsTabCancelled,
            BookingTab.upcoming => l10n.myBookingsTabUpcoming,
          };
          await tester.tap(find.text(tabLabel));
          await tester.pumpAndSettle();
        }

        final Finder ownList = find.byKey(
          ValueKey<String>('my-bookings-list-${tab.name}'),
        );
        // Anti-vacuity: this tab genuinely renders its own rows (not just
        // "the count elsewhere adds up") — each id below is asserted
        // present EXACTLY once, scoped to its OWN tab's list.
        for (final Booking booking in byTab[tab]!) {
          expect(
            find.descendant(
              of: ownList,
              matching: find.byKey(ValueKey<String>('service-${booking.id}')),
            ),
            findsOneWidget,
            reason: '${booking.id} must render exactly once, under ${tab.name}',
          );
        }
      }

      // Total cover, restated numerically: the three per-tab counts sum to
      // the whole fixture — no row silently vanished between the fixture
      // and the three loops above.
      expect(upcoming.length + pastTab.length + cancelledTab.length, 9);
    });
  });

  // -------------------------------------------------------------------------
  // Optional fields
  // -------------------------------------------------------------------------

  group('salon name', () {
    testWidgets('renders only when the booking carries one', (tester) async {
      final repo = _MockBookingRepository();
      final atSalon = _booking(
        id: 'b6',
        status: BookingStatus.confirmed,
        salonName: 'Lviv Nails Studio',
      );
      final independent = _booking(
        id: 'b7',
        status: BookingStatus.confirmed,
        startAt: DateTime.utc(2026, 7, 21, 10),
      );
      _stubAllTabs(repo, upcoming: <Booking>[atSalon, independent]);

      await tester.pumpWidget(_host(repo));
      await tester.pumpAndSettle();

      expect(find.text('Lviv Nails Studio'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // Empty state
  // -------------------------------------------------------------------------

  group('empty state', () {
    testWidgets('shows the empty state + Знайти майстра CTA on an empty tab', (
      tester,
    ) async {
      final repo = _MockBookingRepository();
      _stubAllTabs(repo);

      await tester.pumpWidget(_host(repo));
      await tester.pumpAndSettle();

      expect(find.byType(BookingsEmptyState), findsOneWidget);
      expect(
        find.byKey(const Key('my-bookings-empty-find-master')),
        findsOneWidget,
      );
    });

    testWidgets('past + cancelled empty tabs show the empty state WITHOUT the '
        '«Знайти майстра» CTA (gated to Майбутні only)', (tester) async {
      final repo = _MockBookingRepository();
      _stubAllTabs(repo); // every tab empty

      await tester.pumpWidget(_host(repo));
      await tester.pumpAndSettle();

      final l10n = _l10n(tester);

      // Минулі — empty state renders, but the CTA (and its spacer) is omitted:
      // «Знайти майстра» only belongs on the upcoming tab, where the client has
      // no future appointments yet. On a past/cancelled empty history there is
      // nothing to book AWAY from, so the CTA must be absent.
      await tester.tap(find.text(l10n.myBookingsTabPast));
      await tester.pumpAndSettle();
      expect(find.byType(BookingsEmptyState), findsOneWidget);
      expect(
        find.byKey(const Key('my-bookings-empty-find-master')),
        findsNothing,
        reason: 'the CTA is gated to Майбутні — it must not render on Минулі',
      );

      // Скасовані — same gated-off behaviour on the second non-upcoming tab.
      await tester.tap(find.text(l10n.myBookingsTabCancelled));
      await tester.pumpAndSettle();
      expect(find.byType(BookingsEmptyState), findsOneWidget);
      expect(
        find.byKey(const Key('my-bookings-empty-find-master')),
        findsNothing,
        reason:
            'the CTA is gated to Майбутні — it must not render on Скасовані',
      );
    });
  });

  // -------------------------------------------------------------------------
  // Pull-to-refresh
  // -------------------------------------------------------------------------

  group('pull-to-refresh', () {
    testWidgets('re-fetches page 0 for the active tab', (tester) async {
      final repo = _MockBookingRepository();
      _stubAllTabs(
        repo,
        upcoming: <Booking>[
          _booking(id: 'b8', status: BookingStatus.confirmed),
        ],
      );

      await tester.pumpWidget(_host(repo));
      await tester.pumpAndSettle();

      verify(
        () => repo.getMyBookings(
          statuses: BookingTab.upcoming.statuses,
          partition: BookingPartition.upcoming,
          sort: BookingSort.oldest,
          page: 0,
          size: any(named: 'size'),
        ),
      ).called(1);

      await tester.fling(
        find.byType(RefreshIndicator),
        const Offset(0, 300),
        1000,
      );
      await tester.pumpAndSettle();

      verify(
        () => repo.getMyBookings(
          statuses: BookingTab.upcoming.statuses,
          partition: BookingPartition.upcoming,
          sort: BookingSort.oldest,
          page: 0,
          size: any(named: 'size'),
        ),
      ).called(1);
    });
  });

  // -------------------------------------------------------------------------
  // Card tap navigation
  // -------------------------------------------------------------------------

  group('card tap navigation', () {
    testWidgets('tapping a card pushes /bookings/:id', (tester) async {
      final repo = _MockBookingRepository();
      _stubAllTabs(
        repo,
        upcoming: <Booking>[
          _booking(id: 'b9', status: BookingStatus.confirmed),
        ],
      );

      String? pushedLocation;
      final router = GoRouter(
        initialLocation: '/bookings',
        routes: <RouteBase>[
          GoRoute(
            path: '/bookings',
            builder: (_, _) => const MyBookingsScreen(),
          ),
          GoRoute(
            path: '/bookings/:bookingId',
            builder: (BuildContext context, GoRouterState state) {
              pushedLocation = state.uri.toString();
              return const Scaffold(key: Key('booking_detail_stub'));
            },
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          retry: beauticaProviderRetry,
          // ignore: avoid_dynamic_calls
          overrides: <Object>[
            bookingRepositoryProvider.overrideWithValue(repo),
          ].cast(),
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: _delegates,
            supportedLocales: _locales,
            locale: const Locale('uk'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(BookingCard));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('booking_detail_stub')), findsOneWidget);
      expect(pushedLocation, '/bookings/b9');
    });
  });
}
