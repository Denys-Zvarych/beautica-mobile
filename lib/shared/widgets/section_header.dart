// Section heading row — a title, an optional info glyph, and an optional
// trailing widget (an action, or a count).
//
// PROMOTED (Phase 21.11, REUSE-FIRST) out of
// `features/schedule/presentation/widgets/schedule_widgets.dart`, where it was
// public but feature-local with a single consumer
// (`master_schedule_screen.dart`'s «Календар» heading). Phase 21.11's
// approved preview needs the SAME structure — title, spacer, trailing count —
// for its «Очікують підтвердження» header, and a second feature must not
// import another feature's `presentation/` widgets nor fork a near-identical
// `SectionHeaderRow`. Moved verbatim: the schedule caller passes none of the
// new parameter below and renders byte-identically.
//
// ADDITIVE parameter: [titleStyle] (default `null` → the original
// `VelvetText.headingSm`). Phase 21.11's header is the smaller
// `VelvetText.sectionLabel()` variant the approved preview specifies; every
// pre-existing caller omits it.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';

/// Section heading: a title, an optional info glyph, and an optional trailing
/// widget (e.g. an outlined "Налаштування" action, or a count).
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.info,
    this.trailing,
    this.titleStyle,
  });

  final String title;
  final String? info;
  final Widget? trailing;

  /// Overrides the default `VelvetText.headingSm` title style. Null keeps the
  /// original heading treatment — see this file's header for why it exists.
  final TextStyle? titleStyle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Text(title, style: titleStyle ?? VelvetText.headingSm),
        if (info != null) ...<Widget>[
          const SizedBox(width: VelvetSpacing.sm),
          Tooltip(
            message: info!,
            child: const Icon(
              Icons.info_outline_rounded,
              size: 18,
              color: BrandColors.muted,
            ),
          ),
        ],
        const Spacer(),
        ?trailing,
      ],
    );
  }
}
