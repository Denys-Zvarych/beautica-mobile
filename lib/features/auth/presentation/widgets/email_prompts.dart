// M517 (AUTH-D17, CLI-D09) — the three «Email для сповіщень» prompts, built
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
//   (c) [ProviderEmailPromptCard] — every provider role's home, under the
//       profile / header card: either tap hides it; shown again once 30 days
//       later while there is still no confirmed email, then never.
//
// (b) and (c) show only on an EXPLICIT `emailVerified == false` from
// GET /users/me — an unknown state never prompts. All prompt state is
// device-local ([EmailPromptStore]).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/navigation/single_flight.dart';
import '../../../../core/theme/brand_colors.dart';
import '../../../../core/theme/velvet_geometry.dart';
import '../../../../core/time/clock_provider.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../routing/route_names.dart';
import '../../../../shared/widgets/velvet_banner.dart';
import '../../../master/presentation/widgets/settings_row.dart';
import '../../data/email_prompt_store.dart';
import '../../domain/email_prompt_state.dart';
import '../../domain/user.dart';
import '../../domain/user_role.dart';
import '../auth_selectors.dart';

part 'email_prompts.g.dart';

// ── (a) Profile row ─────────────────────────────────────────────────────────

/// «Email для сповіщень» settings row (AUTH-D17 a).
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
      subtitle: l10n.profileNotificationEmailSubtitle,
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

// ── (c) Provider home card ──────────────────────────────────────────────────

/// Whether the provider home card is due for [userId] now (AUTH-D17 c).
@riverpod
Future<bool> providerEmailCardDue(Ref ref, String userId) async {
  final EmailPromptState state = await ref
      .watch(emailPromptStoreProvider)
      .read(userId);
  return state.providerCardDueAt(ref.read(clockProvider)());
}

/// The provider home / dashboard email card (AUTH-D17 c), with its own
/// leading `lg` gap. Renders NOTHING (zero size) unless it is due, so a host
/// without a prompt lays out exactly as before.
///
/// The due flag comes from an async storage read, so the card arrives a frame
/// or more after the host. It is revealed with an [AnimatedSize] + fade (no
/// gap is ever reserved while it is not due — a zero-size child keeps the
/// host's layout and pixels unchanged), and either tap hides it at once,
/// before the store round trip, the gap then collapsing smoothly. Reduced
/// motion ([MediaQuery.disableAnimationsOf]) snaps both.
class ProviderEmailPromptCard extends ConsumerStatefulWidget {
  const ProviderEmailPromptCard({super.key, this.padding = EdgeInsets.zero});

  /// Extra padding around the card + gap (a sliver host's side gutter).
  final EdgeInsets padding;

  @override
  ConsumerState<ProviderEmailPromptCard> createState() =>
      _ProviderEmailPromptCardState();
}

class _ProviderEmailPromptCardState
    extends ConsumerState<ProviderEmailPromptCard> {
  static const Duration _revealDuration = Duration(milliseconds: 320);

  /// Optimistic local hide: set on tap, cleared once the persisted state has
  /// been re-read (which then reports "not due" by itself).
  bool _hiddenLocally = false;

  Future<void> _hide(String userId) async {
    setState(() => _hiddenLocally = true);
    final EmailPromptStore store = ref.read(emailPromptStoreProvider);
    final EmailPromptState state = await store.read(userId);
    await store.write(
      userId,
      state.withProviderCardHidden(ref.read(clockProvider)()),
    );
    if (!mounted) return;
    ref.invalidate(providerEmailCardDueProvider(userId));
    try {
      await ref.read(providerEmailCardDueProvider(userId).future);
    } on Object {
      // A failed re-read leaves the card hidden for this mount — fail-quiet.
      return;
    }
    if (!mounted) return;
    setState(() => _hiddenLocally = false);
  }

  @override
  Widget build(BuildContext context) {
    final Duration duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : _revealDuration;
    return AnimatedSize(
      duration: duration,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: _content(context, duration),
    );
  }

  Widget _content(BuildContext context, Duration duration) {
    final (String? userId, bool lacksEmail, UserRole? role) = ref.watch(
      currentUserProvider.select(
        (User? u) => (u?.id, u?.lacksConfirmedEmail ?? false, u?.role),
      ),
    );
    if (userId == null ||
        !lacksEmail ||
        role == null ||
        role == UserRole.client) {
      return const SizedBox.shrink();
    }
    final bool due =
        ref.watch(providerEmailCardDueProvider(userId)).value ?? false;
    if (!due || _hiddenLocally) return const SizedBox.shrink();

    final AppLocalizations l10n = AppLocalizations.of(context);
    return Padding(
      padding: widget.padding.add(const EdgeInsets.only(top: VelvetSpacing.lg)),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: duration,
        curve: Curves.easeOutCubic,
        builder: (_, double t, Widget? child) {
          // dim-decorative: a one-shot reveal fade (0 → 1), never a state dim.
          return Opacity(opacity: t, child: child);
        },
        child: VelvetBanner(
          key: const Key('provider-home-email-card'),
          icon: Icons.mark_email_unread_outlined,
          color: BrandColors.accentDeep,
          message: l10n.providerHomeEmailPromptTitle,
          actionLabel: l10n.emailPromptAdd,
          onAction: () {
            unawaited(_hide(userId));
            context.pushOnce(RouteNames.notificationEmail);
          },
          secondaryActionLabel: l10n.emailPromptNotNow,
          onSecondaryAction: () => unawaited(_hide(userId)),
        ),
      ),
    );
  }
}
