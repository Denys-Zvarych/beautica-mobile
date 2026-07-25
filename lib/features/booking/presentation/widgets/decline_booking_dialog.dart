// Track 27.x Wave A — «Скасувати запис клієнта?» — the PROVIDER's decline
// confirmation, which also collects an OPTIONAL free-text comment.
//
// A `part of 'cancel_booking_dialog.dart'` (see that file's `part`
// directive), mirroring `cancel_visit_dialog.dart`'s precedent: it reuses the
// single-booking dialog's private destructive chrome — the red
// [_DestructiveBadge], the optional-note [_NoteField] (relabelled for the
// provider via its new `label`/`hint` overrides), the saturated
// [_DestructiveButton] — so the client-cancel and provider-decline
// confirmations are visually identical, while `CancelBookingDialog`'s own
// render stays byte-for-byte unchanged.
//
// ## Why this is NOT `CancelBookingDialog` with a role flag
//
// The two dialogs write to DIFFERENT backend endpoints with DIFFERENT
// `cancellationReason` values baked in (`PATCH .../cancel` →
// `CLIENT_CANCELLED`, always sent by `BookingRepository.cancelBooking`;
// `PATCH .../decline` → `PROVIDER_UNAVAILABLE`, always sent by
// `BookingRepository.declineBooking`), and the recap's second row names a
// DIFFERENT party (the master for the client's dialog, the client for this
// one). Branching one widget on `viewer.isProvider` would tangle two
// unrelated write paths behind one call site for a savings of a handful of
// lines; two thin dialogs sharing the same private chrome is the smaller
// surface to reason about.
//
// ## ⚠ Same warning as `CancelBookingDialog` — DO NOT build a picker out of
// the `CancellationReason` enum. This dialog collects ONLY the free text; the
// enum value is fixed inside the repository, never surfaced here.

part of 'cancel_booking_dialog.dart';

/// Opens the decline confirmation for [booking] on behalf of the
/// authenticated PROVIDER.
///
/// Resolves to the provider's optional comment (possibly an EMPTY string —
/// confirmed but wrote nothing) on confirm — forwarded to
/// `BookingRepository.declineBooking` (or, when [isAppointment] is `true`,
/// `AppointmentRepository.declineAppointment`) as the `comment`/
/// `providerComment`, mutually visible to the client once the booking(s)
/// read `DECLINED` (CLAUDE.md booking-notes rule). Resolves to `null` on
/// every way of backing out, exactly like [showCancelBookingDialog] — `null`
/// means *do nothing*.
///
/// [isAppointment] (`Booking.appointmentId != null`) swaps the title/subtitle
/// to the whole-visit copy — the decline transitions EVERY service in the
/// visit, not just [booking].
Future<String?> showDeclineBookingDialog(
  BuildContext context,
  Booking booking, {
  bool isAppointment = false,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: true,
    builder: (_) =>
        DeclineBookingDialog(booking: booking, isAppointment: isAppointment),
  );
}

class DeclineBookingDialog extends StatefulWidget {
  const DeclineBookingDialog({
    super.key,
    required this.booking,
    this.isAppointment = false,
  });

  final Booking booking;

  /// See [showDeclineBookingDialog]'s doc.
  final bool isAppointment;

  @override
  State<DeclineBookingDialog> createState() => _DeclineBookingDialogState();
}

class _DeclineBookingDialogState extends State<DeclineBookingDialog> {
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
    final Booking b = widget.booking;

    // The counterparty from the PROVIDER's side is the CLIENT — same guest
    // fallback `BookingCounterpartyHeader`/`_ClientStrip` already use, so a
    // LINK/guest booking's recap reads identically here.
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
          key: const Key('decline-booking-dialog'),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Center(child: _DestructiveBadge()),
                const SizedBox(height: VelvetSpacing.md),

                Text(
                  widget.isAppointment
                      ? l10n.declineAppointmentDialogTitle
                      : l10n.declineBookingDialogTitle,
                  textAlign: TextAlign.center,
                  style: VelvetText.subheading(),
                ),
                const SizedBox(height: VelvetSpacing.xs),
                Text(
                  widget.isAppointment
                      ? l10n.declineAppointmentDialogSubtitle
                      : l10n.declineBookingDialogSubtitle,
                  textAlign: TextAlign.center,
                  style: VelvetText.bookSuccessSubline,
                ),
                const SizedBox(height: VelvetSpacing.md),

                // ── WHAT is about to be destroyed — the client's booking.
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
                  label: l10n.declineBookingNoteLabel,
                  hint: l10n.declineBookingNoteHint,
                ),
                const SizedBox(height: VelvetSpacing.md),

                // ── The destructive action — the ONLY way anything is
                //    declined.
                _DestructiveButton(
                  buttonKey: const Key('decline-booking-confirm'),
                  label: l10n.declineBookingConfirmCta,
                  icon: Icons.close_rounded,
                  onPressed: () => dismissOverlay(context, _note.text.trim()),
                ),
                const SizedBox(height: VelvetSpacing.xs),

                // ── The safe way out. Also the scrim, also the back gesture.
                Center(
                  child: TextButton(
                    key: const Key('decline-booking-keep'),
                    onPressed: () => dismissOverlay(context),
                    child: Text(
                      l10n.declineBookingKeepCta,
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
