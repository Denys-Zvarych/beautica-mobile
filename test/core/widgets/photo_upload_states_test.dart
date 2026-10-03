// Phase 072 — upload / image states on the existing photo widgets.
//
// Covers the additive params only; the default (no-arg) renders are pinned by
// the goldens in test/golden/{neumorphic_avatar_editor,profile_avatar,
// service_photo_slot,photo_thumbnail}_golden_test.dart.

import 'dart:io';

import 'package:beautica_mobile/core/media/beautica_image.dart';
import 'package:beautica_mobile/core/media/local_preview_image.dart';
import 'package:beautica_mobile/core/media/media_config.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/core/widgets/upload_state_overlay.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/profile_avatar.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_category_list.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_photo_slot.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_media_cache.dart';
import '../../helpers/pump_app.dart';

const String _kHost = 'media.test';

// The editor's `semanticLabel` default (a pre-existing literal, not new copy).
final String _editorLabel = const NeumorphicAvatarEditor(
  state: AvatarEditState.pristine,
  initials: '',
  onTap: _noop,
).semanticLabel;

void _noop() {}

final AppLocalizations _l10n = lookupAppLocalizations(const Locale('uk'));

Widget _editor({
  AvatarEditState state = AvatarEditState.picking,
  double? progress,
  bool failed = false,
  VoidCallback? onRetry,
  VoidCallback? onTap,
  File? preview,
}) => NeumorphicAvatarEditor(
  state: state,
  initials: 'ДЗ',
  onTap: onTap ?? () {},
  progress: progress,
  uploadFailed: failed,
  onRetry: onRetry,
  previewFile: preview,
);

CircularProgressIndicator _ring(WidgetTester t) =>
    t.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator));

void main() {
  late FakeMediaCacheManager fake;

  setUp(() {
    MediaConfig.debugAllowedHosts = <String>{_kHost};
    fake = FakeMediaCacheManager(mediaLoadingForever);
    debugMediaCacheManager = fake;
  });
  tearDown(() {
    debugMediaCacheManager = null;
    MediaConfig.debugAllowedHosts = null;
  });

  group('NeumorphicAvatarEditor', () {
    testWidgets('picking + progress: determinate ring and % in semantics', (
      tester,
    ) async {
      final SemanticsHandle h = tester.ensureSemantics();
      await tester.pumpApp(_editor(progress: 0.4));
      await tester.pump();

      expect(_ring(tester).value, 0.4);
      expect(
        tester.getSemantics(find.byType(NeumorphicAvatarEditor)),
        matchesSemantics(
          label: _editorLabel,
          value: '40%',
          isButton: true,
          hasEnabledState: true,
        ),
      );
      h.dispose();
    });

    testWidgets('picking without progress stays indeterminate (no value)', (
      tester,
    ) async {
      await tester.pumpApp(_editor());
      await tester.pump();
      expect(_ring(tester).value, isNull);
    });

    testWidgets('progress 1.0 is NOT shown as done: ring indeterminate, '
        'announced at most 99%', (tester) async {
      final SemanticsHandle h = tester.ensureSemantics();
      await tester.pumpApp(_editor(progress: 1.0));
      await tester.pump();

      expect(_ring(tester).value, isNull);
      expect(
        tester.getSemantics(find.byType(NeumorphicAvatarEditor)).value,
        '99%',
      );
      h.dispose();
    });

    testWidgets('failed: retry fires the callback; target is >= 48 dp', (
      tester,
    ) async {
      int retries = 0;
      await tester.pumpApp(
        _editor(
          state: AvatarEditState.loaded,
          failed: true,
          onRetry: () => retries++,
        ),
      );
      await tester.pump();

      final Size target = tester.getSize(find.byKey(const Key('upload-retry')));
      expect(target.width, greaterThanOrEqualTo(kUploadRetryTarget));
      expect(target.height, greaterThanOrEqualTo(kUploadRetryTarget));

      await tester.tap(find.byKey(const Key('upload-retry')));
      await tester.pump();
      expect(retries, 1);
    });

    testWidgets('no failed flag: no retry affordance (default render)', (
      tester,
    ) async {
      await tester.pumpApp(_editor(state: AvatarEditState.loaded));
      await tester.pump();
      expect(find.byKey(const Key('upload-retry')), findsNothing);
    });

    testWidgets('previewFile uses the local path and opens no socket', (
      tester,
    ) async {
      await tester.pumpApp(
        _editor(
          state: AvatarEditState.loaded,
          preview: File('/tmp/media_upload/preview.jpg'),
        ),
      );
      await tester.pump();
      expect(find.byType(LocalPreviewImage), findsOneWidget);
      expect(find.byType(RemoteImage), findsNothing);
      expect(fake.getFileStreamCalls, 0);
    });
  });

  group('ServicePhotoSlot', () {
    testWidgets('ignores taps while uploadProgress != null; chip hidden', (
      tester,
    ) async {
      int taps = 0;
      await tester.pumpApp(
        SizedBox(
          width: 280,
          child: ServicePhotoSlot(
            imageUrl: 'https://$_kHost/p.png',
            onTap: () => taps++,
            uploadProgress: 0.4,
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(ServicePhotoSlot));
      await tester.pump();
      expect(taps, 0);
      expect(find.text(_l10n.servicePhotoChange), findsNothing);
      expect(_ring(tester).value, 0.4);
    });

    testWidgets('taps still work with no upload state (default behaviour)', (
      tester,
    ) async {
      int taps = 0;
      await tester.pumpApp(
        SizedBox(
          width: 280,
          child: ServicePhotoSlot(
            imageUrl: 'https://$_kHost/p.png',
            onTap: () => taps++,
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byType(ServicePhotoSlot));
      await tester.pump();
      expect(taps, 1);
      expect(find.text(_l10n.servicePhotoChange), findsOneWidget);
    });

    testWidgets('uploading exposes % in semantics, capped below 100', (
      tester,
    ) async {
      final SemanticsHandle h = tester.ensureSemantics();
      await tester.pumpApp(
        const SizedBox(
          width: 280,
          child: ServicePhotoSlot(uploadProgress: 1.0),
        ),
      );
      await tester.pump();
      expect(_ring(tester).value, isNull);
      final node = tester
          .getSemantics(find.byType(ServicePhotoSlot))
          .getSemanticsData();
      expect(node.label, contains(_l10n.photoUploading));
      expect(node.value, '99%');
      h.dispose();
    });

    testWidgets('failed: message + retry callback; text-scale 1.3 does not '
        'overflow', (tester) async {
      int retries = 0;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpApp(
        SizedBox(
          width: 280,
          child: ServicePhotoSlot(
            imageUrl: 'https://$_kHost/p.png',
            onTap: () {},
            uploadFailed: true,
            onRetry: () => retries++,
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('upload-failed-message')), findsOneWidget);
      await tester.tap(find.byKey(const Key('upload-retry')));
      await tester.pump();
      expect(retries, 1);
      expect(tester.takeException(), isNull);
    });
  });

  group('network surface is still the allow-list only', () {
    testWidgets('ProfileAvatar with a non-allow-listed host fetches nothing', (
      tester,
    ) async {
      await tester.pumpApp(
        const ProfileAvatar(imageUrl: 'https://evil.test/p.png'),
      );
      await tester.pump();
      expect(fake.getFileStreamCalls, 0);
      expect(find.byIcon(Icons.person_outline), findsOneWidget);
    });

    testWidgets('PhotoThumbnail: null url renders no RemoteImage; '
        'disallowed host fetches nothing', (tester) async {
      await tester.pumpApp(const PhotoThumbnail());
      expect(find.byType(RemoteImage), findsNothing);

      await tester.pumpApp(
        const PhotoThumbnail(photoUrl: 'http://media.test/p.png'),
      );
      await tester.pump();
      expect(fake.getFileStreamCalls, 0);
      expect(find.byIcon(Icons.spa_rounded), findsOneWidget);
    });

    testWidgets('an allow-listed URL DOES reach the cache (positive control)', (
      tester,
    ) async {
      await tester.pumpApp(
        const ProfileAvatar(imageUrl: 'https://$_kHost/p.png'),
      );
      await tester.pump();
      expect(fake.getFileStreamCalls, 1);
    });
  });
}
