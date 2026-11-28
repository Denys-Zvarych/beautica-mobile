// M572 (CLI-102, REV-45) — the «Видалити оцінку й коментар?» confirmation on
// «Рейтинг клієнта»: the viewer's own rating goes WITH its comment, and the
// body says so. Composed on the shared [ConfirmDialogShell]; destructive tone
// like every other delete confirm.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/navigation/overlay_navigation.dart';
import 'package:beautica_mobile/core/navigation/single_flight.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/confirm_dialog_shell.dart';
import 'package:beautica_mobile/shared/widgets/destructive_action.dart';

/// Opens the confirm. Resolves `true` only on the red confirm; every other
/// exit (cancel, barrier, back gesture) resolves to `null` — do nothing.
Future<bool?> showDeleteClientRatingDialog(BuildContext context) =>
    showDialogOnce<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const DeleteClientRatingDialog(),
    );

class DeleteClientRatingDialog extends StatelessWidget {
  const DeleteClientRatingDialog({super.key});

  static const Key dialogKey = Key('delete-client-rating-dialog');
  static const Key confirmKey = Key('delete-client-rating-confirm');
  static const Key cancelKey = Key('delete-client-rating-cancel');

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return ConfirmDialogShell(
      dialogKey: dialogKey,
      badge: const ConfirmDialogBadge(
        icon: Icons.delete_outline_rounded,
        tint: BrandColors.error,
        alpha: 0.16,
      ),
      title: l10n.clientRatingDeleteTitle,
      message: l10n.clientRatingDeleteBody,
      action: DestructiveButton(
        key: confirmKey,
        label: l10n.clientRatingDeleteConfirm,
        icon: Icons.delete_outline_rounded,
        onPressed: () => dismissOverlay(context, true),
      ),
      dismissKey: cancelKey,
      dismissLabel: l10n.clientRatingDeleteCancel,
    );
  }
}
