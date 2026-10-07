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
import 'package:beautica_mobile/shared/widgets/notification_bell_button.dart';
import 'package:beautica_mobile/shared/widgets/velvet_top_bar.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

/// Test-local sentinel. Deliberately NOT an l10n string: this file tests the
/// bar's LAYOUT contract, so the title must be a value the test owns (M2 bans
/// localised strings as finders for navigation//screen assertions — a
/// test-owned sentinel is not locale-coupled).
// Test-supplied label passed INTO the widget under test — not l10n copy.
const String _kBackLabel = 'Салон';

const String _kBackSemantics = 'Повернутися до салону';

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

  // ── titleWidget (new parameter) ───────────────────────────────────────────
  //
  // Added for MyRatingScreen's "beautica" wordmark (branch-root parity). Must
  // be purely additive: the default (null) renders EXACTLY the pre-existing
  // `Text(title, style: VelvetText.subheading())` in the same centred slot —
  // pinned by the two groups above, which never pass `titleWidget` and must
  // keep passing unmodified.

  group('VelvetTopBar — titleWidget (new parameter)', () {
    testWidgets('omitted → falls back to Text(title) exactly as before', (
      tester,
    ) async {
      await _pump(tester, VelvetTopBar(title: _kTitle, onBack: () {}));

      expect(
        _titleFinder,
        findsOneWidget,
        reason:
            'the default-null titleWidget must not disturb the existing '
            'Text(title) rendering pinned by the groups above',
      );
    });

    testWidgets(
      'supplied → renders in the centred slot INSTEAD of Text(title)',
      (tester) async {
        const Key wordmarkKey = Key('vtb_titleWidget_sentinel');
        await _pump(
          tester,
          VelvetTopBar(
            title: _kTitle,
            onBack: () {},
            titleWidget: const Text('beautica', key: wordmarkKey),
          ),
        );

        expect(
          find.byKey(wordmarkKey),
          findsOneWidget,
          reason: 'titleWidget must render in the bar\'s centred title slot',
        );
        expect(
          _titleFinder,
          findsNothing,
          reason:
              'when titleWidget is supplied, the default Text(title) must NOT '
              'also render — title stops being a visible node, not merely '
              'shadowed by an overlay',
        );
      },
    );

    testWidgets('supplied → titleWidget stays centred like the default title', (
      tester,
    ) async {
      const Key wordmarkKey = Key('vtb_titleWidget_centred_sentinel');
      await _pump(
        tester,
        VelvetTopBar(
          title: _kTitle,
          onBack: () {},
          titleWidget: const Text('beautica', key: wordmarkKey),
        ),
      );

      final double titleCentre = tester.getCenter(find.byKey(wordmarkKey)).dx;
      final double barCentre = tester.getCenter(find.byType(VelvetTopBar)).dx;

      expect(
        titleCentre,
        closeTo(barCentre, 0.5),
        reason:
            'titleWidget occupies the SAME Stack slot as the default title, '
            'so it inherits the identical centring guarantee',
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

  // ── backLabel — Phase 24.1a labelled «‹ Салон» pill ───────────────────────

  group('VelvetTopBar — backLabel (Phase 24.1a)', () {
    const Key backKey = Key('vtb_labelled_back');
    // Longest master-mode title in use (`ownerOwnProfileTitle`, uk).
    const String longestTitle = 'Мій профіль';

    /// The owner-profile trailing pair: bell + `tune_rounded`, same gap as
    /// `owner_own_profile_screen.dart`.
    Widget trailingPair() => Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        NotificationBellButton(onTap: () {}, semanticLabel: 'Сповіщення'),
        const SizedBox(width: VelvetSpacing.sm + 4),
        NeumorphicIconButton(
          icon: Icons.tune_rounded,
          semanticLabel: 'Налаштування',
          onTap: () {},
        ),
      ],
    );

    testWidgets('backLabel renders the visible pill text and still fires', (
      tester,
    ) async {
      var backs = 0;
      await _pump(
        tester,
        VelvetTopBar(
          title: _kTitle,
          backKey: backKey,
          backLabel: _kBackLabel,
          onBack: () => backs++,
        ),
      );

      expect(
        find.descendant(
          of: find.byKey(backKey),
          matching: find.text(_kBackLabel),
        ),
        findsOneWidget,
      );
      expect(
        tester.getSize(find.byKey(backKey)).width,
        greaterThan(NeumorphicIconButton.extent),
      );

      await tester.tap(find.byKey(backKey));
      await tester.pump();
      expect(backs, 1);
    });

    /// Pumps the owner master-mode bar — [title] (default: the longest
    /// title), «Салон» pill, bell+tune trailing unless [withTrailing] is
    /// `false` — at [width]×800 and [textScale].
    Future<void> pumpOwnerBar(
      WidgetTester tester,
      double textScale, {
      double width = 360,
      String title = longestTitle,
      bool withTrailing = true,
      VoidCallback? onBack,
    }) async {
      await tester.pumpApp(
        Scaffold(
          body: SafeArea(
            child: Column(
              children: <Widget>[
                VelvetTopBar(
                  title: title,
                  backKey: backKey,
                  backLabel: _kBackLabel,
                  backSemanticLabel: _kBackSemantics,
                  onBack: onBack ?? () {},
                  trailing: withTrailing ? trailingPair() : null,
                ),
              ],
            ),
          ),
        ),
        width: width,
        height: 800,
        textScaleFactor: textScale,
      );
      await tester.pump();
    }

    /// Asserts the title can never touch the pill or the bell: both the
    /// rendered title AND its whole layout slot (the widest it could ever
    /// paint — the paragraph's max width, centred on the strip) sit strictly
    /// between the pill and the bell. The slot assertion is what turns red if
    /// the inset is dropped (a short title alone would still clear the pill).
    void expectTitleClear(WidgetTester tester, Finder titleFinder) {
      final Rect pill = tester.getRect(find.byKey(backKey));
      final Rect title = tester.getRect(titleFinder);
      final Rect bell = tester.getRect(find.byType(NotificationBellButton));
      final Rect strip = tester.getRect(_stripFinder);
      final RenderParagraph paragraph = tester.renderObject(titleFinder);
      final double slotHalf = paragraph.constraints.maxWidth / 2;

      expect(
        strip.center.dx - slotHalf,
        greaterThanOrEqualTo(pill.right),
        reason: 'the title slot must start right of the «Салон» pill',
      );
      expect(
        strip.center.dx + slotHalf,
        lessThanOrEqualTo(bell.left),
        reason: 'the title slot must end left of the bell',
      );
      expect(title.left, greaterThanOrEqualTo(pill.right));
      expect(title.right, lessThanOrEqualTo(bell.left));
      expect(tester.takeException(), isNull);
    }

    testWidgets(
      '360×640: longest title clears the pill and the bell+tune pair, '
      'no overflow',
      (tester) async {
        await pumpOwnerBar(tester, 1.0);

        final Finder titleFinder = find.descendant(
          of: find.byType(VelvetTopBar),
          matching: find.text(longestTitle),
        );
        expectTitleClear(tester, titleFinder);
        // Not ellipsised at 360 — the full title fits its inset slot.
        final RenderParagraph paragraph = tester.renderObject(titleFinder);
        expect(paragraph.didExceedMaxLines, isFalse);
      },
    );

    /// Phase 383 — the collapsed shape: the icon-only 48 dp chevron, no
    /// visible label, the SAME key and semantics, still tappable.
    Future<void> expectCollapsed(WidgetTester tester) async {
      expect(tester.getSize(find.byKey(backKey)), const Size(48, 48));
      expect(
        find.descendant(
          of: find.byKey(backKey),
          matching: find.text(_kBackLabel),
        ),
        findsNothing,
      );
      final SemanticsHandle handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.byKey(backKey)),
        isSemantics(label: _kBackSemantics, isButton: true),
      );
      handle.dispose();
    }

    // Phase 383 (LOW layout) — at 360 dp with ≥1.3× text the labelled pill
    // would leave the title a glyph or two, so it collapses to the chevron
    // and the title keeps the 1.0× inset that clears the bell+tune pair.
    for (final double scale in <double>[1.3, 2.0]) {
      testWidgets('360×800 @ $scale× text: the pill collapses to the '
          'icon-only chevron, semantics intact, title clear', (tester) async {
        var backs = 0;
        await pumpOwnerBar(tester, scale, onBack: () => backs++);

        await expectCollapsed(tester);
        expectTitleClear(
          tester,
          find.descendant(
            of: find.byType(VelvetTopBar),
            matching: find.text(longestTitle),
          ),
        );
        await tester.tap(find.byKey(backKey));
        await tester.pump();
        expect(backs, 1, reason: 'the collapsed chevron still navigates back');
      });
    }

    testWidgets('414×800 @ 1.3× text: room to spare keeps the grown labelled '
        'pill, title clear', (tester) async {
      await pumpOwnerBar(tester, 1.3, width: 414);

      expect(
        find.descendant(
          of: find.byKey(backKey),
          matching: find.text(_kBackLabel),
        ),
        findsOneWidget,
      );
      expect(
        tester.getSize(find.byKey(backKey)).width,
        greaterThan(VelvetTopBar.labelledTitleInset - VelvetSpacing.sm),
      );
      expectTitleClear(
        tester,
        find.descendant(
          of: find.byType(VelvetTopBar),
          matching: find.text(longestTitle),
        ),
      );
    });

    testWidgets('320×800 @ 1.0× text, no trailing: collapses and the title '
        'takes the chevron slot inset only', (tester) async {
      const String title = 'Мій розклад';
      await pumpOwnerBar(
        tester,
        1.0,
        width: 320,
        title: title,
        withTrailing: false,
      );

      await expectCollapsed(tester);
      final Finder titleFinder = find.descendant(
        of: find.byType(VelvetTopBar),
        matching: find.text(title),
      );
      final RenderParagraph paragraph = tester.renderObject(titleFinder);
      expect(
        paragraph.constraints.maxWidth,
        tester.getSize(_stripFinder).width -
            2 * (NeumorphicIconButton.extent + VelvetSpacing.sm),
      );
      expect(
        tester.getRect(titleFinder).left,
        greaterThanOrEqualTo(tester.getRect(find.byKey(backKey)).right),
      );
      expect(tester.takeException(), isNull);
    });

    test('labelledBackFits — the readable minimum is ~8 glyphs (or the '
        'whole title, if shorter) of the page-title style, text-scaled', () {
      const TextScaler one = TextScaler.noScaling;
      final double eight = VelvetTopBar.minTitleRoomFor('12345678901', one);
      expect(VelvetTopBar.minTitleRoomFor('123', one), lessThan(eight));
      expect(
        VelvetTopBar.minTitleRoomFor('12345678901', const TextScaler.linear(2)),
        closeTo(2 * eight, 0.001),
      );
      expect(
        VelvetTopBar.labelledBackFits(
          titleRoom: eight,
          title: 'x' * 11,
          scaler: one,
        ),
        isTrue,
      );
      expect(
        VelvetTopBar.labelledBackFits(
          titleRoom: eight - 1,
          title: 'x' * 11,
          scaler: one,
        ),
        isFalse,
      );
    });

    testWidgets('backLabel with a null onBack renders no pill and does not '
        'inset the title', (tester) async {
      await _pump(
        tester,
        const VelvetTopBar(title: _kTitle, backLabel: _kBackLabel),
      );

      expect(find.byType(NeumorphicIconButton), findsNothing);
      expect(find.text(_kBackLabel), findsNothing);
      final Text title = tester.widget<Text>(_titleFinder);
      expect(title.maxLines, isNull, reason: 'the unlabelled title tree');
      expect(
        find.ancestor(
          of: _titleFinder,
          matching: find.byWidgetPredicate(
            (Widget w) =>
                w is Padding &&
                w.padding.horizontal >= 2 * VelvetTopBar.labelledTitleInset,
          ),
        ),
        findsNothing,
      );
    });

    testWidgets('an over-long title ellipsises inside the inset, clear of '
        'the pill', (tester) async {
      const String longTitle = 'Дуже довгий заголовок екрана майстра';
      await tester.pumpApp(
        Scaffold(
          body: SafeArea(
            child: Column(
              children: <Widget>[
                VelvetTopBar(
                  title: longTitle,
                  backKey: backKey,
                  backLabel: _kBackLabel,
                  onBack: () {},
                ),
              ],
            ),
          ),
        ),
        width: 360,
        height: 640,
      );
      await tester.pump();

      final Finder titleFinder = find.text(longTitle);
      final Rect pill = tester.getRect(find.byKey(backKey));
      final Rect title = tester.getRect(titleFinder);
      expect(title.left, greaterThanOrEqualTo(pill.right));
      final RenderParagraph paragraph = tester.renderObject(titleFinder);
      expect(paragraph.didExceedMaxLines, isTrue);
    });

    testWidgets('null backLabel keeps the unpadded, unclamped title', (
      tester,
    ) async {
      await _pump(tester, VelvetTopBar(title: _kTitle, onBack: () {}));

      expect(
        find.descendant(
          of: find.byType(NeumorphicIconButton),
          matching: find.byType(Text),
        ),
        findsNothing,
      );
      expect(tester.getSize(find.byType(NeumorphicIconButton)).width, 48);
      final Text title = tester.widget<Text>(_titleFinder);
      expect(title.maxLines, isNull);
      expect(
        find
            .ancestor(of: _titleFinder, matching: find.byType(Padding))
            .evaluate()
            .where((Element e) {
              final Padding p = e.widget as Padding;
              return p.padding ==
                  const EdgeInsets.symmetric(
                    horizontal: VelvetTopBar.labelledTitleInset,
                  );
            }),
        isEmpty,
      );
    });
  });
}
