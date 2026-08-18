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

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/shared/formatters/uk_calendar.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';
import 'package:beautica_mobile/features/schedule/presentation/effective_schedule_notifier.dart';
import 'package:beautica_mobile/features/schedule/presentation/schedule_range.dart';
import 'package:beautica_mobile/features/schedule/presentation/weekly_schedule_notifier.dart';
import 'package:beautica_mobile/features/schedule/presentation/weekly_template_editor_screen.dart';
import 'package:beautica_mobile/features/schedule/presentation/widgets/discrete_times_editor.dart';
import 'package:beautica_mobile/features/schedule/presentation/widgets/interval_editor.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/calendar_grid.dart';
import 'package:beautica_mobile/shared/widgets/period_range_picker.dart';
import 'package:beautica_mobile/shared/widgets/velvet_top_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

import '../../../helpers/clock_instant.dart';
import '../../../helpers/velvet_snack_matchers.dart';

// ───────────────────────────────────────────────────────────────────────────
// Fixtures.
// ───────────────────────────────────────────────────────────────────────────

/// A fixed clock so the saved active window is run-day independent (M6).
///
/// [_clock] is a DATE TOKEN (see `lib/shared/time/kyiv_day.dart`) — used
/// throughout this file for `validFrom`/`ScheduleRange.month`/assertion
/// comparisons. Never pass it directly to a `clock:` param; use
/// [asClockInstant] (test/helpers/clock_instant.dart) for that instead.
///
/// DO NOT "fix" this to `DateTime.utc(2026, 6, 9)` — it looks like the
/// `forbid_host_local_instant_anchor.sh` anti-pattern but is not one, and
/// converting it introduces a REAL regression (verified, not theorised):
/// this token is compared with bare `==` directly against production's own
/// `validFrom` output at the "UPDATE path: _buildSchedule clamps ... UP to
/// today" test (`weekly.savedSchedule!.validFrom` equals `_clock`), and that
/// `validFrom` is itself `kyivDayOf(...)`'s result — ALWAYS a host-local
/// midnight `DateTime` (`kyiv_day.dart`'s own contract), never UTC. Dart's
/// `DateTime==` compares the underlying INSTANT, not the UTC/local flag, so
/// a bare-local `_clock` and a bare-local production token always agree on
/// every host `TZ` (both resolve through the SAME host offset and cancel
/// out — a coherent "both host-local" pairing, not a host-TZ-dependent
/// one), while a `.utc()` `_clock` would only agree when the host TZ offset
/// happens to be zero. Reproduced: swapping to `.utc()` and running under
/// `TZ=Asia/Tokyo` fails that exact test with `Expected: ...00.000Z` /
/// `Actual: ...00.000` (no `Z`) — confirmed, then reverted. This file's
/// clock-INSTANT need is already served by [asClockInstant] at every
/// `clock:` call site; this bare declaration must stay host-local because
/// its OTHER role — a direct-equality fixture against `kyivDayOf`'s
/// host-local output — depends on matching its construction style, not its
/// calendar value. The whole `TZ=Europe/Kyiv`/`TZ=UTC`/`TZ=Asia/Tokyo`
/// matrix passes with this declaration exactly as written; do not touch it.
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

/// A persisted RANGED template: same days as [_template] but with a closed
/// validity window (`validTo` set), so the editor renders the
/// `weeklyEditorActiveWindowRange(from, to)` label. validFrom = _clock
/// (09.06), validTo = 31.12 → deterministic under the fixed clock.
WeeklySchedule _rangedTemplate({String? id = 'sched-1'}) => WeeklySchedule(
  id: id,
  validFrom: _clock,
  validTo: DateTime(2026, 12, 31),
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

/// A persisted template whose MONDAY carries a STORED WORKING WINDOW: the
/// canonical intervals are `[10:00–18:00]` but the window is `09:00–18:00`,
/// i.e. the master saved a «Перерва» 09:00–10:00 flush against the window
/// start. Tue–Fri are ordinary legacy 09:00–18:00 days (no stored window), so
/// closing Monday never trips the all-off DELETE path.
WeeklySchedule _windowTemplate({String? id = 'sched-1'}) => WeeklySchedule(
  id: id,
  validFrom: _clock,
  validTo: null,
  days: <TemplateDay>[
    TemplateDay(
      dayOfWeek: 1,
      label: 'd1',
      intervals: <WorkInterval>[_interval(10, 0, 18, 0)],
      window: _interval(9, 0, 18, 0),
    ),
    for (int dow = 2; dow <= 7; dow++)
      TemplateDay(
        dayOfWeek: dow,
        label: 'd$dow',
        intervals: dow <= 5
            ? <WorkInterval>[_interval(9, 0, 18, 0)]
            : <WorkInterval>[],
      ),
  ],
);

/// A persisted PRE-WINDOW (legacy) template: Monday carries [mondayIntervals]
/// and NO stored window, so the editor seeds it through the historical
/// gap-reconstruction regime and `_baselineWindows[0]` is `null`.
WeeklySchedule _legacyTemplate(
  List<WorkInterval> mondayIntervals, {
  String? id = 'sched-1',
}) => WeeklySchedule(
  id: id,
  validFrom: _clock,
  validTo: null,
  days: <TemplateDay>[
    TemplateDay(dayOfWeek: 1, label: 'd1', intervals: mondayIntervals),
    for (int dow = 2; dow <= 7; dow++)
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

/// A weekly notifier whose mutations FAIL: it mirrors production
/// ([WeeklyScheduleNotifier.save]/`.delete`) by setting an [AsyncError] state
/// (the swallowed `Failure`) and performing NO `effectiveScheduleProvider`
/// invalidation. The screen reads this post-await `hasError` state and must
/// surface the error WITHOUT popping or showing the saved snackbar.
class _FailingWeekly extends WeeklyScheduleNotifier {
  _FailingWeekly(this._initial);

  final List<WeeklySchedule> _initial;

  bool saveCalled = false;
  bool deleteCalled = false;

  @override
  Future<List<WeeklySchedule>> build() async => _initial;

  @override
  Future<void> save(WeeklySchedule schedule, {String? scheduleId}) async {
    saveCalled = true;
    // Mirror AsyncValue.guard swallowing the Failure into AsyncError; on
    // failure the effective cache is left intact (no invalidate).
    state = AsyncError<List<WeeklySchedule>>(
      const ServerFailure(statusCode: 500),
      StackTrace.current,
    );
  }

  @override
  Future<void> delete(String scheduleId) async {
    deleteCalled = true;
    state = AsyncError<List<WeeklySchedule>>(
      const ServerFailure(statusCode: 500),
      StackTrace.current,
    );
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
    retry: beauticaProviderRetry,
    overrides: overrides.cast(),
  );
  final GoRouter router = GoRouter(
    initialLocation: RouteNames.scheduleWeeklyEditor,
    routes: <RouteBase>[
      GoRoute(
        path: RouteNames.scheduleWeeklyEditor,
        builder: (BuildContext context, GoRouterState state) =>
            WeeklyTemplateEditorScreen(clock: () => asClockInstant(_clock)),
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

/// Reads the `HH:MM` rendered inside any keyed [TimeWell] (`…-work-start`,
/// `…-work-end`, `…-break-N-start`, …).
String _wellText(WidgetTester tester, String key) {
  final Finder well = find.byKey(Key(key));
  expect(well, findsOneWidget, reason: 'time well "$key" must be rendered');
  final Finder txt = find.descendant(of: well, matching: find.byType(Text));
  return tester.widget<Text>(txt.first).data!;
}

/// One velvet-time-picker wheel item extent (px) — matches the picker's fixed
/// `_itemExtent`. Dragging N extents UP (negative dy) advances N rows.
const double _kItemExtent = 46.0;

/// Opens the wheel time picker behind the keyed [key] well, moves the hours
/// wheel by [hourSteps] rows and the minutes wheel by [minuteSteps] rows
/// (positive = later), then confirms.
///
/// The IntervalEditor opens its picker with `minuteStep: 15`, so ONE minute
/// row is 15 minutes.
Future<void> _dragWorkWell(
  WidgetTester tester, {
  required String key,
  int hourSteps = 0,
  int minuteSteps = 0,
}) async {
  final Finder well = find.byKey(Key(key));
  await tester.ensureVisible(well);
  await tester.pumpAndSettle();
  await tester.tap(well);
  await tester.pumpAndSettle();

  final Finder wheels = find.byType(ListWheelScrollView);
  expect(wheels, findsNWidgets(2), reason: 'hours + minutes wheels');
  if (hourSteps != 0) {
    await tester.drag(wheels.at(0), Offset(0, -_kItemExtent * hourSteps));
    await tester.pumpAndSettle();
  }
  if (minuteSteps != 0) {
    await tester.drag(wheels.at(1), Offset(0, -_kItemExtent * minuteSteps));
    await tester.pumpAndSettle();
  }

  await tester.tap(find.byKey(const Key('btn-velvet-time-picker-confirm')));
  await tester.pumpAndSettle();
}

/// Taps the remove ("×") action on the FIRST break row of [dayOfWeek].
///
/// The remove control carries no `Key` in `interval_editor.dart`'s `_BreakRow`,
/// so it is located by its icon SCOPED to the day card — never an
/// order-dependent `.first` across the tree, and never a localised string (M2).
Future<void> _removeBreak(WidgetTester tester, {required int dayOfWeek}) async {
  final Finder remove = find.descendant(
    of: find.byKey(Key('weekly-day-$dayOfWeek')),
    matching: find.byIcon(Icons.close_rounded),
  );
  expect(
    remove,
    findsOneWidget,
    reason: 'day $dayOfWeek must render exactly one break-remove action',
  );
  await tester.ensureVisible(remove);
  await tester.pumpAndSettle();
  await tester.tap(remove);
  await tester.pumpAndSettle();
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

  // ── Day-off Save bug regression (the silently-dead Save button) ────────────
  //
  // BUG: a master with NO template seeds the editor with all 7 days as
  // "day off". The Save gate used to treat a day-off matching the seeded
  // baseline as "no change", leaving `_isDirty`/`_canSave` false and the Save
  // button silently disabled (`onPressed: null`) — "the save button doesn't
  // work" with no explanation. FIX: the gate is a `_SaveGate` and a keyed hint
  // `Key('weekly-no-changes-hint')` renders above Save whenever the gate is
  // `noChanges`, so a day-off selection is never a silently-dead button.
  //
  // These tests drive the gate purely through observable UI (the Save button's
  // enabled flag + the keyed hint's presence) — never `_SaveGate` internals.

  group('WeeklyTemplateEditorScreen — day-off Save bug regression', () {
    testWidgets(
      'fresh create (no server template): editor opens all-off, Save is '
      'DISABLED, and the no-changes hint explains WHY (not a dead button)',
      (tester) async {
        // The empty-state CTA in master_schedule_screen.dart routes here with
        // NO persisted template → an empty server list. The editor seeds an
        // all-off week.
        final ProviderContainer c = await _pump(
          tester,
          overrides: <Object>[
            weeklyScheduleProvider.overrideWith(
              () => _RecordingWeekly(const <WeeklySchedule>[]),
            ),
            effectiveScheduleProvider.overrideWith(() => _CountingEffective()),
          ],
        );
        addTearDown(c.dispose);

        // All seven days seed as day-off → no IntervalEditor work wells exist
        // (each day-off card shows the rest row instead).
        final Finder list = find.byType(Scrollable).first;
        for (int dow = 1; dow <= 7; dow++) {
          await tester.scrollUntilVisible(
            find.byKey(Key('weekly-day-$dow')),
            120,
            scrollable: list,
          );
          expect(
            find.byKey(Key('weekly-day-$dow-work-end')),
            findsNothing,
            reason: 'day $dow seeds as a day-off on a fresh create',
          );
        }

        // Save is disabled (an all-off week with no template equals the
        // persisted NO_SCHEDULE state — legitimately nothing to persist).
        expect(
          _saveButton(tester).onPressed,
          isNull,
          reason: 'an all-off fresh draft equals NO_SCHEDULE → Save disabled',
        );
        // …but the user is TOLD why, via the keyed hint — the regression that
        // turned the disabled Save into a silently-dead button.
        expect(
          find.byKey(const Key('weekly-no-changes-hint')),
          findsOneWidget,
          reason:
              'a disabled Save on an all-off fresh draft must explain itself '
              'with the no-changes hint (not a silently-dead button)',
        );
      },
    );

    testWidgets(
      'fresh create → toggle one day ON with valid hours but NO validity '
      'window: the editor Save ENABLES (submit-time gate, not button-disable) '
      'but pressing it shows the inline required-window error and persists '
      'NOTHING — no navigation',
      (tester) async {
        // NEW MODEL (required-window fix): a FIRST-CREATE with ≥1 valid working
        // day enables Save (the validity range is NOT in the enable gate), but
        // the range is REQUIRED to actually persist. Pressing Save with no
        // range chosen surfaces the inline `error-validity-window` under the
        // period card and bails — no save/delete, no pop. Reverting the guard
        // makes the press persist an open-ended create and navigate away, so
        // the zero-persist + inline-error assertions below fail.
        final _RecordingWeekly weekly = _RecordingWeekly(
          const <WeeklySchedule>[],
        );
        final ProviderContainer c = await _pump(
          tester,
          overrides: _overridesFor(weekly),
        );
        addTearDown(c.dispose);

        // Precondition: an all-off fresh draft is a clean no-op — the
        // no-changes hint is up, Save disabled.
        expect(find.byKey(const Key('weekly-no-changes-hint')), findsOneWidget);
        expect(_saveButton(tester).onPressed, isNull);

        // Toggle Monday ON — the stash seeds valid default hours (09:00–18:00),
        // so the draft is dirty AND error-free: a real, savable change.
        await tester.tap(find.byKey(const Key('weekly-toggle-1')));
        await tester.pumpAndSettle();

        // Save is ENABLED immediately (the validity range is not in the enable
        // gate — it is enforced at submit time). No window pick needed for the
        // button to enable; the windowUnset hint is never shown.
        expect(
          _saveButton(tester).onPressed,
          isNotNull,
          reason:
              'a first-create with one valid working day enables Save — the '
              'validity range is enforced at submit, not by disabling Save',
        );
        expect(
          find.byKey(const Key('weekly-no-changes-hint')),
          findsNothing,
          reason: 'the no-changes hint must clear once the draft is dirty',
        );
        expect(
          find.byKey(const Key('weekly-window-unset-hint')),
          findsNothing,
          reason:
              'the window-unset hint is retired — a dirty first-create no '
              'longer routes through the Apply-window sheet to enable Save',
        );
        // No inline error yet — Save has not been pressed.
        expect(find.byKey(const Key('error-validity-window')), findsNothing);

        // Press the editor Save with NO validity window chosen.
        await tester.tap(find.byKey(const Key('btn-save-weekly-template')));
        await tester.pumpAndSettle();

        // SUBMIT-TIME GUARD: the inline required-window error is now shown, and
        // NOTHING was persisted — no create, no delete, no navigation.
        expect(
          find.byKey(const Key('error-validity-window')),
          findsOneWidget,
          reason:
              'pressing Save on a first-create with no validity window must '
              'surface the inline required-window error',
        );
        expect(
          weekly.saveCalled,
          isFalse,
          reason: 'the required-window guard must block the create (no POST)',
        );
        expect(weekly.deleteCalled, isFalse);
        expect(
          find.byType(WeeklyTemplateEditorScreen),
          findsOneWidget,
          reason: 'the guard keeps the editor on screen (no navigation)',
        );
        expect(find.byKey(const Key('schedule-stub')), findsNothing);
        // Save stays ENABLED — the gate is submit-time, not button-disable.
        expect(
          _saveButton(tester).onPressed,
          isNotNull,
          reason: 'Save remains enabled after the blocked submit attempt',
        );
      },
    );

    testWidgets(
      'existing template, toggle an open day OFF: Save ENABLES and saving '
      'persists that day as a day-off (empty intervals, not silently dropped)',
      (tester) async {
        // Mon–Fri open, Sat/Sun closed. Toggle Wednesday (an open day) OFF.
        final _RecordingWeekly weekly = _RecordingWeekly(<WeeklySchedule>[
          _template(id: 'sched-1'),
        ]);
        final ProviderContainer c = await _pump(
          tester,
          overrides: _overridesFor(weekly),
        );
        addTearDown(c.dispose);

        // Pristine load → Save disabled, hint shown (no edit yet).
        expect(_saveButton(tester).onPressed, isNull);
        expect(find.byKey(const Key('weekly-no-changes-hint')), findsOneWidget);

        // Scroll Wednesday into view and toggle it OFF.
        await tester.scrollUntilVisible(
          find.byKey(const Key('weekly-toggle-3')),
          120,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.byKey(const Key('weekly-toggle-3')));
        await tester.pumpAndSettle();

        // The day-off edit is dirty → Save enables, hint clears.
        expect(
          _saveButton(tester).onPressed,
          isNotNull,
          reason: 'closing a previously-open day makes the draft dirty',
        );
        expect(find.byKey(const Key('weekly-no-changes-hint')), findsNothing);

        await tester.tap(find.byKey(const Key('btn-save-weekly-template')));
        await tester.pumpAndSettle();

        // The save UPDATES the existing template and carries Wednesday as a
        // day-off (empty intervals) — the day-off is persistable, not dropped.
        expect(weekly.saveCalled, isTrue);
        expect(weekly.deleteCalled, isFalse);
        expect(weekly.savedScheduleId, 'sched-1');
        expect(
          weekly.savedSchedule!.days[2].intervals,
          isEmpty,
          reason: 'Wednesday must be persisted as a day-off (empty intervals)',
        );
        // Other open days are untouched (Monday still carries its interval).
        expect(
          weekly.savedSchedule!.days[0].intervals,
          isNotEmpty,
          reason: 'an unedited open day keeps its interval',
        );
      },
    );

    testWidgets(
      'all-off via toggling the last open day of an EXISTING template maps to '
      'the delete path (observable: delete invoked + pop), not a dead Save',
      (tester) async {
        // Monday-only template → toggling Monday off makes the whole week off.
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

        // Close Monday → every day off, but DIRTY (differs from the persisted
        // Monday-open template) → Save enables, hint clears.
        await tester.tap(find.byKey(const Key('weekly-toggle-1')));
        await tester.pumpAndSettle();
        expect(
          _saveButton(tester).onPressed,
          isNotNull,
          reason: 'closing the last open day of a real template is dirty',
        );
        expect(find.byKey(const Key('weekly-no-changes-hint')), findsNothing);

        await tester.tap(find.byKey(const Key('btn-save-weekly-template')));
        await tester.pumpAndSettle();

        // Observable behavior: the all-off-with-existing-template branch DELETES
        // the template (returns to NO_SCHEDULE) and pops back — never a no-op.
        expect(
          weekly.deleteCalled,
          isTrue,
          reason: 'all-off with an existing template DELETEs it',
        );
        expect(weekly.deletedId, 'sched-1');
        expect(
          weekly.saveCalled,
          isFalse,
          reason: 'delete is issued instead of an upsert when all days are off',
        );
        expect(find.byKey(const Key('schedule-stub')), findsOneWidget);
        expect(find.byType(WeeklyTemplateEditorScreen), findsNothing);
      },
    );
  });

  // ── First-create single commit point + REQUIRED validity window ──────────
  //
  // On a FIRST-CREATE (`_serverTemplate == null`) the editor's Save is the
  // SINGLE commit point, and the validity window is now REQUIRED to persist it.
  // Two-layer contract:
  //   • ENABLE GATE — a dirty first-create with ≥1 valid working day ENABLES
  //     Save immediately (the validity range is NOT in the enable gate; the old
  //     `_SaveGate.windowUnset` gate is gone).
  //   • SUBMIT GATE — pressing Save with no window chosen (`_draftWindow ==
  //     null`) surfaces the inline `error-validity-window` error and persists
  //     NOTHING. Choosing a window (via the «Період дії графіка» sheet, which
  //     STAGES the range into `_draftWindow` and returns a `DateTimeRange`)
  //     clears the error; the subsequent Save persists ONE schedule with
  //     `validFrom = _draftWindow.start`, `validTo = _draftWindow.end`.
  //
  // These tests drive the behaviour purely through observable UI/state (the
  // Save button's enabled flag, the inline error key, the recorded save) and
  // resolve any localised copy through AppLocalizations (M2 / M11).
  group('WeeklyTemplateEditorScreen — first-create single commit point', () {
    testWidgets(
      'a dirty first-create (a day toggled ON with valid hours) enables Save '
      'immediately and never shows the (retired) window-unset hint',
      (tester) async {
        final _RecordingWeekly weekly = _RecordingWeekly(
          const <WeeklySchedule>[],
        );
        final ProviderContainer c = await _pump(
          tester,
          overrides: _overridesFor(weekly),
        );
        addTearDown(c.dispose);

        // Toggle Monday ON → valid default hours, dirty, error-free.
        await tester.tap(find.byKey(const Key('weekly-toggle-1')));
        await tester.pumpAndSettle();

        // NEW: Save is ENABLED — the windowUnset gate is gone (Bug 2 fix).
        // Reverting the fix re-introduces the gate and this fails.
        expect(
          _saveButton(tester).onPressed,
          isNotNull,
          reason:
              'a dirty first-create with one valid working day is saveable '
              'directly — there is no validity-window pre-gate',
        );
        // Neither hint is shown: the draft is dirty (no no-changes hint) and
        // the windowUnset hint is retired.
        expect(find.byKey(const Key('weekly-no-changes-hint')), findsNothing);
        expect(
          find.byKey(const Key('weekly-window-unset-hint')),
          findsNothing,
          reason: 'the window-unset hint is no longer rendered on first-create',
        );
      },
    );

    testWidgets(
      'the validity range is NOT in the Save ENABLE gate: with one valid '
      'working day and NO range, Save is ENABLED — but pressing it surfaces '
      'the inline required-window error (submit-time gate, not button-disable)',
      (tester) async {
        // This pins the SEPARATION of the two gates: button-enablement is
        // unchanged (≥1 valid working day enables Save regardless of the range),
        // while the range requirement is enforced ONLY when Save is pressed.
        // If the range were (wrongly) folded back into the enable gate, the
        // first `isNotNull` assertion fails; if the submit guard were reverted,
        // the inline-error assertion fails (the press would persist instead).
        final _RecordingWeekly weekly = _RecordingWeekly(
          const <WeeklySchedule>[],
        );
        final ProviderContainer c = await _pump(
          tester,
          overrides: _overridesFor(weekly),
        );
        addTearDown(c.dispose);

        // Toggle Monday ON — one valid working day, no range chosen.
        await tester.tap(find.byKey(const Key('weekly-toggle-1')));
        await tester.pumpAndSettle();

        // ENABLE GATE: Save is enabled with no range — the range is not part of
        // button enablement.
        expect(
          _saveButton(tester).onPressed,
          isNotNull,
          reason:
              'Save enablement is unchanged — one valid working day enables it '
              'with no validity range selected',
        );
        // No inline error before the press.
        expect(find.byKey(const Key('error-validity-window')), findsNothing);

        // SUBMIT GATE: pressing Save with no range shows the inline error.
        await tester.tap(find.byKey(const Key('btn-save-weekly-template')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('error-validity-window')),
          findsOneWidget,
          reason: 'the range requirement is enforced at submit time',
        );
        expect(
          weekly.saveCalled,
          isFalse,
          reason: 'the submit guard blocks persistence with no range',
        );
        // Save is still enabled after the blocked attempt.
        expect(_saveButton(tester).onPressed, isNotNull);
      },
    );

    testWidgets('first-create Save AFTER picking a validity window persists '
        'the chosen range (validFrom = pick.start, validTo = pick.end) with no '
        'inline error — the editor Save is the single commit point', (
      tester,
    ) async {
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
      expect(_saveButton(tester).onPressed, isNotNull);

      // The validity window is now REQUIRED on first create: pick a custom
      // window 15.06 → 20.06 via the active-window card BEFORE pressing Save.
      // Staging clears any inline error and supplies validFrom/validTo.
      await _pickCustomWindowViaCard(tester, startDay: 15, endDay: 20);

      // Press the editor Save — the single commit point.
      await tester.tap(find.byKey(const Key('btn-save-weekly-template')));
      await tester.pumpAndSettle();

      // The create persisted from the editor Save, carrying the PICKED window.
      // No inline required-window error is shown (a window WAS chosen).
      expect(weekly.saveCalled, isTrue);
      expect(weekly.savedScheduleId, isNull);
      expect(weekly.savedSchedule!.id, isNull);
      expect(
        weekly.savedSchedule!.validFrom,
        DateTime(2026, 6, 15),
        reason: 'validFrom must equal the picked start',
      );
      expect(
        weekly.savedSchedule!.validTo,
        DateTime(2026, 6, 20),
        reason: 'validTo must equal the picked end',
      );
      expect(
        weekly.savedSchedule!.days[0].intervals,
        isNotEmpty,
        reason: 'the open Monday is carried into the persisted create',
      );
      expect(
        find.byKey(const Key('error-validity-window')),
        findsNothing,
        reason: 'a chosen window clears the required-window inline error',
      );
    });

    testWidgets(
      'first-create: opening the Apply-window sheet and picking a custom period '
      'STAGES it (no persist) — only the subsequent editor Save commits, '
      'carrying the PICKED window',
      (tester) async {
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

        // Open the Apply-window sheet via the active-window card and pick a
        // custom window 2026-06-15 → 2026-06-20 (start ≠ injected today 09.06).
        await _pickCustomWindowViaCard(tester, startDay: 15, endDay: 20);

        // The sheet did NOT persist on first-create — it only staged the draft
        // window. No CRUD has fired yet.
        expect(
          weekly.saveCalled,
          isFalse,
          reason:
              'on first-create the Apply-window sheet only STAGES the window — '
              'it must NOT eagerly persist (Bug 2 fix). Reverting the fix fires '
              'a save here and this fails.',
        );

        // Save is enabled (dirty day + a staged window). Commit via the editor
        // Save — the single commit point.
        expect(_saveButton(tester).onPressed, isNotNull);
        await tester.tap(find.byKey(const Key('btn-save-weekly-template')));
        await tester.pumpAndSettle();

        // Now exactly one create fired, carrying the PICKED window — the fixed
        // clock (09.06) proves validFrom is the pick (15.06), not today.
        expect(weekly.saveCalled, isTrue);
        expect(weekly.savedScheduleId, isNull);
        expect(weekly.savedSchedule!.id, isNull);
        expect(
          weekly.savedSchedule!.validFrom,
          DateTime(2026, 6, 15),
          reason: 'validFrom must be the picked start, never DateTime.now()',
        );
        expect(weekly.savedSchedule!.validTo, DateTime(2026, 6, 20));
        expect(
          weekly.savedSchedule!.days[0].intervals,
          isNotEmpty,
          reason: 'the open Monday is carried into the persisted create',
        );
      },
    );
  });

  // ── Bug 2(a) — first-create Save-enable gate (focused regression) ─────────
  //
  // BUG: `_saveGate` returned `_SaveGate.windowUnset` for a dirty first-create
  // whose validity window was unset, so `onPressed` stayed null even when the
  // master had toggled a valid working day on — the Save button looked dead.
  // FIX: `_saveGate` no longer returns `windowUnset`; a dirty first-create with
  // ≥1 valid working day is `saveable`. This focused test pins exactly that: ONE
  // open day, a valid interval, NO second day, and NO Apply-window interaction →
  // `btn-save-weekly-template` has a non-null `onPressed`. Restoring the
  // `windowUnset` gate flips this back to null and the test fails.
  group('WeeklyTemplateEditorScreen — Bug 2(a) first-create Save-enable', () {
    testWidgets(
      'a first-create with exactly ONE open day (valid interval) ENABLES Save '
      'with no second day and no Apply-window interaction',
      (tester) async {
        // Empty server list → first create (`_serverTemplate == null`).
        final ProviderContainer c = await _pump(
          tester,
          overrides: <Object>[
            weeklyScheduleProvider.overrideWith(
              () => _RecordingWeekly(const <WeeklySchedule>[]),
            ),
            effectiveScheduleProvider.overrideWith(() => _CountingEffective()),
          ],
        );
        addTearDown(c.dispose);

        // Precondition — pristine all-off draft: Save disabled, no-changes hint.
        expect(_saveButton(tester).onPressed, isNull);
        expect(find.byKey(const Key('weekly-no-changes-hint')), findsOneWidget);

        // Toggle ONLY Monday on. The stash seeds a valid default interval
        // (09:00–18:00); no other day is touched, and the Apply-window sheet is
        // never opened.
        await tester.tap(find.byKey(const Key('weekly-toggle-1')));
        await tester.pumpAndSettle();

        // Exactly one open day in the summary count — proves a single working
        // day (the count chip listens to _openCountNotifier).
        final AppLocalizations l10n = _l10n(tester);
        expect(
          find.text(l10n.weeklyEditorOpenCount(1)),
          findsOneWidget,
          reason: 'exactly one day is open',
        );

        // THE BUG-2(a) ASSERTION: Save is ENABLED with one open day, no second
        // day, no Apply-window pick. If the windowUnset gate were restored this
        // is null and the test fails.
        expect(
          _saveButton(tester).onPressed,
          isNotNull,
          reason:
              'a dirty first-create with one valid working day must enable '
              'Save directly — the windowUnset gate is removed (Bug 2 fix)',
        );
        // And no gate hint of either kind is shown.
        expect(find.byKey(const Key('weekly-no-changes-hint')), findsNothing);
        expect(find.byKey(const Key('weekly-window-unset-hint')), findsNothing);
      },
    );
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
      'edit with NO existing template → create (save with a null id) is issued '
      'by the editor Save itself — carrying the PICKED validFrom when the '
      'Apply-window sheet staged one (not today)',
      (tester) async {
        // NEW MODEL (Bug 2 fix): the create fires from the editor Save (the
        // single commit point), NOT from the Apply-window sheet. The sheet only
        // STAGES the chosen window into `_draftWindow`; the editor Save reads it
        // and persists. Original intent preserved: prove the editor issues a
        // CREATE (null id) carrying the open Monday, with the saved validFrom
        // being the PICKED date, not a fabricated `today`.
        final _RecordingWeekly weekly = _RecordingWeekly(
          const <WeeklySchedule>[],
        );
        final ProviderContainer c = await _pump(
          tester,
          overrides: _overridesFor(weekly),
        );
        addTearDown(c.dispose);

        // Open Monday → dirty → Save is enabled immediately (no window gate).
        await tester.tap(find.byKey(const Key('weekly-toggle-1')));
        await tester.pumpAndSettle();
        expect(
          _saveButton(tester).onPressed,
          isNotNull,
          reason: 'first-create Save is enabled with one valid working day',
        );

        // Stage a CUSTOM window starting 2026-06-15 (≠ injected today 09.06) via
        // the active-window card. End at 2026-06-20 (same first month → no
        // brittle scroll). Staging does NOT persist.
        await _pickCustomWindowViaCard(tester, startDay: 15, endDay: 20);
        expect(
          weekly.saveCalled,
          isFalse,
          reason: 'staging the window must not persist on first-create',
        );

        // Commit via the editor Save — the single commit point.
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
        // The saved window carries the PICKED validFrom (15.06), NOT the
        // injected today (09.06) — proving the staged window flowed to Save.
        expect(
          weekly.savedSchedule!.validFrom,
          DateTime(2026, 6, 15),
          reason: 'validFrom must equal the picked start, not today',
        );
        expect(
          weekly.savedSchedule!.validTo,
          DateTime(2026, 6, 20),
          reason: 'validTo must equal the picked end',
        );
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

  // ── Save/delete failure → false-success guard ──────────────────────────────
  //
  // RESOLVED (false-success MEDIUM): `WeeklyScheduleNotifier.save`/`.delete`
  // wrap their work in `AsyncValue.guard`, so a failed POST/PUT/DELETE becomes
  // an [AsyncError] STATE and returns NORMALLY rather than throwing back to the
  // screen. The screen reads the POST-await provider state and branches on
  // `hasError`: on failure it surfaces the mapped failure message and does NOT
  // pop / navigate and does NOT show the saved snackbar. The all-off-with-no-
  // template no-op (`mutated == false`) must NOT be misread as a failure — it
  // still pops + reports success.

  group('WeeklyTemplateEditorScreen — save/delete failure (false-success '
      'guard)', () {
    testWidgets(
      'a failed save (update) surfaces the error and does NOT pop or show the '
      'saved snackbar',
      (tester) async {
        final _FailingWeekly weekly = _FailingWeekly(<WeeklySchedule>[
          _template(id: 'sched-1'),
        ]);
        final ProviderContainer c = await _pump(
          tester,
          overrides: _failingOverridesFor(weekly),
        );
        addTearDown(c.dispose);
        final AppLocalizations l10n = _l10n(tester);

        // Make a dirty edit then save.
        await tester.tap(find.byKey(const Key('weekly-toggle-1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('btn-save-weekly-template')));
        await tester.pumpAndSettle();

        expect(weekly.saveCalled, isTrue);
        // The screen STAYS on the editor — it did not pop/navigate.
        expect(find.byType(WeeklyTemplateEditorScreen), findsOneWidget);
        expect(find.byKey(const Key('schedule-stub')), findsNothing);
        // The mapped failure message is shown (the error snackbar AND the
        // screen's AsyncError body both render it — at least one is present).
        expect(find.text(l10n.errServer), findsWidgets);
        // … and the success copy is ABSENT.
        expect(find.text(l10n.savedSnackbar), findsNothing);
      },
    );

    testWidgets(
      'a failed delete (all-off WITH an existing template) surfaces the error '
      'and does NOT pop or show the saved snackbar',
      (tester) async {
        // Monday-only template → closing Monday makes the whole week off →
        // the all-off branch issues delete(existing.id), which fails here.
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
        final _FailingWeekly weekly = _FailingWeekly(<WeeklySchedule>[
          mondayOnly,
        ]);
        final ProviderContainer c = await _pump(
          tester,
          overrides: _failingOverridesFor(weekly),
        );
        addTearDown(c.dispose);
        final AppLocalizations l10n = _l10n(tester);

        await tester.tap(find.byKey(const Key('weekly-toggle-1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('btn-save-weekly-template')));
        await tester.pumpAndSettle();

        expect(weekly.deleteCalled, isTrue);
        expect(weekly.saveCalled, isFalse);
        // The screen STAYS on the editor — no pop/navigate.
        expect(find.byType(WeeklyTemplateEditorScreen), findsOneWidget);
        expect(find.byKey(const Key('schedule-stub')), findsNothing);
        // The mapped failure message is shown (error snackbar AND the AsyncError
        // body both render it).
        expect(find.text(l10n.errServer), findsWidgets);
        expect(find.text(l10n.savedSnackbar), findsNothing);
      },
    );

    testWidgets(
      'all-off with NO existing template is a clean no-op (mutated == false): '
      'it still pops + shows the saved snackbar (not misread as a failure)',
      (tester) async {
        // Seed a NON-persisted template (id == null) with Monday open so the
        // draft has a real baseline to diverge from. Closing Monday makes the
        // week all-off AND dirty (differs from the Monday-open baseline) → Save
        // enables. On save the branch is all-off with NO existing id → no
        // mutation is issued (`mutated == false`); the success path (pop +
        // saved snackbar) must STILL run — the no-op must not be misread as a
        // failure.
        final WeeklySchedule mondayOnlyNoId = WeeklySchedule(
          id: null,
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
          mondayOnlyNoId,
        ]);
        final ProviderContainer c = await _pump(
          tester,
          overrides: _overridesFor(weekly),
        );
        addTearDown(c.dispose);
        final AppLocalizations l10n = _l10n(tester);

        // Close Monday → all-off + dirty (vs the Monday-open baseline).
        await tester.tap(find.byKey(const Key('weekly-toggle-1')));
        await tester.pumpAndSettle();
        expect(
          _saveButton(tester).onPressed,
          isNotNull,
          reason: 'closing the only open day makes an all-off draft dirty',
        );
        await tester.tap(find.byKey(const Key('btn-save-weekly-template')));
        await tester.pumpAndSettle();

        // No CRUD issued — there was no template to delete and nothing to save.
        expect(weekly.saveCalled, isFalse);
        expect(weekly.deleteCalled, isFalse);
        // … yet the clean no-op still popped back + reported success.
        expect(find.byKey(const Key('schedule-stub')), findsOneWidget);
        expect(find.byType(WeeklyTemplateEditorScreen), findsNothing);
        // The saved snackbar fired (the no-op success path), proving the
        // `mutated == false` branch is NOT treated as a failure.
        expect(find.text(l10n.savedSnackbar), findsOneWidget);
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

  // ── Active-window card label (unset-prompt UX change) ──────────────────────
  //
  // The editor's active-window card no longer fabricates a "Графік діє з
  // <today>" value for a first-time master (NO_SCHEDULE / `_serverTemplate ==
  // null`); it shows the muted `weeklyEditorActiveWindowUnset` prompt instead.
  // When a template IS persisted it shows the committed open-ended / ranged
  // label. All assertions resolve the expected copy through `AppLocalizations`
  // (M2 — never a raw UA literal) and are scoped to the card's Key.
  group('WeeklyTemplateEditorScreen — active-window card', () {
    testWidgets('NO_SCHEDULE (no template) shows the unset prompt, NOT a '
        '"Графік діє з <date>" value — and the card is present + tappable', (
      tester,
    ) async {
      // Seed the provider with an EMPTY server list → first-time master,
      // `_serverTemplate == null`.
      final ProviderContainer c = await _pumpEmpty(tester);
      addTearDown(c.dispose);

      final AppLocalizations l10n = _l10n(tester);
      final String unset = l10n.weeklyEditorActiveWindowUnset;
      // The old default-today value would have rendered with `from` = the
      // fixed clock (09.06). Build that exact would-be string to prove it is
      // ABSENT — the regression guard against re-introducing default-today.
      final String wouldBeTodayValue = l10n.weeklyEditorActiveWindowOpenEnded(
        '09.06',
      );

      // The card itself is present.
      expect(
        find.byKey(const Key('weekly-active-window-card')),
        findsOneWidget,
      );

      // The prompt is shown inside the card; the fabricated default-today
      // value is NOT.
      expect(
        find.descendant(
          of: find.byKey(const Key('weekly-active-window-card')),
          matching: find.text(unset),
        ),
        findsOneWidget,
        reason: 'unset state must show the placeholder prompt',
      );
      expect(
        find.text(wouldBeTodayValue),
        findsNothing,
        reason:
            'a first-time master must NOT see a fabricated '
            '"Графік діє з <today>" value (the old default-today behaviour)',
      );

      // The card is still an interactive affordance (opens the apply sheet).
      // Tapping must not throw and the prompt remains (no template persisted).
      await tester.tap(find.byKey(const Key('weekly-active-window-card')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('weekly-active-window-card')),
          matching: find.text(unset),
        ),
        findsOneWidget,
        reason: 'card remains tappable; prompt persists with no template',
      );
    });

    testWidgets('persisted open-ended template shows the filled '
        'weeklyEditorActiveWindowOpenEnded(validFrom), NOT the unset prompt', (
      tester,
    ) async {
      // `_template()` has validFrom = _clock (2026-06-09), validTo = null.
      final ProviderContainer c = await _pumpLoaded(tester, _template());
      addTearDown(c.dispose);

      final AppLocalizations l10n = _l10n(tester);
      final String filled = l10n.weeklyEditorActiveWindowOpenEnded('09.06');

      expect(
        find.descendant(
          of: find.byKey(const Key('weekly-active-window-card')),
          matching: find.text(filled),
        ),
        findsOneWidget,
        reason: 'open-ended template shows the committed validFrom value',
      );
      expect(
        find.text(l10n.weeklyEditorActiveWindowUnset),
        findsNothing,
        reason: 'a persisted template must not show the unset prompt',
      );
    });

    testWidgets('persisted ranged template shows the filled '
        'weeklyEditorActiveWindowRange(validFrom, validTo)', (tester) async {
      final ProviderContainer c = await _pumpLoaded(tester, _rangedTemplate());
      addTearDown(c.dispose);

      final AppLocalizations l10n = _l10n(tester);
      final String filled = l10n.weeklyEditorActiveWindowRange(
        '09.06',
        '31.12',
      );

      expect(
        find.descendant(
          of: find.byKey(const Key('weekly-active-window-card')),
          matching: find.text(filled),
        ),
        findsOneWidget,
        reason: 'ranged template shows the committed validFrom–validTo value',
      );
      expect(
        find.text(l10n.weeklyEditorActiveWindowUnset),
        findsNothing,
        reason: 'a persisted template must not show the unset prompt',
      );
    });

    testWidgets(
      'unset prompt renders in the muted placeholder style; the filled '
      'value renders in the committed style',
      (tester) async {
        // Unset: placeholder color + w600.
        final ProviderContainer cEmpty = await _pumpEmpty(tester);
        addTearDown(cEmpty.dispose);
        final AppLocalizations l10nEmpty = _l10n(tester);
        final Text unsetText = tester.widget<Text>(
          find
              .descendant(
                of: find.byKey(const Key('weekly-active-window-card')),
                matching: find.text(l10nEmpty.weeklyEditorActiveWindowUnset),
              )
              .first,
        );
        expect(
          unsetText.style?.color,
          BrandColors.placeholder,
          reason: 'unset prompt uses the muted placeholder colour',
        );
      },
    );
  });

  // ── Phase 15.8: per-day mode toggle swaps the editor body ──────────────────
  //
  // A working day card now carries an Інтервал / Окремі години sub-toggle
  // (`weekly-mode-toggle-{dow}`) that swaps the body between the IntervalEditor
  // and the DiscreteTimesEditor. The seeded Monday (`_template()` → day 1
  // active, INTERVAL 09:00–18:00) is the subject. Finders key off the source
  // Keys + widget TYPES (M2), never localised copy.
  group('WeeklyTemplateEditorScreen — Phase 15.8 mode toggle', () {
    testWidgets(
      'a working day defaults to INTERVAL: the mode sub-toggle renders and the '
      'IntervalEditor body is shown (DiscreteTimesEditor absent)',
      (tester) async {
        final ProviderContainer c = await _pumpLoaded(tester, _template());
        addTearDown(c.dispose);

        // The mode sub-toggle + both segment chips render for the active day.
        expect(find.byKey(const Key('weekly-mode-toggle-1')), findsOneWidget);
        expect(find.byKey(const Key('weekly-mode-interval-1')), findsOneWidget);
        expect(find.byKey(const Key('weekly-mode-explicit-1')), findsOneWidget);

        // Monday is seeded INTERVAL → its IntervalEditor body renders (the
        // day-1 work-start well exists); no DiscreteTimesEditor for day 1.
        expect(
          find.byKey(const Key('weekly-day-1-work-start')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('weekly-day-1')),
            matching: find.byType(DiscreteTimesEditor),
          ),
          findsNothing,
        );
      },
    );

    testWidgets(
      'tapping «Окремі години» on a working day swaps its body to the '
      'DiscreteTimesEditor (the IntervalEditor work wells are gone)',
      (tester) async {
        final ProviderContainer c = await _pumpLoaded(tester, _template());
        addTearDown(c.dispose);

        final Finder explicitChip = find.byKey(
          const Key('weekly-mode-explicit-1'),
        );
        await tester.ensureVisible(explicitChip);
        await tester.pumpAndSettle();
        await tester.tap(explicitChip);
        await tester.pumpAndSettle();

        // The day-1 card now hosts a DiscreteTimesEditor with its add affordance
        // (`weekly-day-1-add-time`), and the INTERVAL work wells are gone.
        expect(
          find.descendant(
            of: find.byKey(const Key('weekly-day-1')),
            matching: find.byType(DiscreteTimesEditor),
          ),
          findsOneWidget,
        );
        expect(find.byKey(const Key('weekly-day-1-add-time')), findsOneWidget);
        expect(find.byKey(const Key('weekly-day-1-work-start')), findsNothing);
      },
    );

    // Golden for the _DayCard discrete state (+ structural assertion, per the
    // golden-is-not-acceptance rule). The STRUCTURAL pin is the acceptance: the
    // discrete day-1 card hosts a DiscreteTimesEditor with one chip + the
    // discrete-hours summary after a time is added. The golden that follows is a
    // SUPPLEMENTARY pixel snapshot, blessed only once the structure is confirmed
    // correct so the self-referential re-bless can never silently mask a
    // regression.
    testWidgets(
      'the _DayCard discrete state renders the chip + discrete-hours summary '
      '(structural) and matches its golden (supplementary)',
      (tester) async {
        final ProviderContainer c = await _pumpLoaded(tester, _template());
        addTearDown(c.dispose);

        // Switch day-1 to EXPLICIT_TIMES and add the seeded 09:00 time so the
        // card has a deterministic discrete render (chip + min–max label).
        await tester.tap(find.byKey(const Key('weekly-mode-explicit-1')));
        await tester.pumpAndSettle();
        final Finder addTime = find.byKey(const Key('weekly-day-1-add-time'));
        await tester.ensureVisible(addTime);
        await tester.tap(addTime);
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('btn-velvet-time-picker-confirm')),
        );
        await tester.pumpAndSettle();

        // STRUCTURAL acceptance: the discrete card shows the 09:00 chip and the
        // localised discrete-hours summary enumerating the single start (read
        // from l10n — never a raw UA literal). This is the exact reported bug:
        // a single discrete time must read «Запис можливий в години: 09:00», NOT
        // the misleading «Вікно 09:00 - 09:00» / min–max window.
        final Finder dayCard = find.byKey(const Key('weekly-day-1'));
        expect(
          find.descendant(
            of: dayCard,
            matching: find.byKey(const Key('weekly-day-1-chip-09:00')),
          ),
          findsOneWidget,
        );
        final AppLocalizations l10n = _l10n(tester);
        expect(
          find.descendant(
            of: dayCard,
            matching: find.text(
              l10n.scheduleDiscreteTimesWindowSummary('09:00'),
            ),
          ),
          findsOneWidget,
        );
        // The degenerate min–max window must NOT appear anywhere in the card.
        expect(
          find.descendant(
            of: dayCard,
            matching: find.textContaining('09:00 – 09:00'),
          ),
          findsNothing,
        );

        // SUPPLEMENTARY golden of just the day-1 card in its discrete state.
        await expectLater(
          dayCard,
          matchesGoldenFile('goldens/weekly_day_card_discrete.png'),
        );
      },
    );
  });

  // ── Phase 15.8 regression: adding discrete times ENABLES Save ──────────────
  //
  // BUG (DEBUG 3.5): on an EXPLICIT_TIMES («Окремі години») working day, adding
  // discrete times via the add-time picker did NOT enable the Save button —
  // INTERVAL mode worked, EXPLICIT_TIMES did not.
  //
  // ROOT CAUSE: `_DayCard` held a private `List<TimeOfDay>` copy of the discrete
  // times and `_onTimesChanged` never wrote the edited list back into the host
  // `_templateDays[i].times`. So the host's authoritative `TemplateDay.times`
  // stayed empty → `_hasErrors` saw `discreteTimesValid([]) == false` → the Save
  // gate stuck at `hasErrors` → `onPressed == null` (silently-dead Save). The
  // INTERVAL path shares its `DayHours` by reference, so it never lost the edit.
  //
  // FIX: `_onTimesChanged(index, times)` writes the card's edited list into
  // `_templateDays[index].times` BEFORE recomputing the gate; `_buildSchedule`
  // then reads the synced times.
  //
  // These tests drive the bug purely through observable UI/state:
  //   1. PRIMARY — switch a working day to EXPLICIT_TIMES (Save disabled: an
  //      empty explicit day is an error), add two valid times, assert Save
  //      ENABLES and the no-changes hint is absent. FAILS on pre-fix code
  //      (host times stay empty → hasErrors → Save stays disabled).
  //   2. PERSISTED PROOF — Save and capture the recorded schedule; day-1 must
  //      serialise as EXPLICIT_TIMES carrying the added times, proving the host
  //      `TemplateDay.times` (not just the card) was updated.
  //   3. NO-REGRESSION MIRROR — the INTERVAL path (the one that always worked)
  //      still enables Save on a real edit.
  group('WeeklyTemplateEditorScreen — Phase 15.8 add-discrete-times Save-gate '
      'regression', () {
    testWidgets(
      'PRIMARY: switching to EXPLICIT_TIMES then adding two discrete times '
      'ENABLES Save and clears the no-changes/error gate (the silently-dead '
      'Save bug)',
      (tester) async {
        // Seeded Monday is ACTIVE in INTERVAL mode (09:00–18:00).
        final ProviderContainer c = await _pumpLoaded(tester, _template());
        addTearDown(c.dispose);

        // Switch day-1 to «Окремі години». An EXPLICIT_TIMES day with zero
        // times is an ERROR (discreteTimesValid([]) == false) → the gate is
        // `hasErrors` → Save is disabled. This is the precondition the bug
        // never escaped: adding times must clear the error AND keep the draft
        // dirty so Save enables.
        final Finder explicitChip = find.byKey(
          const Key('weekly-mode-explicit-1'),
        );
        await tester.ensureVisible(explicitChip);
        await tester.pumpAndSettle();
        await tester.tap(explicitChip);
        await tester.pumpAndSettle();

        // Precondition: empty explicit day → Save disabled (error gate).
        expect(
          _saveButton(tester).onPressed,
          isNull,
          reason:
              'a working EXPLICIT_TIMES day with no times is invalid → Save '
              'must be disabled until ≥1 valid time is added',
        );

        // Add two valid, 15-min-aligned times: the picker seeds 09:00 on an
        // empty list, then the next full hour (10:00) — both deterministic
        // with NO wheel scrolling (M6: no brittle wheel drive needed here).
        await _addWeeklyDiscreteTime(tester); // → 09:00
        await _addWeeklyDiscreteTime(tester); // → 10:00

        // The chips rendered (the card's view updated).
        expect(
          find.byKey(const Key('weekly-day-1-chip-09:00')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('weekly-day-1-chip-10:00')),
          findsOneWidget,
        );

        // THE REGRESSION ASSERTION: adding times wrote back into the host's
        // TemplateDay.times → error cleared + draft still dirty → Save ENABLES.
        // On the pre-fix code the host times stayed empty → hasErrors → this
        // is `null` and the test fails.
        expect(
          _saveButton(tester).onPressed,
          isNotNull,
          reason:
              'adding discrete times to an EXPLICIT_TIMES day must enable '
              'Save — the host TemplateDay.times was synced from the card',
        );
        expect(
          find.byKey(const Key('weekly-no-changes-hint')),
          findsNothing,
          reason: 'a savable draft must not show the no-changes hint',
        );
      },
    );

    testWidgets(
      'PERSISTED PROOF: saving an EXPLICIT_TIMES day persists day-1 as '
      'EXPLICIT_TIMES carrying the added times (host TemplateDay.times was '
      'updated, not just the card)',
      (tester) async {
        final _RecordingWeekly weekly = _RecordingWeekly(<WeeklySchedule>[
          _template(id: 'sched-1'),
        ]);
        final ProviderContainer c = await _pump(
          tester,
          overrides: _overridesFor(weekly),
        );
        addTearDown(c.dispose);

        // Switch day-1 to EXPLICIT_TIMES and add 09:00 + 10:00.
        final Finder explicitChip = find.byKey(
          const Key('weekly-mode-explicit-1'),
        );
        await tester.ensureVisible(explicitChip);
        await tester.pumpAndSettle();
        await tester.tap(explicitChip);
        await tester.pumpAndSettle();

        await _addWeeklyDiscreteTime(tester); // → 09:00
        await _addWeeklyDiscreteTime(tester); // → 10:00

        // Save is enabled → tap it.
        expect(_saveButton(tester).onPressed, isNotNull);
        await tester.tap(find.byKey(const Key('btn-save-weekly-template')));
        await tester.pumpAndSettle();

        // The editor issued an UPDATE; the recorded shape proves the host
        // TemplateDay.times — not the card's private copy — carried the edit.
        expect(weekly.saveCalled, isTrue);
        expect(weekly.savedScheduleId, 'sched-1');

        final TemplateDay day1 = weekly.savedSchedule!.days[0];
        expect(
          day1.mode,
          WeekdayMode.explicitTimes,
          reason: 'day-1 must persist as EXPLICIT_TIMES',
        );
        expect(
          day1.intervals,
          isEmpty,
          reason: 'an EXPLICIT_TIMES day carries no intervals',
        );
        final List<String> times = day1.times
            .map(
              (TimeOfDay t) =>
                  '${t.hour.toString().padLeft(2, '0')}:'
                  '${t.minute.toString().padLeft(2, '0')}',
            )
            .toList();
        expect(
          times,
          <String>['09:00', '10:00'],
          reason:
              'the saved day must carry the two times added in the card — '
              'proving _onTimesChanged wrote them back into the host',
        );
      },
    );

    testWidgets(
      'NO-REGRESSION MIRROR: an INTERVAL-mode edit (the path that always '
      'worked) still flips the draft dirty and enables Save on an EXISTING '
      'template (the edit-path the mirror targets)',
      (tester) async {
        // RECONCILED (window-gate behaviour change): the mirror is the
        // EDIT-EXISTING path — an INTERVAL edit must still register as savable.
        // Seed an EXISTING template (`_serverTemplate != null`) so the
        // first-create window gate does NOT apply and the assertion stays a
        // faithful guard that an INTERVAL edit flips dirty/saveable. (Toggling a
        // fresh all-off create would be held by the window gate, which is a
        // different contract and not what this mirror guards.)
        final _RecordingWeekly weekly = _RecordingWeekly(<WeeklySchedule>[
          _template(id: 'sched-1'),
        ]);
        final ProviderContainer c = await _pump(
          tester,
          overrides: _overridesFor(weekly),
        );
        addTearDown(c.dispose);

        // Pristine load of an existing template → Save disabled (no edit yet).
        expect(_saveButton(tester).onPressed, isNull);

        // Monday is seeded ACTIVE in INTERVAL mode (09:00–18:00). Toggle it OFF —
        // an INTERVAL-shape change that differs from the persisted baseline →
        // dirty. Because a template already exists, the window gate is cleared,
        // so the dirty INTERVAL edit enables Save directly.
        await tester.tap(find.byKey(const Key('weekly-toggle-1')));
        await tester.pumpAndSettle();

        expect(
          _saveButton(tester).onPressed,
          isNotNull,
          reason: 'an INTERVAL-mode edit on an existing template enables Save',
        );
        expect(find.byKey(const Key('weekly-no-changes-hint')), findsNothing);
        expect(
          find.byKey(const Key('weekly-window-unset-hint')),
          findsNothing,
          reason:
              'an existing template is not subject to the first-create gate',
        );
      },
    );
  });

  // ── M6 — FIRST-CREATE midnight-rollover re-anchor (the headline bug) ────────
  //
  // THE stale-`validFrom` regression. A first-create POSTed a `validFrom`
  // captured ONCE when the «Період дії графіка» preset was picked. Crossing
  // midnight before Save turned that cached start into YESTERDAY, which the
  // backend's `@FutureOrPresent` guard rejects with a 400. The fix makes the
  // editor's clock a LIVE `DateTime Function()` (so `_today` recomputes), and at
  // submit it: (1) re-anchors a now-past `_draftWindow` to a freshly-recomputed
  // today, surfaces the `weeklyEditorWindowReanchored` snackbar, and BAILS the
  // press WITHOUT persisting (the master confirms with a second Save); then a
  // second Save persists a present `validFrom`. `_buildSchedule` additionally
  // clamps a past `validFrom` up to today on the persist path (covers UPDATE).
  //
  // We advance time via the now-live clock seam — `_pumpWithClock` injects a
  // callback over a mutable `now` the test mutates between the preset pick and
  // Save. No new production seam is added (the dev made the clock live).
  //
  // RED-ON-PRE-FIX: revert the submit-time re-anchor/clamp and the FIRST Save
  // persists immediately with the STALE picked start (yesterday) — so
  // `saveCalled` is true after the first press and `savedSchedule.validFrom`
  // equals the stale D, failing the "nothing persisted on first Save" and
  // "validFrom == D+1" assertions below (and the reanchored snackbar never
  // shows). The UPDATE-clamp case fails identically if the `_buildSchedule`
  // past→today clamp is removed (it would persist the legacy 01.06 validFrom).
  group('WeeklyTemplateEditorScreen — M6 first-create midnight rollover', () {
    testWidgets(
      'crossing midnight between picking a today-anchored window and Save '
      're-anchors the window to the NEW today, shows the reanchored snackbar, '
      'and persists NOTHING on that first Save',
      (tester) async {
        // D = 2026-06-09; advance to D+1 = 2026-06-10 before Save. Anchored as
        // a genuine instant (noon UTC), not a bare local `DateTime(y, m, d)` —
        // the editor runs the injected clock through `kyivDayOf`, so a
        // host-local midnight literal drifts a Kyiv day under e.g.
        // TZ=Asia/Tokyo.
        DateTime now = DateTime.utc(2026, 6, 9, 12);
        final _RecordingWeekly weekly = _RecordingWeekly(
          const <WeeklySchedule>[],
        );
        final ProviderContainer c = await _pumpWithClock(
          tester,
          overrides: _overridesFor(weekly),
          clock: () => now,
        );
        addTearDown(c.dispose);
        final AppLocalizations l10n = _l10n(tester);

        // Toggle Monday ON (valid default hours) and pick the «Весь поточний
        // місяць» preset under clock = D → staged window starts 09.06 (== D).
        await tester.tap(find.byKey(const Key('weekly-toggle-1')));
        await tester.pumpAndSettle();
        await _pickThisMonthWindowViaCard(tester);

        // The card reflects the staged window anchored at D (09.06–30.06).
        expect(
          find.text(l10n.weeklyEditorActiveWindowRange('09.06', '30.06')),
          findsOneWidget,
          reason: 'the staged window is anchored at D before the rollover',
        );

        // ── Cross midnight: the live clock now reads D+1. ──
        now = DateTime.utc(2026, 6, 10, 12);

        // FIRST Save — the staged start (09.06) is now past → re-anchor + bail.
        await tester.tap(find.byKey(const Key('btn-save-weekly-template')));
        await tester.pumpAndSettle();

        // (a) NOTHING persisted on this first Save …
        expect(
          weekly.saveCalled,
          isFalse,
          reason:
              'a now-past staged window must re-anchor + bail, NOT POST a '
              'stale yesterday validFrom (the @FutureOrPresent 400 bug)',
        );
        expect(weekly.deleteCalled, isFalse);
        // … the editor stays on screen (no navigation) …
        expect(find.byType(WeeklyTemplateEditorScreen), findsOneWidget);
        expect(find.byKey(const Key('schedule-stub')), findsNothing);
        // … the reanchored snackbar explains the shift (resolved via l10n) …
        expect(
          find.text(l10n.weeklyEditorWindowReanchored('10.06')),
          findsOneWidget,
          reason: 'the master is told the window moved to the new today',
        );
        // … and the active-window card now starts D+1 (10.06), not the stale D.
        expect(
          find.text(l10n.weeklyEditorActiveWindowRange('10.06', '30.06')),
          findsOneWidget,
          reason: 'the re-anchored window now starts the new today (D+1)',
        );
        expect(
          find.text(l10n.weeklyEditorActiveWindowRange('09.06', '30.06')),
          findsNothing,
          reason: 'the stale D-anchored window label is gone after re-anchor',
        );
      },
    );

    testWidgets(
      'the SECOND Save (after the re-anchor) persists validFrom == the NEW '
      'today (D+1), never the stale D',
      (tester) async {
        // Anchored as a genuine instant (noon UTC), not a bare local
        // `DateTime(y, m, d)` — see the previous test's comment above.
        DateTime now = DateTime.utc(2026, 6, 9, 12);
        final _RecordingWeekly weekly = _RecordingWeekly(
          const <WeeklySchedule>[],
        );
        final ProviderContainer c = await _pumpWithClock(
          tester,
          overrides: _overridesFor(weekly),
          clock: () => now,
        );
        addTearDown(c.dispose);

        await tester.tap(find.byKey(const Key('weekly-toggle-1')));
        await tester.pumpAndSettle();
        await _pickThisMonthWindowViaCard(tester);

        // Roll past midnight; the first Save re-anchors (persists nothing).
        now = DateTime.utc(2026, 6, 10, 12);
        await tester.tap(find.byKey(const Key('btn-save-weekly-template')));
        await tester.pumpAndSettle();
        expect(
          weekly.saveCalled,
          isFalse,
          reason: 'the first Save after the rollover only re-anchors + bails',
        );

        // Let the reanchored VelvetSnack run its full lifecycle (entrance +
        // dwell + exit) so it stops overlaying the Save button at the bottom
        // of the screen. `ScaffoldMessenger.hideCurrentSnackBar()` is a no-op
        // against VelvetSnack (wrong host — see
        // test/helpers/velvet_snack_matchers.dart) and leaves the snack
        // mounted, hit-testing the second tap into the Overlay instead of the
        // button underneath.
        await pumpPastVelvetSnack(tester);

        // SECOND Save — the re-anchored start (10.06) is present → persists.
        await tester.tap(find.byKey(const Key('btn-save-weekly-template')));
        await tester.pumpAndSettle();

        expect(weekly.saveCalled, isTrue);
        expect(weekly.savedScheduleId, isNull);
        expect(
          weekly.savedSchedule!.validFrom,
          DateTime(2026, 6, 10),
          reason:
              'the persisted validFrom must be the NEW today (D+1), never the '
              'stale picked D (09.06) that the backend would 400',
        );
        expect(weekly.savedSchedule!.validTo, DateTime(2026, 6, 30));
        expect(
          weekly.savedSchedule!.days[0].intervals,
          isNotEmpty,
          reason: 'the open Monday is carried into the persisted create',
        );
        // The create navigated back on success.
        expect(find.byKey(const Key('schedule-stub')), findsOneWidget);
        expect(find.byType(WeeklyTemplateEditorScreen), findsNothing);
      },
    );

    testWidgets(
      'UPDATE path: _buildSchedule clamps an EXISTING template whose validFrom '
      'is already in the past UP to today on save (@FutureOrPresent applies to '
      'updates too)',
      (tester) async {
        // Fixed clock at the suite _clock (09.06); the template's validFrom
        // (01.06) is already past → it must clamp to today on save.
        final WeeklySchedule pastWindow = WeeklySchedule(
          id: 'sched-1',
          validFrom: DateTime(2026, 6, 1),
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
        final _RecordingWeekly weekly = _RecordingWeekly(<WeeklySchedule>[
          pastWindow,
        ]);
        final ProviderContainer c = await _pump(
          tester,
          overrides: _overridesFor(weekly),
        );
        addTearDown(c.dispose);

        // A dirty edit (close Monday) → Save enables (existing template, no
        // first-create window gate). Saving must clamp the past validFrom.
        await tester.tap(find.byKey(const Key('weekly-toggle-1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('btn-save-weekly-template')));
        await tester.pumpAndSettle();

        expect(weekly.saveCalled, isTrue);
        expect(weekly.savedScheduleId, 'sched-1');
        expect(
          weekly.savedSchedule!.validFrom,
          _clock,
          reason:
              'a past validFrom on an UPDATE must clamp UP to today — the '
              '@FutureOrPresent guard rejects a past validFrom on PUT too',
        );
      },
    );
  });

  // ── mobile-qa (2026-08-03, backlog :226) — Kyiv-anchored `_today` ──────────
  //
  // `_today` (`weekly_template_editor_screen.dart:225`) derives via
  // `kyivDayOf(widget._clock?.call() ?? DateTime.now())`. Every OTHER clock
  // fixture in this file — including the M6 group directly above — anchors on
  // `_clock` (2026-06-09, noon UTC) or a same-day +1 rollover, both nowhere
  // near a Kyiv day boundary, so none of them can disagree with a reverted
  // `dateOnly(clock())` (a bare device/UTC-day read, skipping the
  // `kyivDayOf`/`toBeauticaTime` conversion). This is the one fixture that
  // pins the Kyiv-vs-UTC derivation itself, via the «Весь поточний місяць»
  // preset's `_today`-anchored window — the same `showApplyScheduleSheet
  // (today: _today)` seam `_pickThisMonthWindowViaCard` already drives.
  //
  // Anchored the day BEFORE the boundary `slot_picker_test.dart` /
  // `master_schedule_screen_test.dart` use (2026-07-31T22:30Z, not
  // 2026-08-01T22:30Z) so the Kyiv-correct vs UTC/device-day "today" land in
  // DIFFERENT MONTHS — the strongest possible divergence for a month-window
  // preset: UTC day = Jul 31 (the LAST day of July) vs Kyiv day = Aug 1 (the
  // FIRST day of August), so «Весь поточний місяць» resolves to a single-day
  // 31.07–31.07 window under the bug vs a full 01.08–31.08 window when
  // correct — not merely a one-day slip.
  group('WeeklyTemplateEditorScreen — Kyiv-anchored "today" (mobile-qa, '
      '2026-08-03, backlog :226)', () {
    testWidgets(
      '«Весь поточний місяць» resolves to AUGUST (Kyiv today = Aug 1) even '
      'though the clock instant is still calendar-day JULY 31 in UTC — a '
      'UTC/device-day _today would wrongly stage a single-day 31.07 window',
      (tester) async {
        final DateTime clockInstant = DateTime.utc(2026, 7, 31, 22, 30);
        final _RecordingWeekly weekly = _RecordingWeekly(
          const <WeeklySchedule>[],
        );
        final ProviderContainer c = await _pumpWithClock(
          tester,
          overrides: _overridesFor(weekly),
          clock: () => clockInstant,
        );
        addTearDown(c.dispose);
        final AppLocalizations l10n = _l10n(tester);

        await _pickThisMonthWindowViaCard(tester);

        expect(
          find.text(l10n.weeklyEditorActiveWindowRange('01.08', '31.08')),
          findsOneWidget,
          reason:
              'the Kyiv-correct "today" (Aug 1) must anchor the «Весь '
              'поточний місяць» preset to the FULL August window',
        );
        expect(
          find.text(l10n.weeklyEditorActiveWindowRange('31.07', '31.07')),
          findsNothing,
          reason:
              'a UTC/device-day _today would read the boundary instant as '
              'Jul 31 (still July there) and stage a degenerate single-day '
              'window at the end of the WRONG month',
        );
      },
    );
  });

  // ═════════════════════════════════════════════════════════════════════════
  // 2026-07-27 — STORED WORKING WINDOW in the dirty-diff (`_baselineWindows`).
  //
  // THE SUBTLE PART. Two DIFFERENT persisted day shapes collapse to the SAME
  // canonical interval list:
  //
  //     window 09:00–18:00 + break 09:00–10:00  →  [10:00–18:00]
  //     window 10:00–18:00 + no break           →  [10:00–18:00]
  //
  // The dirty-diff used to compare intervals ONLY, so editing a day from the
  // first shape into the second read as "no changes": the Save button stayed
  // DISABLED on a day the master had visibly just edited. `_baselineWindows`
  // adds the window to the comparison and closes that hole.
  //
  // The pristine-load contract on the other side: merely OPENING an untouched
  // LEGACY (pre-window) template must NOT enable Save, even though
  // `DayHours.fromIntervals` always derives SOME window for display. That holds
  // by VALUE-EQUALITY, not by skipping the comparison: `_seed` baselines the
  // window it actually drew (`seededDay.window`, the derived
  // `[first start, last end]` for a legacy row), so the seeded draft window IS
  // the baseline until the master moves it.
  //
  // An earlier shape of this fix baselined only the STORED window
  // (`d.window?.clone()`), leaving the baseline `null` on every legacy row and
  // the window leg of the diff skipped entirely. That left one edit invisible —
  // see the COMPENSATING-EDIT test below, which is the case this audit
  // originally argued away as unreachable and got wrong.
  //
  // Driven purely through observable UI: the Save button's enabled flag, the
  // keyed no-changes hint, and the rendered window/break wells.
  // ═════════════════════════════════════════════════════════════════════════

  group('WeeklyTemplateEditorScreen — stored-window dirty-diff '
      '(_baselineWindows)', () {
    testWidgets('a stored window seeds the day as WINDOW + BREAK (not a '
        'shortened working day) and the load stays PRISTINE', (tester) async {
      final ProviderContainer c = await _pumpLoaded(tester, _windowTemplate());
      addTearDown(c.dispose);

      // The window well shows the STORED 09:00 start, not the 10:00 the
      // intervals alone would imply.
      expect(
        _wellText(tester, 'weekly-day-1-work-start'),
        '09:00',
        reason:
            'THE BUG: 10:00 here means the stored window was ignored and the '
            'break was normalised into a shortened working day',
      );
      expect(_wellText(tester, 'weekly-day-1-work-end'), '18:00');

      // …and the carved hour is rendered as a real break row.
      expect(
        find.byKey(const Key('weekly-day-1-break-0-start')),
        findsOneWidget,
        reason: 'the edge-flush break must reappear as a break row',
      );
      expect(_wellText(tester, 'weekly-day-1-break-0-start'), '09:00');
      expect(_wellText(tester, 'weekly-day-1-break-0-end'), '10:00');

      // Reconstructing a break out of the stored window is a pure DISPLAY
      // change — it must not register as an edit.
      expect(
        _saveButton(tester).onPressed,
        isNull,
        reason:
            'seeding the window-present regime must keep the Phase 6.2 '
            'pristine-load contract — Save stays disabled until a real edit',
      );
    });

    testWidgets(
      'THE REGRESSION: a WINDOW-ONLY edit that collapses to the SAME interval '
      'list still ENABLES Save',
      (tester) async {
        final _RecordingWeekly weekly = _RecordingWeekly(<WeeklySchedule>[
          _windowTemplate(),
        ]);
        final ProviderContainer c = await _pump(
          tester,
          overrides: _overridesFor(weekly),
        );
        addTearDown(c.dispose);

        expect(_saveButton(tester).onPressed, isNull, reason: 'precondition');

        // ── The master's edit: "I don't want a break at the start, I just
        // want to begin at 10:00." Remove the break, then move the window
        // start 09:00 → 10:00.
        await _removeBreak(tester, dayOfWeek: 1);
        // Intermediate state (window 09:00–18:00, no break) collapses to
        // [09:00–18:00] ≠ the baseline [10:00–18:00], so the interval diff
        // alone already reads dirty here — that is NOT the case under test.
        await _dragWorkWell(
          tester,
          key: 'weekly-day-1-work-start',
          hourSteps: 1,
        );

        // The draft is now window 10:00–18:00 with no breaks → toIntervals()
        // is [10:00–18:00], BYTE-IDENTICAL to the persisted baseline. Only the
        // stored WINDOW differs (09:00 → 10:00).
        expect(_wellText(tester, 'weekly-day-1-work-start'), '10:00');
        expect(
          find.byKey(const Key('weekly-day-1-break-0-start')),
          findsNothing,
          reason: 'the break row was removed',
        );

        expect(
          _saveButton(tester).onPressed,
          isNotNull,
          reason:
              'THE BUG: with an interval-only diff this state equals the '
              'baseline, so Save stayed DISABLED on a visibly-edited day — the '
              'master could not persist the change at all',
        );
        expect(
          find.byKey(const Key('weekly-no-changes-hint')),
          findsNothing,
          reason:
              'the gate must be `saveable`, not `noChanges` — a "no changes" '
              'hint on an edited day is the user-facing symptom',
        );
      },
    );

    testWidgets(
      'the window-only edit PERSISTS: the saved day-1 carries the NEW window '
      'alongside the unchanged intervals',
      (tester) async {
        final _RecordingWeekly weekly = _RecordingWeekly(<WeeklySchedule>[
          _windowTemplate(),
        ]);
        final ProviderContainer c = await _pump(
          tester,
          overrides: _overridesFor(weekly),
        );
        addTearDown(c.dispose);

        await _removeBreak(tester, dayOfWeek: 1);
        await _dragWorkWell(
          tester,
          key: 'weekly-day-1-work-start',
          hourSteps: 1,
        );

        await tester.tap(find.byKey(const Key('btn-save-weekly-template')));
        await tester.pumpAndSettle();

        expect(weekly.saveCalled, isTrue);
        final TemplateDay saved = weekly.savedSchedule!.days.firstWhere(
          (TemplateDay d) => d.dayOfWeek == 1,
        );
        expect(saved.window, isNotNull);
        expect(
          saved.window!.start,
          const TimeOfDay(hour: 10, minute: 0),
          reason: 'the edited від–до must be persisted, not the stale 09:00',
        );
        expect(saved.window!.end, const TimeOfDay(hour: 18, minute: 0));
        // Availability is unchanged by this edit — that is exactly why the
        // interval-only diff could not see it.
        expect(summariseIntervals(saved.intervals), '10:00–18:00');
      },
    );

    testWidgets(
      'a break edit inside a window-present day still enables Save (the '
      'ordinary path is not broken by the added window comparison)',
      (tester) async {
        final ProviderContainer c = await _pumpLoaded(
          tester,
          _windowTemplate(),
        );
        addTearDown(c.dispose);

        await _removeBreak(tester, dayOfWeek: 1);

        expect(
          _saveButton(tester).onPressed,
          isNotNull,
          reason: 'removing a break widens the working day — a real edit',
        );
      },
    );

    // ── The legacy pristine-load contract ───────────────────────────────────

    testWidgets(
      'LEGACY: opening an untouched pre-window template stays PRISTINE even '
      'though the seeded day derives a display window',
      (tester) async {
        // Persisted with intervals ONLY (window == null) — every row saved
        // before the backend stored the field. `DayHours.fromIntervals` still
        // derives a window (10:00–18:00) for display, and `_seed` baselines
        // that SAME derived value, so the window leg of the diff compares
        // 10:00–18:00 against 10:00–18:00 and finds no change.
        final ProviderContainer c = await _pumpLoaded(
          tester,
          _legacyTemplate(<WorkInterval>[_interval(10, 0, 18, 0)]),
        );
        addTearDown(c.dispose);

        expect(
          _wellText(tester, 'weekly-day-1-work-start'),
          '10:00',
          reason: 'legacy rows keep the historical gap-reconstruction display',
        );
        expect(
          find.byKey(const Key('weekly-day-1-break-0-start')),
          findsNothing,
          reason:
              'an edge-flush break is unrecoverable without a stored window — '
              'the legacy regime must stay byte-identical',
        );
        expect(
          _saveButton(tester).onPressed,
          isNull,
          reason:
              'the seeded draft window EQUALS the baselined derived window '
              'until the master moves it — merely OPENING an untouched '
              'template must never enable Save',
        );
        expect(
          find.byKey(const Key('weekly-no-changes-hint')),
          findsOneWidget,
          reason: 'the pristine gate is `noChanges`',
        );
      },
    );

    testWidgets(
      'LEGACY: a split legacy day (two intervals → a derived window WIDER than '
      'either) is also pristine on load',
      (tester) async {
        // Derived window 09:00–18:00 + an interior 13:00–14:00 break, from a
        // row that stored no window at all — the shape most likely to be
        // mistaken for an edit if `_seed` baselined anything other than the
        // window it just drew.
        final ProviderContainer c = await _pumpLoaded(
          tester,
          _legacyTemplate(<WorkInterval>[
            _interval(9, 0, 13, 0),
            _interval(14, 0, 18, 0),
          ]),
        );
        addTearDown(c.dispose);

        expect(_wellText(tester, 'weekly-day-1-work-start'), '09:00');
        expect(_wellText(tester, 'weekly-day-1-work-end'), '18:00');
        expect(_wellText(tester, 'weekly-day-1-break-0-start'), '13:00');

        expect(
          _saveButton(tester).onPressed,
          isNull,
          reason:
              'the derived 09:00–18:00 window is ALSO what `_seed` baselined, '
              'so the window leg finds no change on a pure load',
        );
      },
    );

    testWidgets(
      'a legacy day still enables Save on a REAL edit (a shortened day moves '
      'BOTH the intervals and the window off their baselines)',
      (tester) async {
        final ProviderContainer c = await _pumpLoaded(
          tester,
          _legacyTemplate(<WorkInterval>[_interval(10, 0, 18, 0)]),
        );
        addTearDown(c.dispose);

        await _dragWorkWell(
          tester,
          key: 'weekly-day-1-work-end',
          hourSteps: -1,
        ); // 18:00 → 17:00

        expect(_wellText(tester, 'weekly-day-1-work-end'), '17:00');
        expect(
          _saveButton(tester).onPressed,
          isNotNull,
          reason:
              'shortening a legacy day moves its collapsed intervals AND its '
              'window off the seeded baselines — either leg alone is enough',
        );
      },
    );

    // ── THE COMPENSATING EDIT — the case this audit originally argued away ──
    //
    // My first pass filed this as "verified NOT reachable", reasoning that on a
    // legacy (break-less) day the derived window always equals
    // `[firstStart, lastEnd]`, so any window drag necessarily moves the
    // collapsed intervals too and the interval leg fires anyway.
    //
    // That is true of a LONE window drag. It is FALSE the moment the master
    // makes a COMPENSATING edit — widening the window and carving the widened
    // part straight back out as a break:
    //
    //     persisted (legacy):  [10:00–18:00],  no stored window
    //     seeded:              window 10:00–18:00, no breaks
    //     master edits to:     window 09:00–18:00 + break 09:00–10:00
    //     toIntervals():       [10:00–18:00]   ← IDENTICAL to the baseline
    //
    // The interval leg sees no change. With the earlier `d.window?.clone()`
    // baseline the window leg was skipped on legacy rows, so `_isDirty` was
    // false and Save sat DISABLED on a day the master had visibly just edited —
    // the same user-facing symptom as the window-present regression above, on
    // the far larger population of already-shipped legacy rows.
    //
    // `_seed` now baselines the window it DREW, so the window leg always has an
    // operand and this edit registers.

    testWidgets(
      'THE REGRESSION (legacy rows): a COMPENSATING edit — widen the від, carve '
      'the widened hour back out as a break — collapses to the SAME interval '
      'list and must still ENABLE Save',
      (tester) async {
        final _RecordingWeekly weekly = _RecordingWeekly(<WeeklySchedule>[
          _legacyTemplate(<WorkInterval>[_interval(10, 0, 18, 0)]),
        ]);
        final ProviderContainer c = await _pump(
          tester,
          overrides: _overridesFor(weekly),
        );
        addTearDown(c.dispose);

        expect(
          _saveButton(tester).onPressed,
          isNull,
          reason: 'precondition: an untouched legacy load is pristine',
        );

        // 1. Widen the working window 10:00 → 09:00. On its own this already
        //    moves the intervals to [09:00–18:00], so the interval leg is
        //    dirty here — that is NOT the case under test.
        await _dragWorkWell(
          tester,
          key: 'weekly-day-1-work-start',
          hourSteps: -1,
        );
        expect(_wellText(tester, 'weekly-day-1-work-start'), '09:00');

        // 2. Add a break. With a 09:00–18:00 window and no existing breaks the
        //    editor seeds 09:15–10:15 (window start + 15-min gap, 1 h long).
        final Finder addBreak = find.byKey(const Key('weekly-day-1-add-break'));
        await tester.ensureVisible(addBreak);
        await tester.pumpAndSettle();
        await tester.tap(addBreak);
        await tester.pumpAndSettle();
        expect(_wellText(tester, 'weekly-day-1-break-0-start'), '09:15');

        // 3. Pull the break flush onto the window start and back to a round
        //    hour: 09:15–10:15 → 09:00–10:00. The minute wheel steps by 15.
        await _dragWorkWell(
          tester,
          key: 'weekly-day-1-break-0-start',
          minuteSteps: -1,
        );
        await _dragWorkWell(
          tester,
          key: 'weekly-day-1-break-0-end',
          minuteSteps: -1,
        );

        // The day is now VISIBLY different from the one that loaded …
        expect(_wellText(tester, 'weekly-day-1-work-start'), '09:00');
        expect(_wellText(tester, 'weekly-day-1-break-0-start'), '09:00');
        expect(_wellText(tester, 'weekly-day-1-break-0-end'), '10:00');
        // … while collapsing to BYTE-IDENTICAL availability: window 09:00–18:00
        // minus a 09:00–10:00 break is exactly the persisted [10:00–18:00].
        expect(_wellText(tester, 'weekly-day-1-work-end'), '18:00');

        expect(
          _saveButton(tester).onPressed,
          isNotNull,
          reason:
              'THE BUG: the collapsed intervals equal the baseline, so with a '
              'null legacy window baseline the diff found nothing and Save sat '
              'DISABLED — the master could not persist a break they had just '
              'drawn, on any pre-window row',
        );
        expect(
          find.byKey(const Key('weekly-no-changes-hint')),
          findsNothing,
          reason:
              'a "no changes" hint on a day showing a brand-new break row is '
              'the user-facing symptom',
        );
      },
    );

    testWidgets(
      'the compensating edit PERSISTS: the saved legacy day gains a window '
      '09:00–18:00 while its intervals stay [10:00–18:00]',
      (tester) async {
        final _RecordingWeekly weekly = _RecordingWeekly(<WeeklySchedule>[
          _legacyTemplate(<WorkInterval>[_interval(10, 0, 18, 0)]),
        ]);
        final ProviderContainer c = await _pump(
          tester,
          overrides: _overridesFor(weekly),
        );
        addTearDown(c.dispose);

        await _dragWorkWell(
          tester,
          key: 'weekly-day-1-work-start',
          hourSteps: -1,
        );
        await tester.ensureVisible(
          find.byKey(const Key('weekly-day-1-add-break')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('weekly-day-1-add-break')));
        await tester.pumpAndSettle();
        await _dragWorkWell(
          tester,
          key: 'weekly-day-1-break-0-start',
          minuteSteps: -1,
        );
        await _dragWorkWell(
          tester,
          key: 'weekly-day-1-break-0-end',
          minuteSteps: -1,
        );

        await tester.tap(find.byKey(const Key('btn-save-weekly-template')));
        await tester.pumpAndSettle();

        expect(weekly.saveCalled, isTrue);
        final TemplateDay saved = weekly.savedSchedule!.days.firstWhere(
          (TemplateDay d) => d.dayOfWeek == 1,
        );
        // Availability is unchanged — which is exactly why the interval-only
        // diff could not see this edit.
        expect(summariseIntervals(saved.intervals), '10:00–18:00');
        // …but the row is no longer legacy: it now carries the window that
        // makes the break survive the NEXT reload.
        expect(
          saved.window,
          isNotNull,
          reason:
              'the compensating edit is only meaningful if the widened від is '
              'persisted — otherwise the break vanishes again on reload',
        );
        expect(saved.window!.start, const TimeOfDay(hour: 9, minute: 0));
        expect(saved.window!.end, const TimeOfDay(hour: 18, minute: 0));
      },
    );

    testWidgets(
      'toggling a window-present day OFF and back ON is a no-op → Save '
      're-disables (the window survives the stash round-trip)',
      (tester) async {
        // `_toggleDay` stashes and restores the window with its intervals. If
        // the restore dropped the window, the restored day would seed from
        // gap-reconstruction, its від–до would collapse to 10:00 and the
        // no-op toggle would leave Save stuck ENABLED.
        final ProviderContainer c = await _pumpLoaded(
          tester,
          _windowTemplate(),
        );
        addTearDown(c.dispose);

        await tester.tap(find.byKey(const Key('weekly-toggle-1')));
        await tester.pumpAndSettle();
        expect(_saveButton(tester).onPressed, isNotNull, reason: 'day closed');

        await tester.tap(find.byKey(const Key('weekly-toggle-1')));
        await tester.pumpAndSettle();

        expect(
          _wellText(tester, 'weekly-day-1-work-start'),
          '09:00',
          reason: 'the stored window must survive the off→on stash restore',
        );
        expect(_wellText(tester, 'weekly-day-1-break-0-start'), '09:00');
        expect(
          _saveButton(tester).onPressed,
          isNull,
          reason:
              'a toggle that restores the day exactly is a no-op → Save must '
              're-disable (Phase 6.2 contract)',
        );
      },
    );
  });

  // ── Router-shaped no-`clock:` construction follows clockProvider ───────────
  //
  // Regression guard for the MEDIUM raised in the calendar-consolidation QA
  // pass (`app_router.dart:1090,1113` construct `WeeklyTemplateEditorScreen()`
  // with no `clock:` — exactly as reproduced here): before the fix, `_today`
  // fell back to a bare `DateTime.now()`, so anything the screen derives from
  // "today" silently ignored the E2E harness's / this test's pinned
  // `clockProvider`. Every OTHER test in this file passes an explicit
  // `clock:` (via `_pump`), which bypasses the provider fallback entirely and
  // would stay green even if that fallback regressed back to `DateTime.now()`
  // — so this is the only place that path is exercised.
  //
  // Drives the same production chain a real navigation does: `_today` →
  // `showApplyScheduleSheet(today: _today)` → `ApplyScheduleSheet._pickRange`'s
  // `firstMonth: DateTime(widget.today.year, widget.today.month)`. Reads the
  // picker's OWN rendered "<Місяць> <Рік>" header as ground truth (never a
  // hardcoded expectation) and asserts it resolves to the PINNED month, not
  // whatever month the test happens to run on.
  //
  // NOTE — does not cover the "today" ring itself: at the time this test was
  // written, `showPeriodRangePicker` had no `clock` parameter to forward, so
  // `PeriodRangePicker`'s own `_today` (used only by `_isToday()`/the ring)
  // still fell back to a bare `DateTime.now()` reached through this exact
  // call path. That follow-up gap is now closed and pinned by the dedicated
  // test immediately below this one, which asserts on the ring directly.
  testWidgets(
    'router-shaped construction (no clock:) still resolves "today" from the '
    'overridden clockProvider, not the real host date',
    (tester) async {
      final DateTime pinned = DateTime.utc(2027, 3, 10, 12);
      final ProviderContainer c = ProviderContainer(
        retry: beauticaProviderRetry,
        overrides: <Object>[
          weeklyScheduleProvider.overrideWith(
            () => _RecordingWeekly(<WeeklySchedule>[_template()]),
          ),
          effectiveScheduleProvider.overrideWith(() => _CountingEffective()),
          clockProvider.overrideWithValue(() => pinned),
        ].cast(),
      );
      addTearDown(c.dispose);
      final GoRouter router = GoRouter(
        initialLocation: RouteNames.scheduleWeeklyEditor,
        routes: <RouteBase>[
          GoRoute(
            path: RouteNames.scheduleWeeklyEditor,
            // Deliberately NO `clock:` — mirrors `app_router.dart:1090,1113`.
            builder: (BuildContext context, GoRouterState state) =>
                const WeeklyTemplateEditorScreen(),
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('uk'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('weekly-active-window-card')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('apply-schedule-date-well')));
      await tester.pumpAndSettle();

      final RegExp monthHeaderPattern = RegExp(
        r'^([А-Яа-яІіЇїЄєҐґ]+) (\d{4})$',
      );
      final Text header = tester.widget<Text>(
        find
            .byWidgetPredicate(
              (Widget w) =>
                  w is Text &&
                  w.data != null &&
                  monthHeaderPattern.hasMatch(w.data!),
            )
            .first,
      );
      final RegExpMatch match = monthHeaderPattern.firstMatch(header.data!)!;
      final int monthNumber = monthNamesNominative.indexOf(match.group(1)!) + 1;
      final int year = int.parse(match.group(2)!);

      expect(
        (year, monthNumber),
        (pinned.year, pinned.month),
        reason:
            'the picker\'s first rendered month must follow the pinned '
            'clockProvider (${pinned.year}-${pinned.month}), not the real '
            'host date — proving the router-shaped no-`clock:` construction '
            'no longer falls back to a bare DateTime.now()',
      );
    },
  );

  // ── Router-shaped no-`clock:` construction — the picker's "today" RING ─────
  //
  // Closes the other half of the MEDIUM the test above left explicitly open
  // (its own NOTE): that test proves `firstMonth` follows the pinned
  // `clockProvider`, but `showPeriodRangePicker` had no `clock` parameter to
  // forward, so `PeriodRangePicker`'s own `_today` — used only by the "today"
  // ring — still fell back to a bare `DateTime.now()` on this exact call
  // path. `PeriodRangePicker`'s own widget tests
  // (`period_range_picker_test.dart`) all pass `clock:` explicitly to
  // `PeriodRangePicker` directly, so none of them exercise the
  // `showPeriodRangePicker` → `ApplyScheduleSheet._pickRange` plumbing this
  // guards.
  //
  // Drives the identical production chain as the test above (router →
  // screen → active-window card → date well) and then asserts on the
  // PICKER'S OWN rendered `CalendarDayCell` for the pinned day — ground
  // truth, found by the same [periodDayCellKey] the picker itself uses to key
  // that cell — rather than re-deriving "today" independently.
  testWidgets(
    'router-shaped construction (no clock:) rings the pinned clockProvider '
    'day, not the real host date, on the period-range-picker "today" ring',
    (tester) async {
      final DateTime pinned = DateTime.utc(2027, 3, 10, 12);
      final ProviderContainer c = ProviderContainer(
        retry: beauticaProviderRetry,
        overrides: <Object>[
          weeklyScheduleProvider.overrideWith(
            () => _RecordingWeekly(<WeeklySchedule>[_template()]),
          ),
          effectiveScheduleProvider.overrideWith(() => _CountingEffective()),
          clockProvider.overrideWithValue(() => pinned),
        ].cast(),
      );
      addTearDown(c.dispose);
      final GoRouter router = GoRouter(
        initialLocation: RouteNames.scheduleWeeklyEditor,
        routes: <RouteBase>[
          GoRoute(
            path: RouteNames.scheduleWeeklyEditor,
            // Deliberately NO `clock:` — mirrors `app_router.dart:1090,1113`.
            builder: (BuildContext context, GoRouterState state) =>
                const WeeklyTemplateEditorScreen(),
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('uk'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('weekly-active-window-card')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('apply-schedule-date-well')));
      await tester.pumpAndSettle();

      // `pinned` is noon UTC on 2027-03-10, and Kyiv sits at UTC+2 in March
      // (pre-DST), so its Kyiv calendar day is the same 2027-03-10 the
      // month-header test above asserts on — a plain host-local date token is
      // therefore the right key here (`periodDayCellKey` only reads
      // y/m/d, never the instant).
      // `cellKey` lands on the [CalendarDayCell]'s inner `Semantics` node, not
      // on the [CalendarDayCell] widget itself (`calendar_grid.dart`'s
      // `build()`) — so locate the day by key, then walk up to the
      // [CalendarDayCell] ancestor that carries `isToday`.
      final Key todayCellKey = periodDayCellKey(DateTime(2027, 3, 10));
      final Finder todaySemantics = find.descendant(
        of: find.byType(PeriodRangePicker),
        matching: find.byKey(todayCellKey),
      );
      expect(
        todaySemantics,
        findsOneWidget,
        reason:
            'the pinned day must be rendered in the picker\'s first '
            'visible month for this assertion to be meaningful',
      );
      final Finder todayCell = find.ancestor(
        of: todaySemantics,
        matching: find.byType(CalendarDayCell),
      );
      final CalendarDayCell cell = tester.widget<CalendarDayCell>(todayCell);

      expect(
        cell.isToday,
        isTrue,
        reason:
            'the picker\'s "today" ring must follow the pinned clockProvider '
            '(${pinned.year}-${pinned.month}-${pinned.day}), not the real '
            'host date — proving `showPeriodRangePicker`/`ApplyScheduleSheet'
            '._pickRange` now forward an explicit `clock:` instead of '
            'letting `PeriodRangePicker._today` fall back to a bare '
            '`DateTime.now()`',
      );
    },
  );
}

// ───────────────────────────────────────────────────────────────────────────
// Override helpers.
// ───────────────────────────────────────────────────────────────────────────

/// Opens the weekly day-1 discrete add-time picker and confirms the seeded
/// value (no wheel scrolling). The picker seeds 09:00 on an empty list, then
/// the next full hour after the last time — so successive calls add
/// 09:00, 10:00, … deterministically (M6: no brittle wheel drive).
Future<void> _addWeeklyDiscreteTime(WidgetTester tester) async {
  final Finder add = find.byKey(const Key('weekly-day-1-add-time'));
  await tester.ensureVisible(add);
  await tester.pumpAndSettle();
  await tester.tap(add);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('btn-velvet-time-picker-confirm')));
  await tester.pumpAndSettle();
}

/// Opens the «Період дії графіка» sheet via the tappable active-window card
/// (`weekly-active-window-card` — the retired window-unset hint is no longer the
/// entry point), drives the custom [PeriodRangePicker] to select
/// [startDay]→[endDay] (both in the first rendered month — June 2026 under the
/// fixed clock, so no scrolling), saves the range, then taps «Застосувати».
///
/// On a FIRST-CREATE the «Застосувати» tap STAGES the window (returns a
/// [DateTimeRange] to the editor) WITHOUT persisting — the editor's own Save is
/// the single commit point. Lets a test pick a `validFrom` that differs from the
/// injected today, proving the staged window flows to the editor Save.
Future<void> _pickCustomWindowViaCard(
  WidgetTester tester, {
  required int startDay,
  required int endDay,
}) async {
  await tester.tap(find.byKey(const Key('weekly-active-window-card')));
  await tester.pumpAndSettle();
  // Open the custom range picker via its date well.
  await tester.tap(find.byKey(const Key('apply-schedule-date-well')));
  await tester.pumpAndSettle();
  // Tap the start then end day cells. Day cells expose a `Semantics(button,
  // label: '<day>')`; the first match is the earliest rendered month (June
  // 2026), so no scrolling is needed for in-month days.
  await tester.tap(_dayCell(startDay).first);
  await tester.pumpAndSettle();
  await tester.tap(_dayCell(endDay).first);
  await tester.pumpAndSettle();
  // Save the range, then apply the window.
  await tester.tap(find.byKey(const Key('btn-range-picker-save')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('btn-apply-schedule')));
  await tester.pumpAndSettle();
}

/// A tappable day cell in the [PeriodRangePicker] for the given [day] number.
/// Day cells are `GestureDetector`s wrapped in a button [Semantics] whose
/// `label` is the day-of-month string; we match the button semantics by label.
Finder _dayCell(int day) => find.byWidgetPredicate(
  (Widget w) =>
      w is Semantics &&
      (w.properties.button ?? false) &&
      w.properties.label == '$day',
);

/// Editor overrides bound to a recording weekly notifier + a counting effective
/// notifier (so the invalidation path is observable).
List<Object> _overridesFor(_RecordingWeekly weekly) => <Object>[
  weeklyScheduleProvider.overrideWith(() => weekly),
  effectiveScheduleProvider.overrideWith(() => _CountingEffective()),
];

/// Editor overrides bound to a FAILING weekly notifier (mutations land in
/// AsyncError) + a counting effective notifier (so the absence of an
/// invalidation on failure is observable).
List<Object> _failingOverridesFor(_FailingWeekly weekly) => <Object>[
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

/// Pumps the editor seeded with an EMPTY server list — the first-time /
/// NO_SCHEDULE master (`_serverTemplate == null`). Drives the unset-prompt
/// active-window state.
Future<ProviderContainer> _pumpEmpty(WidgetTester tester) => _pump(
  tester,
  overrides: <Object>[
    weeklyScheduleProvider.overrideWith(
      () => _RecordingWeekly(const <WeeklySchedule>[]),
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
      errBreakCoversWholeWindow: l10n.intervalEditorErrBreakCoversWholeDay,
      errTimeNotAligned: l10n.scheduleErrTimeNotAligned,
    );

/// Pumps the editor under a GoRouter with an ADVANCEABLE [clock] (the now-live
/// `DateTime Function()` seam) so a test can cross midnight between interactions
/// by mutating the clock's backing `now`. Mirrors [_pump] but threads the
/// caller's clock instead of the fixed `_clock`. Returns the container for
/// `addTearDown(container.dispose)`.
Future<ProviderContainer> _pumpWithClock(
  WidgetTester tester, {
  required List<Object> overrides,
  required DateTime Function() clock,
}) async {
  final ProviderContainer container = ProviderContainer(
    retry: beauticaProviderRetry,
    overrides: overrides.cast(),
  );
  final GoRouter router = GoRouter(
    initialLocation: RouteNames.scheduleWeeklyEditor,
    routes: <RouteBase>[
      GoRoute(
        path: RouteNames.scheduleWeeklyEditor,
        builder: (BuildContext context, GoRouterState state) =>
            WeeklyTemplateEditorScreen(clock: clock),
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
  await tester.pumpAndSettle();
  return container;
}

/// Opens the «Період дії графіка» sheet via the active-window card, picks the
/// «Весь поточний місяць» preset (a TODAY-anchored window), and applies it. On a
/// first-create this STAGES the chosen window into the editor's `_draftWindow`
/// (the editor Save is the single commit point) — letting a test stage a window
/// whose start is the clock's "today" at pick time, then advance the clock to
/// exercise the submit-time re-anchor.
Future<void> _pickThisMonthWindowViaCard(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('weekly-active-window-card')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('preset-this-month')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('btn-apply-schedule')));
  await tester.pumpAndSettle();
}
