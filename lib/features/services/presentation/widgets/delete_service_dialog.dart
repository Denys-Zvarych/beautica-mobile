// Phase 5.5 — Delete service confirmation dialog.
// Phase 319 — grows the blocked variant this dialog was written for.
//
// Two variants, one widget (D1):
//   - `blocked: false` (default) — today's unconditional "Deactivate?" prompt,
//     byte-for-byte unchanged: title/body/cancel+destructive-confirm.
//   - `blocked: true` — the refusal surface for a `409
//     ServiceUnassignBlockedFailure` (a master still has a future CONFIRMED
//     booking for the service). Same AlertDialog shell, same VelvetTouch
//     colorScheme tokens, ONE dismiss action — no destructive button, because
//     there is nothing to confirm.
//
// HISTORY: the blocked variant was originally written PRE-EMPTIVE — know the
// count up front (`MasterServiceResponse.futureBookingCount`), disable the
// action before the user ever taps. That DTO field never shipped, so the path
// was suppressed and this file carried a TODO waiting for it. Backend phase
// 307 shipped a different shape instead: REACTIVE — attempt the unassign, and
// the server refuses with a plain-English 409 if a future booking exists. No
// structured count comes back (phase 316 D3: parsing the count out of the
// Java message would couple Ukrainian copy to a Java string literal). So the
// blocked variant is reachable now, through a different door than the TODO
// imagined — the widget, title and interaction are reused unchanged; only the
// trigger (caller-side, see `service_edit_screen.dart`) and the body string
// (count-less, `deleteServiceBlockedBodyNoCount`) differ.
//
// `deleteServiceBlockedBody(count)` — the ORIGINAL plural body — is
// deliberately RETAINED in both ARB files and rendered by NEITHER variant. It
// is not dead copy: if the backend later returns a structured count, this
// dialog can switch to it without touching the ARB. See phase 319 D2.
//
// The dialog follows the VelvetTouch theme: uses [Theme.of(context).colorScheme]
// tokens for the destructive button colour — never a hardcoded hex.
//
// All user-visible strings go through [AppLocalizations]. No raw literals.

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Confirmation dialog for the service deactivation (soft-delete) action, and
/// the refusal surface for the reactive 409 that supersedes it (phase 319).
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
/// With [blocked] true, re-show it as the refusal (no confirmation is being
/// asked, so its resolved value is never `true`):
/// ```dart
/// await showDialog<bool>(
///   context: context,
///   builder: (_) => const DeleteServiceDialog(blocked: true),
/// );
/// ```
///
/// Returns `true` when the master confirmed deactivation, `false` (or `null`
/// when the dialog is dismissed by tapping outside) otherwise. The blocked
/// variant never returns `true` — there is nothing to confirm.
class DeleteServiceDialog extends StatelessWidget {
  const DeleteServiceDialog({super.key, this.blocked = false});

  /// When `true`, renders the refusal surface for a `409
  /// ServiceUnassignBlockedFailure` instead of the deactivation prompt.
  /// Defaults to `false` so every existing caller is unaffected (D1).
  final bool blocked;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AlertDialog(
      key: const Key('delete-service-dialog'),
      title: Text(
        blocked ? l10n.deleteServiceBlockedTitle : l10n.deleteServiceTitle,
      ),
      content: Text(
        blocked ? l10n.deleteServiceBlockedBodyNoCount : l10n.deleteServiceBody,
      ),
      actions: <Widget>[
        TextButton(
          key: const Key('btn-cancel-delete-service'),
          onPressed: () => ModalRoute.of(context)?.navigator?.pop(false),
          child: Text(l10n.actionCancel),
        ),
        // The destructive confirm action only exists for the unblocked
        // variant — the blocked refusal has nothing left to confirm (D1).
        if (!blocked)
          FilledButton(
            key: const Key('btn-confirm-delete-service'),
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
