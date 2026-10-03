// Phase 071 — pick → crop → compress, ending in a JPEG that is ready for
// `MediaUploadRepository.uploadAvatar(File)` (phase 070).
//
// Contract:
//   • `null` whenever the user cancels at ANY step (and intermediates are
//     deleted);
//   • the returned file is a JPEG with EXIF/GPS stripped (the final pass always
//     runs with `keepExif: false`, because uCrop can carry source EXIF through
//     and avatars / service photos are public);
//   • the returned file is ≤ [kRetryAboveBytes] (4.5 MB) or the call throws
//     [UploadTooLargeFailure] — it can never trip the server's 5 MB cap.
//
// The caller owns the returned file: call [MediaPickService.discard] after the
// upload, success or failure.

import 'dart:developer';
import 'dart:io';
import 'dart:math' show Random;

import 'package:beautica_mobile/core/media/pick/crop_labels.dart';
import 'package:beautica_mobile/core/media/pick/image_pick_gateway.dart';
import 'package:beautica_mobile/core/media/pick/media_kind.dart';
import 'package:beautica_mobile/core/media/upload/upload_failure.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'media_pick_service.g.dart';

/// Sub-directory of the temp dir that holds finished picks.
const String kMediaUploadDirName = 'media_upload';

/// Orphaned files in the scratch dir older than this are swept.
const Duration kScratchMaxAge = Duration(days: 1);

/// A finished, upload-ready photo.
final class PickedImage {
  const PickedImage({required this.file, required this.bytes});

  final File file;
  final int bytes;
}

/// Resolves the scratch root; overridable so tests use a throwaway directory.
typedef TempDirProvider = Future<Directory> Function();

final class MediaPickService {
  MediaPickService(
    this._gateway, {
    TempDirProvider tempDir = getTemporaryDirectory,
    DateTime Function()? now,
  }) : _tempDir = tempDir,
       // File-age comparison against lastModified: an absolute instant.
       _now = now ?? (() => DateTime.now()); // instant-ok: file age, no day

  final ImagePickGateway _gateway;
  final TempDirProvider _tempDir;
  final DateTime Function() _now;
  final Random _random = Random.secure();
  bool _swept = false;

  /// Picks from [source], crops to [kind]'s spec, compresses. `null` = cancelled.
  ///
  /// [labels] are the localised strings for the native crop screen.
  Future<PickedImage?> pick(
    MediaKind kind,
    MediaPickSource source, {
    CropLabels? labels,
  }) async {
    final Directory scratch = await _tempDir();
    await _sweepOnce(scratch);
    final String? picked = await _guard(
      () => _gateway.pickImage(source, maxDimension: kPickerMaxDimension),
    );
    if (picked == null) return null;
    return _cropAndCompress(kind, picked, labels, scratch);
  }

  /// Android activity-killed recovery: continues a pick the OS dropped. `null`
  /// when there is nothing to recover or the user cancels the crop.
  Future<PickedImage?> recoverLost(MediaKind kind, {CropLabels? labels}) async {
    final Directory scratch = await _tempDir();
    await _sweepOnce(scratch);
    final String? lost = await _gateway.retrieveLostData();
    if (lost == null) return null;
    return _cropAndCompress(kind, lost, labels, scratch);
  }

  /// Deletes [image]'s temp file. Safe to call twice.
  Future<void> discard(PickedImage image) async {
    try {
      if (await image.file.exists()) await image.file.delete();
    } on FileSystemException catch (e) {
      _logFs('discard', e);
    }
  }

  /// Deletes the whole `media_upload` dir (logout: a previous account's
  /// not-yet-discarded photos must not outlive the session). Never throws.
  Future<void> wipeAll() async {
    try {
      final Directory dir = Directory(
        p.join((await _tempDir()).path, kMediaUploadDirName),
      );
      if (await dir.exists()) await dir.delete(recursive: true);
    } on FileSystemException catch (e) {
      _logFs('wipe', e);
    } on Object {
      // e.g. no path_provider channel (tests / unsupported platform).
      log('wipe failed', name: 'media.pick', level: 900);
    }
  }

  /// Lazy, once per process: removes orphans (crash / kill before `discard`)
  /// older than [kScratchMaxAge]. Fresh files — including the one a current
  /// flow is about to hand back — are never touched.
  Future<void> _sweepOnce(Directory scratch) async {
    if (_swept) return;
    _swept = true;
    try {
      final Directory dir = Directory(
        p.join(scratch.path, kMediaUploadDirName),
      );
      if (!await dir.exists()) return;
      final DateTime cutoff = _now().subtract(kScratchMaxAge);
      await for (final FileSystemEntity e in dir.list()) {
        if (e is! File) continue;
        if ((await e.lastModified()).isBefore(cutoff)) await e.delete();
      }
    } on FileSystemException catch (e) {
      _logFs('sweep', e);
    }
  }

  // Only the stage + OS error code: the exception text carries file paths.
  void _logFs(String stage, FileSystemException e) => log(
    '$stage failed (os error: ${e.osError?.errorCode})',
    name: 'media.pick',
    level: 900,
  );

  Future<PickedImage?> _cropAndCompress(
    MediaKind kind,
    String pickedPath,
    CropLabels? labels,
    Directory scratch,
  ) async {
    String? croppedPath;
    final List<String> outputs = <String>[];
    var succeeded = false;
    String? keepPath;
    try {
      croppedPath = await _guard(
        () => _gateway.cropImage(
          pickedPath,
          spec: kind.spec,
          quality: kCropQuality,
          labels: labels,
        ),
      );
      if (croppedPath == null) return null;

      final Directory outDir = Directory(
        '${scratch.path}/$kMediaUploadDirName',
      );
      await outDir.create(recursive: true);

      var result = await _compress(
        kind,
        croppedPath,
        outDir,
        kFinalQuality,
        outputs,
      );
      var bytes = await result.length();
      // Safety net: a crop already bounded to <=1600x1200 re-encoded at q85
      // is ~0.3-1 MB, so this almost never fires. It only does for a
      // pathologically noisy image; then q70 is tried once before giving up.
      if (bytes > kRetryAboveBytes) {
        result = await _compress(
          kind,
          croppedPath,
          outDir,
          kRetryQuality,
          outputs,
        );
        bytes = await result.length();
        if (bytes > kRetryAboveBytes) throw const UploadTooLargeFailure();
      }
      succeeded = true;
      keepPath = result.path;
      return PickedImage(file: result, bytes: bytes);
    } finally {
      await _deleteScratch(pickedPath, scratch);
      if (croppedPath != null) await _deleteScratch(croppedPath, scratch);
      // Keep only the file handed to the caller; drop the rejected attempts
      // (all of them on failure).
      final String? keep = succeeded ? keepPath : null;
      for (final String path in outputs) {
        if (path != keep) await _deleteScratch(path, scratch);
      }
    }
  }

  Future<File> _compress(
    MediaKind kind,
    String sourcePath,
    Directory outDir,
    int quality,
    List<String> outputs,
  ) async {
    final String target = '${outDir.path}/${_uniqueName()}.jpg';
    // Registered BEFORE the call so a partial file left by a throwing
    // compress is still cleaned up by the caller's finally.
    outputs.add(target);
    final String? out = await _guard(
      () => _gateway.compress(
        sourcePath,
        target,
        maxWidth: kind.spec.maxWidth,
        maxHeight: kind.spec.maxHeight,
        quality: quality,
        // Mandatory: avatars / service photos are public; strip GPS + EXIF.
        keepExif: false,
      ),
    );
    if (out == null) throw const UploadUnknownFailure();
    if (out != target) outputs.add(out);
    return File(out);
  }

  /// Maps a platform failure (e.g. camera permission denied) to a typed one.
  Future<T> _guard<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on PlatformException catch (e) {
      // Code only — plugin message text can carry file paths.
      log(
        'native media call failed: ${e.code}',
        name: 'media.pick',
        level: 900,
      );
      throw const UploadUnknownFailure();
    }
  }

  /// Deletes [path] only when it lives under [scratch]: a plugin that returns
  /// the user's ORIGINAL gallery file must never have it deleted.
  Future<void> _deleteScratch(String path, Directory scratch) async {
    if (!p.isWithin(p.canonicalize(scratch.path), p.canonicalize(path))) {
      return;
    }
    try {
      final File f = File(path);
      if (await f.exists()) await f.delete();
    } on FileSystemException catch (e) {
      _logFs('scratch cleanup', e);
    }
  }

  String _uniqueName() => List<String>.generate(
    8,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

/// App-wide [MediaPickService]; tests override [imagePickGatewayProvider] or
/// this provider directly.
@Riverpod(keepAlive: true)
MediaPickService mediaPickService(Ref ref) =>
    MediaPickService(ref.watch(imagePickGatewayProvider));
