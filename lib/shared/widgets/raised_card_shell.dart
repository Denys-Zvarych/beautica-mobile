// The raised taupe list-card pillow — radius 24, § 9 `extrudedCard` shadows,
// per-caller padding, press-depress when tappable.
//
// PROMOTED (REUSE-FIRST, phase 426) from the file-private `_FavoriteShell` in
// `features/favorites/presentation/widgets/favorite_cards.dart`. The
// «Заблоковані клієнти» card (approved UgcSafety preview) is «the
// «Улюблені» card body», so it takes this shell rather than a copy of it.
// The favourites cards pass exactly what they passed before and render
// identically (golden-verified: `test/golden/favorite_cards_golden_test.dart`).
//
// The one addition: [onTap] may be `null` — a STATIC card (no press scale, no
// button semantics), which is what a blocked entry is: its only action is the
// trailing «Розблокувати», never the card itself.
//
// NOT [NeumorphicCard]: that widget is a static raised surface with a fixed
// `lg` padding and no press state, and giving it one would change every
// surface in the app that already uses it.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';

/// Raised taupe pillow that depresses on tap (when [onTap] is set).
class RaisedCardShell extends StatefulWidget {
  const RaisedCardShell({
    super.key,
    this.semanticLabel,
    required this.onTap,
    required this.padding,
    required this.child,
  });

  /// The card's composed spoken label. Only meaningful on a tappable card.
  final String? semanticLabel;

  /// `null` → a static card: no gesture, no press state, no button role.
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final Widget child;

  @override
  State<RaisedCardShell> createState() => _RaisedCardShellState();
}

class _RaisedCardShellState extends State<RaisedCardShell> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final VoidCallback? onTap = widget.onTap;
    final Widget surface = AnimatedScale(
      scale: _pressed ? 0.985 : 1,
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOut,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: widget.padding,
        decoration: BoxDecoration(
          color: BrandColors.base,
          borderRadius: BorderRadius.circular(VelvetRadii.card),
          boxShadow: _pressed ? null : VelvetShadows.extrudedCard,
        ),
        child: widget.child,
      ),
    );
    if (onTap == null) return RepaintBoundary(child: surface);
    return RepaintBoundary(
      child: Semantics(
        button: true,
        label: widget.semanticLabel,
        child: GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) {
            setState(() => _pressed = false);
            onTap();
          },
          child: surface,
        ),
      ),
    );
  }
}
