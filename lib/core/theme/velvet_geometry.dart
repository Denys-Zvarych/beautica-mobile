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

  /// VelvetSnack's leading icon holder — a softened square, deliberately
  /// tighter than [field] so the holder reads as a glyph chip, not a mini
  /// input. Transcribed verbatim from
  /// `docs/signup-designs/VelvetSnack/lib/theme/velvet_tokens.dart`
  /// (`VelvetRadii.snackIcon`). The snack's own outer shell reuses [card]
  /// directly (24) rather than a separate alias — see
  /// `ARCHITECTURE-mobile.md` § 9.
  static const double snackIcon = 12;
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

  /// VelvetSnack minimum height — one line of message plus 12dp vertical
  /// padding around a 32dp icon holder. Grows to fit two lines. Transcribed
  /// verbatim from
  /// `docs/signup-designs/VelvetSnack/lib/theme/velvet_tokens.dart`.
  static const double snackMinHeight = 56;

  /// VelvetSnack's leading icon holder edge.
  static const double snackIconHolder = 32;

  /// Width of VelvetSnack's leading accent spine — its one saturated
  /// element, the signature of the component.
  static const double snackSpine = 4;

  /// Extra bottom clearance a [VelvetSnack] (`shared/feedback/`) must pass as
  /// `bottomInset` on a screen sitting behind the MASTER's own 4-tile
  /// `VelvetBottomNavBar` (`shared/widgets/velvet_bottom_nav_bar.dart`) — a
  /// bar that widget builds inline as its host screen's own
  /// `bottomNavigationBar`, never suppressed. Mirrors that bar's own
  /// `ConstrainedBox(minHeight: 62)` plus its outer `VelvetSpacing.md` bottom
  /// margin; the device's own bottom safe-area inset is NOT included here —
  /// `VelvetSnackScope` already adds `MediaQuery.viewPadding.bottom` itself,
  /// so folding it into this constant too would double-count it. Keep this
  /// number in sync if `VelvetBottomNavBar`'s own dimensions ever change.
  static const double bottomNavClearanceMaster = 62 + VelvetSpacing.md;

  /// Same as [bottomNavClearanceMaster], for a screen sitting behind the
  /// CLIENT's 5-tab `ClientBottomNav`
  /// (`features/shell/presentation/widgets/client_bottom_nav.dart`) while
  /// that bar is NOT suppressed by `ClientShell` (it only hides on the exact
  /// `/bookings/:bookingId` route — a nested push one level deeper, e.g.
  /// `/bookings/:bookingId/review`, still shows it). Mirrors that bar's own
  /// 64dp rectangle plus its outer `VelvetSpacing.md` bottom margin; same
  /// device-safe-area exclusion rationale as [bottomNavClearanceMaster]. Keep
  /// this number in sync if `ClientBottomNav`'s own dimensions ever change.
  static const double bottomNavClearanceClient = 64 + VelvetSpacing.md;
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

  /// [extrudedCard], DIMMED for a pressed/tapped state — SAME offsets and
  /// blur, alpha cut to 45% on both the dark and light shadow (mirrors
  /// [borderedCard]/[borderedButton]'s own `.withValues(alpha: 0.45)`
  /// convention).
  ///
  /// FIX B (mobile-debugger, this session) — `ServiceCard`
  /// (`service_category_list.dart`) used to swap straight to `null`
  /// (`boxShadow: _pressed ? null : extrudedCard`) on `onTapDown`, animated
  /// over `AnimatedContainer`'s 150ms. A normal tap's down→up gap is far
  /// under 150ms, so the shadow transition reverses mid-flight — a REAL
  /// visual pulse (full shadow → briefly toward none → back to full),
  /// timed exactly like the user-reported "background flicker for a few
  /// milliseconds" on the walk-in service-selection page. This constant is
  /// the fix: the pressed state DIMS instead of fully removing the shadow,
  /// so no frame in the transition is ever shadowless — the two states
  /// interpolate smoothly between "full" and "dim", never "full" and "off".
  /// `ServiceCard` is SHARED with the services list page
  /// (`services_list_screen.dart`), so this propagates to every consumer —
  /// intended per this repo's REUSE-FIRST rule.
  static final List<BoxShadow> extrudedCardPressed = <BoxShadow>[
    BoxShadow(
      color: BrandColors.shadowDarkCard.withValues(alpha: 0.45),
      offset: const Offset(8, 8),
      blurRadius: 18,
    ),
    BoxShadow(
      color: BrandColors.shadowLightStrong.withValues(alpha: 0.45),
      offset: const Offset(-8, -8),
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

  /// Accent-gradient DISC shadow — a smaller-radius sibling of
  /// [extrudedButtonAccent], with offsets/blur reduced ~52/64 so the
  /// elevation reads proportional (not heavy) on an icon-only disc rather
  /// than a full-width CTA button.
  ///
  /// Promoted here (2026-08-26) from a private `_discShadow` constant that
  /// used to live only inside `client_bottom_nav.dart`'s
  /// `_CenterSearchButton`. Two surfaces now consume this SAME token —
  /// `_CenterSearchButton` (the elevated search disc) and
  /// `beauty_timeline_section.dart`'s `_TimelineNode` medallion circles
  /// (the "just make circles same as search button circle" product
  /// decision) — so a future shadow tweak propagates to both identically
  /// (REUSE-FIRST: one token, one fix, every consumer).
  static const List<BoxShadow> extrudedDiscAccent = <BoxShadow>[
    BoxShadow(color: Color(0xFF8C6A44), offset: Offset(5, 5), blurRadius: 11),
    BoxShadow(
      color: BrandColors.shadowLightStrong,
      offset: Offset(-5, -5),
      blurRadius: 11,
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

  /// VelvetSnack's lift. [borderedCard] widened one notch (blur 10 -> 16)
  /// because the snack floats further from the page than an in-flow bordered
  /// card and needs a deeper halo to detach from a busy list behind it. Still
  /// non-offset and alpha-attenuated, so the Impeller-GLES safety rule holds —
  /// this is the ONLY shadow `VelvetSnack` is allowed to use, since it floats
  /// over arbitrary content rather than being welded to the page background.
  /// Transcribed verbatim from
  /// `docs/signup-designs/VelvetSnack/lib/theme/velvet_tokens.dart`.
  static final List<BoxShadow> snackLift = <BoxShadow>[
    BoxShadow(
      color: BrandColors.shadowDarkCard.withValues(alpha: 0.55),
      blurRadius: 16,
    ),
  ];
}

/// Camel→mocha diagonal gradients for "accent disc" surfaces — the same two
/// consumers as [VelvetShadows.extrudedDiscAccent] just above: the client
/// bottom-nav's elevated search disc (`_CenterSearchButton`) and the BEAUTY
/// TIMELINE rail's medallion circles (`_TimelineNode`). Promoted 2026-08-26
/// so both surfaces read as the same physical material (REUSE-FIRST).
abstract final class VelvetGradients {
  /// Disc/medallion face fill.
  static const LinearGradient accentDiscFace = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[BrandColors.accentLatte, BrandColors.accentDeep],
  );

  /// Inner bevel sheen painted on top of [accentDiscFace] while the surface
  /// is in its elevated (non-pressed) state — sells the "physical pillow"
  /// read. White highlight top-left fading through transparent to a faint
  /// black shade bottom-right, matching the gradient's own diagonal.
  static final LinearGradient accentDiscBevel = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[
      Colors.white.withValues(alpha: 0.30),
      Colors.transparent,
      Colors.black.withValues(alpha: 0.14),
    ],
    stops: const <double>[0.0, 0.5, 1.0],
  );
}

/// Motion constants for [VelvetSnack] (`lib/shared/feedback/velvet_snack.dart`)
/// and its host — hoisted here (rather than inlined at call sites) so the
/// port kept exact numbers. Transcribed verbatim from
/// `docs/signup-designs/VelvetSnack/lib/theme/velvet_tokens.dart`
/// (`VelvetSnackMotion`).
abstract final class VelvetSnackMotion {
  /// Entrance — long enough to read as a deliberate settle, short enough not
  /// to delay the message.
  static const Duration enter = Duration(milliseconds: 320);

  /// Exit — deliberately faster than [enter]. Arrivals are announced, exits
  /// get out of the way.
  static const Duration exit = Duration(milliseconds: 200);

  /// Fast replace when a second snack pre-empts the current one.
  static const Duration replace = Duration(milliseconds: 120);

  static const Curve enterCurve = Curves.easeOutCubic;
  static const Curve exitCurve = Curves.easeInCubic;

  /// Slide travel, as a fraction of the snack's own height. 0.35 (not 1.0) so
  /// it rises **out of** the surface rather than flying in from off-screen —
  /// the neumorphic read is "extruded", not "launched".
  static const Offset slideFrom = Offset(0, 0.35);

  /// Entrance scale — a 4% inflate on the same curve, reinforcing the extrude.
  static const double scaleFrom = 0.96;

  /// Fade completes at 60% of the entrance so the text is legible before the
  /// slide finishes.
  static const Interval fadeIn = Interval(0, 0.6, curve: Curves.easeOut);

  /// Default dwell time before auto-dismiss.
  static const Duration dwell = Duration(seconds: 4);

  /// Dwell when a trailing action is present — the user needs time to reach
  /// it.
  static const Duration dwellWithAction = Duration(seconds: 6);
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
