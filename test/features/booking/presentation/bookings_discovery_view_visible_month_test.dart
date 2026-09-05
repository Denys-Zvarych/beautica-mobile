// mobile-qa (2026-08-14) — closes the mobile-build-verifier gap on the
// day-rail month-label fix: nothing constructed the real
// `BookingsDiscoveryView` and exercised the COMPOSED resync — the rail
// (`bookings_day_rail.dart`'s `onVisibleWeekChanged`), the panel
// (`bookings_month_calendar_panel.dart`'s `visibleMonth` /
// `_railInteractive` handoff) and the host
// (`bookings_discovery_view.dart`'s `_visibleMonth` field /
// `_onRailVisibleWeekChanged` / the reset inside `_applySelectedDay`) all at
// once. Each piece is unit-proven in isolation:
//   * `bookings_day_rail_test.dart` — the callback fires on settle, not
//     mid-drag, and on a programmatic `jumpToPage`.
//   * `bookings_month_calendar_panel_test.dart` /
//     `bookings_month_calendar_panel_handoff_test.dart` — the label/handoff
//     math given a synthetic `visibleMonth`.
//   * `bookings_month_calendar_panel_rail_paging_test.dart` — the PRE-feature
//     null-fallback (this widget's own `visibleMonth ?? _month`) when the
//     host does not wire either param at all — see that file's rewritten
//     rationale (mobile-qa, this session) for exactly what it does and does
//     not pin.
// None of the above constructs `BookingsDiscoveryView` itself, so a wiring
// regression at the SEAM between these three widgets — the host forgetting
// to pass `onVisibleWeekChanged`, forgetting to pass `visibleMonth`, or
// forgetting to reset `_visibleMonth` inside `_applySelectedDay` — would
// leave every one of those files green while the real screen still shows
// the bug report's exact symptom. This file drives the real widget through
// all three resync entry points a master actually has — «Сьогодні», a
// rail-chip tap, and expanding the calendar panel — and also pins the
// "paging the rail never fetches" guarantee at the host level, where the
// fetch would actually matter (a synthetic panel host has no provider to
// over-fetch from).
//
// TZ: the fixture crosses a real month boundary via the injected
// `clockProvider` (never the host wall clock — see `core/time/clock_provider
// .dart`), so it is deterministic under any host TZ; still run under
// `TZ=UTC flutter test …` per repo convention for anything date-sensitive.

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
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_day_rail.dart';
import 'package:beautica_mobile/shared/formatters/uk_calendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/clock_instant.dart';
import '../../../helpers/pump_app.dart';

class _MockBookingRepository extends Mock implements BookingRepository {}

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
}

/// Mid-July 2026, a Wednesday — the same fixture day
/// `bookings_month_calendar_panel_rail_paging_test.dart` uses, so a reader
/// who has seen that file recognises the shape immediately.
///
/// A DATE TOKEN (see `lib/shared/time/kyiv_day.dart`) — deliberately bare
/// host-local, NOT `.utc()`. This value plays TWO roles below and each needs
/// DIFFERENT treatment (verified by RUNNING both the naive fix and this one
/// through the full `TZ=Europe/Kyiv`/`TZ=UTC`/`TZ=Asia/Tokyo` matrix, not
/// just reasoned about):
///   (1) `BookingsDayQuery.of(day: _today)` below, and the
///       `expect(calls, [(_today, _today)])` assertions in the tests that
///       follow — `BookingsDayQuery.of` truncates via `dateOnly`
///       (`shared/formatters/api_date.dart`), which reads only
///       `_today.year`/`.month`/`.day` and rebuilds a fresh bare-local
///       `DateTime` from them, so the CAPTURED query argument is always
///       bare-local too. Comparing it against `_today` via `==` then only
///       agrees on EVERY host `TZ` if `_today` ALSO stays bare-local — both
///       sides then resolve through the identical constructor + identical
///       inputs, hence the identical instant, on any one given host (the
///       same coherent-pairing argument
///       `weekly_template_editor_screen_test.dart`'s `_clock` doc makes).
///       Switching `_today`'s own declaration to `.utc()` breaks this half
///       on EVERY host, Kyiv included — confirmed by running it.
///   (2) the production CLOCK (`clockProvider`, in `_pump` below) — here
///       `_today` must NOT be fed raw. [asClockInstant] wraps it into a
///       genuine INSTANT (noon UTC on this same calendar day) first, which
///       is what makes the widget's own `kyivToday(clockProvider)` resolve
///       to this SAME calendar day on every host `TZ` instead of drifting a
///       day under e.g. `TZ=Asia/Tokyo` — feeding `_today` raw here (the
///       pre-fix shape) is the actual bug this fixture exists to not
///       reintroduce (`scripts/forbid_host_local_instant_anchor.sh`'s
///       RULE 2; worked reference:
///       `test/features/schedule/presentation/weekly_template_editor_screen_test.dart`'s
///       `_pump`, which applies the identical split).
final DateTime _today = DateTime(2026, 7, 15);

const Key _railKey = Key('master-bookings-day-rail');
const Key _labelKey = Key('bookings-month-calendar-label');
const Key _toggleKey = Key('bookings-month-calendar-toggle');
const Key _todayKey = Key('master-bookings-today');

String _label(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(_labelKey)).data!;

/// Flings the rail one week further per call — mirrors
/// `bookings_month_calendar_panel_rail_paging_test.dart`'s own `flingRail`,
/// including its 220ms-debounce-clearing pump, so a real chip-tap debounce
/// timer left running by a PRIOR gesture in the same test cannot bleed into
/// the next assertion.
Future<void> _flingRail(WidgetTester tester, {int times = 1}) async {
  for (int i = 0; i < times; i++) {
    await tester.fling(find.byKey(_railKey), const Offset(-300, 0), 800);
    await tester.pumpAndSettle();
    // fixed-wait-ok: advancing past the 220ms rail-tap debounce window, so a
    // stray timer from an earlier gesture in this test cannot fire later and
    // confuse a subsequent fetch-count assertion.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  }
}

/// Pumps the real `BookingsDiscoveryView` — not a synthetic panel host — with
/// a mocked repository that RECORDS every `(from, to)` it was called with, so
/// "paging the rail never fetches" and "the query landed on the right day"
/// are both checkable at this composed level.
Future<({_MockBookingRepository repo, List<(DateTime?, DateTime?)> calls})>
_pump(WidgetTester tester, {DateTime? today}) async {
  final DateTime effectiveToday = today ?? _today;
  final repo = _MockBookingRepository();
  final calls = <(DateTime?, DateTime?)>[];
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
    calls.add((
      i.namedArguments[#from] as DateTime?,
      i.namedArguments[#to] as DateTime?,
    ));
    return const PageResponse<Booking>(
      items: <Booking>[],
      page: 0,
      totalPages: 1,
      totalElements: 0,
    );
  });

  await tester.pumpApp(
    BookingsDiscoveryView(
      query: BookingsDayQuery.of(day: effectiveToday),
      title: 'Мої записи',
      onBookingTap: (Booking _) {},
    ),
    overrides: <Object>[
      screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
      bookingRepositoryProvider.overrideWithValue(repo),
      bookedDaysProvider.overrideWith((ref) async => <DateTime>{}),
      // `asClockInstant`, not the raw date token — see `_today`'s doc for
      // why the two roles need different treatment.
      clockProvider.overrideWithValue(() => asClockInstant(effectiveToday)),
    ],
  );
  await tester.pumpAndSettle();
  return (repo: repo, calls: calls);
}

void main() {
  setUpAll(() {
    registerFallbackValue(BookingStatus.confirmed);
    registerFallbackValue(<BookingStatus>[]);
  });

  testWidgets(
    'browsing the rail into a different month, then pressing «Сьогодні», '
    'lands the label back on the CURRENT month — the exact composed '
    'regression the day-rail month-label fix closes',
    (tester) async {
      final result = await _pump(tester);
      final calls = result.calls;

      // The landing fetch — exactly one, for today.
      expect(calls, <(DateTime?, DateTime?)>[(_today, _today)]);
      calls.clear();

      final String todayLabel = _label(tester);

      // Six weeks forward from mid-July is comfortably past the July/August
      // boundary, so a label tracking the rail's viewport cannot fail to
      // change.
      await _flingRail(tester, times: 6);

      final String browsedLabel = _label(tester);
      expect(
        browsedLabel,
        isNot(todayLabel),
        reason:
            'fixture guard: six week flings did not change the label at '
            'all — either the rail did not actually move, or '
            '`onVisibleWeekChanged` is not wired end-to-end through the real '
            'host; the assertions below would prove nothing either way.',
      );

      // "Also verify": paging the rail is pure navigation — it must never
      // fetch, at the level where a fetch would actually happen.
      expect(
        calls,
        isEmpty,
        reason:
            'browsing the rail issued a fetch ($calls) — a week flick must '
            'only ever relabel, never re-query; that is the entire reason '
            '`onVisibleWeekChanged` is a SEPARATE callback from `onSelectDay`.',
      );

      // Press «Сьогодні». The day never actually changes (it was already
      // today), so this is a pure relabel-back — exactly the bug report's
      // own scenario, reproduced through the real
      // `BookingsDiscoveryView`/`BookingsMonthCalendarPanel`/`BookingsDayRail`
      // wiring rather than a synthetic panel host.
      await tester.tap(find.byKey(_todayKey));
      await tester.pumpAndSettle();

      expect(
        _label(tester),
        todayLabel,
        reason:
            'pressing «Сьогодні» after browsing away left the month label '
            'on the browsed-to month instead of the current one — this is '
            'the production defect the day-rail month-label fix exists to '
            'close.',
      );

      // The day never changed (today → today), so the value-equal
      // `BookingsDayQuery` never issues a second fetch — Riverpod's
      // keepAlive family short-circuits on the unchanged key.
      expect(
        calls,
        isEmpty,
        reason:
            'pressing «Сьогодні» while already on today re-fetched ($calls) '
            '— the query did not actually change, so this should have been '
            'a pure relabel.',
      );
    },
  );

  testWidgets(
    'browsing the rail into a different month, then TAPPING A DAY CHIP '
    'there, lands the query AND the label on the tapped day — the '
    'chip-tap resync path composed at the host level',
    (tester) async {
      final result = await _pump(tester);
      final calls = result.calls;
      calls.clear(); // drop the landing (today) fetch

      await _flingRail(tester, times: 6);
      final String browsedLabel = _label(tester);
      expect(calls, isEmpty, reason: 'browsing the rail must never fetch.');

      final BookingsDayRail rail = tester.widget<BookingsDayRail>(
        find.byType(BookingsDayRail),
      );
      final int settledPage = rail.controller.page!.round();
      final DateTime pagedMonday = railDayAt(
        rail.firstWeekStart,
        settledPage * kRailWeekLength,
      );
      expect(
        pagedMonday.month,
        isNot(_today.month),
        reason: 'fixture guard: the browse excursion did not leave July.',
      );

      await tester.tap(find.byKey(dayChipKey(pagedMonday)));
      // fixed-wait-ok: advancing past the 220ms rail-tap debounce.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(
        _label(tester),
        browsedLabel,
        reason:
            'selecting a day chip inside the browsed month left the label '
            'disagreeing with the very selection the master just made — the '
            'debounced chip-tap path (`_selectDay`) diverged from the '
            'immediate one («Сьогодні»/grid tap) in how it resyncs '
            '`_visibleMonth`.',
      );
      expect(
        calls,
        <(DateTime?, DateTime?)>[(pagedMonday, pagedMonday)],
        reason:
            'the chip tap either issued no fetch, or fetched the wrong day.',
      );
      calls.clear();

      // A second round-trip — back to today — proves the resync survives a
      // chip-tap-initiated selection, not only a browse-then-idle one.
      await tester.tap(find.byKey(_todayKey));
      await tester.pumpAndSettle();

      expect(_label(tester), isNot(browsedLabel));
      // No new fetch: `bookingsDayProvider` is a KEEPALIVE family, and
      // today's member was already resolved by the landing fetch — Riverpod
      // reuses that cached state rather than re-issuing the request. This is
      // NOT the "paging never fetches" guarantee (that's a genuine
      // navigation→no-fetch rule); it's ordinary family-cache reuse, noted
      // here so a future reader does not mistake an empty `calls` for a
      // failure to re-scope the query.
      expect(calls, isEmpty);
    },
  );

  testWidgets(
    'browsing the rail into a different month, then EXPANDING the calendar '
    'panel, reverts the label to the SELECTED day\'s month — the '
    'grid-expand resync path composed at the host level',
    (tester) async {
      final result = await _pump(tester);
      final calls = result.calls;
      calls.clear(); // drop the landing (today) fetch

      final String todayLabel = _label(tester);
      await _flingRail(tester, times: 6);
      final String browsedLabel = _label(tester);
      expect(
        browsedLabel,
        isNot(todayLabel),
        reason: 'fixture guard: browsing did not change the label.',
      );

      // No selection was made — the master only browsed. Expanding the
      // panel hands control to the month grid, which derives its label from
      // the SELECTION (`_month`), not from wherever the rail was left.
      await tester.tap(find.byKey(_toggleKey));
      await tester.pumpAndSettle();

      expect(
        _label(tester),
        todayLabel,
        reason:
            'expanding the calendar panel while the rail was browsed away '
            'left the label on the browsed-to month instead of falling '
            'back to the SELECTED day\'s month once the grid becomes the '
            'interactive layer — the panel\'s own `_railInteractive` '
            'handoff did not reach production through the real host wiring '
            '(`visibleMonth`/`onVisibleWeekChanged` construction args on '
            '`BookingsMonthCalendarPanel`).',
      );
      expect(
        calls,
        isEmpty,
        reason: 'expanding the calendar panel must never fetch.',
      );
    },
  );

  // ---------------------------------------------------------------------
  // The `_visibleMonth` reset inside `_applySelectedDay` — is it
  // LOAD-BEARING? (coordinator audit-fix pass, cycle 1)
  // ---------------------------------------------------------------------
  //
  // Every test above drives the resync end-to-end via `pumpAndSettle()`,
  // which drains the rail's `animateToPage` animation completely before any
  // assertion runs — so all of them equally pass whether `_visibleMonth` is
  // reset SYNCHRONOUSLY inside `_applySelectedDay`, or only relabelled
  // ~320ms later when `_showRailWeekOf`'s own resync settles and
  // `onVisibleWeekChanged` fires independently (`_onRailVisibleWeekChanged`
  // self-heals it either way, eventually). That makes the reset line
  // observably dead against every scenario reachable through
  // `pumpAndSettle()`.
  //
  // The one window where it is NOT redundant: `_showRailWeekOf` only
  // ANIMATES (a real 320ms `AnimationController` sweep, sampled per frame)
  // when the target week is ADJACENT to the rail's current page
  // (`_kRailAnimateMaxPages == 1` in `bookings_discovery_view.dart`) —
  // anything farther jumps synchronously instead. So a resync that is both
  // (a) adjacent and (b) crosses a month boundary opens a real, sampleable
  // gap between "the selection changed" (synchronous) and "the rail's own
  // settle relabels it" (~320ms later). This test targets exactly that gap
  // with `pump(Duration)`, never `pumpAndSettle()`.
  testWidgets(
    'REGRESSION (mid-animation window): «Сьогодні», pressed after browsing '
    'into the ADJACENT week one month back, relabels IMMEDIATELY — not '
    'only after the rail\'s own animateToPage settle ~320ms later',
    (tester) async {
      // Monday 2026-02-02: its own week is entirely February, and the week
      // immediately BEFORE it — Monday 2026-01-26 — is exactly ONE rail
      // page away (adjacent) and sits in January. That combination is what
      // makes `_showRailWeekOf` choose the ANIMATED `animateToPage` branch
      // (not the synchronous `jumpToPage` one) when «Сьогодні» resyncs the
      // rail below.
      //
      // A DATE TOKEN like `_today` above — deliberately bare host-local, fed
      // to `clockProvider` only via `_pump`'s `asClockInstant` wrap, never
      // raw. This test never compares `todayFeb` via `==` directly (only
      // `.weekday`, and `calls` against `isEmpty`), so unlike `_today` it
      // has no SECOND role forcing the bare-local requirement here — it
      // stays bare-local anyway, for consistency with `_today`'s doc and
      // because a date token is what this value conceptually is.
      final DateTime todayFeb = DateTime(2026, 2, 2);
      // `.weekday` reads only the calendar date, never the instant/host
      // `TZ`; verifying the precondition still holds rather than trusting
      // it.
      expect(todayFeb.weekday, DateTime.monday, reason: 'fixture precondition');

      final result = await _pump(tester, today: todayFeb);
      final calls = result.calls;
      calls.clear();

      final String todayLabel = _label(tester);

      // One page BACK — lands on the Jan 26 week, in January. `Offset` sign
      // mirrors this file's sibling `_flingRail`/the day-rail suite's own
      // convention: negative dx pages forward, positive dx pages backward.
      await tester.fling(find.byKey(_railKey), const Offset(300, 0), 800);
      await tester.pumpAndSettle();

      final String browsedLabel = _label(tester);
      expect(
        browsedLabel,
        isNot(todayLabel),
        reason:
            'fixture guard: paging one week back did not relabel at all — '
            'the rail did not actually reach January, so the assertion '
            'below would prove nothing.',
      );

      // «Сьогодні» — the SELECTED day does not actually change (it was
      // already today), but `_selectImmediate` unconditionally runs
      // `_applySelectedDay` (and, per this test, the reset under scrutiny)
      // regardless of whether the value differs, then pages the rail back
      // via an ADJACENT, ANIMATED `_showRailWeekOf` call.
      await tester.tap(find.byKey(_todayKey));
      // Sampled WELL INSIDE the 320ms animateToPage window — deliberately
      // `pump(Duration)`, never `pumpAndSettle()`, which would skip straight
      // past the window this test exists to observe and land on the
      // already self-healed end state.
      // fixed-wait-ok: sampling a mid-animation frame, not a condition.
      await tester.pump(const Duration(milliseconds: 40));

      expect(
        _label(tester),
        todayLabel,
        reason:
            'the label was still showing the browsed-to month 40ms into '
            'the «Сьогодні» resync — only the `_visibleMonth` reset inside '
            '`_applySelectedDay` can correct it this early; the rail\'s own '
            'animateToPage settle (and the independent '
            '`onVisibleWeekChanged` relabel that follows it) does not land '
            'for another ~280ms.',
      );

      // Let the animation actually finish so no Ticker/Timer leaks into the
      // next test, and confirm the self-heal still lands where it should.
      await tester.pumpAndSettle();
      expect(_label(tester), todayLabel);
      expect(
        calls,
        isEmpty,
        reason:
            'the whole browse-then-«Сьогодні» round trip must still never '
            'fetch — the day never actually changed.',
      );
    },
  );

  // =========================================================================
  // STRADDLING WEEKS — the axis this whole suite pinned to the SAFE side by
  // construction, which is exactly why the defect shipped (mobile-qa,
  // 2026-09-01).
  // =========================================================================
  //
  // Every fixture above — `_today` (Wed 2026-07-15) and `todayFeb`
  // (Mon 2026-02-02) — sits in a week that lies ENTIRELY inside one month. For
  // such a week `mondayOf(_day).month == _day.month`, so labelling by the
  // rail's week-START and labelling by the SELECTION are the same number and
  // the pre-fix `_onRailVisibleWeekChanged` could not be told apart from the
  // fixed one. Same for every sibling file (`bookings_month_calendar_panel_*`,
  // `master_bookings_screen_test.dart`).
  //
  // A week that CROSSES a month boundary is the axis where they diverge, and
  // the production symptom is precisely that divergence: the collapsed strip
  // relabelled to the PREVIOUS month for any selection in the tail of a
  // straddling week. Recurrences: 1–4 Oct 2026, 1 Nov 2026, 1–6 Dec 2026.
  //
  // WHY THE COLLAPSED STATE, SPECIFICALLY: `_TopRow`'s label reads
  // `widget.visibleMonth` only while `_railInteractive` (i.e. COLLAPSED) and
  // falls back to `_month` (derived from the selection, always correct) while
  // the grid is open — see `bookings_month_calendar_panel.dart:598-600`. So
  // every assertion below reads the label AFTER collapsing, through the
  // rendered `Text` at `bookings-month-calendar-label`. Never `_visibleMonth`
  // as a widget/State field: a field read is vacuous (this repo has been
  // bitten by exactly that), and the field is not even the whole story — the
  // `if (_visibleMonth == month) return;` short-circuit means the RENDERED
  // string is the only honest observable.
  group('STRADDLING week — the COLLAPSED label names the SELECTED day\'s '
      'month, never the rail week\'s Monday', () {
    /// Thursday 2026-10-01 — a DATE TOKEN, same bare-host-local convention as
    /// [_today] above (fed to `clockProvider` only through `_pump`'s
    /// `asClockInstant` wrap, never raw).
    ///
    /// Its ISO week starts Monday **2026-09-28**, in SEPTEMBER. That is the
    /// whole point: the selected day and its week-start disagree about the
    /// month, so the two labelling rules produce different strings and the
    /// fix becomes observable.
    final DateTime todayOct1 = DateTime(2026, 10, 1);

    /// Sunday 2026-11-01 — where a ONE-MONTH page turn from [todayOct1] lands
    /// (`_stepMonth` keeps the day-of-month, clamped). Its week starts Monday
    /// **2026-10-26**, in OCTOBER — a second, independent straddling pair, so
    /// the page-turn case is not merely a restatement of the «Сьогодні» one.
    final DateTime nov1 = DateTime(2026, 11, 1);

    String labelFor(DateTime day) =>
        '${monthNominative(day.month)} ${day.year}';

    /// Asserts the fixture really is straddling. Without this the tests below
    /// could silently degrade into the already-covered non-straddling case
    /// (e.g. if someone "tidied" the dates) and keep passing while proving
    /// nothing — the same class of quiet defang the existing cases guard with
    /// their own `fixture guard:` expectations.
    void expectStraddling(DateTime day) {
      final DateTime monday = mondayOf(day);
      expect(
        monday.month,
        isNot(day.month),
        reason:
            'fixture precondition: $day must sit in a week whose Monday '
            '($monday) is in a DIFFERENT month — that disagreement is the '
            'entire axis under test.',
      );
    }

    /// A month page turn on `bookings-month-calendar-grid`.
    ///
    /// Deliberately the paused-before-lift recipe, NOT `tester.fling` — the
    /// grid runs `LowThresholdPageScrollPhysics`, and 8 real 40ms-spaced
    /// samples followed by a pump past `VelocityTracker`'s 40ms "assume
    /// stopped" cutoff is the shape that reliably commits a page. Not
    /// re-derived here: see `bookings_pager_commit_threshold_test.dart`'s
    /// header for why 8 samples (4 freezes `PageController.page` mid-drag)
    /// and why a trailing run of zero-delta samples is not a substitute.
    Future<void> pageMonthForward(WidgetTester tester) async {
      final Finder grid = find.byKey(const Key('bookings-month-calendar-grid'));
      final double width = tester.getRect(grid).width;
      const int steps = 8;
      final double dx = -(width * 0.6) / steps;
      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(grid),
      );
      Duration stamp = Duration.zero;
      for (int i = 0; i < steps; i++) {
        stamp += const Duration(milliseconds: 40);
        await gesture.moveBy(Offset(dx, 0), timeStamp: stamp);
        // fixed-wait-ok: advancing the pointer-sample clock in lockstep with
        // the synthetic move timestamps, not waiting on a condition.
        await tester.pump(const Duration(milliseconds: 40));
      }
      // fixed-wait-ok: past VelocityTracker's 40ms "assume stopped" cutoff.
      await tester.pump(const Duration(milliseconds: 60));
      await gesture.up();
      await tester.pumpAndSettle();
    }

    testWidgets(
      'PATH 1 — «Сьогодні», pressed after browsing away, relabels to the '
      'SELECTED day\'s month (October), not to its week-start\'s (September)',
      (tester) async {
        expectStraddling(todayOct1);

        final result = await _pump(tester, today: todayOct1);
        result.calls.clear();

        expect(
          _label(tester),
          labelFor(todayOct1),
          reason:
              'landing must already name the selected day\'s month — the rail '
              'rests on the Sep-28 week, so a week-start label reads '
              '«${labelFor(mondayOf(todayOct1))}» here.',
        );

        // Browse clear of the landing week — and clear of OCTOBER, so the
        // guard below can actually observe a relabel. Six weeks forward from
        // the Sep-28 week lands on the week of Monday 2026-11-09; four would
        // still be inside October and would make this guard vacuous.
        // The move also has to be a REAL page move, because only a rail
        // SETTLE fires `onVisibleWeekChanged` at all.
        await _flingRail(tester, times: 6);
        expect(
          _label(tester),
          isNot(labelFor(todayOct1)),
          reason:
              'fixture guard: browsing six weeks forward from 2026-10-01 did '
              'not relabel — the rail did not move, so the resync below would '
              'prove nothing.',
        );
        expect(result.calls, isEmpty, reason: 'browsing must never fetch.');

        await tester.tap(find.byKey(_todayKey));
        await tester.pumpAndSettle();

        expect(
          _label(tester),
          labelFor(todayOct1),
          reason:
              'THE PRODUCTION BUG. «Сьогодні» on 2026-10-01 re-selects a day '
              'in OCTOBER, but the rail settles on the week starting Monday '
              '28 September 2026 — and `_onRailVisibleWeekChanged` fires AFTER '
              '`_applySelectedDay` has already written the correct month, so '
              'a week-start label clobbers it back to '
              '«${labelFor(mondayOf(todayOct1))}». The master is looking at '
              'October\'s bookings under a September heading.',
        );
        expect(
          result.calls,
          isEmpty,
          reason:
              'the day never actually changed (today -> today), so the whole '
              'round trip must stay a pure relabel.',
        );
      },
    );

    testWidgets(
      'PATH 2 — a grid-cell tap on a FIRST-OF-MONTH day, then COLLAPSE, '
      'leaves the label on the tapped day\'s month',
      (tester) async {
        // Today is deliberately MID-month here (Thursday 15 October 2026,
        // whose week lies entirely inside October), so that the day the grid
        // tap SELECTS — 1 October — is a genuinely new selection two rail
        // pages away. That buys two things the todayOct1 anchor cannot:
        //   • a real rail page move, and therefore a real settle, which is the
        //     only thing that fires `onVisibleWeekChanged` at all;
        //   • a real fetch, so "the tap registered on the day I meant" is
        //     checkable. Re-selecting the ALREADY-selected day produces a
        //     value-equal `BookingsDayQuery` and the keepAlive family reuses
        //     its cached state — an empty `calls` there proves nothing.
        // The SELECTION is what has to straddle, not `today`.
        final DateTime oct15 = DateTime(2026, 10, 15);
        expectStraddling(todayOct1);

        final result = await _pump(tester, today: oct15);
        result.calls.clear();

        // Expand the grid. While open the label reads `_month` (the
        // selection), so it is correct here under BOTH the bug and the fix —
        // the divergence only appears once the panel collapses again.
        await tester.tap(find.byKey(_toggleKey));
        await tester.pumpAndSettle();

        // Tap 1 October in the grid — a day in the TAIL of the straddling
        // week starting Monday 28 September 2026.
        //
        // `tapCalendarDay`, never a bare `tester.tap`: `MonthCalendar` sits in
        // a `SingleChildScrollView` and a below-the-fold cell absorbs a blind
        // tap into the summary bar instead of throwing, which reads as flake
        // on exactly the dates where it bites (`forbid_blind_calendar_tap.sh`).
        //
        // The helper reveals ONLY a cell a tap could not otherwise reach: the
        // panel's expanded grid puts a HORIZONTAL month pager between this
        // cell and the vertical scroll view, and an unconditional
        // `ensureVisible` commits a page turn on it — which SELECTS the next
        // month before the tap lands. See `tapCalendarDay`'s doc for the
        // measurement. Day 1 is in the grid's first row and fully hittable, so
        // no reveal fires here.
        await tester.tapCalendarDay(1);
        await tester.pumpAndSettle();

        expect(
          result.calls,
          <(DateTime?, DateTime?)>[(todayOct1, todayOct1)],
          reason:
              'fixture guard: the grid tap must have registered on 1 OCTOBER. '
              'A swallowed tap issues no fetch at all, and a tap that landed '
              'on another month\'s cell of the same number fetches that '
              'month\'s day instead — either way the label assertion below '
              'would be about the wrong selection.',
        );

        await tester.tap(find.byKey(_toggleKey));
        await tester.pumpAndSettle();

        expect(
          _label(tester),
          labelFor(todayOct1),
          reason:
              'THE PRODUCTION BUG, second reachable path. Tapping 1 October '
              'pages the rail onto the week starting Monday 28 September 2026; '
              'the settle callback then relabels the collapsed strip to '
              '«${labelFor(mondayOf(todayOct1))}» — the month the master just '
              'left — instead of the October day they just picked.',
        );
      },
    );

    testWidgets(
      'PATH 3 — a month PAGE TURN onto a month whose 1st is in a straddling '
      'tail, then COLLAPSE, leaves the label on the newly selected month',
      (tester) async {
        expectStraddling(nov1);

        final result = await _pump(tester, today: todayOct1);
        result.calls.clear();

        await tester.tap(find.byKey(_toggleKey));
        await tester.pumpAndSettle();

        await pageMonthForward(tester);

        // `_stepMonth(1)` keeps the day-of-month (1, no clamping needed), so
        // the selection is now Sunday 2026-11-01, whose week starts Monday
        // 2026-10-26 — in OCTOBER.
        expect(
          result.calls,
          <(DateTime?, DateTime?)>[(nov1, nov1)],
          reason:
              'fixture guard: the page turn did not commit onto November 1 — '
              'the assertion below would then be about the wrong selection. '
              '(A page turn DOES select, unlike a rail week flick.)',
        );

        await tester.tap(find.byKey(_toggleKey));
        await tester.pumpAndSettle();

        expect(
          _label(tester),
          labelFor(nov1),
          reason:
              'THE PRODUCTION BUG, third reachable path. Paging to November '
              'selects 1 November, whose week starts Monday 2026-10-26 — so '
              'the rail settles in OCTOBER and a week-start label drags the '
              'collapsed heading back to «${labelFor(mondayOf(nov1))}» while '
              'the timeline shows November bookings.',
        );
      },
    );
  });
}
