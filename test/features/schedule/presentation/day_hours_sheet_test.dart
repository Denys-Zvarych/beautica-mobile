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
//     override-reason-VACATION, override-note-field, override-save,
//     override-delete, plus the shared IntervalEditor's `override-work-*` keys)
//     — never localised strings (M2; the suite has prior locale-coupling
//     findings).
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
  OverrideReason? initialReason,
  String? initialNote,
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
                  initialReason: initialReason,
                  initialNote: initialNote,
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
        reason: OverrideReason.other,
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
        // reason picker does not.
        expect(find.byKey(const Key('override-work-start')), findsOneWidget);
        expect(find.byKey(const Key('override-work-end')), findsOneWidget);
        expect(find.byKey(const Key('override-reason-VACATION')), findsNothing);

        await tester.tap(find.byKey(const Key('override-save')));
        await tester.pumpAndSettle();

        final captured = verify(
          () => repo.putOverride(captureAny()),
        ).captured.cast<ScheduleOverride>();
        expect(captured, hasLength(1));
        final ScheduleOverride o = captured.single;

        // CUSTOM_HOURS, single date == the targeted date, NO reason/note.
        expect(o.kind, OverrideKind.custom);
        expect(o.isSingleDay, isTrue);
        expect(o.start, _date);
        expect(o.end, _date);
        expect(o.reason, isNull);
        expect(o.note, isNull);

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
      'switching to «Вихідний» renders the four reason chips; picking VACATION '
      '+ a note saves a single-date DAY_OFF override (reason VACATION, note set, '
      'empty intervals)',
      (tester) async {
        final repo = _happyRepo();
        await _pumpSheet(tester, repo: repo);

        // Switch to day-off mode.
        await tester.tap(find.byKey(const Key('override-mode-dayoff')));
        await tester.pumpAndSettle();

        // All four reason chips render; the working-hours pickers are gone.
        expect(
          find.byKey(const Key('override-reason-VACATION')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('override-reason-HOLIDAY')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('override-reason-SICK_DAY')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('override-reason-OTHER')), findsOneWidget);
        expect(find.byKey(const Key('override-work-start')), findsNothing);

        // Pick VACATION and enter a note.
        await tester.tap(find.byKey(const Key('override-reason-VACATION')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('override-note-field')),
          'на морі',
        );
        await tester.pumpAndSettle();

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
        expect(o.reason, OverrideReason.vacation);
        // Wire value pinned exactly (the backend enum contract).
        expect(o.reason!.wire, 'VACATION');
        expect(o.note, 'на морі');
        expect(o.intervals, isEmpty);
      },
    );

    testWidgets(
      'a blank note saves a DAY_OFF override with a null note (not an empty '
      'string)',
      (tester) async {
        final repo = _happyRepo();
        await _pumpSheet(tester, repo: repo, initialDayOff: true);

        // Default reason is VACATION; leave the note blank, save.
        await tester.ensureVisible(find.byKey(const Key('override-save')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('override-save')));
        await tester.pumpAndSettle();

        final captured = verify(
          () => repo.putOverride(captureAny()),
        ).captured.cast<ScheduleOverride>();
        final ScheduleOverride o = captured.single;
        expect(o.kind, OverrideKind.dayOff);
        expect(o.reason, OverrideReason.vacation);
        expect(o.note, isNull);
        expect(o.intervals, isEmpty);
      },
    );

    testWidgets('day-off mode (reason chips) matches its golden', (
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

  group('DayHoursSheet — clear an existing override', () {
    testWidgets(
      'when an override already exists the «Видалити» action is present; '
      'tapping it calls clearOverride(date)',
      (tester) async {
        final repo = _happyRepo();
        await _pumpSheet(tester, repo: repo, hasExistingOverride: true);

        expect(find.byKey(const Key('override-delete')), findsOneWidget);

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

    testWidgets('the clear action is absent when no override exists', (
      tester,
    ) async {
      final repo = _happyRepo();
      await _pumpSheet(tester, repo: repo, hasExistingOverride: false);

      expect(find.byKey(const Key('override-delete')), findsNothing);
    });
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
