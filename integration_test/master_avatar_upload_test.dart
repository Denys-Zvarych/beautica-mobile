// Phase 073 — fake-backed E2E for the master avatar upload, end to end.
//
// Drives the REAL personal-info screen, REAL `AvatarUploadController`, REAL
// `MediaPickService` and REAL `HttpMediaUploadRepository` over the shared
// `FakeBackend`. Only the native pick/crop/compress plugin is replaced
// (`imagePickGatewayProvider`) by a fixture gateway that hands back
// `integration_test/fixtures/avatar.jpg` — the system Photo Picker and uCrop
// cannot run headless (they are covered by
// `patrol/avatar_pick_patrol_test.dart` on a device).
//
// Runs headless: `flutter test integration_test/master_avatar_upload_test.dart
// -d flutter-tester`.

import 'dart:async';
import 'dart:io';

import 'package:beautica_mobile/core/media/beautica_image.dart';
import 'package:beautica_mobile/core/media/media_config.dart';
import 'package:beautica_mobile/core/media/pick/crop_labels.dart';
import 'package:beautica_mobile/core/media/pick/image_pick_gateway.dart';
import 'package:beautica_mobile/core/media/pick/media_kind.dart';
import 'package:beautica_mobile/core/media/pick/media_pick_service.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/profile_avatar.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/fake_media_cache.dart';
import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

const String _fixture = 'integration_test/fixtures/avatar.jpg';
const String _firstUrl = 'https://media.test/avatars/u1/1.jpg';

/// Headless stand-in for the native pick → crop → compress plugins: hands the
/// fixture JPEG through the REAL `MediaPickService` pipeline.
final class _FixtureGateway implements ImagePickGateway {
  int picks = 0;
  bool cancelPick = false;
  CropLabels? lastCropLabels;

  @override
  Future<String?> pickImage(
    MediaPickSource source, {
    required int maxDimension,
  }) async {
    picks++;
    if (cancelPick) return null;
    return _fixture;
  }

  @override
  Future<String?> cropImage(
    String sourcePath, {
    required MediaSpec spec,
    required int quality,
    CropLabels? labels,
  }) async {
    lastCropLabels = labels;
    return sourcePath;
  }

  @override
  Future<String?> compress(
    String sourcePath,
    String targetPath, {
    required int maxWidth,
    required int maxHeight,
    required int quality,
    required bool keepExif,
  }) async {
    await File(sourcePath).copy(targetPath);
    return targetPath;
  }

  @override
  Future<String?> retrieveLostData() async => null;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installOverflowGuard();
    MediaConfig.debugAllowedHosts = <String>{'media.test'};
    // The real cache manager needs path_provider/sqflite; keep the fetch
    // pending so only the widget wiring (the URL) is under test.
    debugMediaCacheManager = FakeMediaCacheManager(mediaLoadingForever);
  });
  tearDown(() async {
    debugMediaCacheManager = null;
    MediaConfig.debugAllowedHosts = null;
    await AppHarness.tearDownHarness();
  });

  late _FixtureGateway gateway;
  late Directory scratch;

  Future<GoRouter> bootAs(
    WidgetTester tester,
    FakeBackend fb,
    UserRole role,
  ) async {
    gateway = _FixtureGateway();
    scratch = Directory.systemTemp.createTempSync('avatar_e2e');
    addTearDown(() => scratch.deleteSync(recursive: true));
    final GoRouter router = await AppHarness.boot(
      tester,
      fb,
      extraOverrides: <Object>[
        imagePickGatewayProvider.overrideWithValue(gateway),
        mediaPickServiceProvider.overrideWithValue(
          MediaPickService(gateway, tempDir: () async => scratch),
        ),
      ],
    );
    await AppHarness.loginAs(tester, fb, role);
    return router;
  }

  AppLocalizations l10n(WidgetTester t) =>
      AppLocalizations.of(t.element(find.byType(Scaffold).first));

  NeumorphicAvatarEditor editor(WidgetTester t) =>
      t.widget<NeumorphicAvatarEditor>(find.byType(NeumorphicAvatarEditor));

  Future<void> chooseFromGallery(WidgetTester tester) async {
    await AppHarness.tapVisible(
      tester,
      find.byKey(const Key('avatar-edit-badge')),
    );
    await AppHarness.pumpUntilFound(
      tester,
      find.byKey(const Key('image-source-gallery')),
    );
    await tester.tap(find.byKey(const Key('image-source-gallery')));
    await tester.pump();
  }

  List<String?> profileAvatarUrls(WidgetTester t) => find
      .byType(ProfileAvatar)
      .evaluate()
      .map((Element e) => (e.widget as ProfileAvatar).imageUrl)
      .toList();

  for (final (String, UserRole, String) c in <(String, UserRole, String)>[
    (
      'INDEPENDENT_MASTER',
      UserRole.independentMaster,
      RouteNames.masterEditPersonal,
    ),
    ('SALON_MASTER', UserRole.salonMaster, RouteNames.salonMasterEditPersonal),
  ]) {
    testWidgets('${c.$1}: gallery -> crop -> upload -> success snack; own '
        'profile then renders the new photo through RemoteImage', (
      tester,
    ) async {
      final FakeBackend fb = FakeBackend();
      final GoRouter router = await bootAs(tester, fb, c.$2);

      router.go(c.$3);
      await AppHarness.settle(tester);
      expect(editor(tester).state, AvatarEditState.pristine);

      await chooseFromGallery(tester);
      await AppHarness.pumpUntilFound(
        tester,
        find.text(l10n(tester).avatarUpdated),
      );

      expect(fb.mediaAvatarUploadCalls, 1);
      expect(gateway.picks, 1);
      expect(
        gateway.lastCropLabels?.title,
        l10n(tester).cropTitle,
        reason: 'the native crop screen gets the localised labels',
      );
      // The refetched profile carries the new URL; the editor shows it.
      await AppHarness.pumpUntilCondition(
        tester,
        () =>
            editor(tester).imageUrl == _firstUrl &&
            editor(tester).state == AvatarEditState.loaded,
        // The local preview is held (<= 2 s) until the remote photo is warm.
        description: 'editor to render the new avatar URL, preview released',
      );
      expect(editor(tester).state, AvatarEditState.loaded);
      // The scratch file was discarded.
      expect(
        Directory('${scratch.path}/$kMediaUploadDirName').existsSync()
            ? Directory('${scratch.path}/$kMediaUploadDirName').listSync()
            : <FileSystemEntity>[],
        isEmpty,
      );

      // Back on the own profile the avatar is a RemoteImage with the new URL.
      router.go(
        c.$2 == UserRole.salonMaster
            ? RouteNames.salonMasterProfile
            : RouteNames.masterProfile,
      );
      await AppHarness.settle(tester);
      await AppHarness.pumpUntilCondition(
        tester,
        () => profileAvatarUrls(tester).contains(_firstUrl),
        description: 'own-profile ProfileAvatar to carry the new URL',
      );
      expect(
        find.descendant(
          of: find.byType(ProfileAvatar),
          matching: find.byWidgetPredicate(
            (Widget w) => w is RemoteImage && w.url == _firstUrl,
          ),
        ),
        findsOneWidget,
      );
    });
  }

  testWidgets(
    '503 storage-off: error snack, avatar unchanged, the picked photo '
    'stays under the retry veil and a retry re-sends it to the server',
    (tester) async {
      final FakeBackend fb = FakeBackend(mediaAvatarUploadStatus: 503);
      final GoRouter router = await bootAs(
        tester,
        fb,
        UserRole.independentMaster,
      );

      router.go(RouteNames.masterEditPersonal);
      await AppHarness.settle(tester);

      await chooseFromGallery(tester);
      await AppHarness.pumpUntilFound(
        tester,
        find.text(l10n(tester).uploadErrorStorage),
      );

      expect(fb.mediaAvatarUploadCalls, 1);
      expect(fb.mediaAvatarUrl, isNull, reason: 'a 503 never sets the avatar');
      expect(editor(tester).uploadFailed, isTrue);
      expect(editor(tester).imageUrl, isNull);
      expect(find.text(l10n(tester).avatarUpdated), findsNothing);

      // The picked photo is KEPT under the retry veil (not discarded)...
      expect(editor(tester).previewFile, isNotNull);
      expect(editor(tester).previewFile!.existsSync(), isTrue);

      // ...and the retry target re-sends THAT file: a second request, no picker.
      await AppHarness.tapVisible(
        tester,
        find.byKey(const Key('upload-retry')),
      );
      await AppHarness.pumpUntilCondition(
        tester,
        () => fb.mediaAvatarUploadCalls == 2 && editor(tester).uploadFailed,
        description: 'the retry to reach POST /media/avatar and fail again',
      );
      expect(gateway.picks, 1, reason: 'retry must not reopen the picker');
      expect(
        find.byKey(const Key('image-source-gallery')),
        findsNothing,
        reason: 'retry must not reopen the source sheet',
      );
      expect(editor(tester).previewFile, isNotNull);

      // Hygiene: the snack host is a process-wide singleton; let this test's
      // error snack finish so it cannot pre-empt the next test's snacks.
      await AppHarness.pumpUntilGone(
        tester,
        find.text(l10n(tester).uploadErrorStorage),
        timeout: const Duration(seconds: 15),
      );
    },
  );

  testWidgets('remove: sheet shows the remove row once an avatar exists; '
      'DELETE reverts the editor to initials and snacks', (tester) async {
    final FakeBackend fb = FakeBackend();
    final GoRouter router = await bootAs(
      tester,
      fb,
      UserRole.independentMaster,
    );

    router.go(RouteNames.masterEditPersonal);
    await AppHarness.settle(tester);

    await chooseFromGallery(tester);
    await AppHarness.pumpUntilCondition(
      tester,
      () =>
          editor(tester).imageUrl == _firstUrl &&
          editor(tester).state == AvatarEditState.loaded,
      description: 'editor to render the uploaded avatar, preview released',
    );
    await AppHarness.pumpUntilGone(
      tester,
      find.text(l10n(tester).avatarUpdated),
      timeout: const Duration(seconds: 15),
    );

    await AppHarness.tapVisible(
      tester,
      find.byKey(const Key('avatar-edit-badge')),
    );
    await AppHarness.pumpUntilFound(
      tester,
      find.byKey(const Key('image-source-remove')),
    );
    await tester.tap(find.byKey(const Key('image-source-remove')));
    await AppHarness.pumpUntilFound(
      tester,
      find.text(l10n(tester).avatarRemoved),
    );

    expect(fb.mediaAvatarDeleteCalls, 1);
    expect(fb.mediaAvatarUrl, isNull);
    await AppHarness.pumpUntilCondition(
      tester,
      () => editor(tester).state == AvatarEditState.pristine,
      description: 'editor to fall back to initials',
    );
  });

  testWidgets('cancel at the picker: no upload, no snack, editor unchanged', (
    tester,
  ) async {
    final FakeBackend fb = FakeBackend();
    final GoRouter router = await bootAs(
      tester,
      fb,
      UserRole.independentMaster,
    );
    gateway.cancelPick = true;

    router.go(RouteNames.masterEditPersonal);
    await AppHarness.settle(tester);

    await chooseFromGallery(tester);
    await tester.pump(
      const Duration(milliseconds: 500),
    ); // fixed-wait-ok: negative assertion: nothing may happen after the cancel
    await tester.pump(
      const Duration(milliseconds: 500),
    ); // fixed-wait-ok: negative assertion: nothing may happen after the cancel

    expect(gateway.picks, 1);
    expect(fb.mediaAvatarUploadCalls, 0);
    expect(fb.mediaAvatarDeleteCalls, 0);
    expect(find.text(l10n(tester).avatarUpdated), findsNothing);
    expect(find.text(l10n(tester).uploadErrorStorage), findsNothing);
    expect(editor(tester).state, AvatarEditState.pristine);
    expect(editor(tester).uploadFailed, isFalse);
    expect(editor(tester).imageUrl, isNull);
  });

  testWidgets('propagation: a profile screen already on the stack picks up '
      'each new URL after pop (no remount), and the crop labels are all '
      'Ukrainian', (tester) async {
    final FakeBackend fb = FakeBackend();
    final GoRouter router = await bootAs(
      tester,
      fb,
      UserRole.independentMaster,
    );

    router.go(RouteNames.masterProfile);
    await AppHarness.settle(tester);
    expect(profileAvatarUrls(tester).whereType<String>(), isEmpty);

    // Edit screen pushed ON TOP of the live profile screen.
    unawaited(router.push<void>(RouteNames.masterEditPersonal));
    await AppHarness.settle(tester);

    await chooseFromGallery(tester);
    await AppHarness.pumpUntilCondition(
      tester,
      () => editor(tester).imageUrl == _firstUrl,
      description: 'editor to render the first uploaded avatar',
    );
    final CropLabels? labels = gateway.lastCropLabels;
    expect(labels, isNotNull);
    expect(labels!.title, 'Обрізати фото');
    expect(labels.doneButton, 'Готово');
    expect(labels.cancelButton, 'Скасувати');

    // Second upload -> a NEW url replaces the first.
    await AppHarness.pumpUntilGone(
      tester,
      find.text(l10n(tester).avatarUpdated),
      timeout: const Duration(seconds: 15),
    );
    await chooseFromGallery(tester);
    const String secondUrl = 'https://media.test/avatars/u1/2.jpg';
    await AppHarness.pumpUntilCondition(
      tester,
      () => editor(tester).imageUrl == secondUrl,
      description: 'editor to render the replaced avatar',
    );
    expect(fb.mediaAvatarUploadCalls, 2);

    router.pop();
    await AppHarness.settle(tester);
    await AppHarness.pumpUntilCondition(
      tester,
      () => profileAvatarUrls(tester).contains(secondUrl),
      description: 'underlying profile ProfileAvatar to carry the new URL',
    );
    expect(profileAvatarUrls(tester), isNot(contains(_firstUrl)));
  });
}
