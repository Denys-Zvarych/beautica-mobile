// Phase 425 D4 — block / unblock client confirmations (provider → client
// only; clients never block).
//
// Ported 1:1 from the approved preview
// `docs/signup-designs/UgcSafety/lib/widgets/moderation_widgets.dart`
// (`showBlockConfirmDialog` / `showUnblockConfirmDialog`), copy verbatim, on
// the shared recipe every confirmation in the app uses: `ConfirmDialogShell`
// + `ConfirmDialogBadge` + `DestructiveButton` / `NeumorphicButton`, opened
// through `showDialogOnce` and closed through `dismissOverlay`. Backing out
// (barrier, back gesture, the quiet back-out) resolves `false`.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/navigation/overlay_navigation.dart';
import 'package:beautica_mobile/core/navigation/single_flight.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/confirm_dialog_shell.dart';
import 'package:beautica_mobile/shared/widgets/destructive_action.dart';

/// «Заблокувати {name}?» — `true` only on the red confirm.
Future<bool> showBlockClientDialog(BuildContext context, String name) async {
  final bool? ok = await showDialogOnce<bool>(
    context: context,
    barrierDismissible: true,
    builder: (_) => BlockClientDialog(name: name),
  );
  return ok ?? false;
}

/// «Розблокувати {name}?» — `true` only on the confirm.
Future<bool> showUnblockClientDialog(BuildContext context, String name) async {
  final bool? ok = await showDialogOnce<bool>(
    context: context,
    barrierDismissible: true,
    builder: (_) => UnblockClientDialog(name: name),
  );
  return ok ?? false;
}

/// The destructive block confirmation.
class BlockClientDialog extends StatelessWidget {
  const BlockClientDialog({super.key, required this.name});

  final String name;

  static const Key confirmKey = Key('block-client-confirm');
  static const Key dismissKey = Key('block-client-dismiss');

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return ConfirmDialogShell(
      dialogKey: const Key('block-client-dialog'),
      badge: const ConfirmDialogBadge(
        icon: Icons.block_rounded,
        tint: BrandColors.error,
        alpha: 0.16,
      ),
      title: l10n.blockDialogTitle(name),
      message: l10n.blockDialogBody,
      action: DestructiveButton(
        key: confirmKey,
        label: l10n.blockDialogConfirm,
        icon: Icons.block_rounded,
        onPressed: () => dismissOverlay(context, true),
      ),
      dismissKey: dismissKey,
      dismissLabel: l10n.blockDialogDismiss,
    );
  }
}

/// The unblock confirmation (camel, not destructive).
class UnblockClientDialog extends StatelessWidget {
  const UnblockClientDialog({super.key, required this.name});

  final String name;

  static const Key confirmKey = Key('unblock-client-confirm');
  static const Key dismissKey = Key('unblock-client-dismiss');

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return ConfirmDialogShell(
      dialogKey: const Key('unblock-client-dialog'),
      badge: const ConfirmDialogBadge(
        icon: Icons.lock_open_rounded,
        tint: BrandColors.accentDeep,
        alpha: 0.14,
      ),
      title: l10n.unblockDialogTitle(name),
      message: l10n.unblockDialogBody,
      action: NeumorphicButton(
        key: confirmKey,
        label: l10n.unblockDialogConfirm,
        icon: Icons.lock_open_rounded,
        onPressed: () => dismissOverlay(context, true),
      ),
      dismissKey: dismissKey,
      dismissLabel: l10n.unblockDialogDismiss,
    );
  }
}
