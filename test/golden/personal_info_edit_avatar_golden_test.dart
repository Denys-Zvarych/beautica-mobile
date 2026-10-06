// Phase 367 (9.6) — D5 promotion proof for the master «Особисті дані».
//
// The avatar wiring (`_onAvatarTap`, `_buildAvatarEditor`, …) was PROMOTED out
// of `PersonalInfoEditScreen` into `AvatarEditorBinding`
// (`lib/core/media/upload/avatar_editor_binding.dart`). These baselines were
// generated from the PRE-promotion screen (HEAD `3e055e06`) and then re-run,
// unchanged, against the promoted screen: the render is byte-identical.
//
// Scenarios: no photo (monogram, idle) and a failed upload (kept photo + retry
// target). The failed preview file does not exist, so `LocalPreviewImage`
// paints its deterministic camel-gradient fallback.

import 'dart:io';

import 'package:alchemist/alchemist.dart' show PumpWidget;
import 'package:beautica_mobile/core/media/upload/upload_failure.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/master/application/avatar_upload_controller.dart';
import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/presentation/personal_info_edit_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/fakes/fake_secure_storage.dart';
import 'helpers/golden_pump.dart';

class _MockMasterRepository extends Mock implements MasterRepository {}

const User _user = User(
  id: 'user-1',
  email: 'olena@beautica.ua',
  role: UserRole.independentMaster,
  firstName: 'Олена',
  lastName: 'Ковальчук',
);

const Master _master = Master(
  id: 'user-1',
  firstName: 'Олена',
  lastName: 'Ковальчук',
  avgRating: 4.8,
  reviewCount: 10,
  type: MasterType.independentMaster,
);

class _StubAuth extends AuthNotifier {
  @override
  Future<AuthSession> build() async =>
      const AuthSession.authenticated(user: _user, accessToken: 't');
}

class _StubProfile extends MasterProfile {
  @override
  Future<Master> build() async => _master;
}

/// Pins the controller in one display state.
class _PinnedController extends AvatarUploadController {
  _PinnedController(this._state);
  final AvatarUploadState _state;
  @override
  AvatarUploadState build() => _state;
}

PumpWidget _pump(AvatarUploadState state) => goldenPumpWidget(
  width: 360,
  overrides: <Object>[
    authProvider.overrideWith(_StubAuth.new),
    masterProfileProvider.overrideWith(_StubProfile.new),
    masterRepositoryProvider.overrideWithValue(_MockMasterRepository()),
    secureStorageProvider.overrideWithValue(FakeSecureStorage()),
    avatarUploadControllerProvider.overrideWith(() => _PinnedController(state)),
  ],
);

void main() {
  goldenTest(
    'master personal info — avatar idle (monogram)',
    fileName: 'personal_info_edit_avatar_idle_360_1x',
    constraints: BoxConstraints.tight(const Size(360, kGoldenHeight)),
    pumpWidget: _pump(const AvatarUploadState.idle()),
    builder: () => const PersonalInfoEditScreen(),
  );

  goldenTest(
    'master personal info — avatar upload failed (retry)',
    fileName: 'personal_info_edit_avatar_failed_360_1x',
    constraints: BoxConstraints.tight(const Size(360, kGoldenHeight)),
    pumpWidget: _pump(
      AvatarUploadState.failed(
        previewFile: File('/nonexistent/media_upload/kept.jpg'),
        failure: const UploadStorageUnavailableFailure(),
      ),
    ),
    builder: () => const PersonalInfoEditScreen(),
  );
}
