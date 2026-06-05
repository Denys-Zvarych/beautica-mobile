// Shared VelvetTouch top-bar chrome.
//
// Extracted from `profile_scaffold.dart` so that any screen that needs the
// standard fixed-height (48 dp) header — back arrow (left), centred title,
// optional trailing action (right) — can use the identical pixel-level construct
// without risk of the two surfaces drifting over time.
//
// Usage (within a SafeArea → Column):
//   VelvetTopBar(title: l10n.scheduleTitle, onBack: () { ... }),

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';

/// A 48 dp fixed-height top bar with an optional back arrow, a centred title,
/// and an optional trailing widget.
///
/// Drop this as the **first child** of a `SafeArea → Column`. The surrounding
/// `Padding` (fromLTRB lg / md / lg / xs) is baked in, matching
/// [ProfileScaffold]'s header exactly.
class VelvetTopBar extends StatelessWidget {
  const VelvetTopBar({
    super.key,
    required this.title,
    this.onBack,
    this.backSemanticLabel = 'Назад',
    this.trailing,
  });

  /// Title rendered centred in the 48 dp strip.
  final String title;

  /// Tap handler for the back arrow. When null the arrow is not shown.
  final VoidCallback? onBack;

  /// Accessible label for the back button (defaults to `'Назад'`; pass a
  /// localised string from [AppLocalizations] at the call site when available).
  final String backSemanticLabel;

  /// Optional right-aligned widget (edit button, overflow menu, etc.).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        VelvetSpacing.lg,
        VelvetSpacing.md,
        VelvetSpacing.lg,
        VelvetSpacing.xs,
      ),
      child: SizedBox(
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            if (onBack != null)
              Align(
                alignment: Alignment.centerLeft,
                child: NeumorphicIconButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  semanticLabel: backSemanticLabel,
                  onTap: onBack!,
                ),
              ),
            Text(
              title,
              style: VelvetText.subheading(),
              textAlign: TextAlign.center,
            ),
            if (trailing != null)
              Align(alignment: Alignment.centerRight, child: trailing),
          ],
        ),
      ),
    );
  }
}
