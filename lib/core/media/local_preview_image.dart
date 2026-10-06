// Phase 072 — local-file preview for a photo the user just picked / is
// uploading. A SEPARATE path from `RemoteImage` on purpose: it takes a `File`
// (never a String URL) and goes through `Image`, so it cannot open a socket
// and cannot be abused to load an arbitrary network URL; the host allow-list in
// `beautica_image.dart` stays untouched and remains the only network-image path.
//
// It also only reads files the 071 pipeline produced (`<temp>/media_upload/`,
// see `isMediaScratchFile`): any other path renders [fallback] without the file
// ever being opened (debug builds assert).

import 'dart:io';

import 'package:beautica_mobile/core/media/pick/media_scratch.dart';
import 'package:flutter/widgets.dart';

class LocalPreviewImage extends StatefulWidget {
  const LocalPreviewImage({
    super.key,
    required this.file,
    required this.width,
    required this.height,
    required this.fallback,
    this.fit = BoxFit.cover,
  });

  final File file;
  final double width;
  final double height;

  /// Shown if the file vanished / cannot be decoded / is not a scratch file.
  final Widget fallback;
  final BoxFit fit;

  /// The decode-bounded provider for [file]: BOTH axes are bound (same
  /// `ResizeImage` + `fit` policy as `beauticaResizedProvider`). A non-finite /
  /// non-positive axis is left unbounded; with neither axis usable the plain
  /// [FileImage] is returned.
  @visibleForTesting
  static ImageProvider providerFor(
    File file,
    double width,
    double height,
    double dpr,
  ) {
    final int? w = _px(width, dpr);
    final int? h = _px(height, dpr);
    final FileImage base = FileImage(file);
    if (w == null && h == null) return base;
    return ResizeImage(
      base,
      width: w,
      height: h,
      policy: ResizeImagePolicy.fit,
    );
  }

  static int? _px(double logical, double dpr) {
    if (!logical.isFinite || !dpr.isFinite) return null;
    final double px = logical * dpr;
    if (!px.isFinite || px < 1) return null;
    return px.round();
  }

  @override
  State<LocalPreviewImage> createState() => _LocalPreviewImageState();
}

class _LocalPreviewImageState extends State<LocalPreviewImage> {
  ImageProvider? _provider;

  /// `FileImage` is cached by path; drop the entry so a stale bitmap cannot
  /// outlive the file (071 writes a fresh `Random.secure` name per pick —
  /// `media_pick_service.dart` `_random` — so this is defence in depth AND frees
  /// the decoded bitmap from the `ImageCache` as soon as it is not shown).
  void _evict() {
    final ImageProvider? provider = _provider;
    _provider = null;
    if (provider != null) provider.evict();
  }

  @override
  void didUpdateWidget(LocalPreviewImage old) {
    super.didUpdateWidget(old);
    if (old.file.path != widget.file.path) _evict();
  }

  @override
  void dispose() {
    _evict();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool allowed = isMediaScratchFile(widget.file);
    assert(
      allowed,
      'LocalPreviewImage only renders files from the media_upload scratch dir, '
      'got ${widget.file.path}',
    );
    if (!allowed) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: widget.fallback,
      );
    }
    final ImageProvider provider = LocalPreviewImage.providerFor(
      widget.file,
      widget.width,
      widget.height,
      MediaQuery.devicePixelRatioOf(context),
    );
    _provider = provider;
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Image(
        image: provider,
        fit: widget.fit,
        gaplessPlayback: true,
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) => widget.fallback,
      ),
    );
  }
}
