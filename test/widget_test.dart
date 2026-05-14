// Phase 0 — proof-of-life widget smoke test.
//
// Verifies the bootstrap counter renders, starts at 0, and increments to 1
// when the floating action button is tapped. Phase 1+ replaces this fixture
// with feature-level widget tests under `test/widget/`.

import 'package:beautica_mobile/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Bootstrap counter increments on FAB tap', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const BeauticaApp());

    expect(find.text('0'), findsOneWidget);
    expect(find.text('1'), findsNothing);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();

    expect(find.text('0'), findsNothing);
    expect(find.text('1'), findsOneWidget);
  });
}
