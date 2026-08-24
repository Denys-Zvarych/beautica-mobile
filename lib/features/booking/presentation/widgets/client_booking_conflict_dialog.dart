/// «У вас вже є запис на цей час» — the NON-destructive confirmation shown
/// when a salon-booking submit returns a client-conflict 409
/// (`ClientBookingConflictFailure`): the CLIENT's own calendar overlaps the
/// slot they are trying to book. See `ClientBookingConflictFailure`'s own doc
/// for the backend contract and `CreateAppointmentRequest.allowClientOverlap`
/// for the resubmit flag this dialog's confirm resolves to.
///
/// PRODUCT DECISION (owner, 2026-08-22, verbatim): "remove the bottom error
/// when client already has a booking on same date/time; instead display a
/// popup that the client wants to make a booking for service … but he
/// already has service …, still proceed? … It's only the client's
/// responsibility." The per-MASTER overlap rule (a different client's slot,
/// or a Postgres EXCLUDE constraint) is untouched and unwaivable — this
/// dialog only ever offers to waive the CLIENT's own self-overlap check.
///
/// ## Chrome — mirrored, not invented
///
/// The shell is 1:1 with `CancelBookingDialog`/`DayOffConflictDialog`: a
/// transparent [Dialog], `insetPadding` (h: lg, v: xl), a `maxWidth: 420`
/// [ConstrainedBox], one bordered [NeumorphicCard] — a centred badge circle,
/// a `subheading()` title, a muted subline, two [LabelledRow] recap rows
/// (separated by a [SectionRule]), a primary pill, a centred quiet
/// back-out. Unlike those two dialogs this is **not** a destructive
/// confirmation — booking both appointments is a perfectly ordinary outcome
/// the client is explicitly allowed to choose — so the badge and primary
/// action are **camel**, never `BrandColors.error`. `cancel_booking_dialog
/// .dart`'s own doc comments already named this dialog by this exact class
/// name and this exact colour rule, ahead of this file existing.
///
/// ## Backing out is the safe path
///
/// `barrierDismissible: true`, the OS back gesture, and an explicit
/// «Скасувати» all resolve to `null` — nothing is (re)submitted unless the
/// client deliberately taps the camel button. The caller (`salon_booking
/// _confirm_screen.dart`'s `_submitOne`) treats every non-`true` resolution
/// identically: stop, leave the confirm screen exactly as it is, no bottom
/// error banner, submit nothing further.
library;

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/navigation/overlay_navigation.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';

import 'labelled_row.dart';
import 'section_rule.dart';

/// Everything [ClientBookingConflictDialog] needs to render — the appointment
/// the client is CURRENTLY trying to book (already flattened to display
/// primitives by the caller, which owns the domain types) plus the
/// [conflict] the server reported for the client's EXISTING booking.
@immutable
class ClientBookingConflictPreview {
  const ClientBookingConflictPreview({
    required this.newServiceNames,
    required this.newMasterName,
    required this.newStart,
    required this.newEnd,
    required this.conflict,
  });

  /// This appointment's ordered service names, already joined (e.g.
  /// "Манікюр, Педикюр") — a visit can carry 2+ services, so this is a plain
  /// comma join (punctuation, not translatable copy), mirroring
  /// `booking_success_screen.dart`'s / `salon_master_selection_screen.dart`'s
  /// identical `.join(', ')` precedent.
  final String newServiceNames;

  /// This appointment's master display name.
  final String newMasterName;

  /// This appointment's chosen visit window.
  final DateTime newStart;
  final DateTime newEnd;

  /// The server's own report of the CLIENT's existing overlapping booking —
  /// carries its own service/master name and window.
  final ClientBookingConflictFailure conflict;
}

/// Opens the client-self-overlap confirmation.
///
/// Resolves to `true` when the client taps «Все одно записатись» (the caller
/// then resubmits the SAME appointment with `allowClientOverlap: true`), and
/// to `null` on every other exit (scrim tap, back gesture, «Скасувати») —
/// meaning *submit nothing, leave the confirm screen exactly as it is*.
Future<bool?> showClientBookingConflictDialog(
  BuildContext context,
  ClientBookingConflictPreview preview,
) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierColor: BrandColors.text.withValues(alpha: 0.35),
    builder: (_) => ClientBookingConflictDialog(preview: preview),
  );
}

class ClientBookingConflictDialog extends StatelessWidget {
  const ClientBookingConflictDialog({super.key, required this.preview});

  final ClientBookingConflictPreview preview;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ClientBookingConflictFailure conflict = preview.conflict;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: VelvetSpacing.lg,
        vertical: VelvetSpacing.xl,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: NeumorphicCard(
          key: const Key('client-booking-conflict-dialog'),
          showBorder: true,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Center(child: _ConflictBadge()),
                const SizedBox(height: VelvetSpacing.md),
                Text(
                  l10n.salonBookingConflictDialogTitle,
                  textAlign: TextAlign.center,
                  style: VelvetText.subheading(),
                ),
                const SizedBox(height: VelvetSpacing.xs),
                Text(
                  l10n.salonBookingConflictDialogSubtitle,
                  textAlign: TextAlign.center,
                  style: VelvetText.bookSuccessSubline,
                ),
                const SizedBox(height: VelvetSpacing.md),
                LabelledRow(
                  key: const Key('client-booking-conflict-new'),
                  label: l10n.salonBookingConflictNewBookingLabel,
                  value: preview.newServiceNames,
                  detail:
                      '${preview.newMasterName} · '
                      '${formatBookingWindow(preview.newStart, preview.newEnd)}',
                  compactText: true,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SectionRule(dense: true),
                LabelledRow(
                  key: const Key('client-booking-conflict-existing'),
                  label: l10n.salonBookingConflictExistingBookingLabel,
                  value: conflict.serviceName,
                  detail:
                      '${conflict.masterName} · '
                      '${formatBookingWindow(conflict.startsAt, conflict.endsAt)}',
                  compactText: true,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: VelvetSpacing.md),
                NeumorphicButton(
                  key: const Key('client-booking-conflict-proceed'),
                  label: l10n.salonBookingConflictProceedCta,
                  onPressed: () => dismissOverlay(context, true),
                ),
                const SizedBox(height: VelvetSpacing.xs),
                Center(
                  child: TextButton(
                    key: const Key('client-booking-conflict-dismiss'),
                    onPressed: () => dismissOverlay(context),
                    child: Text(
                      l10n.salonBookingConflictDismissCta,
                      style: VelvetText.feedbackMutedSm,
                    ),
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

/// The badge circle — **camel**, never `error`: an overlapping booking here
/// is a routine scheduling clash the client is explicitly allowed to accept,
/// not a destructive/failure state. See the file header.
class _ConflictBadge extends StatelessWidget {
  const _ConflictBadge();

  static const double _diameter = 56;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _diameter,
      width: _diameter,
      decoration: BoxDecoration(
        color: BrandColors.accent.withValues(alpha: 0.18),
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.event_repeat_rounded,
        color: BrandColors.accentDeep,
        size: 28,
      ),
    );
  }
}
