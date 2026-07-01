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

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/errors/failures.dart';
import '../../auth/domain/auth_session.dart';
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
    final session = ref.watch(authProvider).value;
    if (session is! Authenticated) {
      throw const UnauthorizedFailure();
    }
    // clientProfileRepositoryProvider is a keepAlive singleton that never emits
    // a new value — ref.read is correct for a one-shot async fetch.
    return ref.read(clientProfileRepositoryProvider).getMyProfile();
  }
}
