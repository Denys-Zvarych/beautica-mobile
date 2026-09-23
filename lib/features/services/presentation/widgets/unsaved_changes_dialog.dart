// Qase defect #26 (case 43 step 2) — unsaved-changes confirmation.
//
// `ServiceForm` has tracked a `_dirtyNotifier` since Phase 5.4 and renders an
// inline caption («Незбережені зміни», `serviceUnsavedChanges`) beside the save
// button while the form is dirty. Nothing consumed that state on the way OUT:
// leaving a dirty form — by the system back gesture or the top-bar back icon —
// discarded the edit silently. The manual case told the tester to expect a
// warning on exit, they saw none, and filed it.
//
// This dialog is the missing half. Its TITLE deliberately reuses
// `serviceUnsavedChanges`, the very string the in-form caption already shows,
// so the indicator on screen and the warning on exit read identically rather
// than as two unrelated messages.
//
// REUSE-FIRST (CLAUDE.md): the AlertDialog shell, the `ModalRoute.of(context)
// ?.navigator?.pop(...)` resolution idiom and the `colorScheme.error` token for
// the destructive action are transcribed from the sibling `DeleteServiceDialog`
// in this same directory — read, not invented, so the two prompts on this
// screen stay visually identical.
//
// All user-visible strings go through [AppLocalizations]. No raw literals.

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Confirmation shown when the master tries to leave a DIRTY [ServiceForm].
///
/// Show via [showDialog]:
/// ```dart
/// final leave = await showDialog<bool>(
///   context: context,
///   builder: (_) => const UnsavedChangesDialog(),
/// );
/// if (leave == true) { /* pop the screen, discarding the edit */ }
/// ```
///
/// Returns `true` only when the master explicitly chose to discard. Dismissing
/// by tapping outside returns `null`, which callers MUST treat as "stay" — the
/// edit is the thing at risk, so anything short of an explicit choice keeps it.
class UnsavedChangesDialog extends StatelessWidget {
  const UnsavedChangesDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AlertDialog(
      key: const Key('unsaved-changes-dialog'),
      // Reuses the in-form dirty caption's string on purpose — see the file
      // header. The tester is told to expect «Незбережені зміни» and that is
      // exactly what both surfaces now say.
      title: Text(l10n.serviceUnsavedChanges),
      content: Text(l10n.serviceUnsavedChangesBody),
      actions: <Widget>[
        TextButton(
          key: const Key('btn-stay-on-form'),
          onPressed: () => ModalRoute.of(context)?.navigator?.pop(false),
          child: Text(l10n.serviceUnsavedChangesStayCta),
        ),
        FilledButton(
          key: const Key('btn-discard-changes'),
          style: ButtonStyle(
            backgroundColor: WidgetStatePropertyAll(
              Theme.of(context).colorScheme.error,
            ),
          ),
          onPressed: () => ModalRoute.of(context)?.navigator?.pop(true),
          child: Text(l10n.serviceUnsavedChangesDiscardCta),
        ),
      ],
    );
  }
}
