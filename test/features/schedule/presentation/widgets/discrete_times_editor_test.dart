// Phase 15.8 — Widget tests for [DiscreteTimesEditor] (EXPLICIT_TIMES mode).
//
// The editor is a host-driven chip list of discrete bookable start times. The
// host owns the `List<TimeOfDay>`, the editor mutates it in place and calls
// `onChanged`; the host rebuilds — exactly the production wiring in
// `weekly_template_editor_screen._DayCard` and `day_hours_sheet`.
//
// STRATEGY (mobile-qa M1/M2/M3/M6):
//   • No network/storage — the editor is a pure presentation widget over a
//     host-owned list, so a fresh `MaterialApp` + a tiny stateful host is the
//     full surface (M1 isolation).
//   • Finders key off the source `Key`s (`{prefix}-add-time`,
//     `{prefix}-chip-HH:MM`, `{prefix}-times-wrap`) and the wheel-picker confirm
//     Key (`btn-velvet-time-picker-confirm`) — never localised copy (M2). Where
//     a localised value IS asserted (the window-label prefix, the duplicate
//     message, the empty-error copy) it is read from `AppLocalizations`, never a
//     raw UA literal (M11).
//   • The wheel picker is driven exactly like velvet_time_picker_test.dart:
//     each `ListWheelScrollView` item extent is 46px, so dragging N extents
//     advances N hours/minutes. `minuteStep:15` keeps the minute wheel quarter
//     aligned, so the resulting times are always 15-min-valid.
//   • No `pump(Duration)` for layout (M6). The ONE place fake-time is advanced
//     is the duplicate-message AUTO-DISMISS, which is a real 2.5 s timer in the
//     widget — advancing past it is the deterministic way to assert it clears,
//     and is the only correct way to drain the pending timer at teardown.
//
// SEED CONTRACT (from the widget): the "add" picker seeds 09:00 when the list
// is empty, otherwise the next full hour after the last time. So:
//   • 1st add, confirm w/o scrolling  → 09:00
//   • 2nd add (list [09:00]) seeds 10:00; confirm w/o scrolling → 10:00
//   • to force a DUPLICATE, scroll the hours wheel back to 09:00 before confirm.

import 'package:beautica_mobile/features/schedule/presentation/widgets/discrete_times_editor.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const Key _addTimeKey = Key('discrete-add-time');
const Key _confirmKey = Key('btn-velvet-time-picker-confirm');

/// One wheel item extent (px) — matches velvet_time_picker's fixed extent.
const double _kItemExtent = 46.0;

void main() {
  // ── Harness ────────────────────────────────────────────────────────────────

  /// Pumps a single [DiscreteTimesEditor] bound to [times], with the real
  /// localised strings and a host that rebuilds on `onChanged` — mirroring the
  /// production `_DayCard` / sheet wiring. Uses the default `discrete` key prefix
  /// so chip / add keys are `discrete-chip-HH:MM` / `discrete-add-time`.
  Future<void> pumpEditor(WidgetTester tester, List<TimeOfDay> times) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('uk'),
        home: Scaffold(body: _EditorHost(times: times)),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Opens the add-time picker, optionally drags the hours wheel by [hourSteps]
  /// item-extents (negative = up = later, positive = down = earlier), then taps
  /// confirm. With `hourSteps == 0` the seeded time is accepted verbatim.
  Future<void> addTime(WidgetTester tester, {int hourSteps = 0}) async {
    await tester.ensureVisible(find.byKey(_addTimeKey));
    await tester.tap(find.byKey(_addTimeKey));
    await tester.pumpAndSettle();

    if (hourSteps != 0) {
      final Finder hoursWheel = find.byType(ListWheelScrollView).first;
      await tester.drag(hoursWheel, Offset(0, -_kItemExtent * hourSteps));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.byKey(_confirmKey));
    await tester.pumpAndSettle();
  }

  AppLocalizations l10nOf(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(DiscreteTimesEditor)));

  // ── Empty-state: error + save-gate surface, no chips, no window label ───────

  group('DiscreteTimesEditor — empty state (Save gate)', () {
    testWidgets(
      'an empty list renders the inline empty error and NO chips / window label '
      '(the working EXPLICIT_TIMES day is invalid → Save blocked)',
      (tester) async {
        final List<TimeOfDay> times = <TimeOfDay>[];
        await pumpEditor(tester, times);

        // No chip wrap, no chips.
        expect(find.byKey(const Key('discrete-times-wrap')), findsNothing);

        // The localised empty-error copy is shown (read from l10n, not a raw
        // literal) — this is the user-visible signal that Save is gated.
        final AppLocalizations l10n = l10nOf(tester);
        expect(find.text(l10n.discreteTimesErrEmpty), findsOneWidget);

        // The add affordance is always present.
        expect(find.byKey(_addTimeKey), findsOneWidget);
      },
    );
  });

  // ── Add → sorted chips + derived window label ───────────────────────────────

  group('DiscreteTimesEditor — add', () {
    testWidgets(
      'adding the seeded 09:00 renders a chip, clears the empty error, and the '
      'host list now holds 09:00',
      (tester) async {
        final List<TimeOfDay> times = <TimeOfDay>[];
        await pumpEditor(tester, times);

        await addTime(tester); // seed 09:00, confirm unchanged

        expect(find.byKey(const Key('discrete-chip-09:00')), findsOneWidget);
        expect(times, <TimeOfDay>[const TimeOfDay(hour: 9, minute: 0)]);

        // The empty error is gone now there is ≥1 time.
        final AppLocalizations l10n = l10nOf(tester);
        expect(find.text(l10n.discreteTimesErrEmpty), findsNothing);
      },
    );

    testWidgets(
      'adding two times keeps them sorted and shows the derived min–max window '
      'label (09:00 – 10:00)',
      (tester) async {
        final List<TimeOfDay> times = <TimeOfDay>[];
        await pumpEditor(tester, times);

        await addTime(tester); // 09:00
        await addTime(tester); // seeds next hour → 10:00

        expect(times, <TimeOfDay>[
          const TimeOfDay(hour: 9, minute: 0),
          const TimeOfDay(hour: 10, minute: 0),
        ]);
        expect(find.byKey(const Key('discrete-chip-09:00')), findsOneWidget);
        expect(find.byKey(const Key('discrete-chip-10:00')), findsOneWidget);

        // The derived window label renders the min–max span with the localised
        // prefix (read from l10n; the "HH:MM – HH:MM" range is the widget's
        // contract).
        final AppLocalizations l10n = l10nOf(tester);
        expect(
          find.text('${l10n.discreteTimesWindowLabel}  09:00 – 10:00'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'a time added out of order is re-sorted into the list (the chip set + '
      'window label reflect the canonical order)',
      (tester) async {
        // Seed the host with a single later time so the next add (which seeds
        // the next hour after the last = wraps to 09:00 only when empty) lands
        // EARLIER than an existing entry, proving sortDedupeTimes ran.
        final List<TimeOfDay> times = <TimeOfDay>[
          const TimeOfDay(hour: 15, minute: 0),
        ];
        await pumpEditor(tester, times);

        // Seed 16:00 (next hour after 15:00) but scroll the hours wheel DOWN by
        // 7 extents → 09:00, which is earlier than the existing 15:00.
        await addTime(tester, hourSteps: -7);

        expect(times, <TimeOfDay>[
          const TimeOfDay(hour: 9, minute: 0),
          const TimeOfDay(hour: 15, minute: 0),
        ], reason: '09:00 must sort BEFORE the pre-seeded 15:00');

        final AppLocalizations l10n = l10nOf(tester);
        expect(
          find.text('${l10n.discreteTimesWindowLabel}  09:00 – 15:00'),
          findsOneWidget,
        );
      },
    );
  });

  // ── Dedupe guard ─────────────────────────────────────────────────────────────

  group('DiscreteTimesEditor — dedupe guard', () {
    testWidgets(
      'picking a time that already exists is REJECTED: the list is unchanged, '
      'the transient duplicate message is shown, then auto-dismisses',
      (tester) async {
        final List<TimeOfDay> times = <TimeOfDay>[];
        await pumpEditor(tester, times);

        await addTime(tester); // 09:00 (the first add seeds 09:00)
        expect(times, <TimeOfDay>[const TimeOfDay(hour: 9, minute: 0)]);

        // Second add seeds 10:00 (next hour). Scroll the hours wheel DOWN by 1
        // extent → 09:00, which is already in the list → must be rejected.
        await addTime(tester, hourSteps: -1);

        // The list did NOT grow — the duplicate was dropped.
        expect(times, <TimeOfDay>[
          const TimeOfDay(hour: 9, minute: 0),
        ], reason: 'a duplicate pick must not be appended');
        expect(find.byKey(const Key('discrete-chip-09:00')), findsOneWidget);

        // The transient duplicate message is on screen (localised, read from
        // l10n — not a raw literal).
        final AppLocalizations l10n = l10nOf(tester);
        expect(find.text(l10n.discreteTimesDuplicateMessage), findsOneWidget);

        // It auto-dismisses after the widget's 2.5 s timer. Advancing fake time
        // past it both proves the dismissal AND drains the pending timer so the
        // FakeAsync teardown sees zero pending timers.
        await tester.pump(const Duration(milliseconds: 2600));
        await tester.pumpAndSettle();
        expect(find.text(l10n.discreteTimesDuplicateMessage), findsNothing);
      },
    );
  });

  // ── Remove ───────────────────────────────────────────────────────────────────

  group('DiscreteTimesEditor — remove', () {
    testWidgets(
      'tapping a chip’s remove ✕ deletes that time; removing the last one '
      'returns the editor to the empty-error state',
      (tester) async {
        final List<TimeOfDay> times = <TimeOfDay>[];
        await pumpEditor(tester, times);

        await addTime(tester); // 09:00
        await addTime(tester); // 10:00
        expect(times, hasLength(2));

        // Remove 09:00 via its chip's remove button (the ✕ is the only
        // GestureDetector inside the keyed chip).
        final Finder chip09 = find.byKey(const Key('discrete-chip-09:00'));
        final Finder remove09 = find.descendant(
          of: chip09,
          matching: find.byType(GestureDetector),
        );
        await tester.tap(remove09);
        await tester.pumpAndSettle();

        expect(times, <TimeOfDay>[const TimeOfDay(hour: 10, minute: 0)]);
        expect(find.byKey(const Key('discrete-chip-09:00')), findsNothing);
        expect(find.byKey(const Key('discrete-chip-10:00')), findsOneWidget);

        // Remove the last remaining time → editor falls back to empty-error.
        final Finder chip10 = find.byKey(const Key('discrete-chip-10:00'));
        await tester.tap(
          find.descendant(of: chip10, matching: find.byType(GestureDetector)),
        );
        await tester.pumpAndSettle();

        expect(times, isEmpty);
        final AppLocalizations l10n = l10nOf(tester);
        expect(find.text(l10n.discreteTimesErrEmpty), findsOneWidget);
      },
    );
  });
}

// ───────────────────────────────────────────────────────────────────────────
// Harness host.
// ───────────────────────────────────────────────────────────────────────────

/// A minimal stateful host that re-renders the editor on every `onChanged`,
/// faithfully reproducing how the real `_DayCard` / sheet drive the widget.
class _EditorHost extends StatefulWidget {
  const _EditorHost({required this.times});

  final List<TimeOfDay> times;

  @override
  State<_EditorHost> createState() => _EditorHostState();
}

class _EditorHostState extends State<_EditorHost> {
  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return SingleChildScrollView(
      child: DiscreteTimesEditor(
        times: widget.times,
        onChanged: () => setState(() {}),
        strings: _discreteStrings(l10n),
        // Default prefix — chip keys are `discrete-chip-HH:MM`, add key is
        // `discrete-add-time` (the widget falls back to 'discrete' for chips
        // but needs the prefix set for the add key; keep them consistent).
        fieldKeyPrefix: 'discrete',
      ),
    );
  }
}

/// Resolves the editor's localised strings the same way its production hosts do,
/// so the widget renders the exact production copy.
DiscreteTimesEditorStrings _discreteStrings(AppLocalizations l10n) =>
    DiscreteTimesEditorStrings(
      addTimeLabel: l10n.discreteTimesAddTime,
      windowLabel: l10n.discreteTimesWindowLabel,
      removeTimeSemantic: l10n.discreteTimesRemoveSemantic,
      timePickerTitle: l10n.discreteTimesPickerTitle,
      timePickerConfirm: l10n.timePickerConfirm,
      timePickerHoursSemantic: l10n.timePickerHoursSemantic,
      timePickerMinutesSemantic: l10n.timePickerMinutesSemantic,
      errEmpty: l10n.discreteTimesErrEmpty,
      duplicateMessage: l10n.discreteTimesDuplicateMessage,
    );
