// Phase 14.18 — SalonBookingSuccessScreen: salon booking flow step 4b, the
// post-submit celebration. Mirrors the independent-master
// `BookingSuccessScreen` (`booking_success_screen.dart`) — animated success
// badge → "Записано!" headline → reassuring subline → the booking recap →
// a single pinned "На головну" — extended to LIST every created appointment
// (one `SalonAppointmentCard` per master) instead of a single recap.
//
// Reached ONLY via `SalonBookingConfirmScreen`'s `pushReplacement` once EVERY
// appointment's `POST /bookings` succeeded (partial failures keep the client
// on the confirm screen), so the recap here is always the full, confirmed
// set. Wrapped in `PopScope(canPop: false)` like the independent success
// screen — the pinned "На головну" is the only way forward.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';

import '../domain/salon_booking_confirm_args.dart';
import 'widgets/salon_appointment_card.dart';
import 'widgets/salon_avatar_gradients.dart';

/// Salon booking flow step 4b — the confirmed N-appointment recap.
class SalonBookingSuccessScreen extends StatefulWidget {
  const SalonBookingSuccessScreen({super.key, required this.args});

  final SalonBookingSuccessArgs args;

  @override
  State<SalonBookingSuccessScreen> createState() =>
      _SalonBookingSuccessScreenState();
}

class _SalonBookingSuccessScreenState extends State<SalonBookingSuccessScreen>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
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

  /// A fade + upward-slide reveal over a sub-interval of [_controller] —
  /// same recipe as `BookingSuccessScreen._reveal`.
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
    final List<SalonBookingAppointment> appointments = widget.args.appointments;
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
                    l10n.salonBookingSuccessTitle,
                    textAlign: TextAlign.center,
                    style: VelvetText.headingLg,
                  ),
                ),
                const SizedBox(height: VelvetSpacing.xs + 2),
                _reveal(
                  start: 0.52,
                  end: 0.78,
                  child: Text(
                    l10n.salonBookingSuccessSubline,
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
                      children: <Widget>[
                        for (
                          int i = 0;
                          i < appointments.length;
                          i++
                        ) ...<Widget>[
                          _reveal(
                            start: 0.6,
                            end: 0.86,
                            child: SalonAppointmentCard(
                              key: ValueKey<String>(
                                'salon-success-appt-'
                                '${appointments[i].schedule.masterId}',
                              ),
                              appointment: appointments[i],
                              avatarGradient: salonAvatarGradient(i),
                            ),
                          ),
                          const SizedBox(height: VelvetSpacing.md),
                        ],
                      ],
                    ),
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

/// The shared success animation, rendered at 80 dp — same asset + wiring as
/// `BookingSuccessScreen._SuccessLottieBadge`. Decorative (excluded from
/// semantics — the "Записано!" headline conveys the state).
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
            controller.duration = composition.duration * 1.4;
            if (!(MediaQuery.maybeOf(context)?.disableAnimations ?? false)) {
              controller.forward(from: 0);
            }
          },
        ),
      ),
    );
  }
}

/// Static stand-in shown for the brief window before the Lottie composition
/// finishes its async decode — same 80 dp footprint + success colour.
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

/// The sole onward action — a raised base-tone neumorphic pill with camel
/// text, matching `BookingSuccessScreen._SecondaryButton`.
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
        key: const Key('salon-success-home-cta'),
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
