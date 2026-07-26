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

  /// The day-off-conflict dialog's destructive-confirm pill lift (2026-07-26
  /// design). Transcribed verbatim from the approved preview
  /// (`docs/signup-designs/DayOffConflictDialog/lib/theme/velvet_tokens.dart`
  /// `VelvetShadows.destructiveLift`).
  ///
  /// **Non-offset and alpha-attenuated on purpose** — same Impeller-GLES
  /// safety rationale as [borderedCard] / [borderedButton] just above: an
  /// OPAQUE shadow at a non-zero offset on a rounded [BoxDecoration] pokes an
  /// untranslated corner sliver past the rounded edge; a non-offset shadow's
  /// rrect footprint exactly matches the button's, so it can only ever read
  /// as a uniform halo. Uses [BrandColors.error] rather than a shadow tone —
  /// this button is the ONE saturated red surface the dialog has, and its
  /// lift should read as a warm red glow, not a neutral drop shadow.
  static final List<BoxShadow> destructiveLift = <BoxShadow>[
    BoxShadow(color: BrandColors.error.withValues(alpha: 0.30), blurRadius: 14),
  ];
}

// NOTE — a `cardDropShadow` recipe (a single OFFSET, fully-opaque
// `shadowDarkCard` shadow) previously lived here and was consumed by
// `MasterBookingCard`. It was REMOVED (not kept as a marked-unsafe constant)
// after root-causing a black-rectangle-in-the-corners regression: the
// Impeller-GLES corner-square artifact is triggered by ANY opaque shadow at a
// non-zero `Offset` on a rounded `BoxDecoration` — hue is irrelevant. The
// shadow's `shadowDarkCard` colour (`#C4B49E`) is not near-white, which is
// exactly why the earlier "offset-opaque-*light*-shadow" guard (see
// `impeller_circle_shadow_guard_test.dart`) missed it: that guard only
// flagged near-white colours at an offset, not opacity+offset generally. The
// guard's classifier is now hue-independent (any opaque colour + non-zero
// offset is unsafe); do not reintroduce an offset recipe using a fully-opaque
// `BrandColors.shadow*` token without re-verifying against the corrected
// guard first. Use [VelvetShadows.borderedCard] / [borderedButton] instead —
// both are non-offset AND alpha-attenuated (`.withValues(alpha: 0.45)`),
// which is why they stay safe.
