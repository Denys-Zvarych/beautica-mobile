// Promoted 2026-09-26 (user-reported) — the profile "meta" row (pin/phone
// icon + a short piece of profile text) was forked byte-for-byte between
// `HomeProfileCard`'s private `_MetaLine` (Home Hub) and
// `PassportScreen._ProfileBlock._line` (Beauty Passport). Saved-settlement
// locality labels since Phase 348/350 compose a village/hromada/oblast
// string long enough to need a second line («с. Іванівка (Шишацька
// громада), Полтавська обл.»), and BOTH forks rendered
// `overflow: TextOverflow.ellipsis` with no `maxLines` — which Flutter
// silently collapses to a SINGLE line instead of wrapping (the same trap
// documented at `master_address_block.dart:342-346`), so the label read as
// «с. Іванівка (Шишацька гром…» on every profile that used either fork.
//
// PROMOTED, NOT COPIED (REUSE-FIRST) — one shared row, additive
// `maxLines`/`style` params so every pre-existing caller renders EXACTLY as
// before (default `maxLines: 1`, default `style: VelvetText.body14Text` —
// the identical style both forks hard-coded). Only the locality row at each
// call site opts into `maxLines: 2`.
//
// NAMED `ProfileMetaLine`, NOT `MetaLine` — a different, unrelated `MetaLine`
// (a service card's duration·price strip) already exists in
// `features/services/presentation/widgets/service_category_list.dart`. Same
// name, different shape (icon+text row here vs. duration/price pair there);
// keeping the two distinct avoids a confusing near-collision.
//
// ICON STAYS CENTER-ALIGNED EVEN WHEN [maxLines] > 1 — deliberately NOT
// top-aligned. `maxLines: 2` is a BUDGET, not a guarantee the text actually
// wraps: most locality strings are short and still render on one line, and
// keying the icon's alignment off the maxLines *parameter* (rather than the
// text's actual, only-known-at-layout line count) shifted the icon by 1px
// for every existing short-locality caller — a real, if tiny, pixel diff a
// first pass of this fix introduced and the golden suite caught
// (`master_profile`/`passport`/`public_master_profile` goldens). Center
// alignment is correct for the common one-line case and an acceptable,
// unchanged compromise for the rarer genuine two-line wrap.

import 'package:flutter/material.dart';

import '../../core/theme/brand_colors.dart';
import '../../core/theme/velvet_geometry.dart';
import '../../core/theme/velvet_text.dart';

/// A single icon + text "meta" row — a profile's location, phone, etc.
///
/// One line by default (matches every pre-existing call site byte-for-byte).
/// Pass `maxLines: 2` (or more) to let long content — chiefly a composed
/// saved-settlement locality label — wrap instead of being silently
/// collapsed to one ellipsised line.
class ProfileMetaLine extends StatelessWidget {
  const ProfileMetaLine({
    super.key,
    required this.icon,
    required this.text,
    this.iconWidget,
    this.onTap,
    this.textKey,
    this.maxLines = 1,
    this.style,
  });

  final IconData icon;

  /// Optional pre-built icon widget (e.g. an [AppIcon] SVG). When non-null it
  /// replaces the Material [Icon] built from [icon]; callers must size/tint
  /// it to match (16 px, [BrandColors.accent]).
  final Widget? iconWidget;
  final String text;
  final VoidCallback? onTap;

  /// Optional key applied to the inner [Text] so finders can target a
  /// specific meta line (e.g. the city) by key rather than matching its
  /// literal string.
  final Key? textKey;

  /// Line budget for [text]. Defaults to `1` — every pre-existing call site
  /// rendered (and, due to the ellipsis-without-maxLines trap, effectively
  /// enforced) a single line. Set to `2` for a locality row so a long
  /// composed saved-settlement label wraps instead of being cut mid-word.
  final int maxLines;

  /// Optional style override. Defaults to [VelvetText.body14Text] — the
  /// identical style both pre-promotion forks hard-coded.
  final TextStyle? style;

  static final TextStyle _defaultStyle = VelvetText.body14Text;

  @override
  Widget build(BuildContext context) {
    final Widget leading =
        iconWidget ?? Icon(icon, size: 16, color: BrandColors.accent);
    final Widget row = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        leading,
        const SizedBox(width: VelvetSpacing.sm),
        Flexible(
          child: Text(
            text,
            key: textKey,
            style: style ?? _defaultStyle,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
    if (onTap == null) return row;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: row,
    );
  }
}
