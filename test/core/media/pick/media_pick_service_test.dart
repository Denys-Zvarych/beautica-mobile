// Phase 071 — MediaPickService against a fake ImagePickGateway (no plugins).

import 'dart:io';

import 'package:beautica_mobile/core/media/pick/crop_labels.dart';
import 'package:beautica_mobile/core/media/pick/image_pick_gateway.dart';
import 'package:beautica_mobile/core/media/pick/media_kind.dart';
import 'package:beautica_mobile/core/media/pick/media_pick_service.dart';
import 'package:beautica_mobile/core/media/upload/upload_failure.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';

class _CompressCall {
  _CompressCall(this.maxWidth, this.maxHeight, this.quality, this.keepExif);
  final int maxWidth;
  final int maxHeight;
  final int quality;
  final bool keepExif;
}

class _FakeGateway implements ImagePickGateway {
  _FakeGateway(this.dir);
  final Directory dir;

  bool cancelPick = false;
  bool cancelCrop = false;
  bool throwOnPick = false;
  String? lost;

  /// Bytes written by compress, by call index (last one repeats).
  List<int> compressSizes = <int>[1000];

  int pickCalls = 0;
  int cropCalls = 0;
  MediaSpec? cropSpec;
  CropLabels? cropLabels;
  final List<_CompressCall> compressCalls = <_CompressCall>[];
  String? pickedPath;
  String? croppedPath;

  File _make(String name, int bytes) {
    final File f = File('${dir.path}/$name')
      ..writeAsBytesSync(List<int>.filled(bytes, 1));
    return f;
  }

  @override
  Future<String?> pickImage(
    MediaPickSource source, {
    required int maxDimension,
  }) async {
    pickCalls++;
    if (throwOnPick) throw PlatformException(code: 'camera_access_denied');
    if (cancelPick) return null;
    expect(maxDimension, 2048);
    return pickedPath = _make('picked.jpg', 10).path;
  }

  @override
  Future<String?> cropImage(
    String sourcePath, {
    required MediaSpec spec,
    required int quality,
    CropLabels? labels,
  }) async {
    cropCalls++;
    cropSpec = spec;
    cropLabels = labels;
    expect(quality, kCropQuality);
    if (cancelCrop) return null;
    return croppedPath = _make('cropped.jpg', 10).path;
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
    final int i = compressCalls.length;
    compressCalls.add(_CompressCall(maxWidth, maxHeight, quality, keepExif));
    final int size = compressSizes[i < compressSizes.length ? i : 0];
    File(targetPath)
      ..createSync(recursive: true)
      ..writeAsBytesSync(List<int>.filled(size, 1));
    return targetPath;
  }

  @override
  Future<String?> retrieveLostData() async =>
      lost == null ? null : _make('lost.jpg', 10).path;
}

void main() {
  late Directory tmp;
  late _FakeGateway gw;
  late MediaPickService service;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('pick_test');
    gw = _FakeGateway(tmp);
    service = MediaPickService(gw, tempDir: () async => tmp);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  List<String> outputs() => Directory(
    '${tmp.path}/$kMediaUploadDirName',
  ).listSync().map((FileSystemEntity e) => e.path).toList();

  test('cancel at pick -> null and crop is never called', () async {
    gw.cancelPick = true;
    expect(await service.pick(MediaKind.avatar, MediaPickSource.gallery), null);
    expect(gw.cropCalls, 0);
    expect(gw.compressCalls, isEmpty);
  });

  test('cancel at crop -> null, picked temp file deleted', () async {
    gw.cancelCrop = true;
    expect(await service.pick(MediaKind.avatar, MediaPickSource.camera), null);
    expect(gw.compressCalls, isEmpty);
    expect(File(gw.pickedPath!).existsSync(), isFalse);
  });

  test('avatar passes 1:1 + circle + 1024, labels forwarded', () async {
    const CropLabels labels = CropLabels(
      title: 't',
      doneButton: 'd',
      cancelButton: 'c',
    );
    await service.pick(
      MediaKind.avatar,
      MediaPickSource.gallery,
      labels: labels,
    );
    expect(gw.cropSpec!.aspectX, 1);
    expect(gw.cropSpec!.aspectY, 1);
    expect(gw.cropSpec!.circle, isTrue);
    expect(gw.cropSpec!.maxWidth, 1024);
    expect(gw.cropSpec!.maxHeight, 1024);
    expect(gw.cropLabels, same(labels));
    expect(gw.compressCalls.single.maxWidth, 1024);
    expect(gw.compressCalls.single.maxHeight, 1024);
  });

  test('service photo passes 4:3 rectangle + 1600x1200', () async {
    await service.pick(MediaKind.servicePhoto, MediaPickSource.gallery);
    expect(gw.cropSpec!.aspectX, 4);
    expect(gw.cropSpec!.aspectY, 3);
    expect(gw.cropSpec!.circle, isFalse);
    expect(gw.compressCalls.single.maxWidth, 1600);
    expect(gw.compressCalls.single.maxHeight, 1200);
  });

  test('compress is always keepExif:false at q85 first', () async {
    gw.compressSizes = <int>[kRetryAboveBytes + 1, 500];
    final PickedImage? r = await service.pick(
      MediaKind.avatar,
      MediaPickSource.gallery,
    );
    expect(r, isNotNull);
    expect(gw.compressCalls.every((_CompressCall c) => !c.keepExif), isTrue);
    expect(gw.compressCalls.first.quality, kFinalQuality);
  });

  test('success returns the file + bytes and removes intermediates', () async {
    gw.compressSizes = <int>[1234];
    final PickedImage r = (await service.pick(
      MediaKind.avatar,
      MediaPickSource.gallery,
    ))!;
    expect(r.bytes, 1234);
    expect(r.file.existsSync(), isTrue);
    expect(r.file.path.endsWith('.jpg'), isTrue);
    expect(File(gw.pickedPath!).existsSync(), isFalse);
    expect(File(gw.croppedPath!).existsSync(), isFalse);
    expect(outputs(), <String>[r.file.path]);
  });

  test(
    'over 4.5 MB -> retry at q70; the rejected attempt is deleted',
    () async {
      gw.compressSizes = <int>[kRetryAboveBytes + 1, 2000];
      final PickedImage r = (await service.pick(
        MediaKind.servicePhoto,
        MediaPickSource.gallery,
      ))!;
      expect(gw.compressCalls.map((_CompressCall c) => c.quality), <int>[
        kFinalQuality,
        kRetryQuality,
      ]);
      expect(r.bytes, 2000);
      expect(outputs(), <String>[r.file.path]);
    },
  );

  test(
    'still too big after retry -> UploadTooLargeFailure, no leftovers',
    () async {
      gw.compressSizes = <int>[kRetryAboveBytes + 1];
      await expectLater(
        service.pick(MediaKind.avatar, MediaPickSource.gallery),
        throwsA(isA<UploadTooLargeFailure>()),
      );
      expect(gw.compressCalls, hasLength(2));
      expect(outputs(), isEmpty);
    },
  );

  test('exactly 4.5 MB is accepted without a retry', () async {
    gw.compressSizes = <int>[kRetryAboveBytes];
    final PickedImage r = (await service.pick(
      MediaKind.avatar,
      MediaPickSource.gallery,
    ))!;
    expect(r.bytes, kRetryAboveBytes);
    expect(gw.compressCalls, hasLength(1));
  });

  test('PlatformException from the picker -> UploadUnknownFailure', () async {
    gw.throwOnPick = true;
    await expectLater(
      service.pick(MediaKind.avatar, MediaPickSource.camera),
      throwsA(isA<UploadUnknownFailure>()),
    );
  });

  test('never deletes a picked file outside the scratch dir', () async {
    final Directory other = Directory.systemTemp.createTempSync('original');
    addTearDown(() => other.deleteSync(recursive: true));
    final File original = File('${other.path}/gallery.jpg')
      ..writeAsBytesSync(<int>[1]);
    final _OutsideGateway outside = _OutsideGateway(tmp, original.path);
    final MediaPickService s = MediaPickService(
      outside,
      tempDir: () async => tmp,
    );
    await s.pick(MediaKind.avatar, MediaPickSource.gallery);
    expect(original.existsSync(), isTrue);
  });

  test('discard deletes the file and is idempotent', () async {
    final PickedImage r = (await service.pick(
      MediaKind.avatar,
      MediaPickSource.gallery,
    ))!;
    await service.discard(r);
    expect(r.file.existsSync(), isFalse);
    await service.discard(r);
  });

  test(
    'recoverLost: nothing -> null; present -> processed like a pick',
    () async {
      expect(await service.recoverLost(MediaKind.avatar), isNull);
      expect(gw.cropCalls, 0);
      gw.lost = 'x';
      final PickedImage? r = await service.recoverLost(MediaKind.avatar);
      expect(r, isNotNull);
      expect(gw.cropCalls, 1);
      expect(gw.compressCalls.single.keepExif, isFalse);
    },
  );
}

/// Picker that returns a path outside the scratch dir.
class _OutsideGateway extends _FakeGateway {
  _OutsideGateway(super.dir, this.path);
  final String path;

  @override
  Future<String?> pickImage(
    MediaPickSource source, {
    required int maxDimension,
  }) async => path;
}
