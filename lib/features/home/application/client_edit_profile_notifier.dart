// CLIENT edit-profile AsyncNotifier.
//
// Loads and caches the authenticated CLIENT's FULL [User] profile (including the
// location fields the home-hub summary does not carry) via
// [ClientProfileRepository.getMyProfile] (`GET /users/me`). The three client
// edit screens (Personal / Contacts / Location) watch this notifier so they all
// seed their fields from one cached source and merge their slice onto it on save
// — exactly the role the [masterProfileProvider] plays for the master edit
// screens.
//
// [keepAlive: true] mirrors [masterProfileProvider]: the cached profile is read
// by every edit screen, so disposing + refetching on each navigation would waste
// bandwidth. Each edit screen calls `ref.invalidate(clientEditProfileProvider)`
// after a successful save to force a re-fetch.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/errors/failures.dart';
import '../../auth/domain/user.dart';
import '../../auth/presentation/auth_notifier.dart';
import '../data/client_profile_repository.dart';

part 'client_edit_profile_notifier.g.dart';

/// Loads and caches the authenticated CLIENT's own full [User] profile.
///
/// Generated provider name: `clientEditProfileProvider`.
@Riverpod(keepAlive: true)
class ClientEditProfile extends _$ClientEditProfile {
  @override
  Future<User> build() {
    // NARROWED with `.select` (mobile-perf MEDIUM follow-through, 2026-08-31)
    // — the same fix, for the same reason, as `master_profile_notifier.dart`'s
    // own `build()`. `AuthNotifier.setAccessToken` re-emits `Authenticated`
    // with a new accessToken on EVERY silent token refresh; watching the whole
    // `AsyncValue<AuthSession>` refetched `GET /users/me` each time. Narrowing
    // only `masterProfileProvider` would have closed half the leak: this
    // provider is the OTHER upstream of `ownerOwnProfileProvider`, so a silent
    // refresh would still have re-run that loader (and its uncached
    // `GET /masters/{id}/services`) while the owner sat on another tab.
    //
    // The selector itself was PROMOTED to [authUserIdOrNull] (2026-09-01) —
    // see its doc for why there is one definition rather than a copy per site.
    final String? userId = ref.watch(authProvider.select(authUserIdOrNull));
    if (userId == null) {
      throw const UnauthorizedFailure();
    }
    // clientProfileRepositoryProvider is a keepAlive singleton that never emits
    // a new value — ref.read is correct for a one-shot async fetch.
    return ref.read(clientProfileRepositoryProvider).getMyProfile();
  }
}
