// Shared "who you're booking with" card shell — the fixed outer frame behind
// [MasterStrip], the single identity card every booking screen (both flows)
// renders.
//
// Owns the `Semantics` + `Material(type: transparency)` Hero-flight guard +
// the extruded `#EDE4D5` camel-wash card (shadow layer + RRect-clipped fill,
// mirroring `NeumorphicCard` but Impeller-GLES-safe — see the build comment) +
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

import 'package:flutter/material.dart';

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

  /// Camel-wash surface — the same lighter taupe used by the pinned booking
  /// summary shelf, so the strip reads as sitting on its own elevated card.
  static const Color _stripSurface = Color(0xFFEDE4D5);

  // The card radius, shared by the shadow layer, the clip, and the fill layer.
  // Compile-time const so the whole BorderRadius is const.
  static const BorderRadius _radius = BorderRadius.all(
    Radius.circular(VelvetRadii.card),
  );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
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
        // IMPELLER-GLES CORNER FIX: the extruded card shadow lives on an OUTER
        // shadow-only box, while the taupe fill is painted inside a ClipRRect.
        // Drawn as one `BoxDecoration(color + borderRadius + boxShadow)` (what
        // NeumorphicCard does), Impeller's OpenGLES backend leaks this card's
        // square fill corners out from behind the rounded arc as opaque
        // (near-white) rectangles — mirrors the master avatar's own RRect
        // workaround and the locality picker sheet's surface clip.
        child: DecoratedBox(
          decoration: const BoxDecoration(
            borderRadius: _radius,
            boxShadow: VelvetShadows.extrudedCard,
          ),
          child: ClipRRect(
            borderRadius: _radius,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: _stripSurface,
                borderRadius: _radius,
              ),
              child: Padding(
                padding: const EdgeInsets.all(VelvetSpacing.sm + 4),
                child: Row(
                  children: <Widget>[
                    MasterAvatarBadge(
                      gradient: avatarGradient,
                      bordered: avatarBordered,
                    ),
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
              ),
            ),
          ),
        ),
      ),
    );
  }
}
