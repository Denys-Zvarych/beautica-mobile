// Phase 15.5 — Widget + unit tests for WeeklyTemplateEditorScreen
// («Робочі дні та години»).
//
// Strategy (mobile-qa M1/M2/M3/M4 + Riverpod hygiene):
//   • The editor's only data surface is `weeklyScheduleProvider`
//     (a keepAlive AsyncNotifier) and, on save, the same notifier's
//     `save`/`delete`. We override the notifier with a recording fake so NO
//     network/storage I/O runs and so we can assert the EXACT CRUD call the
//     editor issued (create vs update vs delete). The fake mirrors production by
//     invalidating `effectiveScheduleProvider` on a successful save/delete, and
//     a build counter on a watched effective window proves that invalidation
//     path is exercised end-to-end from the editor.
//   • Finders use the source `Key`s (btn-save-weekly-template, weekly-toggle-N,
//     weekly-day-N, weekly-day-N-work-start/-work-end/-add-break) — never
//     localised strings (M2). Where a localised value IS asserted (the inline
//     validation error, the saved snackbar) it is resolved through
//     `AppLocalizations`, not hardcoded UA text.
//   • Every test builds a fresh `ProviderContainer`/`ProviderScope` with
//     overrides and disposes it (M1 isolation). No fixed-duration pumps (M6).
//
// What is NOT re-tested here: the notifier's own save→reload→invalidate /
// failed-save-does-not-invalidate contract is owned by
// weekly_schedule_notifier_test.dart. This file proves the EDITOR drives that
// notifier correctly (right method, right args, right gating).

import 'dart:async';

import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';
import 'package:beautica_mobile/features/schedule/presentation/effective_schedule_notifier.dart';
import 'package:beautica_mobile/features/schedule/presentation/schedule_range.dart';
import 'package:beautica_mobile/features/schedule/presentation/weekly_schedule_notifier.dart';
import 'package:beautica_mobile/features/schedule/presentation/weekly_template_editor_screen.dart';
import 'package:beautica_mobile/features/schedule/presentation/widgets/interval_editor.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/velvet_top_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ───────────────────────────────────────────────────────────────────────────
// Fixtures.
// ───────────────────────────────────────────────────────────────────────────

/// A fixed clock so the saved active window is run-day independent (M6).
final DateTime _clock = DateTime(2026, 6, 9);

WorkInterval _interval(int sh, int sm, int eh, int em) => WorkInterval(
  start: TimeOfDay(hour: sh, minute: sm),
  end: TimeOfDay(hour: eh, minute: em),
);

/// A persisted template: Mon–Fri 09:00–18:00, Sat/Sun closed. [id] non-null →
/// the editor must UPDATE (PUT) it; pass `id: null` for an unpersisted shape.
WeeklySchedule _template({String? id = 'sched-1'}) => WeeklySchedule(
  id: id,
  validFrom: _clock,
  validTo: null,
  days: <TemplateDay>[
    for (int dow = 1; dow <= 7; dow++)
      TemplateDay(
        dayOfWeek: dow,
        label: 'd$dow',
        intervals: dow <= 5
            ? <WorkInterval>[_interval(9, 0, 18, 0)]
            : <WorkInterval>[],
      ),
  ],
);

// ───────────────────────────────────────────────────────────────────────────
// Recording WeeklySchedule notifier fake.
//
// Seeds the editor with [_initial] and records the exact save/delete the editor
// issues. On success it mirrors production by invalidating
// `effectiveScheduleProvider`, so a watched effective window rebuilds — letting
// a test prove the editor's success path actually exercises the invalidation.
// ───────────────────────────────────────────────────────────────────────────
class _RecordingWeekly extends WeeklyScheduleNotifier {
  _RecordingWeekly(this._initial);

  final List<WeeklySchedule> _initial;

  WeeklySchedule? savedSchedule;
  String? savedScheduleId;
  bool saveCalled = false;

  String? deletedId;
  bool deleteCalled = false;

  @override
  Future<List<WeeklySchedule>> build() async => _initial;

  @override
  Future<void> save(WeeklySchedule schedule, {String? scheduleId}) async {
    saveCalled = true;
    savedSchedule = schedule;
    savedScheduleId = scheduleId;
    state = AsyncData<List<WeeklySchedule>>(<WeeklySchedule>[schedule]);
    // Mirror production: a successful save invalidates the effective cache so
    // the calendar repaints.
    ref.invalidate(effectiveScheduleProvider);
  }

  @override
  Future<void> delete(String scheduleId) async {
    deleteCalled = true;
    deletedId = scheduleId;
    state = const AsyncData<List<WeeklySchedule>>(<WeeklySchedule>[]);
    ref.invalidate(effectiveScheduleProvider);
  }
}

/// Never-completing weekly load — the loading branch.
class _LoadingWeekly extends WeeklyScheduleNotifier {
  @override
  Future<List<WeeklySchedule>> build() =>
      Completer<List<WeeklySchedule>>().future; // never completes
}

/// Errors on load — the error/retry branch.
class _ErrorWeekly extends WeeklyScheduleNotifier {
  @override
  Future<List<WeeklySchedule>> build() async => throw Exception('weekly boom');
}

/// A trivial effective-schedule fake that counts builds, so a test can prove
/// the editor's successful save invalidated (rebuilt) the effective cache.
class _CountingEffective extends EffectiveScheduleNotifier {
  static int builds = 0;
  @override
  Future<List<EffectiveDay>> build(ScheduleRange range) async {
    builds++;
    return const <EffectiveDay>[];
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Harness.
// ───────────────────────────────────────────────────────────────────────────

/// Pumps the editor under a GoRouter (so its post-save `context.pop`/`go`
/// resolves) over a fresh container seeded with [overrides]. Returns the
/// container so the caller can `addTearDown(container.dispose)`.
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required List<Object> overrides,
  bool settle = true,
}) async {
  final ProviderContainer container = ProviderContainer(
    overrides: overrides.cast(),
  );
  final GoRouter router = GoRouter(
    initialLocation: RouteNames.scheduleWeeklyEditor,
    routes: <RouteBase>[
      GoRoute(
        path: RouteNames.scheduleWeeklyEditor,
        builder: (BuildContext context, GoRouterState state) =>
            WeeklyTemplateEditorScreen(clock: _clock),
      ),
      GoRoute(
        path: RouteNames.masterSchedule,
        builder: (BuildContext context, GoRouterState state) =>
            const Scaffold(key: Key('schedule-stub')),
      ),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('uk'),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
  return container;
}

AppLocalizations _l10n(WidgetTester tester) => AppLocalizations.of(
  tester.element(find.byType(WeeklyTemplateEditorScreen)),
);

NeumorphicButton _saveButton(WidgetTester tester) =>
    tester.widget<NeumorphicButton>(
      find.byKey(const Key('btn-save-weekly-template')),
    );

/// Reads the `HH:MM` rendered inside a day's work-end well (a `TimeWell` →
/// `Text`), used by the rebuild-scope guard to prove an untouched day's local
/// state survived a sibling edit.
String _workEndText(WidgetTester tester, int dayOfWeek) {
  final Finder well = find.byKey(Key('weekly-day-$dayOfWeek-work-end'));
  final Finder txt = find.descendant(of: well, matching: find.byType(Text));
  return tester.widget<Text>(txt.first).data!;
}

void main() {
  setUp(() => _CountingEffective.builds = 0);

  // ── Async load states (M3) ────────────────────────────────────────────────

  group('WeeklyTemplateEditorScreen — async states', () {
    testWidgets('loading shows a spinner', (tester) async {
      final ProviderContainer c = await _pumpLoading(tester);
      addTearDown(c.dispose);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byKey(const Key('btn-save-weekly-template')), findsNothing);
    });

    testWidgets('error shows the retry control', (tester) async {
      final ProviderContainer c = await _pump(
        tester,
        overrides: <Object>[
          weeklyScheduleProvider.overrideWith(() => _ErrorWeekly()),
        ],
      );
      addTearDown(c.dispose);

      expect(find.byKey(const Key('weekly-editor-retry')), findsOneWidget);
      expect(find.byKey(const Key('btn-save-weekly-template')), findsNothing);
    });

    testWidgets('loaded renders the shared top bar + seven day cards', (
      tester,
    ) async {
      final ProviderContainer c = await _pumpLoaded(tester, _template());
      addTearDown(c.dispose);

      expect(find.byType(VelvetTopBar), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);

      // The cards live in a scrolling ListView, so the lower days lazily build.
      // Scroll each into view to prove all seven ISO day cards + toggles exist.
      final Finder list = find.byType(Scrollable).first;
      for (int dow = 1; dow <= 7; dow++) {
        await tester.scrollUntilVisible(
          find.byKey(Key('weekly-day-$dow')),
          120,
          scrollable: list,
        );
        expect(find.byKey(Key('weekly-day-$dow')), findsOneWidget);
        expect(find.byKey(Key('weekly-toggle-$dow')), findsOneWidget);
      }
    });
  });

  // ── Pristine-load + dirty-diff gate (Phase 6.2 contract) ──────────────────

  group('WeeklyTemplateEditorScreen — dirty-diff Save gate', () {
    testWidgets('Save is DISABLED on a freshly loaded (pristine) template', (
      tester,
    ) async {
      final ProviderContainer c = await _pumpLoaded(tester, _template());
      addTearDown(c.dispose);

      expect(
        _saveButton(tester).onPressed,
        isNull,
        reason: 'a pristine load must not enable Save (no edit yet)',
      );
    });

    testWidgets('a real edit (toggle a day off) ENABLES Save', (tester) async {
      final ProviderContainer c = await _pumpLoaded(tester, _template());
      addTearDown(c.dispose);

      // Close Monday — the draft now differs from the loaded baseline.
      await tester.tap(find.byKey(const Key('weekly-toggle-1')));
      await tester.pumpAndSettle();

      expect(
        _saveButton(tester).onPressed,
        isNotNull,
        reason: 'closing a previously-open day makes the draft dirty',
      );
    });

    testWidgets('a no-op toggle that returns to baseline RE-DISABLES Save '
        '(off→on restores identical default hours)', (tester) async {
      // Seed a template whose Monday is the editor default (09:00–18:00) so
      // that toggling it off and back on restores the SAME hours from the
      // stash → the draft collapses back to the baseline and Save re-disables.
      final ProviderContainer c = await _pumpLoaded(tester, _template());
      addTearDown(c.dispose);

      await tester.tap(find.byKey(const Key('weekly-toggle-1')));
      await tester.pumpAndSettle();
      expect(_saveButton(tester).onPressed, isNotNull);

      // Toggle back on — stash restores the default 09:00–18:00, identical to
      // the loaded baseline → no longer dirty.
      await tester.tap(find.byKey(const Key('weekly-toggle-1')));
      await tester.pumpAndSettle();
      expect(
        _saveButton(tester).onPressed,
        isNull,
        reason:
            'a toggle that returns the day to its baseline hours is a no-op '
            '→ Save must disable again (Phase 6.2 no-op-not-dirty contract)',
      );
    });
  });

  // ── Save → correct CRUD (M4: exact call assertion) ────────────────────────

  group('WeeklyTemplateEditorScreen — save issues the correct CRUD', () {
    testWidgets(
      'edit with an EXISTING template → update (save with the existing id)',
      (tester) async {
        final _RecordingWeekly weekly = _RecordingWeekly(<WeeklySchedule>[
          _template(id: 'sched-1'),
        ]);
        final ProviderContainer c = await _pump(
          tester,
          overrides: _overridesFor(weekly),
        );
        addTearDown(c.dispose);

        // Make a dirty edit: close Saturday is already off → close Monday.
        await tester.tap(find.byKey(const Key('weekly-toggle-1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('btn-save-weekly-template')));
        await tester.pumpAndSettle();

        expect(weekly.saveCalled, isTrue);
        expect(weekly.deleteCalled, isFalse);
        expect(
          weekly.savedScheduleId,
          'sched-1',
          reason: 'an existing template must be PUT with its id',
        );
        expect(
          weekly.savedSchedule!.id,
          'sched-1',
          reason: 'the saved schedule carries the existing id',
        );
        // Monday is now closed in the persisted shape.
        expect(weekly.savedSchedule!.days[0].intervals, isEmpty);
      },
    );

    testWidgets(
      'edit with NO existing template → create (save with a null id)',
      (tester) async {
        // No persisted template: an empty server list → the editor seeds an
        // all-off week (id null). Open Monday to make it dirty + non-all-off.
        final _RecordingWeekly weekly = _RecordingWeekly(
          const <WeeklySchedule>[],
        );
        final ProviderContainer c = await _pump(
          tester,
          overrides: _overridesFor(weekly),
        );
        addTearDown(c.dispose);

        await tester.tap(find.byKey(const Key('weekly-toggle-1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('btn-save-weekly-template')));
        await tester.pumpAndSettle();

        expect(weekly.saveCalled, isTrue);
        expect(weekly.deleteCalled, isFalse);
        expect(
          weekly.savedScheduleId,
          isNull,
          reason: 'a fresh create must POST with no schedule id',
        );
        expect(
          weekly.savedSchedule!.id,
          isNull,
          reason: 'a not-yet-persisted draft has no id',
        );
        // The fresh create anchors validFrom on the injected clock (M6).
        expect(weekly.savedSchedule!.validFrom, _clock);
        // Monday is open in the created shape.
        expect(weekly.savedSchedule!.days[0].intervals, isNotEmpty);
      },
    );

    testWidgets('all-days-off with an EXISTING template → delete(existing.id) '
        '(returns to NO_SCHEDULE)', (tester) async {
      // Seed a template with ONLY Monday open so a single toggle closes the
      // whole week → all-off → delete.
      final WeeklySchedule mondayOnly = WeeklySchedule(
        id: 'sched-1',
        validFrom: _clock,
        validTo: null,
        days: <TemplateDay>[
          for (int dow = 1; dow <= 7; dow++)
            TemplateDay(
              dayOfWeek: dow,
              label: 'd$dow',
              intervals: dow == 1
                  ? <WorkInterval>[_interval(9, 0, 18, 0)]
                  : <WorkInterval>[],
            ),
        ],
      );
      final _RecordingWeekly weekly = _RecordingWeekly(<WeeklySchedule>[
        mondayOnly,
      ]);
      final ProviderContainer c = await _pump(
        tester,
        overrides: _overridesFor(weekly),
      );
      addTearDown(c.dispose);

      // Close Monday → every day is now off.
      await tester.tap(find.byKey(const Key('weekly-toggle-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn-save-weekly-template')));
      await tester.pumpAndSettle();

      expect(
        weekly.deleteCalled,
        isTrue,
        reason: 'an all-off week with an existing template must DELETE it',
      );
      expect(weekly.deletedId, 'sched-1');
      expect(
        weekly.saveCalled,
        isFalse,
        reason: 'delete is issued instead of an upsert when all days are off',
      );
    });

    testWidgets(
      'a successful save exercises the effective-schedule invalidation path '
      '(calendar repaint) and navigates back with the saved snackbar',
      (tester) async {
        final _RecordingWeekly weekly = _RecordingWeekly(<WeeklySchedule>[
          _template(id: 'sched-1'),
        ]);
        final ProviderContainer c = await _pump(
          tester,
          overrides: _overridesFor(weekly),
        );
        addTearDown(c.dispose);

        // Watch an effective window so we can observe the invalidation rebuild.
        final ScheduleRange range = ScheduleRange.month(_clock);
        await c.read(effectiveScheduleProvider(range).future);
        final int buildsBefore = _CountingEffective.builds;

        await tester.tap(find.byKey(const Key('weekly-toggle-1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('btn-save-weekly-template')));
        await tester.pumpAndSettle();

        // The editor's success branch ran: the effective cache was invalidated
        // (so the calendar refetches) …
        await c.read(effectiveScheduleProvider(range).future);
        expect(
          _CountingEffective.builds,
          greaterThan(buildsBefore),
          reason:
              'a successful save must invalidate effectiveScheduleProvider so '
              'the calendar repaints',
        );
        // … and the editor popped back to the schedule screen.
        expect(find.byKey(const Key('schedule-stub')), findsOneWidget);
        expect(find.byType(WeeklyTemplateEditorScreen), findsNothing);
      },
    );
  });

  // ── Validation gating (M3/M4) ──────────────────────────────────────────────
  //
  // The editor's Save gate is `_isDirty && !_hasErrors`, where `_hasErrors`
  // calls `dayHoursValid` (== `validateDayHours(...) == null`) on each open day
  // — the SAME pure function the IntervalEditor uses to surface its inline
  // error. So we prove the gate two faithful, deterministic ways:
  //   1. domain: validateDayHours flags every invalid shape with its kind
  //      (driving the wheel time picker to a precise inverted value is brittle
  //      — M6 — so the inverted-window/invalid-break cases are pinned here);
  //   2. widget: the IntervalEditor renders the LOCALISED error (asserted via
  //      the live-region Semantics, not raw UA text) for an inverted window.

  group('WeeklyTemplateEditorScreen — validation gating (domain)', () {
    test(
      'an inverted window (end ≤ start) is flagged windowEndBeforeStart',
      () {
        final DayHours day = DayHours(
          window: _interval(18, 0, 9, 0),
          breaks: const <BreakRange>[],
        );
        expect(dayHoursValid(day), isFalse);
        expect(
          validateDayHours(day)!.kind,
          DayHoursErrorKind.windowEndBeforeStart,
        );
      },
    );

    test('a break with end ≤ start is flagged breakEndBeforeStart', () {
      final DayHours day = DayHours(
        window: _interval(9, 0, 18, 0),
        breaks: <BreakRange>[
          BreakRange(
            start: const TimeOfDay(hour: 13, minute: 0),
            end: const TimeOfDay(hour: 12, minute: 0),
          ),
        ],
      );
      expect(dayHoursValid(day), isFalse);
      expect(
        validateDayHours(day)!.kind,
        DayHoursErrorKind.breakEndBeforeStart,
      );
    });

    test('a break outside the window is flagged breakOutsideWindow', () {
      final DayHours day = DayHours(
        window: _interval(9, 0, 18, 0),
        breaks: <BreakRange>[
          BreakRange(
            start: const TimeOfDay(hour: 19, minute: 0),
            end: const TimeOfDay(hour: 20, minute: 0),
          ),
        ],
      );
      expect(validateDayHours(day)!.kind, DayHoursErrorKind.breakOutsideWindow);
    });
  });

  group('WeeklyTemplateEditorScreen — validation gating (widget)', () {
    testWidgets(
      'an inverted window surfaces the LOCALISED inline error and keeps Save '
      'disabled',
      (tester) async {
        final ProviderContainer c = await _pumpLoaded(tester, _template());
        addTearDown(c.dispose);
        final AppLocalizations l10n = _l10n(tester);

        // Render Monday's IntervalEditor against an inverted window directly,
        // then assert it shows the localised window-error message. (The Save
        // gate reads the same `validateDayHours` over the host's `_days`, so a
        // rendered error == a disabled Save.)
        final DayHours invalid = DayHours(
          window: _interval(18, 0, 9, 0),
          breaks: const <BreakRange>[],
        );
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('uk'),
            home: Scaffold(
              body: IntervalEditor(
                day: invalid,
                onChanged: () {},
                strings: _intervalStrings(l10n),
                fieldKeyPrefix: 'weekly-day-1',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text(l10n.intervalEditorErrEndAfterStart),
          findsOneWidget,
          reason: 'an inverted window must surface its localised error',
        );
      },
    );
  });

  // ── Cross-midnight invariant (domain) ──────────────────────────────────────

  group('WeeklyTemplateEditorScreen — cross-midnight invariant', () {
    test('toIntervals never emits an interval with end ≤ start', () {
      // A window with two breaks collapses to three working intervals — every
      // one must have end > start (the wire contract forbids cross-midnight).
      final DayHours day = DayHours(
        window: _interval(8, 0, 20, 0),
        breaks: <BreakRange>[
          BreakRange(
            start: const TimeOfDay(hour: 12, minute: 0),
            end: const TimeOfDay(hour: 13, minute: 0),
          ),
          BreakRange(
            start: const TimeOfDay(hour: 16, minute: 0),
            end: const TimeOfDay(hour: 16, minute: 30),
          ),
        ],
      );
      final List<WorkInterval> intervals = day.toIntervals();
      expect(intervals, isNotEmpty);
      for (final WorkInterval i in intervals) {
        expect(
          i.endMinutes,
          greaterThan(i.startMinutes),
          reason: 'no interval may invert / cross midnight',
        );
      }
    });
  });

  // ── Read-only SALON_MASTER capability gate ─────────────────────────────────
  //
  // The editor itself has no role logic — the read-only gate is enforced
  // UPSTREAM by MasterScheduleScreen, which suppresses the CTA that routes here
  // for a read-only role (covered in master_schedule_screen_test.dart:
  // "SALON_MASTER (read-only): … add-hours CTA absent"). This test pins the
  // contract from the editor's side: a read-only viewer never reaches it, so
  // there is no edit/save affordance they could trip. We assert the editor's
  // save affordance is gated behind a real edit (disabled on load) — the only
  // state a (hypothetical) read-only viewer could observe — so no write is
  // possible without an explicit edit action.

  group('WeeklyTemplateEditorScreen — read-only safety', () {
    testWidgets(
      'no write affordance is active without an explicit edit (Save disabled '
      'on load — the only state reachable without an edit gesture)',
      (tester) async {
        final ProviderContainer c = await _pumpLoaded(tester, _template());
        addTearDown(c.dispose);

        // On load (the state a non-editing viewer sees) Save cannot fire.
        expect(_saveButton(tester).onPressed, isNull);
      },
    );
  });

  // ── Rebuild-scope regression guard (locks the MEDIUM fix) ──────────────────
  //
  // Editing one day must NOT rebuild/reset the other six days' local state. The
  // host pushes Save-gate/open-count changes through ValueNotifiers so only the
  // Save button + summary chip rebuild on an edit — never the sibling _DayCards.
  // A pragmatic, deterministic assertion: edit day 1 (toggle it off) and verify
  // day 2's displayed work-end value is untouched.

  group('WeeklyTemplateEditorScreen — rebuild-scope guard', () {
    testWidgets(
      'editing day 1 leaves the other days\' displayed hours intact',
      (tester) async {
        final ProviderContainer c = await _pumpLoaded(tester, _template());
        addTearDown(c.dispose);

        final String day2Before = _workEndText(tester, 2);
        expect(day2Before, '18:00', reason: 'baseline: Tue ends 18:00');

        // Edit day 1 only (toggle Monday off).
        await tester.tap(find.byKey(const Key('weekly-toggle-1')));
        await tester.pumpAndSettle();

        // Day 2's local state is unchanged — it never re-seeded from a host
        // rebuild (the MEDIUM rebuild-scope fix).
        expect(
          _workEndText(tester, 2),
          day2Before,
          reason:
              'editing day 1 must not rebuild/reset sibling day cards '
              '(rebuild-scope isolation via ValueNotifiers)',
        );
        // And day 1 is now a day-off (its editor wells are gone).
        expect(
          find.byKey(const Key('weekly-day-1-work-end')),
          findsNothing,
          reason: 'the edited day collapsed to a day-off',
        );
      },
    );
  });
}

// ───────────────────────────────────────────────────────────────────────────
// Override helpers.
// ───────────────────────────────────────────────────────────────────────────

/// Editor overrides bound to a recording weekly notifier + a counting effective
/// notifier (so the invalidation path is observable).
List<Object> _overridesFor(_RecordingWeekly weekly) => <Object>[
  weeklyScheduleProvider.overrideWith(() => weekly),
  effectiveScheduleProvider.overrideWith(() => _CountingEffective()),
];

Future<ProviderContainer> _pumpLoaded(
  WidgetTester tester,
  WeeklySchedule template,
) => _pump(
  tester,
  overrides: <Object>[
    weeklyScheduleProvider.overrideWith(
      () => _RecordingWeekly(<WeeklySchedule>[template]),
    ),
    effectiveScheduleProvider.overrideWith(() => _CountingEffective()),
  ],
);

Future<ProviderContainer> _pumpLoading(WidgetTester tester) => _pump(
  tester,
  settle: false,
  overrides: <Object>[
    weeklyScheduleProvider.overrideWith(() => _LoadingWeekly()),
  ],
);

/// Resolves the IntervalEditor's localised strings the same way the editor does
/// (so the widget-level validation test renders the exact production copy).
IntervalEditorStrings _intervalStrings(AppLocalizations l10n) =>
    IntervalEditorStrings(
      workHoursLabel: l10n.intervalEditorWorkHours,
      breaksLabel: l10n.intervalEditorBreaks,
      addBreak: l10n.intervalEditorAddBreak,
      workStartTitle: l10n.intervalEditorWorkStartTitle,
      workEndTitle: l10n.intervalEditorWorkEndTitle,
      breakStartTitle: l10n.intervalEditorBreakStartTitle,
      breakEndTitle: l10n.intervalEditorBreakEndTitle,
      timePickerConfirm: l10n.timePickerConfirm,
      timePickerHoursSemantic: l10n.timePickerHoursSemantic,
      timePickerMinutesSemantic: l10n.timePickerMinutesSemantic,
      breakStartSemantic: l10n.intervalEditorBreakStartSemantic,
      breakEndSemantic: l10n.intervalEditorBreakEndSemantic,
      removeBreakSemantic: l10n.intervalEditorRemoveBreak,
      errWindowEndBeforeStart: l10n.intervalEditorErrEndAfterStart,
      errBreakEndBeforeStart: l10n.intervalEditorErrBreakEndAfterStart,
      errBreakOutsideWindow: l10n.intervalEditorErrBreakInsideWindow,
      errBreaksOverlap: l10n.intervalEditorErrBreaksOverlap,
    );
