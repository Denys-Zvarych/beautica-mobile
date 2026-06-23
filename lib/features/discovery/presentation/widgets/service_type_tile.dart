// Phase 13.3 — «Вид послуги» grid tile + category→glyph mapper.
//
// A round neumorphic icon tile + caption. Raised pillow by default; on select
// it presses into a concave inset well and the glyph warms to camel — the
// signature interaction of the Пошук filter screen (ported from the approved
// preview's `ServiceTypeTile`, swapping local `VelvetColors.*` for the in-app
// `BrandColors.*` and the standalone tokens for `VelvetSpacing`/`VelvetRadii`).
//
// Icon source: Material OUTLINE glyphs mapped from the category's uppercase
// wire slug (no new Flaticon SVG assets this pass — avoids the release-gate).
// Unmapped categories fall back to a generic spa glyph.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';

/// Maps an approved-category wire slug (uppercase, e.g. `MANICURE`,
/// `LASH_EXTENSIONS`) to a thin-line Material outline glyph for the
/// «Вид послуги» tile.
///
/// Matching is by substring on the slug so the dynamic backend taxonomy (which
/// splits e.g. nails into `MANICURE` / `PEDICURE` / `NAIL_ART`) all resolve to a
/// sensible family glyph without an exhaustive enum. Unmapped slugs fall back to
/// a generic spa glyph — every tile always renders an icon.
IconData serviceTypeIcon(String categorySlug) {
  final String s = categorySlug.toUpperCase();
  bool has(String token) => s.contains(token);

  if (has('PEDICURE')) return Icons.spa_outlined;
  if (has('MANICURE') || has('NAIL')) return Icons.back_hand_outlined;
  if (has('BROW')) return Icons.remove_red_eye_outlined;
  if (has('LASH') || has('EYELASH')) return Icons.visibility_outlined;
  if (has('MAKE') || has('MAKEUP')) return Icons.brush_outlined;
  if (has('HAIR') || has('BARBER') || has('BEARD')) {
    return Icons.content_cut_outlined;
  }
  if (has('COSMETOLOG') || has('FACE') || has('SKIN')) {
    return Icons.face_retouching_natural_outlined;
  }
  if (has('MASSAGE') || has('BODY')) return Icons.self_improvement_outlined;
  if (has('SPA')) return Icons.spa_outlined;
  if (has('REMOVAL') || has('EPIL') || has('LASER')) {
    return Icons.auto_fix_high_outlined;
  }
  if (has('TATTOO') || has('PERMANENT')) return Icons.gesture_outlined;
  return Icons.spa_outlined;
}

/// A round neumorphic icon tile + caption used in the «Вид послуги» grid.
///
/// Selected → pressed-in inset well with a camel glyph; otherwise a raised
/// pillow with a muted glyph. Single-select is enforced by the caller (the
/// controller replaces the prior selection).
class ServiceTypeTile extends StatelessWidget {
  const ServiceTypeTile({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  // Hoisted: the raised-pillow circle decoration never changes, so build()
  // never re-allocates it.
  static const BoxDecoration _raisedCircle = BoxDecoration(
    color: BrandColors.base,
    shape: BoxShape.circle,
    boxShadow: VelvetShadows.extrudedSmall,
  );

  // Caption styles — one per selected/unselected colour, allocated once.
  static final TextStyle _labelSelected = VelvetText.body().copyWith(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: BrandColors.accentDeep,
  );
  static final TextStyle _labelUnselected = VelvetText.body().copyWith(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: BrandColors.textSecondary,
  );

  @override
  Widget build(BuildContext context) {
    final Widget circle = selected
        ? NeumorphicInset(
            radius: 33,
            child: SizedBox(
              height: 66,
              width: 66,
              child: Icon(icon, color: BrandColors.accent, size: 26),
            ),
          )
        : DecoratedBox(
            decoration: _raisedCircle,
            child: SizedBox(
              height: 66,
              width: 66,
              child: Icon(icon, color: BrandColors.textSecondary, size: 26),
            ),
          );

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            circle,
            const SizedBox(height: VelvetSpacing.sm),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: selected ? _labelSelected : _labelUnselected,
            ),
          ],
        ),
      ),
    );
  }
}
