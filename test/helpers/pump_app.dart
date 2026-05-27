// Shared test helper — pumps a MaterialApp with l10n + Riverpod ProviderScope.
//
// Usage:
//   await tester.pumpApp(
//     MyWidget(),
//     overrides: [myProvider.overrideWithValue(fakeValue)],
//   );
//
// The UK locale is used by default because UA is the primary language.
// Pass locale: const Locale('en') to test English strings.

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Extension on [WidgetTester] that wraps [widget] in a minimal
/// [ProviderScope] + [MaterialApp] with l10n configured for tests.
extension PumpApp on WidgetTester {
  // ignore: avoid_returning_null_for_void
  Future<void> pumpApp(
    Widget widget, {
    List<Object> overrides = const [],
    Locale locale = const Locale('uk'),
  }) async {
    await pumpWidget(
      ProviderScope(
        // ProviderScope.overrides accepts List<Override>; we cast so callers
        // can pass a plain list without importing the internal Override type.
        // ignore: avoid_dynamic_calls
        overrides: overrides.cast(),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
          home: widget,
        ),
      ),
    );
  }

  /// Pumps the widget inside a router context (required for go_router calls
  /// like context.go() and context.push() inside the widget under test).
  Future<void> pumpRoutedApp(
    GoRouter router, {
    List<Object> overrides = const [],
    Locale locale = const Locale('uk'),
  }) async {
    await pumpWidget(
      ProviderScope(
        overrides: overrides.cast(),
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
        ),
      ),
    );
  }
}
