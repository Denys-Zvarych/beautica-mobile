// Widget tests for `ContactTile` (lib/shared/widgets/contact_tile.dart).
//
// Written 2026-08-31 by mobile-qa alongside the salon-management Instagram
// empty-state change (`salon_management_profile_screen.dart:837-847`), which
// added the `valueIsPlaceholder` constructor flag and started passing it
// `true` for the "Додати посилання" empty state. `ContactTile` is a SHARED
// render widget with 10 call sites in `lib/`, and until this file existed it
// had ZERO direct widget tests and ZERO golden coverage — every guarantee
// about it was inherited transitively through screen-level key lookups,
// which is exactly the gap that let a `_AddLink` -> `ContactTile` type swap
// pass a pre-existing `find.byKey(...)` assertion unchanged (see
// `salon_management_profile_screen_test.dart`'s "resolved TYPE" additions).
//
// What THIS file proves that the screen-level tests structurally cannot:
//   1. `valueIsPlaceholder: false` (the default, and every pre-existing call
//      site) renders the value in `VelvetText.bodyStrong()` — a REAL
//      rendered-TextStyle assertion, not a field read.
//   2. `valueIsPlaceholder: true` renders the SAME value string in a
//      DIFFERENT resolved style (`VelvetText.link()`), and that style
//      actually differs from (1) in color and font size — the one assertion
//      that would catch `valueIsPlaceholder` being silently ignored by a
//      future refactor of `_valueStyle`.
//   3. The optional `label` caption renders above the value in a two-line
//      column when supplied, and is absent (single-line value only) when
//      omitted — both branches of the `widget.label != null` fork.
//   4. Tapping the tile fires `onTap` exactly once. The tap must land via
//      `tester.tap(find.byKey(...))` — NOT hand-computed hit-test
//      coordinates — because the tile's root is
//      `Semantics -> GestureDetector -> AnimatedScale`; a `warnIfMissed:
//      false` workaround here would paper over a real "the key sits above
//      the hit-testable area" regression rather than proving the tap works.
//   5. `icon` flows to the rendered `Icon` in the glyph well.
//
// Isolation: no Riverpod providers — `ContactTile` takes plain constructor
// args. Every test wraps in a bare `MaterialApp` (no localisation needed;
// `value`/`label` are passed as literals here, matching how call sites pass
// already-resolved l10n strings down).

import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/shared/widgets/contact_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

/// Resolves the rendered [Text] for the tile's value slot — the LAST `Text`
/// descendant of the tile, since the optional platform-label caption (when
/// present) is the first and the value is always the second/only.
Text _valueText(WidgetTester tester, Finder tileFinder) {
  final texts = tester.widgetList<Text>(
    find.descendant(of: tileFinder, matching: find.byType(Text)),
  );
  return texts.last;
}

void main() {
  group('ContactTile — value style (valueIsPlaceholder)', () {
    testWidgets('valueIsPlaceholder: false (default) renders the value in '
        'VelvetText.bodyStrong()', (tester) async {
      await tester.pumpWidget(
        _wrap(
          ContactTile(
            key: const Key('tile'),
            icon: Icons.phone_outlined,
            value: '+380671112233',
            semanticLabel: 'phone',
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final Text valueText = _valueText(tester, find.byKey(const Key('tile')));
      expect(valueText.data, '+380671112233');
      expect(valueText.style, VelvetText.bodyStrong());
    });

    testWidgets('valueIsPlaceholder: true renders the SAME value string in a '
        'DIFFERENT style (VelvetText.link()), not bodyStrong', (tester) async {
      await tester.pumpWidget(
        _wrap(
          ContactTile(
            key: const Key('tile'),
            icon: Icons.alternate_email,
            value: 'Додати посилання',
            valueIsPlaceholder: true,
            semanticLabel: 'add link',
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final Text valueText = _valueText(tester, find.byKey(const Key('tile')));
      expect(valueText.data, 'Додати посилання');
      expect(valueText.style, VelvetText.link());
      expect(
        valueText.style,
        isNot(VelvetText.bodyStrong()),
        reason:
            'this is the assertion that would catch valueIsPlaceholder '
            'being silently ignored: it must resolve to a DIFFERENT style '
            'than the populated-value branch, not merely "some style"',
      );
      // Pin the actual visual divergence, not just style-object identity —
      // color and size are what a viewer actually perceives.
      expect(valueText.style!.color, VelvetText.link().color);
      expect(valueText.style!.color, isNot(VelvetText.bodyStrong().color));
      expect(valueText.style!.fontSize, VelvetText.link().fontSize);
    });
  });

  group('ContactTile — label caption', () {
    testWidgets('label supplied renders a two-line column: caption + value', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          ContactTile(
            key: const Key('tile'),
            icon: Icons.alternate_email,
            value: '@velvet',
            label: 'Instagram',
            semanticLabel: 'Instagram',
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Instagram'), findsOneWidget);
      expect(find.text('@velvet'), findsOneWidget);
      final texts = tester.widgetList<Text>(
        find.descendant(
          of: find.byKey(const Key('tile')),
          matching: find.byType(Text),
        ),
      );
      expect(
        texts.length,
        2,
        reason: 'label present -> caption Text + value Text, two nodes',
      );
    });

    testWidgets('label omitted renders only the value, no caption node', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          ContactTile(
            key: const Key('tile'),
            icon: Icons.phone_outlined,
            value: '+380671112233',
            semanticLabel: 'phone',
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final texts = tester.widgetList<Text>(
        find.descendant(
          of: find.byKey(const Key('tile')),
          matching: find.byType(Text),
        ),
      );
      expect(
        texts.length,
        1,
        reason: 'no label -> value Text only, single-line branch',
      );
    });
  });

  group('ContactTile — tap and icon', () {
    testWidgets('tapping the tile (by key) fires onTap exactly once', (
      tester,
    ) async {
      int taps = 0;
      await tester.pumpWidget(
        _wrap(
          ContactTile(
            key: const Key('tile'),
            icon: Icons.alternate_email,
            value: 'Додати посилання',
            valueIsPlaceholder: true,
            semanticLabel: 'add link',
            onTap: () => taps++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Root is Semantics -> GestureDetector -> AnimatedScale: a tap by KEY
      // must land without `warnIfMissed: false`. If this starts warning, the
      // fix is finding the correct hit-testable descendant — never
      // suppressing the warning.
      // tester.tap() dispatches the down+up pointer pair itself; no
      // intermediate pump is needed since this test asserts only that
      // onTap fired, not any mid-press AnimatedScale/AnimatedContainer
      // value (which would require pump-until-condition, not a fixed wait).
      await tester.tap(find.byKey(const Key('tile')));
      await tester.pumpAndSettle();

      expect(taps, 1);
    });

    testWidgets('icon flows to the rendered Icon in the glyph well', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          ContactTile(
            key: const Key('tile'),
            icon: Icons.alternate_email,
            value: '@velvet',
            semanticLabel: 'Instagram',
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final Icon glyph = tester.widget<Icon>(
        find
            .descendant(
              of: find.byKey(const Key('tile')),
              matching: find.byType(Icon),
            )
            .first,
      );
      expect(glyph.icon, Icons.alternate_email);
    });
  });
}
