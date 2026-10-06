// Phase 071 QA — scriptable ImagePickGateway shared by the invariant tests.

import 'dart:async';
import 'dart:io';

import 'package:beautica_mobile/core/media/pick/crop_labels.dart';
import 'package:beautica_mobile/core/media/pick/image_pick_gateway.dart';
import 'package:beautica_mobile/core/media/pick/media_kind.dart';
import 'package:flutter/services.dart' show PlatformException;

/// One `compress` invocation as the service issued it.
class CompressCall {
  CompressCall(this.quality, this.keepExif, this.target);
  final int quality;
  final bool keepExif;
  final String target;
}

/// Where the fake writes its pick / crop files.
enum Where { scratch, outside }

class ScriptedPickGateway implements ImagePickGateway {
  ScriptedPickGateway({required this.scratch, required this.outside});

  final Directory scratch;
  final Directory outside;

  Where pickIn = Where.scratch;
  Where cropIn = Where.scratch;
  bool cancelPick = false;
  bool cancelCrop = false;
  PlatformException? throwOnCrop;
  PlatformException? throwOnCompress;
  String? lost;

  /// When set, `pickImage` writes its file at exactly this path (may contain
  /// `..` segments) and returns it verbatim.
  String? pickAs;

  /// `compress` writes a partial file at the target BEFORE throwing.
  bool partialBeforeThrow = false;

  /// Per-call compress outcome: byte size, or `null` = plugin returned null.
  List<int?> compressSizes = <int?>[1000];

  final List<CompressCall> compressCalls = <CompressCall>[];
  final List<MediaPickSource> pickSources = <MediaPickSource>[];
  String? pickedPath;
  String? croppedPath;

  /// When set, `pickImage` / `cropImage` complete only after it does (so a test
  /// can dispose the owner mid-pick / mid-crop).
  Completer<void>? holdPick;
  Completer<void>? holdCrop;

  /// The labels the last `cropImage` received (and whether it ran at all).
  CropLabels? seenLabels;
  bool cropLabelsSeen = false;

  /// Phase 369 — every crop spec received, in order.
  final List<MediaSpec> cropSpecs = <MediaSpec>[];

  /// Phase 369 — every compress's `(maxWidth, maxHeight)`.
  final List<(int, int)> compressDims = <(int, int)>[];

  File _make(Where where, String name, int bytes) =>
      File('${(where == Where.scratch ? scratch : outside).path}/$name')
        ..writeAsBytesSync(List<int>.filled(bytes, 1));

  @override
  Future<String?> pickImage(
    MediaPickSource source, {
    required int maxDimension,
  }) async {
    pickSources.add(source);
    if (cancelPick) return null;
    if (pickAs != null) {
      File(pickAs!).writeAsBytesSync(List<int>.filled(10, 1));
      await holdPick?.future;
      return pickedPath = pickAs;
    }
    final String path = pickedPath = _make(pickIn, 'picked.jpg', 10).path;
    await holdPick?.future;
    return path;
  }

  @override
  Future<String?> cropImage(
    String sourcePath, {
    required MediaSpec spec,
    required int quality,
    CropLabels? labels,
  }) async {
    cropLabelsSeen = true;
    seenLabels = labels;
    cropSpecs.add(spec);
    await holdCrop?.future;
    if (throwOnCrop != null) throw throwOnCrop!;
    if (cancelCrop) return null;
    return croppedPath = _make(cropIn, 'cropped.jpg', 10).path;
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
    compressCalls.add(CompressCall(quality, keepExif, targetPath));
    compressDims.add((maxWidth, maxHeight));
    if (throwOnCompress != null) {
      if (partialBeforeThrow) {
        File(targetPath)
          ..createSync(recursive: true)
          ..writeAsBytesSync(List<int>.filled(3, 1));
      }
      throw throwOnCompress!;
    }
    final int? size = compressSizes[i < compressSizes.length ? i : 0];
    if (size == null) return null;
    File(targetPath)
      ..createSync(recursive: true)
      ..writeAsBytesSync(List<int>.filled(size, 1));
    return targetPath;
  }

  @override
  Future<String?> retrieveLostData() async {
    if (lost == null) return null;
    return pickedPath = _make(pickIn, 'lost.jpg', 10).path;
  }
}
