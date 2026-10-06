// Phase 367 (9.6) — ONE own-avatar treatment on every own-profile surface,
// for every role (Scope update 2): the shared `SelfAvatarEditor` — the 104 dp
// extruded ring, the photo or the Comfortaa monogram, and the 30 dp camel
// camera badge at the bottom-right — pinned per role, with and without a
// photo.
//
//   identity card   SALON_OWNER, SALON_ADMIN   (StaffIdentityCard `avatar:`)
//                   CLIENT                     (HomeProfileCard — Головна)
//                   INDEPENDENT_MASTER / SALON_MASTER: the full-screen
//                   `master_profile_golden_test.dart` /
//                   `salon_master_profile_golden_test.dart` (monogram); the
//                   photo state is the same `SelfAvatarEditor` pinned below
//   edit screen     every role: the «Особисті дані» avatar block — see
//                   `own_avatar_edit_screen_golden_test.dart`.

import 'package:beautica_mobile/core/media/upload/avatar_editor_binding.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/home/domain/home_hub_models.dart';
import 'package:beautica_mobile/features/home/presentation/widgets/home_profile_card.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/staff_identity_card.dart';
import 'package:flutter/material.dart';

import '../helpers/fakes/fake_secure_storage.dart';
import 'helpers/photo_state_golden.dart';

class _Auth extends AuthNotifier {
  _Auth(this._u);
  final User _u;
  @override
  Future<AuthSession> build() async =>
      AuthSession.authenticated(user: _u, accessToken: 't');
}

List<Object> _session(UserRole role, String? avatarUrl) => <Object>[
  authProvider.overrideWith(
    () => _Auth(
      User(
        id: 'u1',
        email: 'me@beautica.test',
        role: role,
        firstName: 'Олена',
        lastName: 'Ковальчук',
        avatarUrl: avatarUrl,
      ),
    ),
  ),
  secureStorageProvider.overrideWithValue(FakeSecureStorage()),
];

const ClientProfileSummary _client = ClientProfileSummary(
  firstName: 'Олена',
  lastName: 'Ковальчук',
  city: 'Львів',
  phone: '+380671234567',
  clientRating: null,
  memberSinceYear: 2024,
);

Widget _staffCard(String Function(AppLocalizations) role) => Padding(
  padding: const EdgeInsets.all(16),
  child: Builder(
    builder: (BuildContext context) => StaffIdentityCard(
      displayName: 'Олена Ковальчук',
      roleLabel: role(AppLocalizations.of(context)),
      avatar: SelfAvatarEditor(initials: avatarMonogram('Олена Ковальчук')),
    ),
  ),
);

void main() {
  registerPhotoGoldenMedia();

  for (final ({String name, String? url}) photo
      in <({String name, String? url})>[
        (name: 'monogram', url: null),
        (name: 'photo', url: kGoldenAllowedUrl),
      ]) {
    photoGolden(
      'own_avatar_identity_owner_${photo.name}',
      () => _staffCard((AppLocalizations l) => l.masterRoleSalonOwner),
      overrides: _session(UserRole.salonOwner, photo.url),
    );
    photoGolden(
      'own_avatar_identity_admin_${photo.name}',
      () => _staffCard((AppLocalizations l) => l.adminOwnProfileRoleLabel),
      overrides: _session(UserRole.salonAdmin, photo.url),
    );
    photoGolden(
      'own_avatar_identity_client_${photo.name}',
      () => Padding(
        padding: const EdgeInsets.all(16),
        child: HomeProfileCard(profile: _client, onLocation: () {}),
      ),
      overrides: _session(UserRole.client, photo.url),
    );
  }
}
