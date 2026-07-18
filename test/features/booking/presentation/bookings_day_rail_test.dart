// Phase 7.6 — the «Мої записи» day rail.
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

import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_day_rail.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
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

Widget _rail({
  required DateTime firstDay,
  required DateTime today,
  DateTime? selectedDay,
  Set<DateTime> bookedDays = const <DateTime>{},
  int dayCount = 7,
  bool calendarActive = false,
  ValueChanged<DateTime>? onSelectDay,
  VoidCallback? onSelectAll,
  VoidCallback? onOpenCalendar,
}) {
  return BookingsDayRail(
    controller: ScrollController(),
    firstDay: firstDay,
    dayCount: dayCount,
    today: today,
    selectedDay: selectedDay,
    bookedDays: bookedDays,
    calendarActive: calendarActive,
    onOpenCalendar: onOpenCalendar ?? () {},
    onSelectAll: onSelectAll ?? () {},
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
      await tester.pumpApp(_rail(firstDay: today, today: today, dayCount: 2));
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
    testWidgets('is lazily built — a ListView.builder, never eager children', (
      tester,
    ) async {
      final DateTime today = DateTime(2026, 7, 18);
      await tester.pumpApp(
        _rail(firstDay: railDayAt(today, -180), today: today, dayCount: 361),
      );
      await tester.pumpAndSettle();

      final ListView list = tester.widget<ListView>(
        find.byKey(const Key('master-bookings-day-rail')),
      );
      // A `ListView.builder` has a non-null `itemExtent` + a lazily-evaluated
      // childrenDelegate; an eager `ListView(children: [...])` would report
      // its full child count up front.
      expect(list.itemExtent, kRailItemExtent);
      expect(
        list.childrenDelegate,
        isA<SliverChildBuilderDelegate>(),
        reason: '361 eagerly-built chips is exactly the jank this rail avoids.',
      );
      // Only a window of the 363 items is built.
      expect(
        tester.widgetList(find.byType(GestureDetector)).length,
        lessThan(60),
      );
    });

    testWidgets('a dot marks exactly the booked days', (tester) async {
      final DateTime today = DateTime(2026, 7, 18);
      await tester.pumpApp(
        _rail(
          firstDay: today,
          today: today,
          dayCount: 3,
          bookedDays: <DateTime>{railDayAt(today, 1)},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(dayDotKey(DateTime(2026, 7, 19))), findsOne);
      expect(find.byKey(dayDotKey(DateTime(2026, 7, 18))), findsNothing);
      expect(find.byKey(dayDotKey(DateTime(2026, 7, 20))), findsNothing);
    });

    // ── The two rendered DST guards ────────────────────────────────────────
    //
    // These MUST straddle the transition INSTANT, not merely name a date near
    // it — and getting that wrong is exactly how they were first written.
    //
    // Europe/Kyiv springs forward at 03:00 on 2026-03-29. The original tests
    // used `firstDay = 2026-03-27` and asserted the dot on 2026-03-29, an
    // offset of 2 days. Under the `add(Duration(days: 2))` mutation that is
    // Mar 27 00:00+02 plus 48 absolute hours = Mar 29 00:00+02 — still BEFORE
    // 03:00, so still local midnight, so the dot survived and the test passed
    // while the bug was fully present. The rendered guards were strictly
    // weaker than their names promised; only the `railDayAt` unit group above
    // actually held the contract.
    //
    // The booked day is therefore now placed on the far side of the
    // transition: the derivation must cross it for the skew to exist at all.
    // With the mutation, Mar 27 00:00+02 + 96h lands on Mar 31 01:00+03, which
    // is NOT the local midnight `bookedDaysProvider` puts in its `Set`, so
    // `contains()` misses and the dot disappears — which is the real-world
    // failure, rendered.
    //
    // Both are host-zone dependent BY NATURE, and that is a fact about the
    // production code, not a weakness of the tests: `railDayAt` is built on
    // bare `DateTime`, whose DST behaviour comes from the process zone and
    // nowhere else. On a UTC host `add(Duration(days:))` and calendar
    // arithmetic are genuinely equivalent — the bug does not exist there, so
    // no test can detect it there. See `_kDstSkipReason` for how CI covers it.
    //
    // ── HOW THE SPRING CASE ACTUALLY DETECTS THE MUTATION ─────────────────
    //
    // Read this before refactoring either test.
    //
    // Under the `add(Duration(days: 4))` mutation the spring cell lands on
    // 2026-03-31 01:00 — the SAME CALENDAR DAY as the correct 2026-03-31
    // 00:00. So `dayDotKey(d)`, `toApiDate(d)` and every other
    // day-granularity projection are IDENTICAL between mutant and original.
    // The dot's disappearance comes solely from `bookedDays.contains(d)`:
    // `Set<DateTime>` membership is exact-instant equality, and 01:00 != 00:00.
    //
    // CONSEQUENCE: a future refactor of the rail toward comparing days by KEY
    // or by `toApiDate` string (a natural-looking simplification) would make
    // this test pass under the mutation while the bug is fully present. The
    // autumn case is the same shape. If that comparison ever changes, these
    // guards must be re-derived — do not assume they still bite.
    // `railDayAt`'s midnight-invariant unit group above is the host-independent
    // half of the contract and stays valid either way.

    final bool springObserved = _hostObservesTransition(
      DateTime(2026, 3, 27),
      DateTime(2026, 3, 31),
    );
    final bool autumnObserved = _hostObservesTransition(
      DateTime(2026, 10, 23),
      DateTime(2026, 10, 27),
    );

    testWidgets(
      'a dot SURVIVES a span CROSSING the spring DST transition — the '
      'regression this rail was built to prevent${_dstSuffix(springObserved)}',
      (tester) async {
        final DateTime firstDay = DateTime(2026, 3, 27);
        final DateTime booked = DateTime(2026, 3, 31); // past the 03:00 switch

        await tester.pumpApp(
          _rail(
            firstDay: firstDay,
            today: firstDay,
            dayCount: 6,
            bookedDays: <DateTime>{booked},
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(dayDotKey(booked)),
          findsOne,
          reason:
              'The dot vanished across the spring-forward transition — the '
              'rail is deriving cell dates with Duration arithmetic again.',
        );
      },
      skip: !springObserved,
    );

    testWidgets('a dot SURVIVES a span CROSSING the autumn DST transition'
        '${_dstSuffix(autumnObserved)}', (tester) async {
      final DateTime firstDay = DateTime(2026, 10, 23);
      final DateTime booked = DateTime(2026, 10, 27); // past the 04:00 switch

      await tester.pumpApp(
        _rail(
          firstDay: firstDay,
          today: firstDay,
          dayCount: 6,
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

    testWidgets('the lead items are [calendar][Всі], in that order', (
      tester,
    ) async {
      final DateTime today = DateTime(2026, 7, 18);
      await tester.pumpApp(_rail(firstDay: today, today: today, dayCount: 3));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('master-bookings-calendar-button')),
        findsOne,
      );
      expect(find.byKey(const Key('master-bookings-all-chip')), findsOne);

      // The offset the screen's centring math depends on.
      expect(kRailLeadItems, 2);

      final double calendarX = tester
          .getTopLeft(find.byKey(const Key('master-bookings-calendar-button')))
          .dx;
      final double allX = tester
          .getTopLeft(find.byKey(const Key('master-bookings-all-chip')))
          .dx;
      expect(calendarX, lessThan(allX));
    });

    testWidgets(
      '«Всі» reads as selected only when no day and no range is set',
      (tester) async {
        final DateTime today = DateTime(2026, 7, 18);

        Future<bool?> allChipSelected({
          DateTime? selectedDay,
          bool calendarActive = false,
        }) async {
          await tester.pumpApp(
            _rail(
              firstDay: today,
              today: today,
              dayCount: 3,
              selectedDay: selectedDay,
              calendarActive: calendarActive,
            ),
          );
          await tester.pumpAndSettle();
          return tester
              .getSemantics(find.byKey(const Key('master-bookings-all-chip')))
              .flagsCollection
              .isSelected
              .toBoolOrNull();
        }

        final SemanticsHandle handle = tester.ensureSemantics();
        expect(await allChipSelected(), isTrue);
        expect(await allChipSelected(selectedDay: today), isFalse);
        // A range supersedes the single-day selection, so «Всі» is not selected
        // even though `selectedDay` is null.
        expect(await allChipSelected(calendarActive: true), isFalse);
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
          dayCount: 3,
          onSelectDay: (DateTime d) => tapped = d,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(dayChipKey(DateTime(2026, 7, 20))));
      await tester.pumpAndSettle();

      expect(tapped, DateTime(2026, 7, 20));
      expect(tapped!.hour, 0, reason: 'the reported day must be date-only');
    });

    testWidgets('the calendar button marks itself when a range is active', (
      tester,
    ) async {
      final DateTime today = DateTime(2026, 7, 18);
      bool opened = false;
      await tester.pumpApp(
        _rail(
          firstDay: today,
          today: today,
          dayCount: 3,
          calendarActive: true,
          onOpenCalendar: () => opened = true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('master-bookings-calendar-button')),
      );
      expect(opened, isTrue);
    });

    testWidgets('renders localized weekday abbreviations, never raw literals', (
      tester,
    ) async {
      // 2026-07-20 is a Monday.
      final DateTime monday = DateTime(2026, 7, 20);
      await tester.pumpApp(_rail(firstDay: monday, today: monday, dayCount: 2));
      await tester.pumpAndSettle();

      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(BookingsDayRail)),
      );
      expect(find.text(l10n.weekdayShortMon), findsOne);
      expect(find.text(l10n.weekdayShortTue), findsOne);
    });
  });
}
