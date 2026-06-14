// Phase 15.x / 6.2 — Widget tests for the VelvetTouch wheel time picker
// (`showVelvetTimePicker`).
//
// This surface deliberately REPLACES Flutter's Material `showTimePicker` clock
// dial with two `ListWheelScrollView` wheels (hours 00–23; minutes 00–59 at
// 1-minute granularity — NO snapping). These tests pin the contract the
// working-hours screen and the schedule editors rely on:
//   • opens as a modal bottom sheet with the caller's title + confirm label
//   • the Material clock dial is GONE; the wheels ARE `ListWheelScrollView`
//   • seeds from `initial` and returns the EXACT seeded minute (any 0–59)
//   • scrolling a wheel then confirming returns the changed value (no setState
//     regression — `_hour`/`_minute` are read fresh at confirm)
//   • barrier dismiss resolves to `null`
//   • 24-hour wheel: hours 00–23, minutes every minute 00–59
//
// All finders key off widget Keys / types — never localised strings — so the
// tests survive copy + locale changes (mobile-qa M2).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beautica_mobile/features/schedule/presentation/widgets/velvet_time_picker.dart';

const Key _openButtonKey = Key('test-open-velvet-time-picker');
const Key _confirmKey = Key('btn-velvet-time-picker-confirm');

/// Pumps a minimal host with a single button that opens the picker seeded from
/// [initial], capturing the resolved value into [onResult]. Keeps every test
/// body short and focused on the act/assert (mobile-qa: harness extraction).
Future<void> _pumpPicker(
  WidgetTester tester, {
  required TimeOfDay initial,
  required ValueChanged<TimeOfDay?> onResult,
  String title = 'Pick a time',
  String confirmLabel = 'Confirm',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => Center(
            child: ElevatedButton(
              key: _openButtonKey,
              onPressed: () async {
                final TimeOfDay? result = await showVelvetTimePicker(
                  context,
                  initial,
                  title: title,
                  confirmLabel: confirmLabel,
                  hoursSemanticLabel: 'Hours',
                  minutesSemanticLabel: 'Minutes',
                );
                onResult(result);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.byKey(_openButtonKey));
  await tester.pumpAndSettle();
}

void main() {
  group('showVelvetTimePicker — sheet & dial', () {
    testWidgets('opens as a modal sheet with the passed title and confirm '
        'label, and renders no Material clock dial', (
      WidgetTester tester,
    ) async {
      await _pumpPicker(
        tester,
        initial: const TimeOfDay(hour: 9, minute: 30),
        onResult: (_) {},
        title: 'Start time',
        confirmLabel: 'Save',
      );

      // Sheet is shown via the framework's modal bottom sheet route.
      expect(find.byType(BottomSheet), findsOneWidget);

      // Caller copy is rendered verbatim (passed in, not localised here).
      expect(find.text('Start time'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);

      // Two scroll wheels — hours and minutes.
      expect(find.byType(ListWheelScrollView), findsNWidgets(2));

      // The Material clock dial is gone — no TimePicker route was used, so no
      // Material `Dialog` (the dial is hosted in a Dialog, the wheel in a
      // BottomSheet) and no AM/PM toggle copy is present.
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('AM'), findsNothing);
      expect(find.text('PM'), findsNothing);
    });
  });

  group('showVelvetTimePicker — seeding', () {
    testWidgets('seeds wheels from initial; confirming without scrolling '
        'returns the exact initial value', (WidgetTester tester) async {
      TimeOfDay? result;
      await _pumpPicker(
        tester,
        initial: const TimeOfDay(hour: 9, minute: 30),
        onResult: (TimeOfDay? r) => result = r,
      );

      await tester.tap(find.byKey(_confirmKey));
      await tester.pumpAndSettle();

      expect(result, const TimeOfDay(hour: 9, minute: 30));
    });

    testWidgets('seeds the exact initial minute — no snapping (09:37 stays '
        '09:37)', (WidgetTester tester) async {
      // 1-minute granularity: `_minute` is seeded directly from
      // `widget.initial.minute` with NO snapping. A non-quarter minute (37)
      // round-trips verbatim when the user confirms without scrolling.
      TimeOfDay? result;
      await _pumpPicker(
        tester,
        initial: const TimeOfDay(hour: 9, minute: 37),
        onResult: (TimeOfDay? r) => result = r,
      );

      await tester.tap(find.byKey(_confirmKey));
      await tester.pumpAndSettle();

      expect(result, const TimeOfDay(hour: 9, minute: 37));
    });

    testWidgets('minute wheel offers every minute — seeding :07 round-trips to '
        ':07', (WidgetTester tester) async {
      // Positive regression guard for the 1-minute-granularity feature: a
      // single-digit non-quarter minute (07) is preserved exactly. Under the
      // old [0,15,30,45] snapping this would have collapsed to :00.
      TimeOfDay? result;
      await _pumpPicker(
        tester,
        initial: const TimeOfDay(hour: 14, minute: 7),
        onResult: (TimeOfDay? r) => result = r,
      );

      await tester.tap(find.byKey(_confirmKey));
      await tester.pumpAndSettle();

      expect(result, const TimeOfDay(hour: 14, minute: 7));
    });
  });

  group('showVelvetTimePicker — scrolling', () {
    testWidgets('scrolling the hours wheel then confirming returns the '
        'changed hour (no setState-read regression)', (
      WidgetTester tester,
    ) async {
      TimeOfDay? result;
      await _pumpPicker(
        tester,
        initial: const TimeOfDay(hour: 9, minute: 30),
        onResult: (TimeOfDay? r) => result = r,
      );

      // The hours wheel is the first ListWheelScrollView in the row.
      final Finder hoursWheel = find.byType(ListWheelScrollView).first;

      // Drag up by exactly two item extents (46px each) → advance 2 hours
      // (09 → 11). FixedExtentScrollPhysics snaps to the nearest item.
      await tester.drag(hoursWheel, const Offset(0, -92));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_confirmKey));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      // Minute is unchanged; hour advanced from the scroll. Guards the perf
      // fix: _hour is read fresh at confirm even though scroll never setState's.
      expect(result!.minute, 30);
      expect(result!.hour, greaterThan(9));
    });

    testWidgets('scrolling the minutes wheel then confirming returns the '
        'changed minute', (WidgetTester tester) async {
      TimeOfDay? result;
      await _pumpPicker(
        tester,
        initial: const TimeOfDay(hour: 9, minute: 0),
        onResult: (TimeOfDay? r) => result = r,
      );

      final Finder minutesWheel = find.byType(ListWheelScrollView).last;

      // Each item extent is 46px and the wheel now lists every minute, so
      // dragging up by N item-extents advances exactly N minutes. Drag by 7
      // extents (00 → 07) — a deliberate non-multiple-of-15 to prove 1-minute
      // granularity (the old wheel could never land here).
      await tester.drag(minutesWheel, const Offset(0, -46.0 * 7));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_confirmKey));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.hour, 9);
      // Exact resulting minute — not a quarter step.
      expect(result!.minute, greaterThan(0));
      expect(result!.minute, 7);
    });
  });

  group('showVelvetTimePicker — dismissal', () {
    testWidgets('tapping the barrier dismisses with null (no value)', (
      WidgetTester tester,
    ) async {
      bool called = false;
      TimeOfDay? result;
      await _pumpPicker(
        tester,
        initial: const TimeOfDay(hour: 9, minute: 30),
        onResult: (TimeOfDay? r) {
          called = true;
          result = r;
        },
      );

      // Tap top-left, well above the sheet, to hit the modal barrier.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsNothing);
      expect(called, isTrue);
      expect(result, isNull);
    });
  });

  group('showVelvetTimePicker — 24-hour invariants', () {
    testWidgets('hours wheel exposes 00..23 (24-hour, no AM/PM) and minutes '
        'every minute 00..59', (WidgetTester tester) async {
      await _pumpPicker(
        tester,
        initial: const TimeOfDay(hour: 0, minute: 0),
        onResult: (_) {},
      );

      // No AM/PM affordance anywhere.
      expect(find.text('AM'), findsNothing);
      expect(find.text('PM'), findsNothing);

      // Seeded at 00:00 — the centre band shows 00 for both wheels, with
      // exactly one ':' separator between the two wheels.
      expect(find.text(':'), findsOneWidget);

      // The minutes wheel exposes a full minute per index (60 children), not a
      // 4-entry quarter list. Read the child count off the build delegate to
      // pin 1-minute granularity structurally.
      final ListWheelScrollView minutesWheel = tester
          .widget<ListWheelScrollView>(find.byType(ListWheelScrollView).last);
      final ListWheelChildBuilderDelegate minutesDelegate =
          minutesWheel.childDelegate as ListWheelChildBuilderDelegate;
      expect(minutesDelegate.childCount, 60);

      // And an arbitrary non-quarter minute (59, the maximum) round-trips
      // untouched alongside the maximum hour — proving the full 24×60 range.
      await tester.tapAt(const Offset(10, 10)); // dismiss current sheet
      await tester.pumpAndSettle();

      TimeOfDay? result;
      await _pumpPicker(
        tester,
        initial: const TimeOfDay(hour: 23, minute: 59),
        onResult: (TimeOfDay? r) => result = r,
      );
      await tester.tap(find.byKey(_confirmKey));
      await tester.pumpAndSettle();

      // 23:59 round-trips untouched → both wheel extremes are valid.
      expect(result, const TimeOfDay(hour: 23, minute: 59));
    });
  });
}
