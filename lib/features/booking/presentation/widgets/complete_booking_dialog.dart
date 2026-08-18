// Track 27.x Wave A — «Завершити запис?» confirmation for the PROVIDER's
// «Завершити» action.
//
// A plain VelvetTouch-styled `AlertDialog` (mirrors
// `settings/presentation/logout_action.dart`'s inline dialog and
// `services/presentation/widgets/delete_service_dialog.dart`'s
// show/return-bool contract) rather than the heavier `NeumorphicCard` shell
// `CancelBookingDialog`/`DeclineBookingDialog` use — there is no note field
// to host: completing a booking records no free-text account of what
// happened (unlike decline / not-complete, both of which write
// `providerComment`). POSITIVE action, not destructive: the confirm button
// takes `accentDeep`, never `error`.

import 'package:beautica_mobile/core/navigation/overlay_navigation.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Confirmation dialog for marking ONE booking COMPLETED — either a
/// standalone booking or a single service line of a multi-service visit.
///
/// Show via [showDialog]:
/// ```dart
/// final confirmed = await showDialog<bool>(
///   context: context,
///   builder: (_) => CompleteBookingDialog(isAppointment: booking.appointmentId != null),
/// );
/// if (confirmed == true) {
///   // completeAppointmentService(appointmentId, bookingId) for a visit's
///   // service line, completeBooking(id) for a standalone booking.
/// }
/// ```
///
/// Returns `true` when the provider confirmed, `false` (or `null` when the
/// dialog is dismissed by tapping outside) otherwise — mirrors
/// `DeleteServiceDialog`'s contract.
class CompleteBookingDialog extends StatelessWidget {
  const CompleteBookingDialog({super.key, this.isAppointment = false});

  /// `true` when the booking being completed is one service line of a
  /// multi-service visit (`Booking.appointmentId != null`) — the copy swaps
  /// to the per-service wording, because the confirm completes only that one
  /// service (`completeAppointmentService(appointmentId, bookingId)`) and its
  /// sibling services stay CONFIRMED.
  final bool isAppointment;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AlertDialog(
      key: const Key('complete-booking-dialog'),
      backgroundColor: BrandColors.base,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(VelvetRadii.card)),
      ),
      title: Text(
        isAppointment
            ? l10n.completeAppointmentDialogTitle
            : l10n.completeBookingDialogTitle,
        style: VelvetText.heading(),
      ),
      content: Text(
        isAppointment
            ? l10n.completeAppointmentDialogBody
            : l10n.completeBookingDialogBody,
        style: VelvetText.body(),
      ),
      actions: <Widget>[
        TextButton(
          key: const Key('complete-booking-keep'),
          onPressed: () => dismissOverlay(context, false),
          child: Text(l10n.cancel, style: VelvetText.link()),
        ),
        TextButton(
          key: const Key('complete-booking-confirm'),
          onPressed: () => dismissOverlay(context, true),
          child: Text(
            l10n.completeBookingConfirmCta,
            style: VelvetText.link().copyWith(color: BrandColors.accentDeep),
          ),
        ),
      ],
    );
  }
}
