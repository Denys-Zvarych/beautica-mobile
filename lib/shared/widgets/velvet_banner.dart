// VelvetBanner — the inline form-level feedback banner (icon + message +
// optional action) on a small extruded card.
//
// PROMOTED (REUSE-FIRST, phase 424) verbatim from `AuthBanner` in
// `features/auth/presentation/widgets/auth_scaffold.dart` (which keeps a
// `typedef AuthBanner = VelvetBanner`). It is also the Dart twin of the
// website guest-booking `.banner` (beautica-website/src/styles/book.css),
// used by the moderation report sheet for its 429 / 404 errors. The only
// addition is the defaulted [VelvetBanner.iconSize].

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';

/// A dismissible inline banner for form-level (non-field) feedback such as the
/// login "email not verified" state. Pairs an icon + text + optional action so
/// meaning never relies on color alone.
class VelvetBanner extends StatelessWidget {
  const VelvetBanner({
    super.key,
    required this.icon,
    required this.message,
    required this.color,
    this.actionLabel,
    this.onAction,
    this.iconSize,
  });

  final IconData icon;
  final String message;
  final Color color;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// ADDITIVE (phase 424): glyph size. `null` keeps the auth banner's 20; the
  /// report sheet passes 24 (the website `.banner` icon).
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      container: true,
      child: NeumorphicCard(
        padding: const EdgeInsets.all(VelvetSpacing.md),
        shadows: VelvetShadows.extrudedSmall,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, color: color, size: iconSize ?? 20),
            const SizedBox(width: VelvetSpacing.sm + 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    message,
                    style: VelvetText.feedback(
                      BrandColors.text,
                    ).copyWith(height: 1.45),
                  ),
                  if (actionLabel != null && onAction != null) ...<Widget>[
                    const SizedBox(height: VelvetSpacing.sm),
                    GestureDetector(
                      key: const ValueKey<String>('auth_banner_action'),
                      onTap: onAction,
                      child: Text(
                        actionLabel!,
                        style: VelvetText.link().copyWith(color: color),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
