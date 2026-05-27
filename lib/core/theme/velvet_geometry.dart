import 'package:flutter/material.dart';

import 'brand_colors.dart';

/// Corner radii — VelvetTouch design system.
///
/// Transcribed verbatim from
/// `docs/signup-designs/VelvetTouchDesign/lib/theme/velvet_tokens.dart`.
abstract final class VelvetRadii {
  static const double logoTile = 24;
  static const double field = 16;
  static const double button = 16;
  static const double card = 24;
}

/// Spacing scale (8 dp rhythm with a 4 dp half-step) — VelvetTouch.
///
/// Transcribed verbatim from
/// `docs/signup-designs/VelvetTouchDesign/lib/theme/velvet_tokens.dart`.
abstract final class VelvetSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

/// Fixed control heights — generous for touch (>=48 dp) — VelvetTouch.
///
/// Transcribed verbatim from
/// `docs/signup-designs/VelvetTouchDesign/lib/theme/velvet_tokens.dart`.
abstract final class VelvetSizes {
  static const double field = 49;
  static const double cta = 49;
  static const double logoTile = 78;
}

/// Neumorphic shadow recipes — pre-built [BoxShadow] lists so every surface
/// across the app is pixel-identical. VelvetTouch design system.
///
/// Transcribed verbatim from
/// `docs/signup-designs/VelvetTouchDesign/lib/theme/velvet_tokens.dart`.
abstract final class VelvetShadows {
  /// Raised card — soft, wide.
  static const List<BoxShadow> extrudedCard = <BoxShadow>[
    BoxShadow(
      color: BrandColors.shadowDarkCard,
      offset: Offset(8, 8),
      blurRadius: 18,
    ),
    BoxShadow(
      color: BrandColors.shadowLightStrong,
      offset: Offset(-8, -8),
      blurRadius: 18,
    ),
  ];

  /// Raised button — tighter than the card.
  static const List<BoxShadow> extrudedButton = <BoxShadow>[
    BoxShadow(
      color: BrandColors.shadowDarkButton,
      offset: Offset(6, 6),
      blurRadius: 14,
    ),
    BoxShadow(
      color: BrandColors.shadowLightStrong,
      offset: Offset(-6, -6),
      blurRadius: 14,
    ),
  ];

  /// Raised button — camel-face variant. The dark shadow uses a deeper warm
  /// mocha (`#8C6A44`) so it reads as genuine depth against the camel gradient.
  /// Use instead of [extrudedButton] when the button surface has a camel/mocha
  /// gradient fill.
  static const List<BoxShadow> extrudedButtonAccent = <BoxShadow>[
    BoxShadow(color: Color(0xFF8C6A44), offset: Offset(6, 6), blurRadius: 14),
    BoxShadow(
      color: BrandColors.shadowLightStrong,
      offset: Offset(-6, -6),
      blurRadius: 14,
    ),
  ];

  /// Small raised element (logo tile, OTP cell, badge).
  static const List<BoxShadow> extrudedSmall = <BoxShadow>[
    BoxShadow(
      color: BrandColors.shadowDarkButton,
      offset: Offset(5, 5),
      blurRadius: 12,
    ),
    BoxShadow(
      color: BrandColors.shadowLightStrong,
      offset: Offset(-5, -5),
      blurRadius: 12,
    ),
  ];
}
