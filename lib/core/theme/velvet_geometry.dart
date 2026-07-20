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

  /// Fully-rounded pill (duration/price chips). Large enough that the ends
  /// stay perfectly circular regardless of the element's height.
  /// Transcribed from `docs/signup-designs/ServiceListScreen/lib/theme/velvet_tokens.dart`.
  static const double pill = 999;
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

  /// Subtle ambient shadow for a card that already carries a hairline
  /// [NeumorphicCard.showBorder] stroke for definition.
  ///
  /// [extrudedCard]'s pair of ±8dp-offset shadows are each a rounded-rect the
  /// exact size/radius of the card, just diagonally translated then blurred —
  /// so a squarish sliver of the untranslated corner pokes out from behind
  /// the card's own fill at the two far diagonal corners. That bleed exists
  /// on every [extrudedCard] surface; it only became visually distracting
  /// once a bordered card's crisp 1dp stroke gave the eye a sharp reference
  /// edge to contrast it against. A single **non-offset** shadow has no such
  /// gap — since it isn't translated, its rrect footprint exactly matches the
  /// card's, so it only ever reads as a uniform soft halo around the edge.
  /// The border stroke alone carries the "distinct shape" job; this shadow
  /// just adds a faint hint of lift.
  static final List<BoxShadow> borderedCard = <BoxShadow>[
    BoxShadow(
      color: BrandColors.shadowDarkCard.withValues(alpha: 0.45),
      blurRadius: 10,
    ),
  ];

  /// Subtle ambient shadow for a bordered *button* — the button-scaled sibling
  /// of [borderedCard], following the same **non-offset** single-shadow recipe.
  ///
  /// Same rationale as [borderedCard]: because the shadow isn't translated, its
  /// rrect footprint exactly matches the button, so no untranslated corner
  /// sliver pokes out as a pale square on Impeller-GLES (the artifact that
  /// [extrudedButton]'s ±6dp-offset `shadowLightStrong` pair produces). Uses the
  /// button's own [BrandColors.shadowDarkButton] tone (matching [extrudedButton]
  /// rather than the card shadow) at a tighter blur than [borderedCard]. Pairs
  /// with a hairline border, as `CalendarButton`'s camel edge already provides.
  static final List<BoxShadow> borderedButton = <BoxShadow>[
    BoxShadow(
      color: BrandColors.shadowDarkButton.withValues(alpha: 0.45),
      blurRadius: 8,
    ),
  ];

  /// A single OFFSET dark drop shadow, with no light-highlight pair — the
  /// master booking card's bottom shadow (design parity pass, `MasterBookingCard`).
  ///
  /// The approved SalonManagementDesign card shadow (`_kCardShadow`,
  /// `booking_widgets.dart:161-172`) pairs an offset `shadowDarkCard` shadow
  /// with a low-opacity offset near-white highlight. Only the DARK half is
  /// reproduced here: an offset near-white highlight is the exact Impeller-GLES
  /// white-corner-wedge trigger (resolved 34db74f — see
  /// `impeller_circle_shadow_guard_test.dart`'s "offset-opaque-light-shadow
  /// recipe guard"), while an offset shadow using the non-near-white
  /// `shadowDarkCard` tone is proven SAFE at any offset (that same guard's
  /// "classifier does NOT flag the opaque taupe dark shadow at an offset"
  /// case). This gives the card a real, offset sense of lift — closer to the
  /// design than the non-offset [borderedCard] halo — while staying provably
  /// safe.
  static const List<BoxShadow> cardDropShadow = <BoxShadow>[
    BoxShadow(
      color: BrandColors.shadowDarkCard,
      offset: Offset(5, 5),
      blurRadius: 12,
    ),
  ];
}
