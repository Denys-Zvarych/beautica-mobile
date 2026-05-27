// Phase 1.3 — explicit `onGenerateTitle` localisation test.
//
// Verifies that `MaterialApp.onGenerateTitle` resolves `l10n.appTitle` to
// the locked product name 'Beautica'. The wired-up entry point in
// `lib/main.dart` already exercises this path indirectly (the widget
// smoke test pumps `BeauticaApp`), but a dedicated unit test gives us a
// direct assertion the next time someone reaches for the title hook.
//
// Implementation note: we reach into the rendered `WidgetsApp` widget
// (the inner shell `MaterialApp` constructs) and invoke its
// `onGenerateTitle` callback with the `BuildContext` produced inside the
// home `Builder`. That context sits below the `Localizations` widget
// `MaterialApp` installs, so `AppLocalizations.of(ctx)` resolves the
// correct delegate — which is exactly what Flutter does at runtime when
// it computes the OS task-switcher label.

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('onGenerateTitle resolves appTitle to "Beautica"', (
    WidgetTester tester,
  ) async {
    late BuildContext capturedContext;

    await tester.pumpWidget(
      MaterialApp(
        onGenerateTitle: (ctx) => AppLocalizations.of(ctx).appTitle,
        locale: const Locale('uk', 'UA'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (ctx) {
            capturedContext = ctx;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final WidgetsApp widgetsApp = tester.widget<WidgetsApp>(
      find.byType(WidgetsApp),
    );
    final String? title = widgetsApp.onGenerateTitle?.call(capturedContext);
    expect(title, 'Beautica');
  });
}
