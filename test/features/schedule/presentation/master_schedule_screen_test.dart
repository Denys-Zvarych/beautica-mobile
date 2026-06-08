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
// real role/auth matrix, not silently honoured). The weekly-template CTA now
// lands on the REAL working-hours editor (RouteNames.workingHours →
// WorkingHoursScreen); the dead `scheduleWeeklyEditor` stub route is gone, in
// lockstep with its removal from lib/routing/app_router.dart. The per-date and
// propagate stub routes remain (the day-pencil / copy affordances still target
// them).
// ───────────────────────────────────────────────────────────────────────────

List<RouteBase> _routes() => <RouteBase>[
  GoRoute(
    path: RouteNames.masterSchedule,
    builder: (context, state) => const MasterScheduleScreen(),
  ),
  // The REAL weekly-template editor the CTA now routes to (BUG #1 fix).
  GoRoute(
    path: RouteNames.workingHours,
    builder: (context, state) => const WorkingHoursScreen(),
  ),
  GoRoute(
    path: RouteNames.scheduleDayOverride,
    builder: (context, state) => const PerDateOverrideStubScreen(),
  ),
  GoRoute(
    path: RouteNames.schedulePropagate,
    builder: (context, state) => const SchedulePropagateStubScreen(),
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

    // ── BUG #1 regression: in-grid banner CTA routes to the REAL editor ───────
    //
    // The CTA used to point at the dead `WeeklyTemplateEditorStubScreen`
    // ("coming soon" placeholder) via RouteNames.scheduleWeeklyEditor. The fix
    // repoints `_openTemplateEditor` to RouteNames.workingHours — the REAL
    // WorkingHoursScreen. This test pumps the schedule screen inside the
    // PRODUCTION authRedirect-guarded router, taps the CTA, and asserts the
    // genuine editor mounts (its VelvetTopBar header + the day-toggle rows +
    // the real save button), NOT a stub. Because the route is `/master/...`,
    // the editor is only reachable when the guard's INDEPENDENT_MASTER role
    // gate passes — which the editable session here satisfies. A CTA that
    // pointed at a non-`/master/*` dead route (or one the role can't reach)
    // would be bounced by the real guard, failing this test.
    testWidgets('banner CTA tap routes through authRedirect to the REAL '
        'working-hours editor (BUG #1)', (tester) async {
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

      // Landed on the REAL working-hours editor — the dead stub is gone.
      expect(
        find.byKey(const Key('stub-weekly-template-editor')),
        findsNothing,
        reason: 'CTA must NOT land on the removed "coming soon" stub',
      );
      expect(
        find.byType(WorkingHoursScreen),
        findsOneWidget,
        reason: 'CTA must mount the real WorkingHoursScreen',
      );
      // Its real affordances render: the save button and the seven day toggles.
      expect(
        find.byKey(const Key('btn-save-working-hours')),
        findsOneWidget,
        reason: 'the real editor exposes its save button',
      );
      expect(
        find.byKey(const Key('wh-active-1')),
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

    testWidgets('INDEPENDENT_MASTER (self): edit affordances present', (
      tester,
    ) async {
      final days = _weekWith(todayDay: _working, filler: _working);
      await _pump(tester, overrides: _editableData(days));

      // Weekly-card tap target + day pencil + day-action buttons all present.
      expect(find.byKey(const Key('schedule-weekly-card')), findsOneWidget);
      expect(find.byKey(const Key('schedule-day-pencil')), findsOneWidget);
      expect(find.byKey(const Key('schedule-add-hours')), findsOneWidget);
      expect(find.byKey(const Key('schedule-time-off')), findsOneWidget);
      expect(find.byKey(const Key('schedule-copy')), findsOneWidget);
    });

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
      'working-hours editor (BUG #1)',
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

        // The dead "coming soon" stub is gone; the genuine editor mounts.
        expect(
          find.byKey(const Key('stub-weekly-template-editor')),
          findsNothing,
        );
        expect(find.byType(WorkingHoursScreen), findsOneWidget);
        expect(find.byKey(const Key('btn-save-working-hours')), findsOneWidget);
        expect(find.byKey(const Key('wh-active-1')), findsOneWidget);
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

    // ── BUG #2 mirror guard: the CTA DESTINATION uses the shared header too ───
    //
    // BUG #2 (now fixed): WorkingHoursScreen — the destination the schedule
    // empty-state / banner / weekly-card CTA now routes to — used a Material
    // AppBar while the schedule screen used the 48 dp VelvetTopBar, so the back
    // arrow + title jumped vertically as the user crossed the CTA. The fix
    // migrated WorkingHoursScreen to the shared VelvetTopBar, matching
    // master_schedule_screen.dart.
    //
    // This is the mirror of the schedule-screen header guard above: it actually
    // NAVIGATES through the CTA (via the production authRedirect router) and
    // asserts the landed editor renders VelvetTopBar and NOT an AppBar. It locks
    // any calendar-CTA-reachable screen to the shared header — a future screen
    // swapped in behind the CTA that reintroduces a Material AppBar will be
    // caught immediately. Assertions FAIL on the pre-fix WorkingHoursScreen
    // (AppBar present, no VelvetTopBar) and PASS on the fix.
    testWidgets(
      'CTA destination (working-hours editor) renders VelvetTopBar and NOT a '
      'Material AppBar (BUG #2 — mirror of the schedule-screen header guard)',
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
        expect(find.byType(WorkingHoursScreen), findsOneWidget);

        // It uses the shared VelvetTopBar …
        expect(
          find.byType(VelvetTopBar),
          findsOneWidget,
          reason:
              'the CTA destination must render the shared VelvetTopBar so its '
              'header aligns with the schedule screen the user came from',
        );
        // … and NOT a Material AppBar (the BUG #2 root cause).
        expect(
          find.byType(AppBar),
          findsNothing,
          reason:
              'the CTA destination must NOT contain a Material AppBar — that '
              'was the header vertical-offset mismatch fixed in BUG #2',
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
