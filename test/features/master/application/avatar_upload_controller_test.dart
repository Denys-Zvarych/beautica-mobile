// Phase 073 — AvatarUploadController: pick → upload → profile-patch wiring.
//
// Real `MediaPickService` over the scripted gateway (real file IO, so plain
// `test()`), a scripted `MediaUploadRepository`, and a counting
// `masterProfileProvider` stub: every build is one `GET /masters/me`, so
// "patched, not refetched" is observable as `_profileBuilds == 1`.
//
// No wall-clock waits: [until] polls a CONDITION by yielding to the event loop.

import 'dart:async';
import 'dart:io';

import 'package:beautica_mobile/core/media/pick/image_source_sheet.dart';
import 'package:beautica_mobile/core/media/pick/media_kind.dart';
import 'package:beautica_mobile/core/media/pick/media_pick_service.dart';
import 'package:beautica_mobile/core/media/pick/pending_pick_store.dart';
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
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/media/pick/scripted_pick_gateway.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';
import '../../../helpers/until.dart';

const String kOldAvatar = 'https://media.test/avatars/u1/old.jpg';
const String kNewAvatar = 'https://media.test/avatars/u1/new.jpg';

const User _user = User(
  id: 'user-1',
  email: 'a@beautica.ua',
  role: UserRole.independentMaster,
  firstName: 'Олена',
  lastName: 'Ковальчук',
);

const Master _master = Master(
  id: 'm1',
  firstName: 'Олена',
  lastName: 'Ковальчук',
  avgRating: 0,
  reviewCount: 0,
  type: MasterType.independentMaster,
  avatarUrl: kOldAvatar,
);

/// Signed-in stub whose user can be switched / signed out mid-test.
class _Auth extends AuthNotifier {
  @override
  Future<AuthSession> build() async =>
      const AuthSession.authenticated(user: _user, accessToken: 't');

  void signOut() =>
      state = const AsyncData<AuthSession>(AuthSession.unauthenticated());
}

int _profileBuilds = 0;

class _CountingProfile extends MasterProfile {
  @override
  Future<Master> build() {
    _profileBuilds++;
    return Future<Master>.value(_master);
  }
}

/// Upload whose outcome the test drives; records cancel + the uploaded file.
class _FakeUploads implements MediaUploadRepository {
  final List<File> uploaded = <File>[];
  int deleteCalls = 0;
  int cancelCalls = 0;
  UploadFailure? deleteFailure;

  /// Completes the in-flight upload (value or failure).
  late Completer<String> result;
  late StreamController<double> progress;
  bool filePresentAtUpload = false;

  @override
  UploadTask<String> uploadAvatar(File file) {
    uploaded.add(file);
    filePresentAtUpload = file.existsSync();
    result = Completer<String>();
    progress = StreamController<double>.broadcast();
    return UploadTask<String>(
      progress: progress.stream,
      result: result.future,
      onCancel: () {
        cancelCalls++;
        if (!result.isCompleted) {
          result.completeError(const UploadCancelledFailure());
        }
      },
    );
  }

  @override
  Future<void> deleteAvatar() async {
    deleteCalls++;
    final UploadFailure? f = deleteFailure;
    if (f != null) throw f;
  }
}

void main() {
  late Directory scratch;
  late Directory outside;
  late ScriptedPickGateway gw;
  late _FakeUploads uploads;
  late FakeSecureStorage storage;
  late ProviderContainer container;

  setUp(() async {
    _profileBuilds = 0;
    scratch = Directory.systemTemp.createTempSync('avatar_ctrl_scratch');
    outside = Directory.systemTemp.createTempSync('avatar_ctrl_out');
    gw = ScriptedPickGateway(scratch: scratch, outside: outside);
    uploads = _FakeUploads();
    storage = FakeSecureStorage();
    container = ProviderContainer(
      overrides: [
        mediaPickServiceProvider.overrideWithValue(
          MediaPickService(gw, tempDir: () async => scratch),
        ),
        mediaUploadRepositoryProvider.overrideWithValue(uploads),
        masterProfileProvider.overrideWith(_CountingProfile.new),
        secureStorageProvider.overrideWithValue(storage),
        authProvider.overrideWith(_Auth.new),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authProvider.future);
  });
  tearDown(() {
    scratch.deleteSync(recursive: true);
    outside.deleteSync(recursive: true);
  });

  AvatarUploadController ctrl() =>
      container.read(avatarUploadControllerProvider.notifier);

  /// Keeps the autoDispose controller alive for the whole test.
  void keepAlive() {
    container.listen(avatarUploadControllerProvider, (_, _) {});
  }

  AvatarUploadState current() => container.read(avatarUploadControllerProvider);

  String? cachedAvatar() =>
      container.read(masterProfileProvider).value?.avatarUrl;

  List<File> scratchJpegs() =>
      Directory('${scratch.path}/$kMediaUploadDirName').existsSync()
      ? Directory(
          '${scratch.path}/$kMediaUploadDirName',
        ).listSync().whereType<File>().toList()
      : <File>[];

  /// Starts a gallery pick and waits until its upload is in flight; the INNER
  /// future is the pick's eventual result (so `await startUpload()` does not
  /// wait for it).
  Future<Future<AvatarChangeResult>> startUpload({
    AvatarPrecache? precache,
  }) async {
    final Future<AvatarChangeResult> f = ctrl().change(
      ImageSourceChoice.gallery,
      precache: precache,
    );
    await until(() => uploads.uploaded.isNotEmpty);
    return f;
  }

  test('picker cancel -> no upload, returns Cancelled, state idle', () async {
    keepAlive();
    gw.cancelPick = true;

    final AvatarChangeResult r = await ctrl().change(ImageSourceChoice.gallery);

    expect(r, isA<AvatarChangeCancelled>());
    expect(uploads.uploaded, isEmpty);
    expect(current(), isA<AvatarIdle>());
  });

  test('crop cancel -> no upload', () async {
    keepAlive();
    gw.cancelCrop = true;

    final AvatarChangeResult r = await ctrl().change(ImageSourceChoice.camera);

    expect(r, isA<AvatarChangeCancelled>());
    expect(uploads.uploaded, isEmpty);
    expect(gw.pickSources.single.name, 'camera');
  });

  test('success -> cached profile PATCHED (no refetch), temp file discarded, '
      'idle', () async {
    keepAlive();
    await container.read(masterProfileProvider.future);
    expect(_profileBuilds, 1);
    expect(cachedAvatar(), kOldAvatar);

    final Future<AvatarChangeResult> f = ctrl().change(
      ImageSourceChoice.gallery,
    );
    await until(() => uploads.uploaded.isNotEmpty);
    final AvatarUploading uploading = current() as AvatarUploading;
    expect(uploading.previewFile, isNotNull);
    expect(uploads.filePresentAtUpload, isTrue);

    uploads.progress.add(0.5);
    await until(() => (current() as AvatarUploading).progress == 0.5);

    uploads.result.complete(kNewAvatar);
    final AvatarChangeResult r = await f;

    expect(r, isA<AvatarChangeSucceeded>());
    expect(_profileBuilds, 1, reason: 'patched, NOT refetched (one GET total)');
    expect(cachedAvatar(), kNewAvatar);
    expect(current(), isA<AvatarIdle>());
    expect(uploads.uploaded.single.existsSync(), isFalse);
    expect(scratchJpegs(), isEmpty);
  });

  test('100% progress is not success: 503 after the last byte -> FAILED state '
      'keeping the photo, old avatar + profile untouched', () async {
    keepAlive();
    await container.read(masterProfileProvider.future);

    final Future<AvatarChangeResult> f = ctrl().change(
      ImageSourceChoice.gallery,
    );
    await until(() => uploads.uploaded.isNotEmpty);
    uploads.progress.add(1.0);
    await until(() => (current() as AvatarUploading).progress == 1.0);
    expect(current(), isA<AvatarUploading>(), reason: 'still uploading');

    uploads.result.completeError(const UploadStorageUnavailableFailure());
    final AvatarChangeResult r = await f;

    expect(r, isA<AvatarChangeFailed>());
    expect(
      (r as AvatarChangeFailed).failure,
      isA<UploadStorageUnavailableFailure>(),
    );
    expect(_profileBuilds, 1, reason: 'no refetch on failure');
    expect(cachedAvatar(), kOldAvatar, reason: 'avatar unchanged by a 503');
    final AvatarFailed failed = current() as AvatarFailed;
    expect(failed.failure, isA<UploadStorageUnavailableFailure>());
    expect(failed.previewFile.path, uploads.uploaded.single.path);
    expect(failed.previewFile.existsSync(), isTrue, reason: 'kept for retry');
  });

  test('retry() re-sends the SAME file without the picker; success discards '
      'it', () async {
    keepAlive();
    await container.read(masterProfileProvider.future);
    final Future<AvatarChangeResult> f = await startUpload();
    final File first = uploads.uploaded.single;
    uploads.result.completeError(const UploadNetworkFailure());
    expect(await f, isA<AvatarChangeFailed>());

    final Future<AvatarChangeResult> retry = ctrl().retry();
    await until(() => uploads.uploaded.length == 2);
    expect(uploads.uploaded.last.path, first.path);
    expect(gw.pickSources, hasLength(1), reason: 'the picker did not reopen');
    expect(current(), isA<AvatarUploading>());

    uploads.result.complete(kNewAvatar);
    expect(await retry, isA<AvatarChangeSucceeded>());
    expect(first.existsSync(), isFalse);
    expect(current(), isA<AvatarIdle>());
    expect(cachedAvatar(), kNewAvatar);
  });

  test('retry() with nothing kept is a quiet no-op', () async {
    keepAlive();
    expect(await ctrl().retry(), isA<AvatarChangeCancelled>());
    expect(uploads.uploaded, isEmpty);
  });

  test('a new pick replaces the failed file (old one deleted)', () async {
    keepAlive();
    final Future<AvatarChangeResult> f = await startUpload();
    final File first = uploads.uploaded.single;
    uploads.result.completeError(const UploadNetworkFailure());
    await f;
    expect(first.existsSync(), isTrue);

    final Future<AvatarChangeResult> second = ctrl().change(
      ImageSourceChoice.gallery,
    );
    await until(() => uploads.uploaded.length == 2);
    expect(first.existsSync(), isFalse, reason: 'old kept file released');
    uploads.result.complete(kNewAvatar);
    await second;
  });

  test('a cancelled new pick keeps the failed file and state', () async {
    keepAlive();
    final Future<AvatarChangeResult> f = await startUpload();
    uploads.result.completeError(const UploadNetworkFailure());
    await f;

    gw.cancelPick = true;
    expect(
      await ctrl().change(ImageSourceChoice.gallery),
      isA<AvatarChangeCancelled>(),
    );
    expect(current(), isA<AvatarFailed>());
    expect((current() as AvatarFailed).previewFile.existsSync(), isTrue);
  });

  test('remove() while FAILED drops the kept file', () async {
    keepAlive();
    final Future<AvatarChangeResult> f = await startUpload();
    final File first = uploads.uploaded.single;
    uploads.result.completeError(const UploadNetworkFailure());
    await f;

    expect(await ctrl().remove(), isA<AvatarChangeSucceeded>());
    expect(first.existsSync(), isFalse);
    expect(current(), isA<AvatarIdle>());
  });

  test('pick failure (typed) surfaces as Failed without uploading', () async {
    keepAlive();
    gw.compressSizes = <int?>[null];

    final AvatarChangeResult r = await ctrl().change(ImageSourceChoice.gallery);

    expect(r, isA<AvatarChangeFailed>());
    expect(uploads.uploaded, isEmpty);
    expect(current(), isA<AvatarIdle>(), reason: 'no file => nothing to retry');
  });

  test(
    'dispose mid-upload cancels the task; no state write after dispose',
    () async {
      final ProviderSubscription<AvatarUploadState> sub = container.listen(
        avatarUploadControllerProvider,
        (_, _) {},
      );
      final Future<AvatarChangeResult> f = await startUpload();
      expect(uploads.cancelCalls, 0);

      sub.close();
      await until(() => uploads.cancelCalls == 1); // autoDispose fires

      expect(await f, isA<AvatarChangeCancelled>());
      expect(uploads.uploaded.single.existsSync(), isFalse);
      expect(scratchJpegs(), isEmpty);
    },
  );

  // B1 — the pick service / repo are captured BEFORE the first await, so a
  // dispose in the pick or crop window neither throws a StateError nor leaks.
  for (final bool midCrop in <bool>[false, true]) {
    test('dispose ${midCrop ? 'mid-CROP' : 'mid-PICK'}: result is Cancelled '
        '(nothing escapes), no upload, no orphan scratch file', () async {
      final ProviderSubscription<AvatarUploadState> sub = container.listen(
        avatarUploadControllerProvider,
        (_, _) {},
      );
      final Completer<void> hold = Completer<void>();
      if (midCrop) {
        gw.holdCrop = hold;
      } else {
        gw.holdPick = hold;
      }
      final Future<AvatarChangeResult> f = ctrl().change(
        ImageSourceChoice.gallery,
      );
      await until(() => midCrop ? gw.cropLabelsSeen : gw.pickedPath != null);

      sub.close();
      container.dispose();
      hold.complete();

      expect(await f, isA<AvatarChangeCancelled>());
      expect(uploads.uploaded, isEmpty);
      expect(scratchJpegs(), isEmpty, reason: 'orphan scratch file leaked');
    });
  }

  test(
    'the pick is tagged with owner + kind while in flight, cleared after',
    () async {
      keepAlive();
      gw.holdPick = Completer<void>();
      final Future<AvatarChangeResult> f = ctrl().change(
        ImageSourceChoice.gallery,
      );
      await until(() => gw.pickedPath != null);

      final PendingPick? tag = await PendingPickStore(storage).read();
      expect(tag?.ownerId, 'user-1');
      expect(tag?.kind, MediaKind.avatar);

      gw.cancelPick = false;
      gw.holdPick!.complete();
      await until(() => uploads.uploaded.isNotEmpty);
      expect(
        await storage.readPendingPick(),
        isNull,
        reason: 'cleared once settled',
      );
      uploads.result.complete(kNewAvatar);
      await f;
    },
  );

  test('remove -> deleteAvatar + cache patched to null (no refetch); failure '
      'maps to Failed', () async {
    keepAlive();
    await container.read(masterProfileProvider.future);

    final AvatarChangeResult ok = await ctrl().remove();
    expect(ok, isA<AvatarChangeSucceeded>());
    expect(uploads.deleteCalls, 1);
    expect(_profileBuilds, 1, reason: 'patched, not refetched');
    expect(cachedAvatar(), isNull);

    uploads.deleteFailure = const UploadNetworkFailure();
    final AvatarChangeResult bad = await ctrl().remove();
    expect(bad, isA<AvatarChangeFailed>());
    expect(_profileBuilds, 1);
    expect(current(), isA<AvatarIdle>());
  });

  test(
    'with no cached profile the success path falls back to a refetch',
    () async {
      keepAlive();
      // masterProfileProvider never read => nothing cached to patch.
      final Future<AvatarChangeResult> f = await startUpload();
      uploads.result.complete(kNewAvatar);
      expect(await f, isA<AvatarChangeSucceeded>());
      await container.read(masterProfileProvider.future);
      expect(
        _profileBuilds,
        2,
        reason: 'nothing cached to patch: invalidated, re-read from server',
      );
    },
  );

  test('ImageSourceChoice.remove routed through change() deletes', () async {
    keepAlive();
    await ctrl().change(ImageSourceChoice.remove);
    expect(uploads.deleteCalls, 1);
    expect(gw.pickSources, isEmpty);
  });

  group('recoverLost', () {
    Future<void> tag(String owner, MediaKind kind) =>
        PendingPickStore(storage).begin(owner, kind);

    test('uploads a recovered pick of THIS user exactly once; nothing -> '
        'Cancelled with no native call', () async {
      keepAlive();
      expect(await ctrl().recoverLost(), isA<AvatarChangeCancelled>());
      expect(uploads.uploaded, isEmpty);

      await tag('user-1', MediaKind.avatar);
      gw.lost = 'x';
      final Future<AvatarChangeResult> f = ctrl().recoverLost();
      await until(() => uploads.uploaded.isNotEmpty);
      uploads.result.complete(kNewAvatar);

      expect(await f, isA<AvatarChangeSucceeded>());
      expect(uploads.uploaded, hasLength(1));
      expect(uploads.uploaded.single.existsSync(), isFalse);
      expect(await storage.readPendingPick(), isNull);
    });

    test('ignores (and deletes) a pick of another media kind', () async {
      keepAlive();
      await tag('user-1', MediaKind.servicePhoto);
      gw.lost = 'x';

      expect(await ctrl().recoverLost(), isA<AvatarChangeCancelled>());

      expect(uploads.uploaded, isEmpty);
      expect(File(gw.pickedPath!).existsSync(), isFalse);
    });

    test('is Android-only: no tag read, no native call elsewhere', () async {
      keepAlive();
      await tag('user-1', MediaKind.avatar);
      gw.lost = 'x';
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        expect(await ctrl().recoverLost(), isA<AvatarChangeCancelled>());
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
      expect(gw.pickedPath, isNull, reason: 'retrieveLostData never called');
      expect(uploads.uploaded, isEmpty);
    });

    test('a tap during recovery is queued behind it, not dropped', () async {
      keepAlive();
      final _GatedStorage gated = _GatedStorage()..gate = Completer<void>();
      final ProviderContainer c = ProviderContainer(
        overrides: [
          mediaPickServiceProvider.overrideWithValue(
            MediaPickService(gw, tempDir: () async => scratch),
          ),
          mediaUploadRepositoryProvider.overrideWithValue(uploads),
          masterProfileProvider.overrideWith(_CountingProfile.new),
          secureStorageProvider.overrideWithValue(gated),
          authProvider.overrideWith(_Auth.new),
        ],
      );
      addTearDown(c.dispose);
      await c.read(authProvider.future);
      c.listen(avatarUploadControllerProvider, (_, _) {});
      final AvatarUploadController k = c.read(
        avatarUploadControllerProvider.notifier,
      );

      final Future<AvatarChangeResult> recovery = k.recoverLost();
      await until(() => gated.reads == 1);
      final Future<AvatarChangeResult> tap = k.change(
        ImageSourceChoice.gallery,
      );
      await Future<void>.delayed(Duration.zero);
      expect(gw.pickSources, isEmpty, reason: 'held behind the recovery');

      gated.gate!.complete();
      expect(await recovery, isA<AvatarChangeCancelled>());
      await until(() => uploads.uploaded.isNotEmpty);
      expect(gw.pickSources, hasLength(1), reason: 'the tap proceeded');
      uploads.result.complete(kNewAvatar);
      expect(await tap, isA<AvatarChangeSucceeded>());
    });
  });

  test('a second change while busy is ignored', () async {
    keepAlive();
    final Future<AvatarChangeResult> first = await startUpload();

    final AvatarChangeResult second = await ctrl().change(
      ImageSourceChoice.gallery,
    );
    expect(second, isA<AvatarChangeCancelled>());
    expect(uploads.uploaded, hasLength(1));

    uploads.result.complete('u');
    await first;
  });

  test('progress emits are throttled to >= 1% steps; first, final and state '
      'changes always emit', () async {
    final List<double> seen = <double>[];
    container.listen(avatarUploadControllerProvider, (_, AvatarUploadState n) {
      if (n is AvatarUploading) seen.add(n.progress);
    });
    final Future<AvatarChangeResult> f = await startUpload();
    for (final double p in <double>[
      0.001,
      0.005,
      0.011,
      0.012,
      0.5,
      0.505,
      1.0,
      1.0,
    ]) {
      uploads.progress.add(p);
    }
    await until(() => seen.contains(1.0));

    expect(seen, <double>[0.0, 0.011, 0.5, 1.0]);
    uploads.result.complete(kNewAvatar);
    await f;
  });

  group('precache before releasing the preview', () {
    test('success returns at once; the preview is held until the precache '
        'settles, then released + discarded', () async {
      keepAlive();
      final Completer<void> warm = Completer<void>();
      String? warmed;
      final Future<AvatarChangeResult> f = await startUpload(
        precache: (String url) {
          warmed = url;
          return warm.future;
        },
      );
      final File file = uploads.uploaded.single;
      uploads.result.complete(kNewAvatar);

      expect(await f, isA<AvatarChangeSucceeded>(), reason: 'not blocked');
      expect(warmed, kNewAvatar);
      expect(current(), isA<AvatarUploading>(), reason: 'preview still up');
      expect(file.existsSync(), isTrue);

      warm.complete();
      await until(() => current() is AvatarIdle);
      await until(() => !file.existsSync());
    });

    test('a failing precache still releases the preview', () async {
      keepAlive();
      final Future<AvatarChangeResult> f = await startUpload(
        precache: (String _) async => throw StateError('decode failed'),
      );
      final File file = uploads.uploaded.single;
      uploads.result.complete(kNewAvatar);

      expect(await f, isA<AvatarChangeSucceeded>());
      await until(() => current() is AvatarIdle);
      await until(() => !file.existsSync());
    });
  });

  group('kept file never outlives the session', () {
    test(
      'logout rebuilds the controller: kept file deleted, retry impossible',
      () async {
        keepAlive();
        final Future<AvatarChangeResult> f = await startUpload();
        final File file = uploads.uploaded.single;
        uploads.result.completeError(const UploadNetworkFailure());
        await f;
        expect(current(), isA<AvatarFailed>());

        (container.read(authProvider.notifier) as _Auth).signOut();
        await until(() => !file.existsSync());

        expect(current(), isA<AvatarIdle>());
        expect(await ctrl().retry(), isA<AvatarChangeCancelled>());
        expect(uploads.uploaded, hasLength(1), reason: 'nothing re-sent');
      },
    );
  });
}

/// Storage whose pending-pick read can be held open.
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
