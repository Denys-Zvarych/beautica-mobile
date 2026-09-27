// Widget tests for `ProfileMetaLine` (lib/shared/widgets/profile_meta_line.dart).
//
// mobile-qa gap-fix (2026-09-26) — `ProfileMetaLine` was PROMOTED from two
// byte-for-byte forks (`HomeProfileCard._MetaLine` and
// `PassportScreen._ProfileBlock._line`) as part of the saved-place-label
// two-line fix, but the promotion shipped with NO direct test of the shared
// widget itself — only the five call sites (home_profile_card_test,
// passport_screen_test, master_address_block_test, salon_affiliation_card_test,
// public_salon_profile_screen_test) exercise it indirectly. This file proves
// the widget's own contract in isolation, the way `rating_summary_line_test
// .dart` does for its sibling promoted widget:
//   1. `maxLines` defaults to 1 — every pre-existing call site that does not
//      pass it renders byte-identically to before the promotion.
//   2. `maxLines: 2` actually reaches the inner `Text` and lets a long label
//      wrap to a second line instead of being ellipsis-collapsed to one —
//      this is the load-bearing assertion for the bug this widget exists to
//      fix (see `profile_meta_line.dart`'s file doc).
//   3. `onTap` wraps the row in a `GestureDetector`; `onTap: null` (the
//      default) renders NO `GestureDetector` at all.
//   4. `textKey` lands on the inner `Text`.
//   5. `iconWidget` replaces the Material `Icon` built from `icon` when given.

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/shared/widgets/profile_meta_line.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const String _shortText = 'Львів';

// The exact user-reported shape — long enough to need a second line at a
// narrow width, short enough to still fit within the 2-line budget.
const String _longText = 'с. Іванівка (Шишацька громада), Полтавська обл.';

Widget _wrap(Widget child, {double width = 220}) => MaterialApp(
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: width, child: child),
    ),
  ),
);

/// Re-derives the ACTUAL laid-out line count from the render object, mirroring
/// the pattern every call-site regression test in this repo already uses
/// (`home_profile_card_test.dart`, `master_address_block_test.dart`, etc.) —
/// never trust the widget's `maxLines` param alone, only what it painted.
int _lineCount(RenderParagraph p) {
  final TextPainter painter = TextPainter(
    text: p.text,
    textAlign: p.textAlign,
    textDirection: p.textDirection,
    textScaler: p.textScaler,
    maxLines: p.maxLines,
  )..layout(maxWidth: p.constraints.maxWidth);
  final int lines = painter.computeLineMetrics().length;
  painter.dispose();
  return lines;
}

void main() {
  group('ProfileMetaLine — maxLines contract', () {
    testWidgets('defaults to maxLines: 1 — a long label is collapsed with '
        'ellipsis, never wrapped, when the param is omitted', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ProfileMetaLine(
            icon: Icons.location_on_rounded,
            text: _longText,
            textKey: Key('meta-text'),
          ),
        ),
      );

      final RenderParagraph p = tester.renderObject<RenderParagraph>(
        find.byKey(const Key('meta-text')),
      );
      expect(p.maxLines, 1);
      expect(
        p.didExceedMaxLines,
        isTrue,
        reason:
            'the long fixture must actually exceed one line — otherwise '
            'this assertion is vacuous',
      );
    });

    testWidgets('maxLines: 2 lets a long label wrap to a second line instead '
        'of being ellipsis-collapsed to one', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ProfileMetaLine(
            icon: Icons.location_on_rounded,
            text: _longText,
            textKey: Key('meta-text'),
            maxLines: 2,
          ),
        ),
      );

      final RenderParagraph p = tester.renderObject<RenderParagraph>(
        find.byKey(const Key('meta-text')),
      );
      expect(
        _lineCount(p),
        2,
        reason:
            'the long label must actually wrap onto a second line — a '
            'reverted maxLines: 1 would cap this at one line',
      );
      expect(
        p.didExceedMaxLines,
        isFalse,
        reason:
            'the full label fits within the 2-line budget — it must not '
            'be truncated with an ellipsis',
      );
    });

    testWidgets('a short label renders unchanged on one line whether '
        'maxLines is 1 or 2 (no regression for existing short-label '
        'callers)', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ProfileMetaLine(
            icon: Icons.location_on_rounded,
            text: _shortText,
            textKey: Key('meta-text'),
            maxLines: 2,
          ),
        ),
      );

      final RenderParagraph p = tester.renderObject<RenderParagraph>(
        find.byKey(const Key('meta-text')),
      );
      expect(_lineCount(p), 1);
      expect(p.didExceedMaxLines, isFalse);
    });
  });

  group('ProfileMetaLine — onTap / GestureDetector', () {
    testWidgets('onTap: null renders NO GestureDetector', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ProfileMetaLine(icon: Icons.call_rounded, text: _shortText),
        ),
      );

      expect(find.byType(GestureDetector), findsNothing);
    });

    testWidgets('a non-null onTap wraps the row in a tappable '
        'GestureDetector that fires on tap', (tester) async {
      int taps = 0;
      await tester.pumpWidget(
        _wrap(
          ProfileMetaLine(
            icon: Icons.call_rounded,
            text: _shortText,
            onTap: () => taps++,
          ),
        ),
      );

      expect(find.byType(GestureDetector), findsOneWidget);
      await tester.tap(find.byType(GestureDetector));
      await tester.pump();
      expect(taps, 1);
    });
  });

  group('ProfileMetaLine — icon', () {
    testWidgets('renders a Material Icon built from [icon] by default', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const ProfileMetaLine(
            icon: Icons.location_on_rounded,
            text: _shortText,
          ),
        ),
      );

      final Icon icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.icon, Icons.location_on_rounded);
      expect(icon.size, 16);
      expect(icon.color, BrandColors.accent);
    });

    testWidgets('a non-null iconWidget replaces the Material Icon', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const ProfileMetaLine(
            icon: Icons.location_on_rounded,
            text: _shortText,
            iconWidget: Icon(Icons.star, key: Key('custom-icon')),
          ),
        ),
      );

      expect(find.byKey(const Key('custom-icon')), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is Icon && w.icon == Icons.location_on_rounded,
        ),
        findsNothing,
        reason: 'the Material fallback Icon must not also render',
      );
    });
  });
}
