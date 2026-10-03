// Phase 073 — patrol native check of the REAL avatar path on a device:
// personal-info edit -> avatar badge -> «Обрати з галереї» -> the Android
// Photo Picker (selected natively) -> the uCrop screen (Done tapped natively)
// -> the upload reaches the (fake) backend.
//
// Everything the app owns is real here (screen, controller, pick service, the
// plugin-backed `ImagePickGatewayImpl`, upload repository); only the network
// socket is the `FakeBackend`.
//
// PREREQUISITE — a JPEG in the device gallery. A device test cannot write to
// MediaStore, so seed it from the host BEFORE the run (see this folder's
// README, «Avatar pick seed»):
//   scripts/seed_gallery_fixture.sh   (adb push + MediaProvider scan; `--clean` removes it afterwards)
//
// The Photo Picker grid is Compose with locale-dependent content descriptions
// («Photo taken on …» / «Фото (знято …)»); the freshly seeded photo is the
// newest item, so the FIRST photo cell is selected.
//
// Asserts both outcomes the phase doc names: success against a 200 fake
// (success snack) and the storage-off 503 (storage-unavailable snack + the
// retry veil) — each proves the native path reached the upload.
//
// Run: patrol test --target integration_test/patrol/avatar_pick_patrol_test.dart

import 'dart:io' show Platform;

import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:patrol/patrol.dart';

import 'support/patrol_harness.dart';

const Duration _nativeTimeout = Duration(seconds: 60);

/// uCrop's Done (the toolbar check) — same selector as the EXIF patrol test.
const AndroidSelector _cropDone = AndroidSelector(
  resourceName: 'com.beautica.beautica_mobile:id/menu_crop',
);

AppLocalizations _l10n(PatrolIntegrationTester $) =>
    AppLocalizations.of($.tester.element(find.byType(Scaffold).first));

/// Selects the newest photo in the system Photo Picker. The grid's cell labels
/// are localised, so try each known locale's prefix; the picker closes on a
/// single-select tap.
Future<void> _pickFirstPhoto(PatrolIntegrationTester $) async {
  const List<String> photoLabelParts = <String>['Photo taken on', 'знято'];
  Object? last;
  for (final String part in photoLabelParts) {
    try {
      await $.platform.android.tap(
        AndroidSelector(contentDescriptionContains: part),
        timeout: part == photoLabelParts.first
            ? const Duration(seconds: 15)
            : _nativeTimeout,
      );
      await _confirmPickerSelection($);
      return;
    } on Object catch (e) {
      last = e;
    }
  }
  fail('no photo cell found in the Photo Picker: $last');
}

/// Some pickers (this repo's Samsung / Android 13 device) open the
/// GET_CONTENT Photo Picker in a confirm mode: the tap only CHECKS the photo
/// and a «Done» button commits it. Others return on the tap itself, so a
/// missing button is not an error.
Future<void> _confirmPickerSelection(PatrolIntegrationTester $) async {
  for (final String label in <String>['Done', 'Add', 'Готово', 'Додати']) {
    try {
      await $.platform.android.tap(
        AndroidSelector(text: label),
        timeout: const Duration(seconds: 4),
      );
      return;
    } on Object {
      // try the next label / the picker already closed
    }
  }
}

Future<void> _runAvatarPick(PatrolIntegrationTester $, FakeBackend fb) async {
  final GoRouter router = await PatrolHarness.boot($, fb);
  await PatrolHarness.loginAs($, fb, UserRole.independentMaster);
  router.go(RouteNames.masterEditPersonal);
  await $.pumpAndSettle();

  expect(
    $.tester
        .widget<NeumorphicAvatarEditor>(find.byType(NeumorphicAvatarEditor))
        .state,
    AvatarEditState.pristine,
  );

  await $(const Key('avatar-edit-badge')).tap();
  await $(const Key('image-source-gallery')).tap();

  // The system Photo Picker is in front: no runtime permission dialog.
  expect(await $.platform.mobile.isPermissionDialogVisible(), isFalse);
  await _pickFirstPhoto($);

  // uCrop (localised by CropLabels) — confirm the crop natively.
  await $.platform.android.tap(_cropDone, timeout: _nativeTimeout);
}

void main() {
  const PatrolTesterConfig config = PatrolTesterConfig(
    settlePolicy: SettlePolicy.trySettle,
  );

  tearDown(PatrolHarness.tearDownHarness);

  patrolTest(
    'avatar gallery pick through the Photo Picker and uCrop uploads and '
    'shows the success snack',
    skip: !Platform.isAndroid,
    config: config,
    ($) async {
      final FakeBackend fb = FakeBackend();
      await _runAvatarPick($, fb);

      await $(_l10n($).avatarUpdated).waitUntilVisible();
      expect(fb.mediaAvatarUploadCalls, 1);
      expect(fb.mediaAvatarUrl, isNotNull);
    },
  );

  patrolTest(
    'avatar upload against storage-off backend shows the storage-unavailable '
    'snack and the retry veil',
    skip: !Platform.isAndroid,
    config: config,
    ($) async {
      final FakeBackend fb = FakeBackend(mediaAvatarUploadStatus: 503);
      await _runAvatarPick($, fb);

      await $(_l10n($).uploadErrorStorage).waitUntilVisible();
      expect(fb.mediaAvatarUploadCalls, 1);
      expect(fb.mediaAvatarUrl, isNull);
      expect(
        $.tester
            .widget<NeumorphicAvatarEditor>(find.byType(NeumorphicAvatarEditor))
            .uploadFailed,
        isTrue,
      );

      // Retry re-sends the SAME photo (no picker, no second Photo Picker trip).
      await $(const Key('upload-retry')).tap();
      for (var i = 0; i < 50 && fb.mediaAvatarUploadCalls < 2; i++) {
        await $.tester.pump(
          const Duration(milliseconds: 100),
        ); // fixed-wait-ok: bounded poll of a real-async native step (loop exits on the condition)
      }
      expect(fb.mediaAvatarUploadCalls, 2);
    },
  );
}
