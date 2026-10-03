// Phase 071 QA — the privacy + cleanup invariants of MediaPickService.
//
//  * No path hands back a file that skipped `compress(keepExif: false)`.
//  * Scratch intermediates never leak; the user's gallery original is never
//    deleted; plugin text never reaches the failure.

import 'dart:io';

import 'package:beautica_mobile/core/media/pick/media_kind.dart';
import 'package:beautica_mobile/core/media/pick/media_pick_service.dart';
import 'package:beautica_mobile/core/media/upload/upload_failure.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';

import 'scripted_pick_gateway.dart';

void main() {
  late Directory scratch;
  late Directory outside;
  late ScriptedPickGateway gw;
  late MediaPickService service;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('qa_scratch');
    outside = Directory.systemTemp.createTempSync('qa_gallery');
    gw = ScriptedPickGateway(scratch: scratch, outside: outside);
    service = MediaPickService(gw, tempDir: () async => scratch);
  });
  tearDown(() {
    scratch.deleteSync(recursive: true);
    outside.deleteSync(recursive: true);
  });

  List<String> leftovers() {
    return scratch
        .listSync(recursive: true)
        .whereType<File>()
        .map((File f) => f.path)
        .toList();
  }

  group('EXIF invariant: every returned file went through keepExif:false', () {
    test('normal pick', () async {
      final PickedImage r = (await service.pick(
        MediaKind.avatar,
        MediaPickSource.gallery,
      ))!;
      expect(gw.compressCalls, hasLength(1));
      expect(gw.compressCalls.single.keepExif, isFalse);
      expect(gw.compressCalls.single.target, r.file.path);
    });

    test('recoverLost + size retry: both passes strip EXIF', () async {
      gw.lost = 'x';
      gw.compressSizes = <int?>[kRetryAboveBytes + 1, 900];
      final PickedImage r = (await service.recoverLost(
        MediaKind.servicePhoto,
      ))!;
      expect(gw.compressCalls, hasLength(2));
      expect(gw.compressCalls.every((CompressCall c) => !c.keepExif), isTrue);
      // The returned file is the output of the LAST compress call.
      expect(gw.compressCalls.last.target, r.file.path);
      expect(r.bytes, 900);
    });

    test('size-retry path on a normal pick returns the retry output', () async {
      gw.compressSizes = <int?>[kRetryAboveBytes + 1, 800];
      final PickedImage r = (await service.pick(
        MediaKind.avatar,
        MediaPickSource.camera,
      ))!;
      expect(gw.compressCalls.map((CompressCall c) => c.keepExif), <bool>[
        false,
        false,
      ]);
      expect(gw.compressCalls.last.target, r.file.path);
      expect(gw.compressCalls.first.target, isNot(r.file.path));
    });

    test(
      'null compress result throws, returns no file, leaves nothing',
      () async {
        gw.compressSizes = <int?>[null];
        await expectLater(
          service.pick(MediaKind.avatar, MediaPickSource.gallery),
          throwsA(isA<UploadUnknownFailure>()),
        );
        expect(leftovers(), isEmpty);
      },
    );

    test(
      'null on the retry pass throws and deletes the first output',
      () async {
        gw.compressSizes = <int?>[kRetryAboveBytes + 1, null];
        await expectLater(
          service.pick(MediaKind.avatar, MediaPickSource.gallery),
          throwsA(isA<UploadUnknownFailure>()),
        );
        expect(gw.compressCalls, hasLength(2));
        expect(leftovers(), isEmpty);
      },
    );
  });

  group('cancel at each stage', () {
    test('cancel at pick -> null, nothing written', () async {
      gw.cancelPick = true;
      expect(
        await service.pick(MediaKind.avatar, MediaPickSource.gallery),
        isNull,
      );
      expect(leftovers(), isEmpty);
    });

    test('cancel at crop -> null, picked scratch file deleted', () async {
      gw.cancelCrop = true;
      expect(
        await service.pick(MediaKind.servicePhoto, MediaPickSource.camera),
        isNull,
      );
      expect(gw.compressCalls, isEmpty);
      expect(leftovers(), isEmpty);
    });

    test('recoverLost: cancel at crop -> null, lost file deleted', () async {
      gw.lost = 'x';
      gw.cancelCrop = true;
      expect(await service.recoverLost(MediaKind.avatar), isNull);
      expect(gw.compressCalls, isEmpty);
      expect(leftovers(), isEmpty);
    });
  });

  group('PlatformException maps to UploadUnknownFailure, no plugin text', () {
    final PlatformException secret = PlatformException(
      code: 'secret_plugin_code',
      message: '/data/user/0/private/path leaked',
    );

    test('crop failure: typed, scrubbed, picked file deleted', () async {
      gw.throwOnCrop = secret;
      Object? caught;
      try {
        await service.pick(MediaKind.avatar, MediaPickSource.gallery);
      } on Object catch (e) {
        caught = e;
      }
      expect(caught, isA<UploadUnknownFailure>());
      expect(caught.toString(), isNot(contains('secret_plugin_code')));
      expect(caught.toString(), isNot(contains('private')));
      expect(leftovers(), isEmpty);
    });

    test('compress failure: typed, scrubbed, intermediates deleted', () async {
      gw.throwOnCompress = secret;
      Object? caught;
      try {
        await service.pick(MediaKind.avatar, MediaPickSource.gallery);
      } on Object catch (e) {
        caught = e;
      }
      expect(caught, isA<UploadUnknownFailure>());
      expect(caught.toString(), isNot(contains('secret_plugin_code')));
      expect(leftovers(), isEmpty);
    });
  });

  group('the gallery original (outside scratch) is never deleted', () {
    setUp(() {
      gw.pickIn = Where.outside;
      gw.cropIn = Where.outside;
    });

    void expectGalleryIntact() {
      expect(File(gw.pickedPath!).existsSync(), isTrue);
    }

    test('on success', () async {
      await service.pick(MediaKind.avatar, MediaPickSource.gallery);
      expectGalleryIntact();
      expect(File(gw.croppedPath!).existsSync(), isTrue);
    });

    test('on crop cancel', () async {
      gw.cancelCrop = true;
      await service.pick(MediaKind.avatar, MediaPickSource.gallery);
      expectGalleryIntact();
    });

    test('on compress failure', () async {
      gw.compressSizes = <int?>[null];
      await expectLater(
        service.pick(MediaKind.avatar, MediaPickSource.gallery),
        throwsA(isA<UploadUnknownFailure>()),
      );
      expectGalleryIntact();
    });

    test('on too-large failure', () async {
      gw.compressSizes = <int?>[kRetryAboveBytes + 1];
      await expectLater(
        service.pick(MediaKind.avatar, MediaPickSource.gallery),
        throwsA(isA<UploadTooLargeFailure>()),
      );
      expectGalleryIntact();
    });

    test('on recoverLost success', () async {
      gw.lost = 'x';
      await service.recoverLost(MediaKind.avatar);
      expectGalleryIntact();
    });
  });

  group('scratch cleanup', () {
    test('success leaves exactly the returned file', () async {
      final PickedImage r = (await service.pick(
        MediaKind.avatar,
        MediaPickSource.gallery,
      ))!;
      expect(leftovers(), <String>[r.file.path]);
    });

    test('too-large after retry leaves nothing', () async {
      gw.compressSizes = <int?>[kRetryAboveBytes + 1];
      await expectLater(
        service.pick(MediaKind.avatar, MediaPickSource.gallery),
        throwsA(isA<UploadTooLargeFailure>()),
      );
      expect(leftovers(), isEmpty);
    });
  });
  group('partial compress target', () {
    test('is deleted when compress throws after writing it', () async {
      gw.throwOnCompress = PlatformException(code: 'boom');
      gw.partialBeforeThrow = true;
      await expectLater(
        service.pick(MediaKind.avatar, MediaPickSource.gallery),
        throwsA(isA<UploadUnknownFailure>()),
      );
      expect(gw.compressCalls, hasLength(1));
      expect(leftovers(), isEmpty);
    });
  });

  group('scratch containment uses isWithin, not startsWith', () {
    test('a sibling dir sharing the scratch prefix is never deleted', () async {
      final Directory sibling = Directory('${scratch.path}2')..createSync();
      addTearDown(() => sibling.deleteSync(recursive: true));
      gw.pickAs = '${sibling.path}/picked.jpg';
      await service.pick(MediaKind.avatar, MediaPickSource.gallery);
      expect(File(gw.pickedPath!).existsSync(), isTrue);
    });

    test('a path that climbs out of scratch via .. is never deleted', () async {
      gw.pickAs =
          '${scratch.path}/../${outside.uri.pathSegments.where((String s) => s.isNotEmpty).last}/picked.jpg';
      await service.pick(MediaKind.avatar, MediaPickSource.gallery);
      expect(
        File('${outside.path}/picked.jpg').existsSync(),
        isTrue,
        reason: 'the .. path resolves OUTSIDE scratch and must survive',
      );
    });
  });

  group('orphan sweep (once per process)', () {
    late Directory dir;
    late File stale;
    late File fresh;
    setUp(() {
      dir = Directory('${scratch.path}/$kMediaUploadDirName')..createSync();
      stale = File('${dir.path}/stale.jpg')..writeAsBytesSync(<int>[1]);
      fresh = File('${dir.path}/fresh.jpg')..writeAsBytesSync(<int>[1]);
      stale.setLastModifiedSync(
        DateTime.now().subtract(kScratchMaxAge + const Duration(hours: 1)),
      );
    });

    test('deletes stale, keeps fresh and the current result', () async {
      final PickedImage r = (await service.pick(
        MediaKind.avatar,
        MediaPickSource.gallery,
      ))!;
      expect(stale.existsSync(), isFalse);
      expect(fresh.existsSync(), isTrue);
      expect(r.file.existsSync(), isTrue);
    });

    test('recoverLost sweeps too', () async {
      gw.lost = 'x';
      await service.recoverLost(MediaKind.avatar);
      expect(stale.existsSync(), isFalse);
      expect(fresh.existsSync(), isTrue);
    });

    test('runs only on the first call per service instance', () async {
      await service.pick(MediaKind.avatar, MediaPickSource.gallery);
      final File stale2 = File('${dir.path}/stale2.jpg')
        ..writeAsBytesSync(<int>[1])
        ..setLastModifiedSync(
          DateTime.now().subtract(kScratchMaxAge + const Duration(hours: 1)),
        );
      await service.pick(MediaKind.avatar, MediaPickSource.gallery);
      expect(
        stale2.existsSync(),
        isTrue,
        reason: 'same instance: the sweep must not run a second time',
      );

      final MediaPickService fresh2 = MediaPickService(
        gw,
        tempDir: () async => scratch,
      );
      await fresh2.pick(MediaKind.avatar, MediaPickSource.gallery);
      expect(
        stale2.existsSync(),
        isFalse,
        reason: 'a new service instance sweeps once',
      );
    });
  });

  group('wipeAll (logout)', () {
    test('removes the whole media_upload dir, including fresh files', () async {
      final PickedImage r = (await service.pick(
        MediaKind.avatar,
        MediaPickSource.gallery,
      ))!;
      expect(r.file.existsSync(), isTrue);
      await service.wipeAll();
      expect(
        Directory('${scratch.path}/$kMediaUploadDirName').existsSync(),
        isFalse,
      );
    });

    test('is a no-op when the dir does not exist', () async {
      await service.wipeAll();
      expect(scratch.listSync(), isEmpty);
    });

    // Phase 073 audit (security MEDIUM): image_picker's lost-data record
    // survives logout; wipeAll must consume it and delete its file.
    test('drains the lost-pick record and deletes its file', () async {
      gw.lost = 'x';
      await service.wipeAll();
      final File lostFile = File(gw.pickedPath!);
      expect(lostFile.existsSync(), isFalse);
    });

    test('a lost pick OUTSIDE the temp tree (gallery original) is never '
        'deleted', () async {
      gw.lost = 'x';
      gw.pickIn = Where.outside;
      await service.drainLost();
      expect(File(gw.pickedPath!).existsSync(), isTrue);
    });

    test('never throws when the gateway does', () async {
      final MediaPickService throwing = MediaPickService(
        _ThrowingLostGateway(scratch: scratch, outside: outside),
        tempDir: () async => scratch,
      );
      await throwing.wipeAll();
      await throwing.drainLost();
    });
  });
}

class _ThrowingLostGateway extends ScriptedPickGateway {
  _ThrowingLostGateway({required super.scratch, required super.outside});

  @override
  Future<String?> retrieveLostData() async => throw StateError('plugin hiccup');
}
