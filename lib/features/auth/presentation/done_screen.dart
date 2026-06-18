// Phase 2.12 — Registration Done Screen (VelvetTouch redesign).
//
// SOURCE OF TRUTH:
//   docs/signup-designs/VelvetTouchDesign/lib/screens/registration_done_screen.dart
//
// Design: light-mode neumorphic (VelvetTouch). Warm-taupe base #E6DDD0.
// No glassmorphism, no BackdropFilter, no painter check mark.
// Camel check via Icon(Icons.check_rounded). Chips via NeumorphicInset pills.
// VelvetHeader (logo + wordmark) intentionally omitted — done screen is post-auth.
//
// Security:
//   - Registration draft is reset in a post-frame callback (Phase 2.16 HIGH-1).
//   - ScreenProtector removed — done screen shows no sensitive data post-auth.

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/brand_colors.dart';
import '../../../core/theme/velvet_geometry.dart';
import '../../../core/theme/velvet_text.dart';
import '../../../core/widgets/neumorphic.dart';
import '../../../l10n/app_localizations.dart';
import '../../../routing/role_home.dart';
import '../../../routing/route_names.dart';
import '../domain/user.dart';
import '../domain/user_role.dart';
import '../state/register_draft_notifier.dart';
import 'auth_selectors.dart';
import 'user_role_l10n.dart';
import 'widgets/auth_scaffold.dart';

// ---------------------------------------------------------------------------
// DoneScreen
// ---------------------------------------------------------------------------

/// Terminal "registration complete" screen — Phase 2.12 VelvetTouch redesign.
///
/// Rendered after [VerificationScreen] verifies the OTP. The user is already
/// authenticated; the screen reads first name + role from [currentUserProvider].
/// The registration draft is cleared on mount per Phase 2.16 HIGH-1.
class DoneScreen extends ConsumerStatefulWidget {
  const DoneScreen({super.key});

  @override
  ConsumerState<DoneScreen> createState() => _DoneScreenState();
}

class _DoneScreenState extends ConsumerState<DoneScreen> {
  @override
  void initState() {
    super.initState();
    // Clear registration draft exactly once — after first frame (Phase 2.16 HIGH-1).
    // Placed in initState so it fires once per mount regardless of rebuild count.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(registerDraftProvider.notifier).reset();
      if (kDebugMode) {
        log(
          'Done screen: register draft reset (HIGH-1 contract)',
          name: 'auth.done',
          level: 800,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final user = ref.watch(currentUserProvider);

    final displayName = _resolveDisplayName(user, l10n);
    final roleLabel = user?.role.label(l10n) ?? l10n.registerDoneChipRoleClient;
    final roleIcon = user?.role.icon ?? Icons.person_outline_rounded;

    final descText =
        (user?.role == UserRole.independentMaster ||
            user?.role == UserRole.salonMaster)
        ? l10n.registerDoneDescMaster
        : l10n.registerDoneDesc;

    return AuthScaffold(
      showBack: false,
      bottomBar: NeumorphicButton(
        key: const ValueKey<String>('done_to_app'),
        label: l10n.registerDoneCtaPrimary,
        onPressed: () {
          final role = ref.read(currentUserProvider)?.role;
          final destination = role == null
              ? RouteNames.home
              : roleHomePath(role);
          context.go(destination);
        },
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Top breathing room in place of the logo header.
          const SizedBox(height: VelvetSpacing.xl),

          // Single-tile icon — matches the pattern used by VerificationScreen.
          Center(
            child: Container(
              key: const Key('done-icon-tile'),
              height: 72,
              width: 72,
              decoration: const BoxDecoration(
                color: BrandColors.base,
                borderRadius: BorderRadius.all(
                  Radius.circular(VelvetRadii.logoTile),
                ),
                boxShadow: VelvetShadows.extrudedSmall,
              ),
              child: const Icon(
                Icons.check_rounded,
                color: BrandColors.accent,
                size: 30,
              ),
            ),
          ),
          const SizedBox(height: VelvetSpacing.xl),

          // Personalised headline.
          Text(
            key: const Key('done-greeting'),
            l10n.registerDoneGreeting(displayName),
            style: VelvetText.headingLg,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: VelvetSpacing.sm),

          // Italic accent subtitle.
          Text(
            key: const Key('done-subtitle'),
            l10n.registerDoneSubtitle,
            style: VelvetText.subheadingItalicAccent,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: VelvetSpacing.md),

          // Description body copy — role-aware.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.lg),
            child: Text(
              key: const Key('done-desc'),
              descText,
              style: VelvetText.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: VelvetSpacing.xl),

          // Summary chips — three inset neumorphic pills, each on its own
          // centred line so long labels (e.g. 'Незалежний майстер') never
          // crowd a sibling chip.
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Center(
                child: _SummaryChip(
                  key: const ValueKey<String>('done_chip_role'),
                  icon: roleIcon,
                  label: roleLabel,
                ),
              ),
              const SizedBox(height: VelvetSpacing.sm),
              Center(
                child: _SummaryChip(
                  key: const ValueKey<String>('done_chip_email'),
                  icon: Icons.mark_email_read_outlined,
                  label: l10n.registerDoneChipEmailVerified,
                ),
              ),
              const SizedBox(height: VelvetSpacing.sm),
              Center(
                child: _SummaryChip(
                  key: const ValueKey<String>('done_chip_ready'),
                  icon: Icons.schedule_rounded,
                  label: l10n.registerDoneChipReadyFast,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Display-name resolver
// ---------------------------------------------------------------------------

/// Returns the best available display name for the greeting headline.
///
/// Priority: full name (first + last) → first-only → last-only → l10n fallback.
/// The email address is never used — per the Phase 2.12 fix that removed the
/// `email.split('@').first` fallback.
String _resolveDisplayName(User? user, AppLocalizations l10n) {
  if (user == null) return l10n.registerDoneGreetingFallback;

  final first = user.firstName?.trim() ?? '';
  final last = user.lastName?.trim() ?? '';

  if (first.isNotEmpty && last.isNotEmpty) return '$first $last';
  if (first.isNotEmpty) return first;
  if (last.isNotEmpty) return last;
  return l10n.registerDoneGreetingFallback;
}

// ---------------------------------------------------------------------------
// _SummaryChip — small NeumorphicInset pill (icon + label)
// ---------------------------------------------------------------------------

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return NeumorphicInset(
      radius: VelvetRadii.field,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: VelvetSpacing.md,
          vertical: VelvetSpacing.sm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 15, color: BrandColors.accent),
            const SizedBox(width: VelvetSpacing.sm),
            Flexible(
              child: Text(
                label,
                style: VelvetText.chipLabel,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
