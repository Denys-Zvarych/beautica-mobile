import 'package:go_router/go_router.dart';

/// Auth redirect callback wired into [GoRouter.redirect].
///
/// Phase 1.4 — stub that allows every location unconditionally.
/// Phase 2.9 promotes this to read `authNotifierProvider` and redirect
/// unauthenticated users to [RouteNames.login].
String? authRedirect(GoRouterState state) {
  // Phase 2.9 promotes this to a real guard reading authNotifierProvider.
  return null;
}
