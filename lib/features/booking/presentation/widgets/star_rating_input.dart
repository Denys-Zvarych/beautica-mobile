// Phase 14.6 — the leave-review screen's signature 5-star input.
//
// Ported from the approved preview
// `docs/signup-designs/MasterFeedbackScreen/lib/widgets/star_rating_input.dart`,
// mapped onto the project's tokens (`BrandColors` / `VelvetText` /
// `VelvetSpacing`) and l10n (the descriptive labels + prompt + semantics label
// are passed in by the screen from `AppLocalizations`, never hard-coded here).
//
// ## The one bold move
//
// Everything else on the screen stays quiet and tactile; this widget spends the
// page's single moment of personality. Tapping a star fires a **left-to-right
// scale-pop sweep** across every star up to the one chosen — each lights and
// springs in turn — and the descriptive word beneath crossfades to match. The
// sweep is one `AnimationController` restarted on each tap (cheap, disposed, and
// reduced-motion aware).

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';

/// Row of 5 tappable stars with a live descriptive readout.
///
/// [rating] (0 = unrated) is owned by the parent so the CTA can gate on it;
/// [onChanged] emits the tapped value (1–5). [labels] are the five descriptive
/// words (index 0 = the 1-star label … index 4 = the 5-star label), and
/// [prompt] is shown before any star is chosen — both localized by the caller.
class StarRatingInput extends StatefulWidget {
  const StarRatingInput({
    super.key,
    required this.rating,
    required this.onChanged,
    required this.labels,
    required this.prompt,
    required this.semanticsLabel,
  });

  /// Current rating, 0 = unrated. Owned by the parent so the CTA can gate on it.
  final int rating;

  /// Emits the tapped value, 1–5.
  final ValueChanged<int> onChanged;

  /// The five descriptive labels, ordered 1★ → 5★ (length 5).
  final List<String> labels;

  /// Prompt shown before any star is chosen.
  final String prompt;

  /// Accessibility label for the whole rating control.
  final String semanticsLabel;

  @override
  State<StarRatingInput> createState() => _StarRatingInputState();
}

class _StarRatingInputState extends State<StarRatingInput>
    with SingleTickerProviderStateMixin {
  static const int _count = 5;
  static const double _starBox = 52; // generous 52 dp tap target per star.

  // Hoisted display styles — computed once, never per build/frame.
  static final TextStyle _labelRatedStyle = VelvetText.feedbackRatingWord;
  static final TextStyle _labelPromptStyle = VelvetText.feedbackPrompt;

  late final AnimationController _sweep;

  /// One driven pop [Animation] per star, precomputed once. Each depends only on
  /// its (compile-time-constant) index, never on the animation value, so there
  /// is nothing to re-allocate per frame during the ~480 ms sweep — `build`
  /// merely reads `_pops[i]`. Filled stars pop on their own staggered slice
  /// (left → right); empty stars never move (they render at scale 1).
  late final List<Animation<double>> _pops;

  @override
  void initState() {
    super.initState();
    _sweep = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
      value: 1, // resting = no pop.
    );
    _pops = List<Animation<double>>.generate(_count, (int index) {
      final double start = (index / _count) * 0.5;
      return _sweep.drive(
        TweenSequence<double>(<TweenSequenceItem<double>>[
          TweenSequenceItem<double>(
            tween: Tween<double>(
              begin: 1,
              end: 1.32,
            ).chain(CurveTween(curve: Curves.easeOutBack)),
            weight: 45,
          ),
          TweenSequenceItem<double>(
            tween: Tween<double>(
              begin: 1.32,
              end: 1,
            ).chain(CurveTween(curve: Curves.easeOut)),
            weight: 55,
          ),
        ]).chain(CurveTween(curve: Interval(start, (start + 0.5).clamp(0, 1)))),
      );
    });
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  String _labelFor(int rating) => (rating >= 1 && rating <= _count)
      ? widget.labels[rating - 1]
      : widget.prompt;

  void _select(int value) {
    if (value == widget.rating) return;
    widget.onChanged(value);
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _sweep.value = 1;
    } else {
      _sweep.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final int rating = widget.rating;
    final bool rated = rating >= 1;

    return Column(
      children: <Widget>[
        Semantics(
          label: widget.semanticsLabel,
          value: rated ? '$rating / $_count' : null,
          // Row structure built once — only the leaf ScaleTransition around a
          // filled star's icon rebuilds per sweep frame.
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List<Widget>.generate(_count, (int i) {
              final bool filled = i < rating;
              final Icon icon = Icon(
                filled ? Icons.star_rounded : Icons.star_border_rounded,
                size: 40,
                color: filled ? BrandColors.accent : BrandColors.faint,
              );
              return GestureDetector(
                key: ValueKey<String>('review-star-${i + 1}'),
                behavior: HitTestBehavior.opaque,
                onTap: () => _select(i + 1),
                child: SizedBox(
                  width: _starBox,
                  height: _starBox,
                  child: Center(
                    child: filled
                        ? ScaleTransition(scale: _pops[i], child: icon)
                        : icon,
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: VelvetSpacing.sm),
        // Live emotional readout — the crossfading word.
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (Widget child, Animation<double> anim) {
            return FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.35),
                  end: Offset.zero,
                ).animate(anim),
                child: child,
              ),
            );
          },
          child: Text(
            _labelFor(rating),
            key: ValueKey<int>(rating),
            textAlign: TextAlign.center,
            style: rated ? _labelRatedStyle : _labelPromptStyle,
          ),
        ),
      ],
    );
  }
}
