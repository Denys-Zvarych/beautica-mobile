// Phase 073 QA — controller gaps: concurrency matrix, crop-label hand-off,
// and DESIRED-behaviour pins (skipped until the pending fixes land).

import 'dart:async';
import 'dart:io';

import 'package:beautica_mobile/core/media/pick/crop_labels.dart';
import 'package:beautica_mobile/core/media/pick/image_source_sheet.dart';
import 'package:beautica_mobile/core/media/pick/media_kind.dart';
import 'package:beautica_mobile/core/media/pick/pending_pick_store.dart';
import 'package:beautica_mobile/core/media/pick/media_pick_service.dart';
import 'package:beautica_mobile/core/media/upload/media_upload_repository.dart';
import 'package:beautica_mobile/core/media/upload/upload_failure.dart';
import 'package:beautica_mobile/core/media/upload/upload_task.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/master/application/avatar_upload_controller.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/media/pick/scripted_pick_gateway.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';
import '../../../helpers/until.dart';

const Master _master = Master(
  id: 'm1',
  firstName: 'Олена',
  lastName: 'Ковальчук',
  avgRating: 0,
  reviewCount: 0,
  type: MasterType.independentMaster,
);

const User _user = User(
  id: 'user-1',
  email: 'a@beautica.ua',
  role: UserRole.independentMaster,
  firstName: 'Олена',
  lastName: 'Ковальчук',
);

class _Auth extends AuthNotifier {
  @override
  Future<AuthSession> build() async =>
      const AuthSession.authenticated(user: _user, accessToken: 't');

  /// Signs in as another user: the controller rebuilds (→ disposes).
  void switchTo(String id) => state = AsyncData<AuthSession>(
    AuthSession.authenticated(
      user: User(
        id: id,
        email: '$id@beautica.ua',
        role: UserRole.independentMaster,
        firstName: 'Олена',
        lastName: 'Ковальчук',
      ),
      accessToken: 't',
    ),
  );
}

/// Holds `readPendingPick` until [gate] completes (recovery-probe window).
class _GatedStorage extends FakeSecureStorage {
  Completer<void>? gate;
  int reads = 0;

  @override
  Future<String?> readPendingPick() async {
    reads++;
    await gate?.future;
    return super.readPendingPick();
  }
}

class _Profile extends MasterProfile {
  @override
  Future<Master> build() => Future<Master>.value(_master);
}

class _Uploads implements MediaUploadRepository {
  final List<File> uploaded = <File>[];
  int deleteCalls = 0;
  Completer<void>? holdDelete;
  late Completer<String> result;
  late StreamController<double> progress;

  /// When set, the NEXT upload ignores `cancel()` (a transport that settles
  /// only later) so a stale operation can outlive its build.
  bool holdCancel = false;

  @override
  UploadTask<String> uploadAvatar(File file) {
    uploaded.add(file);
    final Completer<String> r = result = Completer<String>();
    progress = StreamController<double>.broadcast();
    final bool ignoreCancel = holdCancel;
    return UploadTask<String>(
      progress: progress.stream,
      result: r.future,
      onCancel: () {
        if (!ignoreCancel && !r.isCompleted) {
          r.completeError(const UploadCancelledFailure());
        }
      },
    );
  }

  @override
  Future<void> deleteAvatar() async {
    deleteCalls++;
    await holdDelete?.future;
  }
}

void main() {
  late Directory scratch;
  late Directory outside;
  late ScriptedPickGateway gw;
  late _GatedStorage storage;
  late _Uploads uploads;
  late ProviderContainer container;

  setUp(() async {
    scratch = Directory.systemTemp.createTempSync('avatar_gap_scratch');
    outside = Directory.systemTemp.createTempSync('avatar_gap_out');
    gw = ScriptedPickGateway(scratch: scratch, outside: outside);
    storage = _GatedStorage();
    uploads = _Uploads();
    container = ProviderContainer(
      overrides: [
        mediaPickServiceProvider.overrideWithValue(
          MediaPickService(gw, tempDir: () async => scratch),
        ),
        mediaUploadRepositoryProvider.overrideWithValue(uploads),
        masterProfileProvider.overrideWith(_Profile.new),
        secureStorageProvider.overrideWithValue(storage),
        authProvider.overrideWith(_Auth.new),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authProvider.future);
    container.listen(avatarUploadControllerProvider, (_, _) {});
  });
  tearDown(() {
    scratch.deleteSync(recursive: true);
    outside.deleteSync(recursive: true);
  });

  AvatarUploadController ctrl() =>
      container.read(avatarUploadControllerProvider.notifier);
  List<File> scratchFiles() {
    final Directory d = Directory('${scratch.path}/$kMediaUploadDirName');
    return d.existsSync() ? d.listSync().whereType<File>().toList() : <File>[];
  }

  /// Waits until the first upload is in flight.
  Future<void> uploading() => until(() => uploads.uploaded.isNotEmpty);

  group('concurrency', () {
    test('second change() during the PICK window is ignored: one pick, one '
        'upload', () async {
      gw.holdPick = Completer<void>();
      final Future<AvatarChangeResult> first = ctrl().change(
        ImageSourceChoice.gallery,
      );
      await until(() => gw.pickedPath != null);

      final AvatarChangeResult second = await ctrl().change(
        ImageSourceChoice.camera,
      );
      expect(second, isA<AvatarChangeCancelled>());
      expect(gw.pickSources, hasLength(1));

      gw.holdPick!.complete();
      await uploading();
      uploads.result.complete('u');
      expect(await first, isA<AvatarChangeSucceeded>());
      expect(uploads.uploaded, hasLength(1));
    });

    test(
      'remove() while an upload is in flight is ignored: no DELETE',
      () async {
        final Future<AvatarChangeResult> up = ctrl().change(
          ImageSourceChoice.gallery,
        );
        await uploading();

        expect(await ctrl().remove(), isA<AvatarChangeCancelled>());
        expect(uploads.deleteCalls, 0);
        expect(
          container.read(avatarUploadControllerProvider),
          isA<AvatarUploading>(),
        );

        uploads.result.complete('u');
        await up;
      },
    );

    test('change() while a removal is in flight is ignored: no pick', () async {
      uploads.holdDelete = Completer<void>();
      final Future<AvatarChangeResult> rm = ctrl().remove();
      await until(
        () => container.read(avatarUploadControllerProvider) is AvatarRemoving,
      );

      expect(
        await ctrl().change(ImageSourceChoice.gallery),
        isA<AvatarChangeCancelled>(),
      );
      expect(gw.pickSources, isEmpty);
      expect(uploads.uploaded, isEmpty);

      uploads.holdDelete!.complete();
      expect(await rm, isA<AvatarChangeSucceeded>());
      expect(uploads.deleteCalls, 1);
    });

    test('a second remove() while removing sends one DELETE', () async {
      uploads.holdDelete = Completer<void>();
      final Future<AvatarChangeResult> first = ctrl().remove();
      await until(() => uploads.deleteCalls == 1);

      expect(await ctrl().remove(), isA<AvatarChangeCancelled>());
      expect(uploads.deleteCalls, 1);

      uploads.holdDelete!.complete();
      await first;
    });
  });

  group('crop labels', () {
    test(
      'labels given to change() reach the native crop call verbatim',
      () async {
        const CropLabels labels = CropLabels(
          title: 'Обрізати фото',
          doneButton: 'Готово',
          cancelButton: 'Скасувати',
        );
        final Future<AvatarChangeResult> f = ctrl().change(
          ImageSourceChoice.gallery,
          labels: labels,
        );
        await uploading();

        expect(gw.cropLabelsSeen, isTrue);
        expect(gw.seenLabels, same(labels));

        uploads.result.complete('u');
        await f;
      },
    );
  });

  group('desired behaviour pinned by the audit', () {
    test(
      'disposal mid-crop discards the cropped file; nothing uploads',
      () async {
        gw.holdCrop = Completer<void>();
        final Future<AvatarChangeResult> f = ctrl().change(
          ImageSourceChoice.gallery,
        );
        await until(() => gw.cropLabelsSeen);

        container.dispose();
        gw.holdCrop!.complete();

        expect(await f, isA<AvatarChangeCancelled>());
        expect(uploads.uploaded, isEmpty);
        expect(scratchFiles(), isEmpty, reason: 'orphan scratch file leaked');
      },
    );

    test(
      'a failed upload keeps the file; retry re-uploads the SAME file',
      () async {
        final Future<AvatarChangeResult> f = ctrl().change(
          ImageSourceChoice.gallery,
        );
        await uploading();
        final File first = uploads.uploaded.single;
        uploads.result.completeError(const UploadStorageUnavailableFailure());
        expect(await f, isA<AvatarChangeFailed>());

        expect(first.existsSync(), isTrue, reason: 'file kept for retry');
        expect(
          container.read(avatarUploadControllerProvider),
          isA<AvatarFailed>(),
        );

        final Future<AvatarChangeResult> retry = ctrl().retry();
        await until(() => uploads.uploaded.length == 2);
        expect(uploads.uploaded.last.path, first.path);
        uploads.result.complete('u');
        expect(await retry, isA<AvatarChangeSucceeded>());
        expect(first.existsSync(), isFalse, reason: 'discarded after success');
      },
    );

    test(
      'logout (controller disposal) wipes a kept failed-upload file',
      () async {
        final Future<AvatarChangeResult> f = ctrl().change(
          ImageSourceChoice.gallery,
        );
        await uploading();
        uploads.result.completeError(const UploadNetworkFailure());
        await f;
        final File kept = uploads.uploaded.single;
        expect(kept.existsSync(), isTrue);

        container.dispose();

        expect(kept.existsSync(), isFalse);
        expect(scratchFiles(), isEmpty);
      },
    );

    test('dispose during retry()\'s exists() await discards the kept file and '
        'opens no request', () async {
      final Future<AvatarChangeResult> f = ctrl().change(
        ImageSourceChoice.gallery,
      );
      await uploading();
      final File kept = uploads.uploaded.single;
      uploads.result.completeError(const UploadNetworkFailure());
      await f;
      expect(kept.existsSync(), isTrue);

      // retry() runs synchronously up to the exists() await; dispose lands in it.
      final Future<AvatarChangeResult> retry = ctrl().retry();
      container.dispose();

      expect(await retry, isA<AvatarChangeCancelled>());
      expect(uploads.uploaded, hasLength(1), reason: 'no second request');
      expect(kept.existsSync(), isFalse, reason: 'kept file discarded');
      expect(scratchFiles(), isEmpty);
    });

    test('dispose during change()\'s recovery-probe wait returns Cancelled, '
        'no throw', () async {
      storage.gate = Completer<void>();
      final Future<AvatarChangeResult> recovery = ctrl().recoverLost();
      await until(() => storage.reads == 1);
      final Future<AvatarChangeResult> tap = ctrl().change(
        ImageSourceChoice.gallery,
      );
      await Future<void>.delayed(Duration.zero);

      container.dispose();
      storage.gate!.complete();

      expect(await tap, isA<AvatarChangeCancelled>());
      expect(await recovery, isA<AvatarChangeCancelled>());
      expect(gw.pickSources, isEmpty, reason: 'no pick on a dead build');
      expect(uploads.uploaded, isEmpty);
    });

    test('a stale upload after a user-switch rebuild leaves the new build\'s '
        'state and task alone', () async {
      uploads.holdCancel = true;
      final Future<AvatarChangeResult> stale = ctrl().change(
        ImageSourceChoice.gallery,
      );
      await uploading();
      final Completer<String> staleResult = uploads.result;
      uploads.holdCancel = false;

      (container.read(authProvider.notifier) as _Auth).switchTo('user-2');
      await until(
        () => container.read(avatarUploadControllerProvider) is AvatarIdle,
      );
      final Future<AvatarChangeResult> fresh = ctrl().change(
        ImageSourceChoice.gallery,
      );
      await until(() => uploads.uploaded.length == 2);
      final Completer<String> freshResult = uploads.result;
      final File freshFile = uploads.uploaded.last;

      staleResult.completeError(const UploadNetworkFailure());
      await stale;

      final AvatarUploadState now = container.read(
        avatarUploadControllerProvider,
      );
      expect(now, isA<AvatarUploading>(), reason: 'not clobbered to idle');
      expect((now as AvatarUploading).previewFile?.path, freshFile.path);
      container.dispose();
      expect(
        freshResult.isCompleted,
        isTrue,
        reason: '_task still the new one',
      );
      expect(await fresh, isA<AvatarChangeCancelled>());
    });

    test('a stale remove() after a user-switch rebuild does not reset the new '
        'build\'s state', () async {
      uploads.holdDelete = Completer<void>();
      final Future<AvatarChangeResult> stale = ctrl().remove();
      await until(() => uploads.deleteCalls == 1);

      (container.read(authProvider.notifier) as _Auth).switchTo('user-2');
      await until(
        () => container.read(avatarUploadControllerProvider) is AvatarIdle,
      );
      final Future<AvatarChangeResult> fresh = ctrl().change(
        ImageSourceChoice.gallery,
      );
      await uploading();

      uploads.holdDelete!.complete();
      await stale;

      expect(
        container.read(avatarUploadControllerProvider),
        isA<AvatarUploading>(),
      );
      uploads.result.complete('u');
      expect(await fresh, isA<AvatarChangeSucceeded>());
    });

    test('recoverLost ignores a pick that belongs to another user', () async {
      await PendingPickStore(storage).begin('other-user', MediaKind.avatar);
      gw.lost = 'x';

      expect(await ctrl().recoverLost(), isA<AvatarChangeCancelled>());

      expect(uploads.uploaded, isEmpty);
      expect(scratchFiles(), isEmpty);
      expect(File(gw.pickedPath!).existsSync(), isFalse, reason: 'drained');
    });
  });
}
