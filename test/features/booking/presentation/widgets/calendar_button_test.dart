// QA (track 14.x booking) — press-feel guard for the [CalendarButton] pill
// (change #2).
//
// The pill (the booking-success recap's per-appointment «Додати в календар»
// export) has a tactile depress: an `AnimatedScale` that springs to 0.97 over
// 120 ms `easeOut` while `_pressed`, back to 1.0 on release — mirroring the
// canonical `NeumorphicButton` depress. This suite pins that feedback so a
// refactor cannot silently drop it:
//   • the `AnimatedScale` is configured 0.97 / 120 ms / easeOut and rests at
//     1.0;
//   • a `RepaintBoundary` sits ABOVE it, wrapping the scale rather than sitting
//     under it (see the mechanism in the assertion's `reason:` — an inner
//     boundary caches nothing during the press and widens the dirty region to
//     the enclosing recap card);
//   • a held gesture drives the scale target to 0.97, releasing returns it to
//     1.0 (and fires the `onTap`).
//
// [CalendarButton.buttonKey] and [CalendarButton.semanticsLabel] are REQUIRED
// (N of these coexist on one recap, so neither may fall back to a shared
// default) — hence the fixture key/label below.
//
// LOCALE RE-ENTRY: the glyph + label row is CACHED into a `late Widget
// _content` assigned in `didChangeDependencies`, so the two `setState`s a
// tap fires (`onTapDown`, then EITHER `onTapUp` OR `onTapCancel`) rebuild the
// decoration alone. That cache is the reason `_content`
// is non-`final`: a locale change must REASSIGN it. The last test drives a
// real locale swap over the SAME element (state identity asserted, so the
// case cannot go vacuous by silently remounting a fresh `State`) and pins that
// the label re-renders — no stale copy, no `LateInitializationError`.
//
// Finders are type/key-first. The one place copy is read (the locale test)
// resolves it from `AppLocalizations` at the live locale — never a literal, so
// `forbid_cyrillic_finder` stays satisfied and a copy edit cannot redden it.

import 'package:beautica_mobile/features/booking/presentation/widgets/calendar_button.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../helpers/pump_app.dart';

// Stands in for the per-appointment key/label a real call site supplies.
const Key _kButtonKey = Key('calendar-button-under-test');
const String _kSemanticsLabel = 'add-fixture-service-to-calendar';

void main() {
  Finder scaleOf() => find.descendant(
    of: find.byType(CalendarButton),
    matching: find.byType(AnimatedScale),
  );

  Future<void> pumpButton(
    WidgetTester tester,
    VoidCallback onTap, {
    Locale locale = const Locale('uk'),
  }) async {
    await tester.pumpApp(
      Scaffold(
        body: Center(
          child: CalendarButton(
            buttonKey: _kButtonKey,
            semanticsLabel: _kSemanticsLabel,
            onTap: onTap,
          ),
        ),
      ),
      locale: locale,
    );
    await tester.pumpAndSettle();
  }

  /// The label the pill is CURRENTLY painting (read off the rendered `Text`,
  /// i.e. through the `_content` cache).
  String renderedCta(WidgetTester tester) => tester
      .widget<Text>(
        find.descendant(
          of: find.byType(CalendarButton),
          matching: find.byType(Text),
        ),
      )
      .data!;

  /// The label the pill SHOULD be painting at the live locale.
  String expectedCta(WidgetTester tester) => AppLocalizations.of(
    tester.element(find.byType(CalendarButton)),
  ).bookingSuccessAddCalendarCta;

  testWidgets(
    'the AnimatedScale drives the depress (0.97 / 120ms / easeOut), rests at '
    '1.0, and is wrapped by a RepaintBoundary ABOVE the transform',
    (tester) async {
      await pumpButton(tester, () {});

      final AnimatedScale rest = tester.widget<AnimatedScale>(scaleOf());
      expect(rest.scale, 1.0, reason: 'un-pressed → full size');
      expect(rest.duration, const Duration(milliseconds: 120));
      expect(rest.curve, Curves.easeOut);

      // The boundary must be an ANCESTOR of the scale, and there must be none
      // beneath it.
      expect(
        find.descendant(of: scaleOf(), matching: find.byType(RepaintBoundary)),
        findsNothing,
        reason:
            'RepaintBoundary must NOT sit under the AnimatedScale. '
            'RenderTransform is not itself a repaint boundary, so its per-frame '
            'markNeedsPaint walks to the nearest ANCESTOR boundary: a boundary '
            'below the transform pushes that walk out to the scaffold\'s '
            'per-card _reveal boundary, re-recording the WHOLE recap card each '
            'frame of the press. It also caches nothing (the AnimatedContainer '
            'lerps its boxShadow over 150ms — longer than the 120ms scale — so '
            'the child is dirty every frame) and flips '
            'RenderTransform.needsCompositing, allocating a permanent '
            'TransformLayer per button. Do not "tidy" it back inside.',
      );
      // …and the pill's own single boundary is that ancestor, so press
      // repaints are still isolated from sibling cards.
      final Finder ownBoundary = find.descendant(
        of: find.byType(CalendarButton),
        matching: find.byType(RepaintBoundary),
      );
      expect(ownBoundary, findsOneWidget);
      expect(
        find.ancestor(of: scaleOf(), matching: ownBoundary),
        findsOneWidget,
        reason: 'the pill\'s RepaintBoundary must WRAP the AnimatedScale',
      );
    },
  );

  testWidgets(
    'the pill renders the Symbols.calendar_add_on_rounded glyph (calendar + «+»)',
    (tester) async {
      // GLYPH GUARD (track 14.x): the leading icon must be the material_symbols
      // «calendar_add_on» rounded-cut glyph — NOT the plain
      // `Icons.calendar_today_rounded` it replaced. Pins the material_symbols
      // wiring and guards against an accidental revert to the bare calendar.
      await pumpButton(tester, () {});

      expect(
        find.descendant(
          of: find.byType(CalendarButton),
          matching: find.byIcon(Symbols.calendar_add_on_rounded),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'holding the button drives the scale target to 0.97; releasing returns it '
    'to 1.0 and fires onTap',
    (tester) async {
      int taps = 0;
      await pumpButton(tester, () => taps++);

      // Press and HOLD — onTapDown flips `_pressed`, so the AnimatedScale
      // target becomes 0.97. Gesture lands on the KEYED tappable, not on
      // `CalendarButton` itself: the widget is an `Align` that fills its
      // parent, so its centre is not on the right-aligned pill.
      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_kButtonKey)),
      );
      await tester.pump(); // let the tap-down fire + rebuild
      expect(
        tester.widget<AnimatedScale>(scaleOf()).scale,
        0.97,
        reason: 'held → depressed to 0.97',
      );
      expect(taps, 0, reason: 'onTap fires on release, not on press');

      // Release — `_pressed` clears (target back to 1.0) and onTap fires.
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        tester.widget<AnimatedScale>(scaleOf()).scale,
        1.0,
        reason: 'released → springs back to full size',
      );
      expect(taps, 1, reason: 'releasing fired onTap once');
    },
  );

  testWidgets(
    'a LOCALE change re-renders the cached label on the SAME State — the '
    '`late _content` is reassigned, never left stale or uninitialised',
    (tester) async {
      // WHY THIS IS NOT COVERED BY THE OTHER CASES: `_content` is built ONCE
      // per dependency change and handed to the AnimatedContainer as its
      // `child`, so `build` never re-reads `AppLocalizations`. A locale swap
      // therefore reaches the label through exactly ONE route — the
      // `didChangeDependencies` reassignment. Break that (make `_content`
      // `final`, or move the assignment into `initState` where
      // `AppLocalizations.of(context)` is not yet safe) and the pill silently
      // keeps painting the previous locale's copy, or throws
      // LateInitializationError on first build. Neither shows up in a
      // single-locale suite.
      await pumpButton(tester, () {});

      final State before = tester.state(find.byType(CalendarButton));
      final String ukLabel = renderedCta(tester);
      expect(ukLabel, expectedCta(tester));

      // Re-pump the SAME tree under a different locale. The widget types and
      // keys are unchanged, so Flutter REUSES the element — which is what
      // makes this a dependency change rather than a remount.
      await pumpButton(tester, () {}, locale: const Locale('en'));

      expect(
        identical(tester.state(find.byType(CalendarButton)), before),
        isTrue,
        reason:
            'the element must be REUSED — a remount would rebuild _content '
            'from scratch and make this case vacuous',
      );
      expect(tester.takeException(), isNull);

      final String enLabel = renderedCta(tester);
      expect(
        enLabel,
        expectedCta(tester),
        reason: 'the cached content must be reassigned for the new locale',
      );
      expect(
        enLabel,
        isNot(ukLabel),
        reason:
            'uk and en CTAs differ — if they were equal this test could pass '
            'against a stale cache',
      );

      // The glyph survived the rebuild (the cache is rebuilt whole, not
      // patched).
      expect(
        find.descendant(
          of: find.byType(CalendarButton),
          matching: find.byIcon(Symbols.calendar_add_on_rounded),
        ),
        findsOneWidget,
      );
    },
  );
}
