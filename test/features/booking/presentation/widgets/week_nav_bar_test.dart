// Phase 484 — WeekNavBar: title copy (same- / cross-month / cross-year),
// relative line + «Сьогодні» only off-week, callbacks, and the 360 dp ×1.3
// layout (title never truncated, relative line never clipped next to the
// chip — the preview elided «Наступний…» there).
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/week_nav_bar.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

// future-date-ok: pinned calendar fixtures for pure label formatting.
final DateTime _nov16 = DateTime(2026, 11, 16);
// future-date-ok: pinned calendar fixtures for pure label formatting.
final DateTime _oct26 = DateTime(2026, 10, 26);
// future-date-ok: pinned calendar fixtures for pure label formatting.
final DateTime _dec28 = DateTime(2026, 12, 28);

class _Calls {
  final List<bool> view = <bool>[];
  int month = 0;
  int today = 0;
  int prev = 0;
  int next = 0;
}

Widget _bar(
  _Calls calls, {
  DateTime? weekStart,
  int weekOffset = 0,
  bool threeDays = true,
}) => Padding(
  // The host's insets (preview screen: lg left, md right).
  padding: const EdgeInsets.fromLTRB(24, 8, 16, 4),
  child: Align(
    alignment: Alignment.topCenter,
    child: WeekNavBar(
      weekStart: weekStart ?? _nov16,
      weekOffset: weekOffset,
      threeDays: threeDays,
      monthOpen: false,
      onToggleView: calls.view.add,
      onToggleMonth: () => calls.month++,
      onToday: () => calls.today++,
      onPrevWeek: () => calls.prev++,
      onNextWeek: () => calls.next++,
    ),
  ),
);

void main() {
  group('weekTitleLabel', () {
    test('same month — «16–22 листопада»', () {
      expect(weekTitleLabel(_nov16), '16–22 листопада');
    });

    test('cross month — CLDR short genitive on both ends', () {
      expect(weekTitleLabel(_oct26), '26 жовт. – 1 листоп.');
    });

    test('cross year', () {
      expect(weekTitleLabel(_dec28), '28 груд. – 3 січ.');
    });
  });

  group('relativeWeekLabel', () {
    final AppLocalizations l10n = lookupAppLocalizations(const Locale('uk'));

    test('this / next / previous week', () {
      expect(relativeWeekLabel(l10n, 0), 'Цей тиждень');
      expect(relativeWeekLabel(l10n, 1), 'Наступний тиждень');
      expect(relativeWeekLabel(l10n, -1), 'Минулий тиждень');
    });

    test('Ukrainian plural ahead and back', () {
      expect(relativeWeekLabel(l10n, 2), 'Через 2 тижні');
      expect(relativeWeekLabel(l10n, 5), 'Через 5 тижнів');
      expect(relativeWeekLabel(l10n, 21), 'Через 21 тиждень');
      expect(relativeWeekLabel(l10n, -3), '3 тижні тому');
      expect(relativeWeekLabel(l10n, -12), '12 тижнів тому');
    });

    test('plural forms 2 / 5 / 21 / 22 in both directions', () {
      expect(relativeWeekLabel(l10n, 22), 'Через 22 тижні');
      expect(relativeWeekLabel(l10n, -2), '2 тижні тому');
      expect(relativeWeekLabel(l10n, -5), '5 тижнів тому');
      expect(relativeWeekLabel(l10n, -22), '22 тижні тому');
    });

    // `relativeDateWeeksAgo` has `=1` but no `one` branch, so CLDR "one"
    // numbers above 1 (21, 31, …) fall to `other` → «21 тижнів тому».
    // Reachable since phase 484: ‹ steps back without limit.
    test('21 weeks back is «21 тиждень тому» (CLDR one)', () {
      expect(relativeWeekLabel(l10n, 21), 'Через 21 тиждень');
      expect(relativeWeekLabel(l10n, -21), '21 тиждень тому');
    });
  });

  group('weekTitleLabel edges', () {
    test('DST week (Kyiv clocks back Sun 25 Oct) — «19–25 жовтня»', () {
      // future-date-ok: pinned calendar fixture for pure label formatting.
      expect(weekTitleLabel(DateTime(2026, 10, 19)), '19–25 жовтня');
    });

    test('week ending on the month end stays same-month', () {
      // future-date-ok: pinned calendar fixture for pure label formatting.
      expect(weekTitleLabel(DateTime(2026, 11, 23)), '23–29 листопада');
    });
  });

  testWidgets('relative line renders the label for the shown offset', (
    tester,
  ) async {
    final AppLocalizations l10n = lookupAppLocalizations(const Locale('uk'));
    for (final int offset in <int>[0, 1, -1, 3, -4]) {
      await tester.pumpApp(_bar(_Calls(), weekOffset: offset));
      expect(
        tester.widget<Text>(find.byKey(WeekNavBar.relativeKey)).data,
        relativeWeekLabel(l10n, offset),
      );
    }
  });

  testWidgets('«Сьогодні» chip on past and far weeks; its label and tap', (
    tester,
  ) async {
    final AppLocalizations l10n = lookupAppLocalizations(const Locale('uk'));
    for (final int offset in <int>[-1, -3, 2]) {
      final _Calls calls = _Calls();
      await tester.pumpApp(_bar(calls, weekOffset: offset));
      final Finder chip = find.byKey(WeekNavBar.todayKey);
      expect(chip, findsOneWidget);
      expect(
        find
            .descendant(of: chip, matching: find.byType(Text))
            .evaluate()
            .map((Element e) => (e.widget as Text).data),
        <String>[l10n.scheduleTodayAction],
      );
      await tester.tap(chip);
      expect((calls.today, calls.month, calls.prev, calls.next), (1, 0, 0, 0));
      expect(calls.view, isEmpty);
    }
  });

  group('title = month toggle', () {
    Widget bar(_Calls calls, {required bool monthOpen}) => Align(
      alignment: Alignment.topLeft,
      child: WeekNavBar(
        weekStart: _nov16,
        weekOffset: 0,
        threeDays: true,
        monthOpen: monthOpen,
        onToggleView: calls.view.add,
        onToggleMonth: () => calls.month++,
        onToday: () => calls.today++,
        onPrevWeek: () => calls.prev++,
        onNextWeek: () => calls.next++,
      ),
    );

    double chevronTurns(WidgetTester tester) => tester
        .widget<AnimatedRotation>(
          find.descendant(
            of: find.byKey(WeekNavBar.titleKey),
            matching: find.byType(AnimatedRotation),
          ),
        )
        .turns;

    testWidgets('chevron + a11y expanded follow monthOpen; tap fires only '
        'onToggleMonth, once per tap (the bar owns no open state)', (
      tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      final _Calls calls = _Calls();
      await tester.pumpApp(bar(calls, monthOpen: false));
      expect(chevronTurns(tester), 0);
      expect(
        tester.getSemantics(find.byKey(WeekNavBar.titleKey)),
        isSemantics(isButton: true, hasExpandedState: true, isExpanded: false),
      );

      await tester.tap(find.byKey(WeekNavBar.titleKey));
      await tester.pumpAndSettle();
      // The host has not answered yet: the bar must not flip on its own.
      expect(calls.month, 1);
      expect(chevronTurns(tester), 0);

      // Host answers with monthOpen: true — no callback echoes back.
      await tester.pumpApp(bar(calls, monthOpen: true));
      await tester.pumpAndSettle();
      expect(chevronTurns(tester), 0.5);
      expect(
        tester.getSemantics(find.byKey(WeekNavBar.titleKey)),
        isSemantics(isButton: true, hasExpandedState: true, isExpanded: true),
      );
      expect(calls.month, 1);

      await tester.tap(find.byKey(WeekNavBar.titleKey));
      expect((calls.month, calls.today, calls.prev, calls.next), (2, 0, 0, 0));
      expect(calls.view, isEmpty);
      semantics.dispose();
    });

    testWidgets('a slow drag on the title steps no week', (tester) async {
      final _Calls calls = _Calls();
      await tester.pumpApp(bar(calls, monthOpen: false));
      final TestGesture g = await tester.startGesture(
        tester.getCenter(find.byKey(WeekNavBar.titleKey)),
      );
      Duration stamp = Duration.zero;
      // 4 dp per 20 ms = 200 dp/s: a real fling to the recogniser (over
      // kMinFlingVelocity and the slop within the velocity horizon) but under
      // the 250 dp/s week-step threshold.
      for (int i = 0; i < 20; i++) {
        stamp += const Duration(milliseconds: 20);
        await g.moveBy(const Offset(-4, 0), timeStamp: stamp);
      }
      await g.up(timeStamp: stamp);
      await tester.pumpAndSettle();
      expect((calls.prev, calls.next, calls.month), (0, 0, 0));
    });
  });

  group('ViewModeToggle', () {
    Matcher selected(bool on) =>
        isSemantics(isButton: true, hasSelectedState: true, isSelected: on);

    double thumbLeft(WidgetTester tester) => tester
        .widget<AnimatedPositioned>(find.byType(AnimatedPositioned))
        .left!;

    testWidgets('active segment follows threeDays (a11y selected + thumb)', (
      tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      final List<bool> calls = <bool>[];
      await tester.pumpApp(
        Center(child: ViewModeToggle(threeDays: true, onChanged: calls.add)),
      );
      expect(
        tester.getSemantics(find.byKey(ViewModeToggle.threeDaysKey)),
        selected(true),
      );
      expect(
        tester.getSemantics(find.byKey(ViewModeToggle.dayKey)),
        selected(false),
      );
      final double threeLeft = thumbLeft(tester);

      await tester.pumpApp(
        Center(child: ViewModeToggle(threeDays: false, onChanged: calls.add)),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.byKey(ViewModeToggle.dayKey)),
        selected(true),
      );
      expect(
        tester.getSemantics(find.byKey(ViewModeToggle.threeDaysKey)),
        selected(false),
      );
      expect(thumbLeft(tester), lessThan(threeLeft));
      // Rendering alone never reports a change.
      expect(calls, isEmpty);
      semantics.dispose();
    });

    testWidgets('360 dp ×1.3: both labels whole inside their segments', (
      tester,
    ) async {
      await tester.pumpApp(
        Center(child: ViewModeToggle(threeDays: true, onChanged: (_) {})),
        width: 360,
        textScaleFactor: 1.3,
      );
      for (final Key key in <Key>[
        ViewModeToggle.dayKey,
        ViewModeToggle.threeDaysKey,
      ]) {
        final Finder label = find.descendant(
          of: find.byKey(key),
          matching: find.byType(Text),
        );
        final RenderParagraph p = tester.renderObject<RenderParagraph>(label);
        expect(p.didExceedMaxLines, isFalse);
        expect(p.size.width, greaterThanOrEqualTo(p.getMaxIntrinsicWidth(0)));
        final Rect seg = tester.getRect(find.byKey(key));
        final Rect text = tester.getRect(label);
        expect(text.left, greaterThanOrEqualTo(seg.left));
        expect(text.right, lessThanOrEqualTo(seg.right));
      }
    });
  });

  // The toggle track's inset ring never animates, so it must not pay for
  // an animated ring layer.
  testWidgets('toggle track NeumorphicInset has animatedRing: false', (
    tester,
  ) async {
    await tester.pumpApp(
      Center(child: ViewModeToggle(threeDays: true, onChanged: (_) {})),
    );
    final NeumorphicInset track = tester.widget<NeumorphicInset>(
      find.descendant(
        of: find.byType(ViewModeToggle),
        matching: find.byType(NeumorphicInset),
      ),
    );
    expect(track.animatedRing, isFalse);
  });

  testWidgets('«Сьогодні» chip only off the current week', (tester) async {
    final _Calls calls = _Calls();
    await tester.pumpApp(_bar(calls));
    expect(find.byKey(WeekNavBar.todayKey), findsNothing);

    await tester.pumpApp(_bar(calls, weekOffset: 1));
    expect(find.byKey(WeekNavBar.todayKey), findsOneWidget);
    await tester.tap(find.byKey(WeekNavBar.todayKey));
    expect(calls.today, 1);
  });

  testWidgets('toggle, title tap and title swipe reach their callbacks', (
    tester,
  ) async {
    final _Calls calls = _Calls();
    await tester.pumpApp(_bar(calls));

    await tester.tap(find.byKey(ViewModeToggle.dayKey));
    await tester.tap(find.byKey(ViewModeToggle.threeDaysKey));
    expect(calls.view, <bool>[false, true]);

    await tester.tap(find.byKey(WeekNavBar.titleKey));
    expect(calls.month, 1);

    await tester.fling(
      find.byKey(WeekNavBar.titleKey),
      const Offset(-120, 0),
      800,
    );
    await tester.pumpAndSettle();
    expect(calls.next, 1);
    await tester.fling(
      find.byKey(WeekNavBar.titleKey),
      const Offset(120, 0),
      800,
    );
    await tester.pumpAndSettle();
    expect(calls.prev, 1);
    // A swipe is not a tap.
    expect(calls.month, 1);
  });

  group('360 dp at text scale 1.3', () {
    Future<void> pump(WidgetTester tester, DateTime weekStart) =>
        tester.pumpApp(
          _bar(_Calls(), weekStart: weekStart, weekOffset: 1),
          width: 360,
          textScaleFactor: 1.3,
        );

    for (final DateTime week in <DateTime>[_nov16, _oct26, _dec28]) {
      testWidgets('title ${weekTitleLabel(week)} is whole and fits', (
        tester,
      ) async {
        await pump(tester, week);
        final Finder title = find.descendant(
          of: find.byKey(WeekNavBar.titleKey),
          matching: find.byType(Text),
        );
        final Text text = tester.widget<Text>(title);
        expect(text.data, weekTitleLabel(week));
        expect(text.overflow, isNot(TextOverflow.ellipsis));
        final RenderParagraph p = tester.renderObject<RenderParagraph>(title);
        expect(p.didExceedMaxLines, isFalse);
        // Painted inside the title's slot, left of the toggle.
        final Rect titleRect = tester.getRect(title);
        expect(
          titleRect.right,
          lessThanOrEqualTo(
            tester.getRect(find.byType(ViewModeToggle)).left + 0.5,
          ),
        );
      });
    }

    testWidgets('relative line + chip: nothing clipped', (tester) async {
      await pump(tester, _nov16);
      final RenderParagraph p = tester.renderObject<RenderParagraph>(
        find.byKey(WeekNavBar.relativeKey),
      );
      expect(p.didExceedMaxLines, isFalse);
      expect(p.size.width, greaterThanOrEqualTo(p.getMaxIntrinsicWidth(0)));
      final Rect toggle = tester.getRect(find.byType(ViewModeToggle));
      expect(
        tester.getRect(find.byKey(WeekNavBar.relativeKey)).right,
        lessThanOrEqualTo(toggle.left),
      );
      expect(
        tester.getRect(find.byKey(WeekNavBar.todayKey)).right,
        lessThanOrEqualTo(toggle.left),
      );
    });
  });
}
