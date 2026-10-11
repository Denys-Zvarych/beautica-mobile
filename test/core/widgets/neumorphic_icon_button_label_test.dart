// Phase 24.1a — [NeumorphicIconButton.label], the visible «‹ Салон» pill.
//
// Assertions are on RENDERED output (find.text, laid-out sizes, the real
// semantics tree), never on constructor fields — a field assertion would pass
// even if `build` ignored the parameter.

import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

// Test-supplied label passed INTO the widget under test — not l10n copy.
const String _kBackLabel = 'Салон';

const Key _kButton = Key('nib_label_button');

Future<void> _pump(WidgetTester tester, NeumorphicIconButton button) async {
  await tester.pumpApp(
    Scaffold(
      body: Align(alignment: Alignment.topLeft, child: button),
    ),
  );
  await tester.pump();
}

NeumorphicIconButton _button({String? label, VoidCallback? onTap}) =>
    NeumorphicIconButton(
      key: _kButton,
      icon: Icons.arrow_back_ios_new_rounded,
      semanticLabel: 'Назад до салону',
      onTap: onTap ?? () {},
      label: label,
    );

Finder _inButton(Finder matching) =>
    find.descendant(of: find.byKey(_kButton), matching: matching);

void main() {
  group('NeumorphicIconButton.label — labelled pill', () {
    testWidgets('renders the visible label beside the chevron', (tester) async {
      await _pump(tester, _button(label: _kBackLabel));

      expect(_inButton(find.text(_kBackLabel)), findsOneWidget);
      expect(
        _inButton(find.byIcon(Icons.arrow_back_ios_new_rounded)),
        findsOneWidget,
      );

      final Rect chevron = tester.getRect(
        _inButton(find.byIcon(Icons.arrow_back_ios_new_rounded)),
      );
      final Rect text = tester.getRect(_inButton(find.text(_kBackLabel)));
      expect(
        text.left,
        greaterThanOrEqualTo(chevron.right),
        reason: 'the label sits to the RIGHT of the chevron, not under it',
      );
    });

    testWidgets('pill is 48 dp high and wider than the square face', (
      tester,
    ) async {
      await _pump(tester, _button(label: _kBackLabel));

      final Size size = tester.getSize(find.byKey(_kButton));
      expect(size.height, NeumorphicIconButton.extent);
      expect(size.width, greaterThan(NeumorphicIconButton.extent));
    });

    testWidgets('tapping the label pill fires onTap once', (tester) async {
      var taps = 0;
      await _pump(tester, _button(label: _kBackLabel, onTap: () => taps++));

      await tester.tap(find.byKey(_kButton));
      await tester.pump();
      expect(taps, 1);

      // The visible text itself is part of the hit area.
      await tester.tap(_inButton(find.text(_kBackLabel)));
      await tester.pump();
      expect(taps, 2);
    });

    testWidgets('semantics announce semanticLabel once, not the visible text', (
      tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await _pump(tester, _button(label: _kBackLabel));

      expect(
        tester.getSemantics(find.byKey(_kButton)),
        matchesSemantics(
          label: 'Назад до салону',
          isButton: true,
          hasTapAction: true,
        ),
        reason:
            'the visible «Салон» must be excluded so a screen reader does not '
            'read the destination twice',
      );
      expect(find.bySemanticsLabel(RegExp(_kBackLabel)), findsNothing);

      handle.dispose();
    });
  });

  group('NeumorphicIconButton.label — contract edges', () {
    test('label + faceSize is rejected (mutually exclusive)', () {
      expect(
        () => NeumorphicIconButton(
          icon: Icons.arrow_back_ios_new_rounded,
          semanticLabel: 'Назад',
          onTap: () {},
          label: _kBackLabel,
          faceSize: 36,
        ),
        throwsAssertionError,
      );
    });

    testWidgets('a supplied iconWidget renders inside the pill', (
      tester,
    ) async {
      const Key glyph = Key('nib_label_custom_glyph');
      await _pump(
        tester,
        NeumorphicIconButton(
          key: _kButton,
          iconWidget: const SizedBox(key: glyph, width: 22, height: 22),
          semanticLabel: 'Назад до салону',
          onTap: () {},
          label: _kBackLabel,
        ),
      );

      expect(_inButton(find.byKey(glyph)), findsOneWidget);
      expect(_inButton(find.text(_kBackLabel)), findsOneWidget);
    });

    testWidgets('a disabled labelled pill does not fire onTap', (tester) async {
      var taps = 0;
      await _pump(
        tester,
        NeumorphicIconButton(
          key: _kButton,
          icon: Icons.arrow_back_ios_new_rounded,
          semanticLabel: 'Назад до салону',
          onTap: () => taps++,
          label: _kBackLabel,
          enabled: false,
        ),
      );

      await tester.tap(_inButton(find.text(_kBackLabel)), warnIfMissed: false);
      await tester.pump();

      expect(taps, 0);
      expect(_inButton(find.text(_kBackLabel)), findsOneWidget);
    });
  });

  group('NeumorphicIconButton.label — over-long label', () {
    // Test-local over-long label (ASCII — never a find.text target here).
    const String longLabel = 'A deliberately over-long back label for overflow';

    RenderParagraph labelParagraph(WidgetTester tester) =>
        tester.renderObject<RenderParagraph>(
          find.descendant(
            of: _inButton(find.byType(Text)),
            matching: find.byType(RichText),
          ),
        );

    testWidgets('caps the pill at labelMaxWidth and ellipsises', (
      tester,
    ) async {
      await _pump(tester, _button(label: longLabel));

      expect(tester.takeException(), isNull, reason: 'no RenderFlex overflow');
      expect(
        tester.getSize(find.byKey(_kButton)).width,
        NeumorphicIconButton.labelMaxWidth,
      );
      final RenderParagraph p = labelParagraph(tester);
      expect(p.didExceedMaxLines, isTrue);
      final Text text = tester.widget<Text>(_inButton(find.byType(Text)));
      expect(text.overflow, TextOverflow.ellipsis);
      expect(text.maxLines, 1);
    });

    testWidgets('in a parent narrower than labelMaxWidth it shrinks to fit '
        'without overflow', (tester) async {
      const double narrow = 100;
      await tester.pumpApp(
        Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: narrow,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _button(label: longLabel),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull, reason: 'no RenderFlex overflow');
      expect(
        tester.getSize(find.byKey(_kButton)).width,
        lessThanOrEqualTo(narrow),
      );
      expect(labelParagraph(tester).didExceedMaxLines, isTrue);
    });
  });

  group('NeumorphicIconButton.label — null default (pre-phase tree)', () {
    testWidgets('label: null renders the 48×48 square, no Row, no text', (
      tester,
    ) async {
      await _pump(tester, _button());

      expect(tester.getSize(find.byKey(_kButton)), const Size(48, 48));
      expect(_inButton(find.byType(Row)), findsNothing);
      expect(_inButton(find.byType(Text)), findsNothing);
    });
  });
}
