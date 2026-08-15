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
}
