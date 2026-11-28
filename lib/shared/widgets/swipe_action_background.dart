// M544 — the `Dismissible` background revealed by an end-to-start swipe on a
// list card. PROMOTED (REUSE-FIRST) out of `my_salons_screen.dart`, where it
// was the private `_DeleteSalonSwipeBackground`; the defaults reproduce that
// salon reveal exactly (golden-verified by
// `test/golden/my_salons_hub_header_golden_test.dart`), and the «Клієнти» list
// passes its own icon + label.
//
// Flat `BrandColors.error` fill (the same warm terracotta-red
// `SettingsRow(destructive: true)` uses), rounded to `VelvetRadii.card` so
// the reveal reads as "what's under the card" rather than a separate banner.
// Trailing-aligned icon + label: the card slides away to the left, so the
// reveal grows in from the right. No gradient, no blur, no second shadow — the
// sliding card above still carries its own `VelvetShadows.extrudedCard`.
//
// mobile-perf note (swipe-to-delete audit 2026-09): `Dismissible` always
// builds its `background` and clips it to zero width at rest; this widget is
// `const`-constructible with no state and no per-frame work, so that cost is
// accepted.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

/// The trailing-aligned swipe reveal under a list card. See the file header.
class SwipeActionBackground extends StatelessWidget {
  const SwipeActionBackground({
    super.key,
    this.icon = Icons.delete_outline_rounded,
    this.label,
    this.color,
  });

  /// The glyph beside the label. Default: the salon delete glyph.
  final IconData icon;

  /// The label. `null` → «Видалити салон» (`deleteSalonAction`), the original
  /// salon-hub reveal.
  final String? label;

  /// The fill. `null` → [BrandColors.error].
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.lg),
      decoration: BoxDecoration(
        color: color ?? BrandColors.error,
        borderRadius: BorderRadius.circular(VelvetRadii.card),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: BrandColors.white, size: 24),
          const SizedBox(width: VelvetSpacing.xs),
          Text(
            label ?? AppLocalizations.of(context).deleteSalonAction,
            style: VelvetText.bodyStrong().copyWith(color: BrandColors.white),
          ),
        ],
      ),
    );
  }
}
