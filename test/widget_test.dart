// Phase 1.4 — top-level smoke test: BeauticaApp boots without crashing.
//
// The Phase 0 counter scaffold (_BootstrapHome) was removed when
// MaterialApp.router + go_router landed in Phase 1.4.  This test verifies
// the ProviderScope + MaterialApp.router initialises cleanly and routes to
// the /splash placeholder as the initial location.
//
// A more focused router test lives at test/routing/app_router_test.dart.
// Feature-level widget tests land in test/widget/ as features are built.

import 'package:beautica_mobile/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('BeauticaApp boots and renders splash placeholder', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: BeauticaApp()));
    // Allow the router to settle — go_router performs async redirect evaluation
    // on the first frame.
    await tester.pumpAndSettle();

    // The initial route is /splash — _Placeholder renders a Text with 'splash'.
    expect(find.text('splash'), findsOneWidget);
  });
}
