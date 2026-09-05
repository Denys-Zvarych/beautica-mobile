// Phase 21.2 — Delete salon confirmation dialog.
// Phase 291 — rewrote the body to state what DELETE /salons/{salonId}
// actually destroys instead of the stale "soft-deactivate" claim below.
//
// Owner-only destructive action from `salon_settings_screen.dart`'s
// «Видалити салон» row. `DELETE /salons/{salonId}` is NOT a reversible
// soft-deactivate: it hard-deletes staff accounts (backend Phase 295),
// cancels future bookings and notifies the affected clients (backend Phase
// 269), and permanently purges the salon's photos from R2 (backend Phase
// 268 D2) — see the mapping at `SalonController.java:210`. A single
// unconditional confirm, mirroring `DeleteServiceDialog`'s exact shape (no
// separate "deactivate" step; that's an implementation detail, not a
// user-facing state — see the phase doc).
//
// All user-visible strings go through [AppLocalizations]. No raw literals.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/l10n/app_localizations.dart';

/// Confirmation dialog for the destructive salon-delete action.
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
  const DeleteSalonDialog({super.key, this.isLastSalon = false});

  /// Whether this is the owner's only remaining salon. When `true`, the
  /// body gains a closing sentence that they will be left with none and
  /// must create a new one (Phase 291 D2). Defaults to `false` so every
  /// caller that does not pass it renders exactly as before.
  final bool isLastSalon;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AlertDialog(
      key: const Key('delete-salon-dialog'),
      title: Text(l10n.deleteSalonTitle),
      content: Text(
        isLastSalon ? l10n.deleteSalonBodyLastSalon : l10n.deleteSalonBody,
      ),
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
