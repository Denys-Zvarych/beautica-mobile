// Shared VelvetTouch modal-bottom-sheet pieces.
//
// PROMOTED (REUSE-FIRST, Phase 071) out of
// `features/discovery/presentation/widgets/sort_options_sheet.dart`, where the
// chrome and option row were inline / private. The image-source sheet needs the
// identical look, and a second copy would drift. The bodies below are the
// ORIGINALS moved verbatim; the only additions are optional, defaulted
// parameters (`leading`, `labelStyle`, `semanticsLabel`, `tapKey`) that the sort
// sheet leaves unset, so it renders byte-identically
// (`test/golden/sort_options_sheet_golden_test.dart`, seeded pre-promotion).

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';

/// Presents [builder] in a transparent-backed modal sheet, the way every
/// VelvetTouch option sheet is shown (the chrome supplies the surface).
Future<T?> showVelvetSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: false,
    builder: builder,
  );
}

/// Base-colour rounded-top sheet surface: drag handle, [title], then
/// [children] separated by `VelvetSpacing.sm`.
class VelvetSheetChrome extends StatelessWidget {
  const VelvetSheetChrome({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  static const BorderRadius _sheetRadius = BorderRadius.vertical(
    top: Radius.circular(VelvetRadii.card),
  );

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: BrandColors.base,
        borderRadius: _sheetRadius,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            VelvetSpacing.lg,
            VelvetSpacing.md,
            VelvetSpacing.lg,
            VelvetSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Drag handle.
              Center(
                child: Container(
                  height: 4,
                  width: 44,
                  decoration: BoxDecoration(
                    color: BrandColors.faint,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: VelvetSpacing.md),
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Text(title, style: VelvetText.subheading()),
              ),
              const SizedBox(height: VelvetSpacing.md),
              for (int i = 0; i < children.length; i++) ...<Widget>[
                children[i],
                if (i != children.length - 1)
                  const SizedBox(height: VelvetSpacing.sm),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One tappable sheet row. Selected → pressed inset well + camel check;
/// unselected → flat extruded chip on the base surface.
class VelvetSheetOptionRow extends StatelessWidget {
  const VelvetSheetOptionRow({
    super.key,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.semanticsLabel,
    this.tapKey,
    this.leading,
    this.labelStyle,
  });

  final String label;
  final VoidCallback onTap;
  final bool selected;

  /// Screen-reader label; defaults to [label].
  final String? semanticsLabel;

  /// Key placed on the tappable [GestureDetector] (what tests tap by).
  final Key? tapKey;

  /// Optional glyph before the label (e.g. an action icon).
  final Widget? leading;

  /// Overrides the default option label style (e.g. a destructive colour).
  final TextStyle? labelStyle;

  static const BorderRadius _radius = BorderRadius.all(
    Radius.circular(VelvetRadii.field),
  );

  static final TextStyle _labelStyle = VelvetText.discSortOption;

  @override
  Widget build(BuildContext context) {
    final Widget row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: VelvetSpacing.md,
        vertical: VelvetSpacing.md,
      ),
      child: Row(
        children: <Widget>[
          if (leading != null) ...<Widget>[
            leading!,
            const SizedBox(width: VelvetSpacing.md),
          ],
          Expanded(child: Text(label, style: labelStyle ?? _labelStyle)),
          if (selected)
            const Icon(
              Icons.check_rounded,
              color: BrandColors.accent,
              size: 22,
            ),
        ],
      ),
    );

    return Semantics(
      button: true,
      selected: selected,
      label: semanticsLabel ?? label,
      excludeSemantics: leading != null,
      child: GestureDetector(
        key: tapKey,
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: selected
            ? NeumorphicInset(radius: VelvetRadii.field, child: row)
            : DecoratedBox(
                decoration: const BoxDecoration(
                  color: BrandColors.base,
                  borderRadius: _radius,
                  boxShadow: VelvetShadows.extrudedSmall,
                ),
                child: row,
              ),
      ),
    );
  }
}
