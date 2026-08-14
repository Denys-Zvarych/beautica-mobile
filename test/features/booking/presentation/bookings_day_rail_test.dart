// Phase 7.6 — the «Мої записи» day rail.
//
// Phase 7.11 — the «Всі» chip is retired (`BookingsDayQuery` has no all-days
// / range mode any more) and [BookingsDayRail.selectedDay] is now
// non-nullable: exactly one day is selected at all times, including a day
// with no bookings on it. `_rail()` below defaults `selectedDay` to [today]
// so every pre-existing call site keeps expressing "some day is selected"
// without having to say which. The Kyiv-vs-host "today" DERIVATION itself
// (`kyivToday(DateTime.now)`) is NOT this widget's
// responsibility — it lives in `BookingsDiscoveryView`, which is why that
// assertion lives in `master_bookings_screen_test.dart` instead of here; this
// file only pins that the RAIL renders whatever day it is handed as selected,
// unconditionally.
//
// The centrepiece of this suite is the DST pair. `railDayAt` exists because
// the design's `firstDay.add(Duration(days: i))` adds absolute 24-hour blocks:
// across a Europe/Kyiv transition a chain of them lands on 23:00 or 01:00
// instead of local midnight, and `bookedDaysProvider`'s `Set<DateTime>` of
// midnights then MISSES on `contains()`. The dot vanishes for a day, twice a
// year, silently — no crash, no error, no failing assertion anywhere else.
//
// These tests pin both the March and the October transition at two levels:
//
//   • the `railDayAt` unit group — pure arithmetic, no widget. Its midnight
//     invariant holds in EVERY zone, so it is meaningful on any host.
//   • two RENDERED dot-survival guards. These can only observe the skew on a
//     host whose UTC offset actually changes across the transition, so they
//     skip elsewhere and are run on CI by a dedicated `TZ=Europe/Kyiv` step.
//     See the block above `_hostObservesTransition` for why that is a CI step
//     rather than a job-wide zone, and why zone-independence is unreachable
//     here.

import 'dart:async';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_day_rail.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/calendar_grid.dart'
    show kCalendarDotColor;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/pump_app.dart';

/// Europe/Kyiv moves to summer time on the LAST SUNDAY OF MARCH (03:00 → 04:00)
/// and back on the last Sunday of October (04:00 → 03:00).
final DateTime _springForward2026 = DateTime(2026, 3, 29);
final DateTime _fallBack2026 = DateTime(2026, 10, 25);

// ---------------------------------------------------------------------------
// Host-zone gating for the two RENDERED DST guards
// ---------------------------------------------------------------------------
//
// WHY THESE SKIP RATHER THAN ASSERT THEIR PRECONDITION
//
// They were first written with `expect(hostObservesTransition(...), isTrue)`,
// which turned "this host cannot observe the bug" into a RED BUILD: CI is
// `ubuntu-latest` with no `TZ`, i.e. UTC, where the offset never changes and
// both tests failed outright.
//
// WHY CI IS NOT SIMPLY SWITCHED TO TZ=Europe/Kyiv
//
// Because the repo already depends on the runner being UTC. The booking
// formatters are pinned to Europe/Kyiv IN CODE (`shared/time/time_zones.dart`,
// `toBeauticaTime`) precisely so they are host-independent, and
// `slot_time_tz_regression_test.dart` proves that pinning by asserting Kyiv
// wall-clocks on a runner that is NOT Kyiv. Verified by mutation: reverting
// `formatSlotTime` to `time.toLocal()` fails that suite under `TZ=UTC` (2
// failures) and passes it silently under `TZ=Europe/Kyiv`. A global Kyiv
// runner would therefore disarm a guard covering seven formatters across the
// My Bookings, detail, confirm and success surfaces in order to arm two rail
// tests — a strictly worse trade.
//
// The two requirements are mutually exclusive within one process, so they are
// split ACROSS processes: the main CI suite stays UTC (default), and a
// dedicated `TZ=Europe/Kyiv` step runs this file so these two guards genuinely
// execute on CI rather than skipping there. That step is itself pinned by
// `test/ci/dst_rail_ci_coverage_test.dart` — without it this skip would decay
// into permanent coverage theatre.
//
// Making the tests zone-INDEPENDENT is not achievable: `railDayAt` is built on
// bare `DateTime`, and Dart's `DateTime` carries no zone database beyond
// local/UTC — there is no way to evaluate it "as if" in Kyiv. The `timezone`
// package's `TZDateTime` could, but the rail's date path is deliberately
// zone-conversion-free (see `shared/formatters/api_date.dart`'s header: the
// day the user picks IS the day that reaches the wire), so routing it through
// a fixed zone would change production semantics, not just the test.

/// Whether the host zone's UTC offset actually changes across the transition
/// bracketed by [before]/[after] — i.e. whether the DST skew is observable
/// here at all.
bool _hostObservesTransition(DateTime before, DateTime after) =>
    before.timeZoneOffset != after.timeZoneOffset;

/// The reason a DST guard is inert, appended to its test NAME.
///
/// `testWidgets`' `skip` is `bool?` (unlike `test`'s `dynamic`), so it cannot
/// carry a reason string of its own; folding it into the name is the only way
/// to attach it to the test at all.
///
/// Scope of that, precisely: it helps someone running THIS FILE directly, where
/// the reporter prints each test's name. It does NOT reach a CI log — in a
/// directory or whole-suite run the reporter never prints skipped names, so the
/// only trace is the bare `~2` skip counter. Do not rely on this string being
/// read on CI.
///
/// What actually prevents this skip from decaying into permanent coverage
/// theatre is `test/ci/dst_rail_ci_coverage_test.dart`, which pins the
/// dedicated `TZ=Europe/Kyiv` CI step that makes these two guards genuinely
/// execute.
String _dstSuffix(bool observed) => observed
    ? ''
    : ' [SKIPPED on this host: ${DateTime.now().timeZoneName} does not change '
          'UTC offset across this transition, so the skew cannot occur here — '
          'covered on CI by the TZ=Europe/Kyiv step]';

/// Pumps the rail as a WEEK pager (this session's user-requested rework —
/// see `bookings_day_rail.dart`'s header).
///
/// [firstDay] is the day whose WEEK is page 0, and is snapped to that week's
/// Monday with the widget's own [mondayOf]: the pre-rework rail could start
/// on any weekday, this one cannot, and every call site below keeps naming a
/// day rather than a Monday so the tests read the same way they always did.
/// [weekCount] replaces the old `dayCount` — 1 renders exactly one Mon→Sun
/// page.
Widget _rail({
  required DateTime firstDay,
  required DateTime today,
  // Defaults to [today] — the rail always has SOME day selected post-7.11;
  // callers that care which day override it explicitly.
  DateTime? selectedDay,
  Set<DateTime> bookedDays = const <DateTime>{},
  int weekCount = 3,
  int initialPage = 0,
  ValueChanged<DateTime>? onSelectDay,
}) {
  return BookingsDayRail(
    controller: PageController(initialPage: initialPage),
    firstWeekStart: mondayOf(firstDay),
    weekCount: weekCount,
    today: today,
    selectedDay: selectedDay ?? today,
    bookedDays: bookedDays,
    onSelectDay: onSelectDay ?? (_) {},
  );
}

void main() {
  // -------------------------------------------------------------------------
  // The DST arithmetic — the bug this rail is built to avoid
  // -------------------------------------------------------------------------

  group('railDayAt — DST-safe calendar arithmetic', () {
    test(
      'every offset lands on local MIDNIGHT across the spring transition',
      () {
        // Walk the week straddling the last Sunday of March.
        final DateTime base = DateTime(2026, 3, 26);
        for (int i = 0; i < 7; i++) {
          final DateTime d = railDayAt(base, i);
          expect(
            <int>[d.hour, d.minute, d.second],
            <int>[0, 0, 0],
            reason:
                'railDayAt($base, $i) = $d is not local midnight — a Set of '
                'midnights would miss it and the rail dot would vanish.',
          );
        }
      },
    );

    test(
      'every offset lands on local MIDNIGHT across the autumn transition',
      () {
        final DateTime base = DateTime(2026, 10, 22);
        for (int i = 0; i < 7; i++) {
          final DateTime d = railDayAt(base, i);
          expect(
            <int>[d.hour, d.minute, d.second],
            <int>[0, 0, 0],
            reason: 'railDayAt($base, $i) = $d is not local midnight.',
          );
        }
      },
    );

    test('the day AFTER the spring-forward date is the next calendar day', () {
      final DateTime next = railDayAt(_springForward2026, 1);
      expect(next.year, 2026);
      expect(next.month, 3);
      expect(next.day, 30);
      expect(next.hour, 0);
    });

    test('the day AFTER the fall-back date is the next calendar day', () {
      final DateTime next = railDayAt(_fallBack2026, 1);
      expect(next.year, 2026);
      expect(next.month, 10);
      expect(next.day, 26);
      expect(next.hour, 0);
    });

    test(
      'negative offsets are calendar-correct too (the rail spans backwards)',
      () {
        final DateTime prev = railDayAt(_springForward2026, -1);
        expect(prev, DateTime(2026, 3, 28));
        // Month and year boundaries normalise, which is the whole reason the
        // out-of-range day component is safe to pass.
        expect(railDayAt(DateTime(2026, 1, 1), -1), DateTime(2025, 12, 31));
        expect(railDayAt(DateTime(2026, 12, 31), 1), DateTime(2027, 1, 1));
      },
    );

    test('a full ±180-day sweep never drifts off midnight', () {
      final DateTime today = DateTime(2026, 7, 18);
      for (int i = -180; i <= 180; i++) {
        final DateTime d = railDayAt(today, i);
        expect(d.hour, 0, reason: 'offset $i drifted to ${d.hour}:00');
      }
    });

    test(
      'REGRESSION CONTRACT: railDayAt and Duration-based arithmetic agree only '
      'when no transition is crossed — this is why the design line was not '
      'transcribed',
      () {
        // Away from a transition the two agree, which is exactly why the bug
        // hides: 363 of 365 days a year, `add(Duration(days:))` looks correct.
        final DateTime plain = DateTime(2026, 7, 1);
        for (int i = 0; i < 5; i++) {
          expect(railDayAt(plain, i), plain.add(Duration(days: i)));
        }
        // The assertion that matters is the invariant itself, held on EVERY
        // day including the transitions — see the midnight sweeps above.
        // (Whether the two functions actually diverge here depends on the test
        // host's zone; the midnight invariant does not, so that is what is
        // pinned rather than a host-dependent inequality.)
      },
    );
  });

  // -------------------------------------------------------------------------
  // calendarDayCount — the REVERSE-direction DST-safe arithmetic
  // -------------------------------------------------------------------------
  //
  // `railDayAt` (above) is the DST-safe way to go FROM a date + an offset TO
  // a date. `calendarDayCount` is its mirror: FROM two dates TO a day count —
  // needed by `BookingsDiscoveryView._centreRailOn` to convert the selected
  // day back into a rail item index. `DateTime.difference(...).inDays` is NOT
  // safe for that direction either, for the same underlying reason: a
  // Europe/Kyiv spring-forward transition between the two dates shortens the
  // elapsed wall-clock span by exactly the skipped hour, and `Duration.inDays`
  // TRUNCATES rather than rounds — so a 180-calendar-day span crossing the
  // transition reports 179. `bookings_discovery_view.dart` shipped with the
  // unsafe `.difference(...).inDays` form; on a host observing Europe/Kyiv DST
  // (every real device in the market — this repo's own dev VM included) it
  // silently mis-centred the rail by one full `kRailItemExtent` on open for
  // the large majority of the year (any day whose ±180-day span crosses
  // either yearly transition). Fixed to route through this function instead.
  group('calendarDayCount — DST-safe reverse arithmetic', () {
    test('a span with NO DST transition matches plain Duration arithmetic', () {
      expect(calendarDayCount(DateTime(2026, 7, 1), DateTime(2026, 7, 19)), 18);
    });

    test(
      'a ±180-day span CROSSING the spring transition still reports the '
      'true calendar day count — the regression this function exists to fix',
      () {
        // 2026-01-20 to 2026-07-19 crosses the 2026-03-29 spring-forward.
        // Verified BEFORE this fix landed, in a Europe/Kyiv process:
        // `DateTime(2026,7,19).difference(DateTime(2026,1,20))` == 4319:00:00
        // (179 days 23 hours — one hour short because of the skipped hour),
        // so `.inDays` truncated to 179, not 180.
        expect(
          calendarDayCount(DateTime(2026, 1, 20), DateTime(2026, 7, 19)),
          180,
        );
      },
    );

    test('a ±180-day span CROSSING the autumn transition also reports the '
        'true calendar day count', () {
      // 2026-07-19 to 2027-01-15 crosses the 2026-10-25 fall-back (which
      // LENGTHENS the elapsed span by an hour — the mirror-image failure
      // mode: `.inDays` would still floor an OVER-by-one-hour span down to
      // the correct count by luck on THIS side, which is exactly why the
      // spring case above — not this one — is the one that actually caught
      // production silently returning the wrong count).
      expect(
        calendarDayCount(DateTime(2026, 7, 19), DateTime(2027, 1, 15)),
        180,
      );
    });

    test('is antisymmetric: swapping the arguments negates the result', () {
      final DateTime a = DateTime(2026, 1, 20);
      final DateTime b = DateTime(2026, 7, 19);
      expect(calendarDayCount(a, b), -calendarDayCount(b, a));
    });

    test('the same date is a zero-day span', () {
      expect(calendarDayCount(DateTime(2026, 7, 19), DateTime(2026, 7, 19)), 0);
    });
  });

  // -------------------------------------------------------------------------
  // Key identity — pinned against the LITERAL, not against the helper
  // -------------------------------------------------------------------------
  //
  // `dayChipKey`/`dayDotKey` were widened from the day-of-month to the full
  // date because the rail spans 361 days: a `…-chip-20` key matches January's
  // 20th as readily as July's, and `find.byKey` silently takes the first.
  //
  // Every OTHER test in this file addresses cells through those same helpers,
  // which makes them structurally blind to that regression — reverting
  // `dayChipKey` to `'…-chip-${day.day}'` mutates production and expectation
  // symmetrically, so all of them keep passing while the ambiguity is back.
  // These three are the only assertions here that can fail for it, so they are
  // written against literal expected strings rather than the helper.

  group('day keys are unambiguous across the rail span', () {
    test('the key carries the FULL date, not just the day-of-month', () {
      // Spelled out literally — deriving the expectation from the helper under
      // test is what made this hole in the first place.
      expect(
        dayChipKey(DateTime(2026, 7, 20)),
        const Key('master-bookings-day-chip-2026-07-20'),
      );
      expect(
        dayDotKey(DateTime(2026, 7, 20)),
        const Key('master-bookings-day-dot-2026-07-20'),
      );
    });

    test('two dates sharing a day-of-month get DISTINCT keys', () {
      // The rail spans today ± 180 days, so ~12 dates share any day-of-month.
      // Jan 20 and Jul 20 are both inside a single rail span.
      final DateTime jan20 = DateTime(2026, 1, 20);
      final DateTime jul20 = DateTime(2026, 7, 20);
      expect(jan20.day, jul20.day, reason: 'precondition: same day-of-month');

      expect(
        dayChipKey(jan20),
        isNot(dayChipKey(jul20)),
        reason:
            'A day-of-month key collides ~12 times across the rail span and '
            'find.byKey silently resolves to whichever month is built first — '
            'this is the bug that made a day-selection test assert against '
            '2026-01-20 while believing it had tapped 2026-07-20.',
      );
      expect(dayDotKey(jan20), isNot(dayDotKey(jul20)));
    });

    testWidgets('a rendered cell is addressable by its full-date key', (
      tester,
    ) async {
      // Ties the literal above to what the widget actually emits, so the pair
      // cannot drift apart: the string contract AND the rail's use of it are
      // both pinned.
      final DateTime today = DateTime(2026, 7, 20);
      await tester.pumpApp(_rail(firstDay: today, today: today, weekCount: 1));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('master-bookings-day-chip-2026-07-20')),
        findsOne,
      );
    });
  });

  // -------------------------------------------------------------------------
  // Rendering
  // -------------------------------------------------------------------------

  group('rendering', () {
    testWidgets('is lazily built — a PageView.builder, never eager children', (
      tester,
    ) async {
      final DateTime today = DateTime(2026, 7, 18);
      await tester.pumpApp(
        _rail(
          firstDay: railDayAt(today, -7 * 260),
          today: today,
          weekCount: 521,
          initialPage: 260,
        ),
      );
      await tester.pumpAndSettle();

      final PageView pager = tester.widget<PageView>(
        find.byKey(const Key('master-bookings-day-rail')),
      );
      expect(
        pager.childrenDelegate,
        isA<SliverChildBuilderDelegate>(),
        reason:
            '521 eagerly-built week pages (3647 chips) is exactly the jank '
            'this rail avoids — the span is deliberately years wide now (see '
            'kBookingsDayRailWeekSpan), which is only affordable BECAUSE the '
            'pager builds one page at a time.',
      );
      // A handful of pages at most — the visible one plus whatever the
      // viewport's cache extent reaches — never 521.
      expect(
        tester.widgetList(find.byType(GestureDetector)).length,
        lessThan(kRailWeekLength * 4),
      );
    });

    testWidgets('a dot marks exactly the booked days', (tester) async {
      // A Saturday, so its Mon→Sun week spans Jul 13–19 and the assertions
      // below sit either side of the booked day INSIDE one page.
      final DateTime today = DateTime(2026, 7, 18);
      await tester.pumpApp(
        _rail(
          firstDay: today,
          today: today,
          weekCount: 1,
          bookedDays: <DateTime>{railDayAt(today, 1)},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(dayDotKey(DateTime(2026, 7, 19))), findsOne);
      expect(find.byKey(dayDotKey(DateTime(2026, 7, 18))), findsNothing);
      expect(find.byKey(dayDotKey(DateTime(2026, 7, 17))), findsNothing);
    });

    // ── The two rendered DST guards ────────────────────────────────────────
    //
    // These MUST straddle the transition INSTANT, not merely name a date near
    // it — and getting that wrong is exactly how they were first written.
    //
    // ⚠ RE-DERIVED for the week pager (this session). Read this before
    // touching either test: the previous derivation is now INERT, and it is
    // inert for a structural reason, not a fixable one.
    //
    // Europe/Kyiv springs forward at 03:00 on SUNDAY 2026-03-29 and back at
    // 04:00 on SUNDAY 2026-10-25. Both transition instants therefore fall on
    // the LAST day of a Mon→Sun week. The old rail derived every cell as
    // `railDayAt(firstDay, dayIndex)` over a continuous 361-day span, so a
    // cell offset could freely straddle a transition; the pager derives the
    // seven cells of a page as `railDayAt(weekStart, 0..6)` from that page's
    // OWN Monday — and Monday + 6 days lands on Sunday 00:00, which is still
    // BEFORE 03:00/04:00. Within one page, the mutation and the correct
    // arithmetic agree exactly. A guard written the old way would pass on a
    // fully-broken rail.
    //
    // What still crosses — and is now the whole of the rendered risk — is the
    // PAGE stride: `railDayAt(firstWeekStart, weekIndex * 7)`. So both guards
    // below render page 1 of a two-page rail whose page 0 sits on the near
    // side of the transition, and put the booked day on that second page's
    // Monday:
    //
    //   spring: firstWeekStart = Mon 2026-03-23 (+02). Correct → page 1 starts
    //           Mon 2026-03-30 00:00 (+03). Mutant (`add(Duration(days: 7))`)
    //           → Mar 23 00:00+02 + 168h = Mar 30 01:00+03. Same CALENDAR day,
    //           so `dayDotKey`/`toApiDate` are identical between the two —
    //           only `bookedDays.contains(d)` can tell them apart, because
    //           `Set<DateTime>` membership is exact-instant equality and
    //           01:00 != 00:00. The dot vanishes. That IS the production
    //           failure, rendered.
    //   autumn: firstWeekStart = Mon 2026-10-19 (+03). Correct → Mon
    //           2026-10-26 00:00 (+02). Mutant → 168h later is 2026-10-25
    //           23:00, a different calendar day entirely — the dot vanishes
    //           for an even louder reason.
    //
    // CONSEQUENCE, unchanged from the previous revision: a future refactor of
    // the rail toward comparing days by KEY or by `toApiDate` string (a
    // natural-looking simplification) would make the SPRING case pass under
    // the mutation while the bug is fully present. If that comparison ever
    // changes, these guards must be re-derived again — do not assume they
    // still bite.
    //
    // Both are host-zone dependent BY NATURE, and that is a fact about the
    // production code, not a weakness of the tests: `railDayAt` is built on
    // bare `DateTime`, whose DST behaviour comes from the process zone and
    // nowhere else. On a UTC host `add(Duration(days:))` and calendar
    // arithmetic are genuinely equivalent — the bug does not exist there, so
    // no test can detect it there. See `_dstSuffix` for how CI covers it.
    // `railDayAt`'s midnight-invariant unit group above is the
    // host-independent half of the contract and stays valid either way.

    final bool springObserved = _hostObservesTransition(
      DateTime(2026, 3, 23),
      DateTime(2026, 3, 30),
    );
    final bool autumnObserved = _hostObservesTransition(
      DateTime(2026, 10, 19),
      DateTime(2026, 10, 26),
    );

    testWidgets(
      'a dot SURVIVES a PAGE STRIDE crossing the spring DST transition — the '
      'regression this rail was built to prevent${_dstSuffix(springObserved)}',
      (tester) async {
        final DateTime firstDay = DateTime(2026, 3, 23); // a Monday, pre-switch
        final DateTime booked = DateTime(2026, 3, 30); // page 1's own Monday

        await tester.pumpApp(
          _rail(
            firstDay: firstDay,
            today: firstDay,
            weekCount: 2,
            initialPage: 1,
            bookedDays: <DateTime>{booked},
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(dayDotKey(booked)),
          findsOne,
          reason:
              'The dot vanished across the spring-forward transition — the '
              'rail is deriving page start dates with Duration arithmetic '
              'again.',
        );
      },
      skip: !springObserved,
    );

    testWidgets('a dot SURVIVES a PAGE STRIDE crossing the autumn DST '
        'transition${_dstSuffix(autumnObserved)}', (tester) async {
      final DateTime firstDay = DateTime(2026, 10, 19); // a Monday, pre-switch
      final DateTime booked = DateTime(2026, 10, 26); // page 1's own Monday

      await tester.pumpApp(
        _rail(
          firstDay: firstDay,
          today: firstDay,
          weekCount: 2,
          initialPage: 1,
          bookedDays: <DateTime>{booked},
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(dayDotKey(booked)),
        findsOne,
        reason: 'The dot vanished across the fall-back transition.',
      );
    }, skip: !autumnObserved);

    testWidgets(
      'a page is exactly one Mon→Sun week — 7 chips, Monday leftmost, '
      'Sunday rightmost, and no lead item of any kind',
      (tester) async {
        // A SATURDAY, deliberately: the page must render its week's Monday
        // first regardless of which weekday the caller named. Under the
        // retired continuous strip this same call rendered Sat, Sun, Mon…
        // — a mid-week resting span, which is exactly the locked requirement
        // this test now pins against ("it should always starts from Monday").
        final DateTime today = DateTime(2026, 7, 18);
        await tester.pumpApp(
          _rail(firstDay: today, today: today, weekCount: 1),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('master-bookings-all-chip')),
          findsNothing,
          reason: '«Всі» must not render anywhere in the rail post-7.11.',
        );

        final DateTime monday = DateTime(2026, 7, 13);
        final DateTime sunday = DateTime(2026, 7, 19);
        expect(monday.weekday, DateTime.monday, reason: 'fixture precondition');
        expect(sunday.weekday, DateTime.sunday, reason: 'fixture precondition');

        // All seven, and ONLY seven.
        for (int i = 0; i < 7; i++) {
          expect(find.byKey(dayChipKey(railDayAt(monday, i))), findsOne);
        }
        expect(
          find.byKey(dayChipKey(railDayAt(monday, -1))),
          findsNothing,
          reason: 'the Sunday BEFORE this week must not be on the page',
        );
        expect(
          find.byKey(dayChipKey(railDayAt(sunday, 1))),
          findsNothing,
          reason: 'the Monday AFTER this week must not be on the page',
        );

        // …and in the right ORDER, measured, not assumed: Monday is the
        // leftmost slot and Sunday the rightmost.
        final double mondayX = tester
            .getCenter(find.byKey(dayChipKey(monday)))
            .dx;
        final double sundayX = tester
            .getCenter(find.byKey(dayChipKey(sunday)))
            .dx;
        for (int i = 0; i < 7; i++) {
          final double x = tester
              .getCenter(find.byKey(dayChipKey(railDayAt(monday, i))))
              .dx;
          expect(x, greaterThanOrEqualTo(mondayX));
          expect(x, lessThanOrEqualTo(sundayX));
        }
        expect(
          sundayX,
          greaterThan(mondayX),
          reason:
              'fixture guard: the week rendered right-to-left (or collapsed '
              'to one slot), so the ordering assertions above are vacuous',
        );
      },
    );

    testWidgets(
      'paging moves a WHOLE week — the rail never rests on a mid-week span',
      (tester) async {
        // THE headline contract of this rework, and the one thing a
        // continuous strip could not give: after a horizontal fling the rail
        // must sit on the NEXT Mon→Sun page, not 3.4 chips further along.
        final DateTime today = DateTime(2026, 7, 15); // a Wednesday
        await tester.pumpApp(
          _rail(firstDay: today, today: today, weekCount: 2),
        );
        await tester.pumpAndSettle();

        // `_rail` starts page 0 on `firstDay`'s own Monday, so page 0 IS the
        // week of `today` and page 1 is the one after it.
        final DateTime thisMonday = DateTime(2026, 7, 13);
        expect(find.byKey(dayChipKey(thisMonday)), findsOne);

        await tester.fling(
          find.byKey(const Key('master-bookings-day-rail')),
          const Offset(-300, 0),
          800,
        );
        await tester.pumpAndSettle();

        final DateTime nextMonday = railDayAt(thisMonday, 7);
        expect(
          find.byKey(dayChipKey(nextMonday)),
          findsOne,
          reason: 'the fling did not land on the following week at all',
        );
        // The settled page is a WHOLE week: its Monday sits at the same
        // leading inset the previous page's Monday did, to the pixel. A
        // continuous strip resting mid-week would put some Wednesday there
        // instead.
        final Rect railRect = tester.getRect(
          find.byKey(const Key('master-bookings-day-rail')),
        );
        expect(
          tester.getRect(find.byKey(dayChipKey(nextMonday))).left,
          closeTo(railRect.left + VelvetSpacing.lg, 1.0),
          reason:
              'the rail came to rest between two weeks — the first visible '
              'chip is not the new week\'s Monday, flush at the rail\'s own '
              'leading inset',
        );
        expect(
          find.byKey(dayChipKey(railDayAt(nextMonday, 6))).evaluate().length,
          1,
          reason: 'the settled page must still end on a Sunday',
        );
      },
    );

    // Phase 7.16 — the calendar escape hatch is RETIRED outright (not merely
    // un-pinned): day selection is by scrolling the rail alone, with the
    // month switcher's prev/next and «Сьогодні» covering the long-distance
    // jumps the button used to exist for. `_CalendarButton` no longer exists
    // as a class in `bookings_day_rail.dart` — this pins that its key cannot
    // be found anywhere in the rendered rail, at any dayCount.
    //
    // MUTATION-VERIFIED (2026-07-20): re-added a `_CalendarButton`-shaped
    // `GestureDetector(key: Key('master-bookings-calendar-button'))` as a
    // sibling ahead of the `ListView` in `BookingsDayRail.build` → this test
    // failed (`findsOne`, not `findsNothing`). Reverted and confirmed GREEN
    // again. See the handoff report for the actual command output.
    testWidgets(
      'the calendar button is gone from the rail — no escape hatch survives',
      (tester) async {
        final DateTime today = DateTime(2026, 7, 18);
        await tester.pumpApp(
          _rail(firstDay: today, today: today, weekCount: 53, initialPage: 26),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('master-bookings-calendar-button')),
          findsNothing,
        );
      },
    );

    // Phase 7.16 — with the calendar button (and the leading inset it used to
    // carry on its own `Padding`) gone, the strip must carry a SYMMETRIC
    // horizontal inset so the first chip does not sit flush against the
    // screen edge. Measures the real rendered geometry, not the private
    // padding constant — see the 78->70dp group's header for why that
    // discipline matters here.
    //
    // Since the week-pager rework that inset carries a SECOND meaning worth
    // keeping green: it is `VelvetSpacing.lg`, the exact figure
    // `MonthCalendar` self-pads by, so the collapsed rail's seven chips land
    // on the same seven columns as the expanded grid's seven day columns.
    testWidgets(
      'the week\'s Monday sits VelvetSpacing.lg inset from the rail\'s '
      'leading edge — shared with MonthCalendar\'s own column grid',
      (tester) async {
        final DateTime today = DateTime(2026, 7, 18);
        await tester.pumpApp(
          _rail(firstDay: today, today: today, weekCount: 1),
        );
        await tester.pumpAndSettle();

        final Rect railRect = tester.getRect(
          find.byKey(const Key('master-bookings-day-rail')),
        );
        final Rect firstChipRect = tester.getRect(
          find.byKey(dayChipKey(mondayOf(today))),
        );

        expect(
          firstChipRect.left,
          closeTo(railRect.left + VelvetSpacing.lg, 1.0),
          reason:
              'the week\'s Monday must sit VelvetSpacing.lg from the rail\'s '
              'own leading edge — a flush-left first chip means the inset is '
              'gone and the rail no longer shares MonthCalendar\'s columns.',
        );
      },
    );

    testWidgets(
      'a day is always selected — even a day with no bookings on it, and '
      'even when its week is the ONLY page rendered',
      (tester) async {
        final DateTime today = DateTime(2026, 7, 18);
        // No entry for `today` in bookedDays — this pins that selection does
        // NOT depend on the day carrying a dot.
        await tester.pumpApp(
          _rail(
            firstDay: today,
            today: today,
            weekCount: 1,
            selectedDay: today,
            bookedDays: const <DateTime>{},
          ),
        );
        await tester.pumpAndSettle();

        final SemanticsHandle handle = tester.ensureSemantics();
        expect(
          tester
              .getSemantics(find.byKey(dayChipKey(today)))
              .flagsCollection
              .isSelected
              .toBoolOrNull(),
          isTrue,
          reason:
              'today must render selected even though it has no bookings — '
              'there is no null-day state to fall back to post-7.11.',
        );
        expect(
          find.byKey(dayDotKey(today)),
          findsNothing,
          reason: 'precondition: today genuinely carries no booking dot',
        );
        handle.dispose();
      },
    );

    testWidgets('tapping a day reports that exact date', (tester) async {
      final DateTime today = DateTime(2026, 7, 18);
      DateTime? tapped;
      await tester.pumpApp(
        _rail(
          firstDay: today,
          today: today,
          weekCount: 1,
          onSelectDay: (DateTime d) => tapped = d,
        ),
      );
      await tester.pumpAndSettle();

      // A day inside the SAME Mon→Sun page (Jul 13–19) — a pager only ever
      // renders one week, so a target outside it is not on screen to tap.
      await tester.tap(find.byKey(dayChipKey(DateTime(2026, 7, 17))));
      await tester.pumpAndSettle();

      expect(tapped, DateTime(2026, 7, 17));
      expect(tapped!.hour, 0, reason: 'the reported day must be date-only');
    });

    testWidgets('renders localized weekday abbreviations, never raw literals', (
      tester,
    ) async {
      // 2026-07-20 is a Monday.
      final DateTime monday = DateTime(2026, 7, 20);
      await tester.pumpApp(
        _rail(firstDay: monday, today: monday, weekCount: 1),
      );
      await tester.pumpAndSettle();

      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(BookingsDayRail)),
      );
      // A page is a full week, so every abbreviation renders exactly once.
      expect(find.text(l10n.weekdayShortMon), findsOne);
      expect(find.text(l10n.weekdayShortTue), findsOne);
      expect(find.text(l10n.weekdayShortSun), findsOne);
    });
  });

  // -------------------------------------------------------------------------
  // Seven chips on a narrow phone at the largest accessibility text scale
  // -------------------------------------------------------------------------
  //
  // The pager put SEVEN chips on screen at once where the continuous strip
  // showed ~5, and made their width derived rather than fixed: at the 320dp
  // floor a slot is `(320 - 2 * VelvetSpacing.lg) / 7` = 38.9dp, against a
  // chip column laid out at 44dp and (at textScale 2.0) roughly 89dp tall
  // inside a 70dp strip. Both dimensions overflow without the
  // `BoxFit.scaleDown` fit in `_DayChip` — see its class doc.
  //
  // These carry NO manual overflow assertion: `pumpApp` arms
  // `installOverflowGuard`, which fails the test at tearDown on any
  // `RenderFlex overflowed`. Reaching the assertions below without the guard
  // firing IS the proof.
  //
  // The tap case is not incidental. The fit introduces a `FittedBox` — i.e. a
  // transform — into the chip subtree, and mobile-backlog's
  // `project_animatedscale_root_breaks_tap_by_key` records a transform at a
  // keyed widget's root silently dropping it out of the hit-test path, a
  // failure that only goes hard-red at the integration tier. `_DayChip` keeps
  // the keyed `GestureDetector` OUTSIDE the fit specifically to avoid that;
  // this pins it, at the scale where the fit is actually engaged.
  group('seven chips fit a narrow phone at every text scale', () {
    for (final double scale in <double>[1.0, 1.3, 2.0]) {
      testWidgets('a full week renders at 320dp x$scale without overflow', (
        tester,
      ) async {
        final DateTime today = DateTime(2026, 7, 15); // a Wednesday
        await tester.pumpApp(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _rail(
                firstDay: today,
                today: today,
                weekCount: 1,
                bookedDays: <DateTime>{today},
              ),
            ],
          ),
          width: 320,
          textScaleFactor: scale,
        );
        await tester.pumpAndSettle();

        final DateTime monday = mondayOf(today);
        for (int i = 0; i < 7; i++) {
          expect(find.byKey(dayChipKey(railDayAt(monday, i))), findsOne);
        }
        // The strip's own height is unmoved by the text scale — the chip
        // scales into it rather than pushing it out.
        expect(
          tester
              .getSize(find.byKey(const Key('master-bookings-day-rail')))
              .height,
          70.0,
        );
      });
    }

    testWidgets(
      'a chip is still tappable by key at 320dp x2.0 — the fit must not '
      'drop the keyed GestureDetector out of the hit-test path',
      (tester) async {
        final DateTime today = DateTime(2026, 7, 15);
        DateTime? tapped;
        await tester.pumpApp(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _rail(
                firstDay: today,
                today: today,
                weekCount: 1,
                onSelectDay: (DateTime d) => tapped = d,
              ),
            ],
          ),
          width: 320,
          textScaleFactor: 2.0,
        );
        await tester.pumpAndSettle();

        final DateTime target = railDayAt(mondayOf(today), 4); // the Friday
        // NO `warnIfMissed: false` — a miss here is the bug, not noise.
        await tester.tap(find.byKey(dayChipKey(target)));
        await tester.pumpAndSettle();

        expect(
          tapped,
          target,
          reason:
              'the tap did not reach the chip at 320dp x2.0 — the scale-down '
              'fit has been moved above the keyed GestureDetector',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // Past-day muting — days strictly before today recede visually
  // -------------------------------------------------------------------------
  //
  // Precedence pinned here, matching `_DayChip`'s doc:
  //   * a PAST, UNSELECTED day mutes to `BrandColors.weekendMuted` — not
  //     `BrandColors.muted` (2.69:1 on `BrandColors.base`, sub-AA): every
  //     day chip stays tappable (mobile-security, calendar-consolidation
  //     audit), so the muted state is ACTIVE text and must clear WCAG AA on
  //     its own; `weekendMuted` (5.07:1) does. A near-neutral warm gray,
  //     never a cold blue-gray.
  //   * TODAY never mutes, selected or not — it is never "past" by
  //     construction.
  //   * a SELECTED past day (the master browsing history) still reads as
  //     selected (full accent), NOT muted — selection outranks pastness.
  //   * the has-bookings dot stays full accent on a past day regardless of
  //     selection — muting it would fight the rail's "where is the work"
  //     scannability. Pinned as a DELIBERATE choice, not an oversight.
  //
  // FIXTURE NOTE (week-pager rework): "today" here is a THURSDAY
  // (2026-07-23), not the Monday it used to be, and every page pumps
  // `weekCount: 1`. A pager renders exactly one Mon→Sun week, so the past
  // day, today, and the day after today all have to live INSIDE that one
  // week for these colour assertions to have anything to address —
  // mid-week is the only anchor where all three do.
  group('past-day muting', () {
    /// The day-number `Text`'s resolved colour for the cell keyed to [day] —
    /// the second `Text` in the chip's column (weekday caption, then day
    /// number; see the geometry group below for the same structural
    /// addressing).
    Color dayNumberColor(WidgetTester tester, DateTime day) {
      final Text text = tester.widget<Text>(
        find
            .descendant(
              of: find.byKey(dayChipKey(day)),
              matching: find.byType(Text),
            )
            .at(1),
      );
      return text.style!.color!;
    }

    testWidgets('a past, unselected day mutes its day number to '
        'BrandColors.weekendMuted', (tester) async {
      final DateTime today = DateTime(2026, 7, 23);
      final DateTime past = railDayAt(today, -3);
      await tester.pumpApp(
        _rail(firstDay: today, today: today, weekCount: 1, selectedDay: today),
      );
      await tester.pumpAndSettle();

      // The day-number Text is the second of the chip's two Texts.
      final Finder chipTexts = find.descendant(
        of: find.byKey(dayChipKey(past)),
        matching: find.byType(Text),
      );
      final Text dayNumberText = tester.widget<Text>(chipTexts.at(1));
      expect(
        dayNumberText.style!.color,
        BrandColors.weekendMuted,
        reason:
            'a past unselected day must render its number in '
            'BrandColors.weekendMuted — WCAG AA-legal (5.07:1) and a '
            'near-neutral warm gray; BrandColors.muted '
            '(2.69:1) fails AA and every day chip stays tappable, so the '
            'inactive-component exemption never covers it.',
      );

      final Text weekdayText = tester.widget<Text>(chipTexts.at(0));
      expect(
        weekdayText.style!.color,
        BrandColors.weekendMuted,
        reason: 'the weekday caption mutes alongside the day number.',
      );
    });

    testWidgets(
      'today is NEVER muted, even though it renders unselected here',
      (tester) async {
        final DateTime today = DateTime(2026, 7, 23);
        await tester.pumpApp(
          _rail(
            firstDay: today,
            today: today,
            weekCount: 1,
            // A day other than today is selected, so today itself renders
            // UNSELECTED — the only state in which muting could plausibly
            // (and wrongly) apply to it.
            selectedDay: railDayAt(today, 1),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          dayNumberColor(tester, today),
          isNot(BrandColors.weekendMuted),
          reason:
              'today must never render muted — being in the past never '
              'applies to today.',
        );
        expect(dayNumberColor(tester, today), BrandColors.text);
      },
    );

    testWidgets(
      'a SELECTED past day reads as selected (full accent), not muted — '
      'selection outranks pastness',
      (tester) async {
        final DateTime today = DateTime(2026, 7, 23);
        final DateTime past = railDayAt(today, -3);
        await tester.pumpApp(
          _rail(firstDay: today, today: today, weekCount: 1, selectedDay: past),
        );
        await tester.pumpAndSettle();

        expect(
          dayNumberColor(tester, past),
          BrandColors.accent,
          reason:
              'a selected past day must still read as selected — otherwise '
              'the master browsing history cannot see what is currently '
              'open.',
        );
        expect(dayNumberColor(tester, past), isNot(BrandColors.weekendMuted));
      },
    );

    testWidgets(
      'the has-bookings dot stays full accent on a past day — history '
      'remains scannable by design',
      (tester) async {
        final DateTime today = DateTime(2026, 7, 23);
        final DateTime past = railDayAt(today, -3);
        await tester.pumpApp(
          _rail(
            firstDay: today,
            today: today,
            weekCount: 1,
            selectedDay: today,
            bookedDays: <DateTime>{past},
          ),
        );
        await tester.pumpAndSettle();

        final Container dot = tester.widget<Container>(
          find.byKey(dayDotKey(past)),
        );
        final BoxDecoration decoration = dot.decoration! as BoxDecoration;
        expect(
          decoration.color,
          BrandColors.accent,
          reason:
              'the booking dot must stay full accent on a past day — muting '
              'it would defeat the rail\'s scannability for where the work '
              'is, including in history.',
        );
      },
    );
  });

  // mobile-qa (calendar-consolidation cross-surface parity audit) —
  // `_DayChip`'s dot stays a separate, horizontal-chip widget (never rebuilt
  // from `CalendarDayCell`, see `calendar_grid.dart`'s file header) but is
  // documented to share `kCalendarDotColor` — the SAME constant the grid
  // surfaces' density dots use — so this rail's dot cannot silently drift
  // from theirs even though the widget itself does not. The pre-existing
  // "stays full accent" test above (asserting `BrandColors.accent`) proves
  // the RENDERED value but not the SOURCE: `kCalendarDotColor` is currently
  // DEFINED as `BrandColors.accent`, so that assertion would keep passing
  // even if a future edit hardcoded `BrandColors.accent` directly instead of
  // reading the shared constant — exactly the drift the consolidation exists
  // to prevent. Asserting against the imported `kCalendarDotColor` symbol
  // itself (not a copy of its current value) is what actually pins "this
  // rail reads the shared token", per the task's cross-surface parity
  // requirement.
  group('cross-surface parity — the has-bookings dot reads calendar_grid.dart'
      "'s kCalendarDotColor, not an independently-declared value", () {
    testWidgets('a booked day\'s dot color equals the imported '
        'kCalendarDotColor constant', (tester) async {
      final DateTime today = DateTime(2026, 7, 23);
      await tester.pumpApp(
        _rail(
          firstDay: today,
          today: today,
          weekCount: 1,
          selectedDay: today,
          bookedDays: <DateTime>{today},
        ),
      );
      await tester.pumpAndSettle();

      final Container dot = tester.widget<Container>(
        find.byKey(dayDotKey(today)),
      );
      final BoxDecoration decoration = dot.decoration! as BoxDecoration;
      expect(
        decoration.color,
        kCalendarDotColor,
        reason:
            'the rail dot must render exactly calendar_grid.dart\'s '
            'kCalendarDotColor — the single constant every calendar surface '
            '(grid density dots included) reads, per mobile-backlog D5',
      );
    });
  });

  // -------------------------------------------------------------------------
  // Chip geometry — the 78->70dp height / 10->16dp caption-gap parity fix
  // -------------------------------------------------------------------------
  //
  // mobile-qa (2026-07-20): neither value had a direct pixel pin before this
  // group. Every `pumpApp` call in this file already arms
  // `installOverflowGuard` (see `pump_app.dart`), so a regression that made
  // the chip's real content TALLER than its box already failed here via a
  // RenderFlex overflow — but that only protects against the box being too
  // SMALL. A silent drift back toward the old, less-correct 78dp/10dp pair
  // does not overflow anything, so nothing failed. These tests close that
  // gap by measuring the REAL rendered tree (`tester.getSize`/`getRect`),
  // never the private `_railHeight`/`_dayChipCaptionGap` constants — reading
  // the constants back would pass vacuously if the widget ever stopped
  // consuming them consistently.
  //
  // The two numbers are not independent. `_railHeight`'s 70dp -- and the
  // 78dp it replaced -- exist to absorb `VelvetText`'s line-height
  // multipliers on top of `railDayNumber`'s deliberately small 12.6sp
  // (commit 4f2b811). Pinning the height alone, without also proving the
  // chip's actual content still fits inside it at that font size, would
  // leave exactly the regression 78dp was raised to cover unguarded: shrink
  // the height (or grow the gap) without checking the sum against the real
  // font metrics, and the column overflows again. Both halves are proven
  // together below -- the second test completing (its geometry assertions
  // running, then a clean `tearDown`) IS the "still fits, no overflow" proof
  // for the 70dp/16dp pairing.
  group('chip geometry -- 78->70dp / 10->16dp design-parity pin', () {
    testWidgets(
      'the rail renders at the design\'s 70dp height, not the earlier 78dp',
      (tester) async {
        final DateTime today = DateTime(2026, 7, 18);
        // Wrapped in a bare `Column`, matching how `BookingsDiscoveryView`
        // actually places the rail — a plain (non-`Expanded`) child among
        // its other sections. A `Column` hands a non-flex child LOOSE
        // constraints, so the rail's own `SizedBox(height: _railHeight)`
        // resolves to its real 70dp. Pumping the rail bare as `pumpApp`'s
        // `home:` would instead hand it the TIGHT full-test-window height
        // (600dp) straight from the root — that measures the test surface,
        // not the widget, and was this test's own first failed draft.
        await tester.pumpApp(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _rail(firstDay: today, today: today, weekCount: 1),
            ],
          ),
        );
        await tester.pumpAndSettle();

        final double height = tester
            .getSize(find.byKey(const Key('master-bookings-day-rail')))
            .height;
        expect(
          height,
          70.0,
          reason:
              'the rail strip must render at the design\'s own 70dp -- the '
              'earlier 78dp bump existed only to cover a since-fixed '
              'VelvetText line-height overflow and must not silently come '
              'back',
        );
      },
    );

    testWidgets(
      'the weekday caption sits 16dp above the day number, and the chip '
      'fits inside the 70dp box with no overflow',
      (tester) async {
        final DateTime today = DateTime(2026, 7, 18);
        // Same `Column`-wrapped ambient constraints as the height test above
        // — see its comment for why the bare `pumpApp` home would otherwise
        // stretch the rail to the full test-window height instead of its
        // real 70dp, which would make the overflow-fit proof this test also
        // performs meaningless (a 600dp box can absorb any gap).
        await tester.pumpApp(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _rail(firstDay: today, today: today, weekCount: 1),
            ],
          ),
        );
        await tester.pumpAndSettle();

        // Two `Text` widgets inside one chip's Column, in top-to-bottom
        // render order -- weekday caption first, day number second. Located
        // structurally (never by locale text), so this stays valid under any
        // locale.
        final Finder chipTexts = find.descendant(
          of: find.byKey(dayChipKey(today)),
          matching: find.byType(Text),
        );
        expect(
          chipTexts,
          findsNWidgets(2),
          reason:
              'precondition: exactly the weekday caption + the day number -- '
              'a third Text here would mean the chip changed shape and the '
              'geometry below would no longer measure what it claims to',
        );

        final Rect weekdayRect = tester.getRect(chipTexts.at(0));
        final Rect dayNumberRect = tester.getRect(chipTexts.at(1));
        final double gap = dayNumberRect.top - weekdayRect.bottom;

        expect(
          gap,
          closeTo(16, 0.5),
          reason:
              'the weekday-to-day-number gap must render at the design\'s '
              '16dp -- the earlier 10dp bump existed only alongside the old '
              '78dp height and must not silently come back on its own',
        );

        // No explicit overflow assertion needed here: `pumpApp` above already
        // armed `installOverflowGuard`, which fails this test at `tearDown`
        // if the chip Column's REAL content (weekday text + this 16dp gap +
        // the day-number text at its real 12.6sp metrics + the 4dp dot gap +
        // the dot) exceeded the rail's real 70dp height. This test running to
        // completion -- including the geometry assertions above, which
        // execute before tearDown -- is the "still fits, no overflow" half
        // of the pairing this group's header calls out as the actual risk.
      },
    );
  });

  // -------------------------------------------------------------------------
  // Haptic cue contract + drag-tracking state (mobile-qa, 2026-08-14)
  // -------------------------------------------------------------------------
  //
  // `_BookingsDayRailState._onRailScroll` fires `HapticFeedback.selectionClick()`
  // exactly once per COMMITTED week turn — gated on `_draggedSinceLastSettle`
  // (set only by a real finger drag's `ScrollUpdateNotification.dragDetails`,
  // never by a programmatic page move) and diffed against `_lastSettledPage`
  // (the last genuine settle, not a Start-time snapshot — see the class doc
  // for why a snapshot goes stale across an interrupted ballistic). This
  // group pins the whole contract, mocking `HapticFeedback` at the
  // `flutter/platform` channel boundary — same technique
  // `booking_detail_interactions_test.dart` uses for its `add_2_calendar`
  // channel mock.
  //
  // ⚠ FIXED PRODUCTION DEFECT, found while writing this group (mobile-qa,
  // 2026-08-14) and fixed by mobile-dev the same day. `_lastSettledPage`
  // used to start `null`, so `endRounded != _lastSettledPage` was trivially
  // true on the FIRST End this widget ever saw, whether or not anything
  // actually moved. If the VERY FIRST scroll interaction on a
  // freshly-mounted rail was a spring-back, this fired a haptic for a
  // gesture that went nowhere. Confirmed empirically (not merely reasoned):
  // a fresh mount + a single under-threshold paused-release drag used to
  // fire exactly 1 call to `HapticFeedback.vibrate`.
  //
  // Fix: `_lastSettledPage` is now non-nullable and seeded in `initState`
  // from `widget.controller.initialPage` (kept in sync in `didUpdateWidget`
  // if the controller identity changes) — the page the rail actually starts
  // on, not an artificial "nothing happened yet" sentinel. This is why most
  // tests below establish a real settle FIRST regardless: it is also the
  // realistic production case (the rail always renders with a landing
  // selection already resolved before the master's first touch), and it
  // keeps those tests valid independent of how the baseline seeds. The two
  // tests that specifically exercise FIRST-INTERACTION-ON-FRESH-MOUNT
  // behaviour (spring-back and genuine turn) are called out below.
  group('haptic cue contract', () {
    late List<MethodCall> platformCalls;

    setUp(() {
      platformCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (
            MethodCall call,
          ) async {
            platformCalls.add(call);
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    int selectionClicks() => platformCalls
        .where(
          (MethodCall c) =>
              c.method == 'HapticFeedback.vibrate' &&
              c.arguments == 'HapticFeedbackType.selectionClick',
        )
        .length;

    const Key railKey = Key('master-bookings-day-rail');

    /// A FORWARD paused-before-lift drag of [fraction] of [finder]'s own
    /// width — the exact technique
    /// `bookings_pager_commit_threshold_test.dart`'s `_pausedForwardDrag`
    /// establishes (8 real 40ms-spaced samples, then a pump PAST
    /// `VelocityTracker`'s own 40ms "assume stopped" cutoff with no further
    /// sample before `up()`), not re-derived here: see that file's header
    /// for why a trailing run of zero-delta samples produces a
    /// SIGN-REVERSED velocity instead of an exact zero and must not be
    /// substituted for it.
    Future<void> pausedForwardDrag(
      WidgetTester tester,
      Finder finder, {
      required double fraction,
    }) async {
      final double width = tester.getRect(finder).width;
      const int steps = 8;
      final double dx = -(width * fraction) / steps;
      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(finder),
      );
      Duration stamp = Duration.zero;
      for (int i = 0; i < steps; i++) {
        stamp += const Duration(milliseconds: 40);
        await gesture.moveBy(Offset(dx, 0), timeStamp: stamp);
        // fixed-wait-ok: advancing the pointer-sample clock in lockstep with
        // the synthetic move timestamps, not waiting on a condition.
        await tester.pump(const Duration(milliseconds: 40));
      }
      // fixed-wait-ok: advancing past VelocityTracker's own 40ms "assume
      // stopped" cutoff, not waiting on a condition — see
      // bookings_pager_commit_threshold_test.dart's `_pausedForwardDrag`.
      await tester.pump(const Duration(milliseconds: 60));
      await gesture.up();
    }

    testWidgets(
      'CASE 1 (positive control): a committed week turn fires exactly one '
      'haptic — proves the mock is wired and the cue is genuinely '
      'reachable, so the negative-only cases below mean something',
      (tester) async {
        final DateTime today = DateTime(2026, 7, 15); // a Wednesday
        await tester.pumpApp(
          _rail(firstDay: today, today: today, weekCount: 2),
        );
        await tester.pumpAndSettle();

        await tester.fling(find.byKey(railKey), const Offset(-300, 0), 800);
        await tester.pumpAndSettle();

        expect(
          selectionClicks(),
          1,
          reason:
              'a committed week turn must fire the haptic cue exactly '
              'once — 0 would mean either the cue regressed or the mock is '
              'not wired, either of which would make every negative test '
              'below pass for the wrong reason.',
        );
      },
    );

    testWidgets(
      'CASE 2: a spring-back (under-threshold paused release) fires no '
      'haptic',
      (tester) async {
        final DateTime today = DateTime(2026, 7, 15);
        await tester.pumpApp(
          _rail(firstDay: today, today: today, weekCount: 2),
        );
        await tester.pumpAndSettle();

        // Establish a REAL settle first (see the group header) — a genuine
        // committed turn, so the spring-back below is diffed against a real
        // `_lastSettledPage`, not the widget's initial `null`.
        await pausedForwardDrag(tester, find.byKey(railKey), fraction: 0.30);
        await tester.pumpAndSettle();
        final int afterCommit = selectionClicks();

        await pausedForwardDrag(tester, find.byKey(railKey), fraction: 0.20);
        await tester.pumpAndSettle();

        expect(
          selectionClicks(),
          afterCommit,
          reason:
              'a spring-back must never fire the haptic cue — got an extra '
              'call after the under-threshold release.',
        );
      },
    );

    testWidgets('CASE 3: a programmatic jumpToPage resync fires no haptic', (
      tester,
    ) async {
      final DateTime today = DateTime(2026, 7, 15);
      final PageController controller = PageController(initialPage: 0);
      await tester.pumpApp(
        BookingsDayRail(
          controller: controller,
          firstWeekStart: mondayOf(today),
          weekCount: 10,
          today: today,
          selectedDay: today,
          bookedDays: const <DateTime>{},
          onSelectDay: (_) {},
        ),
      );
      await tester.pumpAndSettle();

      // Establish a real settle first — mirrors `_showRailWeekOf` always
      // being called well after the rail's initial mount in production.
      await pausedForwardDrag(tester, find.byKey(railKey), fraction: 0.30);
      await tester.pumpAndSettle();
      final int afterCommit = selectionClicks();

      // Mirrors `_BookingsDiscoveryViewState._showRailWeekOf`'s own
      // programmatic resync — pure navigation echo, never a selection, and
      // never haptic-worthy.
      controller.jumpToPage(5);
      await tester.pumpAndSettle();

      expect(
        selectionClicks(),
        afterCommit,
        reason:
            'a programmatic jumpToPage resync must never fire the haptic '
            'cue.',
      );
    });

    testWidgets(
      'CASE 3b: a programmatic animateToPage resync fires no haptic',
      (tester) async {
        final DateTime today = DateTime(2026, 7, 15);
        final PageController controller = PageController(initialPage: 0);
        await tester.pumpApp(
          BookingsDayRail(
            controller: controller,
            firstWeekStart: mondayOf(today),
            weekCount: 10,
            today: today,
            selectedDay: today,
            bookedDays: const <DateTime>{},
            onSelectDay: (_) {},
          ),
        );
        await tester.pumpAndSettle();

        await pausedForwardDrag(tester, find.byKey(railKey), fraction: 0.30);
        await tester.pumpAndSettle();
        final int afterCommit = selectionClicks();

        // Mirrors `_showRailWeekOf`'s ANIMATED branch (an adjacent-week
        // resync, e.g. from a month step or «Сьогодні»).
        //
        // NOT awaited directly: `animateToPage`'s returned Future only
        // completes once its driven `Ticker` has actually ticked to the end
        // of the animation, and under
        // `AutomatedTestWidgetsFlutterBinding` a `Ticker` only advances
        // inside an explicit `tester.pump()` — nothing pumps between this
        // call and the next line, so awaiting it here deadlocks forever
        // (proved against a bare stock `PageView` with default
        // `PageScrollPhysics`, no `LowThresholdPageScrollPhysics` involved).
        // Starting the animation is itself synchronous (the call schedules
        // the first frame callback before returning), so firing it
        // unawaited and driving it via the `pumpAndSettle` below — which
        // pumps for exactly as long as a frame is scheduled — is both safe
        // and correct.
        unawaited(
          controller.animateToPage(
            2,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOut,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          selectionClicks(),
          afterCommit,
          reason:
              'a programmatic animateToPage resync must never fire the '
              'haptic cue.',
        );
      },
    );

    testWidgets('CASE 4: an interrupted ballistic (a new drag begun while the '
        'previous settle is still animating) fires exactly one haptic for '
        'the NET transition, not two — the mobile-perf drag-chaining fix', (
      tester,
    ) async {
      final DateTime today = DateTime(2026, 7, 15);
      await tester.pumpApp(_rail(firstDay: today, today: today, weekCount: 4));
      await tester.pumpAndSettle();

      final Finder finder = find.byKey(railKey);
      // Establish a real settle first (page 0 -> 1).
      await pausedForwardDrag(tester, finder, fraction: 0.30);
      await tester.pumpAndSettle();
      final int afterBaseline = selectionClicks();

      final double width = tester.getRect(finder).width;

      // Drag A: committed, released, but given NO settle time before Drag
      // B begins — its ballistic is still in flight when interrupted.
      final TestGesture gestureA = await tester.startGesture(
        tester.getCenter(finder),
      );
      Duration stamp = Duration.zero;
      for (int i = 0; i < 8; i++) {
        stamp += const Duration(milliseconds: 40);
        await gestureA.moveBy(Offset(-(width * 0.3) / 8, 0), timeStamp: stamp);
        // fixed-wait-ok: advancing the pointer-sample clock in lockstep with
        // the synthetic move timestamps, not waiting on a condition — see
        // `pausedForwardDrag`'s identical pattern above.
        await tester.pump(const Duration(milliseconds: 40));
      }
      // fixed-wait-ok: advancing past VelocityTracker's own 40ms "assume
      // stopped" cutoff, not waiting on a condition — see
      // `pausedForwardDrag` above.
      await tester.pump(const Duration(milliseconds: 60));
      await gestureA.up();

      // Drag B interrupts immediately — no intervening settle pump.
      final TestGesture gestureB = await tester.startGesture(
        tester.getCenter(finder),
      );
      stamp = Duration.zero;
      for (int i = 0; i < 8; i++) {
        stamp += const Duration(milliseconds: 40);
        await gestureB.moveBy(Offset(-(width * 0.3) / 8, 0), timeStamp: stamp);
        // fixed-wait-ok: advancing the pointer-sample clock in lockstep with
        // the synthetic move timestamps, not waiting on a condition.
        await tester.pump(const Duration(milliseconds: 40));
      }
      // fixed-wait-ok: advancing past VelocityTracker's own 40ms "assume
      // stopped" cutoff, not waiting on a condition.
      await tester.pump(const Duration(milliseconds: 60));
      await gestureB.up();
      await tester.pumpAndSettle();

      expect(
        selectionClicks() - afterBaseline,
        1,
        reason:
            'a chained forward drag (a new drag begun while the previous '
            'ballistic is still animating) must fire the haptic cue '
            'exactly ONCE for the whole gesture, attributed to the NET '
            'page transition — not once per interruption boundary. This '
            'is the exact defect mobile-perf fixed by replacing a '
            'drag-start-page snapshot with _draggedSinceLastSettle + '
            '_lastSettledPage.',
      );
    });

    // REGRESSION PIN for the FIXED PRODUCTION DEFECT — see the group header.
    // `_lastSettledPage` is now seeded from `widget.controller.initialPage`
    // in `initState`, so the very first End this widget ever sees is diffed
    // against where the rail actually starts, not an artificial "always
    // different" `null`.
    testWidgets(
      'CASE 5 (regression pin): a spring-back as the VERY FIRST scroll '
      'interaction on a fresh mount fires no haptic',
      (tester) async {
        final DateTime today = DateTime(2026, 7, 15);
        await tester.pumpApp(
          _rail(firstDay: today, today: today, weekCount: 2),
        );
        await tester.pumpAndSettle();

        await pausedForwardDrag(tester, find.byKey(railKey), fraction: 0.20);
        await tester.pumpAndSettle();

        expect(
          selectionClicks(),
          0,
          reason:
              'the very first scroll interaction ever, a spring-back, must '
              'not fire the haptic cue — the baseline seeded from '
              '`initialPage` must equal the page a spring-back settles back '
              'onto.',
        );
      },
    );

    // The trap a naive fix ("only fire when _lastSettledPage != null") would
    // fall into: suppressing the haptic on a genuine first committed turn
    // from a fresh mount is itself a regression, just the opposite-signed
    // one from CASE 5. Pinned so a future "simplification" of the
    // `initState` seeding can't reintroduce either defect.
    testWidgets('CASE 6 (regression pin, opposite sign of CASE 5): a genuine '
        'committed turn as the VERY FIRST scroll interaction on a fresh '
        'mount fires exactly one haptic', (tester) async {
      final DateTime today = DateTime(2026, 7, 15);
      await tester.pumpApp(_rail(firstDay: today, today: today, weekCount: 2));
      await tester.pumpAndSettle();

      await pausedForwardDrag(tester, find.byKey(railKey), fraction: 0.30);
      await tester.pumpAndSettle();

      expect(
        selectionClicks(),
        1,
        reason:
            'a genuine committed turn — even as the very first interaction '
            'ever on a fresh mount — must still fire the haptic cue '
            'exactly once. A baseline that seeds from `initialPage` must '
            'not be confused with a guard that simply suppresses the cue '
            'until SOME prior settle has happened.',
      );
    });
  });
}
