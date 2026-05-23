// Phase 2.16 — Role selection screen (wizard entry gate). VelvetTouch redesign.
//
// The user picks one of three roles (Client / Salon Owner / Independent Master);
// the choice is written into `registerDraftProvider` via [start] and the wizard
// advances to `/register` (Step 1 — credentials).
//
// This screen is OUTSIDE the wizard ShellRoute — it has its own VelvetHeader +
// headline + login link, and does NOT show the two-dot step progress (the dots
// only appear once the user is inside the wizard).

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:screen_protector/screen_protector.dart';

import '../../../core/theme/velvet_geometry.dart';
import '../../../core/theme/velvet_text.dart';
import '../../../core/widgets/neumorphic.dart';
import '../../../l10n/app_localizations.dart';
import '../../../routing/route_names.dart';
import '../domain/user_role.dart';
import '../state/register_draft_notifier.dart';
import 'user_role_l10n.dart';
import 'widgets/auth_scaffold.dart';

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class RoleSelectionScreen extends ConsumerStatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  ConsumerState<RoleSelectionScreen> createState() =>
      _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends ConsumerState<RoleSelectionScreen> {
  UserRole? _selectedRole;

  @override
  void initState() {
    super.initState();
    if (!kDebugMode) {
      ScreenProtector.preventScreenshotOn();
    }
    // Preselect the role from the draft when the user returns here via the
    // Step 1 "← Назад" link (the draft survives a single-step back). On a
    // fresh entry the draft is null, so _selectedRole stays null and Continue
    // stays disabled until the user picks.
    _selectedRole = ref.read(registerDraftProvider)?.role;
  }

  @override
  void dispose() {
    if (!kDebugMode) {
      ScreenProtector.preventScreenshotOff();
    }
    super.dispose();
  }

  void _continue() {
    final role = _selectedRole;
    if (role == null) return;
    ref.read(registerDraftProvider.notifier).start(role);
    context.go(RouteNames.register);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AuthScaffold(
      showBack: false,
      bottomBar: NeumorphicButton(
        key: const ValueKey<String>('role_continue'),
        label: l10n.registerContinue,
        onPressed: _selectedRole != null ? _continue : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const VelvetHeader(),
          Text(
            l10n.roleSelectHeadline,
            style: VelvetText.heading(),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: VelvetSpacing.sm),
          Text(l10n.registerSubText, style: VelvetText.body()),
          const SizedBox(height: VelvetSpacing.md),
          NeumorphicTile(
            key: const ValueKey<String>('role_client'),
            icon: Icons.spa_rounded,
            title: UserRole.client.label(l10n),
            subtitle: l10n.intentClientDesc,
            selected: _selectedRole == UserRole.client,
            onTap: () => setState(() => _selectedRole = UserRole.client),
          ),
          const SizedBox(height: VelvetSpacing.sm),
          NeumorphicTile(
            key: const ValueKey<String>('role_salon_owner'),
            icon: Icons.storefront_rounded,
            title: UserRole.salonOwner.label(l10n),
            subtitle: l10n.intentSalonDesc,
            selected: _selectedRole == UserRole.salonOwner,
            onTap: () => setState(() => _selectedRole = UserRole.salonOwner),
          ),
          const SizedBox(height: VelvetSpacing.sm),
          NeumorphicTile(
            key: const ValueKey<String>('role_master'),
            icon: Icons.auto_awesome_rounded,
            title: UserRole.independentMaster.label(l10n),
            subtitle: l10n.intentIndependentDesc,
            selected: _selectedRole == UserRole.independentMaster,
            onTap: () =>
                setState(() => _selectedRole = UserRole.independentMaster),
          ),
          const SizedBox(height: VelvetSpacing.md),
          // "Вже є акаунт? Увійти" login link.
          Center(
            child: GestureDetector(
              key: const ValueKey<String>('role_login_link'),
              onTap: () {
                // Security — clear any in-flight draft (e.g. the user came here
                // from Step 1 via the back link). The wizard hasn't filled
                // credentials yet on this screen, but the role choice itself is
                // part of the draft and must not survive a "let me log in
                // instead" detour.
                ref.read(registerDraftProvider.notifier).reset();
                context.go(RouteNames.login);
              },
              child: Padding(
                padding: const EdgeInsets.all(VelvetSpacing.xs),
                child: Text.rich(
                  TextSpan(
                    children: <TextSpan>[
                      TextSpan(
                        text: l10n.registerHaveAccount,
                        style: VelvetText.body(),
                      ),
                      const TextSpan(text: ' '),
                      TextSpan(
                        text: l10n.registerSignIn,
                        style: VelvetText.link(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
