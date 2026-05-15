// Phase 1.4 — smoke test for the go_router routing skeleton.
// Phase 2.9 — Updated: authRedirect now takes (AsyncValue<AuthSession>, state).
//             Test router uses redirect: (_, __) => null so auth logic is not
//             exercised here — that is covered by auth_redirect_test.dart.
//
// Creates a [GoRouter] directly (not via the Riverpod provider) to keep the
// test dependency-free. Validates that:
//   1. The router resolves the initial location to the splash placeholder.
//   2. `router.go(RouteNames.login)` switches the view to the login placeholder.
//   3. The redirect is a no-op for this test (null always) — routing skeleton.
//
// Note: `test/` is excluded from the `no_raw_ui_strings` custom lint rule —
// raw string literals in test find expressions are acceptable here.

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  group('appRouter smoke tests', () {
    late GoRouter router;

    setUp(() {
      router = GoRouter(
        initialLocation: RouteNames.splash,
        // Auth redirect logic is tested in auth_redirect_test.dart.
        // This test exercises the routing skeleton only — no redirects.
        redirect: (context, state) => null,
        routes: [
          GoRoute(
            path: RouteNames.splash,
            builder: (context, s) => const _Placeholder('splash'),
          ),
          GoRoute(
            path: RouteNames.login,
            builder: (context, s) => const _Placeholder('login'),
          ),
          GoRoute(
            path: RouteNames.register,
            builder: (context, s) => const _Placeholder('register'),
          ),
          GoRoute(
            path: RouteNames.home,
            builder: (context, s) => const _Placeholder('home'),
          ),
          GoRoute(
            path: RouteNames.settings,
            builder: (context, s) => const _Placeholder('settings'),
          ),
        ],
      );
    });

    tearDown(() => router.dispose());

    testWidgets('initial route shows splash placeholder', (tester) async {
      await tester.pumpWidget(_TestApp(router: router));
      await tester.pumpAndSettle();

      expect(find.text('splash'), findsOneWidget);
    });

    testWidgets('go(login) navigates to login placeholder', (tester) async {
      await tester.pumpWidget(_TestApp(router: router));
      await tester.pumpAndSettle();

      router.go(RouteNames.login);
      await tester.pumpAndSettle();

      expect(find.text('login'), findsOneWidget);
    });

    testWidgets('all routes resolve without unexpected redirects', (
      tester,
    ) async {
      await tester.pumpWidget(_TestApp(router: router));
      await tester.pumpAndSettle();

      // Navigate to every route and confirm no unexpected redirect occurs.
      for (final path in [
        RouteNames.login,
        RouteNames.register,
        RouteNames.home,
        RouteNames.splash,
        RouteNames.settings,
      ]) {
        router.go(path);
        await tester.pumpAndSettle();
        // The placeholder label is the last segment of the path (e.g. 'login').
        final label = path == RouteNames.home ? 'home' : path.substring(1);
        expect(find.text(label), findsOneWidget);
      }
    });
  });
}

/// Minimal [MaterialApp.router] wrapper that supplies l10n delegates needed
/// by [onGenerateTitle] and any widget under test that calls [AppLocalizations.of].
class _TestApp extends StatelessWidget {
  const _TestApp({required this.router});

  final GoRouter router;

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    routerConfig: router,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('uk', 'UA'),
  );
}

/// Mirror of the private [_Placeholder] in `app_router.dart` — needed because
/// the private class cannot be imported in tests.  Both render `Text(label)`.
class _Placeholder extends StatelessWidget {
  const _Placeholder(this.label);

  final String label;

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text(label)));
}
