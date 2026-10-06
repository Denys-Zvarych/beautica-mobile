// Phase 070 — fake-backed E2E for the shared media-upload seam.
//
// There is no UI in this phase (the avatar screen lands in 073), so this drives
// the REAL `mediaUploadRepositoryProvider` -> app `dioProvider` wiring over the
// shared `FakeBackend` (its Dio is injected into `dioProvider` exactly as every
// other flow does), proving `POST` / `DELETE /api/v1/media/avatar` are routed
// and that phase 073 can rely on the seam:
//   • a multipart POST reaches the fake and resolves to the public URL
//   • 413 / 503 from the fake surface as typed `UploadFailure`s
//   • DELETE is routed (204)
//
// Plain `test()` (not `testWidgets`): real `dart:io` file reads never complete
// under the widget tester's FakeAsync zone.
//
// Runs headless: `flutter test integration_test/media_avatar_upload_flow_test.dart
// -d flutter-tester`.

import 'dart:io';

import 'package:beautica_mobile/core/media/upload/media_upload_repository.dart';
import 'package:beautica_mobile/core/media/upload/upload_failure.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/fakes/fake_secure_storage.dart';
import 'support/app_harness.dart';
import 'support/e2e_boot_policy.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late File photo;
  late FakeBackend fb;
  late ProviderContainer container;

  // The failure status is a CONSTRUCTOR argument (routes are wired once), so
  // each test picks its backend, then reads the repo from a fresh container.
  void useBackend(FakeBackend backend) {
    fb = backend;
    container = ProviderContainer(
      overrides: e2eProviderOverrides(
        fakeBackend: fb,
        storage: FakeSecureStorage(),
      ).cast(),
    );
    addTearDown(container.dispose);
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('media_e2e');
    photo = File('${tmp.path}/avatar.jpg')
      ..writeAsBytesSync(<int>[0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);
    useBackend(FakeBackend());
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  MediaUploadRepository repo() => container.read(mediaUploadRepositoryProvider);

  test(
    'POST /media/avatar through the app Dio resolves to the public URL, '
    'reports progress ending at 1.0 and the fake saw exactly one call',
    () async {
      final task = repo().uploadAvatar(photo);
      final progress = <double>[];
      task.progress.listen(progress.add);

      final url = await task.result;

      expect(url, 'https://media.test/avatars/u1/1.jpg');
      expect(fb.mediaAvatarUploadCalls, 1);
      expect(progress, isNotEmpty);
      expect(progress.last, 1.0);
    },
  );

  test('fake 413 surfaces as UploadTooLargeFailure', () async {
    useBackend(FakeBackend(mediaAvatarUploadStatus: 413));

    await expectLater(
      repo().uploadAvatar(photo).result,
      throwsA(isA<UploadTooLargeFailure>()),
    );
    expect(fb.mediaAvatarUploadCalls, 1);
  });

  test('fake 503 surfaces as UploadStorageUnavailableFailure', () async {
    useBackend(FakeBackend(mediaAvatarUploadStatus: 503));

    await expectLater(
      repo().uploadAvatar(photo).result,
      throwsA(isA<UploadStorageUnavailableFailure>()),
    );
  });

  test('DELETE /media/avatar is routed (204) and counted', () async {
    await repo().deleteAvatar();

    expect(fb.mediaAvatarDeleteCalls, 1);
    expect(fb.mediaAvatarUploadCalls, 0);
  });
}
