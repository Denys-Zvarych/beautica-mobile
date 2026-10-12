// Phase 403 (9.8, D7) — PortfolioEditController: add (pick → upload →
// the returned photo PREPENDED to the cached stored list), failure → retry /
// discard, one upload at a time, cancel on dispose, delete (→ id dropped from
// the cached list; a 404 also drops it, then re-syncs), 5 % progress step, cap pre-check (stored +
// pending), account-switch drain and the owner-scoped lost-pick recovery.
// Stored-list assertions are on CONTENTS, never on how many reads happened. Real MediaPickService over the scripted
// gateway; a scripted MediaUploadRepository.

import 'dart:async';
import 'dart:io';

import 'package:beautica_mobile/core/media/pick/media_kind.dart';
import 'package:beautica_mobile/core/media/pick/media_pick_service.dart';
import 'package:beautica_mobile/core/media/pick/pending_pick_store.dart';
import 'package:beautica_mobile/core/media/portfolio/portfolio_edit_controller.dart';
import 'package:beautica_mobile/core/media/portfolio/portfolio_notifier.dart';
import 'package:beautica_mobile/core/media/portfolio/portfolio_owner.dart';
import 'package:beautica_mobile/core/media/portfolio/portfolio_photo.dart';
import 'package:beautica_mobile/core/media/upload/media_upload_repository.dart';
import 'package:beautica_mobile/core/media/upload/upload_failure.dart';
import 'package:beautica_mobile/core/media/upload/upload_task.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_portfolio_notifier.dart';
import 'package:beautica_mobile/features/salon/data/salon_repository.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fakes/fake_salon_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';
import '../../../helpers/until.dart';
import '../pick/scripted_pick_gateway.dart';

const PortfolioOwner _salonA = PortfolioOwner.salon('salon-a');
const PortfolioOwner _salonB = PortfolioOwner.salon('salon-b');
const PortfolioOwner _master = PortfolioOwner.masterSelf('master-1');

const PortfolioPhoto _stored = PortfolioPhoto(
  id: 'stored',
  url: 'https://m.test/stored.jpg',
);

const PortfolioPhoto _older = PortfolioPhoto(
  id: 'older',
  url: 'https://m.test/older.jpg',
);

/// What the server returns for a NEW upload — distinct from every stored row,
/// so a prepend is observable.
const PortfolioPhoto _fresh = PortfolioPhoto(
  id: 'fresh',
  url: 'https://m.test/fresh.jpg',
);

/// Scripted portfolio transport. Each upload gets its own result completer
/// and progress controller.
class _Uploads implements MediaUploadRepository {
  final List<(PortfolioOwner, File)> uploaded = <(PortfolioOwner, File)>[];
  final List<Completer<PortfolioPhoto>> results = <Completer<PortfolioPhoto>>[];
  final List<StreamController<double>> progress = <StreamController<double>>[];
  final List<(PortfolioOwner, String)> deletes = <(PortfolioOwner, String)>[];
  int cancelCalls = 0;
  UploadFailure? deleteFailure;

  /// When set, the NEXT delete parks on it (taken once, then cleared).
  Completer<void>? holdDelete;
  List<PortfolioPhoto> masterPhotos = const <PortfolioPhoto>[_stored];

  @override
  UploadTask<PortfolioPhoto> uploadPortfolioPhoto(
    PortfolioOwner owner,
    File file,
  ) {
    uploaded.add((owner, file));
    final Completer<PortfolioPhoto> c = Completer<PortfolioPhoto>();
    final StreamController<double> p = StreamController<double>.broadcast();
    results.add(c);
    progress.add(p);
    return UploadTask<PortfolioPhoto>(
      progress: p.stream,
      result: c.future.whenComplete(p.close),
      onCancel: () {
        cancelCalls++;
        if (!c.isCompleted) c.completeError(const UploadCancelledFailure());
      },
    );
  }

  @override
  Future<void> deletePortfolioPhoto(
    PortfolioOwner owner,
    String mediaId,
  ) async {
    deletes.add((owner, mediaId));
    final Completer<void>? hold = holdDelete;
    holdDelete = null;
    if (hold != null) await hold.future;
    final UploadFailure? f = deleteFailure;
    if (f != null) throw f;
  }

  @override
  Future<List<PortfolioPhoto>> getMasterPortfolio(String masterId) async =>
      masterPhotos;

  @override
  UploadTask<String> uploadAvatar(File file) => throw UnimplementedError();

  @override
  Future<void> deleteAvatar() => throw UnimplementedError();

  @override
  UploadTask<String> uploadSalonImage(
    String salonId,
    SalonImageSlot slot,
    File file,
  ) => throw UnimplementedError();

  @override
  Future<void> deleteSalonImage(String salonId, SalonImageSlot slot) =>
      throw UnimplementedError();
}

class _Salons extends FakeSalonRepository {
  _Salons()
    : super(
        salon: const Salon(id: 'salon-a', name: 'Салон'),
      );

  List<PortfolioPhoto> photos = const <PortfolioPhoto>[_stored, _older];

  /// When set, the NEXT read parks on it (taken once, then cleared) — an
  /// in-flight read that a write can land behind.
  Completer<List<PortfolioPhoto>>? heldRead;

  @override
  Future<List<PortfolioPhoto>> getSalonPortfolio(String salonId) async {
    final Completer<List<PortfolioPhoto>>? held = heldRead;
    heldRead = null;
    if (held != null) return held.future;
    return photos;
  }
}

class _Auth extends AuthNotifier {
  @override
  Future<AuthSession> build() async => session('user-1');

  void switchTo(String id) => state = AsyncData<AuthSession>(session(id));

  static AuthSession session(String id) => AuthSession.authenticated(
    user: User(id: id, email: '$id@beautica.ua', role: UserRole.salonOwner),
    accessToken: 't',
  );
}

void main() {
  late Directory scratch;
  late Directory outside;
  late ScriptedPickGateway gw;
  late _Uploads uploads;
  late _Salons salons;
  late FakeSecureStorage storage;
  late ProviderContainer container;

  setUp(() async {
    scratch = Directory.systemTemp.createTempSync('portfolio_ctrl_scratch');
    outside = Directory.systemTemp.createTempSync('portfolio_ctrl_out');
    gw = ScriptedPickGateway(scratch: scratch, outside: outside);
    uploads = _Uploads();
    salons = _Salons();
    storage = FakeSecureStorage();
    container = ProviderContainer(
      overrides: [
        mediaPickServiceProvider.overrideWithValue(
          MediaPickService(gw, tempDir: () async => scratch),
        ),
        mediaUploadRepositoryProvider.overrideWithValue(uploads),
        salonRepositoryProvider.overrideWithValue(salons),
        secureStorageProvider.overrideWithValue(storage),
        authProvider.overrideWith(_Auth.new),
      ],
    );
    addTearDown(() {
      container.dispose();
      scratch.deleteSync(recursive: true);
      outside.deleteSync(recursive: true);
    });
    await container.read(authProvider.future);
  });

  PortfolioEditController ctrl(PortfolioOwner o) {
    container.listen(portfolioEditControllerProvider(o), (_, _) {});
    return container.read(portfolioEditControllerProvider(o).notifier);
  }

  List<PendingPortfolioUpload> pending(PortfolioOwner o) =>
      container.read(portfolioEditControllerProvider(o));

  Future<void> loadStored(PortfolioOwner o) async {
    container.listen(portfolioProvider(o), (_, _) {});
    await container.read(portfolioProvider(o).future);
  }

  /// The stored list the app reads now, as ids.
  Future<List<String>> storedIds(PortfolioOwner o) async => <String>[
    for (final PortfolioPhoto p in await container.read(
      portfolioProvider(o).future,
    ))
      p.id,
  ];

  /// Makes [o]'s portfolio fail its first (pending) upload, leaving one
  /// failed entry behind.
  Future<void> leaveOneFailed(PortfolioOwner o) async {
    final Future<AvatarChangeResult> f = ctrl(o).add(MediaPickSource.gallery);
    await until(() => uploads.uploaded.isNotEmpty);
    uploads.results.last.completeError(const UploadNetworkFailure());
    await f;
    expect(pending(o).single.isUploading, isFalse);
  }

  test('add: picks a SQUARE portfolio crop, uploads to THIS owner, shows '
      'progress; success drops the entry, deletes the file and puts the '
      'returned photo FIRST in the stored portfolio', () async {
    await loadStored(_salonA);
    final PortfolioEditController c = ctrl(_salonA);
    final Future<AvatarChangeResult> f = c.add(MediaPickSource.gallery);
    await until(() => uploads.uploaded.isNotEmpty);

    expect(gw.cropSpecs.single.aspectX, 1);
    expect(gw.cropSpecs.single.aspectY, 1);
    expect(gw.cropSpecs.single.circle, isFalse);
    expect(gw.compressDims.single, (1600, 1600));
    expect(uploads.uploaded.single.$1, _salonA);
    final File file = uploads.uploaded.single.$2;
    expect(pending(_salonA).single.isUploading, isTrue);

    uploads.progress.single.add(0.5);
    await until(() => pending(_salonA).single.progress == 0.5);

    uploads.results.single.complete(_fresh);
    expect(await f, isA<AvatarChangeSucceeded>());
    expect(pending(_salonA), isEmpty);
    expect(file.existsSync(), isFalse, reason: 'scratch file released');
    expect(await storedIds(_salonA), <String>['fresh', 'stored', 'older']);
  });

  test('P1: the returned photo is prepended to the CACHED list — the server '
      'list is not re-read (it still lacks the new photo here)', () async {
    await loadStored(_salonA);
    final Future<AvatarChangeResult> f = ctrl(
      _salonA,
    ).add(MediaPickSource.gallery);
    await until(() => uploads.uploaded.isNotEmpty);
    uploads.results.single.complete(_fresh);
    expect(await f, isA<AvatarChangeSucceeded>());
    expect(
      container.read(portfolioProvider(_salonA)).value,
      const <PortfolioPhoto>[_fresh, _stored, _older],
    );
    expect(await storedIds(_salonA), <String>['fresh', 'stored', 'older']);
  });

  // Not a fallback probe: with no provider alive there is nothing to patch
  // OR invalidate — the next read is simply the first one. The fallback
  // itself is pinned by the "still LOADING" test below.
  test('P1: with NOTHING cached, the next read after an upload is the '
      'server list', () async {
    final Future<AvatarChangeResult> f = ctrl(
      _salonA,
    ).add(MediaPickSource.gallery);
    await until(() => uploads.uploaded.isNotEmpty);
    salons.photos = const <PortfolioPhoto>[_fresh, _stored];
    uploads.results.single.complete(_fresh);
    expect(await f, isA<AvatarChangeSucceeded>());
    expect(await storedIds(_salonA), <String>['fresh', 'stored']);
  });

  test('P1 fallback: an upload that lands while the stored read is still '
      'LOADING invalidates it — the stale in-flight read never wins', () async {
    final Completer<List<PortfolioPhoto>> stale =
        Completer<List<PortfolioPhoto>>();
    salons.heldRead = stale;
    container.listen(portfolioProvider(_salonA), (_, _) {});
    expect(container.read(portfolioProvider(_salonA)).isLoading, isTrue);

    final Future<AvatarChangeResult> f = ctrl(
      _salonA,
    ).add(MediaPickSource.gallery);
    await until(() => uploads.uploaded.isNotEmpty);
    salons.photos = const <PortfolioPhoto>[_fresh, _stored, _older];
    uploads.results.single.complete(_fresh);
    expect(await f, isA<AvatarChangeSucceeded>());
    // The pre-upload read now resolves WITHOUT the new photo.
    stale.complete(const <PortfolioPhoto>[_stored, _older]);

    expect(await storedIds(_salonA), <String>['fresh', 'stored', 'older']);
  });

  test('P1: the salon delegate (salonPortfolioProvider) sees the same '
      'patched list after an upload and a delete', () async {
    container.listen(salonPortfolioProvider('salon-a'), (_, _) {});
    expect(
      await container.read(salonPortfolioProvider('salon-a').future),
      const <PortfolioPhoto>[_stored, _older],
    );
    final PortfolioEditController c = ctrl(_salonA);
    final Future<AvatarChangeResult> f = c.add(MediaPickSource.gallery);
    await until(() => uploads.uploaded.isNotEmpty);
    uploads.results.single.complete(_fresh);
    expect(await f, isA<AvatarChangeSucceeded>());
    expect(
      await container.read(salonPortfolioProvider('salon-a').future),
      const <PortfolioPhoto>[_fresh, _stored, _older],
    );

    expect(await c.delete('stored'), isA<AvatarChangeSucceeded>());
    expect(
      await container.read(salonPortfolioProvider('salon-a').future),
      const <PortfolioPhoto>[_fresh, _older],
    );
  });

  test('P4: the pending list moves in 5 % steps, and the final 100 % is '
      'always emitted', () async {
    final PortfolioEditController c = ctrl(_salonA);
    final List<double> seen = <double>[];
    container.listen<List<PendingPortfolioUpload>>(
      portfolioEditControllerProvider(_salonA),
      (_, List<PendingPortfolioUpload> next) {
        if (next.isNotEmpty) seen.add(next.single.progress);
      },
    );
    final Future<AvatarChangeResult> f = c.add(MediaPickSource.gallery);
    await until(() => uploads.uploaded.isNotEmpty);
    final StreamController<double> p = uploads.progress.single;
    for (final double v in <double>[0.01, 0.02, 0.04, 0.05, 0.07, 0.09]) {
      p.add(v);
    }
    p.add(0.12);
    p.add(0.98);
    p.add(1.0);
    await until(() => seen.isNotEmpty && seen.last == 1.0);
    expect(seen, <double>[0.0, 0.05, 0.12, 0.98, 1.0]);
    uploads.results.single.complete(_fresh);
    expect(await f, isA<AvatarChangeSucceeded>());
  });

  test('P4: a final 100 % within 5 % of the last step is still '
      'emitted', () async {
    final PortfolioEditController c = ctrl(_salonA);
    final Future<AvatarChangeResult> f = c.add(MediaPickSource.gallery);
    await until(() => uploads.uploaded.isNotEmpty);
    uploads.progress.single.add(0.97);
    await until(() => pending(_salonA).single.progress == 0.97);
    uploads.progress.single.add(1.0);
    await until(() => pending(_salonA).single.progress == 1.0);
    uploads.results.single.complete(_fresh);
    await f;
  });

  test('failure keeps the entry + file; retry re-sends the SAME file and '
      'succeeds', () async {
    final PortfolioEditController c = ctrl(_master);
    final Future<AvatarChangeResult> f = c.add(MediaPickSource.camera);
    await until(() => uploads.uploaded.isNotEmpty);
    uploads.results.single.completeError(const UploadNetworkFailure());

    final AvatarChangeResult r = await f;
    expect(r, isA<AvatarChangeFailed>());
    expect((r as AvatarChangeFailed).failure, isA<UploadNetworkFailure>());
    final PendingPortfolioUpload failed = pending(_master).single;
    expect(failed.failure, isA<UploadNetworkFailure>());
    expect(failed.file.existsSync(), isTrue, reason: 'kept for retry');
    expect(c.canAdd, isTrue, reason: 'a failed entry is not in flight');

    final Future<AvatarChangeResult> again = c.retry(failed.id);
    await until(() => uploads.uploaded.length == 2);
    expect(uploads.uploaded[1].$2.path, failed.file.path);
    expect(gw.pickSources, hasLength(1), reason: 'no second picker');
    uploads.results[1].complete(_fresh);
    expect(await again, isA<AvatarChangeSucceeded>());
    expect(pending(_master), isEmpty);
    expect(failed.file.existsSync(), isFalse);
  });

  test('a server 409 limit surfaces as PortfolioLimitReachedFailure on the '
      'entry and the result', () async {
    final PortfolioEditController c = ctrl(_salonA);
    final Future<AvatarChangeResult> f = c.add(MediaPickSource.gallery);
    await until(() => uploads.uploaded.isNotEmpty);
    uploads.results.single.completeError(const PortfolioLimitReachedFailure());
    final AvatarChangeResult r = await f;
    expect(
      (r as AvatarChangeFailed).failure,
      isA<PortfolioLimitReachedFailure>(),
    );
    expect(
      pending(_salonA).single.failure,
      isA<PortfolioLimitReachedFailure>(),
    );
  });

  test('discard drops a failed entry and deletes its file', () async {
    final PortfolioEditController c = ctrl(_salonA);
    final Future<AvatarChangeResult> f = c.add(MediaPickSource.gallery);
    await until(() => uploads.uploaded.isNotEmpty);
    uploads.results.single.completeError(const UploadBusyFailure());
    await f;
    final PendingPortfolioUpload failed = pending(_salonA).single;

    await c.discard(failed.id);
    expect(pending(_salonA), isEmpty);
    expect(failed.file.existsSync(), isFalse);
    expect(uploads.uploaded, hasLength(1), reason: 'nothing re-sent');
  });

  test('ONE upload at a time: add / retry are refused while one is in '
      'flight', () async {
    final PortfolioEditController c = ctrl(_salonA);
    final Future<AvatarChangeResult> first = c.add(MediaPickSource.gallery);
    await until(() => uploads.uploaded.isNotEmpty);
    expect(c.canAdd, isFalse);

    expect(await c.add(MediaPickSource.gallery), isA<AvatarChangeCancelled>());
    expect(gw.pickSources, hasLength(1), reason: 'no second picker');
    expect(uploads.uploaded, hasLength(1));

    uploads.results.single.complete(_fresh);
    await first;
    expect(c.canAdd, isTrue);
  });

  test('add is also refused while a pick is still open', () async {
    final PortfolioEditController c = ctrl(_salonA);
    gw.holdPick = Completer<void>();
    final Future<AvatarChangeResult> first = c.add(MediaPickSource.gallery);
    await until(() => gw.pickedPath != null);
    expect(c.canAdd, isFalse);
    expect(await c.add(MediaPickSource.gallery), isA<AvatarChangeCancelled>());
    gw.holdPick!.complete();
    await until(() => uploads.uploaded.isNotEmpty);
    uploads.results.single.complete(_fresh);
    await first;
    expect(uploads.uploaded, hasLength(1));
  });

  test('dispose mid-upload cancels the task and deletes the file', () async {
    final ProviderSubscription<List<PendingPortfolioUpload>> sub = container
        .listen(portfolioEditControllerProvider(_salonA), (_, _) {});
    final Future<AvatarChangeResult> f = container
        .read(portfolioEditControllerProvider(_salonA).notifier)
        .add(MediaPickSource.gallery);
    await until(() => uploads.uploaded.isNotEmpty);
    final File file = uploads.uploaded.single.$2;

    sub.close();
    await until(() => uploads.cancelCalls == 1);
    expect(await f, isA<AvatarChangeCancelled>());
    expect(file.existsSync(), isFalse);
  });

  test('an account switch drops a kept failed file — never retried under '
      'another user', () async {
    final PortfolioEditController c = ctrl(_salonA);
    final Future<AvatarChangeResult> f = c.add(MediaPickSource.gallery);
    await until(() => uploads.uploaded.isNotEmpty);
    uploads.results.single.completeError(const UploadNetworkFailure());
    await f;
    final PendingPortfolioUpload failed = pending(_salonA).single;

    (container.read(authProvider.notifier) as _Auth).switchTo('user-2');
    await until(() => pending(_salonA).isEmpty);
    // P3: the dispose-time delete is async (fire-and-forget), not sync I/O.
    await until(() => !failed.file.existsSync());
    expect(await c.retry(failed.id), isA<AvatarChangeCancelled>());
    expect(uploads.uploaded, hasLength(1));
  });

  test('at the 30-photo cap (cached), add fails fast with the limit '
      'failure — no picker, no request', () async {
    uploads.masterPhotos = List<PortfolioPhoto>.generate(
      kPortfolioMaxPhotos,
      (int i) => PortfolioPhoto(id: 'p$i', url: 'https://m.test/$i.jpg'),
    );
    await loadStored(_master);
    final AvatarChangeResult r = await ctrl(
      _master,
    ).add(MediaPickSource.gallery);
    expect(
      (r as AvatarChangeFailed).failure,
      isA<PortfolioLimitReachedFailure>(),
    );
    expect(gw.pickSources, isEmpty);
    expect(uploads.uploaded, isEmpty);
  });

  test('below the cap (29), add proceeds', () async {
    uploads.masterPhotos = List<PortfolioPhoto>.generate(
      kPortfolioMaxPhotos - 1,
      (int i) => PortfolioPhoto(id: 'p$i', url: 'https://m.test/$i.jpg'),
    );
    await loadStored(_master);
    final Future<AvatarChangeResult> f = ctrl(
      _master,
    ).add(MediaPickSource.gallery);
    await until(() => uploads.uploaded.isNotEmpty);
    uploads.results.single.complete(_fresh);
    expect(await f, isA<AvatarChangeSucceeded>());
  });

  group('P5: the cap counts pending entries too', () {
    test('29 stored + 1 failed upload kept → add refused, no picker', () async {
      uploads.masterPhotos = List<PortfolioPhoto>.generate(
        kPortfolioMaxPhotos - 1,
        (int i) => PortfolioPhoto(id: 'p$i', url: 'https://m.test/$i.jpg'),
      );
      await loadStored(_master);
      await leaveOneFailed(_master);
      final int picks = gw.pickSources.length;

      final AvatarChangeResult r = await ctrl(
        _master,
      ).add(MediaPickSource.gallery);

      expect(
        (r as AvatarChangeFailed).failure,
        isA<PortfolioLimitReachedFailure>(),
      );
      expect(gw.pickSources, hasLength(picks), reason: 'no second picker');
      expect(uploads.uploaded, hasLength(1), reason: 'nothing new sent');
    });

    test('...and discarding that failed entry frees the slot', () async {
      uploads.masterPhotos = List<PortfolioPhoto>.generate(
        kPortfolioMaxPhotos - 1,
        (int i) => PortfolioPhoto(id: 'p$i', url: 'https://m.test/$i.jpg'),
      );
      await loadStored(_master);
      await leaveOneFailed(_master);
      final PortfolioEditController c = ctrl(_master);
      await c.discard(pending(_master).single.id);

      final Future<AvatarChangeResult> f = c.add(MediaPickSource.gallery);
      await until(() => uploads.uploaded.length == 2);
      uploads.results.last.complete(_fresh);
      expect(await f, isA<AvatarChangeSucceeded>());
    });

    test('with nothing cached, 30 pending entries alone hit the cap', () async {
      final PortfolioEditController c = ctrl(_salonA);
      for (var i = 0; i < kPortfolioMaxPhotos; i++) {
        final Future<AvatarChangeResult> f = c.add(MediaPickSource.gallery);
        await until(() => uploads.uploaded.length == i + 1);
        uploads.results.last.completeError(const UploadNetworkFailure());
        await f;
      }
      expect(pending(_salonA), hasLength(kPortfolioMaxPhotos));
      final AvatarChangeResult r = await c.add(MediaPickSource.gallery);
      expect(
        (r as AvatarChangeFailed).failure,
        isA<PortfolioLimitReachedFailure>(),
      );
      expect(uploads.uploaded, hasLength(kPortfolioMaxPhotos));
    });
  });

  group('delete', () {
    test('success → DELETE for THIS owner, and the id is gone from the '
        'stored list', () async {
      await loadStored(_salonA);
      final AvatarChangeResult r = await ctrl(_salonA).delete('stored');
      expect(r, isA<AvatarChangeSucceeded>());
      expect(uploads.deletes.single, (_salonA, 'stored'));
      expect(await storedIds(_salonA), <String>['older']);
    });

    test('P2: success removes the id LOCALLY — the server list is not '
        're-read (it still has the row here)', () async {
      await loadStored(_salonA);
      expect(
        await ctrl(_salonA).delete('stored'),
        isA<AvatarChangeSucceeded>(),
      );
      expect(
        container.read(portfolioProvider(_salonA)).value,
        const <PortfolioPhoto>[_older],
      );
      // The sync read above also passes mid-refetch (stale-while-revalidate
      // keeps the patched value); the settled read is what pins "no refetch".
      expect(await storedIds(_salonA), <String>['older']);
    });

    test('404 → succeeds quietly, removes the id locally at once, THEN '
        're-syncs: the settled list is what the server returns', () async {
      await loadStored(_salonA);
      uploads.deleteFailure = const UploadNotFoundFailure();
      final AvatarChangeResult r = await ctrl(_salonA).delete('stored');
      expect(r, isA<AvatarChangeSucceeded>());
      // Immediate: the local removal is visible while the re-read runs.
      expect(
        container.read(portfolioProvider(_salonA)).value,
        const <PortfolioPhoto>[_older],
      );
      // Settled: the server still has the row (the 404 had another cause),
      // so the re-read brings it back — the list matches the server.
      expect(await storedIds(_salonA), <String>['stored', 'older']);
    });

    test('ONE delete at a time: a second delete while one is in flight is '
        'refused with no request; the guard is released after', () async {
      await loadStored(_salonA);
      final Completer<void> hold = Completer<void>();
      uploads.holdDelete = hold;
      final PortfolioEditController c = ctrl(_salonA);
      final Future<AvatarChangeResult> first = c.delete('stored');
      await until(() => uploads.deletes.isNotEmpty);

      expect(await c.delete('older'), isA<AvatarChangeCancelled>());
      expect(uploads.deletes, <(PortfolioOwner, String)>[(_salonA, 'stored')]);

      hold.complete();
      expect(await first, isA<AvatarChangeSucceeded>());
      expect(await c.delete('older'), isA<AvatarChangeSucceeded>());
      expect(await storedIds(_salonA), isEmpty);
    });

    test('403 → failed, stored list unchanged', () async {
      await loadStored(_salonA);
      uploads.deleteFailure = const UploadForbiddenFailure();
      final AvatarChangeResult r = await ctrl(_salonA).delete('stored');
      expect((r as AvatarChangeFailed).failure, isA<UploadForbiddenFailure>());
      expect(await storedIds(_salonA), <String>['stored', 'older']);
    });

    test('network failure → failed, stored list unchanged', () async {
      await loadStored(_salonA);
      uploads.deleteFailure = const UploadNetworkFailure();
      final AvatarChangeResult r = await ctrl(_salonA).delete('older');
      expect((r as AvatarChangeFailed).failure, isA<UploadNetworkFailure>());
      expect(await storedIds(_salonA), <String>['stored', 'older']);
    });

    test('an upload failure leaves the stored list unchanged', () async {
      await loadStored(_salonA);
      await leaveOneFailed(_salonA);
      expect(await storedIds(_salonA), <String>['stored', 'older']);
    });
  });

  group('lost-pick recovery (Android)', () {
    test(
      'the pending tag is kind=portfolio, scoped to THIS portfolio',
      () async {
        gw.holdPick = Completer<void>();
        final Future<AvatarChangeResult> f = ctrl(
          _salonA,
        ).add(MediaPickSource.gallery);
        await until(() => gw.pickedPath != null);
        final PendingPick? tag = await PendingPickStore(storage).read();
        expect(tag?.kind, MediaKind.portfolio);
        expect(tag?.scope, 'portfolio:salon:salon-a');
        gw.holdPick!.complete();
        await until(() => uploads.uploaded.isNotEmpty);
        uploads.results.single.complete(_fresh);
        await f;
        expect(await PendingPickStore(storage).read(), isNull);
      },
    );

    test(
      'a pick for salon A is resumed by salon A and uploaded there',
      () async {
        await PendingPickStore(storage).begin(
          'user-1',
          MediaKind.portfolio,
          scope: 'portfolio:salon:salon-a',
        );
        gw.lost = 'x';
        final Future<AvatarChangeResult> r = ctrl(_salonA).recoverLost();
        await until(() => uploads.uploaded.isNotEmpty);
        expect(uploads.uploaded.single.$1, _salonA);
        uploads.results.single.complete(_fresh);
        expect(await r, isA<AvatarChangeSucceeded>());
      },
    );

    test('a pick for salon A is drained — never resumed — by salon B or the '
        'master portfolio', () async {
      for (final PortfolioOwner other in <PortfolioOwner>[_salonB, _master]) {
        await PendingPickStore(storage).begin(
          'user-1',
          MediaKind.portfolio,
          scope: 'portfolio:salon:salon-a',
        );
        gw.lost = 'x';
        expect(await ctrl(other).recoverLost(), isA<AvatarChangeCancelled>());
        expect(uploads.uploaded, isEmpty, reason: '$other');
        expect(File(gw.pickedPath!).existsSync(), isFalse, reason: 'drained');
      }
    });

    test('another user\'s pick is drained', () async {
      await PendingPickStore(
        storage,
      ).begin('user-2', MediaKind.portfolio, scope: 'portfolio:salon:salon-a');
      gw.lost = 'x';
      expect(await ctrl(_salonA).recoverLost(), isA<AvatarChangeCancelled>());
      expect(uploads.uploaded, isEmpty);
    });
  });
}
