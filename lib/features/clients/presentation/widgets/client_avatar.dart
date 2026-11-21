// M510 — the client card's avatar: a photo, or a camel→mocha monogram, in a
// raised ring (ClientCardVariants `ClientAvatar`). The photo goes through the
// allow-listed [RemoteImage] (sized decode); a missing / disallowed / failed
// photo falls back to the monogram, so the SAME widget serves every client.
//
// PII: the name's letters only; never logged.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/media/beautica_image.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/shared/widgets/portfolio_photo_viewer.dart'
    show PhotoViewerReport;
import 'package:beautica_mobile/shared/widgets/profile_photo_preview.dart';

class ClientAvatar extends StatelessWidget {
  const ClientAvatar({
    super.key,
    required this.size,
    this.imageUrl,
    this.initials,
    this.previewOnTap = false,
    this.previewReport,
  });

  /// Face diameter (the ring adds its padding around it).
  final double size;
  final String? imageUrl;

  /// Monogram letters; `null` (a nameless guest) shows a person glyph.
  final String? initials;

  /// ADDITIVE (2026-11-21): `true` → a tap on the PHOTO opens it full
  /// screen ([ProfilePhotoPreviewTap]); no photo → inert. `false` (the
  /// default) — every list row / navigating card — renders and behaves
  /// exactly as before.
  final bool previewOnTap;

  /// ADDITIVE (MOD-39): with [previewOnTap], the viewer's «Поскаржитися» for
  /// this profile ([ProfilePhotoPreviewTap.report]). `null` (the default,
  /// own-profile previews) → no report button.
  final PhotoViewerReport? previewReport;

  static const Key avatarKey = Key('client-avatar');

  /// From this size up the monogram uses the profile display-name token.
  static const double _heroMin = 48;
  static final TextStyle _heroInitials = VelvetText.displayName().copyWith(
    color: BrandColors.white,
  );
  static final TextStyle _smallInitials = VelvetText.masterCardInitials
      .copyWith(color: BrandColors.white);

  @override
  Widget build(BuildContext context) {
    final String? letters = initials;
    final Widget monogram = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: VelvetGradients.accentDiscFace,
      ),
      child: letters == null
          ? Icon(
              Icons.person_rounded,
              size: size * 0.5,
              color: BrandColors.white,
            )
          : Text(
              letters,
              // Standard tokens: the profile display name on the card's
              // hero monogram, the strip's initials on a small avatar.
              style: size >= _heroMin ? _heroInitials : _smallInitials,
              textScaler: TextScaler.noScaling,
            ),
    );
    final String? url = imageUrl;
    final Widget face = url == null
        ? monogram
        : RemoteImage(
            url: url,
            width: size,
            height: size,
            shape: RemoteImageShape.circle,
            excludeFromSemantics: true,
            fallback: monogram,
          );
    final Widget avatar = Container(
      key: avatarKey,
      padding: EdgeInsets.all(size >= 72 ? 4 : 3),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: BrandColors.base,
        boxShadow: VelvetShadows.extrudedSmall,
      ),
      child: face,
    );
    if (!previewOnTap) return avatar;
    return ProfilePhotoPreviewTap(
      imageUrl: url,
      report: previewReport,
      child: avatar,
    );
  }
}
