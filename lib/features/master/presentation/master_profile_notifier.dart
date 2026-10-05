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

/// [master] with its avatar dropped — the `selectAsync` key for a loader that
/// composes `masterProfileProvider` but never renders the master-row avatar
/// (Phase 367 fix). [MasterProfile.patchAvatarUrl] replaces the cached
/// [Master]; a plain `.future` watch would rebuild such a loader — re-firing
/// its downstream reads and flashing its screen's loading branch — for a
/// field it does not show. Selecting through this keeps every OTHER field
/// reactive (freezed value equality) while an avatar-only patch is a no-op.
Master masterIgnoringAvatar(Master master) => master.copyWith(avatarUrl: null);

/// The `.select` key for a WIDGET that branches on `masterProfileProvider`'s
/// [AsyncValue] but never renders the avatar (Phase 367 audit, perf LOW) —
/// the widget-side sibling of [masterIgnoringAvatar]. Use as
/// `ref.watch(masterProfileProvider.select(MasterProfileIgnoringAvatar.new))
/// .profile`.
///
/// [profile] is passed through UNCHANGED (same loading / refresh / error
/// semantics as a bare watch — `whenData` would drop a refresh's previous
/// value), but equality ignores the avatar: an avatar-only
/// [MasterProfile.patchAvatarUrl] does not rebuild the watcher, while every
/// other change (another field, loading, error, a new value) still does. The
/// avatar itself is rendered by a separate narrow watch
/// ([masterAvatarUrlOrNull]). Because a skipped notification keeps the OLD
/// selection, [profile]'s `avatarUrl` may be stale — never read it.
@immutable
final class MasterProfileIgnoringAvatar {
  MasterProfileIgnoringAvatar(this.profile)
    : _key = (
        profile.runtimeType,
        profile.isLoading,
        profile.error,
        switch (profile.value) {
          final Master master => masterIgnoringAvatar(master),
          null => null,
        },
      );

  /// The watched state, as-is.
  final AsyncValue<Master> profile;

  final (Type, bool, Object?, Master?) _key;

  @override
  bool operator ==(Object other) =>
      other is MasterProfileIgnoringAvatar && other._key == _key;

  @override
  int get hashCode => _key.hashCode;
}

/// The cached master's avatar URL, or `null` — the narrow `.select` for the
/// one widget that renders the master-row photo.
String? masterAvatarUrlOrNull(AsyncValue<Master> profile) =>
    profile.value?.avatarUrl;

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

  /// Writes [url] (null = removed) into the CACHED profile without a refetch.
  ///
  /// Phase 073 audit — `POST/DELETE /media/avatar` already returns the new
  /// state, so invalidating (a `GET /masters/me` plus every provider watching
  /// this one) would be pure waste. Returns `false` when there is no cached
  /// profile to patch; the caller then falls back to an invalidate.
  bool patchAvatarUrl(String? url) {
    final Master? current = state.value;
    if (current == null) return false;
    state = AsyncData<Master>(current.copyWith(avatarUrl: url));
    return true;
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
