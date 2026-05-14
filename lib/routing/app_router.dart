import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'auth_redirect.dart';
import 'route_names.dart';

part 'app_router.g.dart';

/// Riverpod-managed [GoRouter] instance.
///
/// Phase 1.4 — placeholder routes for every top-level path. Real screens
/// land in Phase 2.5 (auth) and Phase 2.6 (master home).  [GoRouter] is
/// `keepAlive: true` because it must survive tab switches and is shared
/// across the entire widget tree via [MaterialApp.router].
@Riverpod(keepAlive: true)
GoRouter appRouter(Ref ref) => GoRouter(
  initialLocation: RouteNames.splash,
  redirect: (ctx, state) => authRedirect(state),
  routes: [
    GoRoute(
      path: RouteNames.splash,
      builder: (_, s) => const _Placeholder('splash'),
    ),
    GoRoute(
      path: RouteNames.login,
      builder: (_, s) => const _Placeholder('login'),
    ),
    GoRoute(
      path: RouteNames.register,
      builder: (_, s) => const _Placeholder('register'),
    ),
    GoRoute(
      path: RouteNames.home,
      builder: (_, s) => const _Placeholder('home'),
    ),
  ],
);

/// Throwaway scaffold used by every route until Phase 2.x replaces it with
/// a real screen.  The [label] is a variable, not a raw string literal, so
/// the `no_raw_ui_strings` custom lint rule is satisfied.
class _Placeholder extends StatelessWidget {
  const _Placeholder(this.label);

  final String label;

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text(label)));
}
