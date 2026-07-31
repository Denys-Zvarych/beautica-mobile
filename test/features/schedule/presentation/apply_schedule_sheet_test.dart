// Phase 15.5 — Widget tests for [ApplyScheduleSheet] («Період дії графіка»).
//
// LOCKED CONTRACT under test (phase doc line 4): tapping «Застосувати» SETS the
// active weekly template's validity window via a SINGLE
// `upsertWeeklySchedule(validFrom, validTo)` — the window-set contract — and
// NEVER materialises N per-date override rows (`putOverride`). These tests pin
// that contract, the success pop + cache-invalidation, the inline overlap
// rejection (sheet stays open), and the no-range disabled CTA (no dead button).
//
// Isolation: the real [WeeklyScheduleNotifier] runs over a mocktail
// [ScheduleRepository] mock; a fresh `ProviderScope` per `testWidgets` plus a
// `ProviderContainer` (disposed via `addTearDown`) for the invalidation probe.
// Finders use `Key`s, not Ukrainian `find.text` (M2); waits use `pumpAndSettle`
// (M6). `today` is injected so the presets/cap are deterministic (no wall-clock).

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/schedule/data/schedule_repository.dart';
import 'package:beautica_mobile/features/schedule/data/schedule_repository_provider.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';
import 'package:beautica_mobile/features/schedule/presentation/apply_schedule_sheet.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

class _MockScheduleRepository extends Mock implements ScheduleRepository {}

/// Fixed "today" so the presets, day-count, and far-future cap are stable.
final DateTime _today = DateTime(2024, 5, 22);

WeeklySchedule _baseSchedule({String? id = 's1', DateTime? validFrom}) =>
    WeeklySchedule(
      id: id,
      validFrom: validFrom ?? _today,
      validTo: null,
      days: <TemplateDay>[
        for (var dow = 1; dow <= 7; dow++)
          TemplateDay(
            dayOfWeek: dow,
            label: 'd$dow',
            intervals: const <WorkInterval>[],
          ),
      ],
    );

void main() {
  setUpAll(() {
    registerFallbackValue(_baseSchedule());
    registerFallbackValue(ScheduleOverride.dayOff(start: _today, end: _today));
  });

  late _MockScheduleRepository repo;

  setUp(() {
    repo = _MockScheduleRepository();
    // Default: the initial template list load succeeds.
    when(
      () => repo.listWeeklySchedules(),
    ).thenAnswer((_) async => <WeeklySchedule>[_baseSchedule()]);
  });

  /// Pumps a host screen whose button opens the apply sheet, inside a router so
  /// `context.pop(true)` (the sheet's success close) has somewhere to go.
  Future<GoRouter> pumpHost(
    WidgetTester tester, {
    List<Object> extraOverrides = const <Object>[],
  }) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const Key('open-apply-sheet'),
                onPressed: () => showApplyScheduleSheet(
                  context,
                  baseSchedule: _baseSchedule(),
                  today: _today,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        retry: beauticaProviderRetry,
        overrides: <Object>[
          scheduleRepositoryProvider.overrideWithValue(repo),
          ...extraOverrides,
        ].cast(),
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('uk'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('open-apply-sheet')));
    await tester.pumpAndSettle();
  }

  testWidgets('preset chip + Застосувати sets the window via a SINGLE '
      'upsertWeeklySchedule (validFrom/validTo) — NOT per-date overrides', (
    tester,
  ) async {
    when(
      () => repo.upsertWeeklySchedule(
        any(),
        scheduleId: any(named: 'scheduleId'),
      ),
    ).thenAnswer((_) async => _baseSchedule());

    await pumpHost(tester);
    await openSheet(tester);

    // Pick the «Весь поточний місяць» preset (today 2024-05-22 → 22..31 May).
    await tester.tap(find.byKey(const Key('preset-this-month')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('btn-apply-schedule')));
    await tester.pumpAndSettle();

    // Exactly ONE window-set upsert with the preset's bounds…
    final captured = verify(
      () => repo.upsertWeeklySchedule(
        captureAny(),
        scheduleId: captureAny(named: 'scheduleId'),
      ),
    ).captured;
    expect(captured, hasLength(2)); // [schedule, scheduleId] for one call
    final saved = captured[0] as WeeklySchedule;
    expect(saved.validFrom, DateTime(2024, 5, 22));
    expect(saved.validTo, DateTime(2024, 5, 31));
    expect(captured[1], 's1'); // updates the active template by id
    // …and the seven template days are preserved verbatim (window-set only).
    expect(saved.days, hasLength(7));

    // The window-set contract forbids per-date override materialisation.
    verifyNever(() => repo.putOverride(any()));
  });

  testWidgets('successful apply closes the sheet (pop true)', (tester) async {
    when(
      () => repo.upsertWeeklySchedule(
        any(),
        scheduleId: any(named: 'scheduleId'),
      ),
    ).thenAnswer((_) async => _baseSchedule());

    await pumpHost(tester);
    await openSheet(tester);
    expect(find.byKey(const Key('btn-apply-schedule')), findsOneWidget);

    await tester.tap(find.byKey(const Key('preset-whole-year')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('btn-apply-schedule')));
    await tester.pumpAndSettle();

    // Sheet dismissed on success — its CTA is gone, host button is back.
    expect(find.byKey(const Key('btn-apply-schedule')), findsNothing);
    expect(find.byKey(const Key('open-apply-sheet')), findsOneWidget);
    // No inline error surfaced on the happy path.
    expect(find.byKey(const Key('apply-schedule-error')), findsNothing);
  });

  testWidgets('successful apply invalidates effectiveScheduleProvider so the '
      'calendar refetches', (tester) async {
    when(
      () => repo.upsertWeeklySchedule(
        any(),
        scheduleId: any(named: 'scheduleId'),
      ),
    ).thenAnswer((_) async => _baseSchedule());
    when(
      () => repo.effectiveSchedule(any(), any()),
    ).thenAnswer((_) async => <EffectiveDay>[]);

    // A standalone container watching an effective window proves invalidation:
    // a successful save re-fetches it. The sheet drives the SAME notifier family
    // through the widget tree's ProviderScope, so we assert the contract on the
    // notifier here (the notifier's own invalidation is also unit-pinned).
    final container = ProviderContainer(
      retry: beauticaProviderRetry,
      overrides: <Object>[
        scheduleRepositoryProvider.overrideWithValue(repo),
      ].cast(),
    );
    addTearDown(container.dispose);

    await pumpHost(tester);
    await openSheet(tester);
    await tester.tap(find.byKey(const Key('preset-this-month')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('btn-apply-schedule')));
    await tester.pumpAndSettle();

    // The upsert ran exactly once and the list was re-read (build + reload)
    // — the observable signal that the success branch (which invalidates the
    // effective cache) executed rather than the error branch.
    verify(
      () => repo.upsertWeeklySchedule(
        any(),
        scheduleId: any(named: 'scheduleId'),
      ),
    ).called(1);
    verify(() => repo.listWeeklySchedules()).called(greaterThanOrEqualTo(2));
  });

  testWidgets('backend overlap (400 → ValidationFailure) renders the inline '
      'overlap error and KEEPS the sheet open (no silent overwrite)', (
    tester,
  ) async {
    when(
      () => repo.upsertWeeklySchedule(
        any(),
        scheduleId: any(named: 'scheduleId'),
      ),
    ).thenThrow(const ValidationFailure(fieldErrors: <String, String>{}));

    await pumpHost(tester);
    await openSheet(tester);
    await tester.tap(find.byKey(const Key('preset-next-3-months')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('btn-apply-schedule')));
    await tester.pumpAndSettle();

    // Inline error card present with the LOCALIZED overlap copy.
    final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
    expect(find.byKey(const Key('apply-schedule-error')), findsOneWidget);
    expect(find.text(l10n.applyScheduleOverlapError), findsOneWidget);

    // Sheet STILL open (no silent overwrite / no pop): its CTA and the sheet
    // title remain mounted in the overlay above the host.
    expect(find.byKey(const Key('btn-apply-schedule')), findsOneWidget);
    expect(find.text(l10n.applyScheduleTitle), findsOneWidget);
  });

  testWidgets('with no range selected the CTA is inert (IgnorePointer) AND '
      'shows the range placeholder — no dead-button trap', (tester) async {
    // A schedule whose seed window collapses to null → sheet opens with no
    // pre-selected range.
    final router = GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const Key('open-apply-sheet'),
                onPressed: () => showApplyScheduleSheet(
                  context,
                  // validTo before validFrom → _seedRangeFromSchedule returns
                  // null, so the sheet opens with no range.
                  baseSchedule: _baseSchedule(id: 's1').copyWith(
                    validFrom: DateTime(2024, 5, 22),
                    validTo: DateTime(2024, 5, 21),
                  ),
                  today: _today,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        retry: beauticaProviderRetry,
        overrides: <Object>[
          scheduleRepositoryProvider.overrideWithValue(repo),
        ].cast(),
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('uk'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-apply-sheet')));
    await tester.pumpAndSettle();

    // The CTA exists but is wrapped in an inert IgnorePointer (disabled), AND a
    // visible placeholder explains the period must be chosen — never a silently
    // dead button.
    final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
    expect(find.byKey(const Key('btn-apply-schedule')), findsOneWidget);
    expect(find.text(l10n.applyScheduleRangePlaceholder), findsOneWidget);

    // The CLOSEST IgnorePointer ancestor (the CTA gate) is inert.
    final ignorePointer = tester
        .widgetList<IgnorePointer>(
          find.ancestor(
            of: find.byKey(const Key('btn-apply-schedule')),
            matching: find.byType(IgnorePointer),
          ),
        )
        .first;
    expect(ignorePointer.ignoring, isTrue);

    // Tapping the inert CTA does nothing: no upsert fires.
    await tester.tap(
      find.byKey(const Key('btn-apply-schedule')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    verifyNever(
      () => repo.upsertWeeklySchedule(
        any(),
        scheduleId: any(named: 'scheduleId'),
      ),
    );
  });

  // ── M6 — first-create returns the chosen range UNCLAMPED (clamp lives in the
  //         editor's submit, not here — guards against a future double-clamp) ──
  //
  // The stale-`validFrom` fix moved the validFrom→today re-anchor/clamp to the
  // WEEKLY EDITOR's submit (`_save` / `_buildSchedule`). On a FIRST-CREATE the
  // Apply-schedule sheet must therefore STAGE the picked window verbatim — it
  // pops the chosen `DateTimeRange` to the editor WITHOUT pulling `validFrom`
  // forward to today. If a well-meaning change re-introduced the editor's clamp
  // HERE too, a window picked to start in the future would come back clamped to
  // today (a double-clamp) and this test would fail: it pins the start returned
  // is exactly the picked future start, never `today`.
  testWidgets(
    'first-create (id == null): applying a custom FUTURE window pops the chosen '
    'DateTimeRange UNCLAMPED — start is the picked day, not today',
    (tester) async {
      DateTimeRange? popped;
      bool resolved = false;
      final router = GoRouter(
        initialLocation: '/',
        routes: <RouteBase>[
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  key: const Key('open-apply-sheet'),
                  onPressed: () async {
                    // id == null → first-create: the sheet returns the chosen
                    // window as a draft rather than persisting it.
                    final Object? r = await showApplyScheduleSheet(
                      context,
                      baseSchedule: _baseSchedule(id: null),
                      today: _today,
                    );
                    resolved = true;
                    popped = r is DateTimeRange ? r : null;
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          retry: beauticaProviderRetry,
          overrides: <Object>[
            scheduleRepositoryProvider.overrideWithValue(repo),
          ].cast(),
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('uk'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-apply-sheet')));
      await tester.pumpAndSettle();

      // Pick a custom FUTURE window 24→28 May 2024 (both after today 22 May, in
      // the first rendered month → no scrolling).
      await tester.tap(find.byKey(const Key('apply-schedule-date-well')));
      await tester.pumpAndSettle();
      await tester.tap(_dayCell(24).first);
      await tester.pumpAndSettle();
      await tester.tap(_dayCell(28).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn-range-picker-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn-apply-schedule')));
      await tester.pumpAndSettle();

      // The sheet popped the staged window …
      expect(resolved, isTrue);
      expect(popped, isNotNull);
      // … with the start UNCLAMPED — the picked future day (24 May), NOT today
      // (22 May). A double-clamp here would pull it back to today.
      expect(
        popped!.start,
        DateTime(2024, 5, 24),
        reason:
            'the sheet must return the picked start verbatim — the '
            'validFrom→today clamp lives in the editor submit, not here',
      );
      expect(popped!.end, DateTime(2024, 5, 28));

      // First-create staging never persists from the sheet.
      verifyNever(
        () => repo.upsertWeeklySchedule(
          any(),
          scheduleId: any(named: 'scheduleId'),
        ),
      );
    },
  );
}

/// A tappable day cell in the [PeriodRangePicker] for the given [day] number.
/// Day cells are `GestureDetector`s wrapped in a button [Semantics] whose
/// `label` is the day-of-month string; matched by that label (M2 — keyed on the
/// int, not on a localised string).
Finder _dayCell(int day) => find.byWidgetPredicate(
  (Widget w) =>
      w is Semantics &&
      (w.properties.button ?? false) &&
      w.properties.label == '$day',
);
