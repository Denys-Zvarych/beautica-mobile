// Phase 071 — the ONLY file that talks to the three native plugins
// (image_picker, image_cropper, flutter_image_compress). Everything above it
// works on plain file paths, so tests override [imagePickGatewayProvider] with
// a fake and never touch a platform channel.

import 'dart:developer';

import 'package:beautica_mobile/core/media/pick/crop_labels.dart';
import 'package:beautica_mobile/core/media/pick/media_kind.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'image_pick_gateway.g.dart';

/// Thin seam over the native pick / crop / compress plugins. All paths are
/// absolute filesystem paths; `null` means the user cancelled (or, for
/// [compress], the plugin produced nothing).
abstract interface class ImagePickGateway {
  /// Opens the Photo Picker / camera; returns the picked file's path.
  Future<String?> pickImage(
    MediaPickSource source, {
    required int maxDimension,
  });

  /// Opens the native crop screen on [sourcePath]; returns the cropped path.
  Future<String?> cropImage(
    String sourcePath, {
    required MediaSpec spec,
    required int quality,
    CropLabels? labels,
  });

  /// Re-encodes [sourcePath] to a JPEG at [targetPath], bounded to
  /// [maxWidth]×[maxHeight], with EXIF (incl. GPS) removed — [keepExif] is a
  /// parameter only so tests can assert it is always `false`.
  Future<String?> compress(
    String sourcePath,
    String targetPath, {
    required int maxWidth,
    required int maxHeight,
    required int quality,
    required bool keepExif,
  });

  /// Android only: a pick lost to activity death, or `null`.
  Future<String?> retrieveLostData();
}

/// Plugin-backed implementation.
final class ImagePickGatewayImpl implements ImagePickGateway {
  ImagePickGatewayImpl({ImagePicker? picker, ImageCropper? cropper})
    : _picker = picker ?? ImagePicker(),
      _cropper = cropper ?? ImageCropper();

  final ImagePicker _picker;
  final ImageCropper _cropper;

  @override
  Future<String?> pickImage(
    MediaPickSource source, {
    required int maxDimension,
  }) async {
    final XFile? file = await _picker.pickImage(
      source: switch (source) {
        MediaPickSource.gallery => ImageSource.gallery,
        MediaPickSource.camera => ImageSource.camera,
      },
      maxWidth: maxDimension.toDouble(),
      maxHeight: maxDimension.toDouble(),
      // No imageQuality: that would add a lossy JPEG encode. maxWidth/maxHeight
      // stay as the memory guard; the final compress pass is the lossy step.
    );
    return file?.path;
  }

  @override
  Future<String?> cropImage(
    String sourcePath, {
    required MediaSpec spec,
    required int quality,
    CropLabels? labels,
  }) async {
    final CroppedFile? cropped = await _cropper.cropImage(
      sourcePath: sourcePath,
      maxWidth: spec.maxWidth,
      maxHeight: spec.maxHeight,
      aspectRatio: CropAspectRatio(
        ratioX: spec.aspectX.toDouble(),
        ratioY: spec.aspectY.toDouble(),
      ),
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: quality,
      uiSettings: <PlatformUiSettings>[
        AndroidUiSettings(
          toolbarTitle: labels?.title,
          toolbarColor: BrandColors.base,
          statusBarLight: true,
          toolbarWidgetColor: BrandColors.accentDeep,
          backgroundColor: BrandColors.base,
          activeControlsWidgetColor: BrandColors.accent,
          cropStyle: spec.circle ? CropStyle.circle : CropStyle.rectangle,
          lockAspectRatio: true,
          initAspectRatio: spec.aspectX == spec.aspectY
              ? CropAspectRatioPreset.square
              : CropAspectRatioPreset.ratio4x3,
        ),
        IOSUiSettings(
          title: labels?.title,
          doneButtonTitle: labels?.doneButton,
          cancelButtonTitle: labels?.cancelButton,
          cropStyle: spec.circle ? CropStyle.circle : CropStyle.rectangle,
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
          aspectRatioPickerButtonHidden: true,
        ),
      ],
    );
    return cropped?.path;
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
    // Runs natively on a background thread — never blocks the UI isolate.
    final XFile? out = await FlutterImageCompress.compressAndGetFile(
      sourcePath,
      targetPath,
      minWidth: maxWidth,
      minHeight: maxHeight,
      quality: quality,
      format: CompressFormat.jpeg,
      keepExif: keepExif,
    );
    return out?.path;
  }

  @override
  Future<String?> retrieveLostData() async {
    try {
      final LostDataResponse lost = await _picker.retrieveLostData();
      if (lost.isEmpty) return null;
      final XFile? file = lost.file ?? lost.files?.firstOrNull;
      if (lost.exception != null && file == null) {
        log(
          'lost pick carried an exception (code: ${_codeOf(lost.exception)})',
          name: 'media.pick',
          level: 900,
        );
      }
      return file?.path;
    } on Object catch (e) {
      // Unsupported platforms (iOS/Windows) or a plugin hiccup: nothing to
      // recover, never fatal. Only the code is logged — plugin text can carry
      // file paths.
      log(
        'retrieveLostData failed (code: ${_codeOf(e)})',
        name: 'media.pick',
        level: 900,
      );
      return null;
    }
  }
}

String _codeOf(Object? e) => e is PlatformException ? e.code : 'n/a';

/// Overridden with a fake in tests.
@Riverpod(keepAlive: true)
ImagePickGateway imagePickGateway(Ref ref) => ImagePickGatewayImpl();
