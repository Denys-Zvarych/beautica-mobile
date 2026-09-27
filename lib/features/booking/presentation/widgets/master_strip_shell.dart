// Shared "who you're booking with" card shell — the fixed outer frame behind
// [MasterStrip], the single identity card every booking screen (both flows)
// renders.
//
// Owns the `Semantics` + `Material(type: transparency)` Hero-flight guard +
// the `#EDE4D5` camel-wash card (a single `NeumorphicCard`-style bordered
// decoration carrying the fill colour, hairline border AND a non-offset
// `borderedCard` shadow together — Impeller-GLES-safe, see the build comment) +
// `Row[ MasterAvatarBadge, Expanded(Column[ top label, name,
// Row[ Expanded(subtitle), trailing ] ]) ]` structure — the trailing readout
// ALWAYS rides the SUB-LINE row, never the outer row, so the name keeps the
// column's full width unconditionally (see the placement note in `build`) —
// and exposes the
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
  ///
  /// ALWAYS rendered right-aligned on the sub-line row under the name, so it
  /// can never compete with the master's name for horizontal space. When
  /// there is no [middleLine] the shell synthesises that row with an empty
  /// `Expanded` in front of the readout rather than falling back to the outer
  /// row — there is deliberately no outer-row placement left to fall back to.
  /// See the placement note in [build].
  final Widget? trailing;

  /// Two-stop diagonal avatar gradient; `null` falls back to
  /// [MasterAvatarBadge]'s default camel→mocha wash.
  final List<Color>? avatarGradient;

  /// Adds the salon flow's translucent-white avatar ring.
  final bool avatarBordered;

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
    final Widget? middle = middleLine;
    final Widget? trail = trailing;

    // WHERE THE TRAILING READOUT SITS (2026-09-19, audit HIGH + its LOW
    // follow-up).
    //
    // It ALWAYS rides a SUB-LINE row, NEVER the outer row. There is no longer
    // a branch that can put it beside the name.
    //
    // Hung off the outer `Row`, the readout's full intrinsic width (a 16dp
    // star + «4.8» + «(12)» ≈ 70dp, plus its 8dp gap) came out of the name's
    // `Expanded` — the name and the readout competed for the same horizontal
    // budget even though they sit on different visual lines. At 320dp @ text
    // scale 1.0 — the DEFAULT on a small phone, not an a11y edge case — that
    // left «Олена Ковальчук» 8dp short and it ellipsized. The name is the
    // card's primary identity; it is the one thing here that must never
    // truncate.
    //
    // Moving the readout onto the sub-line row gives the name the column's
    // full width and also binds the rating to the line it actually qualifies
    // (the master's role/title) instead of floating it at the card's vertical
    // centre. This is the composition the deleted `_SalonConfirmMasterCard`
    // fork used, now folded back into the ONE shared shell so all ten booking
    // screens get the wider name column — REUSE-FIRST: the propagation is the
    // point.
    //
    // WHY THERE IS NO `middleLine == null` FALLBACK ANY MORE (the LOW both
    // audits raised, from opposite directions). The first cut of this fix
    // kept the outer-row placement for a card with no sub-line, gated on
    // `middle != null && trail != null`. That left the pre-fix narrow-name
    // layout one keyword away: `MasterStrip.showRole` defaults to FALSE on
    // three of its four constructors, so any future
    // `showRating: true`-without-`showRole: true` call site would have routed
    // straight back onto it — and it was the only untested branch in the
    // shell. An unreachable, untested branch that silently restores a shipped
    // defect is worse than no branch, so the branch is GONE: whenever there
    // is a [trailing] slot the shell SYNTHESISES the sub-line row, putting an
    // empty `Expanded` where there is no [middleLine] to go. The name keeps
    // the column's full width unconditionally — the narrow layout is not
    // representable.
    //
    // NO new parameter: the shell decides from the slots it already has, and
    // the constructor is unchanged. The TRUE name-only card
    // (`middleLine == null` AND `trailing == null` — what every production
    // `showRole: false, showRating: false` call site renders) is untouched:
    // it still emits no sub-line row at all.
    final Widget? subLine = trail != null
        ? Row(
            children: <Widget>[
              // The sub-line still yields first: it is a role label that
              // already ellipsizes at every call site, whereas the readout is
              // four glyphs that mean nothing clipped. With no [middleLine]
              // the `Expanded` is empty and simply right-aligns the readout.
              Expanded(child: middle ?? const SizedBox.shrink()),
              if (middle != null) const SizedBox(width: VelvetSpacing.sm),
              trail,
            ],
          )
        : middle;

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
                if (subLine != null) ...<Widget>[
                  // Same 2dp the top-label gap above uses — one spelling for
                  // "hairline gap inside this card's text column". Was a
                  // `middleGap` parameter until 2026-09-19 (audit LOW): it
                  // had exactly ONE production value across all ten booking
                  // screens and no `lib/` call site ever set it, so it was a
                  // knob that could only ever drift the shared card apart.
                  const SizedBox(height: 2),
                  subLine,
                ],
              ],
            ),
          ),
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
