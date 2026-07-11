// Phase 14.18 — SalonAppointmentCard: one salon appointment's read-only
// summary, shown on BOTH the salon confirmation screen (a last read before
// submit, with live per-appointment submit status) and the salon success
// screen (the confirmed recap).
//
// The independent-master flow's shared `BookingSummaryCards` is
// `Master`/`MasterService`-typed and single-appointment, so it can't be
// reused for the salon N-master model. This card is the salon analogue:
// [SalonMasterStrip] (identity + services + summed duration — the SAME strip
// the "Час" slide showed) over a details card carrying the chosen Дата/Час,
// plus an optional per-appointment submit-status line the confirm screen
// feeds from `SalonBookingSubmitState`.

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
import 'labelled_row.dart';
import 'salon_master_strip.dart';

/// A single salon appointment summary — [SalonMasterStrip] over a Дата/Час
/// details card, with an optional [status]/[failure] line.
class SalonAppointmentCard extends StatelessWidget {
  const SalonAppointmentCard({
    super.key,
    required this.appointment,
    required this.avatarGradient,
    this.status,
    this.failure,
  });

  final SalonBookingAppointment appointment;

  /// Avatar gradient — the same per-position gradient the "Час" slide used.
  final List<Color> avatarGradient;

  /// This appointment's live submit status, or `null` to render no status
  /// line at all (the success screen, where every appointment is done, and
  /// the confirm screen before the first submit attempt).
  final SalonAppointmentSubmitStatus? status;

  /// The failure to surface when [status] is
  /// [SalonAppointmentSubmitStatus.failed].
  final Failure? failure;

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
        SalonMasterStrip(
          schedule: appointment.schedule,
          avatarGradient: avatarGradient,
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
              if (status != null &&
                  status != SalonAppointmentSubmitStatus.pending)
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
