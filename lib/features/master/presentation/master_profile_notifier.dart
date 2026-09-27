// Phase 4.2 — MasterProfile AsyncNotifier.
//
// Loads the authenticated master's profile via [MasterRepository.getMyProfile].
// The user ID is derived from the [authProvider] session so the notifier never
// needs a parameter — it is a keepAlive singleton that every screen reading
// the master's name can watch without causing redundant network calls.
//
// [keepAlive: true] is intentional — the profile is needed on multiple screens
// (nav header, calendar, services) so disposing and refetching on every
// navigation would waste bandwidth. Call [refresh()] explicitly when the user
// saves profile edits (Phase 4.3).

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/errors/failures.dart';
import '../../auth/domain/auth_session.dart';
import '../../auth/presentation/auth_notifier.dart';
import '../data/master_repository.dart';
import '../domain/master.dart';

part 'master_profile_notifier.g.dart';

/// Loads and caches the authenticated INDEPENDENT_MASTER's own profile.
///
/// Generated provider name: `masterProfileProvider`.
@Riverpod(keepAlive: true)
class MasterProfile extends _$MasterProfile {
  @override
  Future<Master> build() {
    // NARROWED with `.select` (mobile-perf MEDIUM, 2026-08-31) — this used to
    // watch the whole `AsyncValue<AuthSession>`. `AuthNotifier.setAccessToken`
    // is called by `refresh_interceptor.dart` on EVERY silent token refresh
    // and emits a new `Authenticated` carrying the same user with a new
    // accessToken; un-narrowed, that re-emission refetched `GET /masters/me`
    // every single time, and every downstream of this keepAlive provider
    // re-ran with it (`ownerOwnProfileProvider` then also refired an uncached
    // `GET /masters/{id}/services`, while the owner sat on another tab).
    //
    // Only the authenticated user's IDENTITY can invalidate this profile, so
    // that is all that is watched. In-repo idiom: `master_service_catalog
    // _provider.dart`'s identical fix, and `working_hours_repository
    // _provider.dart`'s `masterProfileProvider.select(...)`.
    //
    // `null` still means "not authenticated" — a logout flips the selected
    // value from the user id to null, which rebuilds this provider exactly as
    // the un-narrowed watch did (`auth_notifier_test.dart` pins that).
    //
    // The selector itself was PROMOTED to [authUserIdOrNull] (2026-09-01) once
    // five more sites needed it — one definition, not seven copies. `.select`
    // compares the selected `String?`, never the closure identity, so sharing
    // the function is behaviourally identical to the inline switch it replaced.
    final String? userId = ref.watch(authProvider.select(authUserIdOrNull));
    if (userId == null) {
      throw const UnauthorizedFailure();
    }
    // Fix 5 (PERF MEDIUM-3): masterRepositoryProvider is a keepAlive singleton
    // that never emits a new value — ref.watch creates an unnecessary reactive
    // subscription. ref.read is correct here for a one-shot async fetch.
    return ref.read(masterRepositoryProvider).getMyProfile(userId);
  }

  /// Re-fetches the profile. Call after the user saves edits (Phase 4.3).
  Future<void> refresh() async {
    state = const AsyncLoading();
    final session = ref.read(authProvider).value;
    if (session is! Authenticated) {
      state = AsyncError(const UnauthorizedFailure(), StackTrace.current);
      return;
    }
    if (kDebugMode) {
      log(
        'MasterProfile: refreshing for user ${session.user.id}',
        name: 'feature.master',
        level: 800,
      );
    }
    state = await AsyncValue.guard(
      () => ref.read(masterRepositoryProvider).getMyProfile(session.user.id),
    );
  }
}
