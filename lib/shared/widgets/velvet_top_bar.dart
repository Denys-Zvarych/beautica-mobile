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

/// A 48 dp fixed-height top bar with an optional back arrow, a centred title
/// (or [titleWidget] override), and an optional trailing widget.
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
    this.backKey,
    this.titleWidget,
  });

  /// Title rendered centred in the 48 dp strip via `Text(title,
  /// style: VelvetText.pageTitle)` — UNLESS [titleWidget] is supplied, in
  /// which case [titleWidget] is rendered in that exact slot instead and
  /// [title] is used only as this bar's accessible identity (kept required
  /// so every call site still states its screen's semantic title even when
  /// swapping in custom title content).
  final String title;

  /// Optional replacement for the default centred `Text(title, ...)` — e.g.
  /// the "beautica" wordmark on [MyRatingScreen]. Purely additive: omitted
  /// (the default) renders EXACTLY the pre-existing `Text(title,
  /// style: VelvetText.pageTitle)`, so all 5 pre-existing call sites are
  /// byte-identical. When supplied, [title] no longer renders visually but
  /// still documents the screen's identity at the call site.
  ///
  /// Content contract: this slot must carry only static, bounded,
  /// non-user-controlled content — brand marks or other fixed labels known
  /// at build time. Never pass server- or user-derived text here; [title]
  /// remains this bar's accessible identity regardless of what (if anything)
  /// is rendered visually.
  final Widget? titleWidget;

  /// Tap handler for the back arrow. When null the arrow is not shown.
  final VoidCallback? onBack;

  /// Accessible label for the back button (defaults to `'Назад'`; pass a
  /// localised string from [AppLocalizations] at the call site when available).
  final String backSemanticLabel;

  /// Optional right-aligned widget (edit button, overflow menu, etc.).
  final Widget? trailing;

  /// Optional key for the back [NeumorphicIconButton] (used by widget tests).
  ///
  /// Mirrors [SectionScaffold.backKey] so a screen migrating from a Material
  /// `AppBar` can keep its existing back-button test contract. Defaults to null
  /// — existing call sites are unaffected.
  final Key? backKey;

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
                  key: backKey,
                  icon: Icons.arrow_back_ios_new_rounded,
                  semanticLabel: backSemanticLabel,
                  onTap: onBack!,
                ),
              ),
            titleWidget ??
                Text(
                  title,
                  style: VelvetText.pageTitle,
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
