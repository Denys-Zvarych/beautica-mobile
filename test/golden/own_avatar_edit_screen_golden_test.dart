// Phase 367 (9.6) — the «Особисті дані» avatar block, per role, with and
// without a photo. Every role gets the SAME live editor:
//   CLIENT / SALON_ADMIN / SALON_OWNER  `ClientPersonalInfoEditScreen`
//   INDEPENDENT_MASTER / SALON_MASTER   `PersonalInfoEditScreen` (monogram +
//                                       failed states: the D5 promotion proof
//                                       in `personal_info_edit_avatar_golden_test.dart`)

import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/home/application/client_edit_profile_notifier.dart';
import 'package:beautica_mobile/features/home/presentation/client_personal_info_edit_screen.dart';
import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/presentation/personal_info_edit_screen.dart';
import 'package:flutter/material.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/fakes/fake_secure_storage.dart';
import 'helpers/photo_state_golden.dart';

class _MockMasterRepository extends Mock implements MasterRepository {}

User _user(UserRole role, String? url) => User(
  id: 'u1',
  email: 'me@beautica.test',
  role: role,
  firstName: 'Олена',
  lastName: 'Ковальчук',
  avatarUrl: url,
);

class _Auth extends AuthNotifier {
  _Auth(this._u);
  final User _u;
  @override
  Future<AuthSession> build() async =>
      AuthSession.authenticated(user: _u, accessToken: 't');
}

class _EditProfile extends ClientEditProfile {
  _EditProfile(this._u);
  final User _u;
  @override
  Future<User> build() async => _u;
}

class _Profile extends MasterProfile {
  _Profile(this._m);
  final Master _m;
  @override
  Future<Master> build() async => _m;
}

const Size _size = Size(360, 900);

void main() {
  registerPhotoGoldenMedia();

  for (final ({String name, String? url}) photo
      in <({String name, String? url})>[
        (name: 'monogram', url: null),
        (name: 'photo', url: kGoldenAllowedUrl),
      ]) {
    for (final UserRole role in <UserRole>[
      UserRole.client,
      UserRole.salonAdmin,
      UserRole.salonOwner,
    ]) {
      final User u = _user(role, photo.url);
      photoGolden(
        'own_avatar_edit_${role.name}_${photo.name}',
        () => const ClientPersonalInfoEditScreen(),
        size: _size,
        overrides: <Object>[
          authProvider.overrideWith(() => _Auth(u)),
          clientEditProfileProvider.overrideWith(() => _EditProfile(u)),
          secureStorageProvider.overrideWithValue(FakeSecureStorage()),
        ],
      );
    }
  }

  // The master roles' photo state (monogram is the D5 proof file).
  for (final ({UserRole role, MasterType type}) m
      in <({UserRole role, MasterType type})>[
        (role: UserRole.independentMaster, type: MasterType.independentMaster),
        (role: UserRole.salonMaster, type: MasterType.salonMaster),
      ]) {
    photoGolden(
      'own_avatar_edit_${m.role.name}_photo',
      () => const PersonalInfoEditScreen(),
      size: _size,
      overrides: <Object>[
        authProvider.overrideWith(
          () => _Auth(_user(m.role, kGoldenAllowedUrl)),
        ),
        masterProfileProvider.overrideWith(
          () => _Profile(
            Master(
              id: 'u1',
              firstName: 'Олена',
              lastName: 'Ковальчук',
              avgRating: 0,
              reviewCount: 0,
              type: m.type,
              avatarUrl: kGoldenAllowedUrl,
            ),
          ),
        ),
        masterRepositoryProvider.overrideWithValue(_MockMasterRepository()),
        secureStorageProvider.overrideWithValue(FakeSecureStorage()),
      ],
    );
  }
}
