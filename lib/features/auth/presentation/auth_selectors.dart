// Phase 2.4 — Derived auth selectors.
//
// Thin computed providers that shield feature code from needing to unwrap
// AsyncValue<AuthSession> directly. These re-compute only when the auth
// session changes — downstream providers that watch them will not rebuild
// on unrelated state changes.
//
// Both providers use `Ref` (not typed ref variants — deprecated in
// Riverpod 3.x). `.value` is used (not the removed `.valueOrNull`).

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/auth_session.dart';
import '../domain/user.dart';
import 'auth_notifier.dart';

part 'auth_selectors.g.dart';

/// Returns the authenticated [User], or `null` when unauthenticated or loading.
///
/// Widgets that only need the user profile (e.g. displaying the avatar) should
/// watch this provider rather than unwrapping [authProvider] themselves.
@riverpod
User? currentUser(Ref ref) {
  final session = ref.watch(authProvider).value;
  return switch (session) {
    Authenticated(:final user) => user,
    _ => null,
  };
}

/// Returns `true` when the user has a valid, settled [Authenticated] session.
///
/// Use this for gating UI elements that require auth (e.g. showing the FAB
/// to create a new service). Route-level gating is handled by the router
/// guard in `routing/auth_redirect.dart` (Phase 2.9).
@riverpod
bool isAuthenticated(Ref ref) {
  final session = ref.watch(authProvider).value;
  return session is Authenticated;
}
