// Phase 15.5 — Structural widget tests for [PeriodRangePicker].
//
// Pins the two behaviours the apply flow depends on:
//   • past days (before `firstSelectableDay`) are non-tappable — tapping one
//     does NOT begin a selection, so the «Зберегти» CTA stays inert;
//   • tapping a start day then an end day, then «Зберегти», pops the expected
//     `DateTimeRange` via the go_router `context.pop` extension.
//
// Finders use `Key`s for the chrome (the save / back buttons) and the day
// `Semantics` label for the calendar cells (the cells carry no per-day Key);
// waits use `pumpAndSettle` (M6). The picker is pumped inside a GoRouter so its
// `context.pop(range)` resolves (M2/M6 compliant, hermetic — no providers).

import 'package:beautica_mobile/features/schedule/presentation/period_range_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Whether the save CTA's CLOSEST `IgnorePointer` ancestor is inert. The picker
/// nests the save button in `Opacity > IgnorePointer > NeumorphicButton`, so the
/// first ancestor match is the gate we care about.
bool _saveCtaIgnoring(WidgetTester tester) {
  final ignore = tester
      .widgetList<IgnorePointer>(
        find.ancestor(
          of: find.byKey(const Key('btn-range-picker-save')),
          matching: find.byType(IgnorePointer),
        ),
      )
      .first;
  return ignore.ignoring;
}

const _strings = PeriodRangePickerStrings(
  title: 'Виберіть період',
  emptyHint: 'Оберіть період',
  saveLabel: 'Зберегти',
  backSemantic: 'Назад',
  weekdayShort: <String>['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Нд'],
);

void main() {
  // Anchor the picker on June 2024; first selectable day = 10 Jun 2024, so
  // 1–9 Jun are past (frozen) and 10 Jun onward is tappable.
  final firstMonth = DateTime(2024, 6);
  final firstSelectable = DateTime(2024, 6, 10);

  /// Pumps the picker; the popped range is captured into [popped].
  Future<void> pumpPicker(
    WidgetTester tester, {
    required void Function(DateTimeRange?) onPopped,
  }) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  key: const Key('open-picker'),
                  onPressed: () async {
                    final range = await showModalBottomSheet<DateTimeRange>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => SizedBox(
                        height: 700,
                        child: PeriodRangePicker(
                          firstMonth: firstMonth,
                          firstSelectableDay: firstSelectable,
                          strings: _strings,
                        ),
                      ),
                    );
                    onPopped(range);
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-picker')));
    await tester.pumpAndSettle();
  }

  /// Finds the tappable day cell for [day] in the FIRST rendered month (the
  /// anchor month) by matching the day-number `Text` — scoped to the first
  /// match so later months' identical numbers don't collide. The `Text` sits
  /// inside the cell's `GestureDetector`, so tapping its centre hits the
  /// tap target.
  Finder dayCell(int day) => find
      .descendant(
        of: find.byType(PeriodRangePicker),
        matching: find.text('$day'),
      )
      .first;

  testWidgets('a past day is non-tappable — tapping it does not start a '
      'selection and the save CTA stays inert', (tester) async {
    DateTimeRange? popped;
    var popInvoked = false;
    await pumpPicker(
      tester,
      onPopped: (r) {
        popped = r;
        popInvoked = true;
      },
    );

    // 5 Jun 2024 is before the first selectable day (10 Jun) → frozen.
    await tester.tap(dayCell(5), warnIfMissed: false);
    await tester.pumpAndSettle();

    // No selection began → the save CTA is wrapped in an inert IgnorePointer.
    expect(_saveCtaIgnoring(tester), isTrue);

    // Tapping the inert save CTA does nothing — the sheet has not popped.
    await tester.tap(
      find.byKey(const Key('btn-range-picker-save')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(popInvoked, isFalse);
    expect(popped, isNull);
  });

  testWidgets('tapping a start then an end day, then Зберегти, pops the '
      'expected DateTimeRange', (tester) async {
    DateTimeRange? popped;
    await pumpPicker(tester, onPopped: (r) => popped = r);

    // Start 12 Jun, end 20 Jun (both within the anchor month, both selectable).
    await tester.tap(dayCell(12));
    await tester.pumpAndSettle();
    await tester.tap(dayCell(20));
    await tester.pumpAndSettle();

    // The CTA is now active.
    expect(_saveCtaIgnoring(tester), isFalse);

    await tester.tap(find.byKey(const Key('btn-range-picker-save')));
    await tester.pumpAndSettle();

    expect(popped, isNotNull);
    expect(popped!.start, DateTime(2024, 6, 12));
    expect(popped!.end, DateTime(2024, 6, 20));
  });
}
