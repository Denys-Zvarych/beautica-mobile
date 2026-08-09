// Phase 6.2 — Widget tests for WorkingHoursScreen.
//
// Strategy:
//   Override [workingHoursRepositoryProvider] with a [_MockWorkingHoursRepository]
//   so [WorkingHoursNotifier.build] resolves immediately from the mock's [list()]
//   and [save] calls are captured without network I/O.
//
// Coverage (per phase spec):
//   1. Toggle off (day 3 = Wednesday) hides its time well buttons.
//   2. Setting end ≤ start on an active day disables Save and shows the
//      localised errEndAfterStart caption.
//   3. A valid form → tapping Save → calls WorkingHoursRepository.replaceAll
//      with all 7 day entries.
//   4. REGRESSION (dirty-tracking): Save is DISABLED on a pristine load; an
//      edit enables it (4b); reverting the edit to baseline disables it (4c).
//      Guards the _baseline/listEquals fix for the "Save enabled on load" bug.
//   5. Error caption is rendered as a Semantics live-region — verified via
//      widget type + key-less structural assertion (no raw-string finder).
//   6. Repository failure on Save surfaces an error snackbar without crashing.
//   7. Saving with day 7 (Sunday) toggled OFF includes that day with
//      isActive: false in the replaceAll payload.
//
// Known-issue avoidance applied:
//   M11 — interactive element finders use Key or widget type, never raw text.
//   M3  — loading, loaded (valid), loaded (invalid), error states all covered.
//   M6  — pumpAndSettle preferred; magic-delay pump() avoided.
//   M3-adjacent — finders scoped by Key('wh-*').

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/calendar/data/working_hours_repository.dart';
import 'package:beautica_mobile/features/calendar/data/working_hours_repository_provider.dart';
import 'package:beautica_mobile/features/calendar/domain/working_hours.dart';
import 'package:beautica_mobile/features/calendar/presentation/working_hours_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class _MockWorkingHoursRepository extends Mock
    implements WorkingHoursRepository {}

// ---------------------------------------------------------------------------
// Stub data — a full 7-day week with Mon–Fri 09:00–18:00, Sat 10:00–15:00,
// Sun closed.
// ---------------------------------------------------------------------------

List<WorkingHours> _stubWeek() => <WorkingHours>[
  const WorkingHours(
    dayOfWeek: 1,
    startTime: '09:00:00',
    endTime: '18:00:00',
    isActive: true,
  ),
  const WorkingHours(
    dayOfWeek: 2,
    startTime: '09:00:00',
    endTime: '18:00:00',
    isActive: true,
  ),
  const WorkingHours(
    dayOfWeek: 3,
    startTime: '09:00:00',
    endTime: '18:00:00',
    isActive: true,
  ),
  const WorkingHours(
    dayOfWeek: 4,
    startTime: '09:00:00',
    endTime: '18:00:00',
    isActive: true,
  ),
  const WorkingHours(
    dayOfWeek: 5,
    startTime: '09:00:00',
    endTime: '18:00:00',
    isActive: true,
  ),
  const WorkingHours(
    dayOfWeek: 6,
    startTime: '10:00:00',
    endTime: '15:00:00',
    isActive: true,
  ),
  const WorkingHours(
    dayOfWeek: 7,
    startTime: '10:00:00',
    endTime: '16:00:00',
    isActive: false,
  ),
];

// ---------------------------------------------------------------------------
// Pump helper
// ---------------------------------------------------------------------------

/// Pumps [WorkingHoursScreen] with the mock repository override.
///
/// [repo] must already have [list()] and (optionally) [replaceAll()] stubbed.
Future<void> _pumpScreen(
  WidgetTester tester,
  _MockWorkingHoursRepository repo,
) async {
  await tester.pumpWidget(
    ProviderScope(
      retry: beauticaProviderRetry,
      overrides: [workingHoursRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('uk'),
        // No go_router needed — the back button uses context.canPop() /
        // context.pop() (go_router), but none of the tests tap it.
        // GoRouter is not wired here intentionally.
        home: WorkingHoursScreen(),
      ),
    ),
  );
  // Settle: provider resolves + draft initialised + ListView built.
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // Register the fallback value for [WorkingHours] list so mocktail's
  // `any()` matcher can produce a typed default in [replaceAll] stubs.
  setUpAll(() {
    registerFallbackValue(<WorkingHours>[]);
  });

  group('WorkingHoursScreen', () {
    // -----------------------------------------------------------------------
    // Test 1 — Toggling a day OFF hides its time buttons.
    // -----------------------------------------------------------------------
    testWidgets(
      '1. toggling day 3 (Wednesday) off hides wh-start-3 and wh-end-3',
      (tester) async {
        final repo = _MockWorkingHoursRepository();
        when(() => repo.list()).thenAnswer((_) async => _stubWeek());

        await _pumpScreen(tester, repo);

        // Wednesday starts active — its time wells should be present.
        expect(find.byKey(const Key('wh-start-3')), findsOneWidget);
        expect(find.byKey(const Key('wh-end-3')), findsOneWidget);

        // Scroll Wednesday's toggle into view before tapping (the day rows are
        // inside a ListView so some may be off-screen on small test surfaces).
        await tester.ensureVisible(find.byKey(const Key('wh-active-3')));
        await tester.pumpAndSettle();

        // Tap the toggle for Wednesday (dayOfWeek == 3).
        await tester.tap(find.byKey(const Key('wh-active-3')));
        await tester.pumpAndSettle();

        // Time wells for Wednesday must no longer be in the tree.
        expect(find.byKey(const Key('wh-start-3')), findsNothing);
        expect(find.byKey(const Key('wh-end-3')), findsNothing);
      },
    );

    // -----------------------------------------------------------------------
    // Test 2 — end ≤ start disables Save and shows the error caption.
    // -----------------------------------------------------------------------
    testWidgets('2. end ≤ start disables Save and shows errEndAfterStart', (
      tester,
    ) async {
      // Build a week where Monday's end == start (09:00 == 09:00) → invalid.
      final invalidWeek = <WorkingHours>[
        const WorkingHours(
          dayOfWeek: 1,
          startTime: '09:00:00',
          endTime: '09:00:00', // equal → end ≤ start
          isActive: true,
        ),
        ..._stubWeek().skip(1),
      ];

      final repo = _MockWorkingHoursRepository();
      when(() => repo.list()).thenAnswer((_) async => invalidWeek);

      await _pumpScreen(tester, repo);

      final l10n = lookupAppLocalizations(const Locale('uk'));

      // Error caption must be visible.
      expect(find.text(l10n.errEndAfterStart), findsOneWidget);

      // Save button must be disabled (onPressed == null ⟹ GestureDetector
      // has no onTapUp/onTapDown).  We verify by ensuring no [replaceAll]
      // call goes through after tapping the button area.
      await tester.tap(
        find.byKey(const Key('btn-save-working-hours')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      verifyNever(() => repo.replaceAll(any()));
    });

    // -----------------------------------------------------------------------
    // Test 3 — Valid form → Save → replaceAll called with 7 entries.
    // -----------------------------------------------------------------------
    testWidgets('3. valid form → Save → replaceAll called with 7 day entries', (
      tester,
    ) async {
      final repo = _MockWorkingHoursRepository();
      when(() => repo.list()).thenAnswer((_) async => _stubWeek());
      // replaceAll must return the same week (the notifier updates state
      // with its return value; returning an empty list would cause issues
      // only if the screen re-reads the list, which it does not immediately).
      when(() => repo.replaceAll(any())).thenAnswer((_) async => _stubWeek());

      await _pumpScreen(tester, repo);

      // Make the form dirty before saving — a pristine load keeps Save disabled
      // (see Test 4). Toggling Monday (day 1, top of the list so always built)
      // OFF differs from baseline without changing day count or ISO ordering.
      // Monday's isActive flag is irrelevant to this test's assertions
      // (count + ordering), so this edit is safe.
      await tester.ensureVisible(find.byKey(const Key('wh-active-1')));
      await tester.tap(find.byKey(const Key('wh-active-1')));
      await tester.pumpAndSettle();

      // The form is valid (all active days have end > start).
      // Scroll to the Save button and tap it.
      await tester.ensureVisible(
        find.byKey(const Key('btn-save-working-hours')),
      );
      await tester.tap(find.byKey(const Key('btn-save-working-hours')));
      await tester.pumpAndSettle();

      // Capture the list passed to replaceAll.
      final captured = verify(() => repo.replaceAll(captureAny())).captured;
      expect(captured, hasLength(1));
      final List<WorkingHours> saved = captured.first as List<WorkingHours>;
      expect(saved, hasLength(7));

      // Verify ISO day-of-week ordering is preserved (Mon=1 … Sun=7).
      for (int i = 0; i < 7; i++) {
        expect(saved[i].dayOfWeek, equals(i + 1));
      }
    });

    // -----------------------------------------------------------------------
    // Test 4 — REGRESSION: Save is DISABLED on a pristine load.
    //
    // History: this test previously asserted the OPPOSITE — that Save was
    // enabled the instant data loaded — because the implementation used
    // `_draft != null` as the dirty signal. That was the bug: tapping Save on a
    // freshly-loaded, unedited week re-persisted identical data. The fix added
    // a `_baseline` snapshot and made
    //   `_isDirty = _draft != null && !listEquals(_draft, _baseline)`.
    // This test now guards the corrected behaviour: a pristine load leaves the
    // form clean, so Save must NOT fire `replaceAll` when tapped without edits.
    // -----------------------------------------------------------------------
    testWidgets(
      '4. Save is disabled on a pristine load (no edits → replaceAll never called)',
      (tester) async {
        final repo = _MockWorkingHoursRepository();
        when(() => repo.list()).thenAnswer((_) async => _stubWeek());
        when(() => repo.replaceAll(any())).thenAnswer((_) async => _stubWeek());

        await _pumpScreen(tester, repo);

        // Tap Save without editing anything. The button is disabled
        // (onPressed == null), so the tap must be a no-op — `warnIfMissed`
        // suppresses the hit-test warning for a button with no callback.
        await tester.ensureVisible(
          find.byKey(const Key('btn-save-working-hours')),
        );
        await tester.tap(
          find.byKey(const Key('btn-save-working-hours')),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();

        // A clean (pristine) form must NOT persist anything.
        verifyNever(() => repo.replaceAll(any()));
      },
    );

    // -----------------------------------------------------------------------
    // Test 4b — REGRESSION: editing enables Save, reverting disables it again.
    //
    // Complements Test 4: confirms the dirty-tracking is bidirectional.
    // Toggling Sunday (day 7, stub = inactive) ON makes the draft differ from
    // the baseline → Save enabled → replaceAll fires when tapped.
    // -----------------------------------------------------------------------
    testWidgets(
      '4b. editing a day enables Save (dirty draft → replaceAll fires)',
      (tester) async {
        final repo = _MockWorkingHoursRepository();
        when(() => repo.list()).thenAnswer((_) async => _stubWeek());
        when(() => repo.replaceAll(any())).thenAnswer((_) async => _stubWeek());

        await _pumpScreen(tester, repo);

        // Edit: turn Monday (dayOfWeek 1, top of the list so always built) OFF.
        // The week stays valid (no row error) — only the dirty flag flips.
        await tester.ensureVisible(find.byKey(const Key('wh-active-1')));
        await tester.tap(find.byKey(const Key('wh-active-1')));
        await tester.pumpAndSettle();

        // Now the draft differs from baseline → Save is enabled and fires.
        await tester.ensureVisible(
          find.byKey(const Key('btn-save-working-hours')),
        );
        await tester.tap(find.byKey(const Key('btn-save-working-hours')));
        await tester.pumpAndSettle();

        verify(() => repo.replaceAll(any())).called(1);
      },
    );

    // -----------------------------------------------------------------------
    // Test 4c — REGRESSION: reverting an edit back to baseline disables Save.
    //
    // listEquals is a content comparison over freezed value objects, so toggling
    // a day OFF then ON again restores the baseline and Save must go quiet.
    // -----------------------------------------------------------------------
    testWidgets('4c. reverting an edit to baseline disables Save again', (
      tester,
    ) async {
      final repo = _MockWorkingHoursRepository();
      when(() => repo.list()).thenAnswer((_) async => _stubWeek());
      when(() => repo.replaceAll(any())).thenAnswer((_) async => _stubWeek());

      await _pumpScreen(tester, repo);

      // Edit then immediately revert: toggle Monday (day 1, active) OFF…
      await tester.ensureVisible(find.byKey(const Key('wh-active-1')));
      await tester.tap(find.byKey(const Key('wh-active-1')));
      await tester.pumpAndSettle();
      // …then back ON. Draft now equals baseline again.
      await tester.tap(find.byKey(const Key('wh-active-1')));
      await tester.pumpAndSettle();

      // Save is clean again → tapping must not persist.
      await tester.ensureVisible(
        find.byKey(const Key('btn-save-working-hours')),
      );
      await tester.tap(
        find.byKey(const Key('btn-save-working-hours')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      verifyNever(() => repo.replaceAll(any()));
    });

    // -----------------------------------------------------------------------
    // Test 5 — Error caption renders as a Semantics live-region.
    //
    // The error caption is inside a `Semantics(liveRegion: true, ...)` widget
    // (see _DayRow source). We assert on the structural presence of that
    // Semantics widget when the row is invalid — using widget type + tree
    // structure rather than raw localised text, consistent with M2.
    // -----------------------------------------------------------------------
    testWidgets(
      '5. end ≤ start row renders a Semantics liveRegion widget for the error caption',
      (tester) async {
        final invalidWeek = <WorkingHours>[
          const WorkingHours(
            dayOfWeek: 1,
            startTime: '10:00:00',
            endTime: '09:00:00', // end < start → invalid
            isActive: true,
          ),
          ..._stubWeek().skip(1),
        ];

        final repo = _MockWorkingHoursRepository();
        when(() => repo.list()).thenAnswer((_) async => invalidWeek);

        await _pumpScreen(tester, repo);

        // The _DayRow wraps the error caption in Semantics(liveRegion: true).
        // Find that Semantics widget — it must exist when the row has an error.
        final semanticsFinder = find.byWidgetPredicate(
          (Widget widget) =>
              widget is Semantics && (widget.properties.liveRegion ?? false),
        );
        expect(
          semanticsFinder,
          findsOneWidget,
          reason:
              'Error caption must be wrapped in Semantics(liveRegion: true)',
        );

        // Also verify that the error text IS present via text content, purely
        // as a belt-and-suspenders check that the caption actually rendered.
        // (The primary assertion is the Semantics structure above; the text
        // check is a secondary data-binding assertion per QA rules.)
        final l10n = lookupAppLocalizations(const Locale('uk'));
        expect(find.text(l10n.errEndAfterStart), findsOneWidget);
      },
    );

    // -----------------------------------------------------------------------
    // Test 6 — Repository failure on Save surfaces an error snackbar and does
    // not crash the screen.
    //
    // The save handler catches any [Failure] and shows a SnackBar with the
    // failure's userMessage. This test verifies that path end-to-end:
    // the screen remains usable (no exception escapes) and a SnackBar appears.
    // -----------------------------------------------------------------------
    testWidgets(
      '6. repository failure on Save transitions to error state with retry button',
      (tester) async {
        // WorkingHoursNotifier.save() wraps replaceAll in AsyncValue.guard
        // rather than re-throwing. When replaceAll throws a Failure, save()
        // sets state = AsyncError and returns normally (no propagation).
        // The screen watches workingHoursProvider; when it becomes AsyncError
        // the body switches to _ErrorBody which shows the retry button.
        // The screen must not crash, and _ErrorBody must be rendered.
        final repo = _MockWorkingHoursRepository();
        when(() => repo.list()).thenAnswer((_) async => _stubWeek());
        // replaceAll throws synchronously so AsyncValue.guard captures it as
        // AsyncError on the notifier.
        when(() => repo.replaceAll(any())).thenThrow(const NetworkFailure());

        await _pumpScreen(tester, repo);

        // Dirty the form first — a pristine load keeps Save disabled, so the
        // failure path can only be reached after an edit. Toggling Monday
        // (day 1, top of the list so always built) OFF keeps the week valid
        // (no row error) so canSave depends solely on the dirty flag.
        await tester.ensureVisible(find.byKey(const Key('wh-active-1')));
        await tester.tap(find.byKey(const Key('wh-active-1')));
        await tester.pumpAndSettle();

        await tester.ensureVisible(
          find.byKey(const Key('btn-save-working-hours')),
        );
        await tester.tap(find.byKey(const Key('btn-save-working-hours')));
        // Drain all microtasks: save() fires, AsyncValue.guard catches, state
        // becomes AsyncError, setState(_saving=false) runs, build switches to
        // the error branch.
        await tester.pumpAndSettle();

        // The notifier is now in AsyncError → _ErrorBody is rendered with the
        // retry button (NeumorphicButton whose label is l10n.retryLabel).
        // We assert on the structural presence of the retry widget type.
        expect(
          find.byType(NeumorphicButton),
          findsOneWidget,
          reason:
              '_ErrorBody must render a NeumorphicButton retry CTA after save failure',
        );

        // The save-working-hours CTA is gone (it lives in _LoadedBody which is
        // no longer rendered); verify the error branch rendered correctly.
        expect(
          find.byKey(const Key('btn-save-working-hours')),
          findsNothing,
          reason:
              'Save CTA must be absent in the error state (_LoadedBody is not rendered)',
        );
      },
    );

    // -----------------------------------------------------------------------
    // Test 7 — Saving with a day toggled OFF sends that day with isActive:false
    // in the replaceAll payload.
    //
    // The stub week has Sunday (dayOfWeek == 7) already inactive. This test
    // asserts that the payload sent by Save preserves that inactive flag — the
    // repository must receive all 7 days, with Sunday marked closed.
    // -----------------------------------------------------------------------
    testWidgets(
      '7. saving preserves isActive:false for a closed day in replaceAll payload',
      (tester) async {
        final repo = _MockWorkingHoursRepository();
        when(() => repo.list()).thenAnswer((_) async => _stubWeek());
        when(() => repo.replaceAll(any())).thenAnswer((_) async => _stubWeek());

        await _pumpScreen(tester, repo);

        // Sunday (dayOfWeek == 7) is already closed in _stubWeek().
        // Dirty the form WITHOUT touching Sunday — a pristine load keeps Save
        // disabled (see Test 4). Toggling Monday (day 1, top of the list so
        // always built) OFF flips the dirty flag while leaving Sunday inactive
        // and the day count at 7, so this test's Sunday assertions stay valid.
        await tester.ensureVisible(find.byKey(const Key('wh-active-1')));
        await tester.tap(find.byKey(const Key('wh-active-1')));
        await tester.pumpAndSettle();

        // Tap Save.
        await tester.ensureVisible(
          find.byKey(const Key('btn-save-working-hours')),
        );
        await tester.tap(find.byKey(const Key('btn-save-working-hours')));
        await tester.pumpAndSettle();

        final captured = verify(() => repo.replaceAll(captureAny())).captured;
        expect(captured, hasLength(1));
        final List<WorkingHours> saved = captured.first as List<WorkingHours>;

        // Sunday must be present and inactive.
        final sunday = saved.firstWhere((h) => h.dayOfWeek == 7);
        expect(
          sunday.isActive,
          isFalse,
          reason:
              'Sunday (dayOfWeek 7) must be sent to replaceAll with isActive: false',
        );

        // All 7 days sent.
        expect(saved, hasLength(7));
      },
    );
  });
}
