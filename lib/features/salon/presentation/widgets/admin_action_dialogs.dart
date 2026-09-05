/// Phase 21.6 — the two confirmations [AdminSettingsScreen] and
/// [MoveAdminSalonScreen] raise before touching an administrator. Phase 306
/// adds a third, [RemoveMasterDialog], for the categorically larger act of
/// removing a MASTER — its body is a bulleted consequence list rather than
/// [RemoveAdminDialog]'s one-liner, because a master carries booking
/// cancellation/notification and completed-history consequences an admin
/// does not — both endpoints hard-delete the user's account (Phase 299 made
/// the admin endpoint a hard delete too). All three route through the same
/// [_DialogShell] below.
///
/// ## Chrome — mirrored from the shipped app, not invented
///
/// All three dialogs are 1:1 with `CancelBookingDialog` / `ClientBookingConflict
/// Dialog` / `CategoryRequestDialog`: a transparent [Dialog], `insetPadding`
/// (h: lg, v: xl), a `maxWidth: 420` [ConstrainedBox], one [NeumorphicCard],
/// then a centred badge circle, a `subheading()` title, a muted subline, the
/// action, and a centred quiet back-out.
///
/// The approved preview (`docs/signup-designs/SalonManagementDesign/lib/
/// screens/admin_settings_screen.dart:139-200` and
/// `move_admin_salon_screen.dart:79-128`) draws the same badge → title →
/// message column, then a side-by-side [Скасувати][Confirm] pair built from
/// its own private `_DialogButton`. That button is one of the three widgets
/// the port brief names as "already exists in production, do not port" — its
/// production counterparts are [NeumorphicButton] (primary),
/// [DestructiveButton] (destructive) and [QuietAction] (back-out), which
/// every other confirmation in the app already uses stacked. Porting the pair
/// would have meant a fourth private copy of a button that exists three times
/// over, so the ACTION LAYOUT is the shipped one (stacked action + centred
/// quiet back-out) while everything above it is the preview verbatim. This is
/// the single deliberate deviation from the preview on either screen.
///
/// ## Backing out is the safe path
///
/// `barrierDismissible: true`, the OS back gesture and the explicit back-out
/// all resolve to `null`. Nothing is removed or moved unless the viewer
/// deliberately taps the action.
library;

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/navigation/overlay_navigation.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/destructive_action.dart';

/// Opens the destructive «Видалити майстра?» confirmation for the master
/// displayed as [masterName].
///
/// Phase 306 — copy + widget only, no call site yet (phase 307 wires this to
/// the settings screen and the removal endpoint). Resolves to `true` only
/// when the viewer taps the red confirm; every other exit (barrier tap, back
/// gesture, the quiet cancel) resolves to `null`, meaning *do nothing* — the
/// same contract [showRemoveAdminDialog] gives, because backing out must
/// never be the risky path in a destructive confirmation.
Future<bool?> showRemoveMasterDialog(BuildContext context, String masterName) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (_) => RemoveMasterDialog(masterName: masterName),
  );
}

/// Opens the destructive «Видалити адміністратора?» confirmation for the
/// administrator displayed as [adminName].
///
/// Resolves to `true` only when the viewer taps the red confirm; every other
/// exit resolves to `null`, meaning *do nothing*.
Future<bool?> showRemoveAdminDialog(BuildContext context, String adminName) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (_) => RemoveAdminDialog(adminName: adminName),
  );
}

/// Opens the «Перемістити адміністратора?» confirmation for moving
/// [adminName] into [destinationSalonName].
///
/// Resolves to `true` only when the viewer taps the camel confirm; every
/// other exit resolves to `null`.
Future<bool?> showMoveAdminDialog(
  BuildContext context, {
  required String adminName,
  required String destinationSalonName,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (_) => MoveAdminDialog(
      adminName: adminName,
      destinationSalonName: destinationSalonName,
    ),
  );
}

/// The destructive remove-admin confirmation.
class RemoveAdminDialog extends StatelessWidget {
  const RemoveAdminDialog({super.key, required this.adminName});

  /// The administrator's display name, woven into the dialog body so the
  /// viewer sees WHO they are about to cut off — never a bare "this user".
  final String adminName;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return _DialogShell(
      dialogKey: const Key('remove-admin-dialog'),
      badge: const _ActionBadge(
        icon: Icons.person_remove_outlined,
        tint: BrandColors.error,
        // The destructive badge takes the error tone — the same line
        // `CancelBookingDialog` and `ClientBookingConflictDialog` draw
        // between a destructive act and a routine one.
        alpha: 0.16,
      ),
      title: l10n.adminSettingsRemoveDialogTitle,
      // Backend Phase 299 turned `DELETE /salons/{salonId}/admins/{userId}`
      // into a HARD DELETE of the admin's user account (it no longer just
      // nulls `salon_id`), and the message below says so plainly.
      message: l10n.adminSettingsRemoveDialogBody(adminName),
      action: DestructiveButton(
        key: const Key('remove-admin-confirm'),
        label: l10n.adminSettingsRemoveConfirmCta,
        icon: Icons.person_remove_outlined,
        onPressed: () => dismissOverlay(context, true),
      ),
      dismissKey: const Key('remove-admin-dismiss'),
      dismissLabel: l10n.actionCancel,
    );
  }
}

/// The destructive remove-master confirmation.
///
/// `DELETE /salons/{salonId}/masters/{masterId}` (backend phase 297)
/// hard-deletes the master's user account, and phase 298 removed the
/// server-side refusal that used to block this when the master still had
/// future bookings — those bookings are now cancelled and the clients
/// notified instead of the call failing. Backend Phase 299 made
/// [RemoveAdminDialog]'s endpoint a hard delete too, so the two calls are no
/// longer different in KIND — but this dialog's body stays the Phase 291
/// bulleted consequence list, not [RemoveAdminDialog]'s three-bullet one:
/// a master carries booking cancellation/notification and a completed-history
/// consequence that an admin, having no calendar or clients, does not.
class RemoveMasterDialog extends StatelessWidget {
  const RemoveMasterDialog({super.key, required this.masterName});

  /// The master's display name, woven into the dialog body so the viewer
  /// sees WHO they are about to permanently remove — never a bare "this
  /// user".
  final String masterName;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return _DialogShell(
      dialogKey: const Key('dialog-remove-master'),
      badge: const _ActionBadge(
        icon: Icons.person_remove_outlined,
        tint: BrandColors.error,
        alpha: 0.16,
      ),
      title: l10n.removeMasterDialogTitle,
      message: l10n.removeMasterDialogBody(masterName),
      action: DestructiveButton(
        key: const Key('btn-confirm-remove-master'),
        label: l10n.removeMasterConfirmCta,
        icon: Icons.person_remove_outlined,
        onPressed: () => dismissOverlay(context, true),
      ),
      dismissKey: const Key('btn-cancel-remove-master'),
      dismissLabel: l10n.actionCancel,
    );
  }
}

/// The rotate-admin confirmation — NOT destructive: moving an administrator
/// between two salons of the same owner is an ordinary reassignment, so the
/// badge and the action are **camel**, never [BrandColors.error]. Same rule
/// `ClientBookingConflictDialog` states for itself.
class MoveAdminDialog extends StatelessWidget {
  const MoveAdminDialog({
    super.key,
    required this.adminName,
    required this.destinationSalonName,
  });

  final String adminName;
  final String destinationSalonName;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return _DialogShell(
      dialogKey: const Key('move-admin-dialog'),
      badge: const _ActionBadge(
        icon: Icons.swap_horiz_rounded,
        tint: BrandColors.accentDeep,
        alpha: 0.14,
      ),
      title: l10n.moveAdminSalonDialogTitle,
      message: l10n.moveAdminSalonDialogBody(adminName, destinationSalonName),
      action: NeumorphicButton(
        key: const Key('move-admin-confirm'),
        label: l10n.moveAdminSalonConfirmCta,
        icon: Icons.swap_horiz_rounded,
        onPressed: () => dismissOverlay(context, true),
      ),
      dismissKey: const Key('move-admin-dismiss'),
      dismissLabel: l10n.actionCancel,
    );
  }
}

/// The chrome both dialogs share — see this library's header for why it is
/// this shape and not the preview's two-button row.
class _DialogShell extends StatelessWidget {
  const _DialogShell({
    required this.dialogKey,
    required this.badge,
    required this.title,
    required this.message,
    required this.action,
    required this.dismissKey,
    required this.dismissLabel,
  });

  final Key dialogKey;
  final Widget badge;
  final String title;
  final String message;
  final Widget action;
  final Key dismissKey;
  final String dismissLabel;

  @override
  Widget build(BuildContext context) {
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
          key: dialogKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Center(child: badge),
                const SizedBox(height: VelvetSpacing.md),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: VelvetText.subheading(),
                ),
                const SizedBox(height: VelvetSpacing.xs),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: VelvetText.bookSuccessSubline,
                ),
                const SizedBox(height: VelvetSpacing.md),
                action,
                const SizedBox(height: VelvetSpacing.xs),
                QuietAction(
                  key: dismissKey,
                  label: dismissLabel,
                  onPressed: () => dismissOverlay(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The badge circle above the title — the preview's own 52 dp tinted disc
/// (`admin_settings_screen.dart:160-168`), which is also the shape
/// `_DestructiveBadge`/`_ConflictBadge` already use at 56 dp. The preview's
/// diameter is kept.
class _ActionBadge extends StatelessWidget {
  const _ActionBadge({
    required this.icon,
    required this.tint,
    required this.alpha,
  });

  final IconData icon;
  final Color tint;
  final double alpha;

  static const double _diameter = 52;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _diameter,
      width: _diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: tint.withValues(alpha: alpha),
      ),
      child: Icon(icon, size: 24, color: tint),
    );
  }
}
