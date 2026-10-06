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
import 'package:beautica_mobile/core/media/pick/media_kind.dart';
import 'package:beautica_mobile/core/media/pick/media_pick_service.dart';
import 'package:beautica_mobile/core/media/pick/pending_pick_store.dart';
import 'package:beautica_mobile/core/media/upload/avatar_upload_controller.dart';
import 'package:beautica_mobile/core/media/upload/salon_image_upload_controller.dart';
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
import 'package:beautica_mobile/features/salon/application/my_salons_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_management_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_staff_member.dart';
import 'package:beautica_mobile/l10n/app_localizations_uk.dart';
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

  /// Phase 369 — `(salonId, slot)` of every salon upload / delete.
  final List<(String, SalonImageSlot)> salonUploads =
      <(String, SalonImageSlot)>[];
  final List<(String, SalonImageSlot)> salonDeletes =
      <(String, SalonImageSlot)>[];
  UploadFailure? salonDeleteFailure;

  @override
  UploadTask<String> uploadSalonImage(
    String salonId,
    SalonImageSlot slot,
    File file,
  ) {
    salonUploads.add((salonId, slot));
    return uploadAvatar(file);
  }

  @override
  Future<void> deleteSalonImage(String salonId, SalonImageSlot slot) async {
    salonDeletes.add((salonId, slot));
    final UploadFailure? f = salonDeleteFailure;
    if (f != null) throw f;
  }
}

// ── Phase 369 — salon logo / cover fixtures ────────────────────────────────

const String kSalonA = 'salon-a';
const String kSalonB = 'salon-b';
const String kLogo = 'https://media.test/salons/a/logo.jpg';
const String kCover = 'https://media.test/salons/a/cover.jpg';

Salon _salon(String id) => Salon(id: id, name: 'Салон $id');

int _manageBuilds = 0;
int _mySalonsBuilds = 0;

class _Manage extends SalonManagementProfile {
  @override
  Future<SalonManagementProfileData> build(String salonId) async {
    _manageBuilds++;
    return (_salon(salonId), const <SalonStaffMember>[]);
  }
}

class _MySalons extends MySalons {
  @override
  Future<List<Salon>> build() async {
    _mySalonsBuilds++;
    return <Salon>[_salon(kSalonA), _salon(kSalonB)];
  }
}

bool _isMaster(UserRole r) =>
    r == UserRole.independentMaster || r == UserRole.salonMaster;

void main() {
  late Directory scratch;
  late Directory outside;
  late ScriptedPickGateway gw;
  late _FakeUploads uploads;
  late ProviderContainer container;

  late FakeSecureStorage storage;

  Future<void> boot(UserRole role) async {
    _role = role;
    _profileBuilds = 0;
    _manageBuilds = 0;
    _mySalonsBuilds = 0;
    storage = FakeSecureStorage();
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
        secureStorageProvider.overrideWithValue(storage),
        authProvider.overrideWith(_Auth.new),
        salonManagementProfileProvider.overrideWith(_Manage.new),
        mySalonsProvider.overrideWith(_MySalons.new),
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

  // ── Phase 369 — salon logo / cover targets ───────────────────────────────

  group('salon image targets (owner)', () {
    SalonImageUploadController salonCtrl(String id, SalonImageSlot slot) =>
        container.read(salonImageUploadControllerProvider(id, slot).notifier);
    Salon managed(String id) =>
        container.read(salonManagementProfileProvider(id)).value!.$1;
    Salon listed(String id) => container
        .read(mySalonsProvider)
        .value!
        .firstWhere((Salon s) => s.id == id);

    Future<void> bootOwner() async {
      await boot(UserRole.salonOwner);
      for (final String id in <String>[kSalonA, kSalonB]) {
        for (final SalonImageSlot slot in SalonImageSlot.values) {
          container.listen(
            salonImageUploadControllerProvider(id, slot),
            (_, _) {},
          );
        }
      }
      container.listen(salonManagementProfileProvider(kSalonA), (_, _) {});
      container.listen(mySalonsProvider, (_, _) {});
      await container.read(salonManagementProfileProvider(kSalonA).future);
      await container.read(mySalonsProvider.future);
    }

    for (final (SalonImageSlot slot, String url, MediaKind kind)
        in <(SalonImageSlot, String, MediaKind)>[
          (SalonImageSlot.logo, kLogo, MediaKind.salonLogo),
          (SalonImageSlot.cover, kCover, MediaKind.salonCover),
        ]) {
      test('${slot.name}: the binding uploads to (salonA, ${slot.name}) with '
          'the ${kind.name} crop spec and patches the management profile + '
          'the hub list IN PLACE (no refetch)', () async {
        await bootOwner();
        final Future<AvatarChangeResult> f = salonCtrl(
          kSalonA,
          slot,
        ).change(ImageSourceChoice.gallery);
        await until(() => uploads.salonUploads.isNotEmpty);
        expect(uploads.salonUploads.single, (kSalonA, slot));
        expect(gw.cropSpecs.single, same(kind.spec));
        uploads.result.complete(url);

        expect(await f, isA<AvatarChangeSucceeded>());
        final Salon m = managed(kSalonA);
        final Salon l = listed(kSalonA);
        expect(
          slot == SalonImageSlot.logo ? m.avatarUrl : m.coverImageUrl,
          url,
        );
        expect(
          slot == SalonImageSlot.logo ? l.avatarUrl : l.coverImageUrl,
          url,
        );
        expect(
          slot == SalonImageSlot.logo ? m.coverImageUrl : m.avatarUrl,
          isNull,
          reason: 'only the uploaded slot changes',
        );
        expect(listed(kSalonB).avatarUrl, isNull, reason: 'other salon');
        expect(listed(kSalonB).coverImageUrl, isNull);
        expect(_manageBuilds, 1, reason: 'patched, not refetched');
        expect(_mySalonsBuilds, 1, reason: 'patched, not refetched');
        expect(sessionAvatar(), kOld, reason: 'never the personal avatar');
      });

      test('${slot.name}: remove deletes (salonA, ${slot.name}) and clears '
          'it in place', () async {
        await bootOwner();
        final Future<AvatarChangeResult> up = salonCtrl(
          kSalonA,
          slot,
        ).change(ImageSourceChoice.gallery);
        await until(() => uploads.salonUploads.isNotEmpty);
        uploads.result.complete(url);
        await up;

        expect(
          await salonCtrl(kSalonA, slot).remove(),
          isA<AvatarChangeSucceeded>(),
        );
        expect(uploads.salonDeletes.single, (kSalonA, slot));
        final Salon m = managed(kSalonA);
        expect(
          slot == SalonImageSlot.logo ? m.avatarUrl : m.coverImageUrl,
          isNull,
        );
        expect(_manageBuilds, 1);
      });
    }

    test('the cover is cropped 16:9 and encoded at ≤1600×900 q80; the logo '
        '1:1 at the avatar size', () async {
      await bootOwner();
      final Future<AvatarChangeResult> cover = salonCtrl(
        kSalonA,
        SalonImageSlot.cover,
      ).change(ImageSourceChoice.gallery);
      await until(() => uploads.salonUploads.isNotEmpty);
      uploads.result.complete(kCover);
      await cover;
      final MediaSpec spec = gw.cropSpecs.single;
      expect((spec.aspectX, spec.aspectY, spec.circle), (16, 9, false));
      expect(gw.compressDims.single, (1600, 900));
      expect(gw.compressCalls.single.quality, 80);

      final Future<AvatarChangeResult> logo = salonCtrl(
        kSalonA,
        SalonImageSlot.logo,
      ).change(ImageSourceChoice.gallery);
      await until(() => uploads.salonUploads.length == 2);
      uploads.result.complete(kLogo);
      await logo;
      expect(gw.cropSpecs.last.aspectX, gw.cropSpecs.last.aspectY);
      expect(gw.compressDims.last, (
        MediaKind.avatar.spec.maxWidth,
        MediaKind.avatar.spec.maxHeight,
      ));
      expect(gw.compressCalls.last.quality, 85, reason: 'default q85');
    });

    test('a 403 on a salon image is the owner-only forbidden failure and '
        'leaves the salon unchanged', () async {
      await bootOwner();
      uploads.salonDeleteFailure = const UploadForbiddenFailure(
        salonOwnerOnly: true,
      );
      final AvatarChangeResult r = await salonCtrl(
        kSalonA,
        SalonImageSlot.cover,
      ).remove();
      final UploadFailure failure = (r as AvatarChangeFailed).failure;
      expect(failure, isA<UploadForbiddenFailure>());
      expect(
        failure.message(AppLocalizationsUk()),
        'Змінювати фото салону може лише власник',
      );
      expect(managed(kSalonA), _salon(kSalonA));
    });

    test('100% is not success: a 503 after the last byte keeps the cover '
        'for retry and leaves the salon untouched', () async {
      await bootOwner();
      final SalonImageUploadController c = salonCtrl(
        kSalonA,
        SalonImageSlot.cover,
      );
      final Future<AvatarChangeResult> f = c.change(ImageSourceChoice.gallery);
      await until(() => uploads.salonUploads.isNotEmpty);
      uploads.progress.add(1.0);
      uploads.result.completeError(const UploadStorageUnavailableFailure());
      expect(await f, isA<AvatarChangeFailed>());
      expect(managed(kSalonA).coverImageUrl, isNull);
      expect(
        container.read(
          salonImageUploadControllerProvider(kSalonA, SalonImageSlot.cover),
        ),
        isA<AvatarFailed>(),
      );
    });

    test('the pending tag carries the per-salon key', () async {
      await bootOwner();
      gw.holdPick = Completer<void>();
      final Future<AvatarChangeResult> f = salonCtrl(
        kSalonA,
        SalonImageSlot.logo,
      ).change(ImageSourceChoice.gallery);
      await until(() => gw.pickedPath != null);
      final PendingPick? tag = await PendingPickStore(storage).read();
      expect(tag?.kind, MediaKind.salonLogo);
      expect(tag?.scope, 'salonLogo:$kSalonA');
      gw.holdPick!.complete();
      await until(() => uploads.salonUploads.isNotEmpty);
      uploads.result.complete(kLogo);
      await f;
    });

    test('a lost pick for salon A is drained, never resumed, while salon B '
        'recovers', () async {
      await bootOwner();
      await PendingPickStore(
        storage,
      ).begin('user-1', MediaKind.salonLogo, scope: 'salonLogo:$kSalonA');
      gw.lost = 'x';

      expect(
        await salonCtrl(kSalonB, SalonImageSlot.logo).recoverLost(),
        isA<AvatarChangeCancelled>(),
      );
      expect(uploads.salonUploads, isEmpty, reason: 'never lands on B');
      expect(File(gw.pickedPath!).existsSync(), isFalse, reason: 'drained');
      expect(await PendingPickStore(storage).read(), isNull);
    });

    test('a lost pick for salon A IS resumed by salon A', () async {
      await bootOwner();
      await PendingPickStore(
        storage,
      ).begin('user-1', MediaKind.salonLogo, scope: 'salonLogo:$kSalonA');
      gw.lost = 'x';

      final Future<AvatarChangeResult> r = salonCtrl(
        kSalonA,
        SalonImageSlot.logo,
      ).recoverLost();
      await until(() => uploads.salonUploads.isNotEmpty);
      expect(uploads.salonUploads.single, (kSalonA, SalonImageSlot.logo));
      uploads.result.complete(kLogo);
      expect(await r, isA<AvatarChangeSucceeded>());
      expect(managed(kSalonA).avatarUrl, kLogo);
    });

    test('an own-avatar recovery drains a salon-scoped tag (and vice '
        'versa: a salon recovery drains an avatar tag)', () async {
      await bootOwner();
      await PendingPickStore(
        storage,
      ).begin('user-1', MediaKind.salonLogo, scope: 'salonLogo:$kSalonA');
      gw.lost = 'x';
      expect(await ctrl().recoverLost(), isA<AvatarChangeCancelled>());
      expect(uploads.uploaded, isEmpty);

      await PendingPickStore(storage).begin('user-1', MediaKind.avatar);
      expect(
        await salonCtrl(kSalonA, SalonImageSlot.logo).recoverLost(),
        isA<AvatarChangeCancelled>(),
      );
      expect(uploads.uploaded, isEmpty);
    });

    test('logout drains a kept failed salon photo', () async {
      await bootOwner();
      final SalonImageUploadController c = salonCtrl(
        kSalonA,
        SalonImageSlot.logo,
      );
      final Future<AvatarChangeResult> f = c.change(ImageSourceChoice.gallery);
      await until(() => uploads.salonUploads.isNotEmpty);
      uploads.result.completeError(const UploadNetworkFailure());
      await f;
      final File kept =
          (container.read(
                    salonImageUploadControllerProvider(
                      kSalonA,
                      SalonImageSlot.logo,
                    ),
                  )
                  as AvatarFailed)
              .previewFile;
      (container.read(authProvider.notifier) as _Auth).signOut();
      await until(() => !kept.existsSync());
      expect(
        await salonCtrl(kSalonA, SalonImageSlot.logo).retry(),
        isA<AvatarChangeCancelled>(),
      );
    });
  });
}
