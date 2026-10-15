// Phase 405 (9.10, D5) — the «Видалити фото?» confirmation raised before a
// portfolio photo is deleted (independent master's own portfolio, salon
// portfolio on «Про салон»).
//
// REUSE-FIRST: the chrome is the shared [ConfirmDialogShell] +
// [ConfirmDialogBadge] (promoted in this phase from the admin / master
// removal confirmations) and the action is the app-wide red
// [DestructiveButton] — the same shape as `admin_action_dialogs.dart`.
//
// Backing out is the safe path: a barrier tap, the back gesture and the quiet
// «Скасувати» all resolve to `null`; nothing is deleted unless the viewer taps
// the red confirm.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/navigation/overlay_navigation.dart';
import 'package:beautica_mobile/core/navigation/single_flight.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/confirm_dialog_shell.dart';
import 'package:beautica_mobile/shared/widgets/destructive_action.dart';

/// Opens the delete-portfolio-photo confirmation. Resolves to `true` only
/// when the viewer taps the red confirm; every other exit resolves to `null`.
Future<bool?> showDeletePortfolioPhotoDialog(BuildContext context) {
  return showDialogOnce<bool>(
    context: context,
    barrierDismissible: true,
    builder: (_) => const DeletePortfolioPhotoDialog(),
  );
}

/// The destructive delete-portfolio-photo confirmation.
class DeletePortfolioPhotoDialog extends StatelessWidget {
  const DeletePortfolioPhotoDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return ConfirmDialogShell(
      dialogKey: const Key('portfolio-delete-dialog'),
      badge: const ConfirmDialogBadge(
        icon: Icons.delete_outline_rounded,
        tint: BrandColors.error,
        alpha: 0.16,
      ),
      title: l10n.portfolioDeleteDialogTitle,
      message: l10n.portfolioDeleteDialogBody,
      action: DestructiveButton(
        key: const Key('portfolio-delete-confirm'),
        label: l10n.portfolioDeleteConfirm,
        icon: Icons.delete_outline_rounded,
        onPressed: () => dismissOverlay(context, true),
      ),
      dismissKey: const Key('portfolio-delete-dismiss'),
      dismissLabel: l10n.actionCancel,
    );
  }
}
