// Phase 14.18 (restored, non-notifier-coupled) — SalonAppointmentCard: one
// salon appointment's review card on the confirmation screen — the SHARED
// [MasterStrip] identity card over a details card carrying Дата → Час → a
// hairline [SectionRule] → this master's OWN [BookingRecap] (services +
// subtotal) → a second [SectionRule] → this master's OWN
// [BookingCommentField].
//
// RESTORATION NOTE (owner-reported regression, 2026-08-22): Phase 271 deleted
// the original `SalonAppointmentCard` together with the per-master submit
// notifier it was coupled to (see the repo's structural guard against that
// deleted notifier's filename/symbols for that history) — collateral damage,
// not an intended redesign. This file restores the card's VISUAL composition
// only: per-master header, that master's own services/recap/subtotal,
// spacing, neumorphic treatment — transcribed from
// `git show 423dffc3^:lib/…/widgets/salon_appointment_card.dart`. It does NOT
// restore the deleted per-appointment submit-status enum, `status`/`failure`/
// `showSucceededStatus`, or anything else keyed by that notifier — per-master
// submit status is a later phase's job (see that phase's doc).
//
// COMMENT FIELD (owner decision, 2026-08-22, verbatim: "one field per master
// card"): unlike the original, this card now carries its OWN
// [BookingCommentField] rather than the confirm screen driving a single
// shared field for every appointment. The screen owns the
// [commentController]'s lifecycle (created/disposed per appointment — see
// `salon_booking_confirm_screen.dart`); this widget only renders it.
//
// REUSE-FIRST: every piece here is an existing shared widget —
// [MasterStrip.fromSchedule], [NeumorphicCard], [LabelledRow], [SectionRule],
// [BookingRecap], [BookingCommentField]. Nothing here is a fork of any of
// them.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';

import '../../domain/salon_booking_confirm_args.dart';
import 'booking_comment_field.dart';
import 'booking_recap.dart';
import 'labelled_row.dart';
import 'master_strip.dart';
import 'section_rule.dart';

/// A single salon appointment review card — the shared [MasterStrip] over a
/// Дата/Час/services/comment details card.
class SalonAppointmentCard extends StatelessWidget {
  const SalonAppointmentCard({
    super.key,
    required this.appointment,
    required this.selections,
    required this.avatarGradient,
    required this.commentController,
    required this.commentFieldKey,
    this.maxComment = 500,
  });

  final SalonBookingAppointment appointment;

  /// This appointment's services, already mapped to [BookingSelection] by the
  /// caller — kept out of `build()` so this widget never re-derives it on a
  /// rebuild driven by, say, the comment counter's own narrow
  /// [ValueListenableBuilder] (mirrors the deleted card's identical
  /// mobile-perf note — see the file header).
  final List<BookingSelection> selections;

  /// Avatar gradient — the same per-position gradient the "Час" slide used.
  final List<Color> avatarGradient;

  /// THIS appointment's own comment controller — owns/disposes it at the
  /// screen level. See the file header's COMMENT FIELD note.
  final TextEditingController commentController;

  /// Key applied to the inner comment [TextField], distinct per master (e.g.
  /// `salon-confirm-comment-field-<masterId>`) so widget tests can target
  /// each master's field independently.
  final Key commentFieldKey;

  final int maxComment;

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
              const SectionRule(),
              BookingCommentField(
                controller: commentController,
                fieldKey: commentFieldKey,
                maxLength: maxComment,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
