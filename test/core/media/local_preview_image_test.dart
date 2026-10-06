// Phase 072 audit-fix — LocalPreviewImage (decode bounds, eviction, scratch-dir
// guard, finite-width guard) plus the upload-path RepaintBoundary and the
// single-clip avatar invariants.

import 'dart:io';

import 'package:beautica_mobile/core/media/beautica_image.dart';
import 'package:beautica_mobile/core/media/local_preview_image.dart';
import 'package:beautica_mobile/core/media/media_config.dart';
import 'package:beautica_mobile/core/media/pick/image_pick_gateway.dart';
import 'package:beautica_mobile/core/media/pick/media_pick_service.dart';
import 'package:beautica_mobile/core/media/pick/media_scratch.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/core/widgets/upload_state_overlay.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_photo_slot.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_media_cache.dart';
import '../../helpers/pump_app.dart';

final File _a = File('/tmp/media_upload/a.jpg');
final File _b = File('/tmp/media_upload/b.jpg');

/// A completer that never completes — lets a test park an entry in the
/// ImageCache and watch it get evicted.
class _Parked extends ImageStreamCompleter {}

Future<ImageProvider> _park(File f, double w, double h, double dpr) async {
  final ImageProvider p = LocalPreviewImage.providerFor(f, w, h, dpr);
  final Object key = await p.obtainKey(ImageConfiguration.empty);
  PaintingBinding.instance.imageCache.putIfAbsent(key, _Parked.new);
  return p;
}

Future<bool> _cached(ImageProvider p) async => PaintingBinding
    .instance
    .imageCache
    .containsKey(await p.obtainKey(ImageConfiguration.empty));

Finder _boundariesIn(Finder of) =>
    find.descendant(of: of, matching: find.byType(RepaintBoundary));

void main() {
  setUp(() {
    MediaConfig.debugAllowedHosts = <String>{'media.test'};
    debugMediaCacheManager = FakeMediaCacheManager(mediaLoadingForever);
    PaintingBinding.instance.imageCache.clear();
  });
  tearDown(() {
    debugMediaCacheManager = null;
    MediaConfig.debugAllowedHosts = null;
  });

  group('isMediaScratchFile', () {
    test('accepts only <dir>/media_upload/<file>', () {
      expect(isMediaScratchFile(File('/data/cache/media_upload/x.jpg')), true);
      expect(isMediaScratchFile(File('/data/cache/other/x.jpg')), false);
      expect(
        isMediaScratchFile(File('/data/cache/media_upload/../x.jpg')),
        false,
      );
      expect(isMediaScratchFile(File('media_upload/x.jpg')), false);
      expect(isMediaScratchFile(File('/etc/passwd')), false);
    });

    // Phase 367 audit (security INFO): a parent folder that merely HAPPENS to
    // be named `media_upload` (e.g. inside a shared / external dir) is not
    // the pipeline's scratch dir — the full `<temp>/media_upload` parent is.
    test('with a known temp root, only <temp>/media_upload/<file> passes', () {
      const String root = '/data/user/0/app/cache';
      bool ok(String path) => isMediaScratchFile(File(path), tempRoot: root);

      expect(ok('$root/media_upload/x.jpg'), true);
      expect(ok('$root/./media_upload/x.jpg'), true);
      expect(ok('/sdcard/Download/media_upload/x.jpg'), false);
      expect(ok('$root/other/media_upload/x.jpg'), false);
      expect(ok('$root/media_upload/sub/x.jpg'), false);
      expect(ok('$root/media_upload/../media_upload2/x.jpg'), false);
    });

    test('the root MediaPickService resolves is the one enforced', () async {
      addTearDown(debugResetMediaScratchRoot);
      final Directory tmp = Directory.systemTemp.createTempSync('scratch_root');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final File inRoot = File('${tmp.path}/$kMediaUploadDirName/x.jpg');
      const String foreign = '/sdcard/Download/media_upload/x.jpg';

      // No root yet (debug build): the shape check alone.
      expect(isMediaScratchFile(File(foreign)), true);

      // Any temp-dir resolution registers the root (here via wipeAll).
      await MediaPickService(
        _NeverGateway(),
        tempDir: () async => tmp,
      ).wipeAll();

      expect(isMediaScratchFile(inRoot), true);
      expect(isMediaScratchFile(File(foreign)), false);
    });
  });

  group('LocalPreviewImage', () {
    testWidgets('bounds BOTH decode axes (ResizeImage, fit policy)', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpApp(
        Center(
          child: LocalPreviewImage(
            file: _a,
            width: 100,
            height: 60,
            fallback: const SizedBox.shrink(),
          ),
        ),
      );
      final ImageProvider p = tester.widget<Image>(find.byType(Image)).image;
      expect(p, isA<ResizeImage>());
      final ResizeImage r = p as ResizeImage;
      expect(r.width, 200);
      expect(r.height, 120);
      expect(r.policy, ResizeImagePolicy.fit);
      expect(r.imageProvider, isA<FileImage>());
    });

    test('non-finite / degenerate sizes never throw and stay bounded', () {
      for (final double bad in <double>[
        double.infinity,
        double.nan,
        double.negativeInfinity,
        0,
      ]) {
        expect(
          () => LocalPreviewImage.providerFor(_a, bad, bad, 2),
          returnsNormally,
        );
        expect(
          LocalPreviewImage.providerFor(_a, bad, bad, 2),
          isA<FileImage>(),
        );
      }
      final ImageProvider half = LocalPreviewImage.providerFor(
        _a,
        double.infinity,
        50,
        2,
      );
      expect((half as ResizeImage).width, isNull);
      expect(half.height, 100);
      expect(
        LocalPreviewImage.providerFor(_a, 10, 10, double.nan),
        isA<FileImage>(),
      );
    });

    testWidgets('an unbounded width renders without throwing', (tester) async {
      await tester.pumpApp(
        Center(
          child: LocalPreviewImage(
            file: _a,
            width: double.infinity,
            height: 60,
            fallback: const SizedBox.shrink(),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('evicts the old FileImage when the file changes', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      final ValueNotifier<File> n = ValueNotifier<File>(_a);
      addTearDown(n.dispose);
      final ImageProvider pa = await _park(_a, 80, 80, 1);
      await tester.pumpApp(
        Center(
          child: ValueListenableBuilder<File>(
            valueListenable: n,
            builder: (_, f, _) => LocalPreviewImage(
              file: f,
              width: 80,
              height: 80,
              fallback: const SizedBox.shrink(),
            ),
          ),
        ),
      );
      expect(await _cached(pa), isTrue);
      n.value = _b;
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      expect(await _cached(pa), isFalse);
    });

    testWidgets('evicts on dispose', (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      final ImageProvider pa = await _park(_a, 80, 80, 1);
      await tester.pumpApp(
        Center(
          child: LocalPreviewImage(
            file: _a,
            width: 80,
            height: 80,
            fallback: const SizedBox.shrink(),
          ),
        ),
      );
      expect(await _cached(pa), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      expect(await _cached(pa), isFalse);
    });

    testWidgets('rejects a file outside the scratch dir (assert in debug)', (
      tester,
    ) async {
      await tester.pumpApp(
        Center(
          child: LocalPreviewImage(
            file: File('/etc/passwd'),
            width: 40,
            height: 40,
            fallback: const SizedBox.shrink(),
          ),
        ),
      );
      expect(tester.takeException(), isA<AssertionError>());
    });
  });

  group('RepaintBoundary only on the upload path', () {
    testWidgets('ServicePhotoSlot: default has none in the overlay; uploading '
        'adds them', (tester) async {
      await tester.pumpApp(
        const SizedBox(
          width: 280,
          child: ServicePhotoSlot(imageUrl: 'https://media.test/p.png'),
        ),
      );
      final int base = _boundariesIn(
        find.byType(ServicePhotoSlot),
      ).evaluate().length;
      expect(find.byType(UploadProgressOverlay), findsNothing);

      await tester.pumpApp(
        const SizedBox(
          width: 280,
          child: ServicePhotoSlot(
            imageUrl: 'https://media.test/p.png',
            uploadProgress: 0.4,
          ),
        ),
      );
      expect(_boundariesIn(find.byType(UploadProgressOverlay)), findsOneWidget);
      expect(
        _boundariesIn(find.byType(ServicePhotoSlot)).evaluate().length,
        greaterThanOrEqualTo(base + 2),
      );
    });

    testWidgets('NeumorphicAvatarEditor: default adds none; picking adds the '
        'overlay + photo boundaries', (tester) async {
      await tester.pumpApp(
        NeumorphicAvatarEditor(
          state: AvatarEditState.loaded,
          initials: 'ДЗ',
          onTap: () {},
        ),
      );
      final int base = _boundariesIn(
        find.byType(NeumorphicAvatarEditor),
      ).evaluate().length;
      await tester.pumpApp(
        NeumorphicAvatarEditor(
          state: AvatarEditState.picking,
          initials: 'ДЗ',
          onTap: () {},
          progress: 0.5,
        ),
      );
      expect(_boundariesIn(find.byType(UploadProgressOverlay)), findsOneWidget);
      expect(
        _boundariesIn(find.byType(NeumorphicAvatarEditor)).evaluate().length,
        greaterThanOrEqualTo(base + 2),
      );
    });
  });
}

/// A gateway with nothing to pick and no lost record.
class _NeverGateway implements ImagePickGateway {
  @override
  Future<String?> retrieveLostData() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}
