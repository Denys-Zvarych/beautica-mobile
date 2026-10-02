// Phase 076 (10.2, A3) — scroll-jank flow over the four heaviest lists.
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
// services-list, salon-board. Scroll targets are located by the keys the
// screens already carry (`my-bookings-list-upcoming`, `results_list`,
// `services-list-scroll`) or, for the board, by the `BookingsTimelineGrid` itself.
//
// Seeding goes through [FakeBackend]'s own seams — `seedManyBookingsDataset`,
// `seedManySearchMasters`, `seedManyServices`, `salonBoardBookings` — no second
// harness.

import 'dart:async';

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/my_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_timeline_grid.dart';
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

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  /// Flings [scrollable] [_kPasses] times down, then [_kPasses] times back up,
  /// pumping real frames between flings (never `pumpAndSettle`: the search
  /// list's load-more spinner is an indeterminate animation that never
  /// settles).
  Future<void> scrollThrough(WidgetTester tester, Finder scrollable) async {
    for (final double dy in <double>[-700, 700]) {
      for (int i = 0; i < _kPasses; i++) {
        await tester.fling(scrollable, Offset(0, dy), 2400);
        for (int f = 0; f < _kFramesPerFling; f++) {
          // fixed-wait-ok: frame cadence for the profiler — the inertia of a
          // fling has no completion signal to pump until.
          await tester.pump(const Duration(milliseconds: 16));
        }
      }
    }
  }

  /// Runs [scrollThrough] under the frame profiler, then (profile only)
  /// asserts the budget on the summary it produced.
  Future<void> measure(
    WidgetTester tester,
    String key,
    Finder scrollable,
  ) async {
    expect(scrollable, findsWidgets, reason: '$key: scroll target must mount');
    await binding.watchPerformance(
      () => scrollThrough(tester, scrollable),
      reportKey: '${key}_scroll',
    );
    expect(tester.takeException(), isNull, reason: '$key: scroll threw');
    expect(scrollable, findsWidgets, reason: '$key: survived the scroll');

    if (!kProfileMode || !_kEnforce) return;
    final Map<String, dynamic>? summary =
        binding.reportData?['${key}_scroll'] as Map<String, dynamic>?;
    expect(summary, isNotNull, reason: '$key: no frame summary was recorded');
    final num p90 = summary!['90th_percentile_frame_build_time_millis'] as num;
    final num worst = summary['worst_frame_build_time_millis'] as num;
    expect(p90, lessThan(_kBudgetMillis), reason: '$key p90 build ms');
    expect(worst, lessThan(_kBudgetMillis), reason: '$key worst build ms');
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
}
