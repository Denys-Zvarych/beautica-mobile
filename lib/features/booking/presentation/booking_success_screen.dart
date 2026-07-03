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
// DEVIATION — success animation: the approved preview plays
// `assets/lottie/success.json` (`Lottie.asset(..., repeat: false)`). That
// asset does NOT exist in `beautica-mobile` today — `assets/lottie/` only
// ships `splash_wordmark.json` (checked before writing this file; the
// preview app's README claim that "beautica-mobile already has ... the
// success Lottie asset bundled" does not hold for this repo). Rather than
// commit an unreviewed binary/JSON animation asset as part of this phase,
// this screen renders a graceful in-code fallback — [_SuccessCheckBadge], a
// scale+fade-in camel/mocha gradient circle with a check glyph, sized and
// positioned identically to the preview's Lottie slot (112 dp, centered,
// plays once, honours `MediaQuery.disableAnimations`). Swapping in the real
// Lottie asset later is a drop-in replacement of this one widget.
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
    with SingleTickerProviderStateMixin {
  // Drives the staggered fade/slide reveal of the headline, summary and
  // actions, plus the check badge's own scale+fade-in.
  late final AnimationController _controller;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1350),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Respect reduced-motion: jump straight to the resting state.
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
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
                Center(child: _SuccessCheckBadge(controller: _controller)),
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
// Success check badge (Lottie fallback — see file header DEVIATION note)
// ---------------------------------------------------------------------------

/// A camel/mocha gradient circle with a check glyph, scaling + fading in once
/// over the first third of [controller]. Occupies the exact 112 dp slot the
/// approved design reserves for the Lottie success animation.
class _SuccessCheckBadge extends StatelessWidget {
  const _SuccessCheckBadge({required this.controller});

  final AnimationController controller;

  static const double _size = 112;

  @override
  Widget build(BuildContext context) {
    final Animation<double> curved = CurvedAnimation(
      parent: controller,
      curve: const Interval(0.0, 0.45, curve: Curves.elasticOut),
    );
    return Semantics(
      label: '',
      excludeSemantics: true,
      child: AnimatedBuilder(
        animation: curved,
        builder: (BuildContext context, Widget? child) => Opacity(
          opacity: curved.value.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: curved.value.clamp(0.0, 1.0),
            child: child,
          ),
        ),
        child: Container(
          height: _size,
          width: _size,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[BrandColors.accentLatte, BrandColors.accentDeep],
            ),
            boxShadow: VelvetShadows.extrudedButtonAccent,
          ),
          child: const Icon(
            Icons.check_rounded,
            color: BrandColors.white,
            size: _size * 0.5,
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
