// M510 — the client card's avatar: a photo, or a camel→mocha monogram, in a
// raised ring (ClientCardVariants `ClientAvatar`). The photo goes through the
// allow-listed [RemoteImage] (sized decode); a missing / disallowed / failed
// photo falls back to the monogram, so the SAME widget serves every client.
//
// PII: the name's letters only; never logged.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/media/beautica_image.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/client_card_text.dart';

class ClientAvatar extends StatelessWidget {
  const ClientAvatar({
    super.key,
    required this.size,
    this.imageUrl,
    this.initials,
  });

  /// Face diameter (the ring adds its padding around it).
  final double size;
  final String? imageUrl;

  /// Monogram letters; `null` (a nameless guest) shows a person glyph.
  final String? initials;

  static const Key avatarKey = Key('client-avatar');

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
              style: clientHeading(size * 0.34, color: BrandColors.white),
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
    return Container(
      key: avatarKey,
      padding: EdgeInsets.all(size >= 72 ? 4 : 3),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: BrandColors.base,
        boxShadow: VelvetShadows.extrudedSmall,
      ),
      child: face,
    );
  }
}
