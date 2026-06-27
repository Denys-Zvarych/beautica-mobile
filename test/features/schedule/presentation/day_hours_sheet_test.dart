// Phase 15.4 — Widget + golden tests for [DayHoursSheet] (Editor B): the
// per-date override modal sheet that overrides the weekly template for ONE date.
//
// Strategy (mobile-qa M1/M2/M3/M4 + Riverpod hygiene):
//   • The sheet's ONLY network surface is the `overridesProvider(range)`
//     family — it calls `.notifier.putOverride(...)` / `.notifier.clearOverride`.
//     We override the REAL data dependency `scheduleRepositoryProvider` with a
//     mocktail mock (exactly like overrides_notifier_test.dart), so the GENUINE
//     `OverridesNotifier` runs end-to-end and we assert the EXACT
//     `ScheduleOverride` it forwards to the repository — no mocking of the
//     widget-under-test, no real network/storage (M1 isolation).
//   • Finders use the source `Key`s (override-mode-working/-dayoff,
//     override-dayoff-rest, override-save, override-delete, plus the shared
//     IntervalEditor's `override-work-*` keys) — never localised strings (M2;
//     the suite has prior locale-coupling findings).
//
// Phase 15.4 contract change: the backend dropped reason/note from schedule
// overrides. Day-off mode now renders ONLY a clean rest card (keyed
// `override-dayoff-rest`) — no reason grid, no `override-note-field`. Saving a
// day-off requires no reason selection. The clear/revert button keeps Key
// `override-delete` but is now a non-destructive «Повернути до графіка» action.
//   • Goldens use the framework's `matchesGoldenFile` (golden_toolkit is not in
//     the project; the schedule goldens already use this). A fixed device size +
//     the test font keep them deterministic; the sheet is wall-clock free, so
//     they are run-day independent.
//
// OQ-1 (ALWAYS ALLOW) is asserted structurally + behaviourally: the save path
// puts the override with NO intervening confirmation dialog even when bookings
// exist (the sheet has no booking-conflict gate at all).
//
// The past-date guard and the SALON_MASTER read-only gate live on the SCREEN
// (the pencil entry point), and are already covered in
// master_schedule_screen_test.dart — referenced there, not duplicated here (M's
// "reference rather than duplicate" rule). See:
//   • 'past date hides the day pencil (read-only history)'
//   • 'SALON_MASTER (read-only): all edit affordances absent ...'

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/schedule/data/schedule_repository.dart';
import 'package:beautica_mobile/features/schedule/data/schedule_repository_provider.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:beautica_mobile/features/schedule/presentation/day_hours_sheet.dart';
import 'package:beautica_mobile/features/schedule/presentation/overrides_notifier.dart';
import 'package:beautica_mobile/features/schedule/presentation/schedule_range.dart';
import 'package:beautica_mobile/features/schedule/presentation/widgets/discrete_times_editor.dart';
import 'package:beautica_mobile/features/schedule/presentation/widgets/interval_editor.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockScheduleRepository extends Mock implements ScheduleRepository {}

// ───────────────────────────────────────────────────────────────────────────
// Fixtures.
// ───────────────────────────────────────────────────────────────────────────

final ScheduleRange _range = ScheduleRange(
  from: DateTime(2026, 6, 1),
  to: DateTime(2026, 6, 30),
);

final DateTime _date = DateTime(2026, 6, 21);

/// Fixed "today" injected into the sheet so its submit-time past-date guard is
/// run-day independent (keeps these tests wall-clock free). Anchored on [_date]
/// so the override target is today, never past.
DateTime _testToday() => _date;

WorkInterval _interval(int sh, int sm, int eh, int em) => WorkInterval(
  start: TimeOfDay(hour: sh, minute: sm),
  end: TimeOfDay(hour: eh, minute: em),
);

/// The day's current working intervals (a split 09:00–13:00 · 14:00–18:00 day),
/// used to seed the IntervalEditor in working-hours mode.
List<WorkInterval> _currentIntervals() => <WorkInterval>[
  _interval(9, 0, 13, 0),
  _interval(14, 0, 18, 0),
];

// ───────────────────────────────────────────────────────────────────────────
// Harness — pumps a host scaffold whose single button presents the sheet, so
// the sheet runs through its real `showModalBottomSheet` entry point.
// ───────────────────────────────────────────────────────────────────────────

Future<void> _pumpSheet(
  WidgetTester tester, {
  required ScheduleRepository repo,
  List<WorkInterval>? initialIntervals,
  bool hasExistingOverride = false,
  bool initialDayOff = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Object>[
        scheduleRepositoryProvider.overrideWithValue(repo),
      ].cast(),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('uk'),
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => Center(
              child: ElevatedButton(
                key: const Key('open-sheet'),
                onPressed: () => DayHoursSheet.show(
                  context,
                  date: _date,
                  weekdayFull: 'Неділя',
                  dateLabel: '21 червня',
                  range: _range,
                  initialIntervals: initialIntervals ?? _currentIntervals(),
                  hasExistingOverride: hasExistingOverride,
                  initialDayOff: initialDayOff,
                  clock: _testToday,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.byKey(const Key('open-sheet')));
  await tester.pumpAndSettle();
}

/// Drains the bounded-cache keepAlive [Timer] the real [OverridesNotifier] parks
/// after a successful load (`overrides_notifier.dart` —
/// `Timer(_kOverridesCacheTtl, link.close)`). Tests that build a genuine
/// `overridesProvider` and hold a live subscription leave that 5-min release
/// timer parked: the held subscription keeps the provider alive, so its
/// `onDispose(timer.cancel)` does not fire before the body ends, and Flutter's
/// FakeAsync teardown trips `A Timer is still pending even after the widget tree
/// was disposed`. This is test-side timer hygiene only — on device `onDispose`
/// cancels the timer on real disposal. Advancing fake time past the TTL fires
/// the release timer, leaving zero pending timers at teardown. It changes no
/// rendered content, so it cannot weaken the assertions made before it.
Future<void> _drainKeepAliveTimers(WidgetTester tester) async {
  await tester.pump(
    const Duration(minutes: 6),
  ); // > _kOverridesCacheTtl (5 min)
  await tester.pumpAndSettle();
}

/// A repository whose `putOverride` echoes its argument and whose `clearOverride`
/// resolves; `listOverrides` returns empty so the post-mutation reload settles.
_MockScheduleRepository _happyRepo() {
  final repo = _MockScheduleRepository();
  when(
    () => repo.listOverrides(any(), any()),
  ).thenAnswer((_) async => const <ScheduleOverride>[]);
  when(() => repo.putOverride(any())).thenAnswer(
    (inv) async => inv.positionalArguments.first as ScheduleOverride,
  );
  when(() => repo.clearOverride(any())).thenAnswer((_) async {});
  return repo;
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      ScheduleOverride.dayOff(
        start: DateTime(2026, 6, 1),
        end: DateTime(2026, 6, 1),
      ),
    );
    registerFallbackValue(DateTime(2026, 6, 1));
  });

  // ── Working-hours mode → CUSTOM_HOURS override ─────────────────────────────

  group('DayHoursSheet — working-hours mode (CUSTOM_HOURS)', () {
    testWidgets(
      'opens in working-hours mode seeded from current intervals; save puts a '
      'single-date CUSTOM_HOURS override with those intervals and NO reason',
      (tester) async {
        final repo = _happyRepo();
        await _pumpSheet(tester, repo: repo);

        // Working-hours mode is the default surface: the shared IntervalEditor's
        // window pickers (keyed with the `override` prefix) render; the day-off
        // rest card does not.
        expect(find.byKey(const Key('override-work-start')), findsOneWidget);
        expect(find.byKey(const Key('override-work-end')), findsOneWidget);
        expect(find.byKey(const Key('override-dayoff-rest')), findsNothing);

        await tester.tap(find.byKey(const Key('override-save')));
        await tester.pumpAndSettle();

        final captured = verify(
          () => repo.putOverride(captureAny()),
        ).captured.cast<ScheduleOverride>();
        expect(captured, hasLength(1));
        final ScheduleOverride o = captured.single;

        // CUSTOM_HOURS, single date == the targeted date.
        expect(o.kind, OverrideKind.custom);
        expect(o.isSingleDay, isTrue);
        expect(o.start, _date);
        expect(o.end, _date);

        // The intervals are the seeded current intervals (09:00–13:00 ·
        // 14:00–18:00), round-tripped through DayHours.fromIntervals/toIntervals.
        expect(o.intervals, hasLength(2));
        expect(o.intervals[0].start, const TimeOfDay(hour: 9, minute: 0));
        expect(o.intervals[0].end, const TimeOfDay(hour: 13, minute: 0));
        expect(o.intervals[1].start, const TimeOfDay(hour: 14, minute: 0));
        expect(o.intervals[1].end, const TimeOfDay(hour: 18, minute: 0));

        // The sheet dismissed itself on success.
        expect(find.byKey(const Key('override-save')), findsNothing);
      },
    );

    // STRUCTURAL PIN (Phase 15.8 — golden-is-not-acceptance). Custom-hours mode
    // now carries a work-mode sub-toggle (Інтервал / Окремі години) that swaps
    // the editor body. The acceptance for this layout is the structural
    // assertion below; the golden that follows is a SUPPLEMENTARY visual check
    // re-blessed only after this structure was confirmed correct, so the
    // self-referential re-bless can never silently mask a regression. Finders
    // use the source Keys + widget TYPES (M2/M11), never localised copy.
    testWidgets(
      'custom-hours mode renders the work-mode sub-toggle; INTERVAL shows the '
      'IntervalEditor and tapping «Окремі години» swaps to the DiscreteTimesEditor',
      (tester) async {
        final repo = _happyRepo();
        await _pumpSheet(tester, repo: repo);

        // The work-mode sub-toggle and both segment chips render in the default
        // (working-hours) surface.
        expect(
          find.byKey(const Key('override-work-mode-toggle')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('override-work-mode-interval')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('override-work-mode-explicit')),
          findsOneWidget,
        );

        // INTERVAL is the default mode → the IntervalEditor body is shown, the
        // DiscreteTimesEditor body is absent.
        expect(find.byType(IntervalEditor), findsOneWidget);
        expect(find.byType(DiscreteTimesEditor), findsNothing);

        // Tapping «Окремі години» swaps the body: IntervalEditor gone,
        // DiscreteTimesEditor present (with its add-time affordance keyed
        // `override-add-time`).
        await tester.tap(find.byKey(const Key('override-work-mode-explicit')));
        await tester.pumpAndSettle();

        expect(find.byType(DiscreteTimesEditor), findsOneWidget);
        expect(find.byType(IntervalEditor), findsNothing);
        expect(find.byKey(const Key('override-add-time')), findsOneWidget);
      },
    );

    // SUPPLEMENTARY golden (re-blessed for the Phase 15.8 work-mode-toggle
    // layout AFTER the structural pin above confirmed the render is correct).
    testWidgets('custom-hours mode matches its golden', (tester) async {
      final repo = _happyRepo();
      await _pumpSheet(tester, repo: repo);

      await expectLater(
        find.byType(DayHoursSheet),
        matchesGoldenFile('goldens/day_hours_sheet_custom_hours.png'),
      );
    });
  });

  // ── Day-off mode → DAY_OFF override ────────────────────────────────────────

  group('DayHoursSheet — day-off mode (DAY_OFF)', () {
    testWidgets(
      'switching to «Вихідний» shows ONLY the clean rest card — NO reason grid, '
      'NO note field, working-hours pickers gone (Phase 15.4 contract)',
      (tester) async {
        final repo = _happyRepo();
        await _pumpSheet(tester, repo: repo);

        // Switch to day-off mode.
        await tester.tap(find.byKey(const Key('override-mode-dayoff')));
        await tester.pumpAndSettle();

        // The clean rest card is the ONLY day-off affordance.
        expect(find.byKey(const Key('override-dayoff-rest')), findsOneWidget);
        // The reason grid is GONE (the four chips no longer exist) …
        expect(find.byKey(const Key('override-reason-VACATION')), findsNothing);
        expect(find.byKey(const Key('override-reason-HOLIDAY')), findsNothing);
        expect(find.byKey(const Key('override-reason-SICK_DAY')), findsNothing);
        expect(find.byKey(const Key('override-reason-OTHER')), findsNothing);
        // … the note field is GONE …
        expect(find.byKey(const Key('override-note-field')), findsNothing);
        // … and the working-hours pickers are not on screen in day-off mode.
        expect(find.byKey(const Key('override-work-start')), findsNothing);
      },
    );

    testWidgets(
      'saving a day-off needs NO reason selection — the put fires a plain '
      'single-date DAY_OFF override with empty intervals',
      (tester) async {
        final repo = _happyRepo();
        await _pumpSheet(tester, repo: repo, initialDayOff: true);

        // No reason picked (none exists); save straight away.
        await tester.ensureVisible(find.byKey(const Key('override-save')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('override-save')));
        await tester.pumpAndSettle();

        final captured = verify(
          () => repo.putOverride(captureAny()),
        ).captured.cast<ScheduleOverride>();
        expect(captured, hasLength(1));
        final ScheduleOverride o = captured.single;

        expect(o.kind, OverrideKind.dayOff);
        expect(o.isSingleDay, isTrue);
        expect(o.start, _date);
        expect(o.end, _date);
        expect(o.intervals, isEmpty);
      },
    );

    // REGRESSION (UI fix): the day-off rest card is wrapped in
    // `SizedBox(width: double.infinity)` so it spans the FULL sheet content
    // width (it previously sized to its child and looked shifted left). This is
    // the STRUCTURAL pin for that fix so the golden's self-referential re-bless
    // can never silently mask a regression (backlog: goldens are self-referential
    // — confirm against intent). We assert via the source Key (M2/M11: keyed
    // finder + the localised l10n value, never a raw UA literal) that:
    //   • the renamed `scheduleOverrideDayOffRest` label renders inside the card,
    //   • the card's rendered width equals the available sheet content width
    //     (proving `SizedBox(width: double.infinity)` took effect — guards the
    //     left-shift regression).
    testWidgets(
      'the day-off rest card spans full sheet width and shows the localized '
      'scheduleOverrideDayOffRest label (left-shift + rename regression)',
      (tester) async {
        final repo = _happyRepo();
        await _pumpSheet(tester, repo: repo, initialDayOff: true);

        final Finder card = find.byKey(const Key('override-dayoff-rest'));
        expect(card, findsOneWidget);

        // The label resolves to the renamed l10n value (not a raw UA literal),
        // read from AppLocalizations, and renders inside the keyed card.
        final AppLocalizations l10n = AppLocalizations.of(
          tester.element(find.byType(DayHoursSheet)),
        );
        expect(
          find.descendant(
            of: card,
            matching: find.text(l10n.scheduleOverrideDayOffRest),
          ),
          findsOneWidget,
        );

        // The card fills the full content width: the `SizedBox(width:
        // double.infinity)` constrains it to its parent's max width. The mode
        // toggle Row (key override-mode-toggle) is a sibling in the SAME padded
        // content column, so its rendered width IS the available content width —
        // the rest card must match it.
        final double cardWidth = tester.getSize(card).width;
        final double contentWidth = tester
            .getSize(find.byKey(const Key('override-mode-toggle')))
            .width;

        expect(
          cardWidth,
          moreOrLessEquals(contentWidth, epsilon: 1.0),
          reason:
              'the day-off rest card must fill the full sheet content width '
              '(SizedBox(width: double.infinity)); a narrower width means the '
              'left-shift regression returned',
        );
      },
    );

    // Golden is a SUPPLEMENTARY visual check only — the acceptance for day-off
    // mode is the STRUCTURAL assertion above (rest card present; reason grid +
    // note field absent). The PNG was re-blessed against the new clean rest-card
    // render after the structure was confirmed correct; it is not the source of
    // truth for the contract change.
    testWidgets('day-off mode (clean rest card) matches its golden', (
      tester,
    ) async {
      final repo = _happyRepo();
      await _pumpSheet(tester, repo: repo, initialDayOff: true);

      await expectLater(
        find.byType(DayHoursSheet),
        matchesGoldenFile('goldens/day_hours_sheet_day_off.png'),
      );
    });
  });

  // ── Existing override → clear ──────────────────────────────────────────────

  group('DayHoursSheet — revert-to-template (clear) an existing override', () {
    testWidgets(
      'when an override already exists the revert action is present; tapping it '
      'calls clearOverride(date) — the clear→revert-to-template path',
      (tester) async {
        final repo = _happyRepo();
        await _pumpSheet(tester, repo: repo, hasExistingOverride: true);

        expect(find.byKey(const Key('override-delete')), findsOneWidget);

        // Phase 15.8: the sheet body now carries the work-mode sub-toggle +
        // discrete editor, so the content column is taller and the revert
        // action can sit below the fold of the scroll-controlled sheet. Scroll
        // it into view before tapping (mirrors the already-passing failure-path
        // test at the bottom of this file).
        await tester.ensureVisible(find.byKey(const Key('override-delete')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('override-delete')));
        await tester.pumpAndSettle();

        final captured = verify(
          () => repo.clearOverride(captureAny()),
        ).captured.cast<DateTime>();
        expect(captured, hasLength(1));
        expect(captured.single, _date);
        // No put on a clear.
        verifyNever(() => repo.putOverride(any()));
      },
    );

    // REGRESSION (Phase 15.4 rename): the clear/revert button is now the
    // non-destructive «Повернути до графіка» action — its label changed from
    // «Видалити перевизначення». We assert the new label via the keyed widget's
    // text resolving to `l10n.scheduleOverrideDelete` (M2/M11: keyed finder +
    // localised value, never a raw-string finder).
    testWidgets('the revert button (keyed override-delete) shows the new '
        '«Повернути до графіка» label', (tester) async {
      final repo = _happyRepo();
      await _pumpSheet(tester, repo: repo, hasExistingOverride: true);

      final Finder button = find.byKey(const Key('override-delete'));
      expect(button, findsOneWidget);

      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(DayHoursSheet)),
      );
      // The label inside the keyed button resolves to the renamed l10n value.
      expect(
        find.descendant(
          of: button,
          matching: find.text(l10n.scheduleOverrideDelete),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the clear action is absent when no override exists', (
      tester,
    ) async {
      final repo = _happyRepo();
      await _pumpSheet(tester, repo: repo, hasExistingOverride: false);

      expect(find.byKey(const Key('override-delete')), findsNothing);
    });
  });

  // ── show() return contract (jump-to-changed-day fix) ───────────────────────
  //
  // `DayHoursSheet.show(...)` is now `Future<DateTime?>`: the host
  // (`master_schedule_screen._openDayOverride`) awaits it and, on a NON-null
  // result, moves the selected day onto the edited date and re-reads the fresh
  // effective schedule. These tests pin BOTH branches of that contract:
  //   • a successful save  → resolves with the edited date,
  //   • a successful clear → resolves with the edited date,
  //   • a plain dismiss / a validation bail → resolves with `null` (M3: the
  //     no-op branch is covered, not just the happy path).
  // We capture the resolved future via a host that stores it (the standard
  // `_pumpSheet` discards it).

  group('DayHoursSheet.show — resolves with the edited date / null', () {
    testWidgets(
      'a successful CUSTOM_HOURS save resolves the future with the edited date',
      (tester) async {
        final repo = _happyRepo();
        final DateTime? result = await _pumpCapturingSheet(
          tester,
          repo: repo,
          interact: (tester) async {
            await tester.tap(find.byKey(const Key('override-save')));
            await tester.pumpAndSettle();
          },
        );

        expect(result, isNotNull);
        expect(result, _date);
      },
    );

    testWidgets(
      'a successful DAY_OFF save resolves the future with the edited date',
      (tester) async {
        final repo = _happyRepo();
        final DateTime? result = await _pumpCapturingSheet(
          tester,
          repo: repo,
          initialDayOff: true,
          interact: (tester) async {
            await tester.ensureVisible(find.byKey(const Key('override-save')));
            await tester.pumpAndSettle();
            await tester.tap(find.byKey(const Key('override-save')));
            await tester.pumpAndSettle();
          },
        );

        expect(result, _date);
      },
    );

    testWidgets('a successful clear resolves the future with the edited date', (
      tester,
    ) async {
      final repo = _happyRepo();
      final DateTime? result = await _pumpCapturingSheet(
        tester,
        repo: repo,
        hasExistingOverride: true,
        interact: (tester) async {
          // Phase 15.8: scroll the revert action into view first — the taller
          // work-mode-toggle body can push it below the scroll fold.
          await tester.ensureVisible(find.byKey(const Key('override-delete')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('override-delete')));
          await tester.pumpAndSettle();
        },
      );

      expect(result, _date);
      // The clear ran (not a put).
      verify(() => repo.clearOverride(any())).called(1);
      verifyNever(() => repo.putOverride(any()));
    });

    testWidgets(
      'dismissing via the close button resolves the future with null (no-op)',
      (tester) async {
        final repo = _happyRepo();
        final DateTime? result = await _pumpCapturingSheet(
          tester,
          repo: repo,
          interact: (tester) async {
            await tester.tap(find.byKey(const Key('override-close')));
            await tester.pumpAndSettle();
          },
        );

        expect(result, isNull);
        // A plain dismiss never persists anything.
        verifyNever(() => repo.putOverride(any()));
        verifyNever(() => repo.clearOverride(any()));
      },
    );

    testWidgets(
      'a validation bail (invalid window) does NOT resolve with a date: the '
      'sheet stays open, nothing is persisted, no pop',
      (tester) async {
        // Seed an INVALID working window (end before start) so `_hasErrors` is
        // true → tapping save shows the error banner and returns WITHOUT a pop.
        final repo = _happyRepo();
        DateTime? result;
        bool resolved = false;
        await _pumpSheetWithSink(
          tester,
          repo: repo,
          initialIntervals: <WorkInterval>[_interval(18, 0, 9, 0)],
          onResult: (DateTime? d) {
            resolved = true;
            result = d;
          },
        );

        await tester.tap(find.byKey(const Key('override-save')));
        await tester.pumpAndSettle();

        // The future has NOT resolved (the sheet is still open) — the save was
        // a no-op validation bail, not a dismiss.
        expect(resolved, isFalse);
        expect(result, isNull);
        expect(find.byKey(const Key('override-save')), findsOneWidget);
        verifyNever(() => repo.putOverride(any()));
      },
    );
  });

  // ── OQ-1: always allow — no booking-conflict gate ──────────────────────────

  group('DayHoursSheet — OQ-1 always allow (no conflict gate)', () {
    testWidgets(
      'save succeeds with NO confirmation dialog even when bookings exist — the '
      'put fires directly with no intervening AlertDialog',
      (tester) async {
        // The sheet has no booking-count input and no conflict gate: regardless
        // of any bookings on the date, saving puts the override directly. We
        // assert there is NO AlertDialog between tapping save and the put, and
        // that the put happened exactly once.
        final repo = _happyRepo();
        await _pumpSheet(tester, repo: repo, initialDayOff: true);

        await tester.ensureVisible(find.byKey(const Key('override-save')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('override-save')));
        // Single pump: if a confirmation dialog gated the save, it would be on
        // screen now and the put would NOT have fired yet.
        await tester.pump();

        expect(
          find.byType(AlertDialog),
          findsNothing,
          reason: 'OQ-1: the save path must NOT raise a confirmation dialog',
        );

        await tester.pumpAndSettle();
        verify(() => repo.putOverride(any())).called(1);
      },
    );
  });

  // ── Failure path → AsyncError surfaced, sheet stays open (false-success fix) ─
  //
  // RESOLVED (false-success MEDIUM): `OverridesNotifier.putOverride` /
  // `.clearOverride` wrap their work in `AsyncValue.guard`, which SWALLOWS a
  // thrown `Failure` into the provider's `AsyncError` STATE and returns
  // NORMALLY — the awaited mutation never throws back to the widget. The sheet
  // therefore reads the POST-await provider state and branches on `hasError`:
  // on failure it KEEPS the sheet open and shows the failure message, with NO
  // pop and NO success snackbar. These tests pin that correct behaviour.
  //
  // We assert against a fresh container (whose autoDispose family stays alive
  // via a held subscription) so the AsyncError the sheet observed is the same
  // state we read back afterwards.

  group('DayHoursSheet — save failure (false-success guard)', () {
    testWidgets(
      'a repository failure on put surfaces in provider state AND keeps the '
      'sheet open with an error message — no pop, no success snackbar',
      (tester) async {
        final repo = _MockScheduleRepository();
        when(
          () => repo.listOverrides(any(), any()),
        ).thenAnswer((_) async => const <ScheduleOverride>[]);
        when(
          () => repo.putOverride(any()),
        ).thenThrow(const ServerFailure(statusCode: 500));

        final container = ProviderContainer(
          overrides: <Object>[
            scheduleRepositoryProvider.overrideWithValue(repo),
          ].cast(),
        );
        addTearDown(container.dispose);
        // Hold a live subscription so the autoDispose family is NOT torn down
        // (the sheet stays open here, but this keeps the read-back state stable).
        final sub = container.listen(
          overridesProvider(_range),
          (_, _) {},
          fireImmediately: true,
        );
        addTearDown(sub.close);
        await container.read(overridesProvider(_range).future);

        await _pumpSheetInContainer(tester, container: container);

        await tester.ensureVisible(find.byKey(const Key('override-save')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('override-save')));
        await tester.pumpAndSettle();

        // The put was attempted exactly once.
        verify(() => repo.putOverride(any())).called(1);
        // The error landed in provider state (the notifier's AsyncError).
        final state = container.read(overridesProvider(_range));
        expect(state.hasError, isTrue);
        expect(state.error, isA<ServerFailure>());

        final AppLocalizations l10n = AppLocalizations.of(
          tester.element(find.byType(DayHoursSheet)),
        );
        // The sheet STAYS OPEN — the save button is still on screen.
        expect(find.byKey(const Key('override-save')), findsOneWidget);
        // The mapped failure message is shown …
        expect(find.text(l10n.errServer), findsOneWidget);
        // … and the success copy is ABSENT.
        expect(find.text(l10n.savedSnackbar), findsNothing);

        // The real OverridesNotifier parked a 5-min keepAlive release timer;
        // drain it so the FakeAsync teardown sees zero pending timers.
        await _drainKeepAliveTimers(tester);
      },
    );

    testWidgets(
      'a repository failure on clear surfaces in provider state AND keeps the '
      'sheet open with an error message — no pop, no cleared snackbar',
      (tester) async {
        final repo = _MockScheduleRepository();
        when(
          () => repo.listOverrides(any(), any()),
        ).thenAnswer((_) async => const <ScheduleOverride>[]);
        when(
          () => repo.clearOverride(any()),
        ).thenThrow(const ServerFailure(statusCode: 500));

        final container = ProviderContainer(
          overrides: <Object>[
            scheduleRepositoryProvider.overrideWithValue(repo),
          ].cast(),
        );
        addTearDown(container.dispose);
        final sub = container.listen(
          overridesProvider(_range),
          (_, _) {},
          fireImmediately: true,
        );
        addTearDown(sub.close);
        await container.read(overridesProvider(_range).future);

        // hasExistingOverride → the «Видалити» (clear) action is present.
        await _pumpSheetInContainer(
          tester,
          container: container,
          hasExistingOverride: true,
        );

        await tester.ensureVisible(find.byKey(const Key('override-delete')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('override-delete')));
        await tester.pumpAndSettle();

        // The clear was attempted exactly once; no put on a clear.
        verify(() => repo.clearOverride(any())).called(1);
        verifyNever(() => repo.putOverride(any()));
        // The error landed in provider state.
        final state = container.read(overridesProvider(_range));
        expect(state.hasError, isTrue);
        expect(state.error, isA<ServerFailure>());

        final AppLocalizations l10n = AppLocalizations.of(
          tester.element(find.byType(DayHoursSheet)),
        );
        // The sheet STAYS OPEN — the clear action is still on screen.
        expect(find.byKey(const Key('override-delete')), findsOneWidget);
        // The mapped failure message is shown …
        expect(find.text(l10n.errServer), findsOneWidget);
        // … and the cleared-success copy is ABSENT.
        expect(find.text(l10n.scheduleOverrideClearedSnack), findsNothing);

        // Drain the real OverridesNotifier's 5-min keepAlive release timer.
        await _drainKeepAliveTimers(tester);
      },
    );
  });

  // ── M6 — submit-time past-date guard (midnight rollover while open) ─────────
  //
  // The sheet is only ever OPENED for today/future days (the caller hides the
  // pencil on past ones), but a midnight rollover WHILE the sheet sits open can
  // turn the target [date] past between open and Save. A past `start` would 400
  // at the backend (@FutureOrPresent). The fix threads a LIVE
  // `DateTime Function()? clock` into the sheet and, at submit, re-validates the
  // target date against a FRESH today: a now-past date shows the
  // `schedulePastDayBlocked` snackbar and returns BEFORE `putOverride`.
  //
  // We advance the injected clock between open and Save (no new production seam —
  // the dev made the clock live). RED-ON-PRE-FIX: without the submit-time guard
  // the Save would PUT the override for the now-yesterday date, so
  // `verifyNever(putOverride)` fails and the block snackbar never shows.
  group('DayHoursSheet — M6 submit-time past-date guard (rollover)', () {
    testWidgets(
      'a rollover that turns the target date past between open and Save BLOCKS '
      'the put and shows schedulePastDayBlocked — sheet stays open',
      (tester) async {
        final repo = _happyRepo();
        // Live clock starts on the target date (today) and is advanced to the
        // next day AFTER the sheet is open but BEFORE Save.
        DateTime now = _date;
        await tester.pumpWidget(
          ProviderScope(
            overrides: <Object>[
              scheduleRepositoryProvider.overrideWithValue(repo),
            ].cast(),
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('uk'),
              home: Scaffold(
                body: Builder(
                  builder: (BuildContext context) => Center(
                    child: ElevatedButton(
                      key: const Key('open-sheet'),
                      onPressed: () => DayHoursSheet.show(
                        context,
                        date: _date,
                        weekdayFull: 'Неділя',
                        dateLabel: '21 червня',
                        range: _range,
                        initialIntervals: _currentIntervals(),
                        hasExistingOverride: false,
                        initialDayOff: false,
                        clock: () => now,
                      ),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byKey(const Key('open-sheet')));
        await tester.pumpAndSettle();

        // ── Cross midnight while the sheet is open: today is now _date + 1, so
        // the target [date] has fallen into the past. ──
        now = _date.add(const Duration(days: 1));

        // Save — the submit-time guard must block the PUT.
        await tester.ensureVisible(find.byKey(const Key('override-save')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('override-save')));
        await tester.pumpAndSettle();

        final AppLocalizations l10n = AppLocalizations.of(
          tester.element(find.byType(DayHoursSheet)),
        );
        // The block snackbar is shown …
        expect(
          find.text(l10n.schedulePastDayBlocked),
          findsOneWidget,
          reason: 'a now-past target date must surface the blocked-day copy',
        );
        // … the override was NEVER put (the guard returns before persistence) …
        verifyNever(() => repo.putOverride(any()));
        // … and the sheet stays open (no dismiss, no success snackbar).
        expect(find.byKey(const Key('override-save')), findsOneWidget);
        expect(find.text(l10n.savedSnackbar), findsNothing);
      },
    );

    testWidgets(
      'NO rollover (target date still today at Save) puts the override normally '
      '— the guard does not block a still-valid date',
      (tester) async {
        // Control case: the clock never advances, so the target stays today and
        // the put proceeds. Proves the guard is scoped to the rollover, not a
        // blanket block. (The fixed-clock _pumpSheet already injects _testToday.)
        final repo = _happyRepo();
        await _pumpSheet(tester, repo: repo, initialDayOff: true);

        // Resolve l10n while the sheet is still mounted (a successful save
        // dismisses it).
        final AppLocalizations l10n = AppLocalizations.of(
          tester.element(find.byType(DayHoursSheet)),
        );

        await tester.ensureVisible(find.byKey(const Key('override-save')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('override-save')));
        await tester.pumpAndSettle();

        verify(() => repo.putOverride(any())).called(1);
        expect(find.text(l10n.schedulePastDayBlocked), findsNothing);
      },
    );
  });
}

/// Pumps the sheet over an externally-built [container] (so the caller can hold
/// a live subscription and read the provider's post-mutation state back). Mirror
/// of [_pumpSheet] but bound to an [UncontrolledProviderScope].
Future<void> _pumpSheetInContainer(
  WidgetTester tester, {
  required ProviderContainer container,
  bool hasExistingOverride = false,
  bool initialDayOff = true,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('uk'),
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => Center(
              child: ElevatedButton(
                key: const Key('open-sheet'),
                onPressed: () => DayHoursSheet.show(
                  context,
                  date: _date,
                  weekdayFull: 'Неділя',
                  dateLabel: '21 червня',
                  range: _range,
                  initialIntervals: _currentIntervals(),
                  hasExistingOverride: hasExistingOverride,
                  initialDayOff: initialDayOff,
                  clock: _testToday,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open-sheet')));
  await tester.pumpAndSettle();
}

/// Pumps the sheet, opens it, runs [interact], and RETURNS the value the
/// `DayHoursSheet.show(...)` future resolved to. Mirrors [_pumpSheet] but keeps
/// the awaited future so the `Future<DateTime?>` show-contract can be asserted.
Future<DateTime?> _pumpCapturingSheet(
  WidgetTester tester, {
  required ScheduleRepository repo,
  required Future<void> Function(WidgetTester) interact,
  bool hasExistingOverride = false,
  bool initialDayOff = false,
}) async {
  DateTime? captured;
  await _pumpSheetWithSink(
    tester,
    repo: repo,
    hasExistingOverride: hasExistingOverride,
    initialDayOff: initialDayOff,
    onResult: (DateTime? d) => captured = d,
  );
  await interact(tester);
  return captured;
}

/// Host whose button presents the sheet and pipes the resolved `Future<DateTime?>`
/// into [onResult]. The sink fires once the sheet's future completes (on a
/// save / clear / dismiss); it is NEVER called while the sheet stays open (e.g.
/// after a validation bail), which is what lets the bail test assert the future
/// has not resolved.
Future<void> _pumpSheetWithSink(
  WidgetTester tester, {
  required ScheduleRepository repo,
  required void Function(DateTime?) onResult,
  List<WorkInterval>? initialIntervals,
  bool hasExistingOverride = false,
  bool initialDayOff = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Object>[
        scheduleRepositoryProvider.overrideWithValue(repo),
      ].cast(),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('uk'),
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => Center(
              child: ElevatedButton(
                key: const Key('open-sheet'),
                onPressed: () async {
                  final DateTime? r = await DayHoursSheet.show(
                    context,
                    date: _date,
                    weekdayFull: 'Неділя',
                    dateLabel: '21 червня',
                    range: _range,
                    initialIntervals: initialIntervals ?? _currentIntervals(),
                    hasExistingOverride: hasExistingOverride,
                    initialDayOff: initialDayOff,
                    clock: _testToday,
                  );
                  onResult(r);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open-sheet')));
  await tester.pumpAndSettle();
}
