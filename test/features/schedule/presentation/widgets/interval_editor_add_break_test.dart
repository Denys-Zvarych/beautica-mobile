// Regression tests for IntervalEditor._addBreak — the "second break stacks on
// the first" bug.
//
// BUG (fixed): tapping "add break" a second time seeded an IDENTICAL interval on
// top of the first break. The two breaks overlapped, `validateDayHours` returned
// `breaksOverlap`, and Save was gated — the user could never add a second break.
//
// FIX (lib/features/schedule/presentation/widgets/interval_editor.dart):
//   • `_addBreak` seeds each new break AFTER the latest existing break's end
//     (`_nextBreakCursor`), snapped to a 15-min step, default 1h length.
//   • No-room guard: if the seeded break would spill past the window end it
//     early-returns (no degenerate/overlapping break appended, no `onChanged`).
//   • `_hasRoomForBreak` disables the add-break action once the day is full.
//
// These tests exercise the real widget against the real `override-add-break`
// key + the real `validateDayHours` domain function — no mocks needed, the
// editor is a pure StatelessWidget mutating a host-owned DayHours.

import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:beautica_mobile/features/schedule/presentation/widgets/interval_editor.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IntervalEditor._addBreak — second-break regression', () {
    testWidgets(
      'tapping add-break twice on a 09:00–18:00 day yields two distinct, '
      'non-overlapping breaks and a valid (Save-enabled) day',
      (tester) async {
        // Arrange — a default working day, no breaks. The host owns `day` and
        // rebuilds on `onChanged`, exactly like the production screen.
        final DayHours day = DayHours.defaultDay();
        await _pumpEditor(tester, day);

        // Act — tap the add-break action TWICE (the path that used to stack an
        // identical second break on the first).
        await _tapAddBreak(tester);
        await _tapAddBreak(tester);

        // Assert (a) — two breaks now exist.
        expect(
          day.breaks.length,
          2,
          reason:
              'two taps must seed two breaks (the bug produced one usable '
              'break + one stacked duplicate)',
        );

        // Assert (b) — the two breaks are DISTINCT and non-overlapping.
        final BreakRange first = day.breaks[0];
        final BreakRange second = day.breaks[1];
        expect(
          first.startMinutes == second.startMinutes &&
              first.endMinutes == second.endMinutes,
          isFalse,
          reason: 'the second break must not be an identical copy of the first',
        );
        // Sorted, the later break must start at/after the earlier one ends.
        final int earlierEnd = first.startMinutes <= second.startMinutes
            ? first.endMinutes
            : second.endMinutes;
        final int laterStart = first.startMinutes <= second.startMinutes
            ? second.startMinutes
            : first.startMinutes;
        expect(
          laterStart,
          greaterThanOrEqualTo(earlierEnd),
          reason: 'the two breaks must not overlap',
        );

        // Assert (c) — the day validates clean → no `breaksOverlap`, Save enabled.
        expect(
          validateDayHours(day),
          isNull,
          reason:
              'two non-overlapping in-window breaks must pass validation '
              'so Save stays enabled',
        );
      },
    );

    testWidgets(
      'adding breaks until the day is full never produces an overlapping or '
      'inverted break, and the full-day add is a clean no-op',
      (tester) async {
        // Arrange — a NARROW window (09:00–11:00 = 120 min). Each seeded break is
        // ~75 min (15-min gap + 60-min length), so room runs out fast and the
        // no-room guard is exercised quickly.
        final DayHours day = DayHours(
          window: WorkInterval(
            start: const TimeOfDay(hour: 9, minute: 0),
            end: const TimeOfDay(hour: 11, minute: 0),
          ),
          breaks: <BreakRange>[],
        );
        await _pumpEditor(tester, day);

        // Act — hammer the add-break action well past the day's capacity.
        for (int i = 0; i < 8; i++) {
          await _tapAddBreak(tester);
        }

        // Assert — at every step the day stayed valid: no overlap, no inverted /
        // out-of-window break ever appended.
        expect(
          validateDayHours(day),
          isNull,
          reason:
              'no tap may ever append an overlapping/inverted/out-of-window '
              'break (the guard must drop the tap instead)',
        );
        for (final BreakRange b in day.breaks) {
          expect(
            b.endMinutes,
            greaterThan(b.startMinutes),
            reason: 'no break may be degenerate / inverted',
          );
          expect(
            b.startMinutes >= day.window.startMinutes &&
                b.endMinutes <= day.window.endMinutes,
            isTrue,
            reason: 'every break must sit inside the working window',
          );
        }

        // Capture the count once full, then keep tapping — the count must not
        // grow (the add is a clean no-op once there's no room).
        final int fullCount = day.breaks.length;
        await _tapAddBreak(tester);
        await _tapAddBreak(tester);
        expect(
          day.breaks.length,
          fullCount,
          reason: 'once the day is full, add-break must no-op (length frozen)',
        );
        expect(
          validateDayHours(day),
          isNull,
          reason: 'the day stays valid after the full-day no-op taps',
        );
      },
    );
  });
}

// ───────────────────────────────────────────────────────────────────────────
// Harness.
// ───────────────────────────────────────────────────────────────────────────

/// Pumps a single [IntervalEditor] bound to [day], wired with the real localised
/// strings (resolved through `AppLocalizations`) and a host that rebuilds on
/// `onChanged` — mirroring the production screen so the rendered add-break action
/// re-evaluates `_hasRoomForBreak` after each mutation.
Future<void> _pumpEditor(WidgetTester tester, DayHours day) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('uk'),
      home: Scaffold(body: _EditorHost(day: day)),
    ),
  );
  await tester.pumpAndSettle();
}

/// Taps the add-break action by its stable key (never by Ukrainian copy) and
/// settles. The key matches the override sheet's `override-add-break` prefix.
Future<void> _tapAddBreak(WidgetTester tester) async {
  final Finder addBreak = find.byKey(const Key('override-add-break'));
  await tester.ensureVisible(addBreak);
  await tester.tap(addBreak, warnIfMissed: false);
  await tester.pumpAndSettle();
}

/// A minimal stateful host that re-renders the editor on every `onChanged`,
/// faithfully reproducing how the real schedule sheet drives the widget.
class _EditorHost extends StatefulWidget {
  const _EditorHost({required this.day});

  final DayHours day;

  @override
  State<_EditorHost> createState() => _EditorHostState();
}

class _EditorHostState extends State<_EditorHost> {
  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return SingleChildScrollView(
      child: IntervalEditor(
        day: widget.day,
        onChanged: () => setState(() {}),
        strings: _intervalStrings(l10n),
        fieldKeyPrefix: 'override',
      ),
    );
  }
}

/// Resolves the IntervalEditor's localised strings the same way the editor's
/// hosts do, so the widget renders the exact production copy.
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
      errTimeNotAligned: l10n.scheduleErrTimeNotAligned,
    );
