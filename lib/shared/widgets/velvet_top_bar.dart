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
    this.backLabel,
  });

  /// Optional VISIBLE text beside the back chevron (additive, Phase 24.1a —
  /// the owner master-mode «‹ Салон» pill), forwarded to
  /// [NeumorphicIconButton.label]. When non-null AND the back button renders
  /// ([onBack] non-null) the default centred title gets symmetric
  /// [labelledTitleInsetFor] padding plus a one-line ellipsis so it can never
  /// run under the pill, at any text scale. `null` (every pre-existing call site)
  /// renders the byte-identical tree.
  final String? backLabel;

  /// Symmetric horizontal inset of the centred title when [backLabel] is set
  /// at 1.0× text scale: the pill measured once with the longest label in use
  /// («Салон», 95.6 dp) plus a [VelvetSpacing.sm] gap. A constant, not a
  /// `LayoutBuilder` — the label set is closed and small. The inset actually
  /// applied is [labelledTitleInsetFor], which grows the label part with the
  /// ambient text scale.
  static const double labelledTitleInset =
      _pillFixedWidth + _pillLabelWidth + VelvetSpacing.sm;

  /// The text-scale-INDEPENDENT part of the labelled pill: md padding on both
  /// sides + the 22 dp chevron (icons do not text-scale) + the xs gap.
  static const double _pillFixedWidth =
      2 * VelvetSpacing.md + 22 + VelvetSpacing.xs;

  /// The longest label («Салон») laid out at 1.0× in
  /// `VelvetText.bodyStrong()` — 37.6 dp, rounded up. Scaled linearly by the
  /// text scaler, which over-estimates real glyph growth (73.9 dp at 2.0×), so
  /// the inset errs on the side of clearing the pill.
  static const double _pillLabelWidth = 38;

  /// The title inset for [scaler]: the pill's fixed part plus its label part
  /// scaled by [scaler], capped at [NeumorphicIconButton.labelMaxWidth] (the
  /// pill can never be wider), plus the [VelvetSpacing.sm] gap. Equals
  /// [labelledTitleInset] at 1.0×.
  static double labelledTitleInsetFor(TextScaler scaler) =>
      labelledPillWidthFor(scaler) + VelvetSpacing.sm;

  /// The estimated width of the labelled back pill at [scaler]: its fixed part
  /// plus the label part scaled by [scaler], capped at
  /// [NeumorphicIconButton.labelMaxWidth] (the pill can never be wider). The
  /// single estimate every labelled-back host sizes against.
  static double labelledPillWidthFor(TextScaler scaler) {
    final double pill = _pillFixedWidth + scaler.scale(_pillLabelWidth);
    return pill < NeumorphicIconButton.labelMaxWidth
        ? pill
        : NeumorphicIconButton.labelMaxWidth;
  }

  /// Phase 383 (LOW layout) — the readable minimum a labelled back pill must
  /// leave the title: about [_kMinTitleGlyphs] glyphs of [VelvetText.pageTitle]
  /// (or the whole title, when it is shorter), each estimated at
  /// [_kGlyphEms] em and scaled by [scaler]. An estimate, not a layout pass —
  /// it is consulted only by labelled bars, never by the plain chevron.
  static double minTitleRoomFor(String title, TextScaler scaler) {
    final int glyphs = title.characters.length < _kMinTitleGlyphs
        ? title.characters.length
        : _kMinTitleGlyphs;
    final double fontSize = VelvetText.pageTitle.fontSize ?? _kTitleFontSize;
    return scaler.scale(glyphs * _kGlyphEms * fontSize);
  }

  /// Whether a labelled back pill may keep its visible label: `true` when
  /// [titleRoom] (the width left to the title WITH the pill labelled) still
  /// reaches [minTitleRoomFor]. `false` → the host collapses the pill to the
  /// icon-only chevron — same key, same [backSemanticLabel], same 48 dp target
  /// — so a narrow screen / large text scale never squeezes the title down to
  /// a glyph or two.
  static bool labelledBackFits({
    required double titleRoom,
    required String title,
    required TextScaler scaler,
  }) => titleRoom >= minTitleRoomFor(title, scaler);

  static const int _kMinTitleGlyphs = 8;
  static const double _kGlyphEms = 0.6;
  static const double _kTitleFontSize = 14;

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

  /// Phase 383 — the symmetric title inset of a labelled bar COLLAPSED to
  /// the icon-only chevron: the chevron's 48 dp slot plus the
  /// [VelvetSpacing.sm] gap — or, when a [trailing] widget is present, the
  /// 1.0× [labelledTitleInset] the labelled bar was validated against (it
  /// clears the widest trailing in use, the bell + `tune_rounded` pair, whose
  /// icons do not text-scale), so a collapsed title never runs under either
  /// side. Text-scale independent.
  double get _collapsedTitleInset => trailing == null
      ? NeumorphicIconButton.extent + VelvetSpacing.sm
      : labelledTitleInset;

  @override
  Widget build(BuildContext context) {
    // The inset applies only when the labelled pill actually renders.
    final bool labelledBack = backLabel != null && onBack != null;
    final Widget bar = labelledBack
        // Phase 383 — only a labelled bar measures: it collapses to the plain
        // chevron when the title would be left below its readable minimum.
        ? LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final TextScaler scaler = MediaQuery.textScalerOf(context);
              final bool fits = labelledBackFits(
                titleRoom:
                    constraints.maxWidth - 2 * labelledTitleInsetFor(scaler),
                title: title,
                scaler: scaler,
              );
              return _bar(
                showLabel: fits,
                titleInset: fits
                    ? labelledTitleInsetFor(scaler)
                    : _collapsedTitleInset,
              );
            },
          )
        : _bar(showLabel: false, titleInset: null);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        VelvetSpacing.lg,
        VelvetSpacing.md,
        VelvetSpacing.lg,
        VelvetSpacing.xs,
      ),
      child: SizedBox(height: 48, child: bar),
    );
  }

  /// The bar's content. [titleInset] `null` is the byte-identical pre-24.1a
  /// tree (plain centred title) every unlabelled bar renders; non-null insets
  /// the title symmetrically and clamps it to one ellipsised line.
  /// [showLabel] `false` renders the icon-only chevron — the unlabelled bar,
  /// or a labelled one collapsed for lack of title room (same key, same
  /// [backSemanticLabel], same 48 dp target).
  Widget _bar({required bool showLabel, required double? titleInset}) {
    return Stack(
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
              label: showLabel ? backLabel : null,
            ),
          ),
        titleWidget ??
            (titleInset == null
                ? Text(
                    title,
                    style: VelvetText.pageTitle,
                    textAlign: TextAlign.center,
                  )
                : Padding(
                    padding: EdgeInsets.symmetric(horizontal: titleInset),
                    child: Text(
                      title,
                      style: VelvetText.pageTitle,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )),
        if (trailing != null)
          Align(alignment: Alignment.centerRight, child: trailing),
      ],
    );
  }
}
