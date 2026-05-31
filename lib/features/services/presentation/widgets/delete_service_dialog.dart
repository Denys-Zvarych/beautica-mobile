// Phase 5.5 — Delete service confirmation dialog.
//
// Single unconditional "Deactivate?" variant.
//
// TODO: restore blocked variant when backend exposes futureBookingCount in
// MasterServiceResponse. Until then the dialog always shows the deactivation
// prompt — the blocked path cannot be reached because futureBookingCount
// defaults to 0 for all responses.
//
// The dialog follows the VelvetTouch theme: uses [Theme.of(context).colorScheme]
// tokens for the destructive button colour — never a hardcoded hex.
//
// All user-visible strings go through [AppLocalizations]. No raw literals.

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Confirmation dialog for the service deactivation (soft-delete) action.
///
/// Show via [showDialog]:
/// ```dart
/// final confirmed = await showDialog<bool>(
///   context: context,
///   builder: (_) => const DeleteServiceDialog(),
/// );
/// if (confirmed == true) { /* proceed with deactivation */ }
/// ```
///
/// Returns `true` when the master confirmed deactivation, `false` (or `null`
/// when the dialog is dismissed by tapping outside) otherwise.
class DeleteServiceDialog extends StatelessWidget {
  const DeleteServiceDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AlertDialog(
      key: const Key('delete-service-dialog'),
      title: Text(l10n.deleteServiceTitle),
      content: Text(l10n.deleteServiceBody),
      actions: <Widget>[
        TextButton(
          key: const Key('btn-cancel-delete-service'),
          onPressed: () => context.pop(false),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          key: const Key('btn-confirm-delete-service'),
          style: ButtonStyle(
            backgroundColor: WidgetStatePropertyAll(
              Theme.of(context).colorScheme.error,
            ),
          ),
          onPressed: () => context.pop(true),
          child: Text(l10n.actionDelete),
        ),
      ],
    );
  }
}
