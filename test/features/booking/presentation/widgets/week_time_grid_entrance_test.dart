// Phase 486 — the week view's ONE load moment, end to end on the real
// «Записи» screen (`MasterBookingsScreen` → `BookingsDiscoveryView` week
// layout): the strip window glides in from Monday and the grid columns rise
// left→right, driven by ONE `AnimationController` the view owns.
//
// Pinned here:
//   * it runs once the first week lands — mid-way the columns are still
//     fading in and the strip window is still short of its page;
//   * it runs ONCE per screen mount: a week step and a «День / 3 дні» toggle
//     remount the grid on the completed controller, which renders at rest;
//   * reduced motion (`disableAnimations`) — no frame moves: no column
//     fade, the window sits on its page from the first frame.
//
// The grid-level contract (opacity follows the controller, listener hygiene,
// reduced motion inside `WeekTimeGrid`) is `week_time_grid_test.dart`'s.

import 'dart:async';

import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/features/booking/application/booked_days_notifier.dart';
import 'package:beautica_mobile/features/booking/application/bookings_capability.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/master_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/week_nav_bar.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/week_strip.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/week_time_grid.dart';
import 'package:beautica_mobile/features/booking_links/presentation/booking_link_setup_hints_provider.dart';
import 'package:beautica_mobile/features/booking_links/presentation/master_nav_setup_hints_provider.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_scope.dart';
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';
import 'package:beautica_mobile/features/schedule/presentation/effective_schedule_notifier.dart';
import 'package:beautica_mobile/features/schedule/presentation/schedule_range.dart';
import 'package:beautica_mobile/features/services/data/master_service_catalog_provider.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/pump_app.dart';

class _MockBookingRepository extends Mock implements BookingRepository {}

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
}

/// 09:00–18:00 on every day of whatever range is asked for.
class _WeekHoursFake extends EffectiveScheduleNotifier {
  @override
  Future<List<EffectiveDay>> build(
    ScheduleScope scope,
    ScheduleRange range,
  ) async => <EffectiveDay>[
    for (DateTime d = range.from; !d.isAfter(range.to); d = kyivAddDays(d, 1))
      EffectiveDay(
        date: d,
        source: EffectiveSource.template,
        intervals: <WorkInterval>[
          WorkInterval(
            start: const TimeOfDay(hour: 9, minute: 0),
            end: const TimeOfDay(hour: 18, minute: 0),
          ),
        ],
      ),
  ];
}

/// The ONE pinned instant: Thursday 2026-11-12, 12:00 Kyiv (EET, UTC+2).
/// «3 дні» opens on Wed–Fri, so the strip window has three cells to glide
/// from Monday. The app clock (`clockProvider`) and every fixture day derive
/// from this — never from the host clock (M15 clock coherence), so the test
/// is independent of the host's date and TZ.
// future-date-ok: the injected fixed clock itself (M15 clock coherence)
final DateTime _kFixedNow = DateTime.utc(2026, 11, 12, 10);
DateTime _clock() => _kFixedNow;
final DateTime _thursday = kyivToday(_clock);

Booking _booking() {
  final DateTime start = kyivMidnight(
    _thursday,
  ).add(const Duration(hours: 10)).toUtc();
  return Booking(
    id: 'b1',
    masterId: 'm1',
    masterFirstName: 'Марія',
    masterLastName: 'Іванюк',
    masterType: 'INDEPENDENT_MASTER',
    clientId: 'c1',
    clientFirstName: 'Олена',
    clientLastName: 'Ковальчук',
    serviceId: 's1',
    serviceName: 'Манікюр',
    durationMinutes: 60,
    price: 500,
    startAt: start,
    endAt: start.add(const Duration(minutes: 60)),
    status: BookingStatus.confirmed,
    canReview: false,
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(BookingStatus.confirmed);
    registerFallbackValue(BookingSort.oldest);
    registerFallbackValue(<BookingStatus>[]);
    expect(_thursday.weekday, DateTime.thursday, reason: 'fixture clock');
  });

  late _MockBookingRepository repo;

  /// When set, the week fetch waits on it — the screen stays on its loading
  /// frame until the test completes it.
  Completer<void>? hold;

  setUp(() {
    repo = _MockBookingRepository();
    hold = null;
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
        partition: any(named: 'partition'),
        asMaster: any(named: 'asMaster'),
      ),
    ).thenAnswer((_) async {
      await hold?.future;
      return PageResponse<Booking>(
        items: <Booking>[_booking()],
        page: 0,
        totalPages: 1,
        totalElements: 1,
      );
    });
  });

  Future<void> mountScreen(WidgetTester tester) async {
    final GoRouter router = GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (BuildContext context, GoRouterState state) =>
              const MasterBookingsScreen(),
        ),
      ],
    );
    await tester.pumpRoutedApp(
      router,
      overrides: <Object>[
        masterNavSetupHintsProvider.overrideWithValue(
          BookingLinkSetupHints.none,
        ),
        screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
        bookingRepositoryProvider.overrideWithValue(repo),
        bookedDaysProvider.overrideWith((ref) async => <DateTime>{}),
        ownerMasterBookedDaysProvider.overrideWith((ref) async => <DateTime>{}),
        bookingCreationEnabledProvider.overrideWithValue(true),
        masterServiceCatalogProvider.overrideWith(
          (ref) async => const <MasterService>[],
        ),
        effectiveScheduleProvider.overrideWith2((_) => _WeekHoursFake()),
        clockProvider.overrideWithValue(_clock),
      ],
    );
  }

  /// The grid's pager — keyed, so presence checks need no `byType`.
  final Finder gridPager = find.byKey(WeekTimeGrid.pagerKey);
  bool gridMounted() => gridPager.evaluate().isNotEmpty;

  /// `WeekTimeGrid` has no root Key in lib/ — its fields are read by type.
  WeekTimeGrid gridOf(WidgetTester tester) =>
      tester.widget<WeekTimeGrid>(find.byType(WeekTimeGrid));

  /// The [type] transition wrapping column [day] INSIDE the pager — the
  /// route's own page transition is an ancestor too.
  Finder columnWrapper(int day, Type type) => find.ancestor(
    of: find.byKey(WeekTimeGrid.columnKey(day)),
    matching: find.descendant(of: gridPager, matching: find.byType(type)),
  );

  /// One tick to stamp the ticker's start, then 250 ms into the entrance.
  Future<void> pumpMidEntrance(WidgetTester tester) async {
    await tester.pump();
    // fixed-wait-ok: samples the entrance mid-flight; a pump-until would
    // wait the very animation under assertion out.
    await tester.pump(const Duration(milliseconds: 250));
  }

  /// Mounts the screen and pumps single frames until the grid is on screen
  /// — NOT settled, so the entrance is still at its start.
  Future<void> mountUntilGrid(
    WidgetTester tester, {
    bool mount = true,
    bool expectGrid = true,
  }) async {
    if (mount) await mountScreen(tester);
    for (int i = 0; i < 20 && (!gridMounted() || !expectGrid && i < 5); i++) {
      if (!expectGrid && find.byKey(WeekStrip.daysKey).evaluate().isNotEmpty) {
        break;
      }
      await tester.pump();
    }
    if (expectGrid) expect(gridPager, findsOneWidget);
  }

  Animation<double> entranceOf(WidgetTester tester) {
    final Animation<double>? a = gridOf(tester).entrance;
    expect(a, isNotNull, reason: 'the screen hands the grid its entrance');
    return a ?? kAlwaysCompleteAnimation;
  }

  /// The fade wrapping the column of [day] (0 = Monday); `null` when the
  /// column carries no entrance at all (reduced motion).
  double? columnOpacity(WidgetTester tester, int day) {
    final Finder fade = columnWrapper(day, FadeTransition);
    if (fade.evaluate().isEmpty) return null;
    return tester.widget<FadeTransition>(fade.first).opacity.value;
  }

  double windowLeft(WidgetTester tester) =>
      tester.getTopLeft(find.byKey(WeekStrip.windowKey)).dx;

  /// The window's resting x — the page's cell, as the strip lays it out.
  double restingWindowLeft(WidgetTester tester) {
    final Rect days = tester.getRect(find.byKey(WeekStrip.daysKey));
    final PageController pager = gridOf(tester).pageController;
    final double page = pager.page ?? pager.initialPage.toDouble();
    return days.left + page * days.width / 7 + 2;
  }

  /// Taps «next week» and pumps single frames until the NEXT week's grid is
  /// mounted (it loads behind the skeleton first).
  Future<void> stepToNextWeek(WidgetTester tester, DateTime from) async {
    await tester.tap(find.byKey(WeekStepButton.nextKey).first);
    bool nextWeekOnScreen() {
      final Iterable<Element> grids = find.byType(WeekTimeGrid).evaluate();
      return grids.isNotEmpty &&
          (grids.single.widget as WeekTimeGrid).weekStart != from;
    }

    for (int i = 0; i < 20 && !nextWeekOnScreen(); i++) {
      await tester.pump();
    }
    expect(gridOf(tester).weekStart, isNot(from));
  }

  /// Every mounted column at full opacity and the strip window on its page.
  void expectAtRest(WidgetTester tester) {
    for (int day = 0; day < 7; day++) {
      final double? o = columnOpacity(tester, day);
      if (o != null) expect(o, 1, reason: 'column $day replayed');
    }
    expect(windowLeft(tester), closeTo(restingWindowLeft(tester), 0.5));
  }

  // MUTATION: dropped the `_startWeekEntrance()` call → the controller never
  // left 0 and the mid-way expectation failed. Restored.
  testWidgets('the load moment plays once the week lands: columns fade in, '
      'the strip window glides from Monday', (WidgetTester tester) async {
    await mountUntilGrid(tester);
    final Animation<double> entrance = entranceOf(tester);
    final double rest = restingWindowLeft(tester);
    final double monday = tester.getTopLeft(find.byKey(WeekStrip.daysKey)).dx;
    expect(rest - monday, greaterThan(100), reason: 'fixture: Wed–Fri open');
    await pumpMidEntrance(tester);
    expect(entrance.value, inExclusiveRange(0, 1));
    expect(columnOpacity(tester, 2), lessThan(1));
    expect(windowLeft(tester), lessThan(rest - 1));
    expect(windowLeft(tester), greaterThan(monday));

    await tester.pumpAndSettle();
    expect(entrance.status, AnimationStatus.completed);
    // At rest the wrapper has collapsed — no fade left at all.
    expect(columnOpacity(tester, 2), isNull);
    expect(windowLeft(tester), closeTo(rest, 0.5));
  });

  // MUTATION: re-forwarded the controller from `reset()` on every
  // `_showWeekOf` → the next week's columns started at opacity 0. Restored.
  testWidgets('a week step and a «День / 3 дні» toggle do NOT replay it', (
    WidgetTester tester,
  ) async {
    await mountUntilGrid(tester);
    await tester.pumpAndSettle();
    final Animation<double> entrance = entranceOf(tester);
    expect(entrance.status, AnimationStatus.completed);
    await stepToNextWeek(tester, gridOf(tester).weekStart);
    expect(identical(entranceOf(tester), entrance), isTrue);
    expect(entrance.value, 1);
    expectAtRest(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ViewModeToggle.dayKey));
    await tester.pump();
    expect(gridOf(tester).visibleColumns, 1);
    expect(entrance.value, 1);
    expect(entrance.status, AnimationStatus.completed);
    await tester.pumpAndSettle();
  });

  // MUTATION: removed the strip's `disableAnimationsOf` gate → the window
  // started on Monday under reduced motion. Restored.
  testWidgets('reduced motion: no column fades and the window is on its '
      'page from the first frame', (WidgetTester tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    // While the week is still loading the strip is already on screen: its
    // window must sit on the opening page (Wed, index 2), not on Monday.
    final Completer<void> gate = hold = Completer<void>();
    await mountUntilGrid(tester, expectGrid: false);
    expect(gridPager, findsNothing, reason: 'still loading');
    final Rect days = tester.getRect(find.byKey(WeekStrip.daysKey));
    expect(
      windowLeft(tester),
      closeTo(days.left + 2 * days.width / 7 + 2, 0.5),
    );

    gate.complete();
    await mountUntilGrid(tester, mount: false);
    for (int day = 0; day < 7; day++) {
      expect(columnOpacity(tester, day), isNull, reason: 'column $day fades');
    }
    expect(windowLeft(tester), closeTo(restingWindowLeft(tester), 0.5));

    await tester.pump();
    expect(entranceOf(tester).value, 1, reason: 'jumped to rest, not run');
    expect(entranceOf(tester).status, AnimationStatus.completed);
    expect(windowLeft(tester), closeTo(restingWindowLeft(tester), 0.5));
  });

  // ── Phase 486 mobile-qa additions ───────────────────────────────────────

  // MUTATION (mobile-qa 2026-11-12): `_startWeekEntrance()` called before
  // the `async.hasValue || async.hasError` gate → the controller ran under
  // the skeleton and this test went RED. Restored by cp.
  testWidgets('it does not start under the skeleton — only once the first '
      'week lands', (WidgetTester tester) async {
    final Completer<void> gate = hold = Completer<void>();
    await mountUntilGrid(tester, expectGrid: false);
    expect(gridPager, findsNothing, reason: 'still loading');
    final Animation<double>? early = tester
        .widget<WeekStrip>(find.byType(WeekStrip))
        .entrance;
    expect(early, isNotNull, reason: 'the strip holds the entrance too');

    // fixed-wait-ok: proves NOTHING moves while loading — a whole entrance
    // length of frames with the fetch held open.
    await tester.pump(WeekTimeGrid.entranceDuration);
    expect(early?.value, 0);
    expect(early?.status, AnimationStatus.dismissed);

    gate.complete();
    await mountUntilGrid(tester, mount: false);
    await pumpMidEntrance(tester);
    expect(entranceOf(tester).value, inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
  });

  // MUTATION (mobile-qa 2026-11-12): dropped
  // `_weekEntranceController?.dispose()` from the view's `dispose` → the
  // ticker mixin's "disposed with an active Ticker" assert fired and this
  // test went RED. Restored by cp.
  testWidgets('unmounting mid-entrance disposes the controller; a fresh '
      'mount plays its own entrance again', (WidgetTester tester) async {
    await mountUntilGrid(tester);
    final Animation<double> first = entranceOf(tester);
    await pumpMidEntrance(tester); // unmount while the ticker is active
    expect(first.status, AnimationStatus.forward, reason: 'fixture guard');

    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);

    await mountUntilGrid(tester);
    final Animation<double> second = entranceOf(tester);
    expect(identical(second, first), isFalse, reason: 'one per mount');
    await pumpMidEntrance(tester);
    expect(second.value, inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
  });

  // Once the entrance has completed, a column carries no entrance wrapper
  // at all — no FadeTransition (an opacity layer per column per frame)
  // inside the pager. MUTATION (2026-11-12): `_ColumnEntranceState.build`
  // ignoring `_done` → RED on column 2's fade. Restored.
  testWidgets('after the entrance completes the columns carry no '
      'entrance wrapper (no FadeTransition / SlideTransition)', (
    WidgetTester tester,
  ) async {
    await mountUntilGrid(tester);
    await tester.pumpAndSettle();
    expect(entranceOf(tester).status, AnimationStatus.completed);
    // fixed-wait-ok: well past the 750 ms entrance, on purpose.
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.byKey(WeekTimeGrid.columnKey(2)), findsOne);
    for (int day = 0; day < 7; day++) {
      if (find.byKey(WeekTimeGrid.columnKey(day)).evaluate().isEmpty) continue;
      expect(columnOpacity(tester, day), isNull, reason: 'column $day fade');
      expect(
        columnWrapper(day, SlideTransition),
        findsNothing,
        reason: 'column $day slide',
      );
    }
  });

  // The collapse is a MOVE, not a remount: the column subtree is reparented
  // through `_ColumnEntrance`'s GlobalKey, so its elements (and any state
  // below) survive. MUTATION (mobile-qa 2026-11-13): `KeyedSubtree` built
  // without `_childKey` → column 2's element was recreated on completion and
  // this went RED. Restored by cp.
  testWidgets('when the entrance completes the column is reparented, not '
      'remounted — its element survives the collapse', (
    WidgetTester tester,
  ) async {
    await mountUntilGrid(tester);
    await pumpMidEntrance(tester);
    expect(columnOpacity(tester, 2), isNotNull, reason: 'fixture: wrapped');
    final Element during = find
        .byKey(WeekTimeGrid.columnKey(2))
        .evaluate()
        .single;

    await tester.pumpAndSettle();
    expect(columnOpacity(tester, 2), isNull, reason: 'collapsed');
    final Element after = find
        .byKey(WeekTimeGrid.columnKey(2))
        .evaluate()
        .single;
    expect(identical(after, during), isTrue, reason: 'column 2 remounted');
    expect(after.mounted, isTrue);
  });

  // Mid-entrance the sliding column sits on its own layer — the
  // SlideTransition's child is a RepaintBoundary, so the rise re-composites
  // instead of repainting. MUTATION (2026-11-12): RepaintBoundary dropped
  // from the slide's child → RED. Restored.
  testWidgets('inside the column entrance a RepaintBoundary wraps '
      'the SlideTransition child', (WidgetTester tester) async {
    await mountUntilGrid(tester);
    await pumpMidEntrance(tester);
    expect(entranceOf(tester).value, inExclusiveRange(0, 1));

    final Finder slide = columnWrapper(2, SlideTransition);
    expect(slide, findsOne, reason: 'column 2 is mid-entrance');
    expect(tester.widget<SlideTransition>(slide).child, isA<RepaintBoundary>());
    await tester.pumpAndSettle();
  });
}
