// Phase 073 audit — the picked photo must stay CLEARLY visible while it uploads
// and when the upload failed. The 072 overlay laid a 78 % cream veil over it, so
// a real (device) preview looked washed out; goldens over a teal remote image
// and a gradient could not see that. This samples real pixels over a real
// solid-colour scratch file, on a LIGHT and a DARK photo, for BOTH consumers of
// the shared overlay (NeumorphicAvatarEditor, ServicePhotoSlot).
//
// Asserted per sample:
//   * the pixel is still close to the photo's own colour (a veil would pull it
//     towards the cream/base), and clearly different from the base `#E6DDD0`;
//   * the chip behind the spinner / retry icon is cream, so they stay legible
//     on either photo.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/core/widgets/upload_state_overlay.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_photo_slot.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../golden/helpers/solid_png.dart';
import '../../helpers/pump_app.dart';

typedef _Rgb = (int, int, int);

const _Rgb _light = (0xBF, 0xE3, 0xFF); // pale sky blue
const _Rgb _dark = (0x10, 0x20, 0x50); // deep navy
const _Rgb _base = (0xE6, 0xDD, 0xD0);

/// Minimum RGB distance from the base `#E6DDD0` — the old veil landed at ~9.
const double _minFromBase = 45;

/// Maximum RGB distance from the photo's own colour (scrim shift is ~50 max).
const double _maxFromPhoto = 70;

/// Maximum RGB distance of the chip pixel from cream.
const double _maxChipFromCream = 40;

double _dist(_Rgb a, _Rgb b) => math.sqrt(
  math.pow(a.$1 - b.$1, 2) +
      math.pow(a.$2 - b.$2, 2) +
      math.pow(a.$3 - b.$3, 2),
);

_Rgb _cream() {
  const Color c = BrandColors.white;
  return ((c.r * 255).round(), (c.g * 255).round(), (c.b * 255).round());
}

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('upload_visibility'));
  tearDown(() => tmp.deleteSync(recursive: true));

  File scratchPhoto(_Rgb c) {
    final Directory dir = Directory('${tmp.path}/media_upload')
      ..createSync(recursive: true);
    return File('${dir.path}/photo_${c.$1}_${c.$2}_${c.$3}.jpg')
      ..writeAsBytesSync(solidPng(c.$1, c.$2, c.$3));
  }

  /// Reads the pixel at logical [p] of the boundary [key] (pixelRatio 1).
  Future<_Rgb> pixelAt(WidgetTester tester, GlobalKey key, Offset p) async {
    final _Rgb? rgb = await tester.runAsync<_Rgb>(() async {
      final RenderRepaintBoundary b =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final ui.Image img = await b.toImage();
      final ByteData data = (await img.toByteData())!;
      final int i = (p.dy.round() * img.width + p.dx.round()) * 4;
      return (data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2));
    });
    return rgb!;
  }

  /// Waits (real time, bounded) until the sample is near the photo colour,
  /// i.e. the async file decode has landed.
  Future<_Rgb> settledPixel(
    WidgetTester tester,
    GlobalKey key,
    Offset p,
    _Rgb photo,
  ) async {
    _Rgb last = _base;
    for (var i = 0; i < 80; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump();
      last = await pixelAt(tester, key, p);
      if (_dist(last, photo) < _maxFromPhoto) return last;
    }
    return last;
  }

  Widget host(GlobalKey key, Widget child) => RepaintBoundary(
    key: key,
    child: ColoredBox(
      color: BrandColors.base,
      child: Center(child: child),
    ),
  );

  Future<void> expectVisible(
    WidgetTester tester,
    GlobalKey key,
    Offset photoSample,
    Offset chipSample,
    _Rgb photo,
  ) async {
    final _Rgb px = await settledPixel(tester, key, photoSample, photo);
    expect(
      _dist(px, photo),
      lessThan(_maxFromPhoto),
      reason: 'photo not visible (or not loaded): $px vs $photo',
    );
    expect(
      _dist(px, _base),
      greaterThan(_minFromBase),
      reason: 'washed out towards the base: $px',
    );
    final _Rgb chip = await pixelAt(tester, key, chipSample);
    expect(
      _dist(chip, _cream()),
      lessThan(_maxChipFromCream),
      reason: 'spinner/retry chip is not cream: $chip',
    );
  }

  for (final (String, _Rgb) photo in <(String, _Rgb)>[
    ('light', _light),
    ('dark', _dark),
  ]) {
    group('${photo.$1} photo', () {
      testWidgets('avatar editor UPLOADING keeps the photo clearly visible', (
        tester,
      ) async {
        final File file = scratchPhoto(photo.$2);
        final GlobalKey key = GlobalKey();
        await tester.pumpApp(
          host(
            key,
            NeumorphicAvatarEditor(
              state: AvatarEditState.picking,
              initials: 'ДЗ',
              onTap: () {},
              previewFile: file,
              progress: 0.4,
            ),
          ),
        );
        final Offset c = tester.getCenter(find.byType(UploadChip));
        final Rect r = tester.getRect(find.byKey(key));
        await expectVisible(
          tester,
          key,
          Offset(c.dx - 30 - r.left, c.dy - 20 - r.top),
          Offset(c.dx - r.left, c.dy + 19 - r.top),
          photo.$2,
        );
      });

      testWidgets('avatar editor FAILED keeps the photo clearly visible', (
        tester,
      ) async {
        final File file = scratchPhoto(photo.$2);
        final GlobalKey key = GlobalKey();
        await tester.pumpApp(
          host(
            key,
            NeumorphicAvatarEditor(
              state: AvatarEditState.loaded,
              initials: 'ДЗ',
              onTap: () {},
              previewFile: file,
              uploadFailed: true,
              onRetry: () {},
            ),
          ),
        );
        final Offset c = tester.getCenter(find.byType(UploadChip));
        final Rect r = tester.getRect(find.byKey(key));
        await expectVisible(
          tester,
          key,
          Offset(c.dx - 30 - r.left, c.dy - 20 - r.top),
          Offset(c.dx - r.left, c.dy + 17 - r.top),
          photo.$2,
        );
      });

      testWidgets('service photo slot UPLOADING keeps the photo visible', (
        tester,
      ) async {
        final File file = scratchPhoto(photo.$2);
        final GlobalKey key = GlobalKey();
        await tester.pumpApp(
          host(
            key,
            SizedBox(
              width: 320,
              child: ServicePhotoSlot(
                previewFile: file,
                onTap: () {},
                uploadProgress: 0.4,
              ),
            ),
          ),
        );
        final Rect slot = tester.getRect(find.byType(ServicePhotoSlot));
        final Rect r = tester.getRect(find.byKey(key));
        await expectVisible(
          tester,
          key,
          Offset(slot.left + 40 - r.left, slot.top + 30 - r.top),
          Offset(slot.center.dx - r.left, slot.center.dy + 19 - r.top),
          photo.$2,
        );
      });

      testWidgets('service photo slot FAILED keeps the photo visible', (
        tester,
      ) async {
        final File file = scratchPhoto(photo.$2);
        final GlobalKey key = GlobalKey();
        await tester.pumpApp(
          host(
            key,
            SizedBox(
              width: 320,
              child: ServicePhotoSlot(
                previewFile: file,
                onTap: () {},
                uploadFailed: true,
                onRetry: () {},
              ),
            ),
          ),
        );
        final Rect slot = tester.getRect(find.byType(ServicePhotoSlot));
        final Rect r = tester.getRect(find.byKey(key));
        final Rect retry = tester.getRect(
          find.byKey(const Key('upload-retry')),
        );
        await expectVisible(
          tester,
          key,
          Offset(slot.left + 40 - r.left, slot.top + 30 - r.top),
          Offset(retry.center.dx - r.left, retry.bottom - 6 - r.top),
          photo.$2,
        );
      });
    });
  }
}
