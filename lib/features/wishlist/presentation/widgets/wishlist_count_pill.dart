// Phase 236 — the BEAUTY WISH LIST section counter.
//
// Transcribed from the approved preview
// `docs/signup-designs/BeautyPassport/lib/widgets/passport_widgets.dart`
// (`WishlistCountPill`), with the preview's `VelvetColors`/`VelvetAlpha` tokens
// resolved to the shipped `BrandColors` + this file's own named alphas.
//
// It lives with the wish-list widgets rather than in `hub_widgets.dart`: the
// hub file holds the CROSS-feature hub building blocks, and this pill answers
// exactly one question ("how many are saved") for exactly one section.

import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/brand_colors.dart';
import '../../../../core/theme/velvet_geometry.dart';
import '../../../../core/theme/velvet_text.dart';

/// A small camel-tinted counter pill sitting beside the wish-list section
/// title — the section header's "how many are saved" affordance.
///
/// It carries a bare numeral and nothing else. No «збережено» label, no icon:
/// the section title it trails already names what is being counted, and a
/// second word here would make the header read as two competing labels.
/// Language-free by construction, so nothing about it needs localising.
class WishlistCountPill extends StatelessWidget {
  const WishlistCountPill({super.key, required this.count});

  /// How many services are saved. Rendered verbatim — never abbreviated to
  /// «99+»: the list is capped at one page (20) upstream, so there is no
  /// numeral wide enough to need it.
  final int count;

  /// The camel wash and its stroke. Named so the same tint is never re-derived
  /// by hand at a second call site, and so a future counter pill elsewhere can
  /// point at these rather than guessing.
  static const double _kFillAlpha = 0.18;
  static const double _kBorderAlpha = 0.35;

  /// Hoisted: the pill's decoration is constant, so allocating a fresh
  /// `BoxDecoration` + `Border.all` per build would be pure waste in a header
  /// that rebuilds with its section.
  static final BoxDecoration _decoration = BoxDecoration(
    color: BrandColors.accent.withValues(alpha: _kFillAlpha),
    borderRadius: BorderRadius.circular(VelvetRadii.pill),
    border: Border.all(
      color: BrandColors.accent.withValues(alpha: _kBorderAlpha),
    ),
  );

  static final TextStyle _style = VelvetText.pillSm;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: _kVerticalPadding,
      ),
      decoration: _decoration,
      child: Text('$count', style: _style),
    );
  }

  /// Half of `VelvetSpacing.xs` — the preview's own value. Deliberately below
  /// the `AppSpacing` scale's 4dp floor: this is a chip that hugs a single
  /// numeral beside a section title, and a 4dp inset would make it taller than
  /// the title's own line box and break the header's baseline.
  static const double _kVerticalPadding = VelvetSpacing.xs / 2;
}
