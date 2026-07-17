// QA (track 14.x booking) — INTERACTION-coverage suite for [MyBookingsScreen].
//
// my_bookings_screen_test.dart proves the async STATES render (loading /
// partition / empty / salon-name / pull-to-refresh / card-tap). This suite
// closes the remaining INTERACTIVE-element gaps the verification pass found —
// every one is a tap/gesture that fires a callback the state suite only
// asserted the PRESENCE of, never exercised:
//   • the empty-state «Знайти майстра» CTA → context.go('/search');
//   • the ERROR state renders + its retry button re-fetches (the one async
//     state my_bookings_screen_test never pumped);
//   • the infinite-scroll trigger → dragging to the list foot fetches the
//     next page (the notifier suite proves loadMore's merge/guards in
//     isolation; this proves the SCROLL actually calls it).
//
// Finders are key-first; any status/label copy is asserted through l10n, never
// a raw Cyrillic literal — matching my_bookings_screen_test.dart and the CI
// no-raw-string gate.
//
// Wire-format note (backend Phase 26.1/26.3, fixing mobile-debugger findings
// A + B): `GET /bookings/me` now takes the tab's WHOLE status set + a
// `sort=startsAt,<asc|desc>` param in ONE request per tab, instead of one
// fan-out fetch per status — see `booking_repository.dart` and
// `my_bookings_notifier.dart`.

import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/booking_tab.dart';
import 'package:beautica_mobile/features/booking/presentation/my_bookings_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/overflow_guard.dart';

class _MockBookingRepository extends Mock implements BookingRepository {}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

Booking _booking({
  required String id,
  required BookingStatus status,
  DateTime? startAt,
}) {
  final DateTime start = startAt ?? DateTime.utc(2026, 7, 20, 15);
  return Booking(
    id: id,
    masterId: 'master-$id',
    masterFirstName: 'Марія',
    masterLastName: 'Іванюк',
    masterAvatarUrl: null,
    masterType: 'INDEPENDENT_MASTER',
    salonName: null,
    serviceId: 'service-$id',
    serviceName: 'Манікюр з покриттям',
    categoryName: 'Манікюр',
    cityLabel: 'Львів',
    districtLabel: null,
    street: null,
    buildingNo: null,
    durationMinutes: 60,
    price: 650,
    startAt: start,
    endAt: start.add(const Duration(hours: 1)),
    status: status,
    canReview: false,
    clientComment: null,
    providerComment: null,
    clientCancellationNote: null,
    masterProfessionalTitle: null,
    locationNote: null,
  );
}

PageResponse<Booking> _page(
  List<Booking> items, {
  int page = 0,
  int totalPages = 1,
}) => PageResponse<Booking>(
  items: items,
  page: page,
  totalPages: totalPages,
  totalElements: items.length,
);

/// Stubs the ONE `getMyBookings` request each of the three tabs issues
/// (backend Phase 26.1 — the tab's whole status set travels in a single
/// call; Phase 26.3 — `ascending` drives `sort=startsAt,<asc|desc>`).
/// Defaults every tab to an empty page so a test only has to describe the
/// tab(s) it cares about.
void _stubAllTabs(
  _MockBookingRepository repo, {
  List<Booking> upcoming = const <Booking>[],
  List<Booking> past = const <Booking>[],
  List<Booking> cancelled = const <Booking>[],
}) {
  when(
    () => repo.getMyBookings(
      statuses: BookingTab.upcoming.statuses,
      ascending: true,
      page: any(named: 'page'),
      size: any(named: 'size'),
    ),
  ).thenAnswer((_) async => _page(upcoming));
  when(
    () => repo.getMyBookings(
      statuses: BookingTab.past.statuses,
      ascending: false,
      page: any(named: 'page'),
      size: any(named: 'size'),
    ),
  ).thenAnswer((_) async => _page(past));
  when(
    () => repo.getMyBookings(
      statuses: BookingTab.cancelled.statuses,
      ascending: false,
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

/// A plain `MaterialApp home:` host (no router) — for the interactions that
/// fire NO navigation (error retry, infinite scroll). [retry] disables
/// Riverpod's backoff so a build failure stays put and call counts are exact.
Widget _host(
  _MockBookingRepository repo, {
  Duration? Function(int, Object)? retry,
}) {
  return ProviderScope(
    // ignore: avoid_dynamic_calls
    overrides: <Object>[
      bookingRepositoryProvider.overrideWithValue(repo),
    ].cast(),
    retry: retry,
    child: const MaterialApp(
      localizationsDelegates: _delegates,
      supportedLocales: _locales,
      locale: Locale('uk'),
      home: MyBookingsScreen(),
    ),
  );
}

void main() {
  setUp(installOverflowGuard);

  // -------------------------------------------------------------------------
  // Empty-state CTA → «Знайти майстра» navigates to /search
  // -------------------------------------------------------------------------

  group('empty-state CTA', () {
    testWidgets('tapping «Знайти майстра» navigates to /search', (
      tester,
    ) async {
      final repo = _MockBookingRepository();
      _stubAllTabs(repo); // every tab empty → empty state on Майбутні.

      String? wentTo;
      final router = GoRouter(
        initialLocation: '/bookings',
        routes: <RouteBase>[
          GoRoute(
            path: '/bookings',
            builder: (_, _) => const MyBookingsScreen(),
          ),
          GoRoute(
            path: '/search',
            builder: (BuildContext context, GoRouterState state) {
              wentTo = state.uri.toString();
              return const Scaffold(key: Key('search_stub'));
            },
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
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

      expect(
        find.byKey(const Key('my-bookings-empty-find-master')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('my-bookings-empty-find-master')));
      await tester.pumpAndSettle();

      // The CTA fired context.go('/search') — the branch swap, not a push.
      expect(find.byKey(const Key('search_stub')), findsOneWidget);
      expect(wentTo, '/search');
    });
  });

  // -------------------------------------------------------------------------
  // Error state + retry — the async state my_bookings_screen_test never pumped
  // -------------------------------------------------------------------------

  group('error state', () {
    testWidgets('renders the error state when the first page fails', (
      tester,
    ) async {
      final repo = _MockBookingRepository();
      when(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          ascending: any(named: 'ascending'),
          page: any(named: 'page'),
          size: any(named: 'size'),
        ),
      ).thenThrow(Exception('down'));

      // Disable Riverpod's backoff retry so the AsyncError settles (no pending
      // timer at test end) and the fetch count stays exact.
      await tester.pumpWidget(_host(repo, retry: (_, _) => null));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('my_bookings_error')), findsOneWidget);
      expect(find.byKey(const Key('my_bookings_error_retry')), findsOneWidget);
    });

    testWidgets('tapping retry re-fetches the active tab', (tester) async {
      final repo = _MockBookingRepository();
      when(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          ascending: any(named: 'ascending'),
          page: any(named: 'page'),
          size: any(named: 'size'),
        ),
      ).thenThrow(Exception('down'));

      await tester.pumpWidget(_host(repo, retry: (_, _) => null));
      await tester.pumpAndSettle();

      // Майбутні issues exactly one CONFIRMED page-0 fetch on the failed build.
      verify(
        () => repo.getMyBookings(
          statuses: BookingTab.upcoming.statuses,
          ascending: true,
          page: 0,
          size: any(named: 'size'),
        ),
      ).called(1);

      await tester.tap(find.byKey(const Key('my_bookings_error_retry')));
      await tester.pumpAndSettle();

      // Retry invalidated the provider → the CONFIRMED page-0 fetch ran again.
      verify(
        () => repo.getMyBookings(
          statuses: BookingTab.upcoming.statuses,
          ascending: true,
          page: 0,
          size: any(named: 'size'),
        ),
      ).called(1);
    });
  });

  // -------------------------------------------------------------------------
  // Infinite scroll — dragging to the foot fetches the next page
  // -------------------------------------------------------------------------

  group('infinite scroll', () {
    testWidgets('scrolling to the list foot fetches the next page', (
      tester,
    ) async {
      final repo = _MockBookingRepository();
      // Page 0: eight CONFIRMED rows, totalPages 2 → hasMore is true.
      final List<Booking> firstPage = <Booking>[
        for (int i = 0; i < 8; i++)
          _booking(
            id: 'c$i',
            status: BookingStatus.confirmed,
            startAt: DateTime.utc(2026, 8, 1 + i, 10),
          ),
      ];
      when(
        () => repo.getMyBookings(
          statuses: BookingTab.upcoming.statuses,
          ascending: true,
          page: 0,
          size: any(named: 'size'),
        ),
      ).thenAnswer((_) async => _page(firstPage, page: 0, totalPages: 2));
      when(
        () => repo.getMyBookings(
          statuses: BookingTab.upcoming.statuses,
          ascending: true,
          page: 1,
          size: any(named: 'size'),
        ),
      ).thenAnswer(
        (_) async => _page(
          <Booking>[
            _booking(
              id: 'c8',
              status: BookingStatus.confirmed,
              startAt: DateTime.utc(2026, 8, 20, 10),
            ),
          ],
          page: 1,
          totalPages: 2,
        ),
      );
      // The Минулі / Скасовані tabs the drag never visits answer empty.
      when(
        () => repo.getMyBookings(
          statuses: BookingTab.past.statuses,
          ascending: false,
          page: any(named: 'page'),
          size: any(named: 'size'),
        ),
      ).thenAnswer((_) async => _page(const <Booking>[]));
      when(
        () => repo.getMyBookings(
          statuses: BookingTab.cancelled.statuses,
          ascending: false,
          page: any(named: 'page'),
          size: any(named: 'size'),
        ),
      ).thenAnswer((_) async => _page(const <Booking>[]));

      await tester.pumpWidget(_host(repo));
      await tester.pumpAndSettle();

      // Drag the active tab's list to its foot — within the 320px load-more
      // threshold — so the scroll listener calls loadMore().
      await tester.drag(
        find.byKey(const ValueKey<String>('my-bookings-list-upcoming')),
        const Offset(0, -4000),
      );
      await tester.pumpAndSettle();

      verify(
        () => repo.getMyBookings(
          statuses: BookingTab.upcoming.statuses,
          ascending: true,
          page: 1,
          size: any(named: 'size'),
        ),
      ).called(1);
    });
  });
}
