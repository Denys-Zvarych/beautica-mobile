// Phase 431 — «Ліміт перенесень» blocking dialog.
//
// Shown by `booking_confirm_screen.dart` when a provider reschedule returns
// 409 `RESCHEDULE_LIMIT_REACHED` ([RescheduleLimitReachedFailure]). Built on
// the app's shared confirm chrome ([ConfirmDialogShell] + [ConfirmDialogBadge])
// exactly like `regenerate_booking_link_dialog.dart`: camel-family badge at
// 0.14, a [NeumorphicButton] action («Написати в підтримку») and a quiet
// «Зрозуміло» back-out. No new chrome.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/navigation/overlay_navigation.dart';
import 'package:beautica_mobile/core/navigation/single_flight.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/confirm_dialog_shell.dart';

/// Opens the reschedule-limit dialog. Resolves to `true` only on «Написати в
/// підтримку»; every other exit (quiet back-out, barrier, back) is `null`.
Future<bool?> showRescheduleLimitDialog(BuildContext context) {
  return showDialogOnce<bool>(
    context: context,
    barrierDismissible: true,
    builder: (_) => const RescheduleLimitDialog(),
  );
}

class RescheduleLimitDialog extends StatelessWidget {
  const RescheduleLimitDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return ConfirmDialogShell(
      dialogKey: const Key('reschedule-limit-dialog'),
      badge: const ConfirmDialogBadge(
        icon: Icons.event_busy_rounded,
        tint: BrandColors.accentDeep,
        alpha: 0.14,
      ),
      title: l10n.bookingRescheduleLimitTitle,
      message: l10n.bookingErrRescheduleLimitReached,
      // Key on a plain proxy: NeumorphicButton's AnimatedScale root is not
      // hit-tested.
      action: SizedBox(
        key: const Key('reschedule-limit-contact-support'),
        child: NeumorphicButton(
          label: l10n.bookingRescheduleLimitContactSupport,
          icon: Icons.support_agent_rounded,
          onPressed: () => dismissOverlay(context, true),
        ),
      ),
      dismissKey: const Key('reschedule-limit-dismiss'),
      dismissLabel: l10n.bookingRescheduleLimitDismiss,
    );
  }
}
