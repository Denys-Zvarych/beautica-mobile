// Client-no-show — «Клієнт не прийшов?» — the PROVIDER's no-show
// confirmation, which also collects an OPTIONAL free-text comment.
//
// A `part of 'cancel_booking_dialog.dart'` (see that file's `part`
// directive), mirroring `decline_booking_dialog.dart`'s precedent exactly: it
// reuses the single-booking dialog's private destructive chrome — the red
// [_DestructiveBadge], the optional-note [_NoteField] (relabelled for this
// action), the saturated [_DestructiveButton] — so the client-cancel,
// provider-decline, and provider-no-show confirmations are visually
// identical, while `CancelBookingDialog`'s own render stays byte-for-byte
// unchanged.
//
// ## Why this is NOT `DeclineBookingDialog` with a flag
//
// The two dialogs write to DIFFERENT backend endpoints with DIFFERENT
// `cancellationReason`/DTO shapes baked in (`PATCH .../decline` →
// `StatusUpdateRequest.PROVIDER_UNAVAILABLE`, always sent by
// `BookingRepository.declineBooking`; `PATCH .../not-complete` →
// `StatusUpdateRequest.CLIENT_NO_SHOW`, always sent by
// `BookingRepository.notCompleteBooking`), and they apply to entirely
// different points in the booking's timeline (decline is offered BEFORE the
// appointment starts; no-show is offered AFTER it has elapsed — see
// `booking_detail_screen.dart`'s `_providerActions`). Branching one widget on
// a role/kind flag would tangle two unrelated write paths behind one call
// site for a savings of a handful of lines; two thin dialogs sharing the same
// private chrome is the smaller surface to reason about.
//
// ## ⚠ Same warning as `CancelBookingDialog`/`DeclineBookingDialog` — DO NOT
// build a picker out of the `CancellationReason` enum. This dialog collects
// ONLY the free text; the enum value (`CLIENT_NO_SHOW`) is fixed inside the
// repository, never surfaced here.

part of 'cancel_booking_dialog.dart';

/// Opens the no-show confirmation for [booking] on behalf of the
/// authenticated PROVIDER.
///
/// Resolves to the provider's optional comment (possibly an EMPTY string —
/// confirmed but wrote nothing) on confirm — forwarded to
/// `BookingRepository.notCompleteBooking` (or, when [isAppointment] is
/// `true`, `AppointmentRepository.notCompleteAppointment`) as the `comment`/
/// `providerComment`, mutually visible to the client once the booking(s)
/// read `NOT_COMPLETED` (CLAUDE.md booking-notes rule). Resolves to `null` on
/// every way of backing out, exactly like [showCancelBookingDialog]/
/// [showDeclineBookingDialog] — `null` means *do nothing*.
///
/// [isAppointment] (`Booking.appointmentId != null`) swaps the title/subtitle
/// to the whole-visit copy — the no-show transitions EVERY service in the
/// visit, not just [booking].
Future<String?> showNotCompleteBookingDialog(
  BuildContext context,
  Booking booking, {
  bool isAppointment = false,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: true,
    builder: (_) => NotCompleteBookingDialog(
      booking: booking,
      isAppointment: isAppointment,
    ),
  );
}

class NotCompleteBookingDialog extends StatefulWidget {
  const NotCompleteBookingDialog({
    super.key,
    required this.booking,
    this.isAppointment = false,
  });

  final Booking booking;

  /// See [showNotCompleteBookingDialog]'s doc.
  final bool isAppointment;

  @override
  State<NotCompleteBookingDialog> createState() =>
      _NotCompleteBookingDialogState();
}

class _NotCompleteBookingDialogState extends State<NotCompleteBookingDialog> {
  final TextEditingController _note = TextEditingController();

  /// Matches [CancelBookingDialog]'s/[DeclineBookingDialog]'s cap.
  static const int _maxLength = 500;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final Booking b = widget.booking;

    // The counterparty from the PROVIDER's side is the CLIENT — same guest
    // fallback `BookingCounterpartyHeader`/`_ClientStrip`/
    // `DeclineBookingDialog` already use, so a LINK/guest booking's recap
    // reads identically here.
    final String clientDisplayName =
        b.clientName ?? l10n.bookingDetailGuestClient;

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
          key: const Key('not-complete-booking-dialog'),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Center(child: _DestructiveBadge()),
                const SizedBox(height: VelvetSpacing.md),

                Text(
                  widget.isAppointment
                      ? l10n.notCompleteAppointmentDialogTitle
                      : l10n.notCompleteBookingDialogTitle,
                  textAlign: TextAlign.center,
                  style: VelvetText.subheading(),
                ),
                const SizedBox(height: VelvetSpacing.xs),
                Text(
                  widget.isAppointment
                      ? l10n.notCompleteAppointmentDialogSubtitle
                      : l10n.notCompleteBookingDialogSubtitle,
                  textAlign: TextAlign.center,
                  style: VelvetText.bookSuccessSubline,
                ),
                const SizedBox(height: VelvetSpacing.md),

                // ── WHAT is about to be marked — the client's booking.
                LabelledRow(
                  label: l10n.bookingServiceLabel,
                  value: b.serviceName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  compactText: true,
                ),
                const SectionRule(dense: true),
                LabelledRow(
                  label: l10n.bookingClientLabel,
                  value: clientDisplayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  compactText: true,
                ),
                const SectionRule(dense: true),
                LabelledRow(
                  label: l10n.bookingWhenLabel,
                  value: formatFullDate(b.startAt),
                  detail: formatTimeRange(b.startAt, b.durationMinutes),
                  compactText: true,
                ),
                const SizedBox(height: VelvetSpacing.md),

                // ── The note. Optional free text the provider may add —
                //    mutually visible to the client (CLAUDE.md booking-notes
                //    rule), so the copy is written for THAT audience.
                _NoteField(
                  controller: _note,
                  maxLength: _maxLength,
                  label: l10n.notCompleteBookingNoteLabel,
                  hint: l10n.notCompleteBookingNoteHint,
                ),
                const SizedBox(height: VelvetSpacing.md),

                // ── The destructive action — the ONLY way anything is
                //    marked NOT_COMPLETED.
                _DestructiveButton(
                  buttonKey: const Key('not-complete-booking-confirm'),
                  label: l10n.notCompleteBookingConfirmCta,
                  icon: Icons.person_off_rounded,
                  onPressed: () => dismissOverlay(context, _note.text.trim()),
                ),
                const SizedBox(height: VelvetSpacing.xs),

                // ── The safe way out. Also the scrim, also the back gesture.
                Center(
                  child: TextButton(
                    key: const Key('not-complete-booking-keep'),
                    onPressed: () => dismissOverlay(context),
                    child: Text(
                      l10n.notCompleteBookingKeepCta,
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
