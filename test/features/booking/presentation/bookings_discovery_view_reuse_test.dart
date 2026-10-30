// Phase 7.11 — pins the salon-reuse seam `BookingsDiscoveryView` exists to
// provide.
//
// `showMasterFilter` is the flag the salon board flips to offer the teammate
// («Майстер») filter section — see the file header of
// `bookings_discovery_view.dart`. IT IS NO LONGER A NO-OP: the section shipped
// 2026-09-18, multi-select and client-side, and `SalonBookingsScreen` passes
// `true` alongside `masterFilterOptions` (its roster). What this file pins is
// that flipping it changes NOTHING on the master's own screen, in either
// direction:
//   * `showMasterFilter: false` (the master's own screen, forever) renders NO
//     teammate-filter chrome. An accidental `true` on the master's own call
//     site is caught here rather than silently leaking a control that makes no
//     sense for a single master.
//   * `showMasterFilter: true` WITH NO `masterFilterOptions` — which is what a
//     master-scope mount would be — still builds cleanly and still renders no
//     section, because the flag and the option universe are ANDed. An empty
//     universe never produces an empty heading.
//
// Both cases pump the SAME `query`/`onBookingTap` and assert the rest of the
// composition (the status/service filter button, the header, the day rail)
// renders identically regardless of the flag — which is what "the view never
// branches on scope" claims. The «Майстер» section's own behaviour, on a
// scope that actually has a roster, is owned by
// `bookings_filter_sheet_test.dart` and
// `salon_bookings_master_filter_test.dart`.

import 'dart:async';

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/application/booked_days_notifier.dart';
import 'package:beautica_mobile/features/booking/application/bookings_day_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/bookings_day_query.dart';
import 'package:beautica_mobile/features/booking/presentation/bookings_discovery_view.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_day_rail.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_month_calendar_panel.dart';
import 'package:beautica_mobile/shared/formatters/api_date.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/booking_fixture_dates.dart';
import '../../../helpers/pump_app.dart';

class _MockBookingRepository extends Mock implements BookingRepository {}

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
}

class _StubAuth extends AuthNotifier {
  @override
  Future<AuthSession> build() async => const AuthSession.authenticated(
    user: User(
      id: 'master-1',
      email: 'master1@beautica.ua',
      role: UserRole.independentMaster,
    ),
    accessToken: 't',
  );
}

/// Which dot provider a self-heal test mounts the view against.
enum _DotScope { own, ownerMaster, salon }

const String _salonId = 'salon-1';

Booking _booking(String id) {
  // Now-relative, never an absolute literal — see
  // `test/helpers/booking_fixture_dates.dart` for the time bomb this avoids.
  final DateTime start = futureBookingStart();
  return Booking(
    id: id,
    masterId: 'm1',
    masterFirstName: 'Марія',
    masterLastName: 'Іванюк',
    masterType: 'INDEPENDENT_MASTER',
    clientId: 'c-$id',
    clientFirstName: 'Олена',
    clientLastName: 'Ковальчук',
    serviceId: 's1',
    serviceName: 'Манікюр з покриттям',
    durationMinutes: 90,
    price: 650,
    startAt: start,
    endAt: start.add(const Duration(minutes: 90)),
    status: BookingStatus.confirmed,
    canReview: false,
  );
}

/// Any key a teammate-filter affordance would plausibly use, INCLUDING the
/// section that actually shipped — none of these may render on a master-scope
/// mount, under EITHER flag value.
const List<String> _plausibleMasterFilterKeys = <String>[
  'bookings-discovery-master-filter',
  'bookings-discovery-master-filter-button',
  'master-filter-sheet',
  'salon-master-filter-sheet',
  // The real one (`bookings_filter_sheet.dart`). Kept alongside the
  // speculative names above so this list still fails if either the section or
  // a future affordance leaks onto a single master's screen.
  'master-bookings-filter-section-master',
];

Future<void> _pump(
  WidgetTester tester, {
  required bool showMasterFilter,
}) async {
  final repo = _MockBookingRepository();
  when(
    () => repo.getMyBookings(
      statuses: any(named: 'statuses'),
      page: any(named: 'page'),
      size: any(named: 'size'),
      sort: any(named: 'sort'),
      serviceIds: any(named: 'serviceIds'),
      from: any(named: 'from'),
      to: any(named: 'to'),
    ),
  ).thenAnswer(
    (_) async => PageResponse<Booking>(
      items: <Booking>[_booking('b1')],
      page: 0,
      totalPages: 1,
      totalElements: 1,
    ),
  );

  await tester.pumpApp(
    BookingsDiscoveryView(
      query: BookingsDayQuery.of(day: DateTime(2026, 7, 20)),
      title: 'Test Discovery Title',
      showMasterFilter: showMasterFilter,
      onBookingTap: (Booking _) {},
    ),
    overrides: <Object>[
      screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
      bookingRepositoryProvider.overrideWithValue(repo),
      bookedDaysProvider.overrideWith((ref) async => <DateTime>{}),
    ],
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    registerFallbackValue(BookingStatus.confirmed);
    registerFallbackValue(<BookingStatus>[]);
  });

  group('showMasterFilter: false — the master\'s own screen, forever', () {
    testWidgets('renders no teammate-filter affordance', (tester) async {
      await _pump(tester, showMasterFilter: false);
      expect(tester.takeException(), isNull);

      for (final String key in _plausibleMasterFilterKeys) {
        expect(
          find.byKey(Key(key)),
          findsNothing,
          reason:
              '"$key" rendered under showMasterFilter: false — a single '
              'master\'s own list must never offer the teammate filter.',
        );
      }
    });

    testWidgets('the rest of the composition renders normally', (tester) async {
      await _pump(tester, showMasterFilter: false);

      expect(find.byType(BookingsDayRail), findsOne);
      expect(find.byKey(const Key('master-bookings-filter-button')), findsOne);
      expect(
        find.text('Test Discovery Title'),
        findsOne,
      ); // the passed-through title
    });
  });

  group('showMasterFilter: true — the salon drop-in point', () {
    testWidgets(
      'builds cleanly, with no master-specific chrome that would break '
      'under a salon scope',
      (tester) async {
        await _pump(tester, showMasterFilter: true);

        expect(tester.takeException(), isNull);
        expect(find.byType(BookingsDiscoveryView), findsOne);
        expect(find.byType(BookingsDayRail), findsOne);
      },
    );

    testWidgets(
      'renders no teammate-filter affordance WITHOUT masterFilterOptions — '
      'the flag and the option universe are ANDed',
      (tester) async {
        await _pump(tester, showMasterFilter: true);
        // The sheet is not open here; this pins the header chrome. The
        // section's own "empty universe hides the heading" rule is asserted
        // against an OPEN sheet in `bookings_filter_sheet_test.dart`.
        for (final String key in _plausibleMasterFilterKeys) {
          expect(find.byKey(Key(key)), findsNothing);
        }
      },
    );

    testWidgets(
      'renders IDENTICALLY to showMasterFilter: false on a master scope — '
      'the flag alone narrows nothing',
      (tester) async {
        await _pump(tester, showMasterFilter: true);

        expect(
          find.byKey(const Key('master-bookings-filter-button')),
          findsOne,
        );
        expect(find.text('Test Discovery Title'), findsOne);
        // No badge: an unoffered section can never light the funnel.
        expect(
          find.byKey(const Key('master-bookings-filter-badge')),
          findsNothing,
        );
      },
    );
  });

  // 2026-10-30 user report — a day's list shows bookings but its rail dot is
  // missing until the app is reopened. The dot set is a 30-minute cached
  // ±180-day sweep; the day list re-fetches on every select, so a booking made
  // off-device (guest link, client app, another device) reaches the list
  // first. The view must re-fetch the dots when the list it just loaded has
  // bookings on a day the dot set lacks — and must do so sparingly.
  //
  // FALSIFIED (each guard removed in turn, then restored):
  //   * the post-frame `_refreshDotsIfDayMissing` call in the timeline
  //     Consumer → the heal test fails (no dot, 1 fetch);
  //   * `_lastDotRefreshDay == day` → the same-day test fails (4);
  //   * `identical(dots, _lastHealedDots)` → the A→B→A test fails (3);
  //   * the ±kBookedDaysSpanDays window check → the far-day test fails (2);
  //   * `if (dotsAsync.isLoading) return;` → the mid-refresh test fails (3);
  //   * the salon / owner-master invalidate branch pointed at
  //     `bookedDaysProvider` → the matching scope test fails (no dot).
  // End-to-end twin: `integration_test/master_bookings_week_rail_flow_test.dart`.
  group('stale dot self-heal', () {
    // ONE pinned clock for fixture AND widget (clock-coherence invariant).
    final DateTime fixedNow = futureBookingStart();
    final DateTime today = kyivToday(() => fixedNow);
    // Days in the SAME rail week as today (Monday-first) other than today, so
    // their chips are on screen without paging. Calendar arithmetic only.
    final DateTime monday = DateTime(
      today.year,
      today.month,
      today.day - (today.weekday - DateTime.monday),
    );
    final List<DateTime> otherWeekDays = <DateTime>[
      for (int i = 0; i < 7; i++)
        DateTime(monday.year, monday.month, monday.day + i),
    ].where((DateTime d) => d != today).toList();
    final DateTime dayA = otherWeekDays[0];
    final DateTime dayB = otherWeekDays[1];
    // One day past the dot window — it can never carry a dot.
    final DateTime farDay = DateTime(
      today.year,
      today.month,
      today.day + kBookedDaysSpanDays + 1,
    );

    setUpAll(initBeauticaTimeZones);

    /// Pumps the view on today (no bookings). Every day in [bookedListDays]
    /// lists one booking; the [scope]'s dot provider's n-th sweep returns
    /// `dotsForFetch(n)` (a Future to hold a sweep mid-flight); every day
    /// whose list is fetched is added to [listedDays]. ALL three dot
    /// providers are overridden and counted into [sweeps] (the other two
    /// answer an empty set), so a test can prove WHICH one a heal hit.
    /// Returns a getter for the [scope] provider's sweep count.
    Future<int Function()> pumpHeal(
      WidgetTester tester, {
      required Set<DateTime> bookedListDays,
      required FutureOr<Set<DateTime>> Function(int fetch) dotsForFetch,
      Set<DateTime>? listedDays,
      _DotScope scope = _DotScope.own,
      Map<_DotScope, int>? sweeps,
    }) async {
      final Map<_DotScope, int> counts = sweeps ?? <_DotScope, int>{};
      final repo = _MockBookingRepository();
      PageResponse<Booking> answer(Invocation inv) {
        final DateTime? from = inv.namedArguments[#from] as DateTime?;
        final DateTime? day = from == null ? null : dateOnly(from);
        if (day != null) listedDays?.add(day);
        final bool booked = day != null && bookedListDays.contains(day);
        return PageResponse<Booking>(
          items: booked
              ? <Booking>[
                  _booking('b-${toApiDate(day)}').copyWith(
                    startAt: DateTime(day.year, day.month, day.day, 12),
                    endAt: DateTime(day.year, day.month, day.day, 13, 30),
                  ),
                ]
              : const <Booking>[],
          page: 0,
          totalPages: 1,
          totalElements: booked ? 1 : 0,
        );
      }

      when(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          page: any(named: 'page'),
          size: any(named: 'size'),
          sort: any(named: 'sort'),
          serviceIds: any(named: 'serviceIds'),
          from: any(named: 'from'),
          to: any(named: 'to'),
          cancelToken: any(named: 'cancelToken'),
          asMaster: any(named: 'asMaster'),
        ),
      ).thenAnswer((Invocation inv) async => answer(inv));
      when(
        () => repo.getSalonBookings(
          salonId: any(named: 'salonId'),
          masterId: any(named: 'masterId'),
          page: any(named: 'page'),
          size: any(named: 'size'),
          sort: any(named: 'sort'),
          from: any(named: 'from'),
          to: any(named: 'to'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((Invocation inv) async => answer(inv));

      Future<Set<DateTime>> sweep(_DotScope s) async {
        final int n = counts[s] = (counts[s] ?? 0) + 1;
        return s == scope ? await dotsForFetch(n) : <DateTime>{};
      }

      await tester.pumpApp(
        BookingsDiscoveryView(
          query: switch (scope) {
            _DotScope.own => BookingsDayQuery.of(day: today),
            _DotScope.ownerMaster => BookingsDayQuery.of(
              day: today,
              asOwnerMaster: true,
            ),
            _DotScope.salon => BookingsDayQuery.salonOf(
              day: today,
              salonId: _salonId,
            ),
          },
          title: 'Test Discovery Title',
          onBookingTap: (Booking _) {},
        ),
        overrides: <Object>[
          screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
          bookingRepositoryProvider.overrideWithValue(repo),
          bookedDaysProvider.overrideWith((ref) => sweep(_DotScope.own)),
          ownerMasterBookedDaysProvider.overrideWith(
            (ref) => sweep(_DotScope.ownerMaster),
          ),
          salonBookedDaysProvider.overrideWith((ref, String salonId) {
            expect(salonId, _salonId);
            return sweep(_DotScope.salon);
          }),
          clockProvider.overrideWithValue(() => fixedNow),
          authProvider.overrideWith(_StubAuth.new),
        ],
      );
      await tester.pumpUntilGone(
        find.byKey(const Key('master-bookings-skeleton')),
      );
      expect(counts[scope], 1, reason: 'sanity: empty today, no re-fetch');
      return () => counts[scope] ?? 0;
    }

    Future<void> selectRailDay(WidgetTester tester, DateTime day) async {
      await tester.tap(find.byKey(dayChipKey(day)));
      // fixed-wait-ok: crosses the 220ms day-selection debounce Timer, which
      // pumpAndSettle never fires; the list fetch is awaited by pumpAndSettle.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
    }

    ProviderContainer containerOf(WidgetTester tester) =>
        ProviderScope.containerOf(
          tester.element(find.byType(BookingsDiscoveryView)),
        );

    testWidgets('a loaded day with bookings but no dot re-fetches the dots '
        'and the day then shows its dot', (tester) async {
      final int Function() fetches = await pumpHeal(
        tester,
        bookedListDays: <DateTime>{dayA},
        // The stale cache: the first sweep predates A's booking.
        dotsForFetch: (int n) => n == 1 ? <DateTime>{} : <DateTime>{dayA},
      );
      expect(find.byKey(dayDotKey(dayA)), findsNothing, reason: 'sanity');

      await tester.tap(find.byKey(dayChipKey(dayA)));
      // fixed-wait-ok: crosses the 220ms day-selection debounce Timer; the
      // fetch itself is awaited below.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpUntilFound(find.byKey(dayDotKey(dayA)));

      expect(find.byKey(dayDotKey(dayA)), findsOneWidget);
      expect(fetches(), 2, reason: 'exactly one self-heal re-fetch — no loop');
    });

    testWidgets('the same day re-emitting never heals twice, even against a '
        'fresh (externally refreshed) dot set', (tester) async {
      // The two endpoints disagree: the dots never carry A or B.
      final int Function() fetches = await pumpHeal(
        tester,
        bookedListDays: <DateTime>{dayA, dayB},
        dotsForFetch: (int _) => <DateTime>{},
      );
      await selectRailDay(tester, dayA);
      expect(fetches(), 2, reason: 'precondition: A healed once');
      // B's list settles the heal: its result is adopted as trusted.
      await selectRailDay(tester, dayB);
      // Back on A (cached list — no emission yet).
      await selectRailDay(tester, dayA);
      expect(fetches(), 2, reason: 'precondition: no heal on B or back on A');

      // An unrelated refresh (in-app write, TTL) mints a NEW, still-undotted
      // set — so only the per-day guard stands between A and a second sweep.
      containerOf(tester).invalidate(bookedDaysProvider);
      await tester.pumpAndSettle();
      expect(fetches(), 3, reason: 'precondition: the external refresh');

      // A's list re-emits (any day-list refresh).
      containerOf(tester).invalidate(bookingsDayProvider);
      await tester.pumpAndSettle();

      expect(fetches(), 3, reason: 'same day: no second self-heal');
    });

    testWidgets('A→B→A across two undotted days heals at most once for that '
        'dot set', (tester) async {
      final int Function() fetches = await pumpHeal(
        tester,
        bookedListDays: <DateTime>{dayA, dayB},
        // A NEW instance per sweep, never carrying either day.
        dotsForFetch: (int _) => <DateTime>{},
      );

      await selectRailDay(tester, dayA);
      await selectRailDay(tester, dayB);
      await selectRailDay(tester, dayA);

      expect(
        fetches(),
        2,
        reason:
            'one self-heal (on A); the set it produced is trusted for B and '
            'the return to A',
      );
    });

    testWidgets('a day outside the ±kBookedDaysSpanDays dot window never '
        'triggers a dot sweep', (tester) async {
      final Set<DateTime> listed = <DateTime>{};
      final int Function() fetches = await pumpHeal(
        tester,
        bookedListDays: <DateTime>{farDay},
        dotsForFetch: (int _) => <DateTime>{},
        listedDays: listed,
      );

      // The panel's grid-cell path — the real production callback, invoked
      // directly because the far day's cell is months away.
      tester
          .widget<BookingsMonthCalendarPanel>(
            find.byType(BookingsMonthCalendarPanel),
          )
          .onSelectDay(farDay);
      // fixed-wait-ok: crosses the 220ms day-selection debounce Timer, which
      // pumpAndSettle never fires; the list fetch is awaited by pumpAndSettle.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(
        listed,
        contains(farDay),
        reason: 'precondition: the far day\'s list (with its booking) loaded',
      );
      expect(
        fetches(),
        1,
        reason:
            'a day that can never carry a dot heals '
            'nothing',
      );
    });

    testWidgets('a day loaded while the dots are mid-refresh never sweeps '
        'again — the in-flight refresh is left to deliver the dot', (
      tester,
    ) async {
      final Completer<Set<DateTime>> refresh = Completer<Set<DateTime>>();
      final Set<DateTime> listed = <DateTime>{};
      final int Function() fetches = await pumpHeal(
        tester,
        bookedListDays: <DateTime>{dayA},
        // Sweep 1: the stale cache (no A). Sweep 2: an unrelated refresh
        // (in-app write / TTL), held open. Anything later is a self-heal.
        dotsForFetch: (int n) => switch (n) {
          1 => <DateTime>{},
          2 => refresh.future,
          _ => <DateTime>{dayA},
        },
        listedDays: listed,
      );

      // The external refresh starts and stays loading WITH the previous
      // (stale, A-less) value — the shape a bare null check would act on.
      containerOf(tester).invalidate(bookedDaysProvider);
      await tester.pump();
      final AsyncValue<Set<DateTime>> mid = containerOf(
        tester,
      ).read(bookedDaysProvider);
      expect(mid.isLoading, isTrue, reason: 'precondition: mid-refresh');
      expect(mid.value, isNotNull, reason: 'precondition: previous kept');
      expect(fetches(), 2, reason: 'precondition: the external refresh');

      // A's list (with its booking) resolves while the dots are loading.
      await tester.tap(find.byKey(dayChipKey(dayA)));
      // fixed-wait-ok: crosses the 220ms day-selection debounce Timer; the
      // dot refresh is deliberately held open, so no pumpAndSettle here.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      await tester.pump();
      expect(listed, contains(dayA), reason: 'precondition: A\'s list loaded');
      expect(fetches(), 2, reason: 'no self-heal while the dots are loading');
      expect(
        containerOf(tester).read(bookedDaysProvider).isLoading,
        isTrue,
        reason: 'A settled while the dots were still loading',
      );

      // The refresh lands carrying A — the dot the guard waited for.
      refresh.complete(<DateTime>{dayA});
      await tester.pumpAndSettle();

      expect(find.byKey(dayDotKey(dayA)), findsOneWidget);
      expect(fetches(), 2, reason: 'the in-flight refresh was never doubled');
    });

    testWidgets('an in-app write that refreshes the dots after a heal is not '
        'mistaken for the heal\'s result — the next undotted day still heals '
        'once and gets its dot', (tester) async {
      final int Function() fetches = await pumpHeal(
        tester,
        bookedListDays: <DateTime>{dayA, dayB},
        // 1: stale cache. 2: the heal for A (carries A). 3: an in-app write's
        // refresh — B was booked off-device after it. 4: the heal for B.
        dotsForFetch: (int n) => switch (n) {
          1 => <DateTime>{},
          2 || 3 => <DateTime>{dayA},
          _ => <DateTime>{dayA, dayB},
        },
      );

      await selectRailDay(tester, dayA);
      expect(fetches(), 2, reason: 'precondition: A healed');
      expect(find.byKey(dayDotKey(dayA)), findsOneWidget);

      // The write lands between the heal's load and the next list read.
      containerOf(tester).invalidate(bookedDaysProvider);
      await tester.pumpAndSettle();
      expect(fetches(), 3, reason: 'precondition: the in-app write refresh');

      await selectRailDay(tester, dayB);

      expect(
        find.byKey(dayDotKey(dayB)),
        findsOneWidget,
        reason:
            'the write\'s set is a NEW set, so B may heal once — adopting it '
            'as the heal\'s result would leave B dotless',
      );
      expect(fetches(), 4, reason: 'exactly one heal for B — no loop');
    });

    testWidgets('the salon board heals salonBookedDaysProvider(salonId), never '
        'the master-scoped dot providers', (tester) async {
      final Map<_DotScope, int> sweeps = <_DotScope, int>{};
      final int Function() fetches = await pumpHeal(
        tester,
        scope: _DotScope.salon,
        sweeps: sweeps,
        bookedListDays: <DateTime>{dayA},
        dotsForFetch: (int n) => n == 1 ? <DateTime>{} : <DateTime>{dayA},
      );

      await tester.tap(find.byKey(dayChipKey(dayA)));
      // fixed-wait-ok: crosses the 220ms day-selection debounce Timer; the
      // fetch itself is awaited below.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpUntilFound(find.byKey(dayDotKey(dayA)));

      expect(find.byKey(dayDotKey(dayA)), findsOneWidget);
      expect(fetches(), 2, reason: 'one salon-scope self-heal');
      expect(sweeps[_DotScope.own] ?? 0, 0, reason: 'own dots untouched');
      expect(sweeps[_DotScope.ownerMaster] ?? 0, 0);
    });

    testWidgets('the owner-as-master view heals ownerMasterBookedDaysProvider, '
        'never the own or salon dot providers', (tester) async {
      final Map<_DotScope, int> sweeps = <_DotScope, int>{};
      final int Function() fetches = await pumpHeal(
        tester,
        scope: _DotScope.ownerMaster,
        sweeps: sweeps,
        bookedListDays: <DateTime>{dayA},
        dotsForFetch: (int n) => n == 1 ? <DateTime>{} : <DateTime>{dayA},
      );

      await tester.tap(find.byKey(dayChipKey(dayA)));
      // fixed-wait-ok: crosses the 220ms day-selection debounce Timer; the
      // fetch itself is awaited below.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpUntilFound(find.byKey(dayDotKey(dayA)));

      expect(find.byKey(dayDotKey(dayA)), findsOneWidget);
      expect(fetches(), 2, reason: 'one owner-master-scope self-heal');
      expect(sweeps[_DotScope.own] ?? 0, 0, reason: 'own dots untouched');
      expect(sweeps[_DotScope.salon] ?? 0, 0);
    });
  });
}
