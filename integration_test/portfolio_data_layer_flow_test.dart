// Phase 403 (9.8) — fake-backed E2E for the UI-free portfolio data layer.
//
// There is no UI in this phase (the rail / add / delete land in 404 / 405),
// so this drives the REAL wiring end to end over the shared `FakeBackend`
// (its Dio injected into `dioProvider` exactly as every other flow does):
//
//   `PortfolioEditController` → `MediaPickService` (real pipeline over the
//   headless `FixtureAvatarGateway`) → `mediaUploadRepositoryProvider`
//   (`HttpMediaUploadRepository`, app Dio + `ErrorMapperInterceptor`) → wire;
//   `portfolioProvider` → `SalonRepository` / `MediaUploadRepository` → wire.
//
// It asserts OBSERVABLE outcomes only — the stored list a fresh read returns,
// the typed failure, the HTTP paths the fake saw — never how the controller
// refreshes its cache (an audit-fix pass changes invalidate → local
// prepend / remove; these tests must hold across that change).
//
// Plain `test()` (not `testWidgets`): real `dart:io` file reads never complete
// under the widget tester's FakeAsync zone (see media_avatar_upload_flow_test).
//
// Runs headless: `flutter test integration_test/portfolio_data_layer_flow_test.dart
// -d flutter-tester`.

import 'dart:io';

import 'package:beautica_mobile/core/media/pick/media_kind.dart';
import 'package:beautica_mobile/core/media/pick/media_pick_service.dart';
import 'package:beautica_mobile/core/media/portfolio/portfolio_edit_controller.dart';
import 'package:beautica_mobile/core/media/portfolio/portfolio_notifier.dart';
import 'package:beautica_mobile/core/media/portfolio/portfolio_owner.dart';
import 'package:beautica_mobile/core/media/portfolio/portfolio_photo.dart';
import 'package:beautica_mobile/core/media/upload/media_upload_repository.dart';
import 'package:beautica_mobile/core/media/upload/upload_failure.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/fakes/fake_secure_storage.dart';
import 'support/app_harness.dart';
import 'support/e2e_boot_policy.dart';
import 'support/fixture_avatar_gateway.dart';

const String _salonId = FakeBackend.kOwnerSalonId;
const PortfolioOwner _salon = PortfolioOwner.salon(_salonId);
const String _salonPath = '/api/v1/salons/$_salonId/portfolio';
const String _masterWritePath = '/api/v1/media/portfolio';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory scratch;
  late FakeBackend fb;
  late FixtureAvatarGateway gateway;
  late ProviderContainer container;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('portfolio_e2e');
    gateway = FixtureAvatarGateway();
    fb = FakeBackend(wirePortfolio: true);
    container = ProviderContainer(
      overrides: <Object>[
        ...e2eProviderOverrides(fakeBackend: fb, storage: FakeSecureStorage()),
        mediaPickServiceProvider.overrideWithValue(
          MediaPickService(gateway, tempDir: () async => scratch),
        ),
      ].cast(),
    );
    addTearDown(() {
      container.dispose();
      if (scratch.existsSync()) scratch.deleteSync(recursive: true);
    });
  });

  /// Signs [role] in through the REAL `AuthNotifier` → fake `/auth/login`.
  Future<void> signIn(UserRole role, String email) async {
    fb.currentRole = role;
    await container.read(authProvider.future);
    await container.read(authProvider.notifier).login(email, 'Password1!');
    expect(authUserIdOrNull(container.read(authProvider)), isNotNull);
  }

  Future<void> signInOwner() =>
      signIn(UserRole.salonOwner, 'owner@beautica.ua');

  PortfolioEditController edit(PortfolioOwner o) {
    container.listen(portfolioEditControllerProvider(o), (_, _) {});
    return container.read(portfolioEditControllerProvider(o).notifier);
  }

  /// The stored portfolio as the app reads it now (keeps it subscribed so a
  /// write's refresh is observed, like a mounted rail).
  Future<List<String>> storedIds(PortfolioOwner o) async {
    container.listen(portfolioProvider(o), (_, _) {});
    final List<PortfolioPhoto> photos = await container.read(
      portfolioProvider(o).future,
    );
    return <String>[for (final PortfolioPhoto p in photos) p.id];
  }

  UploadFailure failureOf(AvatarChangeResult r) {
    expect(r, isA<AvatarChangeFailed>());
    return (r as AvatarChangeFailed).failure;
  }

  test('salon owner adds a photo: one multipart POST (only `file`, sniffed '
      'image/jpeg) to the SALON path, and the salon portfolio then includes '
      'the stored photo, newest first', () async {
    await signInOwner();
    fb.ownerSalonPortfolioRows.add(fb.portfolioRow('SALON', _salonId));
    expect(await storedIds(_salon), <String>['pf-1']);

    final AvatarChangeResult r = await edit(
      _salon,
    ).add(MediaPickSource.gallery);

    expect(r, isA<AvatarChangeSucceeded>());
    expect(gateway.picks, 1);
    expect(fb.portfolioUploadUris.map((Uri u) => u.path), <String>[_salonPath]);
    expect(fb.portfolioUploadUris.single.query, isEmpty);
    expect(fb.portfolioUploadPartNames.single, <String>['file']);
    expect(fb.portfolioUploadContentTypes.single, 'image/jpeg');
    expect(await storedIds(_salon), <String>['pf-2', 'pf-1']);
    expect(container.read(portfolioEditControllerProvider(_salon)), isEmpty);
  });

  test('409 PORTFOLIO_LIMIT_REACHED surfaces as PortfolioLimitReachedFailure; '
      'the stored list is unchanged and the failed upload is kept', () async {
    await signInOwner();
    fb.ownerSalonPortfolioRows.add(fb.portfolioRow('SALON', _salonId));
    expect(await storedIds(_salon), <String>['pf-1']);
    fb.failPortfolioUploads(409, code: kPortfolioLimitReachedCode);

    final AvatarChangeResult r = await edit(_salon).add(MediaPickSource.camera);

    expect(failureOf(r), isA<PortfolioLimitReachedFailure>());
    expect(fb.portfolioUploadUris, hasLength(1));
    expect(
      container.read(portfolioEditControllerProvider(_salon)).single.failure,
      isA<PortfolioLimitReachedFailure>(),
    );
    expect(await storedIds(_salon), <String>['pf-1']);
  });

  test('a 409 WITHOUT the limit code is a plain conflict, never "limit '
      'reached"', () async {
    await signInOwner();
    fb.failPortfolioUploads(409, code: 'SOMETHING_ELSE');

    final AvatarChangeResult r = await edit(
      _salon,
    ).add(MediaPickSource.gallery);

    expect(failureOf(r), isA<UploadConflictFailure>());
  });

  test('503 with Retry-After surfaces as UploadBusyFailure (not limit '
      'reached); a retry re-sends the same photo and lands it', () async {
    await signInOwner();
    fb.failPortfolioUploads(503, retryAfterSeconds: 2);
    final PortfolioEditController c = edit(_salon);

    final UploadFailure f = failureOf(await c.add(MediaPickSource.gallery));

    expect(f, isA<UploadBusyFailure>());
    expect(f, isNot(isA<PortfolioLimitReachedFailure>()));
    expect((f as UploadBusyFailure).retryAfterSeconds, 2);

    fb.failPortfolioUploads(null);
    final String pendingId = container
        .read(portfolioEditControllerProvider(_salon))
        .single
        .id;
    expect(await c.retry(pendingId), isA<AvatarChangeSucceeded>());
    expect(gateway.picks, 1, reason: 'retry never re-opens the picker');
    expect(fb.portfolioUploadUris.map((Uri u) => u.path), <String>[
      _salonPath,
      _salonPath,
    ]);
    expect(await storedIds(_salon), <String>['pf-1']);
    expect(container.read(portfolioEditControllerProvider(_salon)), isEmpty);
  });

  test(
    '503 WITHOUT Retry-After stays UploadStorageUnavailableFailure',
    () async {
      await signInOwner();
      fb.failPortfolioUploads(503);

      final AvatarChangeResult r = await edit(
        _salon,
      ).add(MediaPickSource.gallery);

      expect(failureOf(r), isA<UploadStorageUnavailableFailure>());
    },
  );

  test('at the 30-photo cap the add is refused client-side: no picker, no '
      'request', () async {
    await signInOwner();
    for (var i = 0; i < kPortfolioMaxPhotos; i++) {
      fb.ownerSalonPortfolioRows.add(fb.portfolioRow('SALON', _salonId));
    }
    expect(await storedIds(_salon), hasLength(kPortfolioMaxPhotos));

    final AvatarChangeResult r = await edit(
      _salon,
    ).add(MediaPickSource.gallery);

    expect(failureOf(r), isA<PortfolioLimitReachedFailure>());
    expect(gateway.picks, 0);
    expect(fb.portfolioUploadUris, isEmpty);
  });

  test('salon owner deletes a photo: DELETE hits the salon path for THAT id '
      'and the salon portfolio no longer includes it', () async {
    await signInOwner();
    fb.ownerSalonPortfolioRows.addAll(<Map<String, dynamic>>[
      fb.portfolioRow('SALON', _salonId),
      fb.portfolioRow('SALON', _salonId),
    ]);
    expect(await storedIds(_salon), <String>['pf-1', 'pf-2']);

    final AvatarChangeResult r = await edit(_salon).delete('pf-1');

    expect(r, isA<AvatarChangeSucceeded>());
    expect(fb.portfolioDeleteUris.map((Uri u) => u.path), <String>[
      '$_salonPath/pf-1',
    ]);
    expect(await storedIds(_salon), <String>['pf-2']);
  });

  test('a delete answered 404 removes the photo at once, then re-syncs: the '
      'settled salon portfolio equals what the backend returns, and no '
      'error is surfaced', () async {
    await signInOwner();
    fb.ownerSalonPortfolioRows.addAll(<Map<String, dynamic>>[
      fb.portfolioRow('SALON', _salonId),
      fb.portfolioRow('SALON', _salonId),
    ]);
    expect(await storedIds(_salon), <String>['pf-1', 'pf-2']);
    fb.failPortfolioDeletes(404);

    final AvatarChangeResult r = await edit(_salon).delete('pf-1');

    expect(r, isA<AvatarChangeSucceeded>());
    expect(fb.portfolioDeleteUris.map((Uri u) => u.path), <String>[
      '$_salonPath/pf-1',
    ]);
    // Immediate: the local removal is visible before the re-read lands.
    expect(
      <String>[
        for (final PortfolioPhoto p
            in container.read(portfolioProvider(_salon)).value ??
                const <PortfolioPhoto>[])
          p.id,
      ],
      <String>['pf-2'],
    );
    // Settled: the 404 triggered a re-read; the fake kept both rows, so the
    // list re-syncs to exactly what the backend returns.
    final List<String> serverIds = <String>[
      for (final Map<String, dynamic> row in fb.ownerSalonPortfolioRows)
        row['id'] as String,
    ];
    expect(await storedIds(_salon), serverIds);
    expect(serverIds, <String>['pf-1', 'pf-2']);
    // No error surfaced: neither on the list nor as a pending entry.
    expect(container.read(portfolioProvider(_salon)).hasError, isFalse);
    expect(container.read(portfolioEditControllerProvider(_salon)), isEmpty);
  });

  test(
    'independent master (self) writes go to /api/v1/media/portfolio — '
    'never a salon path — and reads come from /masters/{id}/portfolio',
    () async {
      await signIn(UserRole.independentMaster, 'master@beautica.ua');
      final PortfolioOwner master = PortfolioOwner.masterSelf(fb.masterRowId);
      expect(await storedIds(master), isEmpty);

      final AvatarChangeResult added = await edit(
        master,
      ).add(MediaPickSource.gallery);

      expect(added, isA<AvatarChangeSucceeded>());
      expect(fb.portfolioUploadUris.map((Uri u) => u.path), <String>[
        _masterWritePath,
      ]);
      expect(fb.portfolioUploadUris.single.query, isEmpty);
      expect(fb.portfolioUploadPartNames.single, <String>['file']);
      expect(await storedIds(master), <String>['pf-1']);

      final AvatarChangeResult deleted = await edit(master).delete('pf-1');

      expect(deleted, isA<AvatarChangeSucceeded>());
      expect(fb.portfolioDeleteUris.map((Uri u) => u.path), <String>[
        '$_masterWritePath/pf-1',
      ]);
      expect(await storedIds(master), isEmpty);
      expect(fb.portfolioReadUris.map((Uri u) => u.path).toSet(), <String>{
        '/api/v1/masters/${fb.masterRowId}/portfolio',
      });
      expect(fb.ownerSalonPortfolioRows, isEmpty);
    },
  );
}
