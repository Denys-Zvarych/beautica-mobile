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
// N-card list). [homeGap] tunes the gap above the pinned footer.
//
// There is no page-level slot below the recap: the independent flow's old
// "Додати в календар" pill lived there, and the multi-service rework moved
// that export onto each appointment card (`BookingSummaryCards.trailingAction`)
// because the OS INSERT sheet takes one event per invocation. The slot went
// with it — do not reintroduce one without a real call site.
//
// GENERALIZATION (Phase 14.3 — «Деталі запису»): the scaffold gained three
// knobs so a REFERENCE view (opened any time, for any booking, including
// ones that went badly) can compose the exact same structural bones as the
// CELEBRATION screens, with the affect swapped out — see the Phase 14.3
// README's "celebration vs. reference" section for the full reasoning:
//   * [heroBuilder] — replaces the hard-coded [SuccessLottieBadge]. `null`
//     (both success screens, unchanged) renders the Lottie via the
//     scaffold's own `_lottieController`, exactly as before. When supplied,
//     the builder receives the SAME staggered-reveal `_controller` the
//     title/subline/recap use, so a caller-built hero (the detail page's
//     `BookingStatusMedallion`) can derive its own entrance sub-interval from
//     it — no Lottie is ever created in that case.
//   * [actions] — replaces the single hard-coded `onHome`/`homeButtonKey`
//     pinned button. Both success screens now build their own
//     [SuccessSecondaryButton] and pass it as the sole entry in this list
//     (byte-identical rendering — the widget itself is unchanged, only WHO
//     constructs it moved). An empty list (the detail page's NOT_COMPLETED
//     case) renders no pinned footer at all. N entries stack with `xs` gaps.
//   * [canPop] — both success screens leave this at the default `false`
//     (their existing `PopScope(canPop: false)` contract: the route was
//     `pushReplacement`d over a submitted form, so there is nothing sane to
//     pop back to). «Деталі запису» is PUSHED from a list and sets this
//     `true`.
//   * [leading] — a fourth, small addition beyond the three above: neither
//     success screen has ever needed a back affordance (their `canPop:
//     false` makes one meaningless), so there was no slot for it. «Деталі
//     запису» IS pushed and DOES pop, so it needs one — an un-animated
//     top-left affordance rendered before the (possibly staggered-in) hero,
//     exactly where the design's own detail scaffold places its back
//     button. `null` (both success screens) renders nothing, byte-identical
//     to before this addition.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';

import 'success_lottie_badge.dart';

/// The shared post-submit / reference-view scaffold. See the file header for
/// how [recapCards] / [homeGap] / [heroBuilder] / [actions] / [canPop] map
/// onto the three call sites (two success screens + the booking detail
/// screen).
class BookingSuccessScaffold extends StatefulWidget {
  const BookingSuccessScaffold({
    super.key,
    this.title,
    required this.subline,
    required this.recapCards,
    this.actions = const <Widget>[],
    this.homeGap = VelvetSpacing.md,
    this.heroBuilder,
    this.showHero = true,
    this.canPop = false,
    this.leading,
    this.headerTrailing,
  });

  /// Headline — "Записано!" for a celebration, the status label for a
  /// reference view. `null` renders no headline at all: the CONFIRMED and the
  /// CANCELLED/DECLINED detail states drop the big status title entirely (the
  /// subline alone carries the state).
  final String? title;

  /// Sub-line under the headline. `null` renders no subline at all — the
  /// detail page passes `null` for an ELAPSED CONFIRMED booking, whose
  /// reminder line ("we'll remind you the day before") is meaningless once
  /// the slot has passed and is dropped alongside its other read-only
  /// affordances.
  final String? subline;

  /// The confirmed-booking recap cards — one for the independent flow, N (one
  /// per master) for the salon flow, one for the detail page. Each is
  /// wrapped in the staggered reveal and separated by a `md` gap.
  final List<Widget> recapCards;

  /// The pinned footer's content, top-to-bottom, separated by `xs` gaps. An
  /// empty list (the default) renders no pinned footer at all — no reserved
  /// padding for a control that is not there.
  final List<Widget> actions;

  /// Gap between the scrolling recap and the pinned footer.
  final double homeGap;

  /// Builds the 80 dp hero slot from the scaffold's own staggered-reveal
  /// controller. `null` (both success screens) renders the celebratory
  /// [SuccessLottieBadge] via the scaffold's internal Lottie controller,
  /// unchanged from before this generalisation.
  final Widget Function(AnimationController revealController)? heroBuilder;

  /// Whether to render the hero slot at all. `true` (both success screens, and
  /// the COMPLETED / NOT_COMPLETED detail states) renders either the caller's
  /// [heroBuilder] or — when that is null — the celebratory Lottie. `false`
  /// (the CONFIRMED and CANCELLED/DECLINED detail states) renders no hero at
  /// all: no medallion, no Lottie, and no space reserved for one.
  final bool showHero;

  /// Whether hardware back / iOS edge-swipe may pop this screen. Defaults to
  /// `false` — the success screens' existing block-back contract.
  final bool canPop;

  /// An un-animated top-left affordance rendered above the hero — the
  /// detail page's back button. `null` (both success screens) renders
  /// nothing.
  final Widget? leading;

  /// An un-animated top-RIGHT affordance rendered in the SAME header row as
  /// [leading], pinned to the far edge opposite the back button — the detail
  /// page's «Додати в календар» icon (CONFIRMED-only). `null` (both success
  /// screens, and the detail page's non-CONFIRMED states) renders nothing and
  /// reserves no space. Requires nothing of [leading]: either, both, or
  /// neither may be present.
  final Widget? headerTrailing;

  @override
  State<BookingSuccessScaffold> createState() => _BookingSuccessScaffoldState();
}

class _BookingSuccessScaffoldState extends State<BookingSuccessScaffold>
    with TickerProviderStateMixin {
  // Drives the staggered fade/slide reveal of the headline, subline, recap,
  // hero (when caller-built) and pinned footer.
  late final AnimationController _controller;

  // Drives the Lottie success animation; its duration is set from the loaded
  // composition inside [SuccessLottieBadge]'s `onLoaded` (stretched to 1.4x).
  // Only allocated when [BookingSuccessScaffold.heroBuilder] is null — a
  // caller-built hero (the detail page's static medallion) never plays a
  // Lottie, so there is nothing for this controller to drive.
  AnimationController? _lottieController;

  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1350),
    );
    // Only allocate a Lottie controller when a Lottie will actually be built:
    // no caller hero AND the hero slot is shown. A hidden hero (the CONFIRMED /
    // CANCELLED / DECLINED detail states) never needs one.
    if (widget.heroBuilder == null && widget.showHero) {
      _lottieController = AnimationController(vsync: this);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Respect reduced-motion: jump straight to the resting state and hold the
    // Lottie (when present) on its final frame.
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _controller.value = 1;
      _lottieController?.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _lottieController?.dispose();
    super.dispose();
  }

  /// A fade + upward-slide reveal over a sub-interval of [_controller].
  ///
  /// PERF (mobile-perf P1): the fade is a [FadeTransition], NOT a raw [Opacity]
  /// rebuilt inside the [AnimatedBuilder]. `Opacity` is a plain widget, so the
  /// old shape re-ran the builder, re-inflated an `Opacity` element and pushed
  /// its opacity through the render tree on EVERY frame of the 1350 ms
  /// staggered entrance — once per recap card, each of which now also carries a
  /// bordered, shadowed pill. `FadeTransition`'s `RenderAnimatedOpacity`
  /// subscribes to the animation itself and answers a tick with `markNeedsPaint`
  /// alone: no element rebuild, no compositing-bits churn, the work stays in the
  /// layer tree.
  ///
  /// The upward slide stays on an [AnimatedBuilder]-driven [Transform.translate]
  /// deliberately — it is an ABSOLUTE 18 dp travel, and [SlideTransition]'s
  /// offset is a FRACTION of the child's own height. Cards, the headline and the
  /// one-line subline differ in height by an order of magnitude, so a fractional
  /// slide would give each element a different travel and visibly change an
  /// already-approved entrance. A translate-only `Transform` costs a
  /// `canvas.translate`, and the pre-built `child` is handed to the builder so
  /// nothing below it rebuilds.
  ///
  /// Timing, curve and travel are unchanged: the same
  /// `Interval(start, end, curve: Curves.easeOutCubic)`, the same 18 dp rise,
  /// and the same implicit 0..1 opacity clamp (`RenderAnimatedOpacity` clamps
  /// internally via `Color.getAlphaFromOpacity`, exactly as the explicit
  /// `.clamp(0.0, 1.0)` did).
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
    // PERF: isolate this animated subtree's repaints from its static siblings
    // (title, subline and every recap card share one Column; the pinned
    // `actions` footer is revealed through this same helper) — mirrors
    // NeumorphicButton.build()'s press-animation RepaintBoundary.
    return RepaintBoundary(
      child: FadeTransition(
        opacity: curved,
        child: AnimatedBuilder(
          animation: curved,
          builder: (BuildContext context, Widget? c) => Transform.translate(
            offset: Offset(0, (1 - curved.value) * 18),
            child: c,
          ),
          child: child,
        ),
      ),
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
    if (widget.recapCards.isNotEmpty) {
      // The original loop trailed a `md` gap after the last card too.
      children.add(const SizedBox(height: VelvetSpacing.md));
    }
    return children;
  }

  /// Stacks [BookingSuccessScaffold.actions] with `xs` gaps between them —
  /// the two-tier hierarchy `BookingDetailScreen`'s CONFIRMED footer needs
  /// («Перенести» primary + «Скасувати запис» secondary), and the single
  /// entry both success screens now supply.
  Widget _actionsColumn() {
    final List<Widget> actions = widget.actions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < actions.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: VelvetSpacing.xs),
          actions[i],
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final AnimationController? lottieController = _lottieController;
    return PopScope(
      canPop: widget.canPop,
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
                if (widget.leading != null ||
                    widget.headerTrailing != null) ...<Widget>[
                  // Back button pinned left, trailing affordance pinned right,
                  // sharing one row. The Spacer holds the trailing icon on the
                  // far edge whether or not `leading` is present, and keeps the
                  // back button at the left edge when `headerTrailing` is null
                  // (byte-identical to the old centre-left Align for the
                  // leading-only states).
                  Row(
                    children: <Widget>[
                      if (widget.leading != null) widget.leading!,
                      const Spacer(),
                      if (widget.headerTrailing != null) widget.headerTrailing!,
                    ],
                  ),
                  const SizedBox(height: VelvetSpacing.xs),
                ],
                if (widget.showHero) ...<Widget>[
                  Center(
                    child: widget.heroBuilder != null
                        ? widget.heroBuilder!(_controller)
                        : SuccessLottieBadge(controller: lottieController),
                  ),
                  const SizedBox(height: VelvetSpacing.xs),
                ],
                if (widget.title != null) ...<Widget>[
                  _reveal(
                    start: 0.45,
                    end: 0.7,
                    child: Text(
                      widget.title!,
                      textAlign: TextAlign.center,
                      style: VelvetText.headingLg,
                    ),
                  ),
                  const SizedBox(height: VelvetSpacing.xs + 2),
                ],
                if (widget.subline != null) ...<Widget>[
                  _reveal(
                    start: 0.52,
                    end: 0.78,
                    child: Text(
                      widget.subline!,
                      textAlign: TextAlign.center,
                      style: VelvetText.bookSuccessSubline,
                    ),
                  ),
                ],
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
                if (widget.actions.isNotEmpty) ...<Widget>[
                  SizedBox(height: widget.homeGap),
                  _reveal(start: 0.8, end: 1.0, child: _actionsColumn()),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One onward action — a raised base-tone neumorphic pill with camel text (no
/// gradient fill). Both success screens build exactly one of these and pass
/// it as their scaffold's sole [BookingSuccessScaffold.actions] entry
/// (unchanged rendering from before the actions-list generalisation — only
/// the construction site moved from the scaffold itself to its callers).
class SuccessSecondaryButton extends StatefulWidget {
  const SuccessSecondaryButton({
    super.key,
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
  State<SuccessSecondaryButton> createState() => _SuccessSecondaryButtonState();
}

class _SuccessSecondaryButtonState extends State<SuccessSecondaryButton> {
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
