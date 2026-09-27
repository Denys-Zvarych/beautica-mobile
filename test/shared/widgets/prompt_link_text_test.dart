// PromptLinkText — pins the baseline alignment that the login sign-up row and
// the OTP resend row both lost when laid out as sibling boxes (body() has
// height 1.5, link() has none). Measures real render geometry, not fields.

import 'package:beautica_mobile/shared/widgets/prompt_link_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const ValueKey<String> _linkKey = ValueKey<String>('prompt_link');
const String _prompt = 'Не отримали код?';

Future<void> _pump(
  WidgetTester tester, {
  required double width,
  double scale = 1.0,
  String link = 'Надіслати знову',
  VoidCallback? onTap,
}) async {
  tester.view.physicalSize = Size(width * 3, 800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: PromptLinkText(
              prompt: _prompt,
              linkLabel: link,
              linkKey: _linkKey,
              onTap: onTap,
            ),
          ),
        ),
      ),
    ),
  );
}

Finder get _promptFinder => find.byWidgetPredicate(
  (w) => w is RichText && w.text.toPlainText().startsWith(_prompt),
);

Finder get _linkFinder =>
    find.descendant(of: find.byKey(_linkKey), matching: find.byType(RichText));

/// Global y of the first line's alphabetic baseline of [finder]'s paragraph.
double _baselineY(WidgetTester tester, Finder finder) {
  final RenderParagraph p = tester.renderObject<RenderParagraph>(finder);
  // Baseline queries assert they run inside the parent's layout; the flag
  // lifts that for a post-layout measurement.
  RenderObject.debugCheckingIntrinsics = true;
  try {
    final double b = p.getDistanceToBaseline(TextBaseline.alphabetic)!;
    return p.localToGlobal(Offset(0, b)).dy;
  } finally {
    RenderObject.debugCheckingIntrinsics = false;
  }
}

void main() {
  testWidgets('prompt and link share one alphabetic baseline', (tester) async {
    await _pump(tester, width: 360);
    // A box-aligned layout put the link 0.5–1.5 dp high; baseline placement
    // is exact at 1.0×.
    expect(
      _baselineY(tester, _linkFinder),
      moreOrLessEquals(_baselineY(tester, _promptFinder), epsilon: 0.01),
    );
  });

  testWidgets('long link wraps at 320 dp / 1.3× instead of overflowing', (
    tester,
  ) async {
    await _pump(tester, width: 320, scale: 1.3, link: 'Надіслати знову (59 с)');
    expect(tester.takeException(), isNull);
    // Wrapped: the link sits on a line below the prompt's first line.
    expect(
      _baselineY(tester, _linkFinder),
      greaterThan(_baselineY(tester, _promptFinder)),
    );
  });

  testWidgets('link text is scaled once, not twice', (tester) async {
    await _pump(tester, width: 360);
    final double base = tester.getRect(_linkFinder).height;
    await _pump(tester, width: 360, scale: 1.3);
    final double scaled = tester.getRect(_linkFinder).height;
    // Double scaling (inner Text + WidgetSpan transform) would give ~1.69×.
    expect(scaled / base, moreOrLessEquals(1.3, epsilon: 0.05));
  });

  testWidgets('tap on the link key fires onTap', (tester) async {
    var taps = 0;
    await _pump(tester, width: 360, onTap: () => taps++);
    await tester.tap(find.byKey(_linkKey));
    expect(taps, 1);
  });

  testWidgets('null onTap leaves the link without a tap handler', (
    tester,
  ) async {
    await _pump(tester, width: 360);
    final GestureDetector detector = tester.widget<GestureDetector>(
      find.byKey(_linkKey),
    );
    expect(detector.onTap, isNull);
  });
}
