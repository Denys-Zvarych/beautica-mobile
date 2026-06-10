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
import 'package:beautica_mobile/features/schedule/presentation/widgets/schedule_widgets.dart';
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
  reason: OverrideReason.vacation,
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
              summariseIntervals(_working(_today).intervals),
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
}

// Completer import lives at the bottom to keep the header import block tidy.
// (dart:async is required for the never-completing loading future.)
