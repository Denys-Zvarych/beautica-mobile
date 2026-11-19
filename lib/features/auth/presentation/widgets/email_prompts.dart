// M517 (AUTH-D17, CLI-D09) — the «Email для сповіщень» prompts, built
// ONLY from existing widgets (no new visual element): the shared
// [SettingsRow] and [VelvetBanner] (with its additive M515 «Не зараз»
// action). Ported from docs/signup-designs/PhoneFirstAuth/lib/screens/
// email_prompt_screens.dart + master_home_screen.dart (approved 2026-11-18).
//
//   (a) [NotificationEmailSettingsRow] — every role's settings hub: «Додати»
//       until an email is confirmed, then the address (ellipsized); tap =
//       add / change. Always visible.
//   (b) [ClientEmailPromptCard] + [claimClientEmailPrompt] — the CLIENT
//       booking-success card, shown once ever (claimed on first show).
//
// The provider home card (former (c)) was removed 2026-11-19 (user decision:
// redundant with (a)).
//
// (b) shows only on an EXPLICIT `emailVerified == false` from GET /users/me —
// an unknown state never prompts. All prompt state is device-local
// ([EmailPromptStore]).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/navigation/single_flight.dart';
import '../../../../core/theme/brand_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../routing/route_names.dart';
import '../../../../shared/widgets/velvet_banner.dart';
import '../../../master/presentation/widgets/settings_row.dart';
import '../../data/email_prompt_store.dart';
import '../../domain/email_prompt_state.dart';
import '../../domain/user.dart';
import '../../domain/user_role.dart';
import '../auth_selectors.dart';

// ── (a) Profile row ─────────────────────────────────────────────────────────

/// «Email для сповіщень» settings row (AUTH-D17 a) — the shared
/// [SettingsRow], no subtitle, so it has the same height, padding, trailing
/// alignment and chevron as its neighbours (manual-test fix 2026-11-19).
class NotificationEmailSettingsRow extends ConsumerWidget {
  const NotificationEmailSettingsRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? email = ref.watch(
      currentUserProvider.select((User? u) => u?.confirmedEmail),
    );
    return SettingsRow(
      key: const Key('row-notification-email'),
      icon: Icons.alternate_email_rounded,
      label: l10n.profileNotificationEmailTitle,
      value: email ?? l10n.emailPromptAdd,
      ellipsizeValue: true,
      onTap: () => context.pushOnce(RouteNames.notificationEmail),
    );
  }
}

// ── (b) Client booking-success card ─────────────────────────────────────────

/// Decides — once, at the success screen's first build — whether the CLIENT
/// booking-success card shows, and records it as shown when it does (AUTH-D17
/// b: "shown once", the flag set on first show). `false` for any non-client,
/// a confirmed / unknown email, or a card already shown on this device.
Future<bool> claimClientEmailPrompt(WidgetRef ref) async {
  final User? user = ref.read(currentUserProvider);
  if (user == null ||
      user.role != UserRole.client ||
      !user.lacksConfirmedEmail) {
    return false;
  }
  final EmailPromptStore store = ref.read(emailPromptStoreProvider);
  final EmailPromptState state = await store.read(user.id);
  if (!state.clientCardDue) return false;
  await store.write(user.id, state.withClientCardShown());
  return true;
}

/// The CLIENT booking-success card (AUTH-D17 b). The host removes it on
/// [onDismiss]; «Додати» also opens the email entry.
class ClientEmailPromptCard extends StatelessWidget {
  const ClientEmailPromptCard({super.key, required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return VelvetBanner(
      key: const Key('booking-success-email-card'),
      icon: Icons.mark_email_unread_outlined,
      color: BrandColors.accentDeep,
      message: l10n.bookingSuccessEmailPromptTitle,
      actionLabel: l10n.emailPromptAdd,
      onAction: () {
        onDismiss();
        context.pushOnce(RouteNames.notificationEmail);
      },
      secondaryActionLabel: l10n.emailPromptNotNow,
      onSecondaryAction: onDismiss,
    );
  }
}
