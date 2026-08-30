// Phase 4.2 — ContactTile.
//
// Moved here (Phase 13.6) from
// `features/master/presentation/widgets/profile_avatar.dart` so it can be
// reused across features (the master AND salon public profiles both render a
// phone/Instagram contact row) without a cross-feature `presentation/`-to-
// `presentation/` import, which the architecture's layering rule forbids.
// `features/master/presentation/widgets/profile_avatar.dart` now re-exports
// this file so its existing import sites are unaffected.
//
// Ported verbatim from
// `docs/signup-designs/MasterProfileScreen/lib/widgets/profile_widgets.dart`.
// `VelvetColors.*` → `BrandColors.*`; all VelvetSpacing/VelvetRadii/VelvetShadows
// are identical in production.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';

/// A tappable raised contact row (phone / Instagram). A small inset glyph well
/// on the left, the value in the middle, a chevron on the right. Depresses on
/// press to confirm the tap.
///
/// When [label] is provided (e.g. "Instagram"), it renders as a muted caption
/// above [value], turning the text column into a two-line block so the
/// platform is always clear without relying on a branded icon.
///
/// When [valueIsPlaceholder] is `true` (default `false`, so every existing
/// call site is unaffected), [value] renders in [VelvetText.link] — the same
/// mocha link weight the screen's other bare "add this" affordances use —
/// instead of [VelvetText.bodyStrong]. Use it for an "add a value" row (e.g.
/// «Додати посилання» standing in for an unset Instagram handle) so the
/// placeholder reads as an invitation to act rather than as real tile data.
class ContactTile extends StatefulWidget {
  const ContactTile({
    super.key,
    required this.icon,
    required this.value,
    required this.onTap,
    required this.semanticLabel,
    this.label,
    this.valueIsPlaceholder = false,
  });

  final IconData icon;
  final String value;
  final VoidCallback onTap;
  final String semanticLabel;

  /// Optional platform label shown above [value] in muted caption style.
  final String? label;

  /// When `true`, [value] renders as a link-styled placeholder rather than a
  /// real value. See class doc.
  final bool valueIsPlaceholder;

  @override
  State<ContactTile> createState() => _ContactTileState();
}

class _ContactTileState extends State<ContactTile> {
  bool _pressed = false;

  TextStyle get _valueStyle =>
      widget.valueIsPlaceholder ? VelvetText.link() : VelvetText.bodyStrong();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _pressed ? 0.985 : 1,
          duration: const Duration(milliseconds: 110),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: BrandColors.base,
              borderRadius: BorderRadius.circular(VelvetRadii.field),
              boxShadow: _pressed ? null : VelvetShadows.extrudedSmall,
            ),
            padding: const EdgeInsets.all(VelvetSpacing.sm + 4),
            child: Row(
              children: <Widget>[
                SizedBox(
                  height: 40,
                  width: 40,
                  child: NeumorphicInset(
                    radius: VelvetRadii.field - 4,
                    child: Center(
                      child: Icon(
                        widget.icon,
                        size: 18,
                        color: BrandColors.accentDeep,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: VelvetSpacing.md),
                Expanded(
                  child: widget.label != null
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              widget.label!,
                              // M-2 fix: pre-composed static; zero per-frame
                              // allocation.
                              style: VelvetText.contactPlatformLabel,
                            ),
                            const SizedBox(height: 2),
                            Text(widget.value, style: _valueStyle),
                          ],
                        )
                      : Text(widget.value, style: _valueStyle),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: BrandColors.faint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
