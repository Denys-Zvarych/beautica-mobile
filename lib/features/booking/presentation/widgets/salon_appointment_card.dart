// Phase 14.18 — SalonAppointmentCard: one salon appointment's read-only
// summary, shown on BOTH the salon confirmation screen (a last read before
// submit, with live per-appointment submit status) and the salon success
// screen (the confirmed recap).
//
// The independent-master flow's shared `BookingSummaryCards` is used
// directly by the SUCCESS screen's per-appointment recap (via
// `BookingSummaryCards.fromSchedule` — see that widget's file header), but
// the CONFIRM screen still needs this bespoke card: it is the only one that
// must carry a live per-appointment submit-status line
// (`SalonBookingSubmitState`), which `BookingSummaryCards` has no concept of.
// This card mirrors `BookingSummaryCards`' details-card structure by hand for
// that reason: the SHARED [MasterStrip] identity card (the SAME widget every
// other booking screen in both flows renders) over a details card carrying
// Дата → Час → a hairline [SectionRule] → this master's own [BookingRecap]
// (services + subtotal) → the optional submit-status line.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';

import '../../application/salon_booking_submit_notifier.dart';
import '../../domain/salon_booking_confirm_args.dart';
import 'booking_recap.dart';
import 'labelled_row.dart';
import 'master_strip.dart';
import 'section_rule.dart';

/// A single salon appointment summary — the shared [MasterStrip] over a
/// Дата/Час details card, with an optional [status]/[failure] line.
class SalonAppointmentCard extends StatelessWidget {
  const SalonAppointmentCard({
    super.key,
    required this.appointment,
    required this.selections,
    required this.avatarGradient,
    this.status,
    this.failure,
    this.showSucceededStatus = true,
  });

  final SalonBookingAppointment appointment;

  /// This appointment's services, already mapped to [BookingSelection] by the
  /// caller — kept out of `build()` so the ~2-3 rebuilds a submit pass drives
  /// per card (pending → submitting → succeeded/failed) don't reallocate this
  /// small list on every status transition (mobile-perf LOW, Phase 14.18
  /// audit). Callers should compute it once per appointment, not per build.
  final List<BookingSelection> selections;

  /// Avatar gradient — the same per-position gradient the "Час" slide used.
  final List<Color> avatarGradient;

  /// This appointment's live submit status, or `null` to render no status
  /// line at all (the success screen, where every appointment is done, and
  /// the confirm screen before the first submit attempt).
  final SalonAppointmentSubmitStatus? status;

  /// The failure to surface when [status] is
  /// [SalonAppointmentSubmitStatus.failed].
  final Failure? failure;

  /// Whether a [status] of [SalonAppointmentSubmitStatus.succeeded] is worth
  /// rendering on screen.
  ///
  /// This is NOT "did this appointment succeed" — [status] already answers
  /// that. It answers "is the user actually staying on this screen to look at
  /// it". The caller passes `inFlight || hasFailures` (see
  /// `_AppointmentCardSlot` in `salon_booking_confirm_screen.dart`) — i.e.
  /// "a submit/retry pass is currently in progress, OR it has settled with at
  /// least one failure":
  ///
  /// - While a pass is `inFlight` (mid multi-master submit, or mid retry),
  ///   this is `true` so an already-succeeded master's "Заплановано" line
  ///   stays visible — it is the signal telling the user which masters are
  ///   already booked, don't retry those. Gating on live `hasFailures` alone
  ///   would hide it here: nothing has failed *yet* partway through a submit,
  ///   and a retry's pre-loop reset clears `hasFailures` before any network
  ///   call even starts, so the checkmark would wrongly read as "not
  ///   attempted" for the whole in-flight duration.
  /// - Once settled (`inFlight == false`): if every appointment succeeded,
  ///   this is `false` — the confirm screen `pushReplacement`s away with no
  ///   `await` between the last state write and the navigation call, so that
  ///   frame never actually paints and the line would just be noise if it
  ///   somehow did. If some failed, this is `true` and the line is the same
  ///   "already booked, don't retry" signal, now shown at rest.
  ///
  /// `submitting` and `failed` are unaffected — they always render.
  final bool showSucceededStatus;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final String dateLabel = formatFullDate(appointment.startAt);
    final String timeLabel = formatTimeRange(
      appointment.startAt,
      appointment.durationMinutes,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        MasterStrip.fromSchedule(
          appointment.schedule,
          showRole: true,
          showRating: true,
          avatarGradient: avatarGradient,
          avatarBordered: true,
        ),
        const SizedBox(height: VelvetSpacing.sm),
        NeumorphicCard(
          showBorder: true,
          padding: const EdgeInsets.all(VelvetSpacing.sm + 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              LabelledRow(label: l10n.bookingDateLabel, value: dateLabel),
              const SizedBox(height: VelvetSpacing.sm),
              LabelledRow(label: l10n.bookingTimeLabel, value: timeLabel),
              const SectionRule(),
              BookingRecap(selections: selections),
              if (status != null &&
                  status != SalonAppointmentSubmitStatus.pending &&
                  (status != SalonAppointmentSubmitStatus.succeeded ||
                      showSucceededStatus))
                Padding(
                  padding: const EdgeInsets.only(top: VelvetSpacing.sm + 2),
                  child: _StatusLine(status: status!, failure: failure),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The per-appointment submit-status line: a spinner while in flight, a green
/// check on success, or an error glyph + the failure's user message on
/// failure.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.status, required this.failure});

  final SalonAppointmentSubmitStatus status;
  final Failure? failure;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    switch (status) {
      case SalonAppointmentSubmitStatus.pending:
        return const SizedBox.shrink();
      case SalonAppointmentSubmitStatus.submitting:
        return Row(
          children: <Widget>[
            const SizedBox(
              height: 15,
              width: 15,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: BrandColors.accent,
              ),
            ),
            const SizedBox(width: VelvetSpacing.sm),
            Text(
              l10n.salonBookingAppointmentSubmitting,
              style: VelvetText.salonApptStatusMuted,
            ),
          ],
        );
      case SalonAppointmentSubmitStatus.succeeded:
        return Row(
          children: <Widget>[
            const Icon(
              Icons.check_circle_rounded,
              size: 16,
              color: BrandColors.success,
            ),
            const SizedBox(width: VelvetSpacing.sm),
            Text(
              l10n.salonBookingAppointmentSucceeded,
              style: VelvetText.salonApptStatusSuccess,
            ),
          ],
        );
      case SalonAppointmentSubmitStatus.failed:
        final String message = failure != null
            ? failure!.userMessage(context)
            : l10n.errUnknown;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(
              Icons.error_outline_rounded,
              size: 16,
              color: BrandColors.error,
            ),
            const SizedBox(width: VelvetSpacing.sm),
            Expanded(
              child: Text(message, style: VelvetText.salonApptStatusError),
            ),
          ],
        );
    }
  }
}
