// Phase 21.2 — Delete salon confirmation dialog.
//
// Owner-only destructive action from `salon_settings_screen.dart`'s
// «Видалити салон» row. `DELETE /salons/{salonId}` is a soft-deactivate under
// the hood (`SalonController.java:104`) — a single unconditional confirm,
// mirroring `DeleteServiceDialog`'s exact shape (no separate "deactivate"
// step; that's an implementation detail, not a user-facing state — see the
// phase doc).
//
// All user-visible strings go through [AppLocalizations]. No raw literals.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/l10n/app_localizations.dart';

/// Confirmation dialog for the salon deactivation (soft-delete) action.
///
/// Show via [showDialog]:
/// ```dart
/// final confirmed = await showDialog<bool>(
///   context: context,
///   builder: (_) => const DeleteSalonDialog(),
/// );
/// if (confirmed == true) { /* proceed with deletion */ }
/// ```
///
/// Returns `true` when the owner confirmed deletion, `false` (or `null` when
/// the dialog is dismissed by tapping outside) otherwise.
class DeleteSalonDialog extends StatelessWidget {
  const DeleteSalonDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AlertDialog(
      key: const Key('delete-salon-dialog'),
      title: Text(l10n.deleteSalonTitle),
      content: Text(l10n.deleteSalonBody),
      actions: <Widget>[
        TextButton(
          key: const Key('btn-cancel-delete-salon'),
          onPressed: () => ModalRoute.of(context)?.navigator?.pop(false),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          key: const Key('btn-confirm-delete-salon'),
          style: ButtonStyle(
            backgroundColor: WidgetStatePropertyAll(
              Theme.of(context).colorScheme.error,
            ),
          ),
          onPressed: () => ModalRoute.of(context)?.navigator?.pop(true),
          child: Text(l10n.actionDelete),
        ),
      ],
    );
  }
}
