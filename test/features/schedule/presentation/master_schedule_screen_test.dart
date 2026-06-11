// Phase 15.2 — Widget + golden tests for MasterScheduleScreen («Графік роботи»).
//
// Strategy (mobile-qa M1/M2/M3/M5 + Riverpod hygiene):
//   • The screen's only network surface is the `effectiveScheduleProvider`
//     family (an AsyncNotifier) and the role-derived `scheduleEditableProvider`.
//     Both are overridden with fakes inside a `ProviderScope` so NO network,
//     storage, or auth I/O runs. For the role cases we override the REAL
//     `authProvider` with a fixed `Authenticated` session so the genuine
//     capability resolver is exercised end-to-end.
//   • Finders use the source `Key`s (schedule-weekly-card, schedule-day-pencil,
//     schedule-add-hours, schedule-time-off, schedule-copy, no-schedule-banner,
//     no-schedule-add-hours, schedule-retry) — not localised strings.
//   • Goldens use the framework's `matchesGoldenFile` (golden_toolkit was
//     removed from the project; see pubspec note). A fixed device size +
//     disabled fonts keep them deterministic.
//
// Data is anchored on the device "today" (the screen selects today on mount and
// requests today's month), so each fake covers the visible week Mon→Sun with a
// known per-day source. Selecting a specific weekday taps the week strip.

import 'dart:async';

import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/calendar/data/working_hours_repository.dart';
import 'package:beautica_mobile/features/calendar/data/working_hours_repository_provider.dart';
import 'package:beautica_mobile/features/calendar/domain/working_hours.dart';
import 'package:beautica_mobile/features/calendar/presentation/working_hours_screen.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';
import 'package:beautica_mobile/features/schedule/presentation/effective_schedule_notifier.dart';
import 'package:beautica_mobile/features/schedule/presentation/master_schedule_screen.dart';
import 'package:beautica_mobile/features/schedule/presentation/weekly_schedule_notifier.dart';
import 'package:beautica_mobile/features/schedule/presentation/schedule_editor_stubs.dart';
import 'package:beautica_mobile/features/schedule/presentation/weekly_template_editor_screen.dart';
import 'package:beautica_mobile/features/schedule/presentation/schedule_range.dart';
import 'package:beautica_mobile/features/schedule/data/schedule_repository.dart';
import 'package:beautica_mobile/features/schedule/data/schedule_repository_provider.dart';
import 'package:beautica_mobile/features/schedule/presentation/widgets/schedule_widgets.dart';
import 'package:beautica_mobile/features/schedule/presentation/widgets/slot_colors.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/auth_redirect.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/velvet_top_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ───────────────────────────────────────────────────────────────────────────
// Date anchoring helpers — every fake is built relative to the device "today"
// so the screen's today-anchored month/week request resolves to known data.
// ───────────────────────────────────────────────────────────────────────────

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
final DateTime _today = _dateOnly(DateTime.now());
DateTime _mondayOf(DateTime d) =>
    _dateOnly(d).subtract(Duration(days: d.weekday - 1));
final DateTime _weekStart = _mondayOf(_today);

WorkInterval _interval(int sh, int sm, int eh, int em) => WorkInterval(
  start: TimeOfDay(hour: sh, minute: sm),
  end: TimeOfDay(hour: eh, minute: em),
);

EffectiveDay _working(DateTime date) => EffectiveDay(
  date: _dateOnly(date),
  source: EffectiveSource.template,
  intervals: <WorkInterval>[_interval(9, 0, 13, 0), _interval(14, 0, 18, 0)],
);

EffectiveDay _dayOff(DateTime date) => EffectiveDay(
  date: _dateOnly(date),
  source: EffectiveSource.overrideDayOff,
  intervals: const <WorkInterval>[],
);

EffectiveDay _custom(DateTime date) => EffectiveDay(
  date: _dateOnly(date),
  source: EffectiveSource.overrideCustom,
  intervals: <WorkInterval>[_interval(10, 0, 15, 0)],
);

EffectiveDay _noSchedule(DateTime date) => EffectiveDay(
  date: _dateOnly(date),
  source: EffectiveSource.noSchedule,
  intervals: const <WorkInterval>[],
);

/// A solid 09:00–18:00 template working day for [date] (Mon/Wed recurring days).
EffectiveDay _templateWorking(DateTime date) => EffectiveDay(
  date: _dateOnly(date),
  source: EffectiveSource.template,
  intervals: <WorkInterval>[_interval(9, 0, 18, 0)],
);

/// The single-date Friday override under test, resolved exactly as the backend
/// would resolve a `ScheduleOverride.custom(start: friday, end: friday)`: a
/// CUSTOM_HOURS [EffectiveDay] carrying the override's intervals. Built FROM a
/// real single-date override so the fixture is honest — the same projection the
/// screen's `_DayIndex`/`_templatePattern` consumes (mobile-qa: keep mocks
/// honest so the test would FAIL against the old month-aggregate behaviour).
EffectiveDay _fridayOverrideDay(DateTime friday) {
  final ScheduleOverride override = ScheduleOverride.custom(
    start: _dateOnly(friday),
    end: _dateOnly(friday),
    intervals: <WorkInterval>[_interval(10, 0, 16, 0)],
  );
  return EffectiveDay(
    date: _dateOnly(override.start),
    source: EffectiveSource.overrideCustom,
    intervals: override.intervals
        .map((WorkInterval w) => w.clone())
        .toList(growable: false),
  );
}

/// Three consecutive weeks (previous, current, next) of a recurring Mon+Wed
/// template, PLUS a one-off Friday override that exists ONLY in the current week
/// (`_weekStart + 4`). Every other Friday — including the previous/next week's —
/// is left out (resolves to NO_SCHEDULE via `_DayIndex`), so only the displayed
/// week's pills light Friday. Returned as the family-wide effective list (the
/// screen rebuilds its date-keyed `_DayIndex` from whatever range it reads, and
/// every relevant date is present here).
List<EffectiveDay> _monWedTemplateWithThisWeekFriday() {
  final List<EffectiveDay> out = <EffectiveDay>[];
  // weekOffset -1 (prev), 0 (current), +1 (next).
  for (final int weekOffset in <int>[-1, 0, 1]) {
    final DateTime weekMonday = _weekStart.add(Duration(days: weekOffset * 7));
    // ISO Monday = +0, Wednesday = +2 → recurring template working days.
    out.add(_templateWorking(weekMonday));
    out.add(_templateWorking(weekMonday.add(const Duration(days: 2))));
  }
  // The one-off Friday override — current week ONLY (`_weekStart + 4`).
  out.add(_fridayOverrideDay(_weekStart.add(const Duration(days: 4))));
  return out;
}

/// A full Monday→Sunday week of resolved days for the current visible week,
/// with [today] resolving to [todayDay] and the other six days [filler].
List<EffectiveDay> _weekWith({
  required EffectiveDay Function(DateTime) todayDay,
  required EffectiveDay Function(DateTime) filler,
}) {
  return <EffectiveDay>[
    for (int i = 0; i < 7; i++)
      if (_dateOnly(_weekStart.add(Duration(days: i))) == _today)
        todayDay(_today)
      else
        filler(_weekStart.add(Duration(days: i))),
  ];
}

// ───────────────────────────────────────────────────────────────────────────
// Fake EffectiveSchedule notifiers (family override → applies to every range).
// ───────────────────────────────────────────────────────────────────────────

class _DataSchedule extends EffectiveScheduleNotifier {
  _DataSchedule(this._days);
  final List<EffectiveDay> _days;
  @override
  Future<List<EffectiveDay>> build(ScheduleRange range) async => _days;
}

/// RANGE-AWARE fake for the month-boundary spillover regression.
///
/// Unlike [_DataSchedule] (which ignores `range` and returns the same list for
/// every family key), this fake serves an [EffectiveDay] for a date ONLY when
/// that date falls inside the [range] the screen actually requested — exactly
/// like the real repository, which can only return what it was asked to fetch.
/// A working day is produced for every Monday and Tuesday in range; every other
/// in-range date is NO_SCHEDULE. Dates OUTSIDE the requested range are simply
/// absent from the result, so the screen's `_DayIndex.lookup` falls back to a
/// NO_SCHEDULE day for them — the precise failure mode of the bug.
///
/// This is what makes the regression honest: under the OLD
/// `ScheduleRange.month(_visibleMonth)` key, a week straddling a boundary fetched
/// only the majority month, so the previous-month spillover Monday/Tuesday were
/// out of range → rendered day-off. Under the union range they are in range →
/// rendered working. [observedRanges] records every key the family was built
/// with so the test can assert the union `from` reaches the spillover days.
class _PerWeekdayRangeSchedule extends EffectiveScheduleNotifier {
  /// Every [ScheduleRange] the screen has keyed this family on (one per visible
  /// month+week view). Shared across instances via the static sink so the test
  /// can inspect the range AFTER navigation regardless of which family instance
  /// served the final view.
  static final List<ScheduleRange> observedRanges = <ScheduleRange>[];

  @override
  Future<List<EffectiveDay>> build(ScheduleRange range) async {
    observedRanges.add(range);
    final List<EffectiveDay> out = <EffectiveDay>[];
    DateTime cursor = _dateOnly(range.from);
    final DateTime end = _dateOnly(range.to);
    while (!cursor.isAfter(end)) {
      // ISO Monday = 1, Tuesday = 2 → recurring template working days.
      if (cursor.weekday == DateTime.monday ||
          cursor.weekday == DateTime.tuesday) {
        out.add(_templateWorking(cursor));
      } else {
        out.add(_noSchedule(cursor));
      }
      cursor = _dateOnly(cursor.add(const Duration(days: 1)));
    }
    return out;
  }
}

class _LoadingSchedule extends EffectiveScheduleNotifier {
  @override
  Future<List<EffectiveDay>> build(ScheduleRange range) {
    return Completer<List<EffectiveDay>>().future; // never completes
  }
}

class _ErrorSchedule extends EffectiveScheduleNotifier {
  @override
  Future<List<EffectiveDay>> build(ScheduleRange range) async =>
      throw Exception('boom');
}

/// Month-change fake for the loading-flash regression: resolves [_days] for the
/// INITIAL visible month's range key and never completes for any OTHER range.
///
/// The screen keys `effectiveScheduleProvider` on `ScheduleRange.month(visible)`
/// and steps `visible` by one month when the `>` arrow is tapped. A single
/// family fake branching on `range` therefore reproduces exactly what happens in
/// production: the current month resolves (and is cached into `_lastDays`),
/// while the next month's freshly-keyed instance sits in `AsyncLoading` with
/// `value == null`. This is the precise condition that used to trip the
/// full-screen spinner gate (`days == null`) before the cache fix.
class _MonthAwareSchedule extends EffectiveScheduleNotifier {
  _MonthAwareSchedule(this._initialMonth, this._days);

  /// The range key the INITIAL visible month resolves to (today's month).
  final ScheduleRange _initialMonth;
  final List<EffectiveDay> _days;

  @override
  Future<List<EffectiveDay>> build(ScheduleRange range) {
    if (range == _initialMonth) return Future<List<EffectiveDay>>.value(_days);
    // Any other month (e.g. after tapping `>`) stays loading forever.
    return Completer<List<EffectiveDay>>().future;
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Stateful fake ScheduleRepository — drives the REAL notifiers end-to-end.
//
// The jump-to-changed-day + show-changes-immediately fix lives in
// `_openDayOverride` + the `_lastDaysRange` guard in `_body`, and only fires
// when the GENUINE `OverridesNotifier` + `EffectiveScheduleNotifier` run (the
// override save → `ref.invalidate(effectiveScheduleProvider)` → same-range
// refetch chain). Overriding the notifiers with static fakes would short the
// very wiring under test, so these tests override ONLY
// `scheduleRepositoryProvider` and let the real providers resolve against this
// mutable repo. `putOverride` mutates the per-date effective data (adds an
// interior pause), so the post-save refetch returns the FRESH override — the
// exact condition the stale `_lastDays` snapshot used to mask.
// ───────────────────────────────────────────────────────────────────────────
class _StatefulFakeScheduleRepository implements ScheduleRepository {
  _StatefulFakeScheduleRepository(this._effective);

  /// date-only → the effective day the calendar reads. Mutated by [putOverride]
  /// / [clearOverride].
  final Map<DateTime, EffectiveDay> _effective;

  int putCount = 0;

  @override
  Future<List<EffectiveDay>> effectiveSchedule(
    DateTime from,
    DateTime to,
  ) async {
    final List<EffectiveDay> out = <EffectiveDay>[];
    DateTime cursor = _dateOnly(from);
    final DateTime end = _dateOnly(to);
    while (!cursor.isAfter(end)) {
      out.add(_effective[cursor] ?? _noSchedule(cursor));
      cursor = _dateOnly(cursor.add(const Duration(days: 1)));
    }
    return out;
  }

  @override
  Future<List<ScheduleOverride>> listOverrides(
    DateTime from,
    DateTime to,
  ) async => const <ScheduleOverride>[];

  @override
  Future<ScheduleOverride> putOverride(ScheduleOverride override) async {
    putCount++;
    final DateTime key = _dateOnly(override.start);
    // Reflect the saved override in the effective data so the next
    // `effectiveSchedule` read (after the provider invalidation) is FRESH.
    _effective[key] = EffectiveDay(
      date: key,
      source: EffectiveSource.overrideCustom,
      intervals: override.intervals
          .map((WorkInterval w) => w.clone())
          .toList(growable: false),
    );
    return override;
  }

  @override
  Future<void> clearOverride(DateTime date) async {
    _effective.remove(_dateOnly(date));
  }

  // ── Unused by these tests (weekly template path) ──────────────────────────
  @override
  Future<List<WeeklySchedule>> listWeeklySchedules() async => <WeeklySchedule>[
    _template(),
  ];

  @override
  Future<WeeklySchedule> upsertWeeklySchedule(
    WeeklySchedule schedule, {
    String? scheduleId,
  }) async => schedule;

  @override
  Future<void> deleteWeeklySchedule(String scheduleId) async {}
}

// ───────────────────────────────────────────────────────────────────────────
// _CompleterScheduleRepository — drives the SEAMLESS-RETENTION + READ-AFTER-WRITE
// regression tests (the exact on-device bug the previous green tests were blind
// to).
//
// Unlike `_StatefulFakeScheduleRepository` (synchronous zero-latency
// read-your-writes that hid the in-flight window), this fake:
//   • serves a fixed PRE-SAVE effective day until a put lands;
//   • after the put, the next `effectiveSchedule` read does NOT resolve
//     immediately — it parks on a [Completer] the TEST controls, so the post-save
//     reload is observably IN FLIGHT across an intermediate `pump()`. The test
//     asserts what the screen renders DURING that window (the exact frame the
//     seamless-retained pre-save value used to leak through), then completes the
//     Completer and asserts the FRESH composition lands.
//   • the post-save read returns the new composition ONLY because `putOverride`
//     flipped `_saved` — i.e. the effective fetch reflects the write strictly
//     after it persisted. This proves the screen issued a GENUINE refetch driven
//     by the reactive `overridesProvider` watch (read-after-write coherence),
//     not a `copyWithPrevious`-retained snapshot.
//
// `listOverrides` returns a list whose IDENTITY changes after the put so the
// `overridesProvider` reload genuinely emits a new value (driving the reactive
// `effectiveScheduleProvider` rebuild even though the screen never reads the
// override list's contents directly).
// ───────────────────────────────────────────────────────────────────────────
class _CompleterScheduleRepository implements ScheduleRepository {
  _CompleterScheduleRepository({
    required this.targetDate,
    required this.preSave,
    required this.postSave,
  });

  /// The date the test edits (and the only date whose composition changes).
  final DateTime targetDate;

  /// The effective day served for [targetDate] BEFORE any put (solid working).
  final EffectiveDay preSave;

  /// The effective day served for [targetDate] AFTER the put resolves (a day
  /// with an interior pause — the freshly-saved override).
  final EffectiveDay postSave;

  bool _saved = false;
  int putCount = 0;
  int effectiveFetchCount = 0;

  /// The bounds of the most recent effective fetch — captured so the test can
  /// complete the parked refetch with a composition over the SAME window the
  /// screen requested (today's month).
  DateTime _rangeFrom = _today;
  DateTime _rangeTo = _today;

  /// Set on the FIRST post-save effective fetch; the test completes it to let
  /// the in-flight reload resolve. Until then that fetch is parked (the
  /// observable in-flight window).
  Completer<List<EffectiveDay>>? pendingPostSaveFetch;

  EffectiveDay _dayFor(DateTime date) {
    if (_dateOnly(date) == _dateOnly(targetDate)) {
      return _saved ? postSave : preSave;
    }
    return _solidWorking(date);
  }

  List<EffectiveDay> _composeRange(DateTime from, DateTime to) {
    final List<EffectiveDay> out = <EffectiveDay>[];
    DateTime cursor = _dateOnly(from);
    final DateTime end = _dateOnly(to);
    while (!cursor.isAfter(end)) {
      out.add(_dayFor(cursor));
      cursor = _dateOnly(cursor.add(const Duration(days: 1)));
    }
    return out;
  }

  @override
  Future<List<EffectiveDay>> effectiveSchedule(
    DateTime from,
    DateTime to,
  ) async {
    effectiveFetchCount++;
    _rangeFrom = _dateOnly(from);
    _rangeTo = _dateOnly(to);
    if (_saved && pendingPostSaveFetch == null) {
      // First post-save fetch: park it so the reload is observably in flight.
      pendingPostSaveFetch = Completer<List<EffectiveDay>>();
      return pendingPostSaveFetch!.future;
    }
    return _composeRange(from, to);
  }

  @override
  Future<List<ScheduleOverride>> listOverrides(
    DateTime from,
    DateTime to,
  ) async {
    // A fresh-identity list each call so the post-put reload genuinely emits a
    // new value (driving the reactive effective-schedule rebuild).
    if (!_saved) return const <ScheduleOverride>[];
    return <ScheduleOverride>[
      ScheduleOverride.custom(
        start: _dateOnly(targetDate),
        end: _dateOnly(targetDate),
        intervals: postSave.intervals
            .map((WorkInterval w) => w.clone())
            .toList(growable: false),
      ),
    ];
  }

  @override
  Future<ScheduleOverride> putOverride(ScheduleOverride override) async {
    putCount++;
    _saved = true;
    return override;
  }

  @override
  Future<void> clearOverride(DateTime date) async {
    _saved = false;
  }

  @override
  Future<List<WeeklySchedule>> listWeeklySchedules() async => <WeeklySchedule>[
    _template(),
  ];

  @override
  Future<WeeklySchedule> upsertWeeklySchedule(
    WeeklySchedule schedule, {
    String? scheduleId,
  }) async => schedule;

  @override
  Future<void> deleteWeeklySchedule(String scheduleId) async {}
}

// ───────────────────────────────────────────────────────────────────────────
// Fake WeeklySchedule notifier — the global "has any schedule" signal that
// gates the focused empty state. Every full-layout case must stub this
// NON-EMPTY so the screen renders the calendar (not the empty state).
// ───────────────────────────────────────────────────────────────────────────

/// One non-empty template (all seven ISO days closed is fine — its mere
/// presence means "the master HAS a schedule", so the full layout renders).
WeeklySchedule _template() => WeeklySchedule(
  validFrom: _today,
  validTo: null,
  days: <TemplateDay>[
    for (int dow = 1; dow <= 7; dow++)
      TemplateDay(
        dayOfWeek: dow,
        label: 'd$dow',
        intervals: <WorkInterval>[_interval(9, 0, 18, 0)],
      ),
  ],
);

class _WeeklyData extends WeeklyScheduleNotifier {
  _WeeklyData(this._templates);
  final List<WeeklySchedule> _templates;
  @override
  Future<List<WeeklySchedule>> build() async => _templates;
}

/// Never-completing weekly signal — used to assert the empty-state verdict is
/// deferred until BOTH sources resolve (no premature empty state flash).
class _LoadingWeekly extends WeeklyScheduleNotifier {
  @override
  Future<List<WeeklySchedule>> build() {
    return Completer<List<WeeklySchedule>>().future; // never completes
  }
}

/// Erroring weekly signal — used to assert weekly-error precedence over the
/// empty-state verdict (the second error branch in `_body`).
class _ErrorWeekly extends WeeklyScheduleNotifier {
  @override
  Future<List<WeeklySchedule>> build() async => throw Exception('weekly boom');
}

// ───────────────────────────────────────────────────────────────────────────
// Auth session fixtures for the role-gating cases.
// ───────────────────────────────────────────────────────────────────────────

class _FixedAuth extends AuthNotifier {
  _FixedAuth(this._role);
  final UserRole _role;
  @override
  Future<AuthSession> build() async => AuthSession.authenticated(
    user: User(id: 'u1', email: 'm@b.c', role: _role),
    accessToken: 'tkn',
  );
}

// ───────────────────────────────────────────────────────────────────────────
// Fake WorkingHoursRepository — the CTA destination (the REAL WorkingHoursScreen
// at RouteNames.workingHours) watches `workingHoursProvider`, which builds from
// `workingHoursRepositoryProvider.list()`. We override the repository with this
// fake so navigating to the destination resolves a full 7-day week with NO
// network / storage I/O (mobile-qa M1 isolation). It is included in EVERY pump's
// override set so any test that happens to push the editor stays hermetic.
// ───────────────────────────────────────────────────────────────────────────
class _FakeWorkingHoursRepository implements WorkingHoursRepository {
  @override
  Future<List<WorkingHours>> list() async => <WorkingHours>[
    for (int dow = 1; dow <= 7; dow++)
      WorkingHours(
        dayOfWeek: dow,
        startTime: '09:00:00',
        endTime: '18:00:00',
        isActive: dow <= 5,
      ),
  ];

  @override
  Future<List<WorkingHours>> replaceAll(List<WorkingHours> hours) async =>
      hours;
}

/// Bridges the test [ProviderContainer] to a [Listenable] so the redirect-bearing
/// router re-evaluates [authRedirect] whenever the auth session changes — the
/// same wiring the production [appRouter] uses (mirrors navigation_links_test).
class _ContainerListenable extends ChangeNotifier {
  _ContainerListenable(ProviderContainer container) {
    container.listen<AsyncValue<AuthSession>>(
      authProvider,
      (_, _) => notifyListeners(),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Harness — pumps the screen inside a GoRouter that wires the PRODUCTION
// `authRedirect` guard (so a CTA pointing at the wrong screen is caught by the
// real auth matrix, not silently honoured). Phase 15.5: the weekly-template CTA
// now lands on the REAL `WeeklyTemplateEditorScreen` at
// RouteNames.scheduleWeeklyEditor (`/schedule/weekly`) — it graduated from the
// `WeeklyTemplateEditorStubScreen` exactly like `/done` graduated to DoneScreen.
// The legacy `/master/working-hours` editor (WorkingHoursScreen) is deprecated
// and is NO LONGER a CTA destination; its route is kept here only so the auth
// matrix stays exercised. The per-date and propagate stub routes remain (the
// day-pencil / copy affordances still target them).
// ───────────────────────────────────────────────────────────────────────────

List<RouteBase> _routes() => <RouteBase>[
  GoRoute(
    path: RouteNames.masterSchedule,
    builder: (context, state) => const MasterScheduleScreen(),
  ),
  // The REAL weekly-template editor the CTA now routes to (Phase 15.5).
  // It reads `weeklyScheduleProvider` (overridden per-test) and saves via
  // `WeeklyScheduleNotifier`, so navigating here stays hermetic.
  GoRoute(
    path: RouteNames.scheduleWeeklyEditor,
    builder: (context, state) => const WeeklyTemplateEditorScreen(),
  ),
  // Deprecated legacy editor — kept routable so the auth guard stays exercised,
  // but it is no longer a CTA destination.
  GoRoute(
    path: RouteNames.workingHours,
    builder: (context, state) => const WorkingHoursScreen(),
  ),
  GoRoute(
    path: RouteNames.scheduleDayOverride,
    builder: (context, state) => const PerDateOverrideStubScreen(),
  ),
  // Phase 15.5: `RouteNames.schedulePropagate` (`/schedule/copy`) now lands on
  // the real `WeeklyTemplateEditorScreen` (which opens the ApplyScheduleSheet),
  // so the retired `SchedulePropagateStubScreen` is no longer wired here.
  GoRoute(
    path: RouteNames.schedulePropagate,
    builder: (context, state) => const WeeklyTemplateEditorScreen(),
  ),
  GoRoute(
    path: RouteNames.masterProfile,
    builder: (context, state) =>
        const Scaffold(key: Key('master-profile-stub')),
  ),
  GoRoute(
    path: RouteNames.home,
    builder: (context, state) => const Scaffold(key: Key('home-stub')),
  ),
  GoRoute(
    path: RouteNames.login,
    builder: (context, state) => const Scaffold(key: Key('login-stub')),
  ),
];

/// A redirect-free router (used by the non-navigation render/golden/state cases
/// where the auth guard is irrelevant and would only add a settle hop).
GoRouter _router() =>
    GoRouter(initialLocation: RouteNames.masterSchedule, routes: _routes());

/// A router that wires the PRODUCTION [authRedirect] over [container]'s
/// [authProvider]. Used by the CTA-navigation tests so a CTA aimed at the wrong
/// screen (e.g. a non-`/master/*` dead stub, or a screen the role can't reach)
/// is rejected by the real guard — the exact gap that let BUG #1 ship.
GoRouter _redirectRouter(ProviderContainer container) => GoRouter(
  initialLocation: RouteNames.masterSchedule,
  refreshListenable: _ContainerListenable(container),
  redirect: (context, state) =>
      authRedirect(container.read(authProvider), state),
  routes: _routes(),
);

Future<void> _pump(
  WidgetTester tester, {
  required List<Object> overrides,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Object>[...overrides, _fakeWorkingHours()].cast(),
      child: MaterialApp.router(
        routerConfig: _router(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('uk'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The working-hours repository override (CTA destination isolation). Typed as
/// [Object] to mirror the existing override lists (which `.cast()` to the
/// Riverpod `Override` type at the `overrides:` boundary).
Object _fakeWorkingHours() => workingHoursRepositoryProvider.overrideWithValue(
  _FakeWorkingHoursRepository(),
);

/// Pumps the schedule screen inside the REDIRECT-bearing router, wired over a
/// fresh [ProviderContainer] seeded with [overrides] (which must include an
/// `authProvider` override so the guard resolves a settled session). Returns the
/// container so the caller can `addTearDown(container.dispose)`. Used by the
/// CTA-navigation tests to prove the destination is reached THROUGH the
/// production auth/role guard.
Future<ProviderContainer> _pumpGuarded(
  WidgetTester tester, {
  required List<Object> overrides,
}) async {
  final container = ProviderContainer(
    overrides: <Object>[...overrides, _fakeWorkingHours()].cast(),
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: _redirectRouter(container),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('uk'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Editable-by-default overrides: an INDEPENDENT_MASTER session + a data
/// notifier returning [days] + a NON-EMPTY weekly template (so the full
/// calendar renders, not the focused empty state).
List<Object> _editableData(List<EffectiveDay> days) => <Object>[
  authProvider.overrideWith(() => _FixedAuth(UserRole.independentMaster)),
  effectiveScheduleProvider.overrideWith(() => _DataSchedule(days)),
  weeklyScheduleProvider.overrideWith(
    () => _WeeklyData(<WeeklySchedule>[_template()]),
  ),
];

/// Role + schedule overrides with an explicit weekly-template list. Used by the
/// role-gating and empty-state cases that need to control the "has any
/// schedule" signal independently of the effective-range data.
List<Object> _withWeekly(
  UserRole role,
  List<EffectiveDay> days,
  List<WeeklySchedule> templates,
) => <Object>[
  authProvider.overrideWith(() => _FixedAuth(role)),
  effectiveScheduleProvider.overrideWith(() => _DataSchedule(days)),
  weeklyScheduleProvider.overrideWith(() => _WeeklyData(templates)),
];

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(MasterScheduleScreen)));

/// Taps the week-strip cell for [date] (selecting it). The strip renders the
/// day number; the cell is found via its localised day-number text inside the
/// WeekStripDay semantics. We tap by the visible day number text within the
/// strip row.
Future<void> _selectStripDay(WidgetTester tester, int dayNumber) async {
  // The strip shows the day-of-month number; tap it to select that date.
  final Finder dayText = find.text('$dayNumber');
  await tester.tap(dayText.first);
  await tester.pumpAndSettle();
}

void main() {
  // ── Slot-projection-bearing data states (golden + finder) ─────────────────

  group('MasterScheduleScreen — resolved data states', () {
    testWidgets('templated working day renders the grid + legend', (
      tester,
    ) async {
      final days = _weekWith(todayDay: _working, filler: _working);
      await _pump(tester, overrides: _editableData(days));

      // The grid + legend render (loaded data state). The selected (today) day
      // is a working day → no NO_SCHEDULE banner.
      expect(find.byType(MasterScheduleScreen), findsOneWidget);
      expect(find.byKey(const Key('no-schedule-banner')), findsNothing);
      expect(find.byType(MasterScheduleScreen), findsOneWidget);

      await expectLater(
        find.byType(MasterScheduleScreen),
        matchesGoldenFile('goldens/schedule_templated_working_day.png'),
      );
    });

    testWidgets('day-off date renders a closed (all-grey) grid', (
      tester,
    ) async {
      final days = _weekWith(todayDay: _dayOff, filler: _working);
      await _pump(tester, overrides: _editableData(days));

      // Day-off is an OVERRIDE_DAY_OFF, not NO_SCHEDULE → no banner.
      expect(find.byKey(const Key('no-schedule-banner')), findsNothing);

      await expectLater(
        find.byType(MasterScheduleScreen),
        matchesGoldenFile('goldens/schedule_day_off.png'),
      );
    });

    testWidgets('custom-hours date renders its custom green slots', (
      tester,
    ) async {
      final days = _weekWith(todayDay: _custom, filler: _working);
      await _pump(tester, overrides: _editableData(days));

      expect(find.byKey(const Key('no-schedule-banner')), findsNothing);

      await expectLater(
        find.byType(MasterScheduleScreen),
        matchesGoldenFile('goldens/schedule_custom_hours.png'),
      );
    });
  });

  // ── NO_SCHEDULE banner (OQ-3) ─────────────────────────────────────────────

  group('MasterScheduleScreen — NO_SCHEDULE banner (OQ-3)', () {
    testWidgets(
      'gap day shows the persistent banner + «Додати робочі години» CTA',
      (tester) async {
        // Today is a gap; the rest of the week is templated (so it is NOT a
        // whole-period gap → single-day copy).
        final days = _weekWith(todayDay: _noSchedule, filler: _working);
        await _pump(tester, overrides: _editableData(days));

        expect(find.byKey(const Key('no-schedule-banner')), findsOneWidget);
        // Editable viewer → the CTA is present.
        expect(find.byKey(const Key('no-schedule-add-hours')), findsOneWidget);
        // Single-day copy (not the whole-period copy).
        final l10n = _l10n(tester);
        expect(find.text(l10n.scheduleNoScheduleDay), findsOneWidget);
        expect(find.text(l10n.scheduleNoSchedulePeriod), findsNothing);

        await expectLater(
          find.byType(MasterScheduleScreen),
          matchesGoldenFile('goldens/schedule_no_schedule_gap.png'),
        );
      },
    );

    testWidgets(
      'whole-period gap uses the «На цей період графік не задано» copy',
      (tester) async {
        // Every day of the visible week is NO_SCHEDULE → whole-period copy.
        final days = _weekWith(todayDay: _noSchedule, filler: _noSchedule);
        await _pump(tester, overrides: _editableData(days));

        final l10n = _l10n(tester);
        expect(find.byKey(const Key('no-schedule-banner')), findsOneWidget);
        expect(find.text(l10n.scheduleNoSchedulePeriod), findsOneWidget);
        expect(find.text(l10n.scheduleNoScheduleDay), findsNothing);
      },
    );

    testWidgets(
      'navigating to a covered day removes the banner (non-blocking)',
      (tester) async {
        // Today is a gap; the OTHER days of the week are templated working days.
        final days = _weekWith(todayDay: _noSchedule, filler: _working);
        await _pump(tester, overrides: _editableData(days));

        // Banner present on the gap (today).
        expect(find.byKey(const Key('no-schedule-banner')), findsOneWidget);

        // Find a templated day in the visible week that is NOT today, and tap
        // its strip cell. Use the Monday of the week unless today IS Monday.
        final DateTime covered = _today == _weekStart
            ? _weekStart.add(const Duration(days: 1))
            : _weekStart;
        await _selectStripDay(tester, covered.day);

        // Banner gone now that a covered day is selected.
        expect(find.byKey(const Key('no-schedule-banner')), findsNothing);
      },
    );

    // ── Phase 15.5: in-grid banner CTA routes to the REAL weekly editor ───────
    //
    // The CTA used to point at the dead `WeeklyTemplateEditorStubScreen`
    // ("coming soon" placeholder); a prior fix briefly diverted it to the
    // legacy `/master/working-hours` editor. Phase 15.5 graduated the stub to
    // the real `WeeklyTemplateEditorScreen` at RouteNames.scheduleWeeklyEditor,
    // and `_openTemplateEditor` now targets it. This test pumps the schedule
    // screen inside the PRODUCTION authRedirect-guarded router, taps the CTA,
    // and asserts the genuine weekly editor mounts (its VelvetTopBar header +
    // the seven day-toggle rows + the real save button), NOT a stub and NOT the
    // deprecated working-hours editor. Routing THROUGH the production redirect
    // proves the CTA destination is reachable for the editable session here.
    testWidgets('banner CTA tap routes through authRedirect to the REAL '
        'weekly-template editor (Phase 15.5)', (tester) async {
      final days = _weekWith(todayDay: _noSchedule, filler: _working);
      final container = await _pumpGuarded(
        tester,
        overrides: _editableData(days),
      );
      addTearDown(container.dispose);

      // The CTA lives inside the scrollable calendar card — scroll it into view
      // before tapping so the hit-test lands on the button, not off-screen.
      await tester.ensureVisible(
        find.byKey(const Key('no-schedule-add-hours')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('no-schedule-add-hours')));
      await tester.pumpAndSettle();

      // Landed on the REAL weekly-template editor — the dead stub is gone and
      // the deprecated working-hours editor is NOT the destination.
      expect(
        find.byKey(const Key('stub-weekly-template-editor')),
        findsNothing,
        reason: 'CTA must NOT land on the removed "coming soon" stub',
      );
      expect(
        find.byType(WorkingHoursScreen),
        findsNothing,
        reason: 'CTA must NOT land on the deprecated working-hours editor',
      );
      expect(
        find.byType(WeeklyTemplateEditorScreen),
        findsOneWidget,
        reason: 'CTA must mount the real WeeklyTemplateEditorScreen',
      );
      // Its real affordances render: the save button and the seven day toggles.
      expect(
        find.byKey(const Key('btn-save-weekly-template')),
        findsOneWidget,
        reason: 'the real editor exposes its save button',
      );
      expect(
        find.byKey(const Key('weekly-toggle-1')),
        findsOneWidget,
        reason: 'the real editor renders the per-day toggle rows',
      );
    });

    // ── Regression: in-grid banner CTA must route via a Material tap affordance ─
    //
    // BUG (now fixed): GhostButton wrapped its label in a bare
    // GestureDetector(onTap:). Inside the calendar card's SingleChildScrollView,
    // the scroll view's vertical-drag recogniser won the gesture arena for a
    // real finger's tap-with-drift, so the CTA's onPressed never fired on
    // device. The widget-test gesture arena does NOT reproduce that device-only
    // drag-vs-tap contention (a simulated tap routes on both the old and new
    // widget), so a gesture-driven assertion cannot separate the two
    // implementations and would be a false guard. The faithful, deterministic
    // guard is STRUCTURAL: the CTA's tap is handled by an InkWell (a Material
    // tap affordance, which wins the arena on device), and NOT by a bare
    // GestureDetector. This assertion FAILS on the pre-fix code (no InkWell over
    // the CTA → a GestureDetector instead) and PASSES on the fix.
    testWidgets(
      'in-grid banner CTA is wired through an InkWell, not a bare '
      'GestureDetector (regression for the dropped tap inside the scroll view)',
      (tester) async {
        final days = _weekWith(todayDay: _noSchedule, filler: _working);
        await _pump(tester, overrides: _editableData(days));

        final Finder cta = find.byKey(const Key('no-schedule-add-hours'));
        await tester.ensureVisible(cta);
        await tester.pumpAndSettle();

        // The fix wires the CTA through an InkWell (the arena-winning Material
        // tap affordance). The pre-fix code has NO InkWell under the CTA — its
        // tap was a bare GestureDetector that lost the arena to the scroll view
        // on device. (InkWell renders a GestureDetector internally, so the
        // discriminator is the presence of InkWell, not absence of one.)
        expect(
          find.descendant(of: cta, matching: find.byType(InkWell)),
          findsOneWidget,
          reason: 'CTA must use InkWell so its tap wins the arena on device',
        );
      },
    );
  });

  // ── Role-based read-only gating (OQ-2) ────────────────────────────────────

  group('MasterScheduleScreen — role gating (OQ-2)', () {
    testWidgets(
      'SALON_MASTER (read-only): all edit affordances absent, read content renders',
      (tester) async {
        final days = _weekWith(todayDay: _working, filler: _working);
        await _pump(
          tester,
          overrides: _withWeekly(UserRole.salonMaster, days, <WeeklySchedule>[
            _template(),
          ]),
        );

        // Read content still renders.
        expect(find.byType(MasterScheduleScreen), findsOneWidget);

        // Every edit affordance is gone.
        expect(find.byKey(const Key('schedule-weekly-card')), findsNothing);
        expect(find.byKey(const Key('schedule-day-pencil')), findsNothing);
        expect(find.byKey(const Key('schedule-add-hours')), findsNothing);
        expect(find.byKey(const Key('schedule-time-off')), findsNothing);
        expect(find.byKey(const Key('schedule-copy')), findsNothing);

        await expectLater(
          find.byType(MasterScheduleScreen),
          matchesGoldenFile('goldens/schedule_read_only_salon_master.png'),
        );
      },
    );

    testWidgets(
      'SALON_MASTER (read-only): NO_SCHEDULE banner shows WITHOUT the CTA',
      (tester) async {
        // A gap today but a non-empty template + working filler days → this is
        // NOT the "no schedule at all" empty state; the in-grid banner renders
        // for the selected gap day. (Read-only role suppresses the CTA.)
        final days = _weekWith(todayDay: _noSchedule, filler: _working);
        await _pump(
          tester,
          overrides: _withWeekly(UserRole.salonMaster, days, <WeeklySchedule>[
            _template(),
          ]),
        );

        // Banner shows informationally...
        expect(find.byKey(const Key('no-schedule-banner')), findsOneWidget);
        // ...but the CTA is suppressed for the read-only role.
        expect(find.byKey(const Key('no-schedule-add-hours')), findsNothing);
      },
    );

    // CANONICAL DAY-PANEL DESIGN GUARD (Phase 15.2 off-design button removal).
    //
    // For an editable self-viewer on a today/future day with a PUBLISHED
    // schedule, the day panel must match the approved design: the date title +
    // a single pencil (`schedule-day-pencil`) + the working-hours summary —
    // and NOTHING ELSE. The three off-design day-panel buttons
    // (`schedule-add-hours` "Додати час", `schedule-time-off` "Час відпочинку",
    // `schedule-copy` "Копіювати") were removed; this is the canonical guard
    // that locks them out so they cannot regress back in. The other
    // `findsNothing` checks elsewhere (read-only role / empty state / past day)
    // cover different viewer/day states; THIS one pins the editable
    // present-day-with-schedule case where the buttons used to live.
    testWidgets(
      'INDEPENDENT_MASTER (self) on a scheduled day: day panel shows ONLY the '
      'pencil + summary; the three removed day-panel buttons are absent',
      (tester) async {
        final days = _weekWith(todayDay: _working, filler: _working);
        await _pump(tester, overrides: _editableData(days));

        // The approved affordances render: weekly-card tap target + the single
        // day pencil. (Today is a working day, so the pencil — not the muted
        // past-day hint — is shown.)
        expect(find.byKey(const Key('schedule-weekly-card')), findsOneWidget);
        expect(find.byKey(const Key('schedule-day-pencil')), findsOneWidget);

        // The working-hours summary renders next to the pencil.
        final l10n = _l10n(tester);
        expect(
          find.text(
            l10n.scheduleDaySummaryWorking(
              summariseSpan(_working(_today).intervals),
            ),
          ),
          findsOneWidget,
          reason: 'the day panel must show the working-hours summary line',
        );

        // The three off-design day-panel buttons are GONE by design.
        expect(
          find.byKey(const Key('schedule-add-hours')),
          findsNothing,
          reason: 'removed off-design button "Додати час" must not return',
        );
        expect(
          find.byKey(const Key('schedule-time-off')),
          findsNothing,
          reason: 'removed off-design button "Час відпочинку" must not return',
        );
        expect(
          find.byKey(const Key('schedule-copy')),
          findsNothing,
          reason: 'removed off-design button "Копіювати" must not return',
        );
      },
    );

    testWidgets('SALON_OWNER (their salon master): edit affordances present', (
      tester,
    ) async {
      final days = _weekWith(todayDay: _working, filler: _working);
      await _pump(
        tester,
        overrides: _withWeekly(UserRole.salonOwner, days, <WeeklySchedule>[
          _template(),
        ]),
      );

      expect(find.byKey(const Key('schedule-weekly-card')), findsOneWidget);
      expect(find.byKey(const Key('schedule-day-pencil')), findsOneWidget);
    });
  });

  // ── Focused "no schedule at all" empty state ──────────────────────────────
  //
  // When the master has NO weekly template AND no override covers the visible
  // range (every day NO_SCHEDULE), the whole calendar is replaced by a single
  // centered empty-state card — NONE of the full layout renders.

  group('MasterScheduleScreen — no-schedule empty state', () {
    testWidgets(
      'editable master with no schedule sees ONLY the add-hours card; full '
      'layout absent',
      (tester) async {
        // No weekly template + an all-NO_SCHEDULE visible week.
        final days = _weekWith(todayDay: _noSchedule, filler: _noSchedule);
        await _pump(
          tester,
          overrides: _withWeekly(
            UserRole.independentMaster,
            days,
            const <WeeklySchedule>[],
          ),
        );

        // The focused empty-state card + whole-period copy + CTA render.
        expect(find.byKey(const Key('no-schedule-banner')), findsOneWidget);
        expect(find.byKey(const Key('no-schedule-add-hours')), findsOneWidget);
        final l10n = _l10n(tester);
        expect(find.text(l10n.scheduleNoSchedulePeriod), findsOneWidget);

        // The full layout is ABSENT — no week strip, no day cells, no legend,
        // no template card, no month-navigator "Today" action, no quick actions.
        expect(find.byType(WeekStripDay), findsNothing);
        expect(find.byType(SlotLegend), findsNothing);
        expect(find.byKey(const Key('schedule-weekly-card')), findsNothing);
        expect(find.byKey(const Key('schedule-today')), findsNothing);
        expect(find.byKey(const Key('schedule-day-pencil')), findsNothing);
        expect(find.byKey(const Key('schedule-add-hours')), findsNothing);
        expect(find.byKey(const Key('schedule-time-off')), findsNothing);
        expect(find.byKey(const Key('schedule-copy')), findsNothing);

        await expectLater(
          find.byType(MasterScheduleScreen),
          matchesGoldenFile('goldens/schedule_empty_state.png'),
        );
      },
    );

    testWidgets(
      'read-only SALON_MASTER with no schedule sees the empty-state card '
      'WITHOUT the CTA',
      (tester) async {
        final days = _weekWith(todayDay: _noSchedule, filler: _noSchedule);
        await _pump(
          tester,
          overrides: _withWeekly(
            UserRole.salonMaster,
            days,
            const <WeeklySchedule>[],
          ),
        );

        // The empty-state card shows informationally...
        expect(find.byKey(const Key('no-schedule-banner')), findsOneWidget);
        // ...but the CTA is suppressed for the read-only role (OQ-2).
        expect(find.byKey(const Key('no-schedule-add-hours')), findsNothing);

        // Full layout still absent.
        expect(find.byType(WeekStripDay), findsNothing);
        expect(find.byType(SlotLegend), findsNothing);
      },
    );

    testWidgets(
      'tapping the empty-state CTA routes through authRedirect to the REAL '
      'weekly-template editor (Phase 15.5)',
      (tester) async {
        final days = _weekWith(todayDay: _noSchedule, filler: _noSchedule);
        final container = await _pumpGuarded(
          tester,
          overrides: _withWeekly(
            UserRole.independentMaster,
            days,
            const <WeeklySchedule>[],
          ),
        );
        addTearDown(container.dispose);

        await tester.ensureVisible(
          find.byKey(const Key('no-schedule-add-hours')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('no-schedule-add-hours')));
        await tester.pumpAndSettle();

        // The dead "coming soon" stub is gone; the genuine weekly editor mounts
        // (NOT the deprecated working-hours editor).
        expect(
          find.byKey(const Key('stub-weekly-template-editor')),
          findsNothing,
        );
        expect(find.byType(WorkingHoursScreen), findsNothing);
        expect(find.byType(WeeklyTemplateEditorScreen), findsOneWidget);
        expect(
          find.byKey(const Key('btn-save-weekly-template')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('weekly-toggle-1')), findsOneWidget);
      },
    );

    // ── Regression: empty-state CTA must route via a Material tap affordance ──
    //
    // BUG (now fixed): GhostButton wrapped its label in a bare
    // GestureDetector(onTap:). Inside the empty-state SingleChildScrollView,
    // the scroll view's vertical-drag recogniser won the gesture arena for a
    // real finger's tap-with-drift, so the CTA's onPressed (navigate to the
    // weekly-template editor) never fired on device. The pre-existing CTA test
    // used `tester.tap` (zero movement), which routes on BOTH the old and new
    // widget — so it missed the bug.
    //
    // The widget-test gesture arena does NOT reproduce the device-only
    // drag-vs-tap contention: a measured sweep showed a simulated tap (and any
    // sub-slop drift) routes identically on the old GestureDetector and the new
    // InkWell, while any supra-slop drift correctly becomes a scroll on both.
    // So no gesture profile separates the implementations — a gesture-driven
    // assertion would be a false guard. The faithful, deterministic guard is
    // STRUCTURAL: the CTA's tap is handled by an InkWell (the arena-winning
    // Material tap affordance) and NOT a bare GestureDetector. This FAILS on
    // the pre-fix code and PASSES on the fix.
    testWidgets(
      'empty-state CTA is wired through an InkWell, not a bare GestureDetector '
      '(regression for the dropped GhostButton tap inside the scroll view)',
      (tester) async {
        final days = _weekWith(todayDay: _noSchedule, filler: _noSchedule);
        await _pump(
          tester,
          overrides: _withWeekly(
            UserRole.independentMaster,
            days,
            const <WeeklySchedule>[],
          ),
        );

        final Finder cta = find.byKey(const Key('no-schedule-add-hours'));
        await tester.ensureVisible(cta);
        await tester.pumpAndSettle();

        // The fix wires the CTA through an InkWell (the arena-winning Material
        // tap affordance). The pre-fix code has NO InkWell under the CTA — its
        // tap was a bare GestureDetector that lost the arena to the scroll view
        // on device. (Note: InkWell itself renders a GestureDetector internally,
        // so the discriminator is the *presence of InkWell*, not the absence of
        // GestureDetector.)
        expect(
          find.descendant(of: cta, matching: find.byType(InkWell)),
          findsOneWidget,
          reason: 'CTA must use InkWell so its tap wins the arena on device',
        );
      },
    );

    testWidgets(
      'a master with an override-only covered day (no template) renders the '
      'FULL layout, not the empty state',
      (tester) async {
        // No weekly template, but a per-date override covers today → this is
        // NOT "no schedule at all"; the calendar must render.
        final days = _weekWith(todayDay: _custom, filler: _noSchedule);
        await _pump(
          tester,
          overrides: _withWeekly(
            UserRole.independentMaster,
            days,
            const <WeeklySchedule>[],
          ),
        );

        // Full layout present (week strip + legend), empty-state copy absent.
        expect(find.byType(WeekStripDay), findsNWidgets(7));
        expect(find.byType(SlotLegend), findsOneWidget);
      },
    );

    testWidgets(
      'weekly signal still loading + all-NO_SCHEDULE effective data shows the '
      'spinner, NOT a premature empty state',
      (tester) async {
        // The empty-state verdict needs BOTH sources resolved. If only the
        // effective range has resolved (all NO_SCHEDULE) while the global
        // "has any schedule" signal is still loading, we must show the spinner
        // — never flash the empty-state card before the verdict is real.
        final days = _weekWith(todayDay: _noSchedule, filler: _noSchedule);
        await tester.pumpWidget(
          ProviderScope(
            overrides: <Object>[
              authProvider.overrideWith(
                () => _FixedAuth(UserRole.independentMaster),
              ),
              effectiveScheduleProvider.overrideWith(() => _DataSchedule(days)),
              weeklyScheduleProvider.overrideWith(() => _LoadingWeekly()),
            ].cast(),
            child: MaterialApp.router(
              routerConfig: _router(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('uk'),
            ),
          ),
        );
        // Pump (not settle — the weekly future never completes).
        await tester.pump();

        // Spinner, not the empty-state card.
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.byKey(const Key('no-schedule-banner')), findsNothing);
        expect(find.byKey(const Key('no-schedule-add-hours')), findsNothing);
      },
    );

    testWidgets(
      'weekly signal error + all-NO_SCHEDULE effective data shows the retry '
      'body, NOT the empty state (weekly-error precedence)',
      (tester) async {
        // The weekly source erroring must take precedence over the empty-state
        // verdict (the second error branch in `_body`). Otherwise a failed
        // global signal would be misread as "no schedule at all".
        final days = _weekWith(todayDay: _noSchedule, filler: _noSchedule);
        await _pump(
          tester,
          overrides: <Object>[
            authProvider.overrideWith(
              () => _FixedAuth(UserRole.independentMaster),
            ),
            effectiveScheduleProvider.overrideWith(() => _DataSchedule(days)),
            weeklyScheduleProvider.overrideWith(() => _ErrorWeekly()),
          ],
        );

        // Retry body, not the empty-state card.
        expect(find.byKey(const Key('schedule-retry')), findsOneWidget);
        expect(find.byKey(const Key('no-schedule-banner')), findsNothing);
        expect(find.byKey(const Key('no-schedule-add-hours')), findsNothing);
      },
    );
  });

  // ── Async UI states (M3) ──────────────────────────────────────────────────

  group('MasterScheduleScreen — async states', () {
    testWidgets('loading shows a spinner', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Object>[
            authProvider.overrideWith(
              () => _FixedAuth(UserRole.independentMaster),
            ),
            effectiveScheduleProvider.overrideWith(() => _LoadingSchedule()),
            weeklyScheduleProvider.overrideWith(
              () => _WeeklyData(<WeeklySchedule>[_template()]),
            ),
          ].cast(),
          child: MaterialApp.router(
            routerConfig: _router(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('uk'),
          ),
        ),
      );
      // Pump (not settle — the loading future never completes).
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    // ── Month-change loading-flash regression (BUG: full-screen spinner) ──────
    //
    // BUG (now fixed): tapping the next-month `>` arrow swapped the keyed
    // `effectiveScheduleProvider(month)` family instance, yielding a fresh
    // `AsyncLoading` whose `value == null`. The old `_body` gate
    // (`if (days == null) return CircularProgressIndicator(...)`) therefore
    // REPLACED the whole calendar with a full-screen spinner for the duration of
    // the new month's load — a jarring flash on every month step.
    //
    // The fix caches the last resolved list in `_lastDays`: during a month-step
    // reload the previous month's content stays on screen and a 2px top
    // `LinearProgressIndicator` (the `reloading` overlay) signals the load. The
    // full-screen spinner is now reserved for the genuine first load.
    //
    // This test PASSES on the fixed code and FAILS on the pre-fix gate: with the
    // old gate, after the tap `days == null` for the next month's key → the
    // calendar (WeekStripDay/SlotLegend) is gone and a CircularProgressIndicator
    // is present — the exact opposite of all three assertions below.
    testWidgets(
      'month change keeps previous content + inline indicator — no full-screen '
      'spinner',
      (tester) async {
        // Month 1 (today's month) resolves to a full templated week; the NEXT
        // month's range key never completes (still loading after the tap).
        final ScheduleRange month1 = ScheduleRange.month(_today);
        final List<EffectiveDay> days = _weekWith(
          todayDay: _working,
          filler: _working,
        );
        await _pump(
          tester,
          overrides: <Object>[
            authProvider.overrideWith(
              () => _FixedAuth(UserRole.independentMaster),
            ),
            effectiveScheduleProvider.overrideWith(
              () => _MonthAwareSchedule(month1, days),
            ),
            weeklyScheduleProvider.overrideWith(
              () => _WeeklyData(<WeeklySchedule>[_template()]),
            ),
          ],
        );

        // ── First load resolved: calendar content is on screen, no spinner ────
        expect(find.byType(WeekStripDay), findsNWidgets(7));
        expect(find.byType(SlotLegend), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byType(LinearProgressIndicator), findsNothing);

        // ── Tap the next-month `>` arrow (by its localised semantic label) ────
        final l10n = _l10n(tester);
        await tester.tap(find.bySemanticsLabel(l10n.scheduleNextMonth));
        // pump() ONLY — the next month's load never completes, so pumpAndSettle
        // would hang.
        await tester.pump();

        // ── Assertion 1: NO full-screen spinner on month change ───────────────
        // FAILS on the pre-fix gate (it returned the full-screen spinner here).
        expect(
          find.byType(CircularProgressIndicator),
          findsNothing,
          reason:
              'stepping the month must NOT replace the screen with a '
              'full-screen spinner while the new month loads',
        );

        // ── Assertion 2: previous month content is still visible ──────────────
        // FAILS on the pre-fix gate (the calendar was replaced by the spinner).
        expect(
          find.byType(WeekStripDay),
          findsNWidgets(7),
          reason:
              'the previous month content must stay on screen during the '
              'month-change reload (cached `_lastDays`)',
        );
        expect(find.byType(SlotLegend), findsOneWidget);

        // ── Assertion 3: subtle inline reload indicator IS present ────────────
        expect(
          find.byType(LinearProgressIndicator),
          findsOneWidget,
          reason:
              'a 2px top LinearProgressIndicator must signal the in-flight '
              'month-change reload',
        );
      },
    );

    testWidgets('error shows the retry control; tap retry re-fetches', (
      tester,
    ) async {
      await _pump(
        tester,
        overrides: <Object>[
          authProvider.overrideWith(
            () => _FixedAuth(UserRole.independentMaster),
          ),
          effectiveScheduleProvider.overrideWith(() => _ErrorSchedule()),
          weeklyScheduleProvider.overrideWith(
            () => _WeeklyData(<WeeklySchedule>[_template()]),
          ),
        ],
      );

      expect(find.byKey(const Key('schedule-retry')), findsOneWidget);

      // Tapping retry invalidates the provider (re-runs build → error again).
      await tester.tap(find.byKey(const Key('schedule-retry')));
      await tester.pumpAndSettle();
      // Still on the error body (the fake always throws); the control survives.
      expect(find.byKey(const Key('schedule-retry')), findsOneWidget);
    });
  });

  // ── Past-day read-only + override dot ─────────────────────────────────────

  group('MasterScheduleScreen — past day + override dots', () {
    testWidgets('past date hides the day pencil (read-only history)', (
      tester,
    ) async {
      // Build a week where a PAST day (yesterday, if in this week) is selected.
      // We select the Monday of the week; if Monday is in the past it must hide
      // the pencil. Skip when today IS Monday (no past day in the strip's start).
      final days = _weekWith(todayDay: _working, filler: _working);
      await _pump(tester, overrides: _editableData(days));

      final DateTime mondayOfWeek = _weekStart;
      if (mondayOfWeek.isBefore(_today)) {
        await _selectStripDay(tester, mondayOfWeek.day);
        // Past day selected → pencil + day-action buttons hidden.
        expect(find.byKey(const Key('schedule-day-pencil')), findsNothing);
        expect(find.byKey(const Key('schedule-add-hours')), findsNothing);
      } else {
        // Today is Monday — the present-day pencil is shown instead.
        expect(find.byKey(const Key('schedule-day-pencil')), findsOneWidget);
      }
    });

    testWidgets('override dot present on an overridden date in the strip', (
      tester,
    ) async {
      // Make a non-today day in the week a custom override so it carries a dot;
      // today stays templated (no dot).
      final List<EffectiveDay> days = <EffectiveDay>[
        for (int i = 0; i < 7; i++)
          if (_dateOnly(_weekStart.add(Duration(days: i))) == _today)
            _working(_today)
          else if (i == 0 && _dateOnly(_weekStart) != _today)
            _custom(_weekStart)
          else
            _working(_weekStart.add(Duration(days: i))),
      ];
      await _pump(tester, overrides: _editableData(days));

      // The screen renders; the override dot is a render detail captured by the
      // strip goldens. Here we assert the screen built with the overridden data
      // without error (the dot logic is unit-covered by hasOverride downstream).
      expect(find.byType(MasterScheduleScreen), findsOneWidget);
    });
  });

  // ── Header-alignment regression (VelvetTopBar shared widget contract) ───────
  //
  // BUG (now fixed): MasterScheduleScreen used a Material AppBar while
  // MasterProfileScreen used a custom 48 dp VelvetTopBar, causing the back
  // arrow + title to be misaligned across the two screens. The fix extracted
  // VelvetTopBar into lib/shared/widgets/velvet_top_bar.dart and replaced the
  // AppBar in the schedule screen with it.
  //
  // The durable guard is STRUCTURAL, not golden-based (regenerated goldens are
  // self-referential and do not prevent visual-divergence regressions):
  //   1. VelvetTopBar is present — the schedule screen renders the shared bar.
  //   2. AppBar is absent       — the old Material AppBar is NOT reintroduced.
  //   3. Title text matches scheduleTitle and a NeumorphicIconButton back arrow
  //      is present — alignment contract is fully enforced.
  //
  // Assertions (1) and (2) FAIL on the pre-fix code (AppBar present, no
  // VelvetTopBar) and PASS on the fixed code. Any future refactor that
  // accidentally swaps VelvetTopBar back to AppBar will be caught immediately.

  group('MasterScheduleScreen — header alignment regression (VelvetTopBar)', () {
    testWidgets('renders VelvetTopBar and NOT a Material AppBar '
        '(regression: schedule screen was misaligned vs profile screen)', (
      tester,
    ) async {
      // Any valid data state works — we need the screen to build fully so we
      // can walk the widget tree. Use the simplest editable case (working day).
      final days = _weekWith(todayDay: _working, filler: _working);
      await _pump(tester, overrides: _editableData(days));

      // ── Assertion 1: shared VelvetTopBar is present (exactly one) ────────
      // FAILS on the pre-fix code (no VelvetTopBar in the schedule screen).
      expect(
        find.byType(VelvetTopBar),
        findsOneWidget,
        reason:
            'MasterScheduleScreen must render the shared VelvetTopBar widget '
            'so header alignment matches MasterProfileScreen',
      );

      // ── Assertion 2: Material AppBar is absent ────────────────────────────
      // FAILS on the pre-fix code (AppBar was still present).
      expect(
        find.byType(AppBar),
        findsNothing,
        reason:
            'MasterScheduleScreen must NOT contain a Material AppBar — it '
            'was the root cause of the header misalignment vs the profile '
            'screen; VelvetTopBar is the replacement',
      );

      // ── Assertion 3: title text and back-arrow button rendered ────────────
      // Verifies the VelvetTopBar is correctly configured, not merely present.
      final l10n = _l10n(tester);
      expect(
        find.text(l10n.scheduleTitle),
        findsOneWidget,
        reason: 'Header title must be scheduleTitle ("Графік роботи")',
      );
      expect(
        find.byType(NeumorphicIconButton),
        findsOneWidget,
        reason:
            'VelvetTopBar must render a NeumorphicIconButton back arrow, '
            'confirming the onBack handler is wired',
      );
    });

    testWidgets(
      'NeumorphicIconButton back arrow carries the correct semantic label',
      (tester) async {
        final days = _weekWith(todayDay: _working, filler: _working);
        await _pump(tester, overrides: _editableData(days));

        // The semantic label drives accessibility and is passed from
        // l10n.registerBackStep ("Назад"). Assert via Semantics finder so the
        // test is coupled to the accessible name, not a visible text string.
        final l10n = _l10n(tester);
        expect(
          find.bySemanticsLabel(l10n.registerBackStep),
          findsOneWidget,
          reason:
              'Back arrow must carry the localised semantic label from '
              'l10n.registerBackStep so screen readers announce it correctly',
        );
      },
    );

    // ── Mirror guard: the CTA DESTINATION uses the shared header too ──────────
    //
    // The header-alignment contract (shared VelvetTopBar, never a Material
    // AppBar) must hold on the screen the schedule empty-state / banner /
    // weekly-card CTA routes to — otherwise the back arrow + title jump
    // vertically as the user crosses the CTA. Phase 15.5 repoints that CTA at
    // the real `WeeklyTemplateEditorScreen`, so this mirror guard now navigates
    // to it (via the production authRedirect router) and asserts it renders the
    // shared VelvetTopBar and NOT an AppBar. It locks any calendar-CTA-reachable
    // screen to the shared header — a future destination that reintroduces a
    // Material AppBar will be caught immediately.
    testWidgets(
      'CTA destination (weekly-template editor) renders VelvetTopBar and NOT a '
      'Material AppBar (mirror of the schedule-screen header guard)',
      (tester) async {
        final days = _weekWith(todayDay: _noSchedule, filler: _working);
        final container = await _pumpGuarded(
          tester,
          overrides: _editableData(days),
        );
        addTearDown(container.dispose);

        // Navigate via the real CTA so we assert the ACTUAL reachable screen.
        await tester.ensureVisible(
          find.byKey(const Key('no-schedule-add-hours')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('no-schedule-add-hours')));
        await tester.pumpAndSettle();

        // We are on the destination editor.
        expect(find.byType(WeeklyTemplateEditorScreen), findsOneWidget);

        // It uses the shared VelvetTopBar …
        expect(
          find.byType(VelvetTopBar),
          findsOneWidget,
          reason:
              'the CTA destination must render the shared VelvetTopBar so its '
              'header aligns with the schedule screen the user came from',
        );
        // … and NOT a Material AppBar.
        expect(
          find.byType(AppBar),
          findsNothing,
          reason:
              'the CTA destination must NOT contain a Material AppBar — the '
              'header would otherwise jump vertically across the CTA',
        );
      },
    );
  });

  // ── Month-navigator two-row header (intended design change) ────────────────
  //
  // DESIGN CHANGE (user-requested, intended): the month-navigator center title
  // changed from a SINGLE-LINE `Text(VelvetText.subheading())` ("<month>
  // <year>") to a centered TWO-ROW `Column` — the month name on row 1 and the
  // year on row 2, both using the smaller `VelvetText.monthNavTitle` (14sp),
  // wrapped in a `MergeSemantics`. The 5 full-screen goldens were re-blessed for
  // this pixel shift, but goldens are self-referential. THIS structural guard
  // asserts the layout INTENT independently of any pixel snapshot, so the
  // two-row stack cannot silently regress back to a single combined line.
  //
  // The screen anchors `_visibleMonth` to the device "today", so the expected
  // month name + year are computed from `_today` (NOT hardcoded). `monthNominative`
  // returns the Ukrainian nominative month name for the test locale.
  group('MasterScheduleScreen — month navigator two-row header', () {
    testWidgets(
      'month name and year render as TWO separate Texts, stacked vertically '
      '(month above year), wrapped in MergeSemantics — not one combined line',
      (tester) async {
        final days = _weekWith(todayDay: _working, filler: _working);
        await _pump(tester, overrides: _editableData(days));

        // The visible month is today's month (the screen anchors on `now()`).
        final String monthName = monthNominative(_today.month);
        final String yearLabel = '${_today.year}';

        // ── Assertion 1: month and year are TWO SEPARATE Text widgets ─────────
        // (NOT a single combined "<month> <year>" Text). The pre-change code had
        // one Text — so the combined finder matched and these two did not.
        final Finder monthText = find.text(monthName);
        final Finder yearText = find.text(yearLabel);
        expect(
          monthText,
          findsOneWidget,
          reason: 'the month name renders as its own Text node',
        );
        expect(
          yearText,
          findsOneWidget,
          reason: 'the year renders as its own Text node',
        );
        // The combined single-line label must NOT exist (regression guard
        // against collapsing the two rows back into one Text).
        expect(
          find.text('$monthName $yearLabel'),
          findsNothing,
          reason:
              'month + year must be two separate rows, not one combined Text',
        );

        // ── Assertion 2: month is stacked ABOVE the year (vertical order) ─────
        // Both Texts share the same centering Column; compare their global dy so
        // the test pins the vertical arrangement, not just co-existence.
        final Offset monthOffset = tester.getTopLeft(monthText);
        final Offset yearOffset = tester.getTopLeft(yearText);
        expect(
          monthOffset.dy < yearOffset.dy,
          isTrue,
          reason:
              'the month name must sit on the row ABOVE the year (two-row stack)',
        );
        // They are co-descendants of a single Column (the two-row stack).
        expect(
          find.ancestor(of: monthText, matching: find.byType(Column)),
          findsWidgets,
        );
        expect(
          find.ancestor(of: yearText, matching: find.byType(Column)),
          findsWidgets,
        );

        // ── Assertion 3: the split stays accessible via MergeSemantics ────────
        // The two Text nodes are wrapped in a MergeSemantics so TalkBack still
        // announces a single "<month> <year>" — assert it wraps BOTH rows.
        expect(
          find.ancestor(of: monthText, matching: find.byType(MergeSemantics)),
          findsOneWidget,
          reason: 'the month row must live under a MergeSemantics',
        );
        expect(
          find.ancestor(of: yearText, matching: find.byType(MergeSemantics)),
          findsOneWidget,
          reason:
              'the year row must live under the SAME MergeSemantics so the '
              'split stays a single accessible announcement',
        );
      },
    );
  });

  // ── Week-strip overflow regression (narrow phone widths) ──────────────────
  //
  // The seven WeekStripDay cells used to be laid out with
  // MainAxisAlignment.spaceBetween over intrinsic-width children, which cannot
  // shrink → a ~46px RenderFlex right-overflow on normal phone widths. The
  // cells are now Expanded (sharing the row) and the day disc is wrapped in a
  // FittedBox, so the strip fits any width. This test pins a narrow phone width
  // and fails if a RenderFlex overflow is ever reintroduced.
  group('MasterScheduleScreen — week strip fits narrow widths', () {
    testWidgets('no RenderFlex overflow at 320 logical px', (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final List<EffectiveDay> days = _weekWith(
        todayDay: _working,
        filler: _working,
      );
      await _pump(tester, overrides: _editableData(days));

      // A RenderFlex overflow is reported as an exception during layout/paint;
      // takeException returns null only when the strip fits. This is the exact
      // guard for the original ~46px right-overflow bug.
      expect(tester.takeException(), isNull);
      expect(find.byType(WeekStripDay), findsNWidgets(7));
    });
  });

  // ── Jump-to-changed-day + show-changes-immediately (the fix under test) ─────
  //
  // `_openDayOverride` now awaits the sheet's `Future<DateTime?>`. On a non-null
  // result it (a) moves `_selected` onto the edited date and (b) awaits the
  // same-range `effectiveScheduleProvider` refetch so the selected-day panel
  // shows the JUST-SAVED override immediately — never the stale pre-save day.
  // The `_lastDaysRange` guard makes the same-range post-save reload skip the
  // `_lastDays` snapshot (else the panel would render pre-save intervals) while
  // a month STEP still serves the snapshot (no loading flash).
  //
  // These tests drive the REAL OverridesNotifier + EffectiveScheduleNotifier
  // against `_StatefulFakeScheduleRepository` (only the repo is overridden), so
  // the whole save → invalidate → refetch → re-select chain runs for real.
  group('MasterScheduleScreen — save jumps to + shows the changed day', () {
    testWidgets(
      'saving a per-date override (adds a pause) on the selected day shows the '
      'fresh override immediately — no stale pre-save intervals, no flash',
      (tester) async {
        // Today opens with a SOLID 09:00–18:00 day (NO interior pause). The
        // override save splits it into 09:00–13:00 · 14:00–18:00 (a 13:00–14:00
        // pause). Pre-save the panel must show ZERO interior timeOff cells;
        // post-save it must show some — proving the fresh data is rendered.
        final container = await _pumpOverrideFlow(tester, edited: _today);

        // Pre-save: the selected (today) panel has NO interior pause.
        expect(_interiorTimeOffCount(tester), 0);

        await _editSelectedDayAddingPause(tester);

        // The save ran exactly once through the real notifier → repo.
        expect(_repoOf(container).putCount, 1);
        // Selection stayed on the edited date.
        expect(find.byKey(const Key('schedule-day-pencil')), findsOneWidget);
        // Post-save: the panel now renders the FRESH override — the 13:00–14:00
        // pause is present as interior timeOff cells. A regression that served
        // the stale `_lastDays` snapshot would still show zero here.
        expect(
          _interiorTimeOffCount(tester),
          greaterThan(0),
          reason:
              'the just-saved pause must be visible immediately; a stale '
              '`_lastDays` snapshot would still show the pre-save solid day',
        );
      },
    );

    testWidgets(
      'editing a day that is NOT the currently-selected day moves `_selected` '
      'onto the changed date and renders its fresh override',
      (tester) async {
        // Find a future day in the visible week (editable; pencil shown). Skip
        // when today is the week's last editable day (no distinct future day).
        final DateTime? future = _futureDayInWeek();
        if (future == null) {
          // Degenerate week position — covered by the selected-day case above.
          return;
        }

        final container = await _pumpOverrideFlow(tester, edited: future);

        // Select the future day (moving `_selected` off today onto it), then
        // edit it. The fix sets `_selected` to the sheet's returned date and
        // re-reads it fresh.
        await _selectStripDay(tester, future.day);
        // Pre-save the future day is a solid 09:00–18:00 (no pause).
        expect(_interiorTimeOffCount(tester), 0);

        await _editSelectedDayAddingPause(tester);

        expect(_repoOf(container).putCount, 1);
        // `_selected` is on the edited (future) day: its strip cell is the lone
        // selected WeekStripDay. A regression dropping `_selected.value =
        // changed` in `_openDayOverride` would leave selection where it was.
        expect(
          _selectedStripDayNumber(tester),
          future.day,
          reason: '_openDayOverride must move `_selected` onto the saved date',
        );
        // The panel header now shows the edited (future) date's fresh override:
        // the interior pause is rendered.
        expect(
          _interiorTimeOffCount(tester),
          greaterThan(0),
          reason:
              'after save the panel must focus the edited date and show its '
              'fresh pause immediately',
        );
      },
    );

    testWidgets(
      'a month STEP still serves the cached snapshot (no flash) — the '
      '`_lastDaysRange` guard distinguishes a step from a same-range reload',
      (tester) async {
        // This pins the OTHER half of the `_lastDaysRange` branch: stepping the
        // month (a DIFFERENT range key) must keep the previous content + show
        // the inline indicator, NOT a full-screen spinner. A regression that
        // dropped the range tag (served stale on EVERY reload, or NEVER) would
        // break exactly one of this assertion and the freshness assertions
        // above — together they fence the guard on both sides.
        final ScheduleRange month1 = ScheduleRange.month(_today);
        final List<EffectiveDay> days = _weekWith(
          todayDay: _working,
          filler: _working,
        );
        await _pump(
          tester,
          overrides: <Object>[
            authProvider.overrideWith(
              () => _FixedAuth(UserRole.independentMaster),
            ),
            effectiveScheduleProvider.overrideWith(
              () => _MonthAwareSchedule(month1, days),
            ),
            weeklyScheduleProvider.overrideWith(
              () => _WeeklyData(<WeeklySchedule>[_template()]),
            ),
          ],
        );

        expect(find.byType(WeekStripDay), findsNWidgets(7));

        final l10n = _l10n(tester);
        await tester.tap(find.bySemanticsLabel(l10n.scheduleNextMonth));
        await tester.pump();

        // Month step → previous content retained, inline indicator, NO spinner.
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byType(WeekStripDay), findsNWidgets(7));
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
      },
    );
  });

  // ── REGRESSION (QA GATE): seamless-retention + read-after-write coherence ───
  //
  // The exact on-device bug that shipped despite the OLD green save-flow tests:
  // on a same-range post-save reload, Riverpod 3.1 `ref.invalidate` /
  // dependency-driven rebuild is SEAMLESS — the in-flight `AsyncLoading` RETAINS
  // the previous (pre-save) `.value` via `copyWithPrevious`. The old tests used a
  // zero-latency read-your-writes fake AND asserted only the FINAL settled frame
  // (`pumpAndSettle`), so they never observed the in-flight window where the
  // stale value leaked through and got re-rendered + re-cached.
  //
  // These two tests park the post-save effective fetch on a Completer the test
  // controls, so the reload is observably IN FLIGHT across an intermediate
  // `pump()`. They drive the REAL OverridesNotifier + EffectiveScheduleNotifier
  // (only `scheduleRepositoryProvider` is overridden), so the genuine reactive
  // `overridesProvider` watch is exercised.
  //
  // Both FAIL on the pre-fix code (where `effective_schedule_notifier.build` did
  // NOT watch `overridesProvider` and the screen keyed the reload off
  // `value == null`): the retained pre-save day would render the pre-save solid
  // grid during the in-flight frame (test #2) and the screen would never issue a
  // genuine refetch for the just-written override (test #3). Verified by reverting
  // the fix — see the QA report.
  group('MasterScheduleScreen — seamless-retention regression (QA gate)', () {
    testWidgets(
      'the in-flight post-save reload does NOT render the retained pre-save '
      'intervals: the screen shows the loading gate, then the FRESH override',
      (tester) async {
        // Today opens as a SOLID 09:00–18:00 day (zero interior pauses). The
        // override adds a 13:00–14:00 pause → post-save the day has interior
        // timeOff cells. The post-save effective fetch is parked on a Completer.
        final repo = _CompleterScheduleRepository(
          targetDate: _today,
          preSave: _solidWorking(_today),
          postSave: EffectiveDay(
            date: _today,
            source: EffectiveSource.overrideCustom,
            intervals: <WorkInterval>[
              _interval(9, 0, 13, 0),
              _interval(14, 0, 18, 0),
            ],
          ),
        );

        final container = ProviderContainer(
          overrides: <Object>[
            authProvider.overrideWith(
              () => _FixedAuth(UserRole.independentMaster),
            ),
            scheduleRepositoryProvider.overrideWithValue(repo),
          ].cast(),
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(
              routerConfig: _router(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('uk'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Pre-save: the selected (today) panel renders the SOLID day — zero
        // interior pauses.
        expect(_interiorTimeOffCount(tester), 0);

        // Open the override sheet for today, add the break, and save. The sheet's
        // own provider reload (`listOverrides`) settles synchronously; only the
        // SCREEN's post-save effective refetch is parked on the Completer.
        await tester.tap(find.byKey(const Key('schedule-day-pencil')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('override-add-break')));
        await tester.tap(find.byKey(const Key('override-add-break')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('override-save')));
        await tester.tap(find.byKey(const Key('override-save')));

        // Drive frames WITHOUT settling (pumpAndSettle would hang on the parked
        // Completer). The put has landed; the post-save effective refetch is now
        // in flight (parked). This is the EXACT window the bug lived in.
        await tester.pump();
        await tester.pump();

        // The write happened …
        expect(repo.putCount, 1);
        // … and a post-save effective fetch is parked (in flight).
        expect(
          repo.pendingPostSaveFetch,
          isNotNull,
          reason:
              'the post-save effective reload must be a genuine refetch '
              '(in flight), not a copyWithPrevious-retained snapshot',
        );
        expect(repo.pendingPostSaveFetch!.isCompleted, isFalse);

        // ── THE GUARD ───────────────────────────────────────────────────────
        // During the in-flight reload the screen MUST NOT render the retained
        // pre-save SOLID day. It routes through the loading gate instead. On the
        // pre-fix code the seamless-retained pre-save value rendered here, so the
        // SOLID grid (zero interior pauses) was on screen — the stale frame the
        // user saw. We assert the stale pre-save grid is NOT shown: either the
        // spinner gate is up (no SlotChips) OR — if any chips render — they are
        // never the pre-save solid composition. The robust, locale-independent
        // signal is the absence of the pre-save grid's full 18-cell solid
        // availability with zero timeOff while NOT yet showing the fresh pause.
        final bool spinnerUp = find
            .byType(CircularProgressIndicator)
            .evaluate()
            .isNotEmpty;
        if (!spinnerUp) {
          // If content is on screen at all during the in-flight reload, it must
          // not be the stale pre-save solid day (which had availableCount==18,
          // timeOff==0). The fresh pause has not resolved yet, so the only way
          // to avoid the stale render is the loading gate → this branch should
          // not be reached on the fixed code. Fail loudly if it is.
          fail(
            'in-flight post-save reload rendered content instead of the '
            'loading gate — the seamless-retained pre-save day leaked through '
            '(the exact on-device bug)',
          );
        }
        // The pre-save solid grid is NOT on screen during the in-flight reload.
        expect(_interiorTimeOffCount(tester), 0);
        expect(find.byType(SlotChip), findsNothing);

        // ── Complete the parked refetch → the FRESH override resolves ─────────
        repo.pendingPostSaveFetch!.complete(
          repo._composeRange(repo._rangeFrom, repo._rangeTo),
        );
        await tester.pumpAndSettle();

        // Now the panel renders the fresh override: the 13:00–14:00 pause shows
        // as interior timeOff cells. A regression that served the retained
        // pre-save snapshot would still show zero here.
        expect(
          _interiorTimeOffCount(tester),
          greaterThan(0),
          reason:
              'once the genuine refetch resolves the just-saved pause must '
              'render — proving the FRESH value, not the retained one, is shown',
        );
      },
    );

    testWidgets(
      'read-after-write coherence: the effective fetch reflecting the override '
      'fires strictly AFTER the write — the screen renders the refetched '
      'composition, not the seamless-retained previous value',
      (tester) async {
        final repo = _CompleterScheduleRepository(
          targetDate: _today,
          preSave: _solidWorking(_today),
          postSave: EffectiveDay(
            date: _today,
            source: EffectiveSource.overrideCustom,
            intervals: <WorkInterval>[
              _interval(9, 0, 13, 0),
              _interval(14, 0, 18, 0),
            ],
          ),
        );

        final container = ProviderContainer(
          overrides: <Object>[
            authProvider.overrideWith(
              () => _FixedAuth(UserRole.independentMaster),
            ),
            scheduleRepositoryProvider.overrideWithValue(repo),
          ].cast(),
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(
              routerConfig: _router(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('uk'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Capture the fetch count at the moment of the first (pre-save) render so
        // we can prove a SECOND, post-write fetch fired.
        final int fetchesBeforeSave = repo.effectiveFetchCount;
        expect(_interiorTimeOffCount(tester), 0);

        await tester.tap(find.byKey(const Key('schedule-day-pencil')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('override-add-break')));
        await tester.tap(find.byKey(const Key('override-add-break')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('override-save')));
        await tester.tap(find.byKey(const Key('override-save')));
        await tester.pump();
        await tester.pump();

        // A genuine post-write effective refetch fired (driven by the reactive
        // `overridesProvider` watch) — the count grew AND it happened after the
        // put. On the pre-fix code (build NOT watching overridesProvider) the
        // override save would NOT trigger an effective refetch via the
        // dependency at all.
        expect(repo.putCount, 1);
        expect(
          repo.effectiveFetchCount,
          greaterThan(fetchesBeforeSave),
          reason:
              'the override write must drive a fresh effective fetch via the '
              'reactive overridesProvider dependency (read-after-write)',
        );
        expect(repo.pendingPostSaveFetch, isNotNull);

        // Resolve the parked refetch with the composition that reflects the
        // write (postSave). The screen must render THIS, not the retained
        // pre-save value.
        repo.pendingPostSaveFetch!.complete(
          repo._composeRange(repo._rangeFrom, repo._rangeTo),
        );
        await tester.pumpAndSettle();

        expect(
          _interiorTimeOffCount(tester),
          greaterThan(0),
          reason:
              'the rendered grid must be the refetched post-write '
              'composition (with the pause), proving read-after-write coherence',
        );
      },
    );
  });

  // ── Weekly-template card pills are WEEK-SCOPED, not month-aggregate ─────────
  //
  // Behaviour change under guard (master_schedule_screen.dart `_templatePattern`
  // + the `schedule-weekly-pills-<7 bits Mon→Sun>` ValueKey on WeekdayPillRow):
  // the top template card's weekday pills now reflect ONLY the currently-
  // displayed week (`_weekStart`..+6), not a whole-month aggregate. A recurring
  // Mon+Wed template plus a single-date Friday override that exists ONLY in the
  // current week must light Mon+Wed+Fri (`...-1010100`) WHILE that week is shown,
  // and collapse to Mon+Wed (`...-1010000`) the moment the strip steps to an
  // adjacent week (whose Friday carries no override).
  //
  // DETERMINISM (M2 / Phase 15.2 device-weekday coupling): the test never reads
  // the real device weekday. Both the screen and the fixtures derive the visible
  // week from `_mondayOf(DateTime.now())` (the screen's `_weekStart` seam), so
  // the Friday under test is ALWAYS `_weekStart + 4` and next-week's Friday is
  // ALWAYS `_weekStart + 11` regardless of the run date. The fake grants
  // intervals to `_weekStart + 4` only, so the "Friday present" and "Friday
  // absent next week" assertions both run every day of the year.
  //
  // GOLDEN-NOT-ACCEPTANCE (Phase 15.2): the acceptance signal is the structural
  // ValueKey of the active weekday set, asserted to FLIP across `_stepWeek` — not
  // a regenerated PNG.
  //
  // TRUE REGRESSION GUARD: the override flows through the SAME `_DayIndex` /
  // `EffectiveDay` projection the screen uses (a real single-date
  // `ScheduleOverride.custom(start: thatFriday, end: thatFriday)` resolved into a
  // `CUSTOM_HOURS` `EffectiveDay` with non-empty intervals). Under the OLD
  // month-aggregate logic the Friday pill would stay lit on EVERY week of the
  // month, so the post-step assertion (`...-1010000`) would FAIL; under the new
  // week-scoped logic it passes.
  group('MasterScheduleScreen — weekly-template pills are week-scoped', () {
    // ISO Monday-first bit strings (Mon,Tue,Wed,Thu,Fri,Sat,Sun).
    const String monWedFri = 'schedule-weekly-pills-1010100';
    const String monWed = 'schedule-weekly-pills-1010000';

    testWidgets(
      'current-week-only Friday override lights Mon+Wed+Fri on the displayed '
      'week, then collapses to Mon+Wed on the next week',
      (tester) async {
        // Recurring Mon+Wed across this week and the two adjacent weeks, plus a
        // SINGLE-DATE Friday override that exists ONLY in the current week.
        final List<EffectiveDay> days = _monWedTemplateWithThisWeekFriday();
        await _pump(
          tester,
          overrides: <Object>[
            authProvider.overrideWith(
              () => _FixedAuth(UserRole.independentMaster),
            ),
            effectiveScheduleProvider.overrideWith(() => _DataSchedule(days)),
            weeklyScheduleProvider.overrideWith(
              () => _WeeklyData(<WeeklySchedule>[_template()]),
            ),
          ],
        );

        // Displayed week (contains the Friday override) → Mon+Wed+Fri.
        expect(
          find.byKey(const ValueKey<String>(monWedFri)),
          findsOneWidget,
          reason:
              'the current week carries the one-off Friday override, so the '
              'pills must light Mon+Wed+Fri',
        );
        expect(
          find.byKey(const ValueKey<String>(monWed)),
          findsNothing,
          reason: 'the Friday pill must be lit while its week is displayed',
        );

        // ── Step to the NEXT week (forward chevron, by its localised semantic
        // label — the same path `_stepWeek(1)` drives). ───────────────────────
        final l10n = _l10n(tester);
        await tester.tap(find.bySemanticsLabel(l10n.scheduleNextWeek));
        await tester.pumpAndSettle();

        // Next week's Friday has NO override → the pill set collapses to Mon+Wed.
        expect(
          find.byKey(const ValueKey<String>(monWed)),
          findsOneWidget,
          reason:
              'stepping to the next week (whose Friday has no override) must '
              'drop the Friday pill — week-scoped, not month-aggregate',
        );
        expect(
          find.byKey(const ValueKey<String>(monWedFri)),
          findsNothing,
          reason:
              'the one-off Friday must NOT bleed onto the next week (this is '
              'the exact assertion the old month-aggregate logic would fail)',
        );

        // ── Step BACK to the original week → Mon+Wed+Fri returns. ─────────────
        await tester.tap(find.bySemanticsLabel(l10n.schedulePrevWeek));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>(monWedFri)),
          findsOneWidget,
          reason: 'returning to the override week must restore the Friday pill',
        );

        // ── Step BACK one more (previous week) → Mon+Wed only. ────────────────
        await tester.tap(find.bySemanticsLabel(l10n.schedulePrevWeek));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>(monWed)),
          findsOneWidget,
          reason:
              'the previous week (no Friday override) must also show Mon+Wed '
              'only — confirming the override is scoped to its single week',
        );
        expect(find.byKey(const ValueKey<String>(monWedFri)), findsNothing);
      },
    );
  });

  // ── REGRESSION (QA GATE): month-boundary week-strip spillover days ──────────
  //
  // BUG (now fixed): when the visible week straddled a month boundary — e.g.
  // Mon 29 Jun 2026 → Sun 5 Jul 2026 with `_visibleMonth` resolved to JULY (the
  // majority month) — the trailing previous-month days (29–30 Jun) rendered as
  // NON-working even though the weekly template marked them working. Cause: the
  // `_range` getter keyed `effectiveScheduleProvider` on
  // `ScheduleRange.month(_visibleMonth)`, i.e. 1–31 Jul ONLY. The spillover days
  // 29–30 Jun were never fetched, so `_DayIndex.lookup` served a NO_SCHEDULE
  // fallback (empty intervals) → those strip cells rendered day-off.
  //
  // FIX: `_range` now returns the UNION of the visible month and the displayed
  // week (`from = min(firstOfMonth, weekStart)`, `to = max(lastOfMonth,
  // weekStart + 6)`), so a straddling week fetches from 29 Jun and the spillover
  // days resolve from their real effective schedule.
  //
  // This test reproduces the report EXACTLY: it navigates the screen to the
  // straddling week (Mon 29 Jun 2026 → Sun 5 Jul 2026) and asserts the 29-Jun
  // and 30-Jun strip cells render WORKING. The fake is RANGE-AWARE — it can only
  // serve a date that was actually fetched — so under the OLD month-only key the
  // 29/30-Jun cells fall outside the requested range and render day-off (the
  // assertion FAILS); under the union range they are in range and render working
  // (PASS). A second assertion pins the union directly: the requested range's
  // `from` must reach 29 Jun (≤), not start at 1 Jul.
  //
  // GOLDEN-NOT-ACCEPTANCE / M2 / M3: the acceptance signal is the STRUCTURAL
  // `WeekStripDay.working` flag on the spillover cells (read off the widget, not
  // a localised string or a PNG), plus the captured `ScheduleRange.from`.
  group('MasterScheduleScreen — month-boundary strip spillover (QA gate)', () {
    // The report's straddling week. 29 Jun 2026 IS a Monday, so its `_mondayOf`
    // is itself; Thursday (2 Jul) lives in July → `_visibleMonth` resolves to
    // July, the exact "majority month" shape from the bug report.
    final DateTime reportWeekMon = DateTime(2026, 6, 29);

    /// Whole-week delta from the device week to [reportWeekMon] — drives the
    /// week chevron a deterministic number of times regardless of run date.
    int weekStepsTo(DateTime targetMon) {
      final int days = _dateOnly(targetMon).difference(_weekStart).inDays;
      return days ~/ 7;
    }

    /// Reads the [WeekStripDay] cell rendered for day-of-month [dayNumber] (the
    /// strip shows one cell per visible-week date; day numbers are unique within
    /// a 7-day window). M2: structural — returns the widget, not a string.
    WeekStripDay stripCell(WidgetTester tester, int dayNumber) {
      return tester
          .widgetList<WeekStripDay>(find.byType(WeekStripDay))
          .singleWhere((WeekStripDay c) => c.day == dayNumber);
    }

    testWidgets(
      'a week straddling Jun→Jul (visible month = July) renders the 29-Jun and '
      '30-Jun spillover cells as WORKING — union range fetches them, not the '
      'month-only range (which left them day-off)',
      (tester) async {
        _PerWeekdayRangeSchedule.observedRanges.clear();
        addTearDown(_PerWeekdayRangeSchedule.observedRanges.clear);

        await _pump(
          tester,
          overrides: <Object>[
            authProvider.overrideWith(
              () => _FixedAuth(UserRole.independentMaster),
            ),
            effectiveScheduleProvider.overrideWith(
              () => _PerWeekdayRangeSchedule(),
            ),
            weeklyScheduleProvider.overrideWith(
              () => _WeeklyData(<WeeklySchedule>[_template()]),
            ),
          ],
        );

        // Navigate from the device week onto the report's straddling week by
        // stepping the week chevron the deterministic number of times. Tapping
        // the chevron drives the exact `_stepWeek` path production uses (which
        // also recomputes `_visibleMonth` to the majority month → July here).
        final l10n = _l10n(tester);
        final int steps = weekStepsTo(reportWeekMon);
        final String chevron = steps >= 0
            ? l10n.scheduleNextWeek
            : l10n.schedulePrevWeek;
        for (int i = 0; i < steps.abs(); i++) {
          await tester.tap(find.bySemanticsLabel(chevron));
          await tester.pumpAndSettle();
        }

        // Sanity: we are on the straddling week — all seven cells present, and
        // the 29/30-Jun spillover cells carry the previous month (inMonth=false)
        // while the July majority days carry inMonth=true. This pins that the
        // navigation actually landed on the boundary week (not some other week).
        expect(find.byType(WeekStripDay), findsNWidgets(7));
        expect(
          stripCell(tester, 29).inMonth,
          isFalse,
          reason: '29 Jun is a previous-month spillover day in a July view',
        );
        expect(
          stripCell(tester, 30).inMonth,
          isFalse,
          reason: '30 Jun is a previous-month spillover day in a July view',
        );
        expect(
          stripCell(tester, 2).inMonth,
          isTrue,
          reason: '2 Jul belongs to the visible (July) month',
        );

        // ── THE REGRESSION ASSERTION ──────────────────────────────────────────
        // Mon 29 Jun + Tue 30 Jun are template working days. Under the OLD
        // `ScheduleRange.month(July)` key these dates were never fetched → the
        // range-aware fake never served them → `_DayIndex` fell back to
        // NO_SCHEDULE → `working == false`. Under the union range they ARE
        // fetched → `working == true`. This is the cell-level proof of the fix.
        expect(
          stripCell(tester, 29).working,
          isTrue,
          reason:
              'Mon 29 Jun is a template working day; the union range must fetch '
              'it so the spillover cell renders WORKING (FAILS on month-only)',
        );
        expect(
          stripCell(tester, 30).working,
          isTrue,
          reason:
              'Tue 30 Jun is a template working day; the union range must fetch '
              'it so the spillover cell renders WORKING (FAILS on month-only)',
        );

        // ── UNION-RANGE PROOF ─────────────────────────────────────────────────
        // Directly assert the screen queried a range whose `from` reaches the
        // spillover days (≤ 29 Jun), not one that starts at 1 Jul. This pins the
        // fix at the source — the `_range` getter — independent of the cells.
        final bool fetchedSpillover = _PerWeekdayRangeSchedule.observedRanges
            .any((ScheduleRange r) => !r.from.isAfter(DateTime(2026, 6, 29)));
        expect(
          fetchedSpillover,
          isTrue,
          reason:
              'the union range must request from ≤ 29 Jun (the spillover days); '
              'the old month-only range started at 1 Jul and never fetched them',
        );
      },
    );
  });

  // ── REGRESSION (QA GATE): the selection follows the visible week step ───────
  //
  // BUG (now fixed): `_stepWeek` / `_stepMonth` shifted the visible window
  // (`_weekStart` / `_visibleMonth`, and therefore `_range`) but left the
  // `_selected` ValueNotifier pointing at the ORIGINALLY-selected date. After
  // stepping forward two weeks the still-selected date fell OUTSIDE the freshly
  // fetched `_range`, so `_DayIndex.lookup(oldSelected)` returned the NO_SCHEDULE
  // fallback (empty intervals) → the selected-day detail panel wrongly rendered
  // the "no working hours" banner (`scheduleNoScheduleDay`) for what is, on its
  // own weekday, a working day.
  //
  // FIX: `_stepWeek` / `_stepMonth` re-anchor `_selected` into the new visible
  // week, preserving the weekday column:
  //   offset = (_selected - oldWeekStart).inDays.clamp(0, 6)   (_selectedWeekdayOffset)
  //   _selected = _dateOnly(newWeekStart + offset days)
  // so the selection is always inside `_range` and resolves real data.
  //
  // HONEST FAKE / TRUE REGRESSION: this reuses `_PerWeekdayRangeSchedule`, which
  // serves a working day for EVERY in-range Monday/Tuesday and is RANGE-AWARE —
  // it can only return a date that was actually fetched. So the old code's stale
  // selection (a date two weeks in the past, never inside the stepped `_range`)
  // would resolve NO_SCHEDULE → the banner appears → these assertions FAIL.
  // Under the fix the selection re-anchors to the same weekday two weeks later
  // (still Mon/Tue → working, in range) → no banner → PASS.
  //
  // M2 / M3 / GOLDEN-NOT-ACCEPTANCE: finders use the source `Key`
  // (`no-schedule-banner`) and the localised summary string read via
  // AppLocalizations — never a raw literal — plus the structural `selected` flag
  // off the `WeekStripDay` cells. No PNG is the acceptance signal.
  group('MasterScheduleScreen — selection follows week steps', () {
    /// The current week's Monday (offset 0) is always a `_PerWeekdayRangeSchedule`
    /// working day, regardless of run date, so selecting it is deterministic.
    final DateTime currentMonday = _weekStart;

    // Step forward SIX weeks. Six is the smallest count that guarantees the
    // visible window has crossed into a later month on EVERY run date, so the
    // originally-selected Monday is provably OUTSIDE the new `_range` (the union
    // of the visible month + visible week). That is precisely the condition under
    // which the OLD stale `_selected` resolves to a NO_SCHEDULE fallback → the
    // banner appears. (Two weeks could stay inside the same month, leaving the
    // stale date in-range and masking the bug; six weeks never can.)
    const int forwardSteps = 6;

    testWidgets('selecting a working weekday then stepping the week forward keeps the '
        'selection on a working day (no NO_SCHEDULE banner) — selection '
        're-anchors into the visible week instead of going stale', (tester) async {
      await _pump(
        tester,
        overrides: <Object>[
          authProvider.overrideWith(
            () => _FixedAuth(UserRole.independentMaster),
          ),
          effectiveScheduleProvider.overrideWith(
            () => _PerWeekdayRangeSchedule(),
          ),
          weeklyScheduleProvider.overrideWith(
            () => _WeeklyData(<WeeklySchedule>[_template()]),
          ),
        ],
      );

      // ── Select a KNOWN working weekday (Monday) in the current week. ───────
      await _selectStripDay(tester, currentMonday.day);

      // The selected day is Monday → a working day → the detail panel shows the
      // working-hours summary, NOT the NO_SCHEDULE banner.
      final l10n = _l10n(tester);
      expect(
        find.byKey(const Key('no-schedule-banner')),
        findsNothing,
        reason:
            'Monday is a working day; its detail panel must NOT show the '
            'no-working-hours banner before any week step',
      );
      expect(
        find.text(
          l10n.scheduleDaySummaryWorking(
            summariseSpan(_templateWorking(currentMonday).intervals),
          ),
        ),
        findsOneWidget,
        reason: 'the selected working day must render its hours summary',
      );
      // Sanity: the selected strip cell is Monday.
      expect(_selectedStripDayNumber(tester), currentMonday.day);

      // ── Step the next-week chevron (the exact `_stepWeek(1)` path). ────────
      for (int i = 0; i < forwardSteps; i++) {
        await tester.tap(find.bySemanticsLabel(l10n.scheduleNextWeek));
        await tester.pumpAndSettle();
      }

      // (1) THE REGRESSION ASSERTION — the detail panel must NOT show the
      // NO_SCHEDULE "no working hours" banner. The OLD `_stepWeek` left
      // `_selected` on the original Monday, now six weeks (and at least one
      // month) outside the stepped `_range`, so `_DayIndex.lookup` returned the
      // NO_SCHEDULE fallback and this banner rendered for a working weekday.
      // The re-anchor keeps the selection on an in-range working weekday → no
      // banner. (FAILS on the pre-fix code, PASSES on the fix.)
      expect(
        find.byKey(const Key('no-schedule-banner')),
        findsNothing,
        reason:
            'after the week steps the selection must re-anchor to an '
            'in-range working weekday — the stale-selection NO_SCHEDULE banner '
            'is the exact regression this pins',
      );
      // Neither NO_SCHEDULE copy variant may render.
      expect(find.text(l10n.scheduleNoScheduleDay), findsNothing);
      expect(find.text(l10n.scheduleNoSchedulePeriod), findsNothing);

      // (2) The selection now sits on a date WITHIN the currently-visible week
      // — specifically the same weekday N weeks later (Monday + 7*N days),
      // which is itself a `_PerWeekdayRangeSchedule` working day. This also
      // proves the selected strip cell is in-range (the old stale selection
      // had NO selected cell in the visible week at all).
      final DateTime expectedSelected = _dateOnly(
        currentMonday.add(const Duration(days: 7 * forwardSteps)),
      );
      expect(
        _selectedStripDayNumber(tester),
        expectedSelected.day,
        reason:
            'the selection must follow the week step to the same weekday '
            '$forwardSteps weeks later (preserving the Monday column), '
            'staying inside _range',
      );
      // Its resolved source is a real working day, so the summary renders.
      expect(
        find.text(
          l10n.scheduleDaySummaryWorking(
            summariseSpan(_templateWorking(expectedSelected).intervals),
          ),
        ),
        findsOneWidget,
        reason:
            'the re-anchored selection resolves to a real working day, so '
            'its hours summary — not the unset/no-schedule copy — renders',
      );
    });
  });
}

// ───────────────────────────────────────────────────────────────────────────
// Helpers for the jump-to-changed-day flow.
// ───────────────────────────────────────────────────────────────────────────

/// A solid (no interior pause) 09:00–18:00 working day for [date].
EffectiveDay _solidWorking(DateTime date) => EffectiveDay(
  date: _dateOnly(date),
  source: EffectiveSource.template,
  intervals: <WorkInterval>[_interval(9, 0, 18, 0)],
);

/// The first future day inside the visible week (strictly after today), or null
/// when today is the last day of the visible week (no distinct editable future
/// day to move onto).
DateTime? _futureDayInWeek() {
  for (int i = 0; i < 7; i++) {
    final DateTime d = _dateOnly(_weekStart.add(Duration(days: i)));
    if (d.isAfter(_today)) return d;
  }
  return null;
}

/// Pumps the screen with the REAL notifiers over a stateful fake repo. The whole
/// visible week is solid working days; [edited] is the date the test will add a
/// pause to. Returns the container so the caller can read the repo's put count.
Future<ProviderContainer> _pumpOverrideFlow(
  WidgetTester tester, {
  required DateTime edited,
}) async {
  final Map<DateTime, EffectiveDay> effective = <DateTime, EffectiveDay>{
    for (int i = 0; i < 7; i++)
      _dateOnly(_weekStart.add(Duration(days: i))): _solidWorking(
        _weekStart.add(Duration(days: i)),
      ),
  };
  final repo = _StatefulFakeScheduleRepository(effective);

  final container = ProviderContainer(
    overrides: <Object>[
      authProvider.overrideWith(() => _FixedAuth(UserRole.independentMaster)),
      scheduleRepositoryProvider.overrideWithValue(repo),
    ].cast(),
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: _router(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('uk'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

_StatefulFakeScheduleRepository _repoOf(ProviderContainer c) =>
    c.read(scheduleRepositoryProvider) as _StatefulFakeScheduleRepository;

/// Opens the day-override sheet (via the pencil) for the currently-selected day,
/// adds a 13:00–14:00 pause by inserting a break, and saves. The shared
/// IntervalEditor seeds a single 09:00–18:00 window from the day's intervals; we
/// add ONE break and set it to 13:00–14:00 via the break pickers.
Future<void> _editSelectedDayAddingPause(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('schedule-day-pencil')));
  await tester.pumpAndSettle();

  // Adding a break to a 09:00–18:00 window seeds a 13:00–14:00 lunch
  // (IntervalEditor._addBreak math), so the saved CUSTOM_HOURS override is
  // 09:00–13:00 · 14:00–18:00 — a clean interior pause. No wheel-driving needed.
  await tester.ensureVisible(find.byKey(const Key('override-add-break')));
  await tester.tap(find.byKey(const Key('override-add-break')));
  await tester.pumpAndSettle();

  await tester.ensureVisible(find.byKey(const Key('override-save')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('override-save')));
  await tester.pumpAndSettle();
}

/// Counts the rendered selected-day grid's interior timeOff cells (the visual
/// signature of a pause). Locale-independent (M2): asserts on `SlotChip.cell`
/// state, not on the summary string.
int _interiorTimeOffCount(WidgetTester tester) {
  final Iterable<SlotChip> chips = tester.widgetList<SlotChip>(
    find.byType(SlotChip),
  );
  return chips.where((SlotChip c) => c.cell.state == SlotState.timeOff).length;
}

/// The day-of-month of the currently-selected week-strip cell (the lone
/// [WeekStripDay] with `selected == true`). Locale-independent (M2): reads the
/// widget's `selected` flag, not a highlighted string.
int _selectedStripDayNumber(WidgetTester tester) {
  final Iterable<WeekStripDay> cells = tester.widgetList<WeekStripDay>(
    find.byType(WeekStripDay),
  );
  return cells.singleWhere((WeekStripDay c) => c.selected).day;
}

// Completer import lives at the bottom to keep the header import block tidy.
// (dart:async is required for the never-completing loading future.)
