// MO-5 — «Скасувати запис?» for a multi-service VISIT.
//
// A `part of cancel_booking_dialog.dart` (see that file's `part` directive): it
// reuses the single-booking dialog's private destructive chrome — the red
// [_DestructiveBadge], the optional-note [_NoteField], the saturated
// [_DestructiveButton] — so the two confirmations are visually identical, while
// the single-booking dialog's own render stays untouched.
//
// The ONE difference vs `CancelBookingDialog`: the recap shows the VISIT — its
// services line (already formatted «N послуг» by the caller, which holds the
// `Appointment`), the master, and the visit's whole window — because a visit
// cancel takes ALL its services away at once. The client's OWN cancel of a
// visit must route to `AppointmentRepository.cancelAppointment` (the backend
// 409s a single-booking cancel on an appointment child), so this dialog is the
// visit path's confirmation and the note it returns is forwarded there.

part of 'cancel_booking_dialog.dart';

/// Opens the cancellation confirmation for a multi-service visit.
///
/// [servicesLabel] is the already-formatted «N послуг» count (the caller holds
/// the `Appointment`); [dateLabel] / [timeDetail] describe the visit's whole
/// window. Resolves to the client's note (possibly an EMPTY string — confirmed
/// but wrote nothing) on confirm, and to `null` when they backed out by any
/// means. `null` means *do nothing*.
Future<String?> showCancelVisitDialog(
  BuildContext context, {
  required String servicesLabel,
  required String masterName,
  required String dateLabel,
  required String timeDetail,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: true,
    builder: (_) => CancelVisitDialog(
      servicesLabel: servicesLabel,
      masterName: masterName,
      dateLabel: dateLabel,
      timeDetail: timeDetail,
    ),
  );
}

/// The visit cancellation confirmation. See [showCancelVisitDialog].
class CancelVisitDialog extends StatefulWidget {
  const CancelVisitDialog({
    super.key,
    required this.servicesLabel,
    required this.masterName,
    required this.dateLabel,
    required this.timeDetail,
  });

  final String servicesLabel;
  final String masterName;
  final String dateLabel;
  final String timeDetail;

  @override
  State<CancelVisitDialog> createState() => _CancelVisitDialogState();
}

class _CancelVisitDialogState extends State<CancelVisitDialog> {
  final TextEditingController _note = TextEditingController();

  /// Matches [CancelBookingDialog]'s cap.
  static const int _maxLength = 500;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

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
          key: const Key('cancel-visit-dialog'),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Center(child: _DestructiveBadge()),
                const SizedBox(height: VelvetSpacing.md),

                Text(
                  l10n.cancelBookingDialogTitle,
                  textAlign: TextAlign.center,
                  style: VelvetText.subheading(),
                ),
                const SizedBox(height: VelvetSpacing.xs),
                Text(
                  l10n.cancelBookingDialogSubtitle,
                  textAlign: TextAlign.center,
                  style: VelvetText.bookSuccessSubline,
                ),
                const SizedBox(height: VelvetSpacing.md),

                // ── WHAT is about to be destroyed — the whole visit: its
                //    services, the master, the window.
                LabelledRow(
                  label: l10n.bookingServicesRecapLabel,
                  value: widget.servicesLabel,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  compactText: true,
                ),
                const SectionRule(dense: true),
                LabelledRow(
                  label: l10n.bookingMasterLabel,
                  value: widget.masterName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  compactText: true,
                ),
                const SectionRule(dense: true),
                LabelledRow(
                  label: l10n.bookingWhenLabel,
                  value: widget.dateLabel,
                  detail: widget.timeDetail,
                  compactText: true,
                ),
                const SizedBox(height: VelvetSpacing.md),

                _NoteField(controller: _note, maxLength: _maxLength),
                const SizedBox(height: VelvetSpacing.md),

                _DestructiveButton(
                  label: l10n.cancelBookingConfirmCta,
                  icon: Icons.close_rounded,
                  onPressed: () => dismissOverlay(context, _note.text.trim()),
                ),
                const SizedBox(height: VelvetSpacing.xs),

                Center(
                  child: TextButton(
                    key: const Key('cancel-visit-keep'),
                    onPressed: () => dismissOverlay(context),
                    child: Text(
                      l10n.cancelBookingKeepCta,
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
