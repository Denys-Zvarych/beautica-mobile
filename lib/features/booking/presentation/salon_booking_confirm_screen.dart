// Phase 14.18 — SalonBookingConfirmScreen: salon booking flow step 4 (final
// review + submit). Mirrors the independent-master `BookingConfirmScreen`
// (`booking_confirm_screen.dart`) structure — a flat read of the whole
// booking, an optional "Коментар для майстра" note, a pinned CTA — extended
// to the salon's N-master model: it lists ONE `SalonAppointmentCard` per
// assigned master and submits N `POST /bookings` calls via
// `SalonBookingSubmit`.
//
// PARTIAL FAILURE (the reason this screen can't just reuse `BookingConfirm`):
// each master's booking succeeds/fails independently. On «Записатись» every
// appointment is attempted; if ALL succeed the screen `pushReplacement`s to
// the salon success screen; if SOME fail the screen STAYS, each failed card
// shows its own error, a SnackBar nudges retry, and the CTA becomes
// «Повторити» — re-submitting ONLY the still-failed appointments (already-
// created bookings are never re-sent, and each reuses its stable idempotency
// key so an ambiguously-failed one de-duplicates). Success is never claimed
// while any appointment failed.
//
// DATA SOURCE: `SalonBookingConfirmArgs` carries the fully-resolved
// appointments forward from `SalonTimeScreen` (the step-3 picks live in an
// autoDispose provider that would be gone by the time this screen mounts) —
// no re-fetch.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';

import '../application/salon_booking_submit_notifier.dart';
import '../domain/salon_booking_confirm_args.dart';
import 'widgets/booking_comment_field.dart';
import 'widgets/booking_cta_footer.dart';
import 'widgets/booking_top_bar.dart';
import 'widgets/salon_appointment_card.dart';
import 'widgets/salon_avatar_gradients.dart';

/// Salon booking flow step 4 — review the N appointments and submit them.
class SalonBookingConfirmScreen extends ConsumerStatefulWidget {
  const SalonBookingConfirmScreen({super.key, required this.args});

  final SalonBookingConfirmArgs args;

  @override
  ConsumerState<SalonBookingConfirmScreen> createState() =>
      _SalonBookingConfirmScreenState();
}

class _SalonBookingConfirmScreenState
    extends ConsumerState<SalonBookingConfirmScreen> {
  static const int _maxComment = 500;

  final TextEditingController _comment = TextEditingController();

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  /// Blocks leaving the screen once at least one appointment has succeeded
  /// (see [SalonBookingSubmitState.hasSucceeded]) — the only safe way forward
  /// after a partial success is the «Повторити» retry, which reuses each
  /// still-failed appointment's stable idempotency key. Leaving here would
  /// return to `SalonTimeScreen` with live schedule state, where re-tapping
  /// «Підтвердити» would re-mint fresh keys for the already-created bookings.
  void _onBack(bool hasSucceeded) {
    if (hasSucceeded) {
      _showBackBlockedMessage();
      return;
    }
    context.pop();
  }

  void _showBackBlockedMessage() {
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.salonBookingBackBlockedMessage),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final SalonBookingSubmitState result = await ref
        .read(salonBookingSubmitProvider.notifier)
        .submit(widget.args.appointments, comment: _comment.text);
    if (!mounted) return;
    if (result.allSucceeded(widget.args.appointments)) {
      context.pushReplacement(
        RouteNames.salonBookingSuccess,
        extra: SalonBookingSuccessArgs(
          salonId: widget.args.salonId,
          appointments: widget.args.appointments,
        ),
      );
      return;
    }
    // Partial (or total) failure — stay put; each failed card already shows
    // its own error. A floating SnackBar nudges the retry the CTA now offers.
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.salonBookingPartialFailureMessage),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Screen-level watch is scoped to just the CTA/back-guard flags via
    // `select` — a record has value equality, so the whole card list is NOT
    // rebuilt on each of the N+2 per-master mutations a submit pass makes.
    // Each card watches its OWN (status, failure) through a scoped Consumer
    // below (mobile-perf LOW, Phase 14.18 salon-submit audit).
    final (bool inFlight, bool hasFailures, bool hasSucceeded) = ref.watch(
      salonBookingSubmitProvider.select(
        (SalonBookingSubmitState s) =>
            (s.inFlight, s.hasFailures, s.hasSucceeded),
      ),
    );
    final List<SalonBookingAppointment> appointments = widget.args.appointments;

    final String ctaLabel = inFlight
        ? l10n.bookingSubmitCtaLoading
        : (hasFailures ? l10n.salonBookingRetryCta : l10n.bookingSubmitCta);

    return PopScope(
      // Once any appointment has been created, block the OS/gesture back so a
      // partial success can only be finished via the «Повторити» retry (which
      // reuses stable idempotency keys). Back stays free while nothing has
      // succeeded yet.
      canPop: !hasSucceeded,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) _showBackBlockedMessage();
      },
      child: Scaffold(
        backgroundColor: BrandColors.base,
        bottomNavigationBar: BookingCtaFooter(
          key: const Key('salon-confirm-cta-footer'),
          buttonKey: const Key('salon-confirm-submit-cta'),
          label: ctaLabel,
          enabled: true,
          loading: inFlight,
          onPressed: _submit,
        ),
        body: SafeArea(
          bottom: false,
          child: Column(
            children: <Widget>[
              BookingTopBar(
                title: l10n.salonBookingConfirmTitle,
                backSemantics: l10n.bookingConfirmBackSemantics,
                onBack: () => _onBack(hasSucceeded),
                backKey: const Key('salon-confirm-back'),
              ),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    VelvetSpacing.lg,
                    VelvetSpacing.md,
                    VelvetSpacing.lg,
                    VelvetSpacing.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      for (int i = 0; i < appointments.length; i++) ...<Widget>[
                        _AppointmentCardSlot(
                          appointment: appointments[i],
                          position: i,
                        ),
                        const SizedBox(height: VelvetSpacing.md),
                      ],
                      BookingCommentField(
                        controller: _comment,
                        fieldKey: const Key('salon-confirm-comment-field'),
                        maxLength: _maxComment,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One appointment card wired to ITS OWN slice of [SalonBookingSubmitState].
///
/// Watching `(statusFor(id), failureFor(id))` through a scoped [Consumer] +
/// `select` (record → value equality) means an unaffected master's card
/// memoizes across every other master's mutation during a submit pass — only
/// the card whose status/failure actually changed rebuilds.
class _AppointmentCardSlot extends StatelessWidget {
  const _AppointmentCardSlot({
    required this.appointment,
    required this.position,
  });

  final SalonBookingAppointment appointment;
  final int position;

  @override
  Widget build(BuildContext context) {
    final String masterId = appointment.schedule.masterId;
    return Consumer(
      builder: (BuildContext context, WidgetRef ref, Widget? child) {
        final (SalonAppointmentSubmitStatus status, Failure? failure) = ref
            .watch(
              salonBookingSubmitProvider.select(
                (SalonBookingSubmitState s) =>
                    (s.statusFor(masterId), s.failureFor(masterId)),
              ),
            );
        return SalonAppointmentCard(
          key: ValueKey<String>('salon-confirm-appt-$masterId'),
          appointment: appointment,
          avatarGradient: salonAvatarGradient(position),
          // `statusFor` returns `pending` before the first submit pass; the
          // card renders no status line for `pending`, so no extra "attempted"
          // gate is needed.
          status: status,
          failure: failure,
        );
      },
    );
  }
}
