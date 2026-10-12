// Phase 404 audit R3 — the opt-in COVER decode for square `BoxFit.cover`
// thumbnails (the portfolio tile).
//
// `beauticaResizedProvider` uses `ResizeImagePolicy.fit`, which bounds BOTH
// axes: a 1200×600 photo in a 216×216 decode box becomes 216×108, and the
// tile's `BoxFit.cover` then upscales the 108px short side 2× — soft. The
// cover decode keeps the short side at the box (432×216) instead.
//
// Pinned here:
//   1. `coverDecodeSize` arithmetic (short side == box, aspect kept, no
//      upscale, panorama long-side clamp);
//   2. the provider really hands that size to the decoder (`getTargetSize`),
//      end-to-end through the cached provider;
//   3. `RemoteImage` defaults to today's fit decode — every existing site is
//      unchanged — and only `decodeToCover: true` switches provider;
//   4. (audit S1) the provider is value-equal and keys synchronously when its
//      inner provider does, so a rebuild never blanks the tile for a frame.

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beautica_mobile/core/media/beautica_image.dart';
import 'package:beautica_mobile/core/media/media_config.dart';

import '../../helpers/fake_media_cache.dart';
import '../../helpers/pump_app.dart';

const String _kHost = 'pub-abc.r2.dev';

void main() {
  group('coverDecodeSize', () {
    void expectSize(ui.TargetImageSize s, int w, int h) {
      expect((s.width, s.height), (w, h));
    }

    test('landscape: short side (height) == box, aspect kept', () {
      expectSize(coverDecodeSize(1200, 600, 216, 216), 432, 216);
    });

    test('portrait: short side (width) == box, aspect kept', () {
      expectSize(coverDecodeSize(600, 1200, 216, 216), 216, 432);
    });

    test('square: exactly the box', () {
      expectSize(coverDecodeSize(1000, 1000, 216, 216), 216, 216);
    });

    test('short side already under the box: intrinsic size, no upscale', () {
      expectSize(coverDecodeSize(400, 100, 216, 216), 400, 100);
      expectSize(coverDecodeSize(50, 50, 216, 216), 50, 50);
    });

    test('panorama: long side clamped to factor × box, aspect kept', () {
      final ui.TargetImageSize s = coverDecodeSize(20000, 400, 216, 216);
      const int maxLong = 216 * kCoverDecodeMaxLongSideFactor;
      expect(s.width, inInclusiveRange(maxLong - 1, maxLong));
      // 50:1 aspect preserved within rounding: 864 / 50 ≈ 17.
      expect(s.height, inInclusiveRange(16, 18));
    });

    test('for every non-pathological source the short side covers the box '
        '(contrast: the fit policy would leave it under)', () {
      for (final (int w, int h) in <(int, int)>[
        (1200, 600),
        (600, 1200),
        (4032, 3024),
        (3024, 4032),
        (1080, 1920),
      ]) {
        final ui.TargetImageSize s = coverDecodeSize(w, h, 216, 216);
        expect(
          [s.width!, s.height!].reduce((int a, int b) => a < b ? a : b),
          greaterThanOrEqualTo(216),
          reason: '$w×$h',
        );
      }
    });
  });

  group('beauticaCoverResizedProvider → decoder', () {
    setUp(() {
      debugMediaCacheManager = FakeMediaCacheManager(mediaLoaded);
    });
    tearDown(() => debugMediaCacheManager = null);

    testWidgets('hands the cover target size to the decoder for a 1200×600 '
        'source in a 216×216 box', (WidgetTester tester) async {
      final ui.TargetImageSize? size = await _decodeTargetFor(
        tester,
        beauticaCoverResizedProvider('https://$_kHost/x.png', 216, 216),
        1200,
        600,
      );

      expect(size, isNotNull);
      expect((size!.width, size.height), (432, 216));
    });
  });

  group('cover provider identity + synchronous key (audit S1)', () {
    const String url = 'https://$_kHost/x.png';

    setUp(() {
      debugMediaCacheManager = FakeMediaCacheManager(mediaLoaded);
    });
    tearDown(() => debugMediaCacheManager = null);

    test('same (url, width, height) → == and same hashCode', () {
      final ImageProvider a = beauticaCoverResizedProvider(url, 216, 216);
      final ImageProvider b = beauticaCoverResizedProvider(url, 216, 216);
      expect(identical(a, b), isFalse);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('a different width, height or url → not ==', () {
      final ImageProvider base = beauticaCoverResizedProvider(url, 216, 216);
      expect(base, isNot(beauticaCoverResizedProvider(url, 217, 216)));
      expect(base, isNot(beauticaCoverResizedProvider(url, 216, 217)));
      expect(
        base,
        isNot(beauticaCoverResizedProvider('https://$_kHost/y.png', 216, 216)),
      );
      // Never equal to the FIT provider for the same box either.
      expect(base, isNot(beauticaResizedProvider(url, 216, 216)));
    });

    test('a synchronous inner key → obtainKey completes synchronously', () {
      final ImageProvider p = debugCoverResizedProviderOver(
        MemoryImage(kTransparentPng),
        width: 216,
        height: 216,
      );
      Object? key;
      p.obtainKey(ImageConfiguration.empty).then((Object k) => key = k);
      // No microtask has run: only a SynchronousFuture fires `then` inline.
      expect(key, isNotNull);
    });

    test('the real (CachedNetworkImageProvider) inner is synchronous too', () {
      Object? key;
      beauticaCoverResizedProvider(
        url,
        216,
        216,
      ).obtainKey(ImageConfiguration.empty).then((Object k) => key = k);
      expect(key, isNotNull);
    });

    test('an asynchronous inner key → falls back to an async future with '
        'the same structural key', () async {
      final ImageProvider p = debugCoverResizedProviderOver(
        _AsyncKeyImage(MemoryImage(kTransparentPng)),
        width: 216,
        height: 216,
      );
      Object? key;
      final Future<Object> f = p.obtainKey(ImageConfiguration.empty);
      unawaited(f.then((Object k) => key = k));
      expect(key, isNull);
      final Object resolved = await f;
      expect(key, isNotNull);
      expect(
        resolved,
        await debugCoverResizedProviderOver(
          _AsyncKeyImage(MemoryImage(kTransparentPng)),
          width: 216,
          height: 216,
        ).obtainKey(ImageConfiguration.empty),
      );
    });

    test('an asynchronous inner key that FAILS → obtainKey rejects with '
        'that same error (never hangs, never swallows it)', () async {
      final StateError boom = StateError('inner key failed');
      final ImageProvider p = debugCoverResizedProviderOver(
        _FailingAsyncKeyImage(boom),
        width: 216,
        height: 216,
      );
      await expectLater(
        p
            .obtainKey(ImageConfiguration.empty)
            .timeout(const Duration(seconds: 5)),
        throwsA(same(boom)),
      );
    });

    testWidgets('a parent rebuild of a loaded cover tile keeps the photo — '
        'no gradient-only (image == null) frame', (WidgetTester tester) async {
      MediaConfig.debugAllowedHosts = <String>{_kHost};
      addTearDown(() => MediaConfig.debugAllowedHosts = null);

      Widget tile(int generation) => RemoteImage(
        key: const Key('cover-tile'),
        url: url,
        width: 72,
        height: 72,
        borderRadius: BorderRadius.circular(16),
        decodeToCover: true,
        // A fresh fallback instance per generation forces a NEW RemoteImage
        // (and so a new provider instance) on every pump.
        fallback: SizedBox(key: ValueKey<int>(generation)),
      );

      await tester.pumpApp(tile(0));
      // Let the real decode of the 1×1 PNG finish.
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
        if (tester.widget<RawImage>(find.byType(RawImage)).image != null) {
          break;
        }
      }
      expect(
        tester.widget<RawImage>(find.byType(RawImage)).image,
        isNotNull,
        reason: 'precondition: the photo loaded',
      );

      for (var gen = 1; gen <= 3; gen++) {
        await tester.pumpApp(tile(gen));
        expect(
          tester.widget<RawImage>(find.byType(RawImage)).image,
          isNotNull,
          reason: 'rebuild #$gen showed the gradient-only (blank) state',
        );
      }
    });
  });

  group('RemoteImage — decode policy selection', () {
    setUp(() {
      MediaConfig.debugAllowedHosts = <String>{_kHost};
      debugMediaCacheManager = FakeMediaCacheManager(mediaLoadingForever);
    });
    tearDown(() {
      debugMediaCacheManager = null;
      MediaConfig.debugAllowedHosts = null;
    });

    Widget remote({bool? cover}) => RemoteImage(
      url: 'https://$_kHost/x.png',
      width: 72,
      height: 72,
      borderRadius: BorderRadius.circular(16),
      decodeToCover: cover ?? false,
      fallback: const SizedBox.shrink(),
    );

    testWidgets('default (every existing site): ResizeImage, fit policy — '
        'unchanged', (WidgetTester tester) async {
      await tester.pumpApp(
        RemoteImage(
          url: 'https://$_kHost/x.png',
          width: 72,
          height: 72,
          borderRadius: BorderRadius.circular(16),
          fallback: const SizedBox.shrink(),
        ),
      );
      final ImageProvider image = tester
          .widget<Image>(find.byType(Image))
          .image;
      expect(image, isA<ResizeImage>());
      expect((image as ResizeImage).policy, ResizeImagePolicy.fit);
    });

    testWidgets('decodeToCover: true → the cover provider, not ResizeImage', (
      WidgetTester tester,
    ) async {
      // Bytes are needed below to reach the decoder (the provider captures
      // the cache manager at construction, i.e. at pump).
      debugMediaCacheManager = FakeMediaCacheManager(mediaLoaded);
      await tester.pumpApp(remote(cover: true));
      final ImageProvider image = tester
          .widget<Image>(find.byType(Image))
          .image;
      expect(image, isNot(isA<ResizeImage>()));

      // mobile-qa (404 re-check) — `isNot(ResizeImage)` alone also passes for
      // an UNBOUNDED provider (full-resolution decode). Pin the decoder
      // really receives the cover size for the widget's 72px box × the
      // view's DPR: a 1200×600 source → short side == box.
      final int box = (72 * tester.view.devicePixelRatio).round();
      final ui.TargetImageSize? size = await _decodeTargetFor(
        tester,
        image,
        1200,
        600,
      );
      expect(size, isNotNull);
      expect((size!.width, size.height), (box * 2, box));
    });
  });
}

/// Drives [provider]'s `loadImage` with a stub decoder and returns the target
/// size its `getTargetSize` callback yields for an [intrinsicW]×[intrinsicH]
/// source. Times out (fails) if the provider never passes a callback — an
/// unbounded decode.
Future<ui.TargetImageSize?> _decodeTargetFor(
  WidgetTester tester,
  ImageProvider provider,
  int intrinsicW,
  int intrinsicH,
) => tester.runAsync(() async {
  final ImageProvider<Object> p = provider;
  final Object key = await p.obtainKey(ImageConfiguration.empty);
  final Completer<ui.TargetImageSize> captured =
      Completer<ui.TargetImageSize>();
  // ignore: invalid_use_of_protected_member
  final ImageStreamCompleter stream = p.loadImage(key, (
    ui.ImmutableBuffer buffer, {
    ui.TargetImageSizeCallback? getTargetSize,
  }) async {
    final ui.TargetImageSizeCallback? cb = getTargetSize;
    if (cb != null && !captured.isCompleted) {
      captured.complete(cb(intrinsicW, intrinsicH));
    }
    throw StateError('decode intentionally stubbed');
  });
  stream.addListener(
    ImageStreamListener((_, _) {}, onError: (Object _, StackTrace? _) {}),
  );
  return captured.future.timeout(const Duration(seconds: 5));
});

/// An inner provider whose key resolves ASYNCHRONOUSLY (a plain `Future`),
/// to pin `_CoverResizeImage.obtainKey`'s fallback path.
class _AsyncKeyImage extends ImageProvider<Object> {
  const _AsyncKeyImage(this.delegate);

  final MemoryImage delegate;

  @override
  Future<Object> obtainKey(ImageConfiguration configuration) =>
      Future<Object>.value(delegate);

  @override
  ImageStreamCompleter loadImage(Object key, ImageDecoderCallback decode) =>
      delegate.loadImage(delegate, decode);
}

/// An inner provider whose key resolution FAILS asynchronously, to pin
/// `_CoverResizeImage.obtainKey`'s `onError` → completer path.
class _FailingAsyncKeyImage extends ImageProvider<Object> {
  const _FailingAsyncKeyImage(this.error);

  final Object error;

  @override
  Future<Object> obtainKey(ImageConfiguration configuration) =>
      Future<Object>.error(error);

  @override
  ImageStreamCompleter loadImage(Object key, ImageDecoderCallback decode) =>
      throw UnimplementedError('key never resolves');
}
