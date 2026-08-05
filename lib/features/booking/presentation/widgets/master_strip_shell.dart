// Shared "who you're booking with" card shell — the fixed outer frame behind
// [MasterStrip], the single identity card every booking screen (both flows)
// renders.
//
// Owns the `Semantics` + `Material(type: transparency)` Hero-flight guard +
// the `#EDE4D5` camel-wash card (a single `NeumorphicCard`-style bordered
// decoration carrying the fill colour, hairline border AND a non-offset
// `borderedCard` shadow together — Impeller-GLES-safe, see the build comment) +
// `Row[ MasterAvatarBadge, Expanded(Column[ top
// label, name, one subtitle line ]), trailing ]` structure, and exposes the
// variable parts as slots ([middleLine], [trailing], [avatarGradient]/
// [avatarBordered], [topLabel], [semanticsLabel]) so the card's surface,
// radius, paddings, text tokens and avatar badge live in exactly one place.
//
// The `Material(type: transparency)` wrapper is unconditional: it paints
// nothing (only installs an ambient `Theme`/`DefaultTextStyle`) and guards the
// Hero flight on the call sites that fly this card between screens.
//
// Any `Hero(tag:)` stays OUTSIDE this shell, at the call sites that already
// own it (`slot_picker_screen.dart`, `booking_summary_cards.dart`).
//
// The optional [onTap] adds a radius-clipped camel press wash INSIDE the card
// and NOTHING at rest, so a tappable instance and an inert one are pixel-
// identical until touched — see [onTap]'s doc for why that matters on a card
// nine screens share, and `MasterStrip.onTap` for which screens opt in.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';

import 'master_avatar_badge.dart';

/// The camel-wash identity card frame. Callers supply the three content slots
/// ([middleLine], [trailing], [avatarGradient]) plus the localized
/// [name]/[topLabel]/[semanticsLabel]; the shell owns the fixed structure,
/// surface, paddings and the Hero-flight `Material` guard.
class MasterStripShell extends StatelessWidget {
  const MasterStripShell({
    super.key,
    required this.semanticsLabel,
    required this.name,
    this.topLabel,
    this.middleLine,
    this.trailing,
    this.avatarGradient,
    this.avatarBordered = false,
    this.middleGap = 2,
    this.onTap,
  });

  /// The full localized accessibility label for the card.
  final String semanticsLabel;

  /// Master display name — the emphasized subheading line.
  final String name;

  /// Optional muted prefix above the name (e.g. «Запис до майстра»); `null`
  /// renders no top label.
  final String? topLabel;

  /// Optional subtitle line under the name — the master's professional title,
  /// falling back to their role label.
  final Widget? middleLine;

  /// Optional trailing widget — the ★ rating readout.
  final Widget? trailing;

  /// Two-stop diagonal avatar gradient; `null` falls back to
  /// [MasterAvatarBadge]'s default camel→mocha wash.
  final List<Color>? avatarGradient;

  /// Adds the salon flow's translucent-white avatar ring.
  final bool avatarBordered;

  /// Vertical gap between the name and [middleLine]. [MasterStrip] leaves it
  /// at the default 2.
  final double middleGap;

  /// Makes the whole card tappable. `null` (the default) leaves it inert —
  /// the card is then a pure identity readout with no button semantics.
  ///
  /// The affordance is deliberately PRESS-ONLY: no chevron, no glyph, no
  /// tint at rest, so a tappable strip and an inert one are pixel-identical
  /// until touched. This card is shared by nine screens, half of which must
  /// stay inert (see the tappability policy on [MasterStrip.onTap]); a
  /// rest-state marker would either shift every one of them or make the same
  /// object look like two different objects depending on the screen.
  final VoidCallback? onTap;

  /// Camel-wash surface — the same lighter taupe used by the pinned booking
  /// summary shelf, so the strip reads as sitting on its own elevated card.
  static const Color _stripSurface = Color(0xFFEDE4D5);

  // The card radius on the single decoration that carries the fill colour and
  // the shadow together. Compile-time const so the whole BorderRadius is const.
  static const BorderRadius _radius = BorderRadius.all(
    Radius.circular(VelvetRadii.card),
  );

  /// Press wash for the tappable variant — camel [BrandColors.accent] at low
  /// alpha, NOT Material's default ink. A stock M3 ripple reads as a foreign
  /// flat-design idiom on a neumorphic camel-wash card; tinting it keeps the
  /// press inside the locked palette.
  static final Color _splash = BrandColors.accent.withValues(alpha: 0.14);
  static final Color _highlight = BrandColors.accent.withValues(alpha: 0.07);

  /// The card's one decoration, hoisted out of [build] (mobile-perf LOW).
  ///
  /// It depends on NO field — it is a pure constant that only `Border.all`
  /// keeps from being `const` — yet it was reallocated on every `build()`.
  /// That is the same waste `MasterBookingCard` hoisted under an earlier
  /// mobile-perf MEDIUM (`master_booking_card.dart:663`), and it now has teeth
  /// here too: a press on a tappable strip rebuilds this subtree, and a list
  /// of these rebuilds all of them at once.
  ///
  /// IMPELLER-GLES CORNER FIX: `extrudedCard` pairs a dark shadow with a
  /// near-white light shadow (`shadowLightStrong`, alpha FF) at a diagonal
  /// `Offset(-8,-8)`. Impeller's OpenGLES backend rasterizes that offset
  /// opaque rrect's untranslated corner as a crisp white SQUARE poking past
  /// the card's rounded corner onto the taupe `base`. The remedy is the
  /// codebase's own `borderedCard` recipe: a single NON-offset,
  /// semi-transparent dark shadow whose rrect footprint exactly matches the
  /// card (uniform soft halo, no protruding corner), paired with the hairline
  /// `BrandColors.faint` border that carries the "distinct shape" job —
  /// mirroring `NeumorphicCard`'s `showBorder` path. The border is what makes
  /// this `final` rather than `const`.
  static final BoxDecoration _decoration = BoxDecoration(
    color: _stripSurface,
    borderRadius: _radius,
    border: Border.all(color: BrandColors.faint, width: 1),
    boxShadow: VelvetShadows.borderedCard,
  );

  @override
  Widget build(BuildContext context) {
    Widget content = Padding(
      padding: const EdgeInsets.all(VelvetSpacing.sm + 4),
      child: Row(
        children: <Widget>[
          MasterAvatarBadge(gradient: avatarGradient, bordered: avatarBordered),
          const SizedBox(width: VelvetSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (topLabel != null) ...<Widget>[
                  Text(topLabel!, style: VelvetText.masterStripLabel),
                  const SizedBox(height: 2),
                ],
                Text(
                  name,
                  style: VelvetText.masterStripName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (middleLine != null) ...<Widget>[
                  SizedBox(height: middleGap),
                  middleLine!,
                ],
              ],
            ),
          ),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: VelvetSpacing.sm),
            trailing!,
          ],
        ],
      ),
    );

    final VoidCallback? tap = onTap;
    if (tap != null) {
      // The InkWell needs its OWN `Material` here, INSIDE the `DecoratedBox`.
      // Ink is painted by the nearest Material ancestor underneath its child,
      // so an InkWell hung off the outer transparency `Material` (which sits
      // ABOVE the DecoratedBox) would splash beneath the card's opaque
      // `_stripSurface` fill and be invisible. Nesting a second transparency
      // Material as the DecoratedBox's child puts the ink layer on top of the
      // fill. `borderRadius` clips the wash to the card's own 24dp corners.
      //
      // Added ONLY on the tappable branch so the inert call sites keep their
      // exact current widget tree.
      content = Material(
        type: MaterialType.transparency,
        borderRadius: _radius,
        child: InkWell(
          onTap: tap,
          borderRadius: _radius,
          splashColor: _splash,
          highlightColor: _highlight,
          child: content,
        ),
      );
    }

    return Semantics(
      label: semanticsLabel,
      button: tap != null,
      // The tappable branch nests an `InkWell`, which contributes its OWN
      // button node carrying the real tap action. Without `excludeSemantics`
      // TalkBack met TWO nodes for one card — an outer labelled button with no
      // action, then an inner actionable one — the same double-announce the
      // booking card was already pulled up on. Excluding the subtree collapses
      // it to one node, which then has to carry the action itself via `onTap`.
      // `MasterFeedbackCard` (`master_feedback_card.dart:166`) already does
      // exactly this; this is the same construction.
      //
      // Safe for the inert branch too: `semanticsLabel` is composed by
      // `MasterStrip` from the very fields the excluded subtree renders (name,
      // subtitle, rating, review count), so nothing announceable is lost.
      onTap: tap,
      excludeSemantics: true,
      child: Material(
        // Guards against the Hero-flight shuttle rendering this subtree
        // outside any Material ancestor: without one, every Text below
        // resolves against MaterialApp's literal error DefaultTextStyle
        // (underlined, no explicit height) for the duration of the flight,
        // producing a brief flash of underlined/tight-line-height text on
        // the master's name. `transparency` paints nothing itself — it only
        // installs the ambient Theme/DefaultTextStyle — so it doesn't
        // interfere with the card's own shadow/decoration painting.
        type: MaterialType.transparency,
        // Decoration hoisted to [_decoration] — see its doc for the
        // Impeller-GLES corner rationale behind the `borderedCard` recipe.
        child: DecoratedBox(decoration: _decoration, child: content),
      ),
    );
  }
}
