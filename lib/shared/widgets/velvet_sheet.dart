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

import 'package:beautica_mobile/core/navigation/single_flight.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';

/// Presents [builder] in a transparent-backed modal sheet, the way every
/// VelvetTouch option sheet is shown (the chrome supplies the surface).
///
/// [isScrollControlled] (ADDITIVE, phase 424) — a sheet holding a text field
/// (the report sheet) passes `true` so it can rise above the keyboard. The
/// default `false` keeps every existing sheet unchanged.
Future<T?> showVelvetSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isScrollControlled = false,
}) {
  return showModalBottomSheetOnce<T>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: isScrollControlled,
    builder: builder,
  );
}

/// Base-colour rounded-top sheet surface: drag handle, [title], then
/// [children] separated by `VelvetSpacing.sm`.
///
/// The handle, title and subtitle form a FIXED header; only [children] scroll
/// (fix, review-trust branch). Previously the whole column sat in one
/// [SingleChildScrollView], so once a tall sheet (the report sheet) overflowed,
/// the scroll view won every vertical drag and the modal sheet's
/// drag-to-dismiss never fired. The padding is split between header and body
/// so a sheet whose content fits renders pixel-identically to before
/// (`test/golden/{sort_options,image_source,report}_sheet_golden_test.dart`).
class VelvetSheetChrome extends StatelessWidget {
  const VelvetSheetChrome({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.dismissOnOverscroll = false,
  });

  final String title;
  final List<Widget> children;

  /// Key on the drag-handle pill (tests drag the sheet down by it).
  static const Key handleKey = Key('velvet-sheet-handle');

  /// ADDITIVE (phase 424): one muted context line under [title] (e.g. «Відгук
  /// від Олена К.»). `null` (the default) renders exactly as before.
  final String? subtitle;

  /// ADDITIVE: when `true`, a user drag that overscrolls the body DOWNWARD at
  /// its top by more than 48 px pops the sheet's route (`maybePop`, so a
  /// blocking `PopScope` wins) — an overflowing sheet can still be dismissed
  /// by pulling its content down, not only by its header. Nested scrollables
  /// (a multi-line text field) never trigger it. `false` (the default) leaves
  /// every existing sheet unchanged.
  final bool dismissOnOverscroll;

  static const BorderRadius _sheetRadius = BorderRadius.vertical(
    top: Radius.circular(VelvetRadii.card),
  );

  @override
  Widget build(BuildContext context) {
    final String? sub = subtitle;
    final Widget body = SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        VelvetSpacing.lg,
        0,
        VelvetSpacing.lg,
        VelvetSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int i = 0; i < children.length; i++) ...<Widget>[
            children[i],
            if (i != children.length - 1)
              const SizedBox(height: VelvetSpacing.sm),
          ],
        ],
      ),
    );
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: BrandColors.base,
        borderRadius: _sheetRadius,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Fixed header — never scrolls, so a drag on it always reaches the
            // modal sheet's drag-to-dismiss.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                VelvetSpacing.lg,
                VelvetSpacing.md,
                VelvetSpacing.lg,
                0,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // Drag handle.
                  Center(
                    child: Container(
                      key: handleKey,
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
                  if (sub != null) ...<Widget>[
                    const SizedBox(height: VelvetSpacing.xs),
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Text(sub, style: VelvetText.feedbackMutedSm),
                    ),
                  ],
                  const SizedBox(height: VelvetSpacing.md),
                ],
              ),
            ),
            Flexible(
              child: dismissOnOverscroll
                  ? _OverscrollDismiss(child: body)
                  : body,
            ),
          ],
        ),
      ),
    );
  }
}

/// Pops the enclosing route when the user pulls [child]'s OWN scrollable
/// down past its top by more than [_threshold] — the `dismissOnOverscroll`
/// behaviour of [VelvetSheetChrome].
///
/// * Only depth-0 notifications count: a nested scrollable (the report
///   sheet's 3-line comment field) overscrolling inside its own box must not
///   close the sheet and throw away the typed text.
/// * The pull accumulates across the drag and resets when the drag ends, so a
///   stray first pixel of overscroll never dismisses.
/// * A route that declines to pop (`PopScope(canPop: false)`, e.g. the report
///   sheet while submitting) is left alone.
class _OverscrollDismiss extends StatefulWidget {
  const _OverscrollDismiss({required this.child});

  final Widget child;

  /// How far (logical px) the body must be pulled past its top to dismiss.
  static const double _threshold = 48;

  @override
  State<_OverscrollDismiss> createState() => _OverscrollDismissState();
}

class _OverscrollDismissState extends State<_OverscrollDismiss> {
  double _pulled = 0;

  /// Covers clamping physics ([OverscrollNotification], Android) and bouncing
  /// physics (a [ScrollUpdateNotification] past `minScrollExtent`, iOS).
  bool _onScroll(ModalRoute<Object?>? route, ScrollNotification n) {
    if (n.depth != 0) return false;
    switch (n) {
      case ScrollStartNotification() || ScrollEndNotification():
        _pulled = 0;
        return false;
      case OverscrollNotification(:final double overscroll, :final dragDetails)
          when dragDetails != null && overscroll < 0:
        _pulled -= overscroll;
      case ScrollUpdateNotification(:final dragDetails, :final metrics)
          when dragDetails != null:
        _pulled = metrics.pixels < metrics.minScrollExtent
            ? metrics.minScrollExtent - metrics.pixels
            : 0;
      default:
        return false;
    }
    if (_pulled <= _OverscrollDismiss._threshold) return false;
    // `isCurrent` guards against a second notification in the same gesture
    // popping the route underneath; `doNotPop` honours a blocking PopScope.
    if (route != null &&
        route.isCurrent &&
        route.popDisposition != RoutePopDisposition.doNotPop) {
      _pulled = 0;
      route.navigator?.maybePop();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    // Read once here, not inside the callback (which would register the
    // dependency from a notification handler).
    final ModalRoute<Object?>? route = ModalRoute.of(context);
    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification n) => _onScroll(route, n),
      child: widget.child,
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
