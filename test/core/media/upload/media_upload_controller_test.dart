// Phase 367 (9.6) — the promoted `MediaUploadFlow` behind the self-avatar
// target, run for EVERY role.
//
// The Phase 073 suites (`test/features/master/application/
// avatar_upload_controller*_test.dart`) pin the flow for INDEPENDENT_MASTER;
// this file is the parametrised copy of the load-bearing cases (success,
// 100%-is-not-success, retry, remove, logout drain) across all five roles,
// plus the D3 sink rule: the session `User` is patched for every role,
// `masterProfileProvider` only for the master roles (or when an owner already
// has one cached) — never BUILT for a non-master, which would 403.

import 'dart:async';
import 'dart:io';

import 'package:beautica_mobile/core/media/pick/image_source_sheet.dart';
import 'package:beautica_mobile/core/media/pick/media_pick_service.dart';
import 'package:beautica_mobile/core/media/upload/avatar_upload_controller.dart';
import 'package:beautica_mobile/core/media/upload/media_upload_repository.dart';
import 'package:beautica_mobile/core/media/upload/upload_failure.dart';
import 'package:beautica_mobile/core/media/upload/upload_task.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../pick/scripted_pick_gateway.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';
import '../../../helpers/until.dart';

const String kOld = 'https://media.test/avatars/u1/old.jpg';
const String kNew = 'https://media.test/avatars/u1/new.jpg';

UserRole _role = UserRole.client;

User _user() => User(
  id: 'user-1',
  email: 'a@beautica.ua',
  role: _role,
  firstName: 'Олена',
  lastName: 'Ковальчук',
  avatarUrl: kOld,
);

class _Auth extends AuthNotifier {
  @override
  Future<AuthSession> build() async =>
      AuthSession.authenticated(user: _user(), accessToken: 't');

  void signOut() =>
      state = const AsyncData<AuthSession>(AuthSession.unauthenticated());
}

int _profileBuilds = 0;

class _CountingProfile extends MasterProfile {
  @override
  Future<Master> build() {
    _profileBuilds++;
    return Future<Master>.value(
      const Master(
        id: 'm1',
        firstName: 'Олена',
        lastName: 'Ковальчук',
        avgRating: 0,
        reviewCount: 0,
        type: MasterType.independentMaster,
        avatarUrl: kOld,
      ),
    );
  }
}

class _FakeUploads implements MediaUploadRepository {
  final List<File> uploaded = <File>[];
  int deleteCalls = 0;
  late Completer<String> result;
  late StreamController<double> progress;

  @override
  UploadTask<String> uploadAvatar(File file) {
    uploaded.add(file);
    result = Completer<String>();
    progress = StreamController<double>.broadcast();
    return UploadTask<String>(
      progress: progress.stream,
      result: result.future,
      onCancel: () {
        if (!result.isCompleted) {
          result.completeError(const UploadCancelledFailure());
        }
      },
    );
  }

  @override
  Future<void> deleteAvatar() async => deleteCalls++;
}

bool _isMaster(UserRole r) =>
    r == UserRole.independentMaster || r == UserRole.salonMaster;

void main() {
  late Directory scratch;
  late Directory outside;
  late ScriptedPickGateway gw;
  late _FakeUploads uploads;
  late ProviderContainer container;

  Future<void> boot(UserRole role) async {
    _role = role;
    _profileBuilds = 0;
    scratch = Directory.systemTemp.createTempSync('media_flow_scratch');
    outside = Directory.systemTemp.createTempSync('media_flow_out');
    gw = ScriptedPickGateway(scratch: scratch, outside: outside);
    uploads = _FakeUploads();
    container = ProviderContainer(
      overrides: [
        mediaPickServiceProvider.overrideWithValue(
          MediaPickService(gw, tempDir: () async => scratch),
        ),
        mediaUploadRepositoryProvider.overrideWithValue(uploads),
        masterProfileProvider.overrideWith(_CountingProfile.new),
        secureStorageProvider.overrideWithValue(FakeSecureStorage()),
        authProvider.overrideWith(_Auth.new),
      ],
    );
    addTearDown(() {
      container.dispose();
      scratch.deleteSync(recursive: true);
      outside.deleteSync(recursive: true);
    });
    await container.read(authProvider.future);
    container.listen(avatarUploadControllerProvider, (_, _) {});
  }

  AvatarUploadController ctrl() =>
      container.read(avatarUploadControllerProvider.notifier);
  AvatarUploadState current() => container.read(avatarUploadControllerProvider);
  String? sessionAvatar() => switch (container.read(authProvider).value) {
    Authenticated(:final user) => user.avatarUrl,
    _ => null,
  };

  for (final UserRole role in UserRole.values) {
    group('selfAvatar as ${role.name}', () {
      test(
        'success patches the session user in place (no /users/me); the '
        'master profile ${_isMaster(role) ? 'too' : 'is never built'}',
        () async {
          await boot(role);
          if (_isMaster(role)) {
            await container.read(masterProfileProvider.future);
          }
          final Future<AvatarChangeResult> f = ctrl().change(
            ImageSourceChoice.gallery,
          );
          await until(() => uploads.uploaded.isNotEmpty);
          uploads.result.complete(kNew);

          expect(await f, isA<AvatarChangeSucceeded>());
          expect(sessionAvatar(), kNew);
          expect(current(), isA<AvatarIdle>());
          if (_isMaster(role)) {
            expect(
              container.read(masterProfileProvider).value?.avatarUrl,
              kNew,
            );
            expect(_profileBuilds, 1, reason: 'patched, not refetched');
          } else {
            expect(
              _profileBuilds,
              0,
              reason: 'GET /masters/me would 403 for ${role.name}',
            );
          }
        },
      );

      test('100% is not success: a 503 after the last byte keeps the photo '
          'for retry and leaves the session avatar untouched', () async {
        await boot(role);
        final Future<AvatarChangeResult> f = ctrl().change(
          ImageSourceChoice.gallery,
        );
        await until(() => uploads.uploaded.isNotEmpty);
        uploads.progress.add(1.0);
        await until(() => (current() as AvatarUploading).progress == 1.0);
        uploads.result.completeError(const UploadStorageUnavailableFailure());

        expect(await f, isA<AvatarChangeFailed>());
        expect(sessionAvatar(), kOld);
        expect((current() as AvatarFailed).previewFile.existsSync(), isTrue);
      });

      test('retry re-sends the SAME file without the picker', () async {
        await boot(role);
        final Future<AvatarChangeResult> f = ctrl().change(
          ImageSourceChoice.gallery,
        );
        await until(() => uploads.uploaded.isNotEmpty);
        uploads.result.completeError(const UploadNetworkFailure());
        expect(await f, isA<AvatarChangeFailed>());

        final Future<AvatarChangeResult> retry = ctrl().retry();
        await until(() => uploads.uploaded.length == 2);
        expect(uploads.uploaded.last.path, uploads.uploaded.first.path);
        expect(gw.pickSources, hasLength(1));
        uploads.result.complete(kNew);
        expect(await retry, isA<AvatarChangeSucceeded>());
        expect(sessionAvatar(), kNew);
      });

      test('remove clears the session avatar', () async {
        await boot(role);
        expect(await ctrl().remove(), isA<AvatarChangeSucceeded>());
        expect(uploads.deleteCalls, 1);
        expect(sessionAvatar(), isNull);
      });

      test('logout drains: the kept failed file is deleted and retry is '
          'impossible', () async {
        await boot(role);
        final Future<AvatarChangeResult> f = ctrl().change(
          ImageSourceChoice.gallery,
        );
        await until(() => uploads.uploaded.isNotEmpty);
        uploads.result.completeError(const UploadNetworkFailure());
        await f;
        final File kept = (current() as AvatarFailed).previewFile;

        (container.read(authProvider.notifier) as _Auth).signOut();
        await until(() => current() is AvatarIdle);

        expect(kept.existsSync(), isFalse);
        expect(await ctrl().retry(), isA<AvatarChangeCancelled>());
        expect(uploads.uploaded, hasLength(1));
      });
    });
  }

  test('an owner whose master profile is ALREADY cached gets it patched too '
      '(owner-as-master), without a refetch', () async {
    await boot(UserRole.salonOwner);
    await container.read(masterProfileProvider.future);
    final Future<AvatarChangeResult> f = ctrl().change(
      ImageSourceChoice.gallery,
    );
    await until(() => uploads.uploaded.isNotEmpty);
    uploads.result.complete(kNew);
    await f;

    expect(container.read(masterProfileProvider).value?.avatarUrl, kNew);
    expect(_profileBuilds, 1);
  });

  test('AuthNotifier.patchAvatarUrl is a no-op without a settled session', () {
    final ProviderContainer c = ProviderContainer(
      overrides: [
        authProvider.overrideWith(_Auth.new),
        secureStorageProvider.overrideWithValue(FakeSecureStorage()),
      ],
    );
    addTearDown(c.dispose);
    // Still AsyncLoading — nothing to patch.
    expect(c.read(authProvider.notifier).patchAvatarUrl(kNew), isFalse);
  });
}
