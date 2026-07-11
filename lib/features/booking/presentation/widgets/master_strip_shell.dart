// Shared "who you're booking with" card shell.
//
// Extracted from the two hand-rolled strips that carried an identical outer
// structure — `widgets/master_strip.dart` (independent-master flow) and
// `widgets/salon_master_strip.dart` (salon flow). Both wrapped the SAME
// `Semantics` + `Material(type: transparency)` Hero-flight guard +
// `NeumorphicCard(#EDE4D5)` + `Row[ MasterAvatarBadge, Expanded(Column[ top
// label, name, one subtitle line ]), trailing ]` around content that only
// differed in three slots:
//
//   • the subtitle line ([middleLine]) — independent: the master's
//     professional title / role; salon: the services this master performs;
//   • the [trailing] widget — independent: a ★ rating readout; salon: a
//     summed-duration pill;
//   • the avatar wash ([avatarGradient]/[avatarBordered]) and the localized
//     [semanticsLabel].
//
// Lifting the common frame here means both cards are now the SAME shell/
// appearance (radius, fill, paddings, text tokens, avatar badge, Hero-flight
// text guard), so a theme refactor touches one place and the two flows can
// never visually drift. The `Material(type: transparency)` wrapper is kept
// unconditionally: it paints nothing (only installs an ambient
// `Theme`/`DefaultTextStyle`) and guards the independent strip's Hero flight —
// harmless dead-weight for the salon strip, which isn't Hero-wrapped.
//
// Any `Hero(tag:)` stays OUTSIDE this shell, at the call sites that already
// own it (`slot_picker_screen.dart`, `booking_summary_cards.dart`).

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';

import 'master_avatar_badge.dart';

/// The shared camel-wash identity card frame. Callers supply the three
/// content slots ([middleLine], [trailing], [avatarGradient]) plus the
/// localized [name]/[topLabel]/[semanticsLabel]; the shell owns the fixed
/// structure, surface, paddings and the Hero-flight `Material` guard.
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

  /// Optional subtitle line under the name — the master's title/role
  /// (independent flow) or their services line (salon flow).
  final Widget? middleLine;

  /// Optional trailing widget — the ★ rating readout (independent flow) or the
  /// summed-duration pill (salon flow).
  final Widget? trailing;

  /// Two-stop diagonal avatar gradient; `null` falls back to
  /// [MasterAvatarBadge]'s default camel→mocha wash.
  final List<Color>? avatarGradient;

  /// Adds the salon flow's translucent-white avatar ring.
  final bool avatarBordered;

  /// Vertical gap between the name and [middleLine]. Independent flow uses 2;
  /// the salon flow's services row uses 4 for a little more breathing room.
  final double middleGap;

  /// Camel-wash surface — the same lighter taupe used by the pinned booking
  /// summary shelf, so the strip reads as sitting on its own elevated card.
  static const Color _stripSurface = Color(0xFFEDE4D5);

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
        // interfere with NeumorphicCard's own shadow/decoration painting.
        type: MaterialType.transparency,
        child: NeumorphicCard(
          color: _stripSurface,
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
    );
  }
}
