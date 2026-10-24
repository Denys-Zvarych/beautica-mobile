// Phase 415 D2 / D3 — «Створити нове посилання?» confirmation.
//
// Built on the app's shared confirm chrome ([ConfirmDialogShell] +
// [ConfirmDialogBadge]) exactly like the routine move-admin confirm
// (`admin_action_dialogs.dart`): camel-family badge at 0.14 + a
// [NeumorphicButton] action + the quiet «Скасувати». Design source:
// `docs/signup-designs/BookingLinks/` entry 10 (and 12 for the revoked body).

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/navigation/overlay_navigation.dart';
import 'package:beautica_mobile/core/navigation/single_flight.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/confirm_dialog_shell.dart';

/// Opens the regenerate confirmation. [fromRevoked] picks the short body
/// (D3: nothing to update in Instagram — the old link is already off).
/// Resolves to `true` only on «Створити»; every other exit is `null`.
Future<bool?> showRegenerateBookingLinkDialog(
  BuildContext context, {
  required bool fromRevoked,
}) {
  return showDialogOnce<bool>(
    context: context,
    barrierDismissible: true,
    builder: (_) => RegenerateBookingLinkDialog(fromRevoked: fromRevoked),
  );
}

class RegenerateBookingLinkDialog extends StatelessWidget {
  const RegenerateBookingLinkDialog({super.key, required this.fromRevoked});

  final bool fromRevoked;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return ConfirmDialogShell(
      dialogKey: const Key('regenerate-booking-link-dialog'),
      badge: const ConfirmDialogBadge(
        icon: Icons.autorenew_rounded,
        tint: BrandColors.accentDeep,
        alpha: 0.14,
      ),
      title: l10n.bookingLinkRegenerateTitle,
      message: fromRevoked
          ? l10n.bookingLinkRegenerateBodyRevoked
          : l10n.bookingLinkRegenerateBody,
      // Key on a plain proxy: NeumorphicButton's AnimatedScale root is not
      // hit-tested.
      action: SizedBox(
        key: const Key('regenerate-booking-link-confirm'),
        child: NeumorphicButton(
          label: l10n.bookingLinkRegenerateConfirm,
          icon: Icons.autorenew_rounded,
          onPressed: () => dismissOverlay(context, true),
        ),
      ),
      dismissKey: const Key('regenerate-booking-link-dismiss'),
      dismissLabel: l10n.actionCancel,
    );
  }
}
