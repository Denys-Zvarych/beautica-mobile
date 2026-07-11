// Shared booking-success screen scaffold.
//
// Lifts the byte-identical celebration structure out of BOTH
// `booking_success_screen.dart` (independent-master flow) and
// `salon_booking_success_screen.dart` (salon flow): the `PopScope(canPop:
// false)` + `Scaffold` + `SafeArea` + `Column` with the animated
// [SuccessLottieBadge], the staggered title/subline reveal, the scrolling
// recap of [recapCards], and the pinned "На головну" secondary button.
//
// Owns BOTH animation controllers (the 1350 ms staggered-reveal driver + the
// Lottie controller), the `_reveal` recipe, and the
// `MediaQuery.disableAnimations` jump-to-end — so the two success screens
// become thin, declarative call sites that just pass their copy + recap cards.
//
// Each entry in [recapCards] is wrapped by the scaffold in the SAME
// `_reveal(0.6, 0.86)` interval and separated by a `md` gap (the salon flow's
// N-card list). [belowRecap] is an optional extra scroll widget revealed a
// touch later (`_reveal(0.66, 0.9)`) — the independent flow's "Додати в
// календар" link, which the salon flow has no analogue for. [homeGap] tunes
// the gap above the pinned button (the only spacing the two originals differ
// on: `md` independent, `sm` salon).

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

import 'success_lottie_badge.dart';

/// The shared post-submit celebration scaffold. See the file header for how
/// [recapCards] / [belowRecap] / [homeGap] map onto the two flows.
class BookingSuccessScaffold extends StatefulWidget {
  const BookingSuccessScaffold({
    super.key,
    required this.title,
    required this.subline,
    required this.recapCards,
    required this.onHome,
    required this.homeButtonKey,
    this.belowRecap,
    this.homeGap = VelvetSpacing.md,
  });

  /// Celebration headline — "Записано!" (both flows use their own l10n key).
  final String title;

  /// Reassuring sub-line under the headline.
  final String subline;

  /// The confirmed-booking recap cards — one for the independent flow, N (one
  /// per master) for the salon flow. Each is wrapped in the staggered reveal
  /// and separated by a `md` gap.
  final List<Widget> recapCards;

  /// Fires when the pinned "На головну" button is tapped.
  final VoidCallback onHome;

  /// Key for the pinned button's tappable — distinct per flow
  /// (`booking-success-home-cta` / `salon-success-home-cta`).
  final Key homeButtonKey;

  /// Optional extra scroll content revealed just after the recap (the
  /// independent flow's calendar link). `null` for the salon flow.
  final Widget? belowRecap;

  /// Gap between the scrolling recap and the pinned button.
  final double homeGap;

  @override
  State<BookingSuccessScaffold> createState() => _BookingSuccessScaffoldState();
}

class _BookingSuccessScaffoldState extends State<BookingSuccessScaffold>
    with TickerProviderStateMixin {
  // Drives the staggered fade/slide reveal of the headline, subline, recap and
  // pinned button.
  late final AnimationController _controller;

  // Drives the Lottie success animation; its duration is set from the loaded
  // composition inside [SuccessLottieBadge]'s `onLoaded` (stretched to 1.4x).
  late final AnimationController _lottieController;

  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1350),
    );
    _lottieController = AnimationController(vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Respect reduced-motion: jump straight to the resting state and hold the
    // Lottie on its final frame.
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _controller.value = 1;
      _lottieController.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _lottieController.dispose();
    super.dispose();
  }

  /// A fade + upward-slide reveal over a sub-interval of [_controller].
  Widget _reveal({
    required double start,
    required double end,
    required Widget child,
  }) {
    // Drive a stateless CurveTween off the controller instead of allocating a
    // CurvedAnimation: a CurveTween is an Animatable, not a Listenable, so it
    // registers no status listener on _controller and needs no disposal — this
    // `build()` runs each frame across N recap cards.
    final Animation<double> curved = _controller.drive(
      CurveTween(curve: Interval(start, end, curve: Curves.easeOutCubic)),
    );
    return AnimatedBuilder(
      animation: curved,
      builder: (BuildContext context, Widget? c) => Opacity(
        opacity: curved.value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, (1 - curved.value) * 18),
          child: c,
        ),
      ),
      child: child,
    );
  }

  List<Widget> _recapContent() {
    final List<Widget> children = <Widget>[];
    for (int i = 0; i < widget.recapCards.length; i++) {
      children.add(_reveal(start: 0.6, end: 0.86, child: widget.recapCards[i]));
      final bool isLast = i == widget.recapCards.length - 1;
      if (!isLast) {
        children.add(const SizedBox(height: VelvetSpacing.md));
      }
    }
    if (widget.belowRecap != null) {
      children.add(const SizedBox(height: VelvetSpacing.sm + 2));
      children.add(_reveal(start: 0.66, end: 0.9, child: widget.belowRecap!));
    } else if (widget.recapCards.isNotEmpty) {
      // Salon flow: the original loop trailed a `md` gap after the last card
      // too.
      children.add(const SizedBox(height: VelvetSpacing.md));
    }
    return children;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: BrandColors.base,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              VelvetSpacing.lg,
              VelvetSpacing.lg,
              VelvetSpacing.lg,
              VelvetSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Center(
                  child: SuccessLottieBadge(controller: _lottieController),
                ),
                const SizedBox(height: VelvetSpacing.xs),
                _reveal(
                  start: 0.45,
                  end: 0.7,
                  child: Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    style: VelvetText.headingLg,
                  ),
                ),
                const SizedBox(height: VelvetSpacing.xs + 2),
                _reveal(
                  start: 0.52,
                  end: 0.78,
                  child: Text(
                    widget.subline,
                    textAlign: TextAlign.center,
                    style: VelvetText.bookSuccessSubline,
                  ),
                ),
                const SizedBox(height: VelvetSpacing.lg),
                Flexible(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: _recapContent(),
                    ),
                  ),
                ),
                SizedBox(height: widget.homeGap),
                _reveal(
                  start: 0.8,
                  end: 1.0,
                  child: _SecondaryButton(
                    buttonKey: widget.homeButtonKey,
                    label: l10n.bookingSuccessHomeCta,
                    icon: Icons.home_outlined,
                    onPressed: widget.onHome,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The sole onward action — a raised base-tone neumorphic pill with camel text
/// (no gradient fill). Shared verbatim between both success screens.
class _SecondaryButton extends StatefulWidget {
  const _SecondaryButton({
    required this.buttonKey,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final Key buttonKey;
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  State<_SecondaryButton> createState() => _SecondaryButtonState();
}

class _SecondaryButtonState extends State<_SecondaryButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        key: widget.buttonKey,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onPressed();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: VelvetSizes.cta,
          decoration: BoxDecoration(
            color: BrandColors.base,
            borderRadius: BorderRadius.circular(VelvetRadii.button),
            boxShadow: _pressed ? null : VelvetShadows.extrudedButton,
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(widget.icon, size: 20, color: BrandColors.accentDeep),
              const SizedBox(width: VelvetSpacing.sm),
              Text(
                widget.label,
                style: VelvetText.cta().copyWith(color: BrandColors.accentDeep),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
