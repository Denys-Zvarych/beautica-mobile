// The app's centred confirmation-dialog chrome: badge disc → title → message
// → one action → a quiet back-out, on a single NeumorphicCard.
//
// PROMOTED (REUSE-FIRST, phase 405 / 9.10) out of
// `features/salon/presentation/widgets/admin_action_dialogs.dart`, where it
// was the private `_DialogShell` + `_ActionBadge` behind the remove-admin /
// remove-master / move-admin confirmations. The portfolio «Видалити фото?»
// confirmation (`portfolio_dialogs.dart`) needs the identical chrome, and a
// second copy is exactly the fork the reuse rule forbids. The code below is
// the ORIGINAL, moved verbatim (only the `_` dropped): the three admin
// dialogs render byte-identically — pinned by
// `test/golden/admin_action_dialogs_golden_test.dart`, seeded BEFORE the move.
//
// See that library's header for why the action layout is stacked (action +
// centred quiet back-out) rather than a side-by-side pair.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/navigation/overlay_navigation.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/shared/widgets/destructive_action.dart';

/// The confirmation chrome. Every exit other than [action] — the quiet
/// back-out, a barrier tap, the back gesture — resolves the dialog to `null`.
class ConfirmDialogShell extends StatelessWidget {
  const ConfirmDialogShell({
    super.key,
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

/// The 52 dp tinted badge disc above a [ConfirmDialogShell] title. A
/// destructive act passes [BrandColors.error] at 0.16; a routine one the camel
/// family at 0.14.
class ConfirmDialogBadge extends StatelessWidget {
  const ConfirmDialogBadge({
    super.key,
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
