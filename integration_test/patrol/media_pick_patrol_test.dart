// Phase 071 — patrol native check of the REAL gallery pick path.
//
// What only a device can prove (and `flutter test` cannot):
//   • the source sheet → gallery hands off to the system Photo Picker through
//     the real image_picker plugin, with NO runtime permission dialog (the app
//     declares no READ_MEDIA_IMAGES / READ_EXTERNAL_STORAGE);
//   • backing out of the native picker resolves `MediaPickService.pick` with
//     `null` (cancel contract) and the app is still alive.
//
// Not runnable on the Ubuntu dev VM (needs native instrumentation + an
// emulator): authored here, executed by the CI patrol emulator job or locally
// via `patrol test --target integration_test/patrol/media_pick_patrol_test.dart`.
// The crop + EXIF/GPS-strip outcome needs a geotagged sample pushed to the
// emulator and is covered by 073's avatar patrol flow + the manual acceptance
// check in the phase doc.

import 'dart:io' show Platform;

import 'package:beautica_mobile/core/media/pick/image_pick_gateway.dart';
import 'package:beautica_mobile/core/media/pick/image_source_sheet.dart';
import 'package:beautica_mobile/core/media/pick/media_kind.dart';
import 'package:beautica_mobile/core/media/pick/media_pick_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

void main() {
  patrolTest(
    'gallery pick opens the Photo Picker without a permission dialog; back -> null',
    // Android-only: the Photo Picker hand-off is an Android intent.
    skip: !Platform.isAndroid,
    config: const PatrolTesterConfig(settlePolicy: SettlePolicy.trySettle),
    ($) async {
      // Real plugins on purpose — this is the native path under test.
      final MediaPickService service = MediaPickService(ImagePickGatewayImpl());
      PickedImage? picked;
      var finished = false;

      await $.pumpWidget(
        MaterialApp(
          locale: const Locale('uk'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: Center(
                child: TextButton(
                  key: const Key('pick-open'),
                  onPressed: () async {
                    final ImageSourceChoice? choice =
                        await showImageSourceSheet(context);
                    if (choice == ImageSourceChoice.gallery) {
                      picked = await service.pick(
                        MediaKind.avatar,
                        MediaPickSource.gallery,
                      );
                      finished = true;
                    }
                  },
                  child: const Text('pick'),
                ),
              ),
            ),
          ),
        ),
      );

      await $(const Key('pick-open')).tap();
      await $(const Key('image-source-gallery')).tap();

      // The system Photo Picker is now in front; Photo Picker needs no
      // runtime permission.
      expect(await $.platform.mobile.isPermissionDialogVisible(), isFalse);

      await $.platform.android.pressBack();
      // Poll (bounded) for the native picker dismiss; no Flutter signal.
      const Duration step = Duration(milliseconds: 500);
      for (var i = 0; i < 10 && !finished; i++) {
        await $.pump(step);
      }

      expect(finished, isTrue);
      expect(picked, isNull);
    },
  );
}
