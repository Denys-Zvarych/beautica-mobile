// QA — shared [VelvetTopBar] contract tests.
//
// WHY THIS FILE EXISTS
// --------------------
// `VelvetTopBar` is the house header used by every ProfileScaffold /
// SectionScaffold screen and (as of the MyRatingScreen migration) by screens
// converting off a Material `AppBar`. Until now it had NO test of its own —
// it was only ever exercised incidentally through the screens that embed it,
// so the two properties that make it "the house header" (a CENTRED title at
// `VelvetText.subheading()`, a 48 dp strip) were unpinned, and the newly added
// `backKey` parameter had no direct coverage at all.
//
// The `backKey` parameter is additive (defaults to null) and is forwarded to
// the back [NeumorphicIconButton]'s `key`. Three behaviours must hold:
//   1. supplied  → the key lands ON THE TAPPABLE BUTTON (not a wrapper),
//   2. omitted   → the back arrow renders exactly as before, unkeyed,
//   3. onBack null → no arrow at all, and a stray `backKey` must NOT conjure
//      one into existence.
//
// The centring tests are geometric on purpose. A `textAlign: TextAlign.center`
// property assertion would still pass if the title were moved into a `Row`
// beside the back arrow (which is exactly how a centred title silently becomes
// a left-aligned one) — measuring the rendered centre against the bar's own
// centre is the only assertion that actually fails on that regression.

import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/shared/widgets/velvet_top_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

/// Test-local sentinel. Deliberately NOT an l10n string: this file tests the
/// bar's LAYOUT contract, so the title must be a value the test owns (M2 bans
/// localised strings as finders for navigation//screen assertions — a
/// test-owned sentinel is not locale-coupled).
const String _kTitle = 'VTB_TITLE_SENTINEL';

/// The title `Text` inside the bar (scoped, so a same-string label elsewhere in
/// a host screen could never satisfy the finder).
final Finder _titleFinder = find.descendant(
  of: find.byType(VelvetTopBar),
  matching: find.text(_kTitle),
);

/// The fixed-height strip inside the bar's baked-in padding.
final Finder _stripFinder = find.descendant(
  of: find.byType(VelvetTopBar),
  matching: find.byWidgetPredicate(
    (Widget w) => w is SizedBox && w.height == 48,
  ),
);

Future<void> _pump(WidgetTester tester, VelvetTopBar bar) async {
  await tester.pumpApp(
    Scaffold(
      body: SafeArea(child: Column(children: <Widget>[bar])),
    ),
  );
  await tester.pump();
}

void main() {
  // ── backKey — the newly added parameter ───────────────────────────────────

  group('VelvetTopBar — backKey (new parameter)', () {
    const Key backKey = Key('vtb_back_button');

    testWidgets('a supplied backKey lands on the back NeumorphicIconButton', (
      tester,
    ) async {
      await _pump(
        tester,
        VelvetTopBar(title: _kTitle, backKey: backKey, onBack: () {}),
      );

      expect(find.byKey(backKey), findsOneWidget);
      expect(
        tester.widget(find.byKey(backKey)),
        isA<NeumorphicIconButton>(),
        reason:
            'backKey must be forwarded to the NeumorphicIconButton itself — a '
            'key landing on a wrapper (Align/Padding) would still be "found" '
            'by byKey while every tap-by-key assertion silently missed the '
            'button',
      );
    });

    testWidgets('tapping the backKey-keyed widget fires onBack', (
      tester,
    ) async {
      // Proves the key is on the TAPPABLE node, not merely present in the tree.
      var backs = 0;
      await _pump(
        tester,
        VelvetTopBar(title: _kTitle, backKey: backKey, onBack: () => backs++),
      );

      await tester.tap(find.byKey(backKey));
      await tester.pump();

      expect(
        backs,
        1,
        reason:
            'a tap on the keyed back button must invoke onBack exactly once',
      );
    });

    testWidgets('the null default leaves the back arrow rendered but unkeyed', (
      tester,
    ) async {
      // Regression guard for the 5 pre-existing call sites that pass no
      // backKey: the parameter must be purely additive.
      var backs = 0;
      await _pump(tester, VelvetTopBar(title: _kTitle, onBack: () => backs++));

      final Finder button = find.byType(NeumorphicIconButton);
      expect(button, findsOneWidget);
      expect(
        tester.widget<NeumorphicIconButton>(button).key,
        isNull,
        reason:
            'omitting backKey must leave the back button unkeyed — the default '
            'must not synthesise a key that could collide across call sites',
      );

      await tester.tap(button);
      await tester.pump();
      expect(backs, 1, reason: 'the unkeyed back arrow must still fire onBack');
    });

    testWidgets('no back arrow at all when onBack is null', (tester) async {
      await _pump(tester, const VelvetTopBar(title: _kTitle));

      expect(
        find.byType(NeumorphicIconButton),
        findsNothing,
        reason: 'onBack == null must render no back affordance',
      );
      expect(
        _titleFinder,
        findsOneWidget,
        reason: 'the title must still render without a back arrow',
      );
    });

    testWidgets('a backKey with a null onBack conjures no phantom button', (
      tester,
    ) async {
      // The `if (onBack != null)` guard owns the arrow; the key must never be
      // able to resurrect it.
      await _pump(tester, const VelvetTopBar(title: _kTitle, backKey: backKey));

      expect(find.byKey(backKey), findsNothing);
      expect(find.byType(NeumorphicIconButton), findsNothing);
    });
  });

  // ── Centred-title contract ────────────────────────────────────────────────

  group('VelvetTopBar — centred title', () {
    testWidgets('the title is centred in the bar even with a back arrow', (
      tester,
    ) async {
      await _pump(tester, VelvetTopBar(title: _kTitle, onBack: () {}));

      final double titleCentre = tester.getCenter(_titleFinder).dx;
      final double barCentre = tester.getCenter(find.byType(VelvetTopBar)).dx;

      expect(
        titleCentre,
        closeTo(barCentre, 0.5),
        reason:
            'the title must be centred in the 48 dp strip, NOT pushed right by '
            'the back arrow — a Row-based layout would shift it and this is '
            'the assertion that catches it',
      );
    });

    testWidgets('the title stays centred with BOTH a back arrow and trailing', (
      tester,
    ) async {
      // Asymmetric chrome (48 dp arrow left, a narrow trailing right) is the
      // case a Row layout gets visibly wrong.
      await _pump(
        tester,
        VelvetTopBar(
          title: _kTitle,
          onBack: () {},
          trailing: const SizedBox(width: 24, height: 24),
        ),
      );

      final double titleCentre = tester.getCenter(_titleFinder).dx;
      final double barCentre = tester.getCenter(find.byType(VelvetTopBar)).dx;

      expect(titleCentre, closeTo(barCentre, 0.5));
    });

    testWidgets('the bar centre is the screen centre (symmetric lg padding)', (
      tester,
    ) async {
      await _pump(tester, VelvetTopBar(title: _kTitle, onBack: () {}));

      final double screenCentre =
          tester.getSize(find.byType(Scaffold)).width / 2;

      expect(
        tester.getCenter(_titleFinder).dx,
        closeTo(screenCentre, 0.5),
        reason:
            'the bar\'s baked-in horizontal padding is symmetric (lg/lg), so a '
            'bar-centred title is also SCREEN-centred — this is the property '
            'the user actually sees',
      );
    });
  });

  // ── Typography + geometry tokens ──────────────────────────────────────────

  group('VelvetTopBar — house typography and geometry', () {
    testWidgets('the title renders at VelvetText.subheading()', (tester) async {
      await _pump(tester, VelvetTopBar(title: _kTitle, onBack: () {}));

      final TextStyle? style = tester.widget<Text>(_titleFinder).style;

      expect(
        style,
        equals(VelvetText.subheading()),
        reason:
            'the house header title style is VelvetText.subheading() — every '
            'VelvetTopBar screen must read identically',
      );
      expect(
        style,
        isNot(equals(VelvetText.heading18)),
        reason:
            'heading18 is the AppBar-era title style MyRatingScreen migrated '
            'OFF; the bar must never regress to it',
      );
    });

    testWidgets('the strip is exactly 48 dp tall', (tester) async {
      await _pump(tester, VelvetTopBar(title: _kTitle, onBack: () {}));

      expect(_stripFinder, findsOneWidget);
      expect(
        tester.getSize(_stripFinder).height,
        48.0,
        reason: 'the house header is a fixed 48 dp strip',
      );
    });

    testWidgets('the baked-in outer padding is lg / md / lg / xs', (
      tester,
    ) async {
      // Documented as "baked in — never wrap or double-pad". Pinned so a host
      // screen adding its own padding is caught by the screen-level spacing
      // test rather than shipping a drifted header.
      await _pump(tester, VelvetTopBar(title: _kTitle, onBack: () {}));

      final Padding outer = tester.widget<Padding>(
        find
            .descendant(
              of: find.byType(VelvetTopBar),
              matching: find.byType(Padding),
            )
            .first,
      );

      expect(
        outer.padding,
        const EdgeInsets.fromLTRB(
          VelvetSpacing.lg,
          VelvetSpacing.md,
          VelvetSpacing.lg,
          VelvetSpacing.xs,
        ),
      );
    });
  });

  // ── Back-affordance accessibility ─────────────────────────────────────────

  group('VelvetTopBar — back affordance semantics', () {
    testWidgets('backSemanticLabel defaults to «Назад»', (tester) async {
      await _pump(tester, VelvetTopBar(title: _kTitle, onBack: () {}));

      expect(
        tester
            .widget<NeumorphicIconButton>(find.byType(NeumorphicIconButton))
            .semanticLabel,
        'Назад',
        reason:
            'the fallback label keeps the arrow screen-reader-addressable at '
            'call sites that predate the localised label',
      );
    });

    testWidgets('a supplied backSemanticLabel reaches the semantics tree', (
      tester,
    ) async {
      // NOTE: dispose() must be called INSIDE the test body — flutter_test's
      // `_verifySemanticsHandlesWereDisposed` runs before addTearDown callbacks,
      // so `addTearDown(handle.dispose)` fails the test it is meant to clean up.
      final SemanticsHandle handle = tester.ensureSemantics();

      await _pump(
        tester,
        VelvetTopBar(
          title: _kTitle,
          onBack: () {},
          backSemanticLabel: 'Повернутися',
        ),
      );

      expect(
        find.bySemanticsLabel('Повернутися'),
        findsOneWidget,
        reason:
            'the label must reach the real semantics tree (a TalkBack user '
            'hears this), not merely sit on the widget as a field',
      );

      handle.dispose();
    });
  });
}
