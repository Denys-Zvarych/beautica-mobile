// Phase 14.2 — BookingSuccessScreen: booking flow Step 3b, the emotional
// payoff shown after `POST /bookings` succeeds.
//
// DESIGN SOURCE: `docs/signup-designs/BookingConfirmSuccess/lib/screens/
// booking_success_screen.dart` (approved 2026-06-30) — transcribed literally:
// an animated check medallion → "Записано!" headline → reassuring subline →
// the SAME `BookingSummaryCards` recap the confirm screen showed (WITHOUT the
// master card, `dense: true`) → a calm "Додати в календар" link → two pinned
// onward actions ("Мої записи" / "На головну").
//
// SUCCESS ANIMATION: plays the approved preview's real
// `assets/lottie/success.json` (`Lottie.asset(..., repeat: false)`), copied
// in from `docs/signup-designs/BookingConfirmSuccess/assets/lottie/` — the
// asset this screen originally shipped without (see git history for the
// prior in-code `_SuccessCheckBadge` gradient-circle fallback it replaced).
// Rendered at 80 dp — smaller than the preview's 112 dp slot (not a
// straight half), a deliberate deviation from the approved design at the
// user's explicit request — with
// its own [_lottieController] (duration set from the loaded composition,
// `forward(from: 0)` once), independent of [_controller] below (which still
// drives the headline/subline/summary/CTA staggered reveal exactly as
// before). Honours `MediaQuery.disableAnimations` by jumping the Lottie
// controller straight to its last frame instead of playing it, mirroring
// how [_controller] itself is pinned to `1` under reduced motion.
//
// DEVIATION — "Додати в календар": the preview's production notes call for
// `add_2_calendar`/ICS wiring. That package is not in `pubspec.yaml` (checked
// before writing this file) and pulling in a new, unreviewed third-party
// dependency is out of scope for this pass — the link is fully rendered and
// tappable but its action is a documented `// TODO` no-op (see
// `_CalendarLink`).
//
// NAVIGATION: `RouteNames.clientBookings` ("/bookings") and
// `RouteNames.clientHome` ("/home") are both ALREADY registered routes (the
// CLIENT shell's «Записи» / «Головна» branches — «Записи» currently renders
// `ClientBookingsPlaceholderScreen` until Phase 14.3 ships the real My
// Bookings screen, but the route itself is real and CLIENT-gated) — no
// TODO/no-op needed for either button.
//
// NO BACK AFFORDANCE: wrapped in `PopScope(canPop: false)` so hardware
// back / iOS edge-swipe is fully blocked on this screen — the two pinned
// buttons are the only ways forward. Combined with `BookingConfirmScreen`'s
// `pushReplacement` (which REMOVES `/booking/confirm` from the nav stack
// rather than pushing on top of it), there is no in-app path back to confirm
// from here at all; see `app_router.dart`'s `bookingSuccess` route comment
// for why no additional `redirect` guard is layered on top of these two.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';

import '../domain/booking_success_args.dart';
import 'widgets/booking_summary_cards.dart';

/// Booking flow Step 3b — the post-submit celebration screen.
class BookingSuccessScreen extends StatefulWidget {
  const BookingSuccessScreen({super.key, required this.args});

  final BookingSuccessArgs args;

  @override
  State<BookingSuccessScreen> createState() => _BookingSuccessScreenState();
}

class _BookingSuccessScreenState extends State<BookingSuccessScreen>
    with TickerProviderStateMixin {
  // Drives the staggered fade/slide reveal of the headline, summary and
  // actions.
  late final AnimationController _controller;

  // Drives the Lottie success animation; its duration is set from the
  // loaded composition in `Lottie.asset`'s `onLoaded` callback, mirroring
  // the approved preview's own wiring
  // (`docs/signup-designs/BookingConfirmSuccess/lib/screens/
  // booking_success_screen.dart`) — independent of [_controller] above, so
  // the badge always plays its full designed animation regardless of how
  // the rest of the screen's staggered reveal is timed.
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
    // Respect reduced-motion: jump straight to the resting state and hold
    // the Lottie on its final frame (mirrors the preview's own guard).
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
    final Animation<double> curved = CurvedAnimation(
      parent: _controller,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
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
                  child: _SuccessLottieBadge(controller: _lottieController),
                ),
                const SizedBox(height: VelvetSpacing.xs),
                _reveal(
                  start: 0.45,
                  end: 0.7,
                  child: Text(
                    l10n.bookingSuccessTitle,
                    textAlign: TextAlign.center,
                    style: VelvetText.heading().copyWith(fontSize: 26),
                  ),
                ),
                const SizedBox(height: VelvetSpacing.xs + 2),
                _reveal(
                  start: 0.52,
                  end: 0.78,
                  child: Text(
                    l10n.bookingSuccessSubline,
                    textAlign: TextAlign.center,
                    style: VelvetText.body().copyWith(height: 1.35),
                  ),
                ),
                const SizedBox(height: VelvetSpacing.lg),
                Flexible(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _reveal(
                          start: 0.6,
                          end: 0.86,
                          child: BookingSummaryCards(
                            master: widget.args.master,
                            service: widget.args.service,
                            start: widget.args.start,
                            showMasterCard: false,
                            dense: true,
                          ),
                        ),
                        const SizedBox(height: VelvetSpacing.sm + 2),
                        _reveal(
                          start: 0.66,
                          end: 0.9,
                          child: const _CalendarLink(),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: VelvetSpacing.md),
                _reveal(
                  start: 0.72,
                  end: 0.95,
                  child: NeumorphicButton(
                    key: const Key('booking-success-my-bookings-cta'),
                    label: l10n.bookingSuccessMyBookingsCta,
                    icon: Icons.event_note_rounded,
                    onPressed: () => context.go(RouteNames.clientBookings),
                  ),
                ),
                const SizedBox(height: VelvetSpacing.sm),
                _reveal(
                  start: 0.8,
                  end: 1.0,
                  child: _SecondaryButton(
                    label: l10n.bookingSuccessHomeCta,
                    icon: Icons.home_outlined,
                    onPressed: () => context.go(RouteNames.clientHome),
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

// ---------------------------------------------------------------------------
// Success Lottie badge
// ---------------------------------------------------------------------------

/// The real designed success animation (`assets/lottie/success.json`),
/// rendered at 80 dp — smaller than the approved preview's 112 dp slot (not
/// a straight half), per explicit request. Plays once, driven by
/// [controller] (see the state class'
/// `_lottieController` doc for the wiring rationale); excluded from the
/// semantics tree since it is purely decorative — the "Записано!" headline
/// right below it already conveys the success state to screen readers.
class _SuccessLottieBadge extends StatelessWidget {
  const _SuccessLottieBadge({required this.controller});

  final AnimationController controller;

  static const double _size = 80;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '',
      excludeSemantics: true,
      child: SizedBox(
        width: _size,
        height: _size,
        child: Lottie.asset(
          'assets/lottie/success.json',
          controller: controller,
          repeat: false,
          fit: BoxFit.contain,
          // PERF: the composition decodes asynchronously; without this the
          // 80 dp slot renders blank for a frame or two before `onLoaded`
          // fires. Swap in a static version of the same circular badge so
          // there's never a blank box, then hand off to the real animation
          // the instant the composition is ready.
          frameBuilder:
              (
                BuildContext context,
                Widget child,
                LottieComposition? composition,
              ) {
                if (composition == null) {
                  return const _SuccessBadgePlaceholder(size: _size);
                }
                return child;
              },
          onLoaded: (LottieComposition composition) {
            controller.duration = composition.duration;
            // Reduced-motion already pinned the controller to the last
            // frame in `didChangeDependencies`; only play otherwise.
            if (!(MediaQuery.maybeOf(context)?.disableAnimations ?? false)) {
              controller.forward(from: 0);
            }
          },
        ),
      ),
    );
  }
}

/// Static stand-in for [_SuccessLottieBadge] shown for the brief window
/// before the Lottie composition finishes its async decode. A plain filled
/// circle with a check glyph — same 80 dp footprint and the same success
/// colour the finished animation lands on, so the swap to the real
/// animation is not a visible jump.
class _SuccessBadgePlaceholder extends StatelessWidget {
  const _SuccessBadgePlaceholder({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: BrandColors.success,
        shape: BoxShape.circle,
      ),
      child: SizedBox(
        width: size,
        height: size,
        child: Center(
          child: Icon(
            Icons.check_rounded,
            color: BrandColors.white,
            size: size * 0.55,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Calendar link (no-op — see file header DEVIATION note)
// ---------------------------------------------------------------------------

/// The tertiary onward action — a calm, borderless "Додати в календар" text
/// link. See file header: real OS-calendar wiring is deferred (no
/// `add_2_calendar` dependency added in this pass).
class _CalendarLink extends StatefulWidget {
  const _CalendarLink();

  @override
  State<_CalendarLink> createState() => _CalendarLinkState();
}

class _CalendarLinkState extends State<_CalendarLink> {
  bool _pressed = false;

  void _onTap() {
    // TODO(phase-14.x): wire a real OS calendar event (title = service name,
    // location = master address, window = booked start→end) via
    // `add_2_calendar` or an ICS export once that dependency is reviewed and
    // added to pubspec.yaml. Intentionally a no-op for this pass — see the
    // file header DEVIATION note.
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: l10n.bookingAddCalendarSemantics,
      child: GestureDetector(
        key: const Key('booking-success-add-calendar'),
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) {
          setState(() => _pressed = false);
          _onTap();
        },
        behavior: HitTestBehavior.opaque,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 120),
          opacity: _pressed ? 0.55 : 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: VelvetSpacing.sm),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.calendar_today_rounded,
                  size: 18,
                  color: BrandColors.accentDeep,
                ),
                const SizedBox(width: VelvetSpacing.sm),
                Text(
                  l10n.bookingSuccessAddCalendarCta,
                  style: VelvetText.bodyStrong().copyWith(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: BrandColors.accentDeep,
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

// ---------------------------------------------------------------------------
// Secondary button ("На головну")
// ---------------------------------------------------------------------------

/// The secondary onward action — a raised base-tone neumorphic pill with
/// camel text (no gradient fill), the quieter sibling of the primary "Мої
/// записи" CTA above it.
class _SecondaryButton extends StatefulWidget {
  const _SecondaryButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

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
        key: const Key('booking-success-home-cta'),
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
