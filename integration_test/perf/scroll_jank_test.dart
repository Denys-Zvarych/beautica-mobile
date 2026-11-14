// Phase 076 (10.2, A3) — scroll-jank flow over the four heaviest lists, plus
// (phase 486) the master's week grid.
//
// WHAT RUNS WHERE
// ---------------
//   * HEADLESS (`flutter test integration_test/perf/scroll_jank_test.dart
//     -d flutter-tester`, i.e. the debug/JIT tier every other flow here uses):
//     each test boots the REAL app against [FakeBackend] seeded with >= 150 rows
//     for its surface and DRIVES the scroll (fling down, fling back up) under
//     `binding.watchPerformance`. It asserts the surface mounted and the scroll
//     ran without a framework error. It asserts NOTHING about frame time:
//     a debug build on a VM has no meaningful frame budget.
//   * DEVICE, PROFILE (`scripts/measure_jank.sh --device <serial>`, which runs
//     `flutter drive --profile --driver=test_driver/integration_test.dart
//     --target=integration_test/perf/scroll_jank_test.dart`): additionally
//     asserts (unless `JANK_ENFORCE=false`, see [_kEnforce]) p90 and worst frame
//     BUILD time < [_kBudgetMillis] per surface and lands every summary in
//     `build/integration_response_data.json` for the runner to tabulate.
//
// SURFACES (report keys `<key>_scroll`): my-bookings, search-results,
// services-list, salon-board, master-week; plus `master-week_entrance` — the
// week view's one 750 ms load moment, watched from the tap that opens the
// tab (so BEFORE the grid's first data frame and the entrance start) until
// the entrance has completed + [_kEntranceTailFrames], with the binding in
// `fullyLive` frame policy for that window only so every vsync frame the
// engine draws is counted (the pump-driven default draws only the frames a
// `pump` asks for — ~4 on a real device, under JANK_MIN_ENTRANCE_FRAMES).
// Scroll targets are located by the
// keys the screens already carry (`my-bookings-list-upcoming`, `results_list`,
// `services-list-scroll`) or, for the board and the week, by the
// `BookingsTimelineGrid` / `WeekTimeGrid` itself.
//
// master-week (phase 486, decision D1): the master's «Записи» week grid in
// «3 дні» on a busy week (8 bookings every day), flung HORIZONTALLY across
// the week — the gesture the week view's frame budget is about. The pager
// has only 7 days and one fling crosses ~3 of them, so the horizontal flings
// head one way until the pager sits on that end, then turn (kFixedNow is a
// Sunday: the pager opens on the LAST page, so the first fling heads for
// Monday). Every fling therefore moves the pager — none piles
// idle frames against a clamped edge, which would dilute p90.
//
// Seeding goes through [FakeBackend]'s own seams — `seedManyBookingsDataset`,
// `seedManySearchMasters`, `seedManyServices`, `salonBoardBookings` — no second
// harness.

import 'dart:async';

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/domain/week_day_model.dart'
    show kWeekGridDays;
import 'package:beautica_mobile/features/booking/presentation/master_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/my_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_timeline_grid.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/week_time_grid.dart';
import 'package:beautica_mobile/features/discovery/domain/search_filters.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_bookings_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_shell_screen.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../../test/helpers/overflow_guard.dart';
import '../support/app_harness.dart';

/// Rows seeded per surface — comfortably past the cache extent so culling,
/// lazy build and dispose are all exercised.
const int _kRows = 160;

/// Frame-budget ceiling (ms) for p90 and worst frame BUILD time. Asserted in
/// profile mode only.
const double _kBudgetMillis = 16;

/// `--dart-define=JANK_ENFORCE=false` (what `scripts/measure_jank.sh` passes by
/// default) skips the in-test budget assertion so an over-budget baseline still
/// reaches the driver, which only writes response data for a PASSING test. The
/// script's own table is the gate in that mode. Defaults to `true`.
const bool _kEnforce = bool.fromEnvironment('JANK_ENFORCE', defaultValue: true);

/// Fling passes in each direction per surface.
const int _kPasses = 4;

/// Frames pumped after each fling so the inertia plays out frame by frame.
const int _kFramesPerFling = 30;

/// Upper bound on the pumps while the week entrance plays (a 750 ms
/// entrance — `WeekTimeGrid.entranceDuration` — is ~45 frames at 60 Hz);
/// the watch ends as soon as it has completed, plus [_kEntranceTailFrames].
const int _kMaxEntranceFrames = 240;

/// Wall-time bound on waiting for the week grid to mount inside the
/// entrance watch (the data load after the tab tap).
const Duration _kEntranceMountTimeout = Duration(seconds: 20);

/// Frames watched after the entrance completes — the frame its column
/// wrappers collapse in belongs to the entrance's cost.
const int _kEntranceTailFrames = 3;

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  /// Vertical: flings [scrollable] [_kPasses] times down, then [_kPasses]
  /// times back up (a 160-row list has room for every fling). Horizontal
  /// (the 7-day week pager, a fling crosses ~3 days): 2 × [_kPasses] flings
  /// that keep heading one way until [atEdge] reports the pager already sits
  /// on that end, then turn — so EVERY fling moves the pager, none is spent
  /// against a clamped edge. Real frames are pumped between flings (never
  /// `pumpAndSettle`: the search list's load-more spinner is an
  /// indeterminate animation that never settles).
  Future<void> scrollThrough(
    WidgetTester tester,
    Finder scrollable, {
    bool horizontal = false,
    bool Function(bool towardStart)? atEdge,
  }) async {
    bool towardStart = true;
    for (int i = 0; i < 2 * _kPasses; i++) {
      if (atEdge?.call(towardStart) ?? false) towardStart = !towardStart;
      // Finger right (+x) scrolls toward the start; finger up (-y) scrolls
      // down the list.
      final Offset drag = horizontal
          ? Offset(towardStart ? 700 : -700, 0)
          : Offset(0, i < _kPasses ? -700 : 700);
      await tester.fling(scrollable, drag, 2400);
      for (int f = 0; f < _kFramesPerFling; f++) {
        // fixed-wait-ok: frame cadence for the profiler — the inertia of a
        // fling has no completion signal to pump until.
        await tester.pump(const Duration(milliseconds: 16));
      }
    }
  }

  /// (profile + enforce only) the build-time budget on [reportKey]'s summary.
  void expectWithinBudget(String reportKey) {
    if (!kProfileMode || !_kEnforce) return;
    final Map<String, dynamic>? summary =
        binding.reportData?[reportKey] as Map<String, dynamic>?;
    expect(summary, isNotNull, reason: '$reportKey: no frame summary');
    final num? p90 =
        summary?['90th_percentile_frame_build_time_millis'] as num?;
    final num? worst = summary?['worst_frame_build_time_millis'] as num?;
    expect(p90, lessThan(_kBudgetMillis), reason: '$reportKey p90 build ms');
    expect(
      worst,
      lessThan(_kBudgetMillis),
      reason: '$reportKey worst build ms',
    );
  }

  /// Runs [scrollThrough] under the frame profiler, then (profile only)
  /// asserts the budget on the summary it produced.
  Future<void> measure(
    WidgetTester tester,
    String key,
    Finder scrollable, {
    bool horizontal = false,
    bool Function(bool towardStart)? atEdge,
  }) async {
    expect(scrollable, findsWidgets, reason: '$key: scroll target must mount');
    await binding.watchPerformance(
      () => scrollThrough(
        tester,
        scrollable,
        horizontal: horizontal,
        atEdge: atEdge,
      ),
      reportKey: '${key}_scroll',
    );
    expect(tester.takeException(), isNull, reason: '$key: scroll threw');
    expect(scrollable, findsWidgets, reason: '$key: survived the scroll');
    expectWithinBudget('${key}_scroll');
  }

  /// Watches the week view's entrance as `<key>_entrance`. [open] (the tab
  /// tap) runs INSIDE the watched action: `watchPerformance` waits 2 s before
  /// it registers its FrameTiming callback, and the data load, grid mount and
  /// whole entrance all finish inside that wait, so a tap made before the
  /// call left only the tail frames recorded. Inside the action the recorder
  /// is live; the grid (found by [grid]) is asserted absent right before
  /// [open], then the action pumps until the grid mounts, until its entrance
  /// completes, and [_kEntranceTailFrames] more. The window runs under
  /// [LiveTestWidgetsFlutterBindingFramePolicy.fullyLive] so every engine
  /// frame is drawn and counted (the default policy draws only the frames a
  /// `pump` asks for); the policy is restored afterwards, so the scroll
  /// surfaces keep theirs.
  Future<void> measureEntrance(
    WidgetTester tester,
    String key,
    Finder grid,
    Future<void> Function() open,
  ) async {
    Animation<double>? entrance;
    final LiveTestWidgetsFlutterBindingFramePolicy policy = binding.framePolicy;
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    try {
      await binding.watchPerformance(() async {
        // The recorder is live from here: nothing of the entrance may have
        // happened yet, or the window would again miss its head.
        expect(
          grid,
          findsNothing,
          reason: '$key: the grid mounted before the entrance watch started',
        );
        await open();
        // Elapsed-time poll budget (the runner's own wait for the data
        // load), measured by a Stopwatch — no clock read at all.
        final Stopwatch waited = Stopwatch()..start();
        while (grid.evaluate().isEmpty) {
          if (waited.elapsed > _kEntranceMountTimeout) {
            throw TestFailure('$key: grid never mounted in the watch');
          }
          // fixed-wait-ok: frame cadence for the profiler while the data
          // loads; bounded by the elapsed-time budget above.
          await tester.pump(const Duration(milliseconds: 16));
        }
        entrance = tester.widget<WeekTimeGrid>(grid).entrance;
        final Animation<double> e = entrance ?? kAlwaysCompleteAnimation;
        for (int f = 0; f < _kMaxEntranceFrames && !e.isCompleted; f++) {
          // fixed-wait-ok: frame cadence for the profiler, bounded; ends as
          // soon as the entrance completes.
          await tester.pump(const Duration(milliseconds: 16));
        }
        for (int f = 0; f < _kEntranceTailFrames; f++) {
          // fixed-wait-ok: the collapse frame(s) right after completion.
          await tester.pump(const Duration(milliseconds: 16));
        }
      }, reportKey: '${key}_entrance');
    } finally {
      binding.framePolicy = policy;
    }
    expect(tester.takeException(), isNull, reason: '$key: entrance threw');
    expect(entrance, isNotNull, reason: 'the week view hands the grid one');
    expect(entrance?.isCompleted, isTrue, reason: '$key: entrance never ended');
    expectWithinBudget('${key}_entrance');
  }

  testWidgets('my-bookings scroll', (tester) async {
    final FakeBackend fb = FakeBackend()..currentRole = UserRole.client;
    fb.seedManyBookingsDataset(<Map<String, dynamic>>[
      for (int i = 0; i < _kRows; i++)
        fb.datasetBookingRow(
          id: 'perf-upcoming-$i',
          status: 'CONFIRMED',
          startsAt: kFixedNow.add(Duration(hours: 6 * (i + 1))),
        ),
    ]);
    final GoRouter router = await AppHarness.boot(tester, fb);
    await AppHarness.loginAs(tester, fb, UserRole.client);

    await tester.tap(find.byKey(const Key('client-nav-tile-3')));
    await AppHarness.settle(tester);
    AppHarness.expectLocation(router, RouteNames.clientBookings);
    expect(find.byType(MyBookingsScreen), findsOneWidget);

    await measure(
      tester,
      'my-bookings',
      find.byKey(const ValueKey<String>('my-bookings-list-upcoming')),
    );
  });

  testWidgets('search-results scroll', (tester) async {
    final FakeBackend fb = FakeBackend()..currentRole = UserRole.client;
    fb.seedManySearchMasters(_kRows);
    final GoRouter router = await AppHarness.boot(tester, fb);
    await AppHarness.loginAs(tester, fb, UserRole.client);

    unawaited(
      router.push<void>(
        RouteNames.clientSearchResults,
        extra: const SearchFilters(),
      ),
    );
    await AppHarness.pumpUntilFound(
      tester,
      find.byKey(const Key('results_list')),
      timeout: const Duration(seconds: 20),
    );

    await measure(
      tester,
      'search-results',
      find.byKey(const Key('results_list')),
    );
  });

  testWidgets('services-list scroll', (tester) async {
    final FakeBackend fb = FakeBackend()
      ..currentRole = UserRole.independentMaster
      ..seedManyServices(_kRows, categories: const <String>['NAILS']);
    final GoRouter router = await AppHarness.boot(tester, fb);
    await AppHarness.loginAs(tester, fb, UserRole.independentMaster);

    router.go(RouteNames.services);
    final Finder section = find.byKey(const Key('category_section_NAILS'));
    await AppHarness.pumpUntilFound(tester, section);
    await AppHarness.tapVisible(tester, section);
    await AppHarness.settle(tester);
    expect(find.byType(ServicesListScreen), findsOneWidget);

    await measure(
      tester,
      'services-list',
      find.byKey(const Key('services-list-scroll')),
    );
  });

  testWidgets('salon-board scroll', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()
        ..currentRole = UserRole.salonOwner
        ..bookingProviderCanReviewClient = false;
      await AppHarness.boot(tester, fb);

      // Seeded AFTER boot: the Kyiv zone is initialised by harness startup.
      // 5 roster masters x 32 non-overlapping 20-minute slots = 160 cards.
      final DateTime day = kyivToday(() => kFixedNow);
      const List<(String, String)> roster = <(String, String)>[
        ('master-aaa', 'Софія'),
        ('master-ccc', 'Марія'),
        ('master-ddd', 'Оксана'),
        ('master-eee', 'Тетяна'),
        ('master-fff', 'Наталія'),
      ];
      fb.salonBoardBookings = <Map<String, dynamic>>[
        for (int m = 0; m < roster.length; m++)
          for (int s = 0; s < _kRows ~/ roster.length; s++)
            fb.salonBoardBookingRow(
              id: 'perf-board-$m-$s',
              masterId: roster[m].$1,
              masterFirstName: roster[m].$2,
              masterLastName: 'Тест',
              // Kyiv is UTC+3 in June; 08:00 Kyiv + s * 20 min.
              startsAt: DateTime.utc(day.year, day.month, day.day, 5, s * 20),
              duration: const Duration(minutes: 20),
            ),
      ];
      await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
      await AppHarness.pumpUntilFound(
        tester,
        find.byType(SalonShellScreen),
        timeout: const Duration(seconds: 20),
      );
      final Finder tab = find.byKey(const Key('salon-nav-tile-1'));
      await AppHarness.pumpUntilFound(
        tester,
        tab.hitTestable(),
        timeout: const Duration(seconds: 20),
      );
      await tester.tap(tab);
      await tester.pump();
      await AppHarness.pumpUntilFound(
        tester,
        find.byType(SalonBookingsScreen),
        timeout: const Duration(seconds: 20),
      );
      await AppHarness.pumpUntilFound(
        tester,
        find.byType(BookingsTimelineGrid),
        timeout: const Duration(seconds: 20),
      );

      // Fling ON the grid: its own box is on screen, whereas the inner
      // vertical `SingleChildScrollView` (the one the grid attaches its
      // controller to) is as tall as the whole day, so its centre is off
      // screen and not hit-testable. The vertical drag falls through the
      // horizontal strip scroller to that inner scroller.
      await measure(tester, 'salon-board', find.byType(BookingsTimelineGrid));
    });
  });

  testWidgets('master-week fling', (tester) async {
    // No `mockNetworkImagesFor`: the week grid loads no network image, and
    // that mock also swallows the VM-service socket `watchPerformance` opens.
    final FakeBackend fb = FakeBackend()
      ..currentRole = UserRole.independentMaster;
    await AppHarness.boot(tester, fb);

    // Seeded AFTER boot (Kyiv zone). The injected clock's own week, 8
    // one-hour bookings 09:00–17:00 Kyiv on every day = 56 cards.
    final DateTime monday = kyivWeekStart(kyivToday(() => kFixedNow));
    fb.seedManyBookingsDataset(<Map<String, dynamic>>[
      for (int d = 0; d < 7; d++)
        for (int h = 9; h < 17; h++)
          fb.datasetBookingRow(
            id: 'perf-week-$d-$h',
            status: 'CONFIRMED',
            startsAt: kyivMidnight(
              kyivAddDays(monday, d),
            ).add(Duration(hours: h)).toUtc(),
          ),
    ]);
    await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
    // The tab tap runs inside the entrance watch, after its recorder is
    // live, so the window covers the grid's first data frame and the whole
    // 750 ms entrance.
    final Finder weekTab = find.byKey(const Key('master-nav-tile-1'));
    expect(weekTab, findsOneWidget, reason: 'master-week: week tab');
    await measureEntrance(
      tester,
      'master-week',
      find.byType(WeekTimeGrid),
      () => tester.tap(weekTab),
    );
    expect(find.byType(MasterBookingsScreen), findsOneWidget);
    expect(find.byKey(WeekTimeGrid.pagerKey), findsOneWidget);

    // The extremes the flings reach, sampled on every pager tick — the
    // budget is about a Mon→Sun fling, so the run must actually cover it.
    final WeekTimeGrid g = tester.widget<WeekTimeGrid>(
      find.byType(WeekTimeGrid),
    );
    final PageController pager = g.pageController;
    final double lastPage = (kWeekGridDays - g.visibleColumns).toDouble();
    double minPage = double.infinity;
    double maxPage = double.negativeInfinity;
    void sample() {
      final double? p = pager.hasClients ? pager.page : null;
      if (p == null) return;
      if (p < minPage) minPage = p;
      if (p > maxPage) maxPage = p;
    }

    sample();
    pager.addListener(sample);
    // A fling turns only once the pager sits on the end it was heading for.
    final List<double> pageBeforeFling = <double>[];
    bool atEdge(bool towardStart) {
      final double p = pager.page ?? pager.initialPage.toDouble();
      pageBeforeFling.add(p);
      return towardStart ? p <= 0.01 : p >= lastPage - 0.01;
    }

    await measure(
      tester,
      'master-week',
      // ON the grid's own box: the pager is as tall as the whole day inside
      // the vertical scroll, so its centre is off screen (the salon board's
      // reason above). The grid's centre sits on the pager, right of the
      // ruler, so the horizontal fling drives the pager itself.
      find.byType(WeekTimeGrid),
      horizontal: true,
      atEdge: atEdge,
    );
    pager.removeListener(sample);

    // The flings must reach BOTH ends of the week — page 0 (Monday on the
    // left) and the last page (Sunday on the right) — or the measured frames
    // never cover the Mon→Sun fling D1 budgets (observed 0..4 in «3 дні»).
    // MUTATION (mobile-qa 2026-11-12): flings cut to 1 pass of
    // ±60 px → RED on the Monday end. Restored by cp.
    // Every fling moved the pager: no two consecutive flings started from
    // the same page (a fling spent against a clamped edge would).
    // MUTATION (2026-11-12): the old 4-one-way-then-4-back flings → RED
    // (pages before each fling 4, 1, 0, 0, 0, …). Restored by cp.
    for (int f = 1; f < pageBeforeFling.length; f++) {
      expect(
        (pageBeforeFling[f] - pageBeforeFling[f - 1]).abs(),
        greaterThan(0.5),
        reason:
            'master-week fling ${f - 1} did not move the pager '
            '(pages before each fling: $pageBeforeFling)',
      );
    }
    expect(
      minPage,
      lessThanOrEqualTo(0.01),
      reason: 'master-week fling never reached Monday (min page)',
    );
    expect(
      maxPage,
      greaterThanOrEqualTo(lastPage - 0.01),
      reason:
          'master-week fling never reached the last page '
          '(max page, want $lastPage)',
    );
  });
}
